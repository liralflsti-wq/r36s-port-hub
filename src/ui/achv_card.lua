-- =============================================================================
--  Cartas das conquistas (usado pela tela de Conquistas e pela comemoracao)
--    AC.image(def)               imagem da carta (cache; nil se nao houver)
--    AC.art(def, x, y, w, h)     fundo com raios na cor da raridade + imagem
--                                inteira (nunca corta: imagens com fundo viram
--                                adesivo com borda branca)
--    AC.card(def, x, y, w, h, o) carta inteira: moldura da raridade, arte,
--                                faixa da raridade, nome e data;
--                                o = { on = bool, locked = bool, date = texto }
--  Molduras por raridade:
--    comum     prata, lisa
--    incomum   verde, com fio de luz por dentro
--    epica     roxa, brilho pulsando em volta e gemas nos cantos
--    lendaria  dourada em degrade, reflexo correndo e faiscas piscando
--    unica     borda arco-iris girando, brilho holografico na arte e estrelas
--              orbitando a carta
-- =============================================================================
local T = require("ui.theme")
local G = require("ui.gfx")
local Icons = require("ui.icons")
local I18N = require("lib.i18n")
local L = I18N.L
local A = require("core.achievements")
local lg = love.graphics

local AC = {}
local IMGS = {}

local function anim() return App and App.animations and App.animations() end
local function now() return anim() and App.t or 0 end

function AC.image(def)
  if not def or not def.card then return nil end
  local v = IMGS[def.card]
  if v == nil then
    local ok, im = pcall(lg.newImage, def.card)
    v = ok and im or false
    if v then v:setFilter("linear", "linear") end
    IMGS[def.card] = v
  end
  return v or nil
end

local function hsv(h, s, v)
  h = (h % 1) * 6
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v else return v, p, q end
end
AC.hsv = hsv

--- estrela de 4 pontas
local function twinkle(x, y, r, c, a)
  lg.setColor(c[1], c[2], c[3], a)
  lg.polygon("fill", x, y - r, x + r * 0.22, y - r * 0.22, x + r, y, x + r * 0.22, y + r * 0.22,
    x, y + r, x - r * 0.22, y + r * 0.22, x - r, y, x - r * 0.22, y - r * 0.22)
end
AC.twinkle = twinkle

--- arte da carta: degrade e raios na cor da conquista, imagem encaixada embaixo
function AC.art(def, x, y, w, h, spin)
  local c = def.color or { 1, 0.7, 0.2 }
  G.clip(x, y, w, h)
  for i = 0, h - 1, 2 do
    local k = i / h
    lg.setColor(c[1] * (0.25 + 0.5 * k), c[2] * (0.25 + 0.5 * k), c[3] * (0.25 + 0.5 * k), 1)
    lg.rectangle("fill", x, y + i, w, 2)
  end
  local cx, cy = x + w / 2, y + h * 0.55
  local r = math.max(w, h)
  for i = 0, 11 do
    local a1 = i / 12 * math.pi * 2 + (spin or 0)
    local a2 = a1 + math.pi / 12
    lg.setColor(1, 1, 1, 0.10)
    lg.polygon("fill", cx, cy, cx + math.cos(a1) * r, cy + math.sin(a1) * r, cx + math.cos(a2) * r, cy + math.sin(a2) * r)
  end
  local img = AC.image(def)
  if img and def.fill then
    -- imagem com fundo: inteira (sem cortar), como um adesivo com borda branca
    local pad = math.max(3, math.floor(math.min(w, h) * 0.05))
    local bw = math.max(2, math.floor(pad * 0.5))
    local sc = math.min((w - 2 * pad - 2 * bw) / img:getWidth(), (h - 2 * pad - 2 * bw) / img:getHeight())
    local iw, ih = img:getWidth() * sc, img:getHeight() * sc
    local ix, iy = x + (w - iw) / 2, y + (h - ih) / 2
    lg.setColor(0, 0, 0, 0.45)
    lg.rectangle("fill", ix - bw + 2, iy - bw + 3, iw + 2 * bw, ih + 2 * bw, 3, 3)
    lg.setColor(0.05, 0.04, 0.04, 1)
    lg.rectangle("fill", ix - bw - 1, iy - bw - 1, iw + 2 * bw + 2, ih + 2 * bw + 2, 3, 3)
    lg.setColor(1, 1, 1, 1)
    lg.rectangle("fill", ix - bw, iy - bw, iw + 2 * bw, ih + 2 * bw, 2, 2)
    lg.draw(img, ix, iy, 0, sc, sc)
  elseif img then
    local sc = math.min((w - 6) / img:getWidth(), (h - 4) / img:getHeight())
    local iw, ih = img:getWidth() * sc, img:getHeight() * sc
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, x + (w - iw) / 2, y + h - ih, 0, sc, sc)
  else
    Icons.draw("trophy", cx - 24, cy - 24, { 1, 1, 1 }, 2)
  end
  G.unclip()
end

-- ---------------------------------------------------------------------------
-- molduras
local B = 6   -- largura da faixa da moldura

