-- =============================================================================
--  Historico de erros de comunicacao (Configuracoes > Rede e conectividade)
--  Guarda as ultimas falhas de rede do proprio hub: catalogo online, verificacao
--  de atualizacao, downloads e teste dos repositorios. Sem senhas nem conteudo
--  de arquivos: so data, o que falhou, o endereco (servidor) e o motivo.
-- =============================================================================
local json = require("lib.json")

local N = { list = nil }
local FILE = "netlog.json"
local MAX = 30

local function load()
  if N.list then return end
  N.list = {}
  local ok, text = pcall(love.filesystem.read, FILE)
  if ok and text then
    local d = json.decode(text)
    if type(d) == "table" then
      for _, e in ipairs(d) do if type(e) == "table" and e.what then N.list[#N.list + 1] = e end end
    end
  end
end

--- servidor de um endereco (sem caminho, para nao guardar links inteiros)
local function host_of(url)
  return tostring(url or ""):match("^%a+://([^/%?#]+)") or ""
end

--- registra uma falha. what = texto curto (ja traduzido ou chave), url opcional
function N.add(what, url, reason)
  load()
  table.insert(N.list, 1, { time = os.time(), what = tostring(what), host = host_of(url), reason = tostring(reason or "") })
  while #N.list > MAX do table.remove(N.list) end
  pcall(love.filesystem.write, FILE, json.encode(N.list))
end

function N.all() load(); return N.list end
function N.count() load(); return #N.list end

function N.clear()
  N.list = {}
  pcall(love.filesystem.remove, FILE)
end

return N
