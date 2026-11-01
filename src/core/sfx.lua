-- =============================================================================
--  Efeitos sonoros da interface (navegar, confirmar, voltar, notificacao).
--  Os sons sao gerados em codigo na primeira vez que tocam (nenhum arquivo,
--  poucos KB de memoria). Preferencias em settings.txt:
--    sfx (1/0), sfx_vol (0..100), notif_sound (1/0)
-- =============================================================================
local Prefs = require("core.prefs")

local S = { enabled = true, volume = 40, sounds = {}, ok = love.audio ~= nil and love.sound ~= nil }

local RATE = 22050

-- tons: lista de { freq, duracao } tocados em sequencia, com envelope curto
local DEFS = {
  move = { { 1320, 0.022 } },
  ok = { { 988, 0.04 }, { 1480, 0.06 } },
  back = { { 880, 0.04 }, { 587, 0.06 } },
  notify = { { 1175, 0.07 }, { 1568, 0.11 } },
  error = { { 330, 0.09 }, { 262, 0.13 } },
}

local function build(def)
  local total = 0
  for _, t in ipairs(def) do total = total + t[2] end
  local n = math.floor(total * RATE)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  local i = 0
  for _, t in ipairs(def) do
    local freq, len = t[1], math.floor(t[2] * RATE)
    for k = 0, len - 1 do
      if i >= n then break end
      local p = k / len
      local env = math.min(1, k / (RATE * 0.004)) * (1 - p) ^ 1.5   -- ataque rapido, saida suave
      -- onda quadrada suavizada (timbre retro, sem chiado)
      local ph = (k * freq / RATE) % 1
      local v = (ph < 0.5 and 1 or -1) * 0.6 + math.sin(2 * math.pi * freq * k / RATE) * 0.4
      sd:setSample(i, v * env * 0.35)
      i = i + 1
    end
  end
  return love.audio.newSource(sd, "static")
end

function S.load()
  S.enabled = Prefs.get("sfx") ~= "0"
  S.volume = tonumber(Prefs.get("sfx_vol") or "") or 40
  S.notif = Prefs.get("notif_sound") ~= "0"
end

local function play(name)
  if not S.ok or S.volume <= 0 then return end
  local src = S.sounds[name]
  if src == nil then
    local ok, s = pcall(build, DEFS[name])
    src = ok and s or false
    S.sounds[name] = src
  end
  if not src then return end
  src:stop()
  src:setVolume(S.volume / 100)
  src:play()
end

--- som de navegacao (so com "Efeitos sonoros" ligado)
function S.play(name)
  if S.enabled then play(name) end
end

--- som de notificacao (so com "Som das notificações" ligado)
function S.notify(kind)
  if S.notif then play((kind == "error" or kind == "warn") and "error" or "notify") end
end

--- previa ao mudar o volume (toca mesmo se o efeito estiver desligado)
function S.preview() play("ok") end

local MAP = { up = "move", down = "move", left = "move", right = "move", l1 = "move", r1 = "move",
  a = "ok", x = "ok", y = "ok", select = "ok", b = "back" }
function S.on_action(act)
  local n = MAP[act]
  if n then S.play(n) end
end

function S.set_enabled(on) S.enabled = on and true or false; Prefs.set("sfx", S.enabled and "1" or "0") end
function S.set_volume(v) S.volume = math.max(0, math.min(100, v)); Prefs.set("sfx_vol", S.volume) end
function S.set_notify(on) S.notif = on and true or false; Prefs.set("notif_sound", S.notif and "1" or "0") end

return S