local function frame_flat(x, y, w, h, c, k)
  lg.setColor(c[1] * k, c[2] * k, c[3] * k, 1)
  lg.rectangle("fill", x, y, w, h, 8, 8)
end

local function frame_gold(x, y, w, h)
  G.clip(x, y, w, h)
  for i = 0, h - 1, 2 do
    local k = i / h
    local m = 1 - math.abs(k - 0.3) * 1.3
    lg.setColor(0.62 + 0.38 * m, 0.40 + 0.50 * m, 0.08 + 0.45 * m, 1)
    lg.rectangle("fill", x, y + i, w, 2)
  end
  G.unclip()
end

local function frame_rainbow(x, y, w, h, t)
  -- faixa arco-iris girando em volta da carta (segmentos pelo perimetro)
  local per = 2 * (w + h)
  local seg = 6
  local pos = 0
  local function put(px, py, pw, ph)
    local r, g, b = hsv(pos / per - t * 0.25, 0.75, 1)
    lg.setColor(r, g, b, 1)
    lg.rectangle("fill", px, py, pw, ph)
    pos = pos + math.max(pw, ph)
  end
  for xx = x, x + w - seg, seg do put(xx, y, seg, B) end
  for yy = y, y + h - seg, seg do put(x + w - B, yy, B, seg) end
  for xx = x + w - seg, x, -seg do put(xx, y + h - B, seg, B) end
  for yy = y + h - seg, y, -seg do put(x, yy, B, seg) end
end

--- moldura + brilho de fundo; devolve a cor de destaque da raridade
local function draw_frame(def, x, y, w, h, locked)
  local R = A.rarity(def)
  local c = R.color
  local t = now()
  lg.setColor(0, 0, 0, 0.45)
  lg.rectangle("fill", x + 3, y + 4, w, h, 8, 8)
  if locked then
    frame_flat(x, y, w, h, { 0.30, 0.30, 0.36 }, 0.6)
    lg.setColor(0.12, 0.12, 0.15, 1)
    lg.rectangle("fill", x + B, y + B, w - 2 * B, h - 2 * B, 5, 5)
    return { 0.45, 0.45, 0.52 }
  end
  local rar = def.rarity
  if rar == "epic" or rar == "unique" then
    local p = anim() and (0.5 + 0.5 * math.sin(t * (rar == "epic" and 3 or 2))) or 0.6
    lg.setBlendMode("add")
    for g = 4, 1, -1 do
      local r, gg, b = c[1], c[2], c[3]
      if rar == "unique" then r, gg, b = hsv(t * 0.2 + g * 0.1, 0.7, 1) end
      lg.setColor(r, gg, b, 0.06 * p)
      lg.rectangle("fill", x - g * 3, y - g * 3, w + g * 6, h + g * 6, 10 + g, 10 + g)
    end
    lg.setBlendMode("alpha")
  end
  if rar == "legendary" then frame_gold(x, y, w, h)
  elseif rar == "unique" then
    lg.setColor(0.1, 0.1, 0.12, 1)
    lg.rectangle("fill", x, y, w, h, 8, 8)
    frame_rainbow(x, y, w, h, t)
  else frame_flat(x, y, w, h, c, 1) end
  -- miolo claro (fundo do nome)
  lg.setColor(0.98, 0.96, 0.92, 1)
  lg.rectangle("fill", x + B, y + B, w - 2 * B, h - 2 * B, 5, 5)
  -- fio de luz (incomum em diante)
  if rar ~= "common" then
    lg.setColor(1, 1, 1, rar == "uncommon" and 0.55 or 0.85)
    lg.rectangle("line", x + B - 2.5, y + B - 2.5, w - 2 * B + 5, h - 2 * B + 5, 6, 6)
  end
  -- gemas nos cantos (epica)
  if rar == "epic" then
    for _, p in ipairs({ { x + 4, y + 4 }, { x + w - 4, y + 4 }, { x + 4, y + h - 4 }, { x + w - 4, y + h - 4 } }) do
      lg.setColor(1, 1, 1, 1)
      lg.polygon("fill", p[1], p[2] - 4, p[1] + 4, p[2], p[1], p[2] + 4, p[1] - 4, p[2])
      lg.setColor(c[1], c[2], c[3], 1)
      lg.polygon("fill", p[1], p[2] - 2.5, p[1] + 2.5, p[2], p[1], p[2] + 2.5, p[1] - 2.5, p[2])
    end
  end
  return c
end

