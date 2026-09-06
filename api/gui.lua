-- gui.lua — компактная библиотека окон и виджетов для OpenComputers.
-- Не использует двойную буферизацию и картинки-иконки, чтобы занимать
-- как можно меньше места на диске и в памяти.

local component = require("component")
local keyboard  = require("keyboard")
local gpu = component.gpu

local theme = loadfile("/os/api/theme.lua")()

local gui = {}
gui.theme = theme
gui.windows = {}        -- z-order: последний элемент — самый верхний
gui._focusedInput = nil -- виджет, получающий клавиатурный ввод

local function clamp(v, a, b)
  if v < a then return a elseif v > b then return b else return v end
end
gui.clamp = clamp

--------------------------------------------------------------------------
-- Примитивы рисования
--------------------------------------------------------------------------
function gui.rect(x, y, w, h, bg)
  if w < 1 or h < 1 then return end
  if bg then gpu.setBackground(bg) end
  gpu.fill(x, y, w, h, " ")
end

function gui.text(x, y, str, fg, bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x, y, str)
end

function gui.focusInput(widget)
  gui._focusedInput = widget
end

--------------------------------------------------------------------------
-- Базовый Widget
--------------------------------------------------------------------------
local Widget = {}
Widget.__index = Widget

function Widget.new(x, y, w, h)
  return setmetatable({ x = x, y = y, w = w, h = h, visible = true }, Widget)
end

function Widget:hit(px, py)
  return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h
end

function Widget:draw(win) end
function Widget:onTouch(win, x, y, btn) end
function Widget:onKey(win, char, code) end
function Widget:onScroll(win, dir) end

gui.Widget = Widget

--------------------------------------------------------------------------
-- Label
--------------------------------------------------------------------------
local Label = setmetatable({}, { __index = Widget })
Label.__index = Label

