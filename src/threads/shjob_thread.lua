-- =============================================================================
--  R36S PORT HUB - comandos de verificacao em segundo plano (somente leitura)
--  Recebe { out = canal, cmds = { "cmd1", "cmd2", ... } } e devolve, na ordem,
--  a saida e o codigo de cada um. Usado por Configuracoes (espaco dos ports,
--  repositorios, modulos do hub). Nenhum comando aqui altera arquivos.
-- =============================================================================
require("love.timer")
local job = ...
local OUT = love.thread.getChannel(job.out)

local res = {}
for i, cmd in ipairs(job.cmds or {}) do
  local t0 = love.timer.getTime()
  local p = io.popen(cmd .. " 2>/dev/null; echo \"__rc=$?\"")
  local s = p and p:read("*a") or ""
  if p then p:close() end
  local rc = tonumber(s:match("__rc=(%d+)%s*$")) or 1
  s = s:gsub("__rc=%d+%s*$", "")
  res[i] = { out = s, rc = rc, secs = love.timer.getTime() - t0 }
  OUT:push({ t = "progress", done = i, total = #job.cmds })
end
OUT:push({ t = "done", results = res })
