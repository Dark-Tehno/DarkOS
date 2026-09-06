-- updater.lua — подключается к серверу обновлений ("Раздача обновлений" на
-- другом компьютере) и скачивает те файлы /os, которые отличаются от
-- локальных или отсутствуют. После обновления нужно перезагрузить компьютер.
local filesystem = require("filesystem")
local computer = require("computer")

local function localInfo(net, relPath)
  local full = filesystem.concat("/os", relPath)
  local content = net.readFile(full)
  if not content then return nil end
  return { size = #content, checksum = net.checksum(content) }
end

return {
  id = "updater",
  name = "Обновление",
  icon = "O",
  run = function(ctx, args)
    local gui = ctx.gui
    local net = ctx.net

    local win = gui.newWindow{ title = "Обновление ОС", x = 8, y = 3, w = 52, h = 18 }
    win:add(gui.label(1, 1, "Имя/адрес сервера обновлений:", gui.theme.windowText))
    local addrInput = win:add(gui.input(1, 2, win.w - 2, ""))
    local status = win:add(gui.label(1, 4, "", gui.theme.warn))
    local log = win:add(gui.textarea(1, 5, win.w - 2, win.h - 8, { "Введите имя сервера и нажмите «Проверить»." }, false))

    local pending, serverAddress = nil, nil

    local function addLog(msg)
      table.insert(log.lines, msg)
      if #log.lines > 300 then table.remove(log.lines, 1) end
      log.top = math.max(0, #log.lines - log.h)
    end

    local function redrawNow()
      status:draw(win)
      log:draw(win)
    end

    local function check()
      if not net.available() then
        status:setText("Нет сетевой карты в этом компьютере")
        return
      end
      local target = addrInput.text
      if target == "" then status:setText("Укажите имя сервера"); return end
      status:setText("Ищу сервер и сверяю файлы..."); redrawNow()
      local manifest, addrOrErr = net.requestManifest(target, 3)
      if not manifest then
        status:setText("Ошибка: " .. tostring(addrOrErr))
        return
      end
      serverAddress = addrOrErr
      pending = {}
      log.lines = {}
      for _, entry in ipairs(manifest) do
        local li = localInfo(net, entry.path)
        if not li then
          table.insert(pending, entry.path)
          addLog("[новый]     " .. entry.path)
        elseif li.size ~= entry.size or li.checksum ~= entry.checksum then
          table.insert(pending, entry.path)
          addLog("[изменён]   " .. entry.path)
        else
          addLog("[актуален]  " .. entry.path)
        end
      end
      status:setText(#pending == 0 and "Всё уже актуально" or (#pending .. " файл(ов) требуют обновления — нажмите «Обновить»"))
    end

    local function update()
      if not pending or #pending == 0 then
        status:setText("Сначала нажмите «Проверить обновления»")
        return
      end
      for _, relPath in ipairs(pending) do
        status:setText("Скачиваю " .. relPath .. "..."); redrawNow()
        local content, err = net.fetchFile(serverAddress, relPath, 5)
        if not content then
          addLog("ОШИБКА при " .. relPath .. ": " .. tostring(err))
        else
          local full = filesystem.concat("/os", relPath)
          local dir = filesystem.path(full)
          if dir and dir ~= "" and not filesystem.exists(dir) then
            filesystem.makeDirectory(dir)
          end
          local f = io.open(full, "w")
          if f then
            f:write(content)
            f:close()
            addLog("Обновлён: " .. relPath)
          else
            addLog("Не удалось записать: " .. relPath)
          end
        end
      end
      pending = {}
      status:setText("Готово. Перезагрузите компьютер, чтобы применить обновления.")
    end

    win:add(gui.button(1, win.h - 2, 16, 1, "Проверить", function() check() end))
    win:add(gui.button(18, win.h - 2, 16, 1, "Обновить", function() update() end))
    win:add(gui.button(35, win.h - 2, 16, 1, "Перезагрузить", function()
      computer.shutdown(true)
    end))
    win:add(gui.label(1, win.h - 1, "Перезагрузка мгновенная — сохраните файлы!", gui.theme.err))

    return win
  end
}
