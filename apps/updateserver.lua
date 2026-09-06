-- updateserver.lua — раздаёт файлы вашей ОС (/os) другим компьютерам по сети,
-- чтобы не копировать обновления на каждый компьютер вручную. Запустите это
-- приложение на "эталонном" компьютере с самой свежей версией ОС.
local event = require("event")

return {
  id = "updateserver",
  name = "Раздача обновлений",
  icon = "U",
  run = function(ctx, args)
    local gui = ctx.gui
    local net = ctx.net

    local win = gui.newWindow{ title = "Раздача обновлений — выключена", x = 8, y = 3, w = 52, h = 16 }
    local status = win:add(gui.label(1, 1, "Статус: остановлена", gui.theme.warn))
    win:add(gui.label(1, 2, "Имя сервера (его вводят в «Обновлении» на клиентах):", gui.theme.windowText))
    local nameInput = win:add(gui.input(1, 3, win.w - 2, "update-server"))
    local log = win:add(gui.textarea(1, 5, win.w - 2, win.h - 7, { "Нажмите «Запустить», чтобы начать раздавать /os." }, false))

    local handler = nil

    local function addLog(msg)
      table.insert(log.lines, msg)
      if #log.lines > 200 then table.remove(log.lines, 1) end
      log.top = math.max(0, #log.lines - log.h)
    end

    local function stop()
      if handler then
        event.ignore("modem_message", handler)
        handler = nil
        status:setText("Статус: остановлена")
        win.title = "Раздача обновлений — выключена"
      end
    end

    local function start()
      if not net.available() then
        addLog("Нет сетевой карты (modem/network card) в этом компьютере!")
        return
      end
      local name = nameInput.text
      if name == "" then addLog("Укажите имя сервера"); return end
      net.open()
      handler = net.makeUpdateServer("/os", name, addLog)
      event.listen("modem_message", handler)
      status:setText("Статус: работает (" .. name .. ")")
      win.title = "Раздача обновлений — " .. name
      addLog("Сервер '" .. name .. "' раздаёт /os и ждёт запросов.")
    end

    win:add(gui.button(1, win.h - 1, 12, 1, "Запустить", function() start() end))
    win:add(gui.button(14, win.h - 1, 12, 1, "Остановить", function() stop() end))

    win.onClose = stop
    return win
  end
}
