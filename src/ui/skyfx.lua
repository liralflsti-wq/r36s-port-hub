-- =============================================================================
--  Efeitos dos temas Sky Warriors e Moonlight Blade (arte original, em codigo)
--  Moonlight Blade: brasas vermelhas subindo, petalas caindo, corte de energia
--  ao apertar A e golpe de espada cortando a tela na abertura.
--  Sky Warriors:
--    - nuvens que andam devagar pelo ceu
--    - rastro de luz cruzando o ceu de vez em quando
--    - faiscas de energia subindo da opcao escolhida (ui/themeviews.lua)
--    - brilho de "carregar poder" ao apertar A
--    - impacto na tela de abertura (ui/screens/splash.lua)
--  Com "Animações da interface" desligado, as nuvens ficam paradas e os outros
--  efeitos nao aparecem.
-- =============================================================================
local T = require("ui.theme")
local lg = love.graphics

local FX = {}

local function is_blade() return T.style.background == "blade" end
function FX.on()
  local b = T.style.background
  return b == "sky" or b == "blade"
end
local function anim() return App and App.animations and App.animations() end

-- ---------------------------------------------------------------------------
-- Nuvens: cada uma desenhada uma vez numa imagem pequena (leve no R36S)
local CLOUD_W, CLOUD_H = 150, 80
local cloud_img
local function make_cloud()
  local cv = lg.newCanvas(CLOUD_W, CLOUD_H)
  local prev = lg.getCanvas()
  lg.push("all")
  lg.setCanvas(cv)
  lg.clear(0, 0, 0, 0)
  lg.origin()
  local cx, cy, s = 62, 50, 1
  local puffs = { { -1.0, 0.15, 0.55 }, { -0.45, -0.2, 0.75 }, { 0.25, -0.35, 0.9 }, { 0.95, -0.05, 0.65 }, { 1.45, 0.2, 0.45 } }
  lg.setColor(0.55, 0.72, 0.92, 0.55)
  for _, p in ipairs(puffs) do lg.circle("fill", cx + p[1] * 30 * s, cy + p[2] * 30 * s + 6 * s, p[3] * 30 * s) end
  lg.setColor(1, 1, 1, 0.94)
  for _, p in ipairs(puffs) do lg.circle("fill", cx + p[1] * 30 * s, cy + p[2] * 30 * s, p[3] * 30 * s) end
  lg.setColor(1, 1, 1, 1)
  lg.rectangle("fill", cx - 30 * s, cy, 76 * s, 14 * s)
  lg.pop()
  lg.setCanvas(prev)
  cv:setFilter("linear", "linear")
  return cv
end

-- x inicial, y, escala, opacidade, velocidade (px/s)
local CLOUDS = {
  { 400, 70, 1.25, 0.95, 4.0 },
  { 560, 165, 0.9, 0.85, 6.5 },
  { 250, 30, 0.7, 0.6, 2.5 },
  { 40, 250, 1.0, 0.7, 5.0 },
  { 330, 235, 0.65, 0.65, 3.2 },
  { -120, 120, 0.55, 0.5, 7.5 },
}

--- desenha o que fica por cima do fundo fixo (chamado logo depois do fundo)
local function blade_back()
  local t = (anim() and App.t) or 0
  -- brasas vermelhas subindo devagar
  for i = 1, 22 do
    local sp = 10 + (i % 5) * 4
    local x = ((i * 89) % T.W) + math.sin(t * 0.8 + i) * 12
    local y = T.H - ((t * sp + i * 41) % (T.H + 40))
    local a = 0.35 + 0.35 * math.sin(t * 2 + i)
    lg.setColor(1, 0.25, 0.15, a * 0.4)
    lg.circle("fill", x, y, 3)
    lg.setColor(1, 0.6, 0.4, a)
    lg.circle("fill", x, y, 1.2)
  end
  -- petalas caindo na diagonal
  for i = 1, 9 do
    local sp = 14 + (i % 3) * 6
    local x = ((i * 137 + t * sp * 0.8) % (T.W + 60)) - 30
    local y = ((i * 53 + t * sp) % (T.H + 40)) - 20
    local r = t * (1 + i % 3) + i
    lg.push()
    lg.translate(x, y)
    lg.rotate(r)
    lg.setColor(0.85, 0.12, 0.18, 0.75)
    lg.ellipse("fill", 0, 0, 4, 2)
    lg.pop()
  end
end

