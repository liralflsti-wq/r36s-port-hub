-- =============================================================================
--  Atualizacoes do hub: historico (pasta de dados do app, update_history.json)
--  Versao anterior, versao instalada, data, origem, pacote, resultado e erro.
-- =============================================================================
local json = require("lib.json")

local M = {}
local FILE = "update_history.json"
local MAX = 100

function M.list()
  local ok, text = pcall(love.filesystem.read, FILE)
  local d = ok and text and json.decode(text) or nil
  return type(d) == "table" and d or {}
end

--- entry = { from, to, origin = "local"|"rede"|"backup"|"recuperacao", package, result = "ok"|"erro"|"restaurado", error }
function M.add(entry)
  local d = M.list()
  entry.time = entry.time or os.time()
  d[#d + 1] = entry
  while #d > MAX do table.remove(d, 1) end
  pcall(love.filesystem.write, FILE, json.encode(d))
end

--- mais recentes primeiro
function M.recent()
  local d, t = M.list(), {}
  for i = #d, 1, -1 do t[#t + 1] = d[i] end
  return t
end

return M
