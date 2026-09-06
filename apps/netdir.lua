-- netdir.lua — «Сеть»: пока это приложение открыто и включено, ваш компьютер
-- виден остальным (отвечает на поиск других компьютеров). Кнопка «Обновить
-- список» показывает все компьютеры, которые сейчас включены и тоже видимы —
-- по сути внутриигровой «интернет» между вашими машинами, без нужды помнить
-- адреса. Клик по компьютеру в списке сразу открывает его в «Обозревателе».
local event = require("event")

return {
  id = "netdir",
  name = "Сеть",
  icon = "@",
  run = function(ctx, args)
    local gui = ctx.gui
    local net = ctx.net

    local win = gui.newWindow{ title = "Сеть — вы не видны", x = 6, y = 2, w = 50, h = 18 }
    local status = win:add(gui.label(1, 1, "Статус: скрыт", gui.theme.warn))
    local list = win:add(gui.textarea(1, 3, win.w - 2, win.h - 6, { "Нажмите «Войти в сеть», затем «Обновить список»." }, false))

    local handler = nil
    local found = {} -- индекс строки списка -> { address=, name=, extra= }
    local rowButtons = {}

    local function redrawNow()
      status:draw(win)
      list:draw(win)
    end

    local function join()
      if not net.available() then
        status:setText("Нет сетевой карты в этом компьютере")
        return
      end
      net.open()
      handler = net.makePresenceResponder(
        function() return ctx.desktop.getComputerName() end,
        function() return ctx.state.siteName end
      )
      event.listen("modem_message", handler)
      status:setText("Статус: виден в сети как «" .. ctx.desktop.getComputerName() .. "»")
      win.title = "Сеть — вы видны"
    end

    local function leave()
      if handler then
        event.ignore("modem_message", handler)
        handler = nil
      end
      status:setText("Статус: скрыт")
      win.title = "Сеть — вы не видны"
    end

    local function scan()
      if not net.available() then
        status:setText("Нет сетевой карты в этом компьютере")
        return
      end
      status:setText("Ищу компьютеры в сети..."); redrawNow()
      local results = net.scanNetwork(1.5)
      for _, b in ipairs(rowButtons) do win:remove(b) end
      rowButtons = {}
      found = results
      if #results == 0 then
        list.visible = true
        list:setLines({ "Никого не найдено.", "Убедитесь, что на других компьютерах тоже", "открыто приложение «Сеть» и нажато «Войти в сеть»." })
      else
        list.visible = false
        for i, r in ipairs(results) do
          if 3 + i - 1 > win.h - 4 then break end
          local extraText = r.extra and (" — сайт «" .. tostring(r.extra) .. "»") or ""
          local line = "> " .. (r.name or "?") .. extraText
          local b = win:add(gui.button(1, 3 + i - 1, win.w - 2, 1, line, function()
            local browser = ctx.appapi.get("netbrowser")
            if browser then browser.run(ctx, { site = r.address }) end
          end, { bg = gui.theme.windowBg, fg = gui.theme.accent }))
          table.insert(rowButtons, b)
        end
      end
      status:setText("Найдено компьютеров: " .. #results)
    end

    win:add(gui.button(1, win.h - 2, 14, 1, "Войти в сеть", function() join() end))
    win:add(gui.button(16, win.h - 2, 12, 1, "Выйти", function() leave() end))
    win:add(gui.button(29, win.h - 2, 16, 1, "Обновить список", function() scan() end))

    win.onClose = leave

    return win
  end
}