--- efeitos por cima da carta (reflexo, holografia, faiscas, estrelas)
local function draw_fx(def, x, y, w, h, ax, ay, aw, ah)
  if not anim() then return end
  local t = App.t
  local rar = def.rarity
  if rar == "legendary" or rar == "unique" then
    local k = (t * 0.45) % 1.8
    local sx = x - 60 + k * (w + 120)
    G.clip(x, y, w, h)
    lg.setBlendMode("add")
    lg.setColor(1, 1, 0.9, 0.22)
    lg.polygon("fill", sx, y, sx + 26, y, sx - 34, y + h, sx - 60, y + h)
    lg.setColor(1, 1, 0.9, 0.12)
    lg.polygon("fill", sx + 34, y, sx + 42, y, sx - 18, y + h, sx - 26, y + h)
    lg.setBlendMode("alpha")
    G.unclip()
  end
  if rar == "unique" then
    G.clip(ax, ay, aw, ah)
    lg.setBlendMode("add")
    for i = -2, 8 do
      local bx = ax + i * 40 + ((t * 30) % 40) - 40
      local r, g, b = hsv(i * 0.15 + t * 0.2, 0.8, 1)
      lg.setColor(r, g, b, 0.10)
      lg.polygon("fill", bx, ay, bx + 18, ay, bx + 18 - ah * 0.5, ay + ah, bx - ah * 0.5, ay + ah)
    end
    lg.setBlendMode("alpha")
    G.unclip()
    local cx, cy = x + w / 2, y + h / 2
    for i = 1, 5 do
      local a = t * 0.9 + i / 5 * math.pi * 2
      local r, g, b = hsv(i / 5 + t * 0.2, 0.5, 1)
      twinkle(cx + math.cos(a) * (w / 2 + 6), cy + math.sin(a) * (h / 2 + 6), 3 + 2 * math.abs(math.sin(t * 3 + i)), { r, g, b }, 0.95)
    end
  elseif rar == "legendary" then
    for i = 1, 6 do
      local ph = (t * 0.8 + i * 0.37) % 1
      local side = i % 4
      local u = (i * 0.618) % 1
      local px = (side == 0 or side == 2) and (x + u * w) or (side == 1 and x + w or x)
      local py = (side == 1 or side == 3) and (y + u * h) or (side == 0 and y or y + h)
      local a = math.sin(ph * math.pi)
      twinkle(px, py, 2 + 5 * a, { 1, 0.95, 0.6 }, a)
    end
  end
end

--- carta inteira
function AC.card(def, x, y, w, h, o)
  o = o or {}
  local locked = o.locked
  local R = A.rarity(def)
  local hc = draw_frame(def, x, y, w, h, locked)
  local ax, ay, aw = x + B + 3, y + B + 3, w - 2 * B - 6
  local nh = math.max(34, math.floor(h * 0.24))
  local ah = h - 2 * B - 6 - nh
  if locked then
    lg.setColor(0.07, 0.07, 0.09, 1)
    lg.rectangle("fill", ax, ay, aw, ah, 4, 4)
    local sz = math.min(aw, ah) * 0.42
    Icons.draw("lock", ax + aw / 2 - sz / 2, ay + ah / 2 - sz / 2, { 0.45, 0.45, 0.52 }, sz / 24)
  else
    AC.art(def, ax, ay, aw, ah, o.spin)
    lg.setColor(0, 0, 0, 0.35)
    lg.rectangle("line", ax + 0.5, ay + 0.5, aw - 1, ah - 1, 3, 3)
  end
  -- faixa da raridade (no pe da arte; a bloqueada nao mostra)
  local rname = locked and "" or string.upper(I18N.tr(R.name))
  local rw = T.f.pix8:getWidth(rname) + 12
  local rx, ry = x + (w - rw) / 2, ay + ah - 7
  if not locked then
    lg.setColor(0.08, 0.07, 0.10, 1)
    lg.rectangle("fill", rx, ry, rw, 13, 6, 6)
    lg.setColor(hc[1], hc[2], hc[3], 1)
    lg.rectangle("line", rx + 0.5, ry + 0.5, rw - 1, 12, 6, 6)
    G.text(T.f.pix8, rname, rx + 6, ry + 3, hc)
  end
  -- nome e data (o.bare: sem textos, para cartas pequenas do carrossel)
  if o.bare then
    if not locked then draw_fx(def, x, y, w, h, ax, ay, aw, ah) end
    return
  end
  local ny = ry + 15
  local name = locked and "???" or I18N.tr(def.name)
  local f = G.fit(w < 150 and T.f.small or T.f.bodyb, name, aw - 4)
  local tc = locked and { 0.55, 0.55, 0.62 } or { 0.10, 0.07, 0.05 }
  G.text(f, name, ax, ny, tc, "center", aw)
  if o.date and not locked then
    G.text(T.f.pix8, o.date, ax, ny + 2 + f:getHeight(), { 0.35, 0.30, 0.25 }, "center", aw)
  elseif locked then
    G.text(T.f.pix8, I18N.tr(L("BLOQUEADA")), ax, ny + 2 + f:getHeight(), { 0.45, 0.45, 0.52 }, "center", aw)
  end
  if not locked then draw_fx(def, x, y, w, h, ax, ay, aw, ah) end
  if o.on then
    local p = anim() and App.pulse(0.7, 0.3, 2.5) or 1
    lg.setColor(T.c.accent[1], T.c.accent[2], T.c.accent[3], p)
    lg.setLineWidth(3)
    lg.rectangle("line", x - 4, y - 4, w + 8, h + 8, 10, 10)
    lg.setLineWidth(1)
  end
end

return AC
