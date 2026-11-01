-- =============================================================================
--  Trilha sonora do R36S PORT HUB
--    main     -> "Tema principal - R36S PORT HUB" (identidade sonora oficial:
--                aviso inicial e menu principal)
--    nav      -> "Tema de navegação - Retro Arcade" (loja, categorias, detalhes)
--    download -> "Tema de download - Download Power" (durante a instalação)
--  As faixas sao tocadas em streaming (pouca memoria) com transicao suave.
-- =============================================================================
local U = require("lib.util")

local M = {
  enabled = true,
  volume = 0.55,
  current = nil,      -- nome da faixa desejada
  sources = {},       -- nome -> Source (carregada sob demanda)
  levels = {},        -- nome -> volume atual (0..1) para a transicao
  available = false,
}

local FILES = {
  main = "assets/music/tema_principal.ogg",
  nav = "assets/music/tema_navegacao.ogg",
  download = "assets/music/tema_download.ogg",
}
local FADE = 1.2            -- segundos para entrar/sair
local SETTINGS = "settings.txt"

local Prefs = require("core.prefs")

local function load_settings()
  local m = Prefs.get("music")
  if m then M.enabled = m == "1" end
  local v = tonumber(Prefs.get("music_vol") or "")
  if v then M.volume = math.max(0, math.min(100, v)) / 100 end
end

--- volume da musica em % (0..100), salvo em settings.txt
function M.volume_pct() return math.floor(M.volume * 100 + 0.5) end
function M.set_volume_pct(p)
  p = math.max(0, math.min(100, p))
  M.volume = p / 100
  Prefs.set("music_vol", p)
end

function M.save_settings()
  Prefs.set("music", M.enabled and "1" or "0")   -- preserva as outras preferencias
end

function M.init()
  load_settings()
  M.available = love.audio ~= nil
  if not M.available then U.log("audio indisponivel; musica desligada") end
end

local function source(name)
  local s = M.sources[name]
  if s then return s end
  if not M.available or not FILES[name] then return nil end
  local ok, src = pcall(love.audio.newSource, FILES[name], "stream")
  if not ok or not src then
    U.log("falha ao abrir musica:", name, tostring(src))
    FILES[name] = nil
    return nil
  end
  src:setLooping(true)
  src:setVolume(0)
  M.sources[name] = src
  M.levels[name] = 0
  return src
end

--- Escolhe a faixa (troca com transicao). nil = silencio.
function M.play(name)
  if name == M.current then
    -- mesma faixa: so retoma se ela ainda nao estiver tocando (ex.: pedida na
    -- abertura, antes do audio ficar pronto)
    -- (a faixa ja foi aberta e iniciada antes: nada a fazer)
    if not name or not M.enabled or not M.available or M.sources[name] ~= nil then return end
  end
  M.current = name
  if name and M.enabled then
    local s = source(name)
    if s and not s:isPlaying() then
      -- a faixa principal recomeca do inicio quando volta; as outras continuam de onde pararam
      if name == "main" then s:seek(0) end
      s:play()
    end
  end
end

function M.update(dt)
  if not M.available then return end
  local step = dt / FADE
  for name, s in pairs(M.sources) do
    local target = (M.enabled and name == M.current) and 1 or 0
    local lv = M.levels[name] or 0
    if lv < target then lv = math.min(target, lv + step)
    elseif lv > target then lv = math.max(target, lv - step) end
    M.levels[name] = lv
    s:setVolume(lv * M.volume)
    if lv <= 0 and target == 0 and s:isPlaying() then s:pause() end
  end
end

function M.set_enabled(on)
  M.enabled = on and true or false
  M.save_settings()
  if M.enabled and M.current then
    local s = source(M.current)
    if s and not s:isPlaying() then s:play() end
  end
end

function M.toggle()
  M.set_enabled(not M.enabled)
  return M.enabled
end

function M.stop_all()
  for _, s in pairs(M.sources) do pcall(s.stop, s) end
end

return M
