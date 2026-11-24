-- =============================================================================
--  Comemoracao de conquista liberada (aparece uma vez, em qualquer tema)
--  A imagem da carta pula no canto inferior direito com raios de quadrinho
--  girando atras e o grito da conquista (ex.: "INSTALADO!"); embaixo, a faixa
--  "CONQUISTA DESBLOQUEADA" com o nome. Some sozinha em ~3,5 s e nao bloqueia
--  os botoes (a janela que estiver aberta continua funcionando).
-- =============================================================================
local T = require("ui.theme")
local G = require("ui.gfx")
local Icons = require("ui.icons")
local I18N = require("lib.i18n")
local L = I18N.L
local AC = require("ui.achv_card")
local lg = love.graphics

local P = { t0 = nil, def = nil, queue = {} }
local DUR = 3.6

local function anim() return App and App.animations and App.animations() end

function P.show(def)
  if not def then return end
  -- uma comemoracao de cada vez: a proxima espera a atual terminar
  if P.t0 and App.t - P.t0 < DUR then P.queue[#P.queue + 1] = def; return end
  P.def, P.t0 = def, App.t
  -- som de conquista (muda com a raridade)
  pcall(function() require("core.sfx").achievement(def.rarity) end)
end

local function ease_back(k)
  local s = 1.9
  k = k - 1
  return k * k * ((s + 1) * k + s) + 1
end

local function outlined(f, txt, x, y, c, o)
  for dx = -o, o do
    for dy = -o, o do
      if dx * dx + dy * dy >= o * o - 1 then G.text(f, txt, x + dx, y + dy, { 0, 0, 0, 1 }) end
    end
  end
  G.text(f, txt, x, y, c)
end

function P.draw()
  if not P.t0 then return end
  local def = P.def
  local t = App.t - P.t0
  if t >= DUR then
    P.t0 = nil
    local nxt = table.remove(P.queue, 1)
    if nxt then P.show(nxt) end
    return
  end
  local img = AC.image(def)
  local k_in = anim() and math.min(1, t / 0.38) or 1
  local k_out = anim() and math.max(0, (t - (DUR - 0.4)) / 0.4) or 0
  local sc = anim() and ease_back(k_in) or 1
  local SC = 1
  local w, h = 130, 190
  if img then
    SC = math.min(w / img:getWidth(), h / img:getHeight())
    w, h = img:getWidth() * SC, img:getHeight() * SC
  end
  local x = T.W - w / 2 - 30
  local y = T.H - h / 2 - 66 + (1 - k_in) * 160 + k_out * 280
  local c = def.color or { 1, 0.75, 0.2 }
  -- raios girando atras
  if k_out < 1 then
    local a = (1 - k_out) * math.min(1, t / 0.2)
    lg.push()
    lg.translate(x, y)
    lg.rotate(anim() and t * 0.6 or 0)
    local r = h * 0.85 * sc
    for i = 0, 15 do
      local a1 = i / 16 * math.pi * 2
      local a2 = a1 + math.pi / 16
      if i % 2 == 0 then lg.setColor(c[1], c[2], c[3], 0.6 * a) else lg.setColor(1, 1, 0.92, 0.55 * a) end
      lg.polygon("fill", 0, 0, math.cos(a1) * r, math.sin(a1) * r, math.cos(a2) * r, math.sin(a2) * r)
    end
    lg.pop()
  end
  -- adesivo (imagem da carta) com sombra
  local rot = -0.14 + (anim() and math.sin(t * 9) * 0.04 * math.max(0, 1 - t / 1.2) or 0)
  lg.push()
  lg.translate(x, y)
  lg.rotate(rot)
  lg.scale(sc, sc)
  if img and def.fill then
    -- imagem com fundo: vira um adesivo retangular com borda branca e contorno
    lg.setColor(0, 0, 0, 0.45)
    lg.rectangle("fill", -w / 2 - 6 + 6, -h / 2 - 6 + 8, w + 12, h + 12, 10, 10)
    lg.setColor(0.06, 0.05, 0.05, 1)
    lg.rectangle("fill", -w / 2 - 7, -h / 2 - 7, w + 14, h + 14, 11, 11)
    lg.setColor(1, 1, 1, 1)
    lg.rectangle("fill", -w / 2 - 5, -h / 2 - 5, w + 10, h + 10, 9, 9)
    lg.draw(img, -w / 2, -h / 2, 0, SC, SC)
  elseif img then
    lg.setColor(0, 0, 0, 0.45)
    lg.draw(img, -w / 2 + 6, -h / 2 + 8, 0, SC, SC)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, -w / 2, -h / 2, 0, SC, SC)
  else
    Icons.draw("trophy", -36, -36, { 1, 0.85, 0.2 }, 3)
  end
  lg.pop()
  -- grito da conquista em cima
  local shout = I18N.tr(def.shout or L("CONQUISTA!"))
  local f = T.f.h1 or T.f.h2
  local tw = f:getWidth(shout)
  local tx = math.min(T.W - tw - 14, x - tw / 2)
  local ty = y - h / 2 * sc - f:getHeight() * 0.6 + (anim() and math.sin(t * 7) * 2 or 0)
  local pop = anim() and math.min(1, math.max(0, (t - 0.2) / 0.2)) or 1
  if pop > 0 then
    lg.push()
    lg.translate(tx + tw / 2, ty + f:getHeight() / 2)
    lg.rotate(-0.08)
    lg.scale(pop, pop)
    outlined(f, shout, -tw / 2, -f:getHeight() / 2, { 1, 0.86, 0.12, 1 }, 3)
    lg.pop()
  end
  -- faixa "CONQUISTA DESBLOQUEADA" com o nome
  local bk = anim() and math.min(1, math.max(0, (t - 0.3) / 0.25)) or 1
  local bo = k_out
  if bk > 0 then
    local R = require("core.achievements").rarity(def)
    local head = I18N.tr(L("CONQUISTA DESBLOQUEADA")) .. "  ·  " .. string.upper(I18N.tr(R.name))
    local name = I18N.tr(def.name)
    local nf = T.f.bodyb
    local bw = math.max(T.f.pix8:getWidth(head), nf:getWidth(name)) + 64
    local bh = 44
    local bx = T.W - bw - 14 + (1 - bk) * (bw + 30) + bo * (bw + 30)
    local by = T.H - bh - 12 - 34
    lg.setColor(0, 0, 0, 0.55)
    lg.rectangle("fill", bx + 3, by + 4, bw, bh, 8, 8)
    lg.setColor(0.08, 0.07, 0.10, 0.96)
    lg.rectangle("fill", bx, by, bw, bh, 8, 8)
    lg.setColor(c[1], c[2], c[3], 1)
    lg.setLineWidth(2)
    lg.rectangle("line", bx + 1, by + 1, bw - 2, bh - 2, 8, 8)
    lg.setLineWidth(1)
    Icons.draw("trophy", bx + 10, by + bh / 2 - 12, { 1, 0.84, 0.2 }, 1)
    G.text(T.f.pix8, head, bx + 44, by + 7, c)
    G.text(nf, name, bx + 44, by + 19, { 1, 1, 1 })
  end
end

return P
