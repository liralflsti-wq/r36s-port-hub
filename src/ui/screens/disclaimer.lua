-- Tela de aviso inicial obrigatorio (exibida sempre antes de entrar na loja)
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")

local S = {}

local PARAGRAPHS = {
  L("Bem-vindo ao R36S PORT HUB!"),
  L("Este projeto é uma iniciativa independente, criada por fãs e para fãs do console R36S, com o objetivo de facilitar o acesso, a organização e a descoberta de ports de jogos."),
  L("Não somos desenvolvedores, proprietários ou representantes dos jogos e ports disponibilizados por terceiros."),
  L("Não nos responsabilizamos pela criação, funcionamento, conteúdo, distribuição ou eventuais problemas relacionados aos jogos e ports de terceiros."),
  L("Todos os direitos pertencem aos seus respectivos desenvolvedores e detentores de propriedade intelectual. Respeite as licenças e os direitos autorais de cada projeto."),
  L("Feito pela comunidade, para a comunidade!"),
}

function S:on_language() self:build() end

function S:enter(p)
  self.from_language = p and p.from_language
  self:build()
end

function S:build()
  self.t = self.t or 0
  self.blocks = {}
  local w = 548
  for i, p in ipairs(PARAGRAPHS) do
    local font = (i == 1 or i == #PARAGRAPHS) and T.f.bodyb or T.f.body
    self.blocks[i] = { font = font, lines = G.wrap(font, p, w), first = i == 1, last = i == #PARAGRAPHS }
  end
end

function S:update(dt) self.t = self.t + dt end

function S:draw()
  local x, y, w, h = 26, 18, T.W - 52, T.H - 36
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.yellow, lw = 2, r = 12 })
  G.rect(x, y, w, 6, T.c.yellow, 3)

  -- titulo com icone de alerta
  local ty = y + 24
  local ix = x + 24
  love.graphics.setColor(T.c.yellow)
  love.graphics.polygon("fill", ix + 11, ty - 2, ix + 23, ty + 18, ix - 1, ty + 18)
  G.text(T.f.pix8, "!", ix + 8, ty + 8, T.c.bg0)
  G.text(T.f.pix16, L("AVISO IMPORTANTE"), ix + 36, ty + 2, T.c.yellow)

  local cy = ty + 38
  for _, b in ipairs(self.blocks) do
    local lh = b.font:getHeight() * b.font:getLineHeight()
    local color = b.first and T.c.accent2 or (b.last and T.c.accent or T.c.text)
    for _, l in ipairs(b.lines) do
      G.text(b.font, l, x + 22, cy, color)
      cy = cy + lh
    end
    cy = cy + 7
  end

  -- botao
  local bw, bh = 400, 42
  local bx, by = (T.W - bw) / 2, y + h - bh - 18
  -- pulso decorativo: parado com animacoes desligadas ou no modo economico
  local pulse = App.animations() and (0.5 + 0.5 * math.sin(self.t * 4)) or 0.5
  G.rect(bx - 3, by - 3, bw + 6, bh + 6, T.c.accent, 10, 0.25 + 0.25 * pulse)
  G.rect(bx, by, bw, bh, T.c.accent, 8)
  -- icone do A + texto, centralizados juntos
  local label = L("PARA CONTINUAR")
  local tw = T.f.pix16:getWidth(label)
  local gx = bx + (bw - (16 + 12 + tw)) / 2
  G.button_icon("a", gx, by + 13, T.c.text)
  G.text(T.f.pix16, label, gx + 28, by + 13, T.c.bg0)
end

function S:action(act)
  if act == "a" then
    App.disclaimer_accepted()
  elseif act == "b" and self.from_language then
    App.reset_to("language", { first = true })   -- volta para a escolha de idioma
  end
end

return S
