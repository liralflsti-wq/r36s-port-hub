-- =============================================================================
--  Visualizador de conquistas (Meu perfil > Conquistas)
--  Carrossel de cartas: a carta escolhida fica no centro, inteira e na
--  proporcao original; duas cartas de cada lado, menores e mais escuras.
--  Abaixo, um painel separado com nome, descricao, raridade, data e numero,
--  sempre inteiros (o texto diminui de fonte antes de ser cortado).
--  No topo, o progresso geral (liberadas / total) com barra.
--    esquerda/direita: carta anterior/proxima | L1/R1: pula 5 cartas
--    A: ver a carta em tela cheia | X: trocar o nome | B: voltar
--  So desenho e navegacao: o sistema de conquistas e o salvamento nao mudam.
--  (A versao anterior, em pasta de cartas, esta em archive/achievements_pasta_0.5.5.lua)
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local A = require("core.achievements")
local AC = require("ui.achv_card")
local lg = love.graphics

local S = {}

-- geometria (640x480)
local TOP = 46                     -- abaixo do cabecalho
local CW, CH = 140, 210            -- carta do centro (2:3)
local CY = 88                      -- topo da carta do centro
local SLOTS = {                    -- distancia do centro -> deslocamento, escala, escurecer
  [0] = { dx = 0, k = 1.0, dim = 0 },
  [1] = { dx = 138, k = 0.76, dim = 0.35 },
  [2] = { dx = 236, k = 0.58, dim = 0.6 },
}
local PX, PY, PW, PH = 14, 312, 612, 134   -- painel de informacoes

