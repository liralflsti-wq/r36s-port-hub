-- =============================================================================
--  Entrada: botoes fisicos do R36S (gamepad SDL), analogico e teclado.
--  Mesma estrategia do KMP: love.gamepadpressed + mapeamento de teclas
--  (o gptokeyb do PortMaster pode gerar teclas tambem; duplicatas sao filtradas).
--
--  Acoes: up down left right a b x y l1 r1 l2 r2 start select
-- =============================================================================
local Input = { handler = nil, held = {}, rep = nil, last = {}, axis = { x = 0, y = 0 } }

local PAD = {
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  a = "a", b = "b", x = "x", y = "y",
  leftshoulder = "l1", rightshoulder = "r1",
  start = "start", back = "select",
  guide = "shot",   -- botao FN do R36S: tira um print da tela
}

-- Mesmo mapeamento de teclas do KMP (compativel com o gptokeyb do PortMaster)
local KEYS = {
  up = "up", down = "down", left = "left", right = "right",
  ["return"] = "a", kpenter = "a", a = "a",
  b = "b", space = "b", backspace = "b",
  x = "x", y = "y",
  pageup = "l1", pagedown = "r1",
  escape = "start", tab = "select",
  f12 = "shot",
}

local REPEATABLE = { up = true, down = true, left = true, right = true, l1 = true, r1 = true }
local DELAY, RATE = 0.32, 0.075
local DEDUP = 0.06

local function fire(act)
  local now = love.timer.getTime()
  if Input.last[act] and now - Input.last[act] < DEDUP then return end
  Input.last[act] = now
  if Input.handler then Input.handler(act) end
end

local function press(act, src)
  if not act then return end
  Input.held[act] = (Input.held[act] or 0) + 1
  fire(act)
  if REPEATABLE[act] then Input.rep = { act = act, src = src, t = DELAY } end
end

local function release(act, src)
  if not act then return end
  local n = (Input.held[act] or 1) - 1
  Input.held[act] = n > 0 and n or nil
  if Input.rep and Input.rep.act == act then Input.rep = nil end
end

function Input.gamepadpressed(_, button)
  if not PAD[button] then print("[porthub] botao sem funcao: " .. tostring(button)) end
  press(PAD[button], "pad")
end
function Input.gamepadreleased(_, button) release(PAD[button], "pad") end

function Input.keypressed(key, _, isrepeat)
  if isrepeat then return end
  press(KEYS[key], "key")
end
function Input.keyreleased(key) release(KEYS[key], "key") end

-- Analogico esquerdo funciona como direcional
function Input.gamepadaxis(_, axis, value)
  local TH = 0.55
  if axis == "leftx" then
    local prev = Input.axis.x
    local now = value > TH and 1 or (value < -TH and -1 or 0)
    if now ~= prev then
      if prev == 1 then release("right", "axis") elseif prev == -1 then release("left", "axis") end
      if now == 1 then press("right", "axis") elseif now == -1 then press("left", "axis") end
      Input.axis.x = now
    end
  elseif axis == "lefty" then
    local prev = Input.axis.y
    local now = value > TH and 1 or (value < -TH and -1 or 0)
    if now ~= prev then
      if prev == 1 then release("down", "axis") elseif prev == -1 then release("up", "axis") end
      if now == 1 then press("down", "axis") elseif now == -1 then press("up", "axis") end
      Input.axis.y = now
    end
  elseif axis == "triggerleft" or axis == "triggerright" then
    local act = axis == "triggerleft" and "l2" or "r2"
    local key = "trig_" .. act
    local down = value > 0.5
    if down and not Input[key] then Input[key] = true; press(act, "axis")
    elseif not down and Input[key] then Input[key] = false; release(act, "axis") end
  end
end

function Input.update(dt)
  local r = Input.rep
  if not r then return end
  if not Input.held[r.act] then Input.rep = nil; return end
  r.t = r.t - dt
  if r.t <= 0 then
    r.t = RATE
    Input.last[r.act] = nil
    fire(r.act)
  end
end

function Input.is_held(act) return Input.held[act] ~= nil end

function Input.reset()
  Input.held = {}
  Input.rep = nil
end

return Input
