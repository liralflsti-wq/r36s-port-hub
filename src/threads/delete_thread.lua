-- =============================================================================
--  R36S PORT HUB - thread de exclusao de um jogo (nao trava a interface)
--  Recebe a pasta base (/roms/ports ja resolvida) e os NOMES dos itens da raiz
--  a apagar. Revalida tudo antes de apagar: nomes simples, dentro da base,
--  links simbolicos sao removidos sem seguir o destino.
-- =============================================================================
local job = ...
local OUT = love.thread.getChannel(job.out_channel)

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end
local function ok(r) return r == 0 or r == true end
local function sh(cmd) return ok(os.execute(cmd)) end

local base = job.base
local failed, removed = {}, {}

if type(base) ~= "string" or base == "" or base == "/" or not base:match("/ports$") then
  OUT:push({ t = "done", failed = { "pasta base inválida" }, removed = {} })
  return
end

for _, name in ipairs(job.items or {}) do
  if type(name) ~= "string" or name == "" or name == "." or name == ".." or name:find("/") then
    failed[#failed + 1] = tostring(name)
  else
    local p = base .. "/" .. name
    local cmd
    if sh("test -L " .. shq(p)) then
      cmd = "rm -f -- " .. shq(p)           -- remove so o link
    elseif sh("test -d " .. shq(p)) then
      cmd = "rm -rf -- " .. shq(p)
    elseif sh("test -e " .. shq(p)) then
      cmd = "rm -f -- " .. shq(p)
    end
    if cmd then
      sh(cmd .. " 2>/dev/null")
      if sh("test -e " .. shq(p) .. " -o -L " .. shq(p)) then
        failed[#failed + 1] = name
      else
        removed[#removed + 1] = name
      end
    end
  end
end
sh("sync")
print("[excluir] removidos: " .. table.concat(removed, ", ") .. (#failed > 0 and (" | falhas: " .. table.concat(failed, ", ")) or ""))
io.stdout:flush()
OUT:push({ t = "done", failed = failed, removed = removed })
