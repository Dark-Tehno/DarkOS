-- editor.lua — простой текстовый редактор с открытием/сохранением файлов.
local filesystem = require("filesystem")

local function readLines(path)
  local lines = {}
  local f = io.open(path, "r")
  if not f then return { "" } end
  for line in f:lines() do table.insert(lines, line) end
  f:close()
  if #lines == 0 then lines = { "" } end
  return lines
end

local function writeLines(path, lines)
  local dir = filesystem.path(path)
  if dir and dir ~= "" and not filesystem.exists(dir) then
    filesystem.makeDirectory(dir)
  end
  local f, err = io.open(path, "w")
  if not f then return false, err end
  f:write(table.concat(lines, "\n"))
  f:close()
  return true
end

return {
  id = "editor",
  name = "Редактор",
  icon = "E",
  run = function(ctx, args)
    local gui = ctx.gui
    local path = args and args.path or nil
    local lines = path and readLines(path) or { "" }

    local win = gui.newWindow{
      title = "Редактор" .. (path and (" — " .. path) or " — новый файл"),
      x = 8, y = 2, w = 54, h = 20,
    }

    local pathInput = win:add(gui.input(1, 1, win.w - 2, path or ""))
    local area = win:add(gui.textarea(1, 3, win.w - 2, win.h - 5, lines, true))
    local status = win:add(gui.label(1, win.h - 1, "Ctrl+S — сохранить (или кнопка ниже)", gui.theme.warn))

    local saveBtn = win:add(gui.button(win.w - 12, 1, 11, 1, "Сохранить", function()
      local target = pathInput.text
      if target == "" then
        status:setText("Укажите путь к файлу вверху")
        return
      end
      local ok, err = writeLines(target, area.lines)
      status:setText(ok and ("Сохранено: " .. target) or ("Ошибка: " .. tostring(err)))
      win.title = "Редактор — " .. target
    end))

    -- поддержка Ctrl+S прямо во время редактирования текста
    local originalOnKey = area.onKey
    area.onKey = function(self, w, char, code)
      local keyboard = require("keyboard")
      if keyboard.isControlDown() and code == keyboard.keys.s then
        saveBtn.onClick(w)
        return
      end
      originalOnKey(self, w, char, code)
    end

    return win
  end
}
