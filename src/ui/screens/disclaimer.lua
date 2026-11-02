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
  self.scroll = 0
  self.blocks = {}
  local w = 548
  local total = 0
  for i, p in ipairs(PARAGRAPHS) do
    local font = (i == 1 or i == #PARAGRAPHS) and T.f.bodyb or T.f.body
    local lines = G.wrap(font, p, w)
    local lh = font:getHeight() * font:getLineHeight()
    self.blocks[i] = { font = font, lines = lines, lh = lh, first = i == 1, last = i == #PARAGRAPHS }
    total = total + #lines * lh + 7
  end
  self.content_h = total
end

-- tamanho do texto mudou (Configuracoes): refaz as linhas
function S:on_font() self:build() end

function S:update(dt) self.t = self.t + dt end

--- area do texto (entre o titulo e o botao)
local function area()
  local x, y, w, h = 26, 18, T.W - 52, T.H - 36
  local ty = y + 24
  local bh = 42
  local by = y + h - bh - 18
  local top = ty + 38
  local bottom = by - 14
  return x, y, w, h, ty, top, bottom, by
end

function S:max_scroll()
  local _, _, _, _, _, top, bottom = area()
  return math.max(0, math.ceil(self.content_h - (bottom - top)))
end

function S:draw()
  local x, y, w, h, ty, top, bottom, by = area()
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.yellow, lw = 2, r = 12 })
  G.rect(x, y, w, 6, T.c.yellow, 3)

  -- titulo com icone de alerta
  local ix = x + 24
  love.graphics.setColor(T.c.yellow)
  love.graphics.polygon("fill", ix + 11, ty - 2, ix + 23, ty + 18, ix - 1, ty + 18)
  G.text(T.f.pix8, "!", ix + 8, ty + 8, T.c.bg0)
  G.text(T.f.pix16, L("AVISO IMPORTANTE"), ix + 36, ty + 2, T.c.yellow)

  -- texto: com letra grande ele pode passar da area; entao rola (direcional)
  local maxs = self:max_scroll()
  self.scroll = math.max(0, math.min(self.scroll or 0, maxs))
  G.clip(x + 4, top, w - 8, bottom - top)
  local cy = top - self.scroll
  for _, b in ipairs(self.blocks) do
    local color = b.first and T.c.accent2 or (b.last and T.c.accent or T.c.text)
    for _, l in ipairs(b.lines) do
      if cy + b.lh >= top and cy <= bottom then G.text(b.font, l, x + 22, cy, color) end
      cy = cy + b.lh
    end
    cy = cy + 7
  end
  G.unclip()
  if maxs > 0 then
    -- barra de rolagem e setas: ha mais texto acima/abaixo
    local track = bottom - top
    local hh = math.max(20, track * track / self.content_h)
    G.rect(x + w - 12, top + (track - hh) * (self.scroll / maxs), 4, hh, T.c.yellow, 2, 0.8)
    G.color(T.c.yellow)
    local ax = x + w / 2
    if self.scroll > 0 then love.graphics.polygon("fill", ax, top - 8, ax - 7, top - 1, ax + 7, top - 1) end
    if self.scroll < maxs then love.graphics.polygon("fill", ax, bottom + 9, ax - 7, bottom + 2, ax + 7, bottom + 2) end
  end

  -- botao (sempre no mesmo lugar, nunca coberto pelo texto)
  local bw, bh = 400, 42
  local bx = (T.W - bw) / 2
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
  if act == "down" or act == "up" then
    local step = (T.f.body:getHeight() * T.f.body:getLineHeight()) * 2
    self.scroll = math.max(0, math.min(self:max_scroll(), (self.scroll or 0) + (act == "down" and step or -step)))
  elseif act == "a" then
    App.disclaimer_accepted()
  elseif act == "b" and self.from_language then
    App.reset_to("language", { first = true })   -- volta para a escolha de idioma
  end
end

return S
