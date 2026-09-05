-- files.lua — файловый менеджер: просмотр папок, открытие файлов в редакторе,
-- создание/удаление файлов и папок.
local filesystem = require("filesystem")

return {
  id = "files",
  name = "Проводник",
  icon = "F",
  run = function(ctx, args)
    local gui = ctx.gui
    local win = gui.newWindow{ title = "Проводник", x = 6, y = 2, w = 46, h = 18 }

    local path = (args and args.path) or "/home"
    local selected = nil
    local entries = {}
    local rowButtons = {}

    local pathLabel = win:add(gui.label(1, 1, path, gui.theme.accent))
    local status = win:add(gui.label(1, win.h - 2, "", gui.theme.warn))
    local refresh -- объявляем заранее: используется в замыканиях кнопок ниже

    local btnOpen = win:add(gui.button(1, win.h - 1, 10, 1, "Открыть", function()
      if selected and not selected.isDir then
        local appapi = ctx.appapi
        local editor = appapi.get("editor")
        if editor then editor.run(ctx, { path = selected.full }) end
      elseif selected and selected.isDir then
        path = selected.full
        refresh()
      end
    end))
    local btnDelete = win:add(gui.button(12, win.h - 1, 10, 1, "Удалить", function()
      if selected then
        local ok, err = pcall(filesystem.remove, selected.full)
        status:setText(ok and "Удалено" or ("Ошибка: " .. tostring(err)))
        selected = nil
        refresh()
      end
    end))
    local btnNewFile = win:add(gui.button(23, win.h - 1, 10, 1, "Новый файл", function()
      local n = 1
      local newPath
      repeat
        newPath = filesystem.concat(path, "new" .. n .. ".lua")
        n = n + 1
      until not filesystem.exists(newPath)
      local f = io.open(newPath, "w")
      if f then f:write(""); f:close() end
      refresh()
    end))
    local btnUp = win:add(gui.button(34, win.h - 1, 8, 1, "Вверх", function()
      if path ~= "/" then
        path = filesystem.path(path) or "/"
        selected = nil
        refresh()
      end
    end))

    refresh = function()
      for _, b in ipairs(rowButtons) do win:remove(b) end
      rowButtons = {}
      entries = {}
      if filesystem.exists(path) and filesystem.isDirectory(path) then
        for name in filesystem.list(path) do
          local isDir = name:sub(-1) == "/"
          local clean = isDir and name:sub(1, -2) or name
          table.insert(entries, { name = clean, isDir = isDir, full = filesystem.concat(path, clean) })
        end
      end
      table.sort(entries, function(a, b)
        if a.isDir ~= b.isDir then return a.isDir end
        return a.name < b.name
      end)
      pathLabel:setText(path:sub(1, win.w - 2))
      local row = 3
      for _, e in ipairs(entries) do
        if row > win.h - 3 then break end
        local label = (e.isDir and "[папка] " or "        ") .. e.name
        local b = win:add(gui.button(1, row, win.w - 2, 1, label, function()
          selected = e
          status:setText("Выбрано: " .. e.name)
        end, { bg = gui.theme.windowBg, fg = e.isDir and gui.theme.accent or gui.theme.windowText }))
        table.insert(rowButtons, b)
        row = row + 1
      end
    end

    refresh()
    return win
  end
}
