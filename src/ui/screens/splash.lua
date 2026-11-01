-- =============================================================================
--  Tela de abertura: logo, nome, slogan, BETA e carregamento REAL
--  Cada etapa da inicializacao roda em um quadro; a barra mostra quantas
--  etapas ja terminaram (nada de porcentagem inventada ou espera artificial).
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local C = require("config")
local lg = love.graphics

local S = {}
local SLOGAN = "Your Port. Your Console. Your Adventure."

function S:enter(p)
  self.steps = p.steps or {}
  self.i = 0
  self.msg = L("Iniciando...")
  self.done = false
  self.on_done = p.on_done
end

function S:update()
  if self.done then return end
  -- desenha o quadro atual antes de rodar a proxima etapa
  if self.drawn then
    self.i = self.i + 1
    local st = self.steps[self.i]
    if st then
      self.msg = st[1]
      local ok, e = pcall(st[2])
      if not ok then print("[porthub] etapa de inicializacao falhou: " .. tostring(st[1]) .. ": " .. tostring(e)) end
    else
      self.done = true
      if self.on_done then self.on_done() end
      return
    end
  end
end

function S:draw()
  self.drawn = true
  -- logo centralizada
  local img_w, img_h = 252, 170
  local lx = (T.W - img_w) / 2
  G.logo(lx, 70, "splash")
  G.text(T.f.pix16, "R36S PORT HUB", 0, 258, T.c.text, "center", T.W)
  G.text(T.f.body, SLOGAN, 0, 284, T.c.accent2, "center", T.W)
  local tag = C.VERSION
  local tw = T.f.pix8:getWidth(tag) + 12
  G.tag(tag, (T.W - tw) / 2, 308, T.c.accent, T.c.bg0, T.f.pix8)
  -- barra de carregamento (etapas concluidas / total)
  local n = math.max(1, #self.steps)
  local frac = math.min(1, math.max(0, self.i) / n)
  G.progress(170, 372, T.W - 340, 10, frac, T.c.accent)
  G.text(T.f.small, self.msg or "", 0, 392, T.c.dim, "center", T.W)
end

function S:action() end   -- nada a fazer durante o carregamento

return S
