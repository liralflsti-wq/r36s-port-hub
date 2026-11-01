-- Configuracoes > categoria: lista de opcoes com interruptores, sliders,
-- escolhas e acoes (definidas em ui/settings_defs.lua)
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local Icons = require("ui.icons")
local Defs = require("ui.settings_defs")
local lg = love.graphics

local S = {}

local X, W = 16, 640 - 32
local LIST_Y, ROW_H, GAP, VISIBLE = 50, 42, 4, 6
local FOOT_Y = LIST_Y + VISIBLE * (ROW_H + GAP) + 4

local function txt(v, scr)
  if type(v) == "function" then return v(scr) end
  return v
end

function S:enter(p)
  self.cat = Defs.BY_ID[p.id]
  self.sel, self.top = 1, 0
  if self.cat.enter then self.cat.enter(self) end
  self:rebuild()
end

function S:rebuild()
  local r = self.cat.rows
  self.rows = type(r) == "function" and r(self) or r
  if self.sel > #self.rows then self.sel = #self.rows end
end

function S:resume()
  if self.cat.resume then self.cat.resume(self) end
end

function S:on_language() self:rebuild() end

function S:update(dt)
  if self.cat.update then self.cat.update(dt, self) end
end

local function color(name) return T.c[name] or T.c.accent end

-- chevron ">" discreto
local function chevron(x, y, c)
  G.color(c)
  lg.setLineWidth(2)
  lg.line(x, y, x + 5, y + 5, x, y + 10)
  lg.setLineWidth(1)
end

-- interruptor: [ estado (o) ]
local function switch(xr, y, on, dim)
  local sw, sh = 46, 22
  local sx = xr - sw
  G.rect(sx, y, sw, sh, on and T.c.green or T.c.bg0, 11, dim and 0.45 or 1)
  G.frame(sx, y, sw, sh, on and T.c.green or T.c.line, 11)
  G.color(on and T.c.bg0 or T.c.faint, dim and 0.6 or 1)
  lg.circle("fill", on and (sx + sw - 11) or (sx + 11), y + sh / 2, 8)
  local lbl = on and L("LIGADO") or L("DESLIGADO")
  local lw = T.f.pix8:getWidth(lbl)
  G.text(T.f.pix8, lbl, sx - 10 - lw, y + 7, dim and T.c.faint or (on and T.c.green or T.c.dim))
  return sx - 10 - lw
end

-- slider: [────●────] 70%
local function slider(xr, y, v, minv, dim, c)
  local pct = string.format("%d%%", v)
  local pw = 46
  G.text(T.f.bodyb, pct, xr - pw, y + 2, dim and T.c.faint or T.c.text, "right", pw)
  local tw = 150
  local tx = xr - pw - 12 - tw
  local f = (v - minv) / (100 - minv)
  f = math.max(0, math.min(1, f))
  G.rect(tx, y + 8, tw, 6, T.c.bg0, 3)
  G.frame(tx, y + 8, tw, 6, T.c.line, 3)
  G.rect(tx, y + 8, math.max(6, tw * f), 6, c, 3, dim and 0.45 or 1)
  G.color(dim and T.c.faint or T.c.text)
  lg.circle("fill", tx + tw * f, y + 11, 8)
  return tx
end

