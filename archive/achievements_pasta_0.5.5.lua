-- =============================================================================
--  Album de cartas (Meu perfil > Conquistas), no estilo das pastas de cartas
--  colecionaveis: uma pasta aberta com duas paginas, 4 bolsos em cada pagina
--  (8 cartas por vez). As bloqueadas aparecem com cadeado e "???".
--  Sem datas: ano e lancamento so aparecem na tela de albuns, quando houver
--  mais de uma temporada.
--    direcional: escolher carta (passar da borda vira a pagina)
--    L1/R1: virar a pagina | A: ver a carta inteira | X: trocar o nome | B: voltar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local Icons = require("ui.icons")
local A = require("core.achievements")
local AC = require("ui.achv_card")
local lg = love.graphics

local S = {}
local PER = 8                       -- cartas por pagina dupla (2 paginas x 2x2)
local BX, BY, BW, BH = 10, 48, 620, 378
local PW = 290                      -- largura de cada pagina
local PKW, PKH, PGAP = 124, 168, 10 -- bolso
local FLIP = 0.28                   -- tempo da virada de pagina

function S:enter(p)
  self.p = p or {}
  pcall(A.check_final)
  self.season = A.season(self.p.season) or A.SEASONS[#A.SEASONS]
  self.defs = A.defs_of(self.season.id)
  self.sel = 1
  self.zoom = false
  self.flip_t, self.flip_dir = -9, 1
end

local function spreads(n) return math.max(1, math.ceil(n / PER)) end

-- posicao de um bolso: pagina 0 (esquerda) ou 1 (direita), coluna e linha
local function pocket_xy(slot)
  local side = math.floor(slot / 4)
  local k = slot % 4
  local c, r = k % 2, math.floor(k / 2)
  local px = (side == 0) and (BX + 14) or (BX + BW - 14 - PW)
  local x = px + math.floor((PW - (2 * PKW + PGAP)) / 2) + c * (PKW + PGAP)
  local y = BY + 14 + r * (PKH + PGAP)
  return x, y
end

local function draw_binder(self, sp, nsp)
  -- capa (couro escuro com costura)
  lg.setColor(0.10, 0.11, 0.17, 1)
  lg.rectangle("fill", BX, BY, BW, BH, 12, 12)
  lg.setColor(0.20, 0.22, 0.32, 1)
  lg.setLineWidth(1)
  for i = 0, math.floor((BW - 24) / 10) do
    local x = BX + 12 + i * 10
    lg.line(x, BY + 5, x + 5, BY + 5); lg.line(x, BY + BH - 5, x + 5, BY + BH - 5)
  end
  -- paginas
  for side = 0, 1 do
    local px = (side == 0) and (BX + 14) or (BX + BW - 14 - PW)
    lg.setColor(0.16, 0.17, 0.24, 1)
    lg.rectangle("fill", px, BY + 8, PW, BH - 16, 6, 6)
    lg.setColor(0.22, 0.24, 0.34, 1)
    lg.rectangle("line", px + 0.5, BY + 8.5, PW - 1, BH - 17, 6, 6)
  end
  -- lombada com argolas
  local cx = BX + BW / 2
  lg.setColor(0.07, 0.08, 0.12, 1)
  lg.rectangle("fill", cx - 9, BY + 8, 18, BH - 16)
  for _, ry in ipairs({ BY + 60, BY + BH / 2, BY + BH - 60 }) do
    lg.setColor(0.55, 0.58, 0.66, 1)
    lg.setLineWidth(3)
    lg.ellipse("line", cx, ry, 13, 7)
    lg.setLineWidth(1)
    lg.setColor(0.85, 0.88, 0.95, 0.6)
    lg.arc("line", "open", cx, ry, 12, math.pi * 1.1, math.pi * 1.6)
  end
  -- numero das paginas
  local ny = BY + BH - 15
  G.text(T.f.pix8, string.format("%d", sp * 2 + 1), BX + 14, ny, T.c.faint, "center", PW)
  G.text(T.f.pix8, string.format("%d", sp * 2 + 2), BX + BW - 14 - PW, ny, T.c.faint, "center", PW)
  if sp > 0 then G.text(T.f.pix8, "< L1", BX + 22, ny, T.c.accent) end
  if sp < nsp - 1 then G.text(T.f.pix8, "R1 >", BX + BW - 56, ny, T.c.accent) end
end

local function draw_pocket(x, y, d, on, spin)
  -- fundo do bolso
  lg.setColor(0.08, 0.09, 0.13, 1)
  lg.rectangle("fill", x, y, PKW, PKH, 5, 5)
  if d then
    AC.card(d, x + 5, y + 5, PKW - 10, PKH - 10, { on = on, locked = not A.unlocked(d.id), spin = spin })
  end
  -- plastico: brilho diagonal e a borda de cima do bolso
  lg.setColor(1, 1, 1, 0.07)
  lg.polygon("fill", x + PKW * 0.15, y, x + PKW * 0.45, y, x + PKW * 0.05, y + PKH, x - 0, y + PKH * 0.75, x, y + PKH * 0.35)
  lg.setColor(1, 1, 1, 0.10)
  lg.rectangle("line", x + 0.5, y + 0.5, PKW - 1, PKH - 1, 5, 5)
  lg.setColor(1, 1, 1, 0.16)
  lg.line(x + 4, y + 18, x + PKW - 4, y + 18)
end

function S:draw()
  local season = self.season
  local got, total = A.count(season.id)
  G.header(L("Álbum de cartas"), I18N.tr(season.name) .. " · " .. I18N.tr(season.title) .. "   " .. string.format("%d / %d", got, total))
  local n = #self.defs
  local nsp = spreads(n)
  local sp = math.floor((self.sel - 1) / PER)
  -- virada de pagina: as paginas deslizam e aparecem
  local k = math.min(1, (App.t - self.flip_t) / FLIP)
  local anim = App.animations() and k < 1
  if anim then
    lg.push()
    local e = 1 - (1 - k) ^ 3
    lg.translate(self.flip_dir * (1 - e) * 40, 0)
  end
  draw_binder(self, sp, nsp)
  local spin = App.animations() and App.t * 0.3 or 0
  for slot = 0, PER - 1 do
    local i = sp * PER + slot + 1
    local x, y = pocket_xy(slot)
    draw_pocket(x, y, self.defs[i], i == self.sel, (i == self.sel) and spin or 0)
  end
  if anim then
    lg.pop()
    lg.setColor(T.c.bg0[1], T.c.bg0[2], T.c.bg0[3], (1 - k) * 0.6)
    lg.rectangle("fill", BX, BY, BW, BH, 12, 12)
  end
  -- carta escolhida: nome e raridade (ou o enigma, se bloqueada)
  local d = self.defs[self.sel]
  if d then
    local locked = not A.unlocked(d.id)
    local y = BY + BH + 6
    local Pf = require("core.profile")
    local tx = BX + 4
    if Pf.avatar_image() then
      Pf.draw(BX + 2, y - 3, 22)
      tx = BX + 30
    end
    local line
    if locked then
      line = "???  ·  " .. I18N.tr(L("Enigma: ")) .. I18N.tr(d.hint or L("Continue explorando o hub."))
    else
      line = I18N.tr(d.name) .. "  ·  " .. I18N.tr(A.rarity(d).name) .. "  ·  " .. I18N.tr(d.desc)
    end
    G.text_fit(T.f.small, line, tx, y, BX + BW - 4 - tx, locked and T.c.faint or T.c.dim)
  end
  if self.zoom and d and A.unlocked(d.id) then
    require("ui.achv_view").draw(d, App.t - (self.zoom_t or App.t), nil)
    G.hints({ { "a", L("Fechar") }, { "b", L("Voltar") } })
    return
  end
  local hints = { { "dpad", L("Navegar") }, { "l1r1", L("Virar página") } }
  if d and A.unlocked(d.id) then hints[#hints + 1] = { "a", L("Ver carta") } end
  hints[#hints + 1] = { "x", L("Trocar nome") }
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:goto(i, dir)
  local n = #self.defs
  i = math.max(1, math.min(n, i))
  local old = math.floor((self.sel - 1) / PER)
  self.sel = i
  local new = math.floor((i - 1) / PER)
  if new ~= old then
    self.flip_t, self.flip_dir = App.t, dir or (new > old and 1 or -1)
    pcall(function() require("core.sfx").play("nav") end)
  end
end

function S:action(act)
  local n = #self.defs
  if self.zoom then
    if act == "a" or act == "b" then self.zoom = false end
    return
  end
  if act == "b" then App.pop(); return end
  if act == "x" then A.ask_name(false); return end
  if n == 0 then return end
  local sp = math.floor((self.sel - 1) / PER)
  local slot = (self.sel - 1) % PER
  local side, kk = math.floor(slot / 4), slot % 4
  local col, row = side * 2 + kk % 2, math.floor(kk / 2)   -- col 0..3 na pagina dupla
  local function idx(s, c, r)
    local sd = math.floor(c / 2)
    return s * PER + sd * 4 + r * 2 + (c % 2) + 1
  end
  if act == "left" then
    if col > 0 then self:goto(idx(sp, col - 1, row))
    elseif sp > 0 then self:goto(idx(sp - 1, 3, row), -1) end
  elseif act == "right" then
    local j = idx(sp, col + 1, row)
    if col < 3 and j <= n then self:goto(j)
    elseif sp < spreads(n) - 1 then self:goto(math.min(n, idx(sp + 1, 0, row)), 1) end
  elseif act == "up" then
    if row > 0 then self:goto(idx(sp, col, 0)) end
  elseif act == "down" then
    local j = idx(sp, col, 1)
    if row == 0 and j <= n then self:goto(j) end
  elseif act == "l1" then
    if sp > 0 then self:goto(idx(sp - 1, col, row), -1) end
  elseif act == "r1" then
    if sp < spreads(n) - 1 then self:goto(math.min(n, idx(sp + 1, col, row)), 1) end
  elseif act == "a" then
    local d = self.defs[self.sel]
    if d and A.unlocked(d.id) then self.zoom = true; self.zoom_t = App.t end
  end
end

return S