function gui.label(x, y, text, fg)
  local l = setmetatable(Widget.new(x, y, #text, 1), Label)
  l.text, l.fg = text, fg or theme.windowText
  return l
end

function Label:setText(t) self.text = t; self.w = #t end

function Label:draw(win)
  local maxW = win.w - self.x - 1
  local t = self.text
  if maxW > 0 and #t > maxW then t = t:sub(1, maxW) end
  gui.text(win.x + self.x, win.y + self.y, t, self.fg, win.bg)
end

--------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------
local Button = setmetatable({}, { __index = Widget })
Button.__index = Button

function gui.button(x, y, w, h, label, onClick, colors)
  local b = setmetatable(Widget.new(x, y, w, h), Button)
  b.label, b.onClick = label, onClick
  b.bg = (colors and colors.bg) or theme.btnBg
  b.fg = (colors and colors.fg) or theme.btnText
  return b
end

function Button:draw(win)
  local ax, ay = win.x + self.x, win.y + self.y
  gui.rect(ax, ay, self.w, self.h, self.bg)
  local label = self.label
  if #label > self.w - 2 then label = label:sub(1, self.w - 2) end
  local tx = ax + math.max(0, math.floor((self.w - #label) / 2))
  local ty = ay + math.floor((self.h - 1) / 2)
  gui.text(tx, ty, label, self.fg, self.bg)
end

function Button:onTouch(win, x, y, btn)
  if self.onClick then self.onClick(win) end
end

--------------------------------------------------------------------------
-- TextInput (однострочное поле ввода)
--------------------------------------------------------------------------
local TextInput = setmetatable({}, { __index = Widget })
TextInput.__index = TextInput

function gui.input(x, y, w, text)
  local t = setmetatable(Widget.new(x, y, w, 1), TextInput)
  t.text = text or ""
  t.onEnter = nil
  return t
end

function TextInput:draw(win)
  local ax, ay = win.x + self.x, win.y + self.y
  local focused = gui._focusedInput == self
  gui.rect(ax, ay, self.w, 1, focused and theme.inputBgFoc or theme.inputBg)
  local shown = self.text
  if #shown > self.w - 1 then shown = shown:sub(#shown - self.w + 2) end
  gui.text(ax, ay, shown, theme.inputText)
  if focused then gui.text(ax + #shown, ay, "_", theme.accent) end
end

function TextInput:onTouch(win, x, y, btn)
  gui.focusInput(self)
end

function TextInput:onKey(win, char, code)
  if code == keyboard.keys.back then
    self.text = self.text:sub(1, #self.text - 1)
  elseif code == keyboard.keys.enter then
    if self.onEnter then self.onEnter(self.text) end
  elseif char and char >= 32 and char < 127 then
    self.text = self.text .. string.char(char)
  end
end

--------------------------------------------------------------------------
-- TextArea (многострочная область — просмотр и редактирование)
--------------------------------------------------------------------------
local TextArea = setmetatable({}, { __index = Widget })
TextArea.__index = TextArea

function gui.textarea(x, y, w, h, lines, editable)
  local t = setmetatable(Widget.new(x, y, w, h), TextArea)
  t.lines = lines or { "" }
  t.top, t.cx, t.cy = 0, 0, 0
  t.editable = editable or false
  return t
end

function TextArea:setLines(lines)
  self.lines = lines
  self.top, self.cx, self.cy = 0, 0, 0
end

function TextArea:getText()
  return table.concat(self.lines, "\n")
end

function TextArea:ensureVisible()
  if self.cy < self.top then self.top = self.cy end
  if self.cy > self.top + self.h - 1 then self.top = self.cy - self.h + 1 end
  if self.top < 0 then self.top = 0 end
end

function TextArea:draw(win)
  local ax, ay = win.x + self.x, win.y + self.y
  gui.rect(ax, ay, self.w, self.h, theme.areaBg)
  for i = 1, self.h do
    local line = self.lines[self.top + i]
    if line then
      local shown = line:sub(1, self.w)
      gui.text(ax, ay + i - 1, shown, theme.areaText, theme.areaBg)
    end
  end
  if self.editable and gui._focusedInput == self then
    local sy = self.cy - self.top
    if sy >= 0 and sy < self.h then
      local sx = clamp(self.cx, 0, self.w - 1)
      gui.text(ax + sx, ay + sy, "_", theme.accent)
    end
  end
end

function TextArea:onTouch(win, x, y, btn)
  if not self.editable then return end
  gui.focusInput(self)
  self.cy = clamp(self.top + y, 0, #self.lines - 1)
  self.cx = clamp(x, 0, #(self.lines[self.cy + 1] or ""))
end

function TextArea:onScroll(win, dir)
  self.top = clamp(self.top - dir, 0, math.max(0, #self.lines - self.h))
end

function TextArea:onKey(win, char, code)
  if not self.editable then return end
  local line = self.lines[self.cy + 1] or ""
  local K = keyboard.keys
  if code == K.left then
    self.cx = math.max(0, self.cx - 1)
  elseif code == K.right then
    self.cx = math.min(#line, self.cx + 1)
  elseif code == K.up then
    self.cy = math.max(0, self.cy - 1)
    self.cx = math.min(self.cx, #(self.lines[self.cy + 1] or ""))
  elseif code == K.down then
    self.cy = math.min(#self.lines - 1, self.cy + 1)
    self.cx = math.min(self.cx, #(self.lines[self.cy + 1] or ""))
  elseif code == K.home then
    self.cx = 0
  elseif code == K["end"] then
    self.cx = #line
  elseif code == K.enter then
    local before, after = line:sub(1, self.cx), line:sub(self.cx + 1)
    self.lines[self.cy + 1] = before
    table.insert(self.lines, self.cy + 2, after)
    self.cy, self.cx = self.cy + 1, 0
  elseif code == K.back then
    if self.cx > 0 then
      self.lines[self.cy + 1] = line:sub(1, self.cx - 1) .. line:sub(self.cx + 1)
      self.cx = self.cx - 1
    elseif self.cy > 0 then
      local prev = self.lines[self.cy]
      self.cx = #prev
      self.lines[self.cy] = prev .. line
      table.remove(self.lines, self.cy + 1)
      self.cy = self.cy - 1
    end
  elseif code == K.delete then
    if self.cx < #line then
      self.lines[self.cy + 1] = line:sub(1, self.cx) .. line:sub(self.cx + 2)
    elseif self.lines[self.cy + 2] then
      self.lines[self.cy + 1] = line .. self.lines[self.cy + 2]
      table.remove(self.lines, self.cy + 2)
    end
  elseif char and char >= 32 and char < 127 then
    self.lines[self.cy + 1] = line:sub(1, self.cx) .. string.char(char) .. line:sub(self.cx + 1)
    self.cx = self.cx + 1
  end
  self:ensureVisible()
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------
local Window = {}
Window.__index = Window

function gui.newWindow(opts)
  opts = opts or {}
  local w = setmetatable({}, Window)
  local sw, sh = gpu.getResolution()
  w.w = math.max(10, math.min(opts.w or 40, sw))
  w.h = math.max(4, math.min(opts.h or 15, sh - 1))
  w.x = math.max(1, math.min(opts.x or 4, sw - w.w + 1))
  w.y = math.max(1, math.min(opts.y or 2, sh - w.h))
  w.title = opts.title or "Окно"
  w.bg = opts.bg or theme.windowBg
  w.titleBg = opts.titleBg or theme.titleBg
  w.widgets = {}
  w.closable = opts.closable ~= false
  w.noTitle = opts.noTitle or false
  w.onClose = opts.onClose
  w.dragging = false
  table.insert(gui.windows, w)
  gui.focused = w
  return w
end

function Window:add(widget)
  table.insert(self.widgets, widget)
  return widget
end

function Window:remove(widget)
  for i, wd in ipairs(self.widgets) do
    if wd == widget then table.remove(self.widgets, i); break end
  end
end

function Window:close()
  for i, w in ipairs(gui.windows) do
    if w == self then table.remove(gui.windows, i); break end
  end
  if gui._focusedInput and gui._focusedInput._owner == self then gui._focusedInput = nil end
  if gui.focused == self then gui.focused = gui.windows[#gui.windows] end
  if self.onClose then self.onClose() end
end

function Window:bringToFront()
  for i, w in ipairs(gui.windows) do
    if w == self then table.remove(gui.windows, i); break end
  end
  table.insert(gui.windows, self)
  gui.focused = self
end

function Window:draw()
  gui.rect(self.x, self.y, self.w, self.h, self.bg)
  if not self.noTitle then
    gui.rect(self.x, self.y, self.w, 1, self.titleBg)
    local t = self.title
    if #t > self.w - 4 then t = t:sub(1, self.w - 4) end
    gui.text(self.x + 1, self.y, t, theme.titleText, self.titleBg)
    if self.closable then
      gui.text(self.x + self.w - 2, self.y, "X", theme.titleText, theme.closeBg)
    end
  end
  for _, wd in ipairs(self.widgets) do
    if wd.visible then wd:draw(self) end
  end
end

function Window:contains(x, y)
  return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h
end

function Window:touchLocal(x, y, btn)
  local lx, ly = x - self.x, y - self.y
  if not self.noTitle and ly == 0 then
    if self.closable and lx == self.w - 2 then self:close(); return true end
    self.dragging = true
    self.dragOffX, self.dragOffY = x - self.x, y - self.y
    return true
  end
  for i = #self.widgets, 1, -1 do
    local wd = self.widgets[i]
    if wd.visible and wd:hit(lx, ly) then
      wd._owner = self
      wd:onTouch(self, lx - wd.x, ly - wd.y, btn)
      return true
    end
  end
  gui._focusedInput = nil
  return false
end

gui.Window, gui.Button, gui.Label, gui.TextInput, gui.TextArea = Window, Button, Label, TextInput, TextArea

--------------------------------------------------------------------------
-- Диспетчеризация событий экрана/клавиатуры
-- Возвращает true, если событие было обработано GUI (перехвачено окном)
--------------------------------------------------------------------------
function gui.dispatch(name, a1, a2, a3, a4, a5)
  -- a1 = address; для touch/drag/drop/scroll: a2=x a3=y a4=btn/dir a5=player
  -- для key_down/key_up: a2=char a3=code a4=player
  if name == "touch" then
    for i = #gui.windows, 1, -1 do
      local w = gui.windows[i]
      if w:contains(a2, a3) then
        w:bringToFront()
        w:touchLocal(a2, a3, a4)
        return true
      end
    end
    return false
  elseif name == "drag" then
    for i = #gui.windows, 1, -1 do
      local w = gui.windows[i]
      if w.dragging then
        w.x = a2 - w.dragOffX
        w.y = a3 - w.dragOffY
        return true
      end
    end
  elseif name == "drop" then
    for _, w in ipairs(gui.windows) do w.dragging = false end
  elseif name == "scroll" then
    for i = #gui.windows, 1, -1 do
      local w = gui.windows[i]
      if w:contains(a2, a3) then
        local lx, ly = a2 - w.x, a3 - w.y
        for j = #w.widgets, 1, -1 do
          local wd = w.widgets[j]
          if wd.visible and wd:hit(lx, ly) then wd:onScroll(w, a4) end
        end
        return true
      end
    end
  elseif name == "key_down" then
    if gui._focusedInput then
      gui._focusedInput:onKey(gui._focusedInput._owner, a2, a3)
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------
-- Отрисовка всех окон (без фона рабочего стола — это делает init.lua)
--------------------------------------------------------------------------
function gui.drawWindows()
  for _, w in ipairs(gui.windows) do w:draw() end
end

return gui
