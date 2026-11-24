-- =============================================================================
--  Imagem da carta em tela cheia (Conquistas > A numa carta liberada)
--  Mostra a imagem inteira, sem cortes, com a entrada e os efeitos da raridade:
--    comum     aparece suave (esmaece e cresce um pouco)
--    incomum   sobe com um pulinho, brilho verde e faiscas subindo
--    epica     explode do centro com ondas roxas, aura pulsando e orbes girando
--    lendaria  clarao dourado, raios de luz girando atras, reflexo passando na
--              imagem e faiscas douradas na moldura
--    unica     raios arco-iris, moldura arco-iris girando, brilho holografico na
--              imagem, chuva de confete e estrelas orbitando
--  AV.draw(def, t, date)  t = segundos desde que abriu
-- =============================================================================
local T = require("ui.theme")
local G = require("ui.gfx")
local I18N = require("lib.i18n")
local L = I18N.L
local A = require("core.achievements")
local AC = require("ui.achv_card")
local lg = love.graphics

local AV = {}

local function anim() return App and App.animations and App.animations() end
local function clamp(v) return math.max(0, math.min(1, v)) end
local function ease_out(k) return 1 - (1 - k) ^ 3 end
local function ease_back(k)
  local s = 1.7
  k = k - 1
  return k * k * ((s + 1) * k + s) + 1
end
local function rnd(i) return ((i * 7919 + 104729) % 997) / 997 end

--- raios girando atras da imagem
local function rays(cx, cy, r, n, t, colfn, a)
  for i = 0, n - 1 do
    local a1 = i / n * math.pi * 2 + t
    local a2 = a1 + math.pi / n
    local c = colfn(i)
    lg.setColor(c[1], c[2], c[3], a)
    lg.polygon("fill", cx, cy, cx + math.cos(a1) * r, cy + math.sin(a1) * r, cx + math.cos(a2) * r, cy + math.sin(a2) * r)
  end
end

