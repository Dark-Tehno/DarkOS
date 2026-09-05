-- settings.lua — базовые настройки рабочего стола + сведения о системе.
local component = require("component")
local computer = require("computer")

return {
  id = "settings",
  name = "Настройки",
  icon = "•",
  run = function(ctx, args)
    local gui = ctx.gui
    local desktop = ctx.desktop

    local win = gui.newWindow{ title = "Настройки", x = 12, y = 3, w = 44, h = 15 }

    win:add(gui.label(1, 1, "Цвет рабочего стола:", gui.theme.windowText))
    local colors = { 0x1F3A5F, 0x2E2E2E, 0x203A20, 0x4A2020, 0x3A2E4A }
    for i, c in ipairs(colors) do
      win:add(gui.button(1 + (i - 1) * 6, 2, 5, 1, "    ", function()
        desktop.setWallpaper(c)
      end, { bg = c, fg = c }))
    end

    local gpu = component.gpu
    local w, h = gpu.getResolution()
    local info = {
      "Память: " .. math.floor(computer.freeMemory() / 1024) .. " / " .. math.floor(computer.totalMemory() / 1024) .. " КБ",
      "Экран: " .. w .. "x" .. h .. ", глубина цвета: " .. gpu.getDepth() .. " бит",
      "Сетевая карта: " .. (component.isAvailable("modem") and "есть" or "нет"),
      "Интернет-карта: " .. (component.isAvailable("internet") and "есть" or "нет"),
      "Аптайм: " .. math.floor(computer.uptime()) .. " сек.",
    }
    win:add(gui.textarea(1, 5, win.w - 2, win.h - 7, info, false))

    return win
  end
}
