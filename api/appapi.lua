-- appapi.lua — реестр приложений.
-- Приложение — это файл /os/apps/<имя>.lua, который возвращает таблицу:
--   {
--     id   = "editor",          -- уникальный идентификатор
--     name = "Редактор",        -- имя в меню Пуск
--     icon = "E",                -- один символ-значок на рабочем столе
--     run  = function(ctx, args) ... end  -- вызывается при запуске
--   }
-- Подробности и шаблон — в README.md.

local filesystem = require("filesystem")

local appapi = {}
local apps = {}

function appapi.register(app)
  if not app or not app.id then return false, "у приложения нет id" end
  apps[app.id] = app
  return true
end

function appapi.get(id) return apps[id] end

function appapi.list()
  local list = {}
  for _, a in pairs(apps) do table.insert(list, a) end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- Загружает все .lua файлы из указанной папки как приложения.
function appapi.loadAll(path, onError)
  if not filesystem.exists(path) then return end
  for file in filesystem.list(path) do
    if file:sub(-4) == ".lua" then
      local full = filesystem.concat(path, file)
      local chunk, err = loadfile(full)
      if not chunk then
        if onError then onError(file, err) end
      else
        local ok, appOrErr = pcall(chunk)
        if not ok then
          if onError then onError(file, appOrErr) end
        elseif type(appOrErr) == "table" then
          appapi.register(appOrErr)
        end
      end
    end
  end
end

return appapi
