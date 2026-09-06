-- autorun.lua
-- Поместите этот файл в КОРЕНЬ диска компьютера (то есть путь должен быть
-- ровно "/autorun.lua"), рядом с папкой "os". На части сборок OpenOS для
-- 1.12.2 автозапуск отсюда работает "из коробки"; если у вас не сработает —
-- см. README.md, раздел "Автозапуск", про альтернативный способ через
-- /home/.shrc.

local ok, err = pcall(function()
  dofile("/os/init.lua")
end)

if not ok then
  io.stderr:write("Не удалось запустить ОС: " .. tostring(err) .. "\n")
  io.stderr:write("Вы остались в обычной консоли OpenOS.\n")
end
