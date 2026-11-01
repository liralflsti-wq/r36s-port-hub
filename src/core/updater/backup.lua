-- =============================================================================
--  Atualizacoes do hub: backups e diario de instalacao
--
--  r36sporthub/backups/<id>/
--     meta.json   versao anterior/nova, pacote, data, arquivos, tamanho, estado
--     files/...   copia dos arquivos que a atualizacao trocou (mesmos caminhos)
--     added.txt   arquivos que a atualizacao criou (apagados ao restaurar)
--  r36sporthub/backups/.journal  (lido tambem pelo lancador R36S PORT HUB.sh)
--     state=applying  -> instalacao interrompida no meio: restaurar
--     state=pending   -> instalada; a proxima abertura confirma
--     state=booting   -> abrindo a versao nova; se o app nao confirmar, restaurar
--  Politica: guarda os 3 backups completos mais recentes. O mais antigo so e
--  apagado depois que uma atualizacao nova termina bem.
-- =============================================================================
local json = require("lib.json")

local M = {}
M.KEEP = 3

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end

function M.dir(app_dir) return app_dir .. "/backups" end

function M.valid_id(id) return type(id) == "string" and id:match("^[%w%-_%.]+$") ~= nil and id ~= "." and id ~= ".." end

function M.new_id(version)
  local v = tostring(version or "x"):gsub("[^%w%.]", "")
  return os.date("%Y%m%d-%H%M%S") .. "_v" .. (v ~= "" and v or "x")
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  local ok = f:write(data)
  f:close()
  return ok and true or false
end
M.write_file = write

function M.read_meta(app_dir, id)
  local d = json.decode(read(M.dir(app_dir) .. "/" .. id .. "/meta.json") or "")
  return type(d) == "table" and d or nil
end

function M.write_meta(app_dir, id, meta)
  return write(M.dir(app_dir) .. "/" .. id .. "/meta.json", json.encode(meta))
end

--- backups existentes (mais recentes primeiro)
function M.list(app_dir)
  local base = M.dir(app_dir)
  local h = io.popen("ls -1 " .. shq(base) .. " 2>/dev/null")
  local t = {}
  if h then
    for id in (h:read("*a") or ""):gmatch("[^\n]+") do
      if M.valid_id(id) and id:sub(1, 1) ~= "." then
        local m = M.read_meta(app_dir, id)
        if m then m.id = id; t[#t + 1] = m end
      end
    end
    h:close()
  end
  table.sort(t, function(a, b) return (a.created or 0) > (b.created or 0) end)
  return t
end

function M.delete(app_dir, id)
  if not M.valid_id(id) then return false end
  local p = M.dir(app_dir) .. "/" .. id
  os.execute("rm -rf -- " .. shq(p) .. " 2>/dev/null")
  return read(p .. "/meta.json") == nil
end

--- apaga os backups completos alem dos `keep` mais recentes (nunca `except`)
function M.prune(app_dir, keep, except)
  local n = 0
  for _, m in ipairs(M.list(app_dir)) do
    if m.state == "complete" and m.id ~= except then
      n = n + 1
      if n > (keep or M.KEEP) - (except and 1 or 0) then M.delete(app_dir, m.id) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Diario
function M.journal_path(app_dir) return M.dir(app_dir) .. "/.journal" end

function M.journal_read(app_dir)
  local s = read(M.journal_path(app_dir))
  if not s then return nil end
  local j = {}
  for k, v in s:gmatch("([%w_]+)=([^\n]*)") do j[k] = v end
  return j.state and j or nil
end

function M.journal_write(app_dir, j)
  os.execute("mkdir -p " .. shq(M.dir(app_dir)) .. " 2>/dev/null")
  local lines = {}
  for _, k in ipairs({ "state", "backup", "from", "to", "origin", "package" }) do
    if j[k] then lines[#lines + 1] = k .. "=" .. tostring(j[k]):gsub("[\r\n]", " ") end
  end
  local p = M.journal_path(app_dir)
  local ok = write(p .. ".new", table.concat(lines, "\n") .. "\n") and os.rename(p .. ".new", p)
  os.execute("sync 2>/dev/null")
  return ok
end

function M.journal_clear(app_dir)
  os.remove(M.journal_path(app_dir))
  os.execute("sync 2>/dev/null")
end

return M
