-- =============================================================================
--  Atualizacoes do hub: integridade (SHA-256 de cada arquivo)
--  Calculado pelo proprio LOVE (love.data), sem depender de programas do
--  sistema; so arquivos muito grandes usam o sha256sum, se existir.
-- =============================================================================
require("love.data")

local M = {}
local IN_MEMORY = 96 * 1024 * 1024

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end

--- SHA-256 (hex minusculo) de um arquivo, ou nil
function M.sha256_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end") or 0
  if size <= IN_MEMORY then
    f:seek("set", 0)
    local data = f:read("*a") or ""
    f:close()
    return love.data.encode("string", "hex", love.data.hash("sha256", data)):lower()
  end
  f:close()
  local h = io.popen("sha256sum " .. shq(path) .. " 2>/dev/null")
  if not h then return nil end
  local out = h:read("*a") or ""
  h:close()
  local sum = out:match("^(%x+)")
  return sum and #sum == 64 and sum:lower() or nil
end

return M
