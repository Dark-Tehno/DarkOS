-- netproto.lua — простой протокол "OCNet" поверх modem/network card.
-- Позволяет одному компьютеру объявить себя "сайтом" по имени, а другим —
-- находить его по имени (без знания адреса) и запрашивать у него "страницы".
--
-- Формат страницы: { title = "строка", body = "текст (можно с \n)",
--                     links = { {label="Открыть магазин", path="/shop"}, ... } }

local component = require("component")
local event = require("event")
local computer = require("computer")
local filesystem = require("filesystem")
local serialization = require("serialization")

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

--------------------------------------------------------------------------
-- Вспомогательные функции для работы с файлами (нужны для передачи файлов
-- и автообновления по сети)
--------------------------------------------------------------------------
function netproto.readFile(path)
  local f = io.open(path, "r")
  if not f then return nil, "нет файла: " .. tostring(path) end
  local content = f:read("*a") or ""
  f:close()
  return content
end

-- Простая контрольная сумма (алгоритм вроде Adler-32) — не для криптографии,
-- а только чтобы быстро понять, отличается ли файл от версии на другом
-- компьютере, без пересылки содержимого целиком.
function netproto.checksum(data)
  local a, b = 1, 0
  for i = 1, #data do
    a = (a + data:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return b * 65536 + a
end

-- Рекурсивный обход папки, возвращает список {path=относительный, full=абсолютный}
local function walk(dir, base, out)
  base = base or dir
  out = out or {}
  if not filesystem.exists(dir) then return out end
  for name in filesystem.list(dir) do
    local isDir = name:sub(-1) == "/"
    local clean = isDir and name:sub(1, -2) or name
    local full = filesystem.concat(dir, clean)
    if isDir then
      walk(full, base, out)
    else
      local rel = full:sub(#base + 1):gsub("^/+", "")
      table.insert(out, { path = rel, full = full })
    end
  end
  return out
end

function netproto.buildManifest(rootDir)
  local manifest = {}
  for _, f in ipairs(walk(rootDir)) do
    local content = netproto.readFile(f.full) or ""
    table.insert(manifest, { path = f.path, size = #content, checksum = netproto.checksum(content) })
  end
  return manifest
end

--------------------------------------------------------------------------
-- Сервер обновлений: раздаёт файлы из rootDir другим компьютерам по сети.
-- ВАЖНО: раздаётся только содержимое rootDir (по умолчанию "/os"), выйти
-- за его пределы через путь вида "../../" нельзя — такие сегменты вырезаются.
--------------------------------------------------------------------------
local CHUNK_SIZE = 4000

function netproto.makeUpdateServer(rootDir, serverName, onLog)
  local m = modem()
  local log = onLog or function() end
  local function safeFull(rel)
    rel = tostring(rel):gsub("%.%.", "")
    return filesystem.concat(rootDir, rel)
  end
  return function(_, _, from, port, _, cmd, a1, a2)
    if port ~= netproto.PORT then return end
    if cmd == "OCNET_DISCOVER" and a1 == serverName then
      m.send(from, netproto.PORT, "OCNET_FOUND", serverName)
    elseif cmd == "OCNET_MANIFEST_REQ" then
      local manifest = netproto.buildManifest(rootDir)
      m.send(from, netproto.PORT, "OCNET_MANIFEST", serialization.serialize(manifest))
      log("Манифест (" .. #manifest .. " файлов) отправлен -> " .. tostring(from))
    elseif cmd == "OCNET_FILE_INFO" then
      local full = safeFull(a1)
      if not filesystem.exists(full) or filesystem.isDirectory(full) then
        m.send(from, netproto.PORT, "OCNET_FILE_ERR", a1, "файл не найден на сервере")
      else
        local content = netproto.readFile(full) or ""
        local count = math.max(1, math.ceil(#content / CHUNK_SIZE))
        m.send(from, netproto.PORT, "OCNET_FILE_META", a1, #content, count)
      end
    elseif cmd == "OCNET_FILE_CHUNK_REQ" then
      local full = safeFull(a1)
      local idx = a2 or 0
      local content = netproto.readFile(full) or ""
      local from_i = idx * CHUNK_SIZE + 1
      local to_i = math.min(#content, from_i + CHUNK_SIZE - 1)
      m.send(from, netproto.PORT, "OCNET_FILE_CHUNK", a1, idx, content:sub(from_i, to_i))
      log("Отдана часть " .. idx .. " файла " .. a1 .. " -> " .. tostring(from))
    end
  end
end

-- Клиент: запросить манифест (список файлов+размеров+чек-сумм) у сервера обновлений.
function netproto.requestManifest(target, timeout)
  local m = modem()
  if not m then return nil, "Нет сетевой карты" end
  local address = target
  if not (type(target) == "string" and target:match(UUID_PATTERN)) then
    local addr, err = netproto.discover(target, timeout)
    if not addr then return nil, err end
    address = addr
  end
  netproto.open()
  m.send(address, netproto.PORT, "OCNET_MANIFEST_REQ")
  local deadline = computer.uptime() + (timeout or 4)
  while computer.uptime() < deadline do
    local left = deadline - computer.uptime()
    local e, _, from, port, _, cmd, data = event.pull(left, "modem_message")
    if e and from == address and port == netproto.PORT and cmd == "OCNET_MANIFEST" then
      local ok, manifest = pcall(serialization.unserialize, data)
      if ok and manifest then return manifest, address end
      return nil, "Повреждённый манифест от сервера"
    end
  end
  return nil, "Сервер обновлений не ответил"
end

-- Клиент: скачать один файл по относительному пути (по частям).
-- onProgress(получено_частей, всего_частей), необязательный.
function netproto.fetchFile(address, relPath, timeout, onProgress)
  local m = modem()
  if not m then return nil, "Нет сетевой карты" end
  netproto.open()
  m.send(address, netproto.PORT, "OCNET_FILE_INFO", relPath)
  local count
  local deadline = computer.uptime() + (timeout or 4)
  while computer.uptime() < deadline do
    local left = deadline - computer.uptime()
    local e, _, from, port, _, cmd, p1, p2 = event.pull(left, "modem_message")
    if e and from == address and port == netproto.PORT then
      if cmd == "OCNET_FILE_META" and p1 == relPath then count = p2; break end
      if cmd == "OCNET_FILE_ERR" and p1 == relPath then return nil, p2 end
    end
  end
  if not count then return nil, "Нет ответа от сервера обновлений" end
  local chunks = {}
  for i = 0, count - 1 do
    m.send(address, netproto.PORT, "OCNET_FILE_CHUNK_REQ", relPath, i)
    local got = false
    local d2 = computer.uptime() + (timeout or 4)
    while computer.uptime() < d2 do
      local left2 = d2 - computer.uptime()
      local e2, _, from2, port2, _, cmd2, rp2, idx2, data2 =
        event.pull(left2, "modem_message")
      if e2 and from2 == address and port2 == netproto.PORT and cmd2 == "OCNET_FILE_CHUNK"
         and rp2 == relPath and idx2 == i then
        chunks[i + 1] = data2 or ""
        got = true
        break
      end
    end
    if not got then return nil, "Обрыв связи на части " .. i .. " файла " .. relPath end
    if onProgress then onProgress(i + 1, count) end
  end
  return table.concat(chunks)
end

--------------------------------------------------------------------------
-- "Сетевое окружение" — обнаружение включённых компьютеров в сети.
-- Компьютер становится видимым только пока активен presence-обработчик
-- (то есть пока пользователь сам включил это в приложении "Сеть").
--------------------------------------------------------------------------
-- nameFn()  — функция, возвращающая текущее имя компьютера (может меняться)
-- extraFn() — необязательная функция, возвращающая доп. инфо (например имя сайта)
function netproto.makePresenceResponder(nameFn, extraFn)
  local m = modem()
  return function(_, _, from, port, _, cmd)
    if port ~= netproto.PORT then return end
    if cmd == "OCNET_PING" then
      local extra = extraFn and extraFn() or nil
      m.send(from, netproto.PORT, "OCNET_PONG", nameFn and nameFn() or "?", extra)
    end
  end
end

-- Разослать пинг всем и собрать ответы за timeout секунд.
-- Возвращает список { {address=, name=, extra=}, ... }
function netproto.scanNetwork(timeout)
  local m = modem()
  if not m then return {}, "Нет сетевой карты" end
  netproto.open()
  m.broadcast(netproto.PORT, "OCNET_PING")
  local results, seen = {}, {}
  local deadline = computer.uptime() + (timeout or 1.5)
  while computer.uptime() < deadline do
    local left = deadline - computer.uptime()
    local e, _, from, port, _, cmd, name, extra = event.pull(left, "modem_message")
    if e and port == netproto.PORT and cmd == "OCNET_PONG" and not seen[from] then
      seen[from] = true
      table.insert(results, { address = from, name = name, extra = extra })
    end
  end
  return results
end

return netproto
