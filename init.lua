-- init.lua — точка входа кастомной ОС.
-- Загружается через /autorun.lua (см. README.md) поверх OpenOS.

local component = require("component")
local event = require("event")
local term = require("term")
local filesystem = require("filesystem")
local computer = require("computer")
local gpu = component.gpu

local OS_ROOT = "/os"

local function load(relPath)
  local full = OS_ROOT .. relPath
  local chunk, err = loadfile(full)
  if not chunk then error("Не удалось загрузить " .. full .. ": " .. tostring(err), 0) end
  return chunk()
end

local gui    = load("/api/gui.lua")
local appapi = load("/api/appapi.lua")
local net    = load("/api/netproto.lua")

--------------------------------------------------------------------------
-- Подготовка экрана
--------------------------------------------------------------------------
local maxW, maxH = gpu.maxResolution()
gpu.setResolution(maxW, maxH)
local screenW, screenH = gpu.getResolution()
term.clear()
term.setCursorBlink(false)

--------------------------------------------------------------------------
-- Простая персистентная настройка (цвет обоев)
--------------------------------------------------------------------------
local CONFIG_PATH = OS_ROOT .. "/config.lua"
local config = { wallpaper = gui.theme.desktop }
if filesystem.exists(CONFIG_PATH) then
  local chunk = loadfile(CONFIG_PATH)
  if chunk then
    local ok, cfg = pcall(chunk)
    if ok and type(cfg) == "table" then config = cfg end
  end
end
local function saveConfig()
  local f = io.open(CONFIG_PATH, "w")
  if f then
    f:write("return { wallpaper = " .. string.format("0x%06X", config.wallpaper) .. " }\n")
    f:close()
  end
end

--------------------------------------------------------------------------
-- Контекст, доступный всем приложениям
--------------------------------------------------------------------------
local ctx = { gui = gui, net = net, appapi = appapi, fs = filesystem }
ctx.desktop = {
  setWallpaper = function(color)
    config.wallpaper = color
    saveConfig()
  end,
}

local function launchApp(app, args)
  local ok, winOrErr = pcall(app.run, ctx, args)
  if not ok then
    local w = gui.newWindow{ title = "Ошибка в приложении " .. app.name, x = 6, y = 4, w = 50, h = 10 }
    local lines = {}
    for l in tostring(winOrErr):gmatch("([^\n]*)\n?") do table.insert(lines, l) end
    w:add(gui.textarea(1, 1, w.w - 2, w.h - 2, lines, false))
  end
end

--------------------------------------------------------------------------
-- Загрузка приложений
--------------------------------------------------------------------------
local loadErrors = {}
appapi.loadAll(OS_ROOT .. "/apps", function(file, err)
  table.insert(loadErrors, file .. ": " .. tostring(err))
end)

--------------------------------------------------------------------------
-- Рабочий стол: иконки, панель задач, меню «Пуск»
--------------------------------------------------------------------------
local startMenuWin = nil

local function closeStartMenu()
  if startMenuWin then startMenuWin:close(); startMenuWin = nil end
end

local function openStartMenu()
  closeStartMenu()
  local apps = appapi.list()
  local h = math.min(#apps + 2, screenH - 3)
  startMenuWin = gui.newWindow{
    title = "", noTitle = true, closable = false,
    x = 1, y = screenH - 1 - h, w = 22, h = h,
    bg = gui.theme.taskbar,
  }
  for i, app in ipairs(apps) do
    startMenuWin:add(gui.button(1, i, startMenuWin.w - 2, 1, "[" .. app.icon .. "] " .. app.name, function(win)
      launchApp(app)
      closeStartMenu()
    end, { bg = gui.theme.taskbar, fg = gui.theme.taskbarText }))
  end
end

local ICON_X, ICON_Y0 = 2, 2
local function iconAt(px, py)
  if px < ICON_X then return nil end
  local i = py - ICON_Y0 + 1
  local apps = appapi.list()
  local app = apps[i]
  if app and py >= ICON_Y0 then
    local label = "[" .. app.icon .. "] " .. app.name
    if px < ICON_X + #label then return app end
  end
  return nil
end

local function drawDesktop()
  gui.rect(1, 1, screenW, screenH, config.wallpaper)
  local apps = appapi.list()
  for i, app in ipairs(apps) do
    local label = "[" .. app.icon .. "] " .. app.name
    gui.text(ICON_X, ICON_Y0 + i - 1, label, 0xFFFFFF, config.wallpaper)
  end
end

local TASKBAR_Y = screenH
local function drawTaskbar()
  gui.rect(1, TASKBAR_Y, screenW, 1, gui.theme.taskbar)
  gui.text(1, TASKBAR_Y, " ПУСК ", gui.theme.taskbarText, gui.theme.accent)
  local clock = os.date("%H:%M:%S")
  gui.text(screenW - #clock - 8, TASKBAR_Y, clock, gui.theme.taskbarText, gui.theme.taskbar)
  gui.text(screenW - 6, TASKBAR_Y, "ВЫХОД", gui.theme.taskbarText, gui.theme.err)
end

local function draw()
  drawDesktop()
  gui.drawWindows()
  drawTaskbar()
end

--------------------------------------------------------------------------
-- Главный цикл
--------------------------------------------------------------------------
local running = true

local function handleTouch(x, y, btn)
  if y == TASKBAR_Y then
    if x >= 1 and x <= 6 then
      if startMenuWin then closeStartMenu() else openStartMenu() end
      return true
    elseif x >= screenW - 6 then
      running = false
      return true
    end
    return true
  end
  local handled = gui.dispatch("touch", nil, x, y, btn)
  if handled then return true end
  local app = iconAt(x, y)
  if app then launchApp(app); return true end
  if startMenuWin then closeStartMenu() end
  return false
end

if #loadErrors > 0 then
  local w = gui.newWindow{ title = "Ошибки загрузки приложений", x = 5, y = 3, w = 50, h = 12 }
  w:add(gui.textarea(1, 1, w.w - 2, w.h - 2, loadErrors, false))
end

while running do
  draw()
  local sig = { event.pull(1) }
  local name = sig[1]
  if name == "touch" then
    handleTouch(sig[3], sig[4], sig[5])
  elseif name == "drag" or name == "drop" or name == "scroll" then
    gui.dispatch(name, sig[2], sig[3], sig[4], sig[5], sig[6])
  elseif name == "key_down" then
    gui.dispatch(name, sig[2], sig[3], sig[4], sig[5])
  end
end

--------------------------------------------------------------------------
-- Выход — возвращаем обычный вид консоли OpenOS
--------------------------------------------------------------------------
term.clear()
term.setCursorBlink(true)
print("Рабочая среда завершена. Вы в обычной консоли OpenOS.")
