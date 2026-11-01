-- =============================================================================
--  BIOS do Sistema > BIOS no console
--  Esquerda: sistemas (com jogos primeiro) e o estado de cada um
--  Direita: os arquivos do sistema selecionado, onde ficam e o estado real
--  Somente leitura: instalar e substituir ficam em "Analisar e instalar".
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Bios = require("core.bios")
local Ref = require("core.bios_ref")

local S = {}

local LX, LY, LW = 12, 50, 270

function S:enter()
  self.sel, self.top, self.dscroll = 1, 0, 0
  self.rows = Bios.rows()
end
function S:resume() self.rows = Bios.rows() end

local function color(st) return T.c[(Bios.ST[st] or { "", "dim" })[2]] or T.c.dim end

function S:rh() return 44 + (T.f.bodyb:getHeight() - T.base_font(T.f.bodyb):getHeight()) + (T.f.small:getHeight() - T.base_font(T.f.small):getHeight()) end

function S:draw()
  local d = Bios.detect_dir()
  G.header(L("BIOS no console"), d.dir or "")
  local rows = self.rows
  local rh = self:rh()
  local vis = math.floor((436 - LY) / rh)
  self.vis = vis
  if self.sel > self.top + vis then self.top = self.sel - vis end
  if self.sel <= self.top then self.top = self.sel - 1 end
  for i = self.top + 1, math.min(#rows, self.top + vis) do
    local r = rows[i]
    local y = LY + (i - self.top - 1) * rh
    local on = i == self.sel
    local c = color(r.state)
    G.rect(LX, y, LW, rh - 4, on and T.c.bg3 or T.c.bg1, 6)
    if on then G.frame(LX, y, LW, rh - 4, T.c.yellow, 6, 2) end
    G.rect(LX + 6, y + 8, 4, rh - 20, c, 2)
    local ft, fs, ty, sy = G.row_fonts(rh - 4, 4, 23)
    local tag = r.games and L("COM JOGOS") or nil
    local tw = tag and (T.f.pix8:getWidth(I18N.tr(tag)) + 12) or 0
    G.text_fit(ft, r.sys.name, LX + 18, y + ty, LW - 30 - (tw > 0 and tw + 6 or 0), on and T.c.text or T.c.dim)
    if tag then G.tag(tag, LX + LW - 8 - tw, y + ty + 2, T.c.accent2, T.c.bg0, T.f.pix8) end
    local sub = I18N.tr(Bios.ST[r.state][1])
    if Bios.scan() then sub = sub .. "  •  " .. string.format(I18N.tr(L("%d de %d arquivos")), r.present, r.total) end
    G.text_fit(fs, sub, LX + 18, y + sy, LW - 30, c)
  end
  if #rows > vis then
    local track = vis * rh - 4
    local hh = math.max(16, track * vis / #rows)
    G.rect(LX + LW + 2, LY + (track - hh) * (self.top / (#rows - vis)), 3, hh, T.c.yellow, 1, 0.7)
  end
  -- detalhes do sistema
  local r = rows[self.sel]
  local px, py, pw, ph = LX + LW + 12, LY, T.W - (LX + LW + 12) - 12, 386
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  if not r then G.hints({ { "b", L("Voltar") } }); return end
  G.rect(px, py, pw, 4, color(r.state), 2)
  G.clip(px + 2, py + 6, pw - 4, ph - 8)
  local y = py + 12 - self.dscroll
  G.text_fit(T.f.h3, r.sys.name, px + 12, y, pw - 24, T.c.text)
  y = y + G.step(T.f.h3, 24)
  local tag = Bios.ST[r.state][1]
  local tw = G.tag(tag, px + 12, y, color(r.state), T.c.bg0, T.f.pix8)
  local rule = ({ all = L("a wiki pede todos"), any = L("qualquer um basta"), groups = L("um de cada grupo"),
    list = L("a wiki só lista os arquivos") })[r.sys.rule]
  G.text_fit(T.f.small, I18N.tr(rule), px + 20 + tw, y + 1, pw - 32 - tw, T.c.faint)
  y = y + 24
  for _, f in ipairs(r.files) do
    local fc = color(f.state)
    G.rect(px + 12, y + 5, 6, 6, fc, 3)
    local name = f.path:sub(1, 1) == "@" and (I18N.tr(L("ROMs/")) .. f.path:sub(2)) or f.path
    G.text_fit(T.f.bodyb, name, px + 24, y, pw - 36, f.state == "missing" and T.c.dim or T.c.text)
    y = y + G.step(T.f.bodyb, 18)
    local info = I18N.tr(Bios.ST[f.state][1])
    if f.opt and f.state ~= "optional" then info = info .. "  •  " .. I18N.tr(f.copy and L("cópia recomendada") or L("opcional")) end
    if f.e and f.e.size then info = info .. "  •  " .. U.format_bytes(f.e.size) end
    if f.e and f.e.md5 then info = info .. "  •  MD5 " .. f.e.md5:sub(1, 8) .. "…" end
    if f.p and f.state ~= "installed" then info = info .. "  •  " .. I18N.tr(f.p.verified and L("no pacote (confirmada)") or L("no pacote")) end
    G.text_fit(T.f.small, info, px + 24, y, pw - 36, fc)
    y = y + G.step(T.f.small, 18)
  end
  y = y + 6
  local notes = {}
  if r.sys.note then notes[#notes + 1] = I18N.tr(r.sys.note) end
  notes[#notes + 1] = I18N.tr(L("INSTALADA = MD5 igual a uma versão conhecida (libretro). VERIFICAÇÃO PENDENTE = o arquivo existe, mas a versão não pôde ser confirmada; o hash serve só para identificação."))
  for _, n in ipairs(notes) do
    for _, l in ipairs(G.wrap(T.f.small, n, pw - 24)) do
      G.text(T.f.small, l, px + 12, y, T.c.faint)
      y = y + G.step(T.f.small, 15)
    end
    y = y + 4
  end
  self.dmax = math.max(0, (y + self.dscroll) - (py + ph - 10))
  G.unclip()
  G.hints({ { "dpad", L("Navegar") }, { "l1", "" }, { "r1", L("Rolar detalhes") }, { "b", L("Voltar") } })
end

function S:action(act)
  local n = #self.rows
  if n == 0 then if act == "b" then App.pop() end return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1; self.dscroll = 0
  elseif act == "down" then self.sel = self.sel % n + 1; self.dscroll = 0
  elseif act == "left" then self.sel = math.max(1, self.sel - (self.vis or 8)); self.dscroll = 0
  elseif act == "right" then self.sel = math.min(n, self.sel + (self.vis or 8)); self.dscroll = 0
  elseif act == "r1" then self.dscroll = math.min(self.dmax or 0, self.dscroll + 60)
  elseif act == "l1" then self.dscroll = math.max(0, self.dscroll - 60)
  elseif act == "b" then App.pop()
  end
end

return S
