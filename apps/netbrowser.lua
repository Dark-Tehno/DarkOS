-- netbrowser.lua — "браузер" для связи с другими компьютерами/сайтами
-- в пределах сервера через modem/network card по протоколу OCNet.
return {
  id = "netbrowser",
  name = "Обозреватель",
  icon = "N",
  run = function(ctx, args)
    local gui = ctx.gui
    local net = ctx.net

    local win = gui.newWindow{ title = "Обозреватель сети", x = 5, y = 2, w = 56, h = 20 }

    local addr = win:add(gui.input(1, 1, win.w - 12, (args and args.site) or ""))
    local status = win:add(gui.label(1, win.h - 1, "", gui.theme.warn))
    local body = win:add(gui.textarea(1, 3, win.w - 2, win.h - 6, { "Введите имя сайта или адрес и нажмите «Перейти».", "", "Если у вас есть свой хост (см. приложение «Мой сайт»),", "просто введите его имя." }, false))

    local linkButtons = {}
    local currentAddress = nil

    local function clearLinks()
      for _, b in ipairs(linkButtons) do win:remove(b) end
      linkButtons = {}
    end

    local function load(target, path)
      status:setText("Загрузка...")
      status:draw(win)
      local page, err = net.get(target, path or "/")
      if not page then
        status:setText("Ошибка: " .. tostring(err))
        return
      end
      currentAddress = page.address
      win.title = "Обозреватель — " .. (page.title or target)
      local lines = {}
      for l in tostring(page.body or ""):gmatch("([^\n]*)\n?") do table.insert(lines, l) end
      if #lines == 0 then lines = { "" } end
      body:setLines(lines)
      clearLinks()
      local row = win.h - 5
      for i, link in ipairs(page.links or {}) do
        if row < 4 then break end
        local b = win:add(gui.button(1, row, win.w - 2, 1, "> " .. link.label, function()
          load(currentAddress, link.path)
        end, { bg = gui.theme.windowBg, fg = gui.theme.accent }))
        table.insert(linkButtons, b)
        row = row - 1
      end
      status:setText("Готово")
    end

    win:add(gui.button(win.w - 10, 1, 9, 1, "Перейти", function()
      if not net.available() then
        status:setText("Нет сетевой карты в этом компьютере")
        return
      end
      load(addr.text, "/")
    end))

    addr.onEnter = function(text) load(text, "/") end

    if args and args.site and args.site ~= "" then
      load(args.site, "/")
    end

    return win
  end
}
