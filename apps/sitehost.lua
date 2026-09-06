-- sitehost.lua — превращает этот компьютер в "сайт", который другие пользователи
-- смогут найти по имени через приложение "Обозреватель" и открыть ваши страницы.
--
-- Страницы задаются в файле /os/sitedata/site.lua (создаётся автоматически
-- при первом запуске с примером). Формат — см. комментарий в этом файле после
-- первого запуска, либо секцию README.md "Как сделать свой сайт".

local filesystem = require("filesystem")
local event = require("event")

local CONFIG_PATH = "/os/sitedata/site.lua"

local DEFAULT_CONFIG = [==[
-- Настройка вашего сайта в сети OCNet.
-- name  — имя, по которому вас будут искать в "Обозревателе".
-- pages — таблица "путь" -> {title=, body=, links={ {label=,path=}, ... }}
return {
  name = "мой-сайт",
  pages = {
    ["/"] = {
      title = "Добро пожаловать",
      body = "Это моя страница в локальной сети сервера.\nОтредактируйте /os/sitedata/site.lua, чтобы изменить содержимое.",
      links = { { label = "О компьютере", path = "/about" } },
    },
    ["/about"] = {
      title = "О компьютере",
      body = "Здесь можно разместить информацию о вашем магазине, складе или сервисе.",
      links = { { label = "На главную", path = "/" } },
    },
  },
}
]==]

local function ensureConfig()
  if not filesystem.exists(CONFIG_PATH) then
    if not filesystem.exists("/os/sitedata") then filesystem.makeDirectory("/os/sitedata") end
    local f = io.open(CONFIG_PATH, "w")
    f:write(DEFAULT_CONFIG)
    f:close()
  end
end

return {
  id = "sitehost",
  name = "Мой сайт",
  icon = "S",
  run = function(ctx, args)
    local gui = ctx.gui
    local net = ctx.net
    ensureConfig()

    local win = gui.newWindow{ title = "Мой сайт — выключен", x = 10, y = 3, w = 50, h = 16 }
    local log = win:add(gui.textarea(1, 3, win.w - 2, win.h - 6, { "Нажмите «Запустить», чтобы начать раздавать сайт." }, false))
    local status = win:add(gui.label(1, 1, "Статус: остановлен", gui.theme.warn))

    local handler, siteName = nil, nil

    local function addLog(msg)
      table.insert(log.lines, msg)
      if #log.lines > 200 then table.remove(log.lines, 1) end
      log.top = math.max(0, #log.lines - log.h)
    end

    local function stop()
      if handler then
        event.ignore("modem_message", handler)
        handler = nil
        status:setText("Статус: остановлен")
        win.title = "Мой сайт — выключен"
        ctx.state.siteName = nil
      end
    end

    local function start()
      if not net.available() then
        addLog("Нет сетевой карты (modem/network card) в этом компьютере!")
        return
      end
      local chunk, err = loadfile(CONFIG_PATH)
      if not chunk then addLog("Ошибка в конфиге: " .. tostring(err)); return end
      local ok, cfg = pcall(chunk)
      if not ok or type(cfg) ~= "table" then addLog("Ошибка в конфиге: " .. tostring(cfg)); return end
      siteName = cfg.name or "сайт"
      net.open()
      handler = net.makeHost(siteName, cfg.pages or {}, addLog)
      event.listen("modem_message", handler)
      status:setText("Статус: работает (" .. siteName .. ")")
      win.title = "Мой сайт — " .. siteName
      ctx.state.siteName = siteName
      addLog("Сайт '" .. siteName .. "' запущен и ждёт запросов.")
    end

    win:add(gui.button(1, win.h - 2, 12, 1, "Запустить", function() start() end))
    win:add(gui.button(14, win.h - 2, 12, 1, "Остановить", function() stop() end))
    win:add(gui.button(27, win.h - 2, 16, 1, "Открыть конфиг", function()
      local editor = ctx.appapi.get("editor")
      if editor then editor.run(ctx, { path = CONFIG_PATH }) end
    end))

    win.onClose = stop

    return win
  end
}
