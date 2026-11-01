-- =============================================================================
--  Teclado na tela (reutilizavel): App.push("textinput", {
--    title, label, value, mode = "text"|"digits", secret = bool, max,
--    validate = fn(v) -> ok, msg,  on_ok = fn(v), on_cancel = fn() })
--  A digita a tecla | B apaga | X maiusculas | Y mostra/oculta (senha)
--  L1/R1 movem o cursor do texto
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local lg = love.graphics

local S = {}

local ROWS_TEXT = {
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
  { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
  { "a", "s", "d", "f", "g", "h", "j", "k", "l", "-" },
  { "z", "x", "c", "v", "b", "n", "m", ".", "_", "@" },
  { "#SHIFT", "#APAGAR", "#OK", "#CANCELAR" },
}
local ROWS_DIGITS = {
  { "1", "2", "3", "4", "5" },
  { "6", "7", "8", "9", "0" },
  { "#APAGAR", "#OK", "#CANCELAR" },
}
-- modo "full" (ex.: senha de Wi-Fi): letras, numeros, simbolos e espaco
local ROWS_FULL = {
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
  { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
  { "a", "s", "d", "f", "g", "h", "j", "k", "l", "-" },
  { "z", "x", "c", "v", "b", "n", "m", ".", "_", "@" },
  { "#SHIFT", "#SYM", "#ESPACO", "#APAGAR", "#OK", "#CANCELAR" },
}
local ROWS_SYM = {
  { "!", "@", "#", "$", "%", "^", "&", "*", "(", ")" },
  { "-", "_", "=", "+", "[", "]", "{", "}", "\\", "|" },
  { ";", ":", "'", "\"", ",", ".", "<", ">", "/", "?" },
  { "`", "~", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
  { "#SHIFT", "#SYM", "#ESPACO", "#APAGAR", "#OK", "#CANCELAR" },
}
local SPECIAL = { ["#SHIFT"] = L("MAIÚSC."), ["#APAGAR"] = "APAGAR", ["#OK"] = "OK", ["#CANCELAR"] = L("CANCELAR"),
  ["#ESPACO"] = "ESPAÇO", ["#SYM"] = "!#1" }

function S:enter(p)
  self.p = p
  self.value = tostring(p.value or "")
  self.cursor = #self.value
  self.rows = p.mode == "digits" and ROWS_DIGITS or (p.mode == "full" and ROWS_FULL or ROWS_TEXT)
  self.sym = false
  self.r, self.c = 1, 1
  self.shift = false
  self.reveal = not p.secret
  self.err = nil
end

local function key_label(self, k)
  if k == "#SYM" then return self.sym and "abc" or "!#1" end
  if SPECIAL[k] then return SPECIAL[k] end
  if self.sym then return k end
  if self.shift then return k:upper() end
  return k
end

local function insert(self, ch)
  local max = self.p.max or 64
  if #self.value >= max then App.toast(L("Limite de ") .. max .. L(" caracteres."), "warn"); return end
  self.value = self.value:sub(1, self.cursor) .. ch .. self.value:sub(self.cursor + 1)
  self.cursor = self.cursor + 1
  self.err = nil
end

local function backspace(self)
  if self.cursor > 0 then
    self.value = self.value:sub(1, self.cursor - 1) .. self.value:sub(self.cursor + 1)
    self.cursor = self.cursor - 1
  end
  self.err = nil
end

local function confirm(self)
  if self.p.validate then
    local ok, msg = self.p.validate(self.value)
    if not ok then self.err = msg; return end
  end
  local fn, v = self.p.on_ok, self.value
  App.pop()
  if fn then fn(v) end
end

local function cancel(self)
  local fn = self.p.on_cancel
  App.pop()
  if fn then fn() end
end

function S:draw()
  G.header(self.p.title or L("Digitar"))
  local x, w = 20, T.W - 40
  G.text(T.f.bodyb, self.p.label or "", x, 52, T.c.dim)
  -- campo
  G.panel(x, 74, w, 44, { bg = T.c.bg0, border = self.err and T.c.red or T.c.accent2, lw = 2 })
  local shown = self.reveal and self.value or string.rep("*", #self.value)
  local before = self.reveal and self.value:sub(1, self.cursor) or string.rep("*", self.cursor)
  local f = T.f.h2
  local tx = x + 14
  local cw = f:getWidth(before)
  local shift = math.max(0, cw - (w - 40))
  G.clip(x + 4, 76, w - 8, 40)
  G.text(f, shown, tx - shift, 84, T.c.text)
  if math.floor(App.t * 2) % 2 == 0 then G.rect(tx - shift + cw + 1, 82, 2, 28, T.c.accent) end
  G.unclip()
  local info = #self.value .. "/" .. (self.p.max or 64)
  G.text(T.f.small, info, x + w - T.f.small:getWidth(info), 122, T.c.faint)
  if self.err then G.text_fit(T.f.small, self.err, x, 122, w - 60, T.c.red)
  elseif self.p.hint then G.text_fit(T.f.small, self.p.hint, x, 122, w - 60, T.c.faint) end

  -- teclado
  local ky = 148
  for ri, row in ipairs(self.rows) do
    local n = #row
    local gap = 6
    local kw = math.floor((w - gap * (n - 1)) / n)
    local kh = self.p.mode == "digits" and 52 or 46
    for ci, k in ipairs(row) do
      local kx = x + (ci - 1) * (kw + gap)
      local on = ri == self.r and ci == self.c
      local special = SPECIAL[k] ~= nil
      local bg = on and T.c.accent or (special and T.c.bg3 or T.c.bg2)
      if k == "#SHIFT" and self.shift and not on then bg = T.c.accent2 end
      G.rect(kx, ky, kw, kh, bg, 6)
      if not on then G.frame(kx, ky, kw, kh, T.c.line, 6) end
      local lbl = key_label(self, k)
      local font = special and T.f.bodyb or T.f.h2
      G.text(font, lbl, kx, ky + (kh - font:getHeight()) / 2, on and T.c.bg0 or T.c.text, "center", kw)
    end
    ky = ky + (self.p.mode == "digits" and 58 or 52)
  end
  local hints = { { "dpad", L("Mover") }, { "a", L("Digitar") }, { "b", L("Apagar") } }
  if self.p.mode ~= "digits" then hints[#hints + 1] = { "x", L("Maiúsculas") } end
  if self.p.secret then hints[#hints + 1] = { "y", self.reveal and L("Ocultar") or L("Mostrar") } end
  hints[#hints + 1] = { "l1", L("Cursor") }
  G.hints(hints)
end

function S:action(act)
  local rows = self.rows
  if act == "up" then
    self.r = (self.r - 2) % #rows + 1
    self.c = math.min(self.c, #rows[self.r])
  elseif act == "down" then
    self.r = self.r % #rows + 1
    self.c = math.min(self.c, #rows[self.r])
  elseif act == "left" then self.c = (self.c - 2) % #rows[self.r] + 1
  elseif act == "right" then self.c = self.c % #rows[self.r] + 1
  elseif act == "l1" then self.cursor = math.max(0, self.cursor - 1)
  elseif act == "r1" then self.cursor = math.min(#self.value, self.cursor + 1)
  elseif act == "b" then backspace(self)
  elseif act == "x" and self.p.mode ~= "digits" then self.shift = not self.shift
  elseif act == "y" and self.p.secret then self.reveal = not self.reveal
  elseif act == "a" then
    local k = rows[self.r][self.c]
    if k == "#SHIFT" then self.shift = not self.shift
    elseif k == "#SYM" then
      self.sym = not self.sym
      self.rows = self.sym and ROWS_SYM or ROWS_FULL
      rows = self.rows
      self.c = math.min(self.c, #rows[self.r])
    elseif k == "#ESPACO" then insert(self, " ")
    elseif k == "#APAGAR" then backspace(self)
    elseif k == "#OK" then confirm(self)
    elseif k == "#CANCELAR" then cancel(self)
    else insert(self, (self.shift and not self.sym) and k:upper() or k) end
  end
end

return S
