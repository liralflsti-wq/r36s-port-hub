-- =============================================================================
--  Analisador do cartao SD (thread). SOMENTE LEITURA: so lista e soma tamanhos.
--  Uma passada com `find` (sem seguir links, sem sair do cartao: -xdev).
-- =============================================================================
require("love.timer")
local root, out_name, ctl_name, pidfile = ...
local OUT = love.thread.getChannel(out_name)
local CTL = love.thread.getChannel(ctl_name)

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local TOP_N = 60
local t0 = love.timer.getTime()

-- pastas: caminho real -> { size, files }
local dirs = { [root] = { size = 0, files = 0, dirs = 0 } }
local nfiles, nbytes = 0, 0
local top = {}      -- maiores arquivos (ordenados, no maximo TOP_N)
local min_top = -1

local function add_top(size, path)
  if #top >= TOP_N and size <= min_top then return end
  local pos = #top + 1
  for i = 1, #top do if size > top[i].size then pos = i; break end end
  table.insert(top, pos, { size = size, path = path })
  if #top > TOP_N then table.remove(top) end
  min_top = #top >= TOP_N and top[#top].size or -1
end

local function cancelled()
  local m = CTL:pop()
  return m == "cancel"
end

-- 1) pastas (inclusive as vazias), para a navegacao
local cmd_d = "sh -c " .. shq("echo $$ > " .. shq(pidfile) .. "; exec find " .. shq(root) .. " -xdev -type d 2>/dev/null")
local h = io.popen(cmd_d)
local n = 0
for line in h:lines() do
  if line ~= root then
    dirs[line] = dirs[line] or { size = 0, files = 0, dirs = 0 }
    local parent = line:match("^(.*)/[^/]+$")
    if dirs[parent] then dirs[parent].dirs = dirs[parent].dirs + 1 end
  end
  n = n + 1
  if n % 500 == 0 and cancelled() then
    os.execute("kill $(cat " .. shq(pidfile) .. ") 2>/dev/null")
    h:close()
    OUT:push({ t = "cancelled" })
    return
  end
end
h:close()

-- 2) arquivos com tamanho (stat em lote)
local cmd_f = "sh -c " .. shq("echo $$ > " .. shq(pidfile) .. "; exec find " .. shq(root)
  .. " -xdev -type f -exec stat -c '%s|%n' {} + 2>/dev/null")
h = io.popen(cmd_f)
for line in h:lines() do
  local size, path = line:match("^(%d+)|(.*)$")
  if size then
    size = tonumber(size)
    nfiles = nfiles + 1
    nbytes = nbytes + size
    add_top(size, path)
    -- soma em todas as pastas acima do arquivo
    local d = path:match("^(.*)/[^/]+$")
    local first = true
    while d and #d >= #root do
      local e = dirs[d]
      if not e then e = { size = 0, files = 0, dirs = 0 }; dirs[d] = e end
      e.size = e.size + size
      if first then e.files = e.files + 1; first = false end
      if d == root then break end
      d = d:match("^(.*)/[^/]+$")
    end
    if nfiles % 2000 == 0 then
      OUT:push({ t = "progress", files = nfiles, bytes = nbytes, elapsed = love.timer.getTime() - t0 })
      if cancelled() then
        os.execute("kill $(cat " .. shq(pidfile) .. ") 2>/dev/null")
        h:close()
        OUT:push({ t = "cancelled" })
        return
      end
    end
  end
end
h:close()
os.remove(pidfile)

-- total recursivo de arquivos por pasta (para mostrar "N arquivos")
OUT:push({ t = "done", dirs = dirs, top = top, files = nfiles, bytes = nbytes, ndirs = n,
  elapsed = love.timer.getTime() - t0 })