function AV.draw(def, t, date)
  local rar = def.rarity or "common"
  local R = A.rarity(def)
  local c = R.color
  if not anim() then t = 5 end
  local img = AC.image(def)
  -- fundo escuro
  lg.setColor(0, 0, 0, 0.88 * clamp(t / 0.2))
  lg.rectangle("fill", 0, 0, T.W, T.H)
  -- tamanho da imagem (inteira, cabendo na tela)
  local maxw, maxh = T.W - 80, T.H - 128
  local iw, ih = 200, 280
  local sc = 1
  if img then
    sc = math.min(maxw / img:getWidth(), maxh / img:getHeight())
    iw, ih = img:getWidth() * sc, img:getHeight() * sc
  end
  local cx, cy = T.W / 2, 18 + maxh / 2
  -- entrada por raridade
  local k = clamp(t / 0.45)
  local s, dy, alpha = 1, 0, 1
  if rar == "common" then s, alpha = 0.92 + 0.08 * ease_out(k), ease_out(k)
  elseif rar == "uncommon" then dy = (1 - ease_back(k)) * 120; alpha = clamp(t / 0.15)
  elseif rar == "epic" then s = math.max(0.05, ease_back(k))
  elseif rar == "legendary" then s = 0.6 + 0.4 * ease_back(k); alpha = clamp(t / 0.12)
  else s = math.max(0.05, ease_back(clamp(t / 0.55))) end
  local tt = anim() and App.t or 0
  -- fundo de efeitos (atras)
  if rar == "uncommon" then
    local p = 0.5 + 0.5 * math.sin(tt * 2.5)
    lg.setBlendMode("add")
    for g = 6, 1, -1 do
      lg.setColor(c[1], c[2], c[3], 0.05 * p * alpha)
      lg.rectangle("fill", cx - iw / 2 - g * 8, cy + dy - ih / 2 - g * 8, iw + g * 16, ih + g * 16, 16, 16)
    end
    lg.setBlendMode("alpha")
  elseif rar == "epic" then
    local p = 0.6 + 0.4 * math.sin(tt * 3)
    lg.setBlendMode("add")
    for g = 7, 1, -1 do
      lg.setColor(c[1], c[2], c[3], 0.05 * p)
      lg.ellipse("fill", cx, cy, (iw / 2 + g * 14) * s, (ih / 2 + g * 12) * s)
    end
    -- ondas de choque na entrada
    for i = 0, 2 do
      local w = clamp((t - i * 0.12) / 0.7)
      if w > 0 and w < 1 then
        lg.setColor(0.85, 0.6, 1, (1 - w) * 0.9)
        lg.setLineWidth(4 - i)
        lg.circle("line", cx, cy, 30 + w * 360)
      end
    end
    lg.setLineWidth(1)
    lg.setBlendMode("alpha")
  elseif rar == "legendary" then
    lg.setBlendMode("add")
    rays(cx, cy, 520, 16, tt * 0.25, function(i) return i % 2 == 0 and { 1, 0.8, 0.3 } or { 1, 0.95, 0.7 } end, 0.10 * alpha)
    lg.setBlendMode("alpha")
  elseif rar == "unique" then
    lg.setBlendMode("add")
    rays(cx, cy, 540, 20, tt * 0.3, function(i) local r, g, b = AC.hsv(i / 20 + tt * 0.1, 0.8, 1); return { r, g, b } end, 0.10)
    lg.setBlendMode("alpha")
  end
  -- moldura e imagem
  lg.push()
  lg.translate(cx, cy + dy)
  lg.scale(s, s)
  local fx, fy = -iw / 2, -ih / 2
  local B = 8
  if rar == "unique" then
    -- moldura arco-iris girando
    local per = 2 * (iw + ih)
    local seg, pos = 8, 0
    local function put(px, py, pw, ph)
      local r, g, b = AC.hsv(pos / per - tt * 0.3, 0.8, 1)
      lg.setColor(r, g, b, alpha)
      lg.rectangle("fill", px, py, pw, ph)
      pos = pos + math.max(pw, ph)
    end
    local x0, y0, w0, h0 = fx - B, fy - B, iw + 2 * B, ih + 2 * B
    for xx = x0, x0 + w0 - seg, seg do put(xx, y0, seg, B) end
    for yy = y0, y0 + h0 - seg, seg do put(x0 + w0 - B, yy, B, seg) end
    for xx = x0 + w0 - seg, x0, -seg do put(xx, y0 + h0 - B, seg, B) end
    for yy = y0 + h0 - seg, y0, -seg do put(x0, yy, B, seg) end
  else
    local fc = rar == "common" and { 0.95, 0.95, 0.97 } or c
    lg.setColor(0, 0, 0, 0.5 * alpha)
    lg.rectangle("fill", fx - B + 5, fy - B + 7, iw + 2 * B, ih + 2 * B, 8, 8)
    lg.setColor(fc[1], fc[2], fc[3], alpha)
    lg.rectangle("fill", fx - B, fy - B, iw + 2 * B, ih + 2 * B, 8, 8)
    lg.setColor(1, 1, 1, 0.8 * alpha)
    lg.rectangle("line", fx - 3.5, fy - 3.5, iw + 7, ih + 7, 4, 4)
  end
  if img then
    lg.setColor(1, 1, 1, alpha)
    lg.draw(img, fx, fy, 0, sc, sc)
  end
  -- efeitos por cima da imagem
  if rar == "legendary" or rar == "unique" then
    local kk = (tt * 0.5) % 1.6
    local sx = fx - 80 + kk * (iw + 160)
    G.clip(cx + (fx) * s, cy + dy + fy * s, iw * s, ih * s)
    lg.setBlendMode("add")
    lg.setColor(1, 1, 0.9, 0.25)
    lg.polygon("fill", sx, fy, sx + 40, fy, sx - 60, fy + ih, sx - 100, fy + ih)
    lg.setColor(1, 1, 0.9, 0.12)
    lg.polygon("fill", sx + 52, fy, sx + 64, fy, sx - 36, fy + ih, sx - 48, fy + ih)
    if rar == "unique" then
      for i = -3, 12 do
        local bx = fx + i * 50 + ((tt * 40) % 50) - 50
        local r, g, b = AC.hsv(i * 0.12 + tt * 0.2, 0.8, 1)
        lg.setColor(r, g, b, 0.09)
        lg.polygon("fill", bx, fy, bx + 24, fy, bx + 24 - ih * 0.5, fy + ih, bx - ih * 0.5, fy + ih)
      end
    end
    lg.setBlendMode("alpha")
    G.unclip()
  end
  lg.pop()
  -- particulas na frente
  if anim() then
    local L2, R2, T2, B2 = cx - iw / 2 * s, cx + iw / 2 * s, cy + dy - ih / 2 * s, cy + dy + ih / 2 * s
    if rar == "uncommon" then
      for i = 1, 14 do
        local sp = 30 + rnd(i) * 40
        local y = B2 - ((tt * sp + rnd(i * 3) * 300) % (B2 - T2 + 40))
        local x = L2 + rnd(i * 7) * (R2 - L2) + math.sin(tt * 2 + i) * 8
        AC.twinkle(x, y, 2 + 2 * rnd(i * 5), { 0.6, 1, 0.7 }, 0.8)
      end
    elseif rar == "epic" then
      for i = 1, 4 do
        local a = tt * 1.2 + i / 4 * math.pi * 2
        local x, y = cx + math.cos(a) * (iw / 2 * s + 26), cy + math.sin(a) * (ih / 2 * s + 18)
        lg.setBlendMode("add")
        for g = 3, 1, -1 do
          lg.setColor(c[1], c[2], c[3], 0.25)
          lg.circle("fill", x, y, 3 + g * 3)
        end
        lg.setBlendMode("alpha")
        lg.setColor(1, 1, 1, 1)
        lg.circle("fill", x, y, 3)
      end
    elseif rar == "legendary" then
      for i = 1, 10 do
        local ph = (tt * 0.7 + i * 0.31) % 1
        local side = i % 4
        local u = (i * 0.618) % 1
        local x = (side == 0 or side == 2) and (L2 + u * (R2 - L2)) or (side == 1 and R2 or L2)
        local y = (side == 1 or side == 3) and (T2 + u * (B2 - T2)) or (side == 0 and T2 or B2)
        local a = math.sin(ph * math.pi)
        AC.twinkle(x, y, 3 + 8 * a, { 1, 0.95, 0.6 }, a)
      end
      -- clarao da entrada
      if t < 0.4 then
        lg.setColor(1, 0.95, 0.7, 0.6 * (1 - t / 0.4))
        lg.rectangle("fill", 0, 0, T.W, T.H)
      end
    elseif rar == "unique" then
      -- confete caindo (forte na entrada, depois continua leve)
      local n = t < 2 and 60 or 24
      for i = 1, n do
        local fall = (tt * (60 + rnd(i) * 80) + rnd(i * 13) * T.H) % (T.H + 20) - 20
        local x = rnd(i * 7) * T.W + math.sin(tt * 2 + i) * 12
        local r, g, b = AC.hsv(rnd(i * 3), 0.7, 1)
        lg.push()
        lg.translate(x, fall)
        lg.rotate(tt * 3 + i)
        lg.setColor(r, g, b, 0.9)
        lg.rectangle("fill", -3, -1.5, 6, 3)
        lg.pop()
      end
      for i = 1, 6 do
        local a = tt * 0.8 + i / 6 * math.pi * 2
        local r, g, b = AC.hsv(i / 6 + tt * 0.2, 0.5, 1)
        AC.twinkle(cx + math.cos(a) * (iw / 2 * s + 28), cy + math.sin(a) * (ih / 2 * s + 22), 4 + 3 * math.abs(math.sin(tt * 3 + i)), { r, g, b }, 1)
      end
    end
  end
  -- nome, raridade e data embaixo
  local by = T.H - 104
  local name = I18N.tr(def.name)
  local tag = string.upper(I18N.tr(R.name))
  local tw = T.f.pix8:getWidth(tag) + 14
  lg.setColor(0.08, 0.07, 0.10, 1)
  lg.rectangle("fill", T.W / 2 - tw / 2, by, tw, 15, 7, 7)
  lg.setColor(c[1], c[2], c[3], 1)
  lg.rectangle("line", T.W / 2 - tw / 2 + 0.5, by + 0.5, tw - 1, 14, 7, 7)
  G.text(T.f.pix8, tag, T.W / 2 - tw / 2 + 7, by + 4, c)
  G.text(T.f.h3 or T.f.bodyb, name, 0, by + 18, { 1, 1, 1 }, "center", T.W)
  if date then G.text(T.f.small, date, 0, by + 42, { 0.75, 0.75, 0.8 }, "center", T.W) end
end

return AV
