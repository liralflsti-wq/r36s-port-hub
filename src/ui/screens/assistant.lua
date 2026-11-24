-- =============================================================================
--  Tela do assistente (L2 de qualquer tela, ou Meu perfil > Assistente)
--  Esquerda: o robo grande (vira para o lado da resposta enquanto fala).
--  Direita: a resposta (aparece digitando, com dados reais do hub) e o menu
--  de perguntas. Algumas respostas trazem um atalho (X) para resolver.
--    cima/baixo: pergunta | A: perguntar | X: atalho | L1/R1: rolar resposta
--    B: voltar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local A = require("core.assistant")
local K = require("core.assistant.knowledge")
local AV = require("ui.assistant")
local lg = love.graphics

local S = {}
local CPS = 140          -- letras por segundo do efeito de digitacao

function S:enter(p)
  self.sel = 1
  self.scroll = 0
  self:ask((p and p.topic) or "brief")
end

function S:resume() self.ans = K.answer(self.topic or "brief") end

function S:ask(id)
  self.topic = id
  self.ans = K.answer(id)
  self.t0 = App.t
  self.scroll = 0
  -- pensa um instante e aponta para a resposta
  A.play("think", 0.55)
  self.point_at = App.t + 0.55
end

function S:update()
  if self.point_at and App.t >= self.point_at then
    self.point_at = nil
    A.play("point", 1.5)
  end
end

local function wrapped(ans, w)
  local f = T.f.small
  local out = {}
  for _, line in ipairs(ans.lines or {}) do
    local _, ls = f:getWrap(I18N.tr(line), w)
    for _, l in ipairs(ls) do out[#out + 1] = l end
    if #ls == 0 then out[#out + 1] = "" end
  end
  return out
end

function S:draw()
  G.header(A.name(), I18N.tr(L("Assistente do R36S PORT HUB")))
  -- robo
  G.panel(12, 50, 214, 384, { r = 12 })
  local glow = 0.5 + 0.5 * math.sin(App.t * 1.5)
  lg.setColor(0.2, 0.6, 1, 0.08 + 0.05 * glow)
  lg.ellipse("fill", 119, 380, 90, 16)
  AV.draw(112, 376, 236, { key = "big", yaw = -0.25 })
  G.text(T.f.h2, A.name(), 12, 392, T.c.text, "center", 214)
  lg.setColor(0.3, 0.9, 0.5, 1)
  lg.circle("fill", 82, 422, 3)
  G.text(T.f.small, I18N.tr(L("Online · local")), 90, 413, T.c.dim)
  -- resposta
  local px, pw = 236, T.W - 248
  G.panel(px, 50, pw, 218, { r = 10 })
  local ans = self.ans or { lines = {} }
  G.text_fit(T.f.bodyb, I18N.tr(ans.title or ""), px + 12, 58, pw - 24, T.c.accent or T.c.text)
  local lines = wrapped(ans, pw - 28)
  local total = 0
  for _, l in ipairs(lines) do total = total + #l end
  local shown = math.floor((App.t - (self.t0 or 0)) * CPS)
  local lh = T.f.small:getHeight() + 2
  local vis = math.floor((218 - 52) / lh)
  self.max_scroll = math.max(0, #lines - vis)
  if self.scroll > self.max_scroll then self.scroll = self.max_scroll end
  local used = 0
  G.clip(px + 8, 80, pw - 16, 218 - 40)
  for i, l in ipairs(lines) do
    local cut = l
    if used + #l > shown then cut = l:sub(1, math.max(0, shown - used)):gsub("[\192-\255][\128-\191]*$", "") end
    used = used + #l
    local row = i - self.scroll
    if row >= 1 and row <= vis then
      G.text(T.f.small, cut, px + 14, 82 + (row - 1) * lh, T.c.text)
    end
    if used >= shown then break end
  end
  G.unclip()
  if self.max_scroll > 0 then G.text(T.f.pix8, "L1/R1", px + pw - 50, 252, T.c.faint) end
  -- perguntas
  local qy, rh = 276, 20
  for i, tp in ipairs(K.TOPICS) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local x = px + col * (pw / 2 + 2)
    local y = qy + row * (rh + 22)
    local w = pw / 2 - 2
    local on = i == self.sel
    G.rect(x, y, w, rh + 18, on and T.c.bg3 or T.c.bg1, 8)
    if on then G.frame(x, y, w, rh + 18, T.c.accent, 8, 2) end
    G.text_fit(T.f.small, I18N.tr(tp.q), x + 10, y + 10, w - 20, (tp.id == self.topic) and T.c.yellow or T.c.text)
  end
  local hints = { { "dpad", L("Escolher") }, { "a", L("Perguntar") } }
  if ans.go then hints[#hints + 1] = { "x", ans.go[1] } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local n = #K.TOPICS
  if act == "b" or act == "l2" then App.pop(); return end
  if act == "up" then self.sel = self.sel > 2 and self.sel - 2 or self.sel
  elseif act == "down" then self.sel = self.sel + 2 <= n and self.sel + 2 or self.sel
  elseif act == "left" then self.sel = ((self.sel - 1) % 2 == 1) and self.sel - 1 or self.sel
  elseif act == "right" then self.sel = ((self.sel - 1) % 2 == 0 and self.sel < n) and self.sel + 1 or self.sel
  elseif act == "a" then self:ask(K.TOPICS[self.sel].id)
  elseif act == "x" and self.ans and self.ans.go then pcall(self.ans.go[2])
  elseif act == "l1" then self.scroll = math.max(0, self.scroll - 3)
  elseif act == "r1" then self.scroll = math.min(self.max_scroll or 0, self.scroll + 3)
  end
end

return S