function FX.draw_back()
  if not FX.on() then return end
  if is_blade() then return blade_back() end
  if not cloud_img then cloud_img = make_cloud() end
  local t = (anim() and App.t) or 0
  local span = T.W + CLOUD_W * 1.4
  for _, c in ipairs(CLOUDS) do
    local x = ((c[1] + t * c[5]) + CLOUD_W) % span - CLOUD_W * 1.3
    lg.setColor(1, 1, 1, c[4])
    lg.draw(cloud_img, x, c[2], 0, c[3], c[3])
  end
  if not anim() then return end
  -- rastro de luz cruzando o ceu a cada 11 segundos (dura 1,3 s)
  local period, dur = 11, 1.3
  local k = (App.t % period) / dur
  if k < 1 then
    local x0, y0, x1, y1 = -60, 40, T.W + 60, 150
    local hx, hy = x0 + (x1 - x0) * k, y0 + (y1 - y0) * k
    local tail = 140
    local dx, dy = (x1 - x0), (y1 - y0)
    local len = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / len, dy / len
    for i = 10, 1, -1 do
      local a = (1 - i / 10) * 0.9 * (1 - k * 0.3)
      lg.setColor(1, 0.95, 0.7, a * 0.35)
      lg.setLineWidth(i * 0.8)
      lg.line(hx - dx * tail * (i / 10), hy - dy * tail * (i / 10), hx, hy)
    end
    lg.setLineWidth(1)
    for g = 6, 1, -1 do
      lg.setColor(1, 0.9, 0.5, 0.08)
      lg.circle("fill", hx, hy, g * 2.2)
    end
    lg.setColor(1, 1, 1, 0.95)
    lg.circle("fill", hx, hy, 2.5)
  end
end

-- ---------------------------------------------------------------------------
-- Faiscas subindo de uma barra escolhida (x, y, largura, altura)
function FX.sparks(x, y, w, h)
  if not (FX.on() and anim()) then return end
  local t = App.t
  if is_blade() then
    -- fagulhas vermelhas saindo do fio da lamina
    for i = 1, 8 do
      local ph = (t * (0.9 + (i % 3) * 0.3) + i * 0.173) % 1
      local sx = x + 16 + ((i * 61) % math.max(1, math.floor(w - 30))) + ph * 8
      local sy = y + h * 0.8 - ph * (h + 10)
      local a = (1 - ph)
      lg.setColor(1, 0.1, 0.15, a * 0.5)
      lg.circle("fill", sx, sy, 3.5)
      lg.setColor(1, 0.85, 0.8, a)
      lg.circle("fill", sx, sy, 1.3)
    end
    return
  end
  for i = 1, 10 do
    local ph = (t * (0.7 + (i % 3) * 0.25) + i * 0.137) % 1
    local sx = x + 20 + ((i * 53) % math.max(1, math.floor(w - 30))) + math.sin(t * 3 + i) * 3
    local sy = y + h - ph * (h + 22)
    local a = (1 - ph) * 0.9
    lg.setColor(1, 0.45, 0.05, a * 0.55)
    lg.circle("fill", sx, sy, 4.5)
    lg.setColor(1, 1, 1, a)
    lg.circle("fill", sx, sy, 2.0)
  end
end

-- ---------------------------------------------------------------------------
-- "Carregar poder" ao apertar A: ondas de luz saindo da opcao escolhida.
-- Desenhado por cima de tudo, entao continua visivel quando a tela muda.
FX.focus = nil      -- centro da ultima opcao escolhida (x, y), gravado pelas barras

local burst
local BURST = 0.45
function FX.on_action(act)
  if act == "a" and FX.on() and anim() and FX.focus then
    burst = { x = FX.focus[1], y = FX.focus[2], t0 = App.t }
  end
end

local function slash(cx, cy, k, len, thick)
  -- corte de energia na diagonal: linha branca com nucleo e brilho vermelho
  local ang = -0.55
  local dx, dy = math.cos(ang), math.sin(ang)
  local grow = math.min(1, k * 3)                   -- o corte se abre rapido
  local fade = 1 - math.max(0, (k - 0.35) / 0.65)   -- e some devagar
  local l = len * grow
  local x0, y0 = cx - dx * l, cy - dy * l
  local x1, y1 = cx + dx * l, cy + dy * l
  for g = 6, 1, -1 do
    lg.setColor(0.95, 0.08, 0.15, 0.10 * fade)
    lg.setLineWidth(thick + g * 5)
    lg.line(x0, y0, x1, y1)
  end
  lg.setColor(1, 0.35, 0.35, 0.8 * fade)
  lg.setLineWidth(thick + 2)
  lg.line(x0, y0, x1, y1)
  lg.setColor(1, 1, 1, fade)
  lg.setLineWidth(math.max(1, thick * 0.5))
  lg.line(x0, y0, x1, y1)
  lg.setLineWidth(1)
  -- fagulhas espalhadas ao longo do corte
  for j = 1, 16 do
    local tt = (j / 16) * 2 - 1
    local px, py = cx + dx * l * tt, cy + dy * l * tt
    local off = (j % 2 == 0 and 1 or -1) * (6 + (j * 7) % 18) * grow
    lg.setColor(1, 0.5 + (j % 3) * 0.15, 0.4, fade * 0.9)
    lg.circle("fill", px - dy * off, py + dx * off, 1.5 + (j % 3) * 0.6)
  end
end
FX.slash = slash

