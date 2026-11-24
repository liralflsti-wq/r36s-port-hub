-- =============================================================================
--  Animacoes do drone assistente (por peca, procedural, com transicao suave)
--  Pecas: root, body, head, visor, eye_l/r, ear_l/r, antenna_tip, halo,
--         thruster, chest, hand_l/r (as maos flutuam soltas)
--  Animacoes: idle, talk, wave, point, think, alert, happy, sleep
--  Sempre por cima: flutuar, anel girando, propulsor pulsando, piscar.
--    local c = Anim.new()
--    Anim.play(c, "wave", 2.0)   toca e volta para a base
--    Anim.set_base(c, "talk"|"idle"|"sleep")
--    Anim.update(c, dt); local pose = Anim.pose(c, animate)
-- =============================================================================
local Anim = {}
Anim.BLEND = 0.3

local sin, cos, abs, pi = math.sin, math.cos, math.abs, math.pi
local function ease(x) x = math.max(0, math.min(1, x)); return x * x * (3 - 2 * x) end

function Anim.new()
  return { base = "idle", state = "idle", t = 0, time = 0, left = nil, prev = nil, prev_t = 0, mix = 1,
    blink_in = 2.5, blink_t = nil }
end

function Anim.play(c, name, dur)
  if c.state == name and not dur then return end
  c.prev, c.prev_t = c.state, c.t
  c.state, c.t, c.mix = name, 0, 0
  c.left = dur
end

function Anim.set_base(c, name)
  if c.base == name then return end
  c.base = name
  if not c.left then Anim.play(c, name) end
end

function Anim.update(c, dt)
  c.t, c.prev_t, c.time = c.t + dt, c.prev_t + dt, c.time + dt
  c.mix = math.min(1, c.mix + dt / Anim.BLEND)
  if c.left then
    c.left = c.left - dt
    if c.left <= 0 then c.left = nil; Anim.play(c, c.base) end
  end
  if c.blink_t then
    c.blink_t = c.blink_t + dt
    if c.blink_t > 0.13 then c.blink_t = nil end
  else
    c.blink_in = c.blink_in - dt
    if c.blink_in <= 0 then c.blink_t = 0; c.blink_in = 2 + math.random() * 4 end
  end
end

local function q(P, n) P[n] = P[n] or {}; return P[n] end
local function add(P, n, k, v) local x = q(P, n); x[k] = (x[k] or 0) + v end

-- maos: posicao de descanso flutuando ao lado do corpo
local POSES = {}

function POSES.idle(P, t)
  add(P, "head", "rz", sin(t * 0.7) * 0.04)
  add(P, "head", "ry", sin(t * 0.45) * 0.12)
  add(P, "hand_l", "ty", sin(t * 1.9) * 0.02)
  add(P, "hand_r", "ty", sin(t * 1.9 + 1.4) * 0.02)
  add(P, "hand_l", "rz", sin(t * 1.3) * 0.08)
  add(P, "hand_r", "rz", -sin(t * 1.3 + 0.7) * 0.08)
end

function POSES.talk(P, t)
  POSES.idle(P, t)
  add(P, "head", "rx", sin(t * 7) * 0.035)
  add(P, "head", "rz", sin(t * 3.3) * 0.04)
  -- gesto com a mao direita (da imagem: lado +x)
  local g = 0.5 + 0.5 * sin(t * 2.6)
  add(P, "hand_r", "tx", -0.06 * g)
  add(P, "hand_r", "ty", 0.08 + 0.05 * sin(t * 4.4))
  add(P, "hand_r", "tz", 0.08)
  add(P, "hand_r", "rz", -0.4 - 0.2 * sin(t * 4.4))
  P.talking = true
end

function POSES.wave(P, t)
  POSES.idle(P, t * 0.6)
  local up = ease(t / 0.35)
  add(P, "hand_r", "tx", 0.04 * up)
  add(P, "hand_r", "ty", 0.48 * up)
  add(P, "hand_r", "tz", 0.06 * up)
  add(P, "hand_r", "rz", (-0.2 + sin(t * 10) * 0.55) * up)
  add(P, "head", "rz", -0.1 * up)
  add(P, "body", "rz", -0.05 * up)
  P.eyes_happy = up > 0.5
end

function POSES.point(P, t)
  POSES.idle(P, t * 0.6)
  local up = ease(t / 0.3)
  add(P, "hand_r", "tx", 0.18 * up)
  add(P, "hand_r", "ty", 0.22 * up)
  add(P, "hand_r", "tz", 0.12 * up)
  add(P, "hand_r", "rz", -1.3 * up)
  add(P, "head", "ry", 0.35 * up)
  add(P, "root", "ry", 0.12 * up)
  P.eyes_look = { 0.012 * up, 0 }
end

function POSES.think(P, t)
  local up = ease(t / 0.35)
  add(P, "hand_l", "tx", 0.26 * up)
  add(P, "hand_l", "ty", 0.32 * up)
  add(P, "hand_l", "tz", 0.22 * up)
  add(P, "hand_l", "rz", 0.6 * up)
  add(P, "head", "rz", 0.12 * up + sin(t * 2) * 0.02)
  add(P, "head", "rx", -0.08 * up)
  add(P, "hand_r", "ty", sin(t * 1.9) * 0.02)
  q(P, "antenna_tip").s = 1 + 0.4 * abs(sin(t * 8))
  P.eyes_look = { -0.008 * up, 0.012 * up }
