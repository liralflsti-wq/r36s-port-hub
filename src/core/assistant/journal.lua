-- =============================================================================
--  Diario de atividades do assistente (activity.json nos dados do app)
--  Tudo o que acontece no hub vira uma linha: port instalado/removido,
--  download cancelado, erro, jogo aberto, conquista, transferencia FTP,
--  atualizacao do hub, catalogo atualizado. O assistente usa isto para
--  responder "o que eu fiz hoje?" e para comentar o que acabou de acontecer.
--    J.add(kind, text)  J.today()  J.recent(n)  J.count(kind, desde)
-- =============================================================================
local J = {}
local FILE = "activity.json"
local MAX = 300
local list

local function load()
  if list then return list end
  local ok, txt = pcall(love.filesystem.read, FILE)
  local d = ok and txt and select(2, pcall(require("lib.json").decode, txt)) or nil
  list = type(d) == "table" and d or {}
  return list
end

local function save()
  pcall(function() love.filesystem.write(FILE, require("lib.json").encode(load())) end)
end

function J.add(kind, text)
  local l = load()
  l[#l + 1] = { t = os.time(), k = tostring(kind), x = tostring(text or "") }
  while #l > MAX do table.remove(l, 1) end
  save()
end

--- atividades de hoje (mais antigas primeiro)
function J.today()
  local out, day = {}, os.date("%Y-%m-%d")
  for _, e in ipairs(load()) do
    if os.date("%Y-%m-%d", e.t) == day then out[#out + 1] = e end
  end
  return out
end

--- as n mais recentes (mais novas primeiro)
function J.recent(n)
  local l, out = load(), {}
  for i = #l, math.max(1, #l - (n or 10) + 1), -1 do out[#out + 1] = l[i] end
  return out
end

function J.count(kind, since)
  local n = 0
  for _, e in ipairs(load()) do
    if e.k == kind and (not since or e.t >= since) then n = n + 1 end
  end
  return n
end

return J