function S:draw()
  local cat = self.cat
  G.header(cat.name, L("Configurações"))
  local ccol = color(cat.color)

  if self.sel > self.top + VISIBLE then self.top = self.sel - VISIBLE end
  if self.sel <= self.top then self.top = self.sel - 1 end

  local y = LIST_Y
  for i = self.top + 1, math.min(#self.rows, self.top + VISIBLE) do
    local r = self.rows[i]
    local on = i == self.sel
    local dim = r.enabled and not r.enabled(self)
    G.panel(X, y, W, ROW_H, { bg = on and T.c.bg3 or T.c.bg1, border = on and ccol or T.c.line, lw = on and 2 or 1 })
    if on then G.rect(X, y + 8, 4, ROW_H - 16, ccol, 2) end
    local xr = X + W - 14
    local left = xr      -- onde comeca o controle (para o rotulo nao encostar)
    local cy = y + (ROW_H - 22) / 2
    if r.kind == "toggle" then
      left = switch(xr, cy, r.get(self), dim)
    elseif r.kind == "slider" then
      if r.available and not r.available() then
        local tag = L("INDISPONÍVEL")
        local tw = T.f.pix8:getWidth(tag) + 12
        G.tag(tag, xr - tw, cy + 2, T.c.red, T.c.bg0, T.f.pix8)
        left = xr - tw
      else
        left = slider(xr, cy, r.get(self), r.min or 0, dim, ccol)
      end
    elseif r.kind == "value" and r.nudge then
      -- escolha com esquerda/direita:  < VALOR >
      local v = txt(r.value, self) or ""
      local tw = T.f.pix8:getWidth(require("lib.i18n").tr(v)) + 12
      local ac = on and ccol or T.c.faint
      G.color(ac)
      lg.polygon("fill", xr, cy + 11, xr - 6, cy + 6, xr - 6, cy + 16)
      G.tag(v, xr - 14 - tw, cy + 2, on and ccol or T.c.accent2, T.c.bg0, T.f.pix8)
      G.color(ac)
      lg.polygon("fill", xr - 28 - tw, cy + 11, xr - 22 - tw, cy + 6, xr - 22 - tw, cy + 16)
      left = xr - 28 - tw
    elseif r.kind == "value" then
      chevron(xr - 6, cy + 6, on and ccol or T.c.faint)
      local v = txt(r.value, self) or ""
      local tw = T.f.pix8:getWidth(require("lib.i18n").tr(v)) + 12
      G.tag(v, xr - 16 - tw, cy + 2, on and ccol or T.c.accent2, T.c.bg0, T.f.pix8)
      left = xr - 16 - tw
    elseif r.kind == "action" then
      chevron(xr - 6, cy + 6, on and ccol or T.c.faint)
      left = xr - 16
      local v = r.value and txt(r.value, self)
      if v and v ~= "" then
        local maxw = 220
        local vw = math.min(maxw, T.f.small:getWidth(v))
        G.text_fit(T.f.small, v, left - 6 - vw, cy + 4, maxw, T.c.dim)
        left = left - 6 - vw
      end
    elseif r.kind == "info" then
      local v = txt(r.value, self) or ""
      local lw = T.f.bodyb:getWidth(txt(r.label, self))
      local maxw = W - 28 - lw - 24
      local vw = math.min(maxw, T.f.bodyb:getWidth(v))
      G.text_fit(T.f.bodyb, v, xr - vw, cy + 2, maxw, r.color and r.color(self) or T.c.text)
      left = xr - vw
    end
    local lx = X + 16
    if r.icon then
      Icons.draw(r.icon, lx, cy - 1, on and ccol or T.c.dim, 1)
      lx = lx + 32
    end
    G.text_fit(T.f.bodyb, txt(r.label, self), lx, cy + 2, left - lx - 12,
      dim and T.c.faint or (on and T.c.text or T.c.dim))
    y = y + ROW_H + GAP
  end

  -- barra de rolagem
  if #self.rows > VISIBLE then
    local track = VISIBLE * (ROW_H + GAP) - GAP
    local hh = track * VISIBLE / #self.rows
    G.rect(T.W - 8, LIST_Y + (track - hh) * (self.top / (#self.rows - VISIBLE)), 3, hh, ccol, 1, 0.7)
  end

  -- descricao da opcao selecionada
  local r = self.rows[self.sel]
  local fh = 436 - FOOT_Y
  G.panel(X, FOOT_Y, W, fh, { bg = T.c.bg1 })
  G.rect(X, FOOT_Y, 4, fh, ccol, 2)
  Icons.draw(cat.icon, X + 16, FOOT_Y + 12, ccol, 1)
  if r then
    G.text_fit(T.f.bodyb, txt(r.label, self), X + 52, FOOT_Y + 10, W - 70, T.c.text)
    -- descricao: com texto maior, a fonte desce ate caber; se nao couber, encurta
    local ty = FOOT_Y + 12 + math.max(20, T.f.bodyb:getHeight())
    local df, lines, dlh = G.fit_lines(T.f.small, txt(r.desc, self) or "", W - 70, FOOT_Y + fh - 6 - ty, true)
    for k = 1, #lines do
      G.text(df, lines[k], X + 52, ty + (k - 1) * dlh, T.c.dim)
    end
  end

  local hints = { { "dpad", L("Navegar") } }
  if r and (r.kind == "slider" or (r.kind == "value" and r.nudge)) then hints[1] = { "dpad", L("Ajustar") } end
  if r and r.kind == "toggle" then hints[#hints + 1] = { "a", L("Alternar") }
  elseif r and r.kind == "value" and r.nudge then hints[#hints + 1] = { "a", L("Alternar") }
  elseif r and (r.kind == "value" or r.kind == "action") then hints[#hints + 1] = { "a", L("Abrir") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local n = #self.rows
  local r = self.rows[self.sel]
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "b" then App.pop()
  elseif not r then return
  elseif r.kind == "toggle" and (act == "a" or act == "left" or act == "right") then
    if r.enabled and not r.enabled(self) then return end
    local cur = r.get(self)
    local want = cur
    if act == "a" then want = not cur elseif act == "left" then want = false else want = true end
    if want ~= cur then r.set(want, self) end
  elseif r.kind == "value" and r.nudge and (act == "left" or act == "right" or act == "a") then
    if r.enabled and not r.enabled(self) then return end
    -- A avanca e volta ao primeiro depois do ultimo
    r.nudge(act == "left" and -1 or 1, act == "a")
  elseif r.kind == "slider" and (act == "left" or act == "right") then
    if r.enabled and not r.enabled(self) then return end
    r.nudge(act == "left" and -1 or 1, self)
  elseif r.kind == "slider" and act == "a" and r.available and not r.available() then
    r.nudge(1, self)
  elseif (r.kind == "value" or r.kind == "action") and act == "a" then
    if r.enabled and not r.enabled(self) then return end
    r.on_a(self)
  end
end

return S