end

function POSES.alert(P, t)
  local k = ease(t / 0.15)
  local shake = t < 0.5 and sin(t * 60) * 0.02 or 0
  add(P, "root", "tz", -0.05 * k)
  add(P, "head", "rx", -0.12 * k)
  add(P, "head", "rz", shake)
  add(P, "hand_l", "ty", 0.2 * k); add(P, "hand_l", "tz", 0.1 * k); add(P, "hand_l", "rz", 0.5 * k)
  add(P, "hand_r", "ty", 0.2 * k); add(P, "hand_r", "tz", 0.1 * k); add(P, "hand_r", "rz", -0.5 * k)
  P.alert = true
end

function POSES.happy(P, t)
  local spin = ease(math.min(1, t / 1.1))
  add(P, "root", "ry", spin * pi * 2)
  add(P, "root", "ty", abs(sin(t * 5)) * 0.08)
  add(P, "hand_l", "ty", 0.35); add(P, "hand_l", "rz", 0.4 + sin(t * 12) * 0.2)
  add(P, "hand_r", "ty", 0.35); add(P, "hand_r", "rz", -0.4 - sin(t * 12) * 0.2)
  P.eyes_happy = true
end

function POSES.sleep(P, t)
  add(P, "head", "rx", 0.18)
  add(P, "head", "rz", 0.08)
  add(P, "root", "ty", -0.04)
  add(P, "hand_l", "ty", -0.04); add(P, "hand_r", "ty", -0.04)
  P.eyes_closed = true
  P.dim = true
end

Anim.LIST = { "idle", "talk", "wave", "point", "think", "alert", "happy", "sleep" }

local FIELDS = { "rx", "ry", "rz", "tx", "ty", "tz" }
local function blend(a, b, k)
  local out, names = {}, {}
  for n, v in pairs(a) do if type(v) == "table" and n ~= "eyes_look" then names[n] = true end end
  for n, v in pairs(b) do if type(v) == "table" and n ~= "eyes_look" then names[n] = true end end
  for n in pairs(names) do
    local qa, qb, r = a[n] or {}, b[n] or {}, {}
    for _, f in ipairs(FIELDS) do r[f] = (qa[f] or 0) * (1 - k) + (qb[f] or 0) * k end
    if qa.s or qb.s then r.s = (qa.s or 1) * (1 - k) + (qb.s or 1) * k end
    out[n] = r
  end
  local src = k < 0.5 and a or b
  for _, f in ipairs({ "eyes_happy", "eyes_closed", "alert", "talking", "dim" }) do out[f] = src[f] end
  local la, lb = a.eyes_look or { 0, 0 }, b.eyes_look or { 0, 0 }
  out.eyes_look = { la[1] * (1 - k) + lb[1] * k, la[2] * (1 - k) + lb[2] * k }
  return out
end

local function eval(name, t)
  local P = {}
  ;(POSES[name] or POSES.idle)(P, t)
  return P
end

function Anim.pose(c, animate)
  local P
  if animate == false then P = eval(c.base == "sleep" and "sleep" or "idle", 0)
  else
    P = eval(c.state, c.t)
    if c.mix < 1 and c.prev then local s = c.mix; P = blend(eval(c.prev, c.prev_t), P, s * s * (3 - 2 * s)) end
    -- sempre: flutuar, anel, propulsor, antena
    add(P, "root", "ty", 0.05 + sin(c.time * 1.7) * 0.03)
    add(P, "root", "rz", sin(c.time * 1.1) * 0.02)
    add(P, "halo", "ry", c.time * 1.6)
    add(P, "halo", "rz", sin(c.time * 0.9) * 0.08)
    local th = q(P, "thruster")
    th.s = (th.s or 1) * (P.dim and 0.6 or (0.85 + 0.15 * sin(c.time * 14)))
    local at = q(P, "antenna_tip")
    at.s = (at.s or 1) * (1 + 0.15 * sin(c.time * 3))
    if c.blink_t and not P.eyes_happy then P.eyes_closed = true end
  end
  local look = P.eyes_look or { 0, 0 }
  local talk = P.talking and (0.75 + 0.25 * abs(sin((c.time or 0) * 11))) or 1
  for _, e in ipairs({ "eye_l", "eye_r" }) do
    local x = q(P, e)
    x.tx = (x.tx or 0) + look[1]
    x.ty = (x.ty or 0) + look[2]
    if P.eyes_closed then x.sy = 0.12
    elseif P.eyes_happy then x.sy = 0.35; x.ty = x.ty + 0.012
    else x.sy = talk end
    if P.alert then x.color = { 1, 0.25, 0.25, 1 }; x.s = 1.15 end
  end
  if P.alert then
    for _, n in ipairs({ "chest", "thruster", "antenna_tip", "earglow_l", "earglow_r" }) do q(P, n).color = { 1, 0.3, 0.3, 1 } end
  end
  return P
end

return Anim