function S:enter(p)
  self.p = p or {}
  pcall(A.check_final)
  self.season = A.season(self.p.season) or A.SEASONS[#A.SEASONS]
  self.defs = A.defs_of(self.season.id)
  self.sel = 1
  -- comeca na carta liberada mais recente (ou na primeira)
  local best
  for i, d in ipairs(self.defs) do
    local at = A.unlocked(d.id)
    if at and (not best or at > best) then best = at; self.sel = i end
  end
  self.pos = self.sel              -- posicao animada do carrossel
  self.zoom = false
end

function S:update(dt)
  local k = math.min(1, dt * 12)
  if not (App.animations and App.animations()) then k = 1 end
  self.pos = self.pos + (self.sel - self.pos) * k
  if math.abs(self.sel - self.pos) < 0.002 then self.pos = self.sel end
end

-- interpola o lugar de uma carta pela distancia (fracionaria) ao centro
local function slot(dist)
  local a = math.min(2, math.abs(dist))
  local i = math.floor(a)
  local f = a - i
  local s0, s1 = SLOTS[i], SLOTS[math.min(2, i + 1)]
  local dx = s0.dx + (s1.dx - s0.dx) * f
  local k = s0.k + (s1.k - s0.k) * f
  local dim = s0.dim + (s1.dim - s0.dim) * f
  return (dist < 0 and -dx or dx), k, dim
end

local function arrow(x, y, dir, on)
  local c = on and T.c.accent or T.c.line
  lg.setColor(c[1], c[2], c[3], on and 1 or 0.5)
  if dir < 0 then lg.polygon("fill", x + 10, y - 16, x - 6, y, x + 10, y + 16)
  else lg.polygon("fill", x - 10, y - 16, x + 6, y, x - 10, y + 16) end
end

--- texto que cabe inteiro na caixa: desce de fonte ate caber (nunca corta)
local function fit_block(fonts, s, w, maxh)
  s = I18N.tr(s or "")
  for _, f in ipairs(fonts) do
    local _, lines = f:getWrap(s, w)
    local lh = f:getHeight() * f:getLineHeight()
    if #lines * lh <= maxh + 0.5 then return f, lines, lh end
  end
  local f = fonts[#fonts]
  local _, lines = f:getWrap(s, w)
  return f, lines, f:getHeight() * f:getLineHeight()
end

function S:draw_cards()
  local n = #self.defs
  local cx = T.W / 2
  local cyc = CY + CH / 2
  -- de tras para frente: as mais longe primeiro, a do centro por ultimo
  local order = {}
  for i = math.max(1, math.floor(self.pos) - 3), math.min(n, math.ceil(self.pos) + 3) do
    local dist = i - self.pos
    if math.abs(dist) <= 2.4 then order[#order + 1] = { i = i, dist = dist } end
  end
  table.sort(order, function(a, b) return math.abs(a.dist) > math.abs(b.dist) end)
  local spin = (App.animations and App.animations()) and App.t * 0.3 or 0
  for _, o in ipairs(order) do
    local d = self.defs[o.i]
    local dx, k, dim = slot(o.dist)
    local w, h = math.floor(CW * k), math.floor(CH * k)
    local x, y = math.floor(cx + dx - w / 2), math.floor(cyc - h / 2)
    local center = o.i == self.sel
    -- brilho atras da carta escolhida
    if center then
      local rc = A.unlocked(d.id) and A.rarity(d).color or T.c.accent
      for r = 3, 1, -1 do
        lg.setColor(rc[1], rc[2], rc[3], 0.08 * r)
        lg.rectangle("fill", x - r * 3, y - r * 3, w + r * 6, h + r * 6, 12, 12)
      end
    end
    AC.card(d, x, y, w, h, { on = center, locked = not A.unlocked(d.id), spin = center and spin or 0, bare = not center })
    if dim > 0.01 then
      lg.setColor(T.c.bg0[1], T.c.bg0[2], T.c.bg0[3], dim)
      lg.rectangle("fill", x, y, w, h, 8, 8)
    end
  end
  -- setas laterais
  arrow(26, cyc, -1, self.sel > 1)
  arrow(T.W - 26, cyc, 1, self.sel < n)
end

function S:draw_panel()
  local d = self.defs[self.sel]
  if not d then return end
  local at = A.unlocked(d.id)
  local r = A.rarity(d)
  local rc = at and r.color or T.c.faint
  G.panel(PX, PY, PW, PH, { bg = T.c.bg1, border = rc, lw = 2, r = 10 })
  -- faixa de cor da raridade a esquerda
  lg.setColor(rc[1], rc[2], rc[3], 1)
  lg.rectangle("fill", PX + 6, PY + 10, 4, PH - 20, 2, 2)
  local tx, tw = PX + 20, PW - 34
  -- nome
  local name = at and d.name or "???"
  local nf, nlines, nlh = fit_block({ T.f.h3, T.f.bodyb, T.f.small }, name, tw, 22)
  for k, ln in ipairs(nlines) do G.text(nf, ln, tx, PY + 10 + (k - 1) * nlh, T.c.text) end
  -- descricao (ou o enigma, se bloqueada)
  local desc = at and I18N.tr(d.desc) or (I18N.tr(L("Enigma: ")) .. I18N.tr(d.hint or L("Continue explorando o hub.")))
  local df, dlines, dlh = fit_block({ T.f.body, T.f.small }, desc, tw, 44)
  for k, ln in ipairs(dlines) do G.text(df, ln, tx, PY + 36 + (k - 1) * dlh, at and T.c.dim or T.c.faint) end
  -- linha de dados: raridade | data | numero
  local ly = PY + PH - 46
  G.color(T.c.line); lg.rectangle("fill", tx, ly - 6, tw, 1)
  local cols = {
    { L("RARIDADE"), at and I18N.tr(r.name) or I18N.tr(L("Bloqueada")), rc },
    { L("DESBLOQUEADA EM"), at and os.date("%d/%m/%Y", at) or "—", T.c.text },
    { L("CONQUISTA Nº"), string.format("%03d / %03d", self.sel, #self.defs), T.c.text },
  }
  local cw = math.floor(tw / 3)
  for k, c in ipairs(cols) do
    local x = tx + (k - 1) * cw
    if k > 1 then G.color(T.c.line); lg.rectangle("fill", x - 8, ly, 1, 34) end
    G.text_fit(T.f.pix8, I18N.tr(c[1]), x, ly + 2, cw - 14, T.c.faint)
    G.text_fit(T.f.bodyb, c[2], x, ly + 16, cw - 14, c[3])
  end
end

function S:draw()
  local got, total = A.count(self.season.id)
  G.header(L("Conquistas"), string.format("%d / %d", got, total))
  -- progresso geral
  local bx, by, bw = 14, TOP + 6, T.W - 28
  G.progress(bx, by, bw, 8, total > 0 and got / total or 0, T.c.accent)
  local pct = total > 0 and math.floor(got / total * 100 + 0.5) or 0
  local Pf = require("core.profile")
  local who = A.user_name()
  local line = string.format(I18N.tr(L("%d de %d liberadas (%d%%)")), got, total, pct)
  if who and who ~= "" then line = who .. "  ·  " .. line end
  local lx = bx
  if Pf.avatar_image() then Pf.draw(bx, by + 12, 18); lx = bx + 24 end
  G.text_fit(T.f.small, line, lx, by + 14, bw - (lx - bx), T.c.dim)
  self:draw_cards()
  self:draw_panel()
  local d = self.defs[self.sel]
  if self.zoom and d and A.unlocked(d.id) then
    require("ui.achv_view").draw(d, App.t - (self.zoom_t or App.t), nil)
    G.hints({ { "a", L("Fechar") }, { "b", L("Voltar") } })
    return
  end
  local hints = { { "dpad", L("Selecionar") }, { "l1r1", L("Pular 5") } }
  if d and A.unlocked(d.id) then hints[#hints + 1] = { "a", L("Detalhes") } end
  hints[#hints + 1] = { "x", L("Trocar nome") }
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:go(i)
  local n = #self.defs
  i = math.max(1, math.min(n, i))
  if i ~= self.sel then
    self.sel = i
    pcall(function() require("core.sfx").play("nav") end)
  end
end

function S:action(act)
  if self.zoom then
    if act == "a" or act == "b" then self.zoom = false end
    return
  end
  if act == "b" then App.pop(); return end
  if act == "x" then A.ask_name(false); return end
  if #self.defs == 0 then return end
  if act == "left" or act == "up" then self:go(self.sel - 1)
  elseif act == "right" or act == "down" then self:go(self.sel + 1)
  elseif act == "l1" then self:go(self.sel - 5)
  elseif act == "r1" then self:go(self.sel + 5)
  elseif act == "a" then
    local d = self.defs[self.sel]
    if d and A.unlocked(d.id) then self.zoom = true; self.zoom_t = App.t end
  end
end

return S
