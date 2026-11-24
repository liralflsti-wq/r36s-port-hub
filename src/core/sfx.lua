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

-- ---------------------------------------------------------------------------
-- Som de conquista (estilo dos consoles atuais): um "whoosh" suave de entrada,
-- sinos de cristal (sintese FM) tocando um acorde que sobe e um pouco de eco.
-- Cada raridade tem a sua versao, cada vez mais rica:
--   comum     dois sinos (quinta subindo)
--   incomum   tres sinos (arpejo maior)
--   epica     arpejo + acorde grave por baixo
--   lendaria  arpejo de quatro notas + brilho agudo cintilando
--   unica     arpejo longo, acorde cheio, brilho e um "pling" final no alto
local ARATE = 32000
local function note(n) return 440 * 2 ^ ((n - 69) / 12) end   -- nota MIDI -> Hz
local ACHV = {
  common = { notes = { { 76, 0.00 }, { 83, 0.11 } }, len = 1.4 },
  uncommon = { notes = { { 72, 0.00 }, { 76, 0.09 }, { 79, 0.18 } }, len = 1.6 },
  epic = { notes = { { 72, 0.00 }, { 76, 0.08 }, { 79, 0.16 }, { 84, 0.26 } }, pad = { 48, 55, 60 }, len = 1.9 },
  legendary = { notes = { { 74, 0.00 }, { 78, 0.08 }, { 81, 0.16 }, { 86, 0.24 }, { 90, 0.36 } }, pad = { 50, 57, 62 },
    sparkle = 12, len = 2.2 },
  unique = { notes = { { 72, 0.00 }, { 76, 0.07 }, { 79, 0.14 }, { 83, 0.21 }, { 86, 0.28 }, { 88, 0.40 }, { 96, 0.62 } },
    pad = { 48, 55, 60, 64 }, sparkle = 22, len = 2.6 },
}

function S.build_achievement(rar)
  local d = ACHV[rar] or ACHV.common
  local n = math.floor(d.len * ARATE)
  local buf = {}
  for i = 1, n do buf[i] = 0 end
  local tau = 2 * math.pi
  -- whoosh de entrada: ruido filtrado subindo
  local lp, seed = 0, 12345
  for i = 1, math.floor(0.22 * ARATE) do
    seed = (seed * 1103515245 + 12345) % 2147483648
    local r = seed / 2147483648 * 2 - 1
    local p = i / (0.22 * ARATE)
    local k = 0.02 + 0.25 * p
    lp = lp + (r - lp) * k
    buf[i] = buf[i] + lp * math.sin(math.pi * p) * 0.35
  end
  -- sinos FM: portadora + modulador 3,5x com indice que decai
  local function bell(f, t0, amp, dec)
    local s0 = math.floor(t0 * ARATE) + 1
    local len = math.min(n - s0, math.floor(dec * 4 * ARATE))
    for k = 0, len do
      local t = k / ARATE
      local env = math.min(1, t / 0.004) * math.exp(-t / dec)
      local idx = 2.2 * math.exp(-t / (dec * 0.35))
      local v = math.sin(tau * f * t + idx * math.sin(tau * f * 3.5 * t))
        + 0.35 * math.sin(tau * f * 2 * t) * math.exp(-t / (dec * 0.5))
      buf[s0 + k] = buf[s0 + k] + v * env * amp
    end
  end
  for _, nt in ipairs(d.notes) do bell(note(nt[1]), nt[2], 0.22, 0.32) end
  -- acorde grave (pad suave)
  if d.pad then
    for _, m in ipairs(d.pad) do
      local f = note(m)
      local s0 = math.floor(0.12 * ARATE)
      for k = 0, n - s0 - 1 do
        local t = k / ARATE
        local env = math.min(1, t / 0.25) * math.exp(-t / 0.7)
        buf[s0 + k + 1] = buf[s0 + k + 1] + (math.sin(tau * f * t) + 0.3 * math.sin(tau * f * 2.003 * t)) * env * 0.07
      end
    end
  end
  -- brilho: sininhos bem agudos aleatorios
  if d.sparkle then
    for j = 1, d.sparkle do
      seed = (seed * 1103515245 + 12345) % 2147483648
      local r1 = seed / 2147483648
      seed = (seed * 1103515245 + 12345) % 2147483648
      local r2 = seed / 2147483648
      bell(note(96 + math.floor(r1 * 12)), 0.25 + r2 * (d.len - 0.9), 0.05, 0.08)
    end
  end
  -- eco (tres atrasos com realimentacao) e limite suave
  local taps = { { 0.083, 0.30 }, { 0.137, 0.22 }, { 0.211, 0.16 } }
  for _, tp in ipairs(taps) do
    local dl = math.floor(tp[1] * ARATE)
    for i = dl + 1, n do buf[i] = buf[i] + buf[i - dl] * tp[2] end
  end
  local peak = 0
  for i = 1, n do if math.abs(buf[i]) > peak then peak = math.abs(buf[i]) end end
  local g = peak > 0 and 0.85 / peak or 1
  local sd = love.sound.newSoundData(n, ARATE, 16, 1)
  for i = 1, n do
    local v = buf[i] * g
    v = v / (1 + math.abs(v) * 0.15)
    -- fim suave (sem estalo)
    local tail = (n - i) / (0.05 * ARATE)
    if tail < 1 then v = v * tail end
    sd:setSample(i - 1, v)
  end
  return sd
end

--- toca o som da conquista (respeita "Som das notificações" e o volume dos efeitos)
function S.achievement(rar)
  if not S.ok or not S.notif or S.volume <= 0 then return end
  local key = "achv_" .. (rar or "common")
  local src = S.sounds[key]
  if src == nil then
    local ok, sd = pcall(S.build_achievement, rar)
    src = ok and love.audio.newSource(sd, "static") or false
    S.sounds[key] = src
  end
  if not src then return end
  src:stop()
  src:setVolume(math.min(1, S.volume / 100 * 1.4))
  src:play()
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
