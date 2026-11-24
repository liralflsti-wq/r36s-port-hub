-- =============================================================================
--  Meu perfil > Conquistas: os ALBUNS de temporada
--  4 albuns por ano (um por trimestre: jan-mar, abr-jun, jul-set, out-dez).
--  Cada vaga mostra o album lancado (capa = carta final, nome, data de
--  lancamento e progresso) ou "Em breve" / "Sem album" para as outras.
--  A abre o album escolhido (as cartas daquela temporada).
--    direcional: escolher | A: abrir o album | X: trocar nome | B: voltar
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
local QNAMES = { L("JAN – MAR"), L("ABR – JUN"), L("JUL – SET"), L("OUT – DEZ") }
local GX, GY, GAP = 14, 104, 8
local SW = math.floor((640 - 2 * GX - 3 * GAP) / 4)
local SH = 160

-- anos mostrados: do primeiro album ate o ano seguinte ao atual (ou ao ultimo album)
local function years()
  local first, last = tonumber(os.date("%Y")), tonumber(os.date("%Y"))
  for _, s in ipairs(A.SEASONS) do
    if s.year then first = math.min(first, s.year); last = math.max(last, s.year) end
  end
  local out = {}
  for y = first, last + 1 do out[#out + 1] = y end
  return out
end

local function slot_season(y, q)
  for _, s in ipairs(A.SEASONS) do if s.year == y and s.quarter == q then return s end end
  return nil
end

function S:enter()
  self.years = years()
  -- comeca no album mais recente
  self.yi, self.q = 1, 1
  local last = A.SEASONS[#A.SEASONS]
  for i, y in ipairs(self.years) do if last and y == last.year then self.yi, self.q = i, last.quarter or 1 end end
  self.scroll = math.max(0, self.yi - 2)
end

local function final_card(sid)
  local defs = A.defs_of(sid)
  for _, d in ipairs(defs) do if d.final then return d end end
  return defs[#defs]
end

local function first_season() return A.SEASONS[1] end

function S:draw()
  local got, total = A.count()
  G.header(L("Álbuns"), string.format(I18N.tr(L("%d de %d cartas")), got, total))
  G.panel(12, 50, T.W - 24, 46, { r = 10 })
  Icons.draw("trophy", 24, 61, T.c.yellow, 1)
  G.text(T.f.pix8, I18N.tr(L("JOGADOR")), 58, 56, T.c.faint)
  G.text_fit(T.f.bodyb, A.user_name() or I18N.tr(L("Sem nome")), 58, 68, 220, T.c.text)
  G.text_fit(T.f.small, I18N.tr(L("4 álbuns por ano: um a cada trimestre. Cada temporada traz cartas novas.")), 300, 64, T.W - 324, T.c.dim)
  local fs = first_season()
  local vis = 2
  if self.yi <= self.scroll then self.scroll = self.yi - 1 end
  if self.yi > self.scroll + vis then self.scroll = self.yi - vis end
  local now_y, now_q = tonumber(os.date("%Y")), math.floor((tonumber(os.date("%m")) - 1) / 3) + 1
  for r = 1, vis do
    local yi = self.scroll + r
    local y = self.years[yi]
    if y then
      local ry = GY + (r - 1) * (SH + 26)
      G.text(T.f.h2 or T.f.bodyb, tostring(y), GX, ry, T.c.text)
      for q = 1, 4 do
        local x, sy = GX + (q - 1) * (SW + GAP), ry + 22
        local on = (yi == self.yi and q == self.q)
        local s = slot_season(y, q)
        G.rect(x, sy, SW, SH, on and T.c.bg3 or T.c.bg1, 8)
        if on then G.frame(x, sy, SW, SH, T.c.accent, 8, 2) end
        G.text(T.f.pix8, I18N.tr(QNAMES[q]), x + 8, sy + 6, T.c.faint)
        if s then
          local got_s, tot_s = A.count(s.id)
          -- capa: a imagem da carta final do album (escura enquanto bloqueada)
          local d = final_card(s.id)
          local img = d and AC.image(d)
          local cw, ch = SW - 16, 56
          if img then
            local k = math.max(cw / img:getWidth(), ch / img:getHeight())
            G.clip(x + 8, sy + 18, cw, ch)
            local open = A.unlocked(d.id)
            lg.setColor(open and 1 or 0.18, open and 1 or 0.18, open and 1 or 0.24, 1)
            lg.draw(img, x + 8 + (cw - img:getWidth() * k) / 2, sy + 18 + (ch - img:getHeight() * k) / 2, 0, k, k)
            G.unclip()
            if not open then Icons.draw("lock", x + SW / 2 - 8, sy + 38, T.c.faint, 1) end
          else
            G.rect(x + 8, sy + 18, cw, ch, T.c.bg2 or T.c.bg0, 6)
          end
          G.frame(x + 8, sy + 18, cw, ch, got_s == tot_s and T.c.yellow or T.c.bg3, 6, 1)
          G.text_fit(T.f.bodyb, I18N.tr(s.name), x + 8, sy + 78, SW - 16, T.c.text)
          G.text_fit(T.f.small, I18N.tr(s.title), x + 8, sy + 96, SW - 16, T.c.dim)
          G.text(T.f.pix8, I18N.tr(L("LANÇADO EM")), x + 8, sy + 114, T.c.faint)
          G.text(T.f.small, A.release_label(s), x + 8, sy + 124, T.c.text)
          G.text(T.f.small, string.format("%d / %d", got_s, tot_s), x + SW - 54, sy + 124, got_s == tot_s and T.c.green or T.c.dim)
          G.progress(x + 8, sy + 144, SW - 16, 6, tot_s > 0 and got_s / tot_s or 0, got_s == tot_s and T.c.green or T.c.yellow)
        else
          local before = fs and (y < fs.year or (y == fs.year and q < fs.quarter))
          local past = (y < now_y) or (y == now_y and q < now_q)
          local label = before and L("Sem álbum") or (past and L("Sem álbum") or L("Em breve"))
          if not before and not past then Icons.draw("lock", x + SW / 2 - 8, sy + 54, T.c.faint, 1) end
          G.text(T.f.small, I18N.tr(label), x, sy + 84, T.c.faint, "center", SW)
        end
      end
    end
  end
  local s = slot_season(self.years[self.yi], self.q)
  local hints = { { "dpad", L("Navegar") } }
  if s then hints[#hints + 1] = { "a", L("Abrir álbum") } end
  hints[#hints + 1] = { "x", L("Trocar nome") }
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  if act == "b" then App.pop(); return end
  if act == "x" then A.ask_name(false); return end
  if act == "left" then self.q = math.max(1, self.q - 1)
  elseif act == "right" then self.q = math.min(4, self.q + 1)
  elseif act == "up" then self.yi = math.max(1, self.yi - 1)
  elseif act == "down" then self.yi = math.min(#self.years, self.yi + 1)
  elseif act == "a" then
    local s = slot_season(self.years[self.yi], self.q)
    if s then App.push("achievements", { season = s.id }) end
  end
end

return S
