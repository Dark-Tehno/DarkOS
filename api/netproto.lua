-- netproto.lua — простой протокол "OCNet" поверх modem/network card.
-- Позволяет одному компьютеру объявить себя "сайтом" по имени, а другим —
-- находить его по имени (без знания адреса) и запрашивать у него "страницы".
--
-- Формат страницы: { title = "строка", body = "текст (можно с \n)",
--                     links = { {label="Открыть магазин", path="/shop"}, ... } }

local component = require("component")
local event = require("event")
local computer = require("computer")

local netproto = {}
netproto.PORT = 4590 -- при желании можно сменить порт в этом файле на всех машинах сети

local function modem()
  if not component.isAvailable("modem") then return nil end
  return component.modem
end
netproto.modem = modem

function netproto.available()
  return modem() ~= nil
end

function netproto.open()
  local m = modem()
  if not m then return false, "Нет сетевой карты (modem / network card) на этом компьютере" end
  if not m.isOpen(netproto.PORT) then m.open(netproto.PORT) end
  return true
end

-- Найти адрес сайта по его имени. timeout в секундах.
function netproto.discover(name, timeout)
  local m = modem()
  if not m then return nil, "Нет сетевой карты" end
  local ok, err = netproto.open()
  if not ok then return nil, err end
  m.broadcast(netproto.PORT, "OCNET_DISCOVER", name)
  local deadline = computer.uptime() + (timeout or 2)
  while computer.uptime() < deadline do
    local left = deadline - computer.uptime()
    local e, _, from, port, _, cmd, respName = event.pull(left, "modem_message")
    if e and port == netproto.PORT and cmd == "OCNET_FOUND" and respName == name then
      return from
    end
  end
  return nil, "Сайт с именем '" .. tostring(name) .. "' не найден"
end

local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

-- Запросить страницу по адресу (или по имени, если это не похоже на адрес компонента).
function netproto.get(target, path, timeout)
  local m = modem()
  if not m then return nil, "Нет сетевой карты" end
  local address = target
  if not (type(target) == "string" and target:match(UUID_PATTERN)) then
    local addr, err = netproto.discover(target, timeout)
    if not addr then return nil, err end
    address = addr
  end
  local ok, err = netproto.open()
  if not ok then return nil, err end
  m.send(address, netproto.PORT, "OCNET_GET", path or "/")
  local deadline = computer.uptime() + (timeout or 3)
  while computer.uptime() < deadline do
    local left = deadline - computer.uptime()
    local e, _, from, port, _, cmd, title, body, links = event.pull(left, "modem_message")
    if e and from == address and port == netproto.PORT and cmd == "OCNET_PAGE" then
      return { title = title, body = body, links = links or {}, address = address }
    end
  end
  return nil, "Нет ответа от " .. tostring(address)
end

-- Запустить обработчик "сайта": siteName — имя, по которому вас будут находить,
-- pages — таблица path -> {title=,body=,links=}. Возвращает функцию-обработчик,
-- которую нужно передать в event.listen("modem_message", handler) и сохранить,
-- чтобы потом можно было event.ignore.
function netproto.makeHost(siteName, pages, onLog)
  local m = modem()
  local log = onLog or function() end
  return function(_, _, from, port, _, cmd, a1)
    if port ~= netproto.PORT then return end
    if cmd == "OCNET_DISCOVER" and a1 == siteName then
      m.send(from, netproto.PORT, "OCNET_FOUND", siteName)
      log("Отклик на поиск от " .. tostring(from))
    elseif cmd == "OCNET_GET" then
      local page = pages[a1] or pages["/404"] or { title = "404", body = "Страница не найдена: " .. tostring(a1), links = {} }
      m.send(from, netproto.PORT, "OCNET_PAGE", page.title, page.body, page.links)
      log("Запрос страницы " .. tostring(a1) .. " от " .. tostring(from))
    end
  end
end

return netproto