function FX.draw_front()
  if not burst then return end
  local k = (App.t - burst.t0) / BURST
  if k >= 1 or not FX.on() then burst = nil; return end
  if is_blade() then
    lg.setColor(1, 0.9, 0.9, 0.12 * (1 - k))
    lg.rectangle("fill", 0, 0, T.W, T.H)
    slash(burst.x, burst.y, k, 360, 5)
    return
  end
  local e = 1 - (1 - k) ^ 2
  -- clarao rapido na tela toda
  lg.setColor(1, 0.95, 0.75, 0.22 * (1 - k))
  lg.rectangle("fill", 0, 0, T.W, T.H)
  -- aneis de energia
  for i = 0, 2 do
    local r = 12 + e * (90 + i * 50)
    lg.setColor(1, 0.80 - i * 0.12, 0.25, (1 - k) * (0.9 - i * 0.25))
    lg.setLineWidth(4 - i)
    lg.circle("line", burst.x, burst.y, r)
  end
  lg.setLineWidth(1)
  -- raios curtos em volta
  for j = 0, 11 do
    local a = j / 12 * math.pi * 2
    local r1, r2 = 18 + e * 50, 30 + e * 110
    lg.setColor(1, 0.95, 0.6, (1 - k) * 0.8)
    lg.setLineWidth(2)
    lg.line(burst.x + math.cos(a) * r1, burst.y + math.sin(a) * r1, burst.x + math.cos(a) * r2, burst.y + math.sin(a) * r2)
  end
  lg.setLineWidth(1)
end

-- ---------------------------------------------------------------------------
-- Impacto na tela de abertura: clarao branco, ondas de choque e tremida da logo.
-- t = segundos desde que a abertura apareceu. Devolve o deslocamento da logo.
FX.SPLASH_MIN = 1.3   -- tempo minimo da abertura com o efeito (os dois temas)
function FX.splash_shake(t)
  if not (FX.on() and anim()) then return 0, 0 end
  if is_blade() then
    if t < 0.35 or t > 0.7 then return 0, 0 end
    local k = 1 - (t - 0.35) / 0.35
    return math.sin(t * 80) * 4 * k, 0
  end
  if t < 0.15 or t > 0.6 then return 0, 0 end
  local k = 1 - (t - 0.15) / 0.45
  return math.sin(t * 90) * 6 * k, math.cos(t * 70) * 4 * k
end

function FX.splash_fx(t, cx, cy)
  if not (FX.on() and anim()) then return end
  if is_blade() then
    -- 0 a 0,3 s: tela preta com o corte atravessando; depois as metades se
    -- separam e somem, mostrando a abertura por baixo
    if t < 0.30 then
      lg.setColor(0, 0, 0, 1)
      lg.rectangle("fill", 0, 0, T.W, T.H)
      slash(cx, T.H / 2, t / 0.30 * 0.34, 520, 6)
      return
    end
    local k = (t - 0.30) / 0.8
    if k >= 1 then return end
    local e = k ^ 1.6
    local ang = -0.55
    local dx, dy = math.cos(ang), math.sin(ang)
    local nx, ny = -dy, dx
    local push = e * 260
    -- duas metades pretas deslizando para lados opostos do corte
    for side = -1, 1, 2 do
      local ox, oy = nx * push * side, ny * push * side
      local L = 900
      local x0, y0 = cx - dx * L, T.H / 2 - dy * L
      local x1, y1 = cx + dx * L, T.H / 2 + dy * L
      lg.setColor(0, 0, 0, 1 - e * 0.6)
      lg.polygon("fill", x0 + ox, y0 + oy, x1 + ox, y1 + oy, x1 + ox + nx * L * side, y1 + oy + ny * L * side,
        x0 + ox + nx * L * side, y0 + oy + ny * L * side)
    end
    slash(cx, T.H / 2, 0.34 + k * 0.66, 520, 6)
    return
  end
  -- energia juntando antes do impacto (0 a 0,15 s)
  if t < 0.15 then
    local k = t / 0.15
    for i = 1, 14 do
      local a = i / 14 * math.pi * 2
      local r = 220 * (1 - k)
      lg.setColor(1, 0.9, 0.5, 0.8 * k)
      lg.circle("fill", cx + math.cos(a) * r, cy + math.sin(a) * r, 3)
    end
    return
  end
  local k = (t - 0.15) / 0.9
  if k >= 1 then return end
  -- clarao branco
  lg.setColor(1, 1, 1, math.max(0, 0.85 - k * 2.2))
  lg.rectangle("fill", 0, 0, T.W, T.H)
  -- ondas de choque
  for i = 0, 2 do
    local kk = math.max(0, k - i * 0.12)
    local r = 20 + kk * (380 + i * 60)
    lg.setColor(1, 0.82, 0.3, (1 - kk) * 0.8)
    lg.setLineWidth(6 - i * 2)
    lg.circle("line", cx, cy, r)
  end
  lg.setLineWidth(1)
  -- raios
  for j = 0, 15 do
    local a = j / 16 * math.pi * 2 + 0.1
    local r1, r2 = 60 + k * 120, 120 + k * 320
    lg.setColor(1, 0.95, 0.7, (1 - k) * 0.6)
    lg.setLineWidth(3)
    lg.line(cx + math.cos(a) * r1, cy + math.sin(a) * r1, cx + math.cos(a) * r2, cy + math.sin(a) * r2)
  end
  lg.setLineWidth(1)
end

return FX
