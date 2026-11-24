-- =============================================================================
--  Voz do assistente (falas fixas gravadas, so em portugues)
--    Cada fala fixa tem um arquivo assets/assistant/voice/<id>.ogg, onde <id> sao
--    os 10 primeiros caracteres do SHA-1 do texto. Falas com numeros ao vivo
--    (bateria, IP, espaco livre) nao tem audio e aparecem so no balao.
--    V.play(texto) -> duracao em segundos, ou nil se nao tocou
--  Meu perfil > Voz do assistente: ligada / desligada (assistant.json "voice").
-- =============================================================================
local V = {}
local DIR = "assets/assistant/voice/"
local cur
local cache = {}

local function id_of(text)
  local ok, h = pcall(love.data.hash, "sha1", text)
  if not ok then return nil end
  return (love.data.encode("string", "hex", h)):sub(1, 10)
end

function V.enabled()
  local A = require("core.assistant")
  return A.get("voice") ~= false and A.talk() ~= "off" and A.enabled()
end

function V.stop()
  if cur then pcall(function() cur:stop() end) end
  cur = nil
end

function V.has(text)
  local id = text and id_of(text)
  return id and love.filesystem.getInfo(DIR .. id .. ".ogg") ~= nil
end

function V.play(text)
  V.stop()
  if not text or require("lib.i18n").lang ~= "pt-BR" or not V.enabled() then return nil end
  local id = id_of(text)
  if not id then return nil end
  local path = DIR .. id .. ".ogg"
  local src = cache[id]
  if src == nil then
    if not love.filesystem.getInfo(path) then cache[id] = false; return nil end
    local ok, s = pcall(love.audio.newSource, path, "static")
    src = ok and s or false
    cache[id] = src
  end
  if not src then return nil end
  V.stop()
  pcall(function() src:setVolume(0.9); src:play() end)
  cur = src
  local okd, d = pcall(function() return src:getDuration() end)
  return okd and d or nil
end

return V
