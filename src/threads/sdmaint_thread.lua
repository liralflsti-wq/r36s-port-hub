-- =============================================================================
--  Otimizador e manutencao do microSD (thread): operacoes demoradas.
--  job.op:
--    "analyze"  - pastas e arquivos que mais ocupam (du/find, somente leitura)
--    "dups"     - arquivos duplicados por conteudo (md5), somente leitura
--    "integrity"- estado de montagem, log do kernel, estado ext4, flags exFAT
--                 (tudo somente leitura; nunca roda fsck em particao montada)
--    "fsck"     - verificacao SOMENTE LEITURA (-n) de UMA particao desmontada
--    "trim"     - fstrim nos pontos de montagem pedidos (depois de confirmar)
--    "sync"     - grava dados pendentes (sync)
--    "cleantmp" - apaga restos de instalacoes do proprio hub (pasta tmp do hub)
--  Progresso: { t = "progress", text, done, total }   Fim: { t = "done", ... }
--  Cancelar: mensagem "cancel" no canal de controle (mata o comando em curso).
-- =============================================================================
require("love.timer")
local out_name, ctl_name, job = ...
local OUT = love.thread.getChannel(out_name)
local CTL = love.thread.getChannel(ctl_name)
local U = require("lib.util")
local M = require("core.sdmaint")

local function progress(text, done, total) OUT:push({ t = "progress", text = text, done = done, total = total }) end
local cancelled = false
local function check_cancel()
  if CTL:pop() == "cancel" then cancelled = true end
  return cancelled
end

local PID = job.pidfile
--- roda um comando que pode demorar, guardando o pid (para cancelar)
local function popen_lines(cmd, on_line)
  local h = io.popen("sh -c " .. U.shq("echo $$ > " .. U.shq(PID) .. "; exec " .. cmd) .. " 2>/dev/null")
  if not h then return end
  local n = 0
  for line in h:lines() do
    on_line(line)
    n = n + 1
    if n % 200 == 0 and check_cancel() then
      local pid = U.trim(U.read_file(PID) or "")
      if pid ~= "" then os.execute("kill " .. pid .. " 2>/dev/null") end
      break
    end
  end
  h:close()
  os.remove(PID)
end

--- roda com saida + codigo; tenta sem sudo e, se faltar permissao, com "sudo -n"
local function run(cmd, allow_sudo)
  local function once(c)
    local out = U.capture("{ " .. c .. "; } 2>&1; echo \"__EXIT:$?\"") or ""
    local code = tonumber(out:match("__EXIT:(%d+)%s*$"))
    return out:gsub("__EXIT:%d+%s*$", ""), code
  end
  local out, code = once(cmd)
  if allow_sudo and code ~= 0 then
    local o = out:lower()
    if o:find("permission denied", 1, true) or o:find("operation not permitted", 1, true)
        or o:find("must be root", 1, true) or o:find("you must have", 1, true) or o:find("are you root", 1, true)
        or o:find("not permitted", 1, true) or o:find("eacces", 1, true) or o:find("read kernel buffer failed", 1, true) then
      local o2, c2 = once("sudo -n " .. cmd)
      if not o2:lower():find("sudo:", 1, true) then return o2, c2, true end
    end
  end
  return out, code, false
end

local R = { t = "done", op = job.op }

-- ---------------------------------------------------------------------------
local function op_analyze()
  R.parts = {}
  for i, p in ipairs(job.parts or {}) do
    if check_cancel() then break end
    local r = { name = p.name, mp = p.mp, dirs = {}, files = {} }
    progress(string.format("%s (%d/%d): %s", p.mp, i, #job.parts, "du"), i - 1, #job.parts)
    local ok = false
    popen_lines("du -x -k -d 1 " .. U.shq(p.mp), function(l)
      local kb, path = l:match("^(%d+)%s+(.+)$")
      if kb then
        ok = true
        if path == p.mp then r.total = tonumber(kb) * 1024
        else r.dirs[#r.dirs + 1] = { size = tonumber(kb) * 1024, path = path } end
      end
    end)
    if not ok then r.du_failed = true end
    table.sort(r.dirs, function(a, b) return a.size > b.size end)
    while #r.dirs > 8 do table.remove(r.dirs) end
    if check_cancel() then R.parts[#R.parts + 1] = r; break end
    progress(string.format("%s (%d/%d): %s", p.mp, i, #job.parts, "find"), i - 0.5, #job.parts)
    popen_lines("find " .. U.shq(p.mp) .. " -xdev -type f -size +10240k -exec stat -c '%s|%n' {} +", function(l)
      local sz, path = l:match("^(%d+)|(.+)$")
      if sz then r.files[#r.files + 1] = { size = tonumber(sz), path = path } end
    end)
    table.sort(r.files, function(a, b) return a.size > b.size end)
    while #r.files > 10 do table.remove(r.files) end
    R.parts[#R.parts + 1] = r
  end
  R.cancelled = cancelled
end

-- ---------------------------------------------------------------------------
local function op_dups()
  local hasher = M.has("md5sum") and "md5sum" or (M.has("sha1sum") and "sha1sum") or nil
  if not hasher then R.error = "nohash"; return end
  R.hasher = hasher
  local min_kb = job.min_kb or 1024
  local files, n = {}, 0
  for _, root in ipairs(job.roots or {}) do
    progress(root, 0, nil)
    popen_lines("find " .. U.shq(root) .. " -xdev -type f -size +" .. (min_kb - 1) .. "k -exec stat -c '%s|%n' {} +", function(l)
      local sz, path = l:match("^(%d+)|(.+)$")
      if sz then
        n = n + 1
        files[#files + 1] = { size = tonumber(sz), path = path }
        if n % 500 == 0 then progress(root, n, nil) end
      end
    end)
    if cancelled then break end
  end
  R.scanned = #files
  if cancelled then R.cancelled = true; return end
  -- 1) mesmo tamanho
  local by = {}
  for _, f in ipairs(files) do by[f.size] = by[f.size] or {}; table.insert(by[f.size], f) end
  local cand, cand_bytes = {}, 0
  for size, l in pairs(by) do
    if #l > 1 then for _, f in ipairs(l) do cand[#cand + 1] = f; cand_bytes = cand_bytes + f.size end end
  end
  table.sort(cand, function(a, b) return a.size > b.size end)
  R.candidates = #cand
  -- 2) hash do primeiro 1 MB; 3) hash completo de quem continuar igual
  local function hash(cmd)
    local out = U.capture(cmd .. " 2>/dev/null") or ""
    return out:match("^(%x+)")
  end
  local done_b, total_b = 0, cand_bytes
  local part = {}
  for i, f in ipairs(cand) do
    if check_cancel() then R.cancelled = true; return end
    local h = hash("head -c 1048576 -- " .. U.shq(f.path) .. " | " .. hasher)
    if h then
      local k = f.size .. ":" .. h
      part[k] = part[k] or {}
      table.insert(part[k], f)
    end
    done_b = done_b + math.min(f.size, 1048576)
    if i % 5 == 0 then progress("hash", done_b, total_b) end
  end
  local groups = {}
  local full_total, full_done = 0, 0
  for _, l in pairs(part) do if #l > 1 and l[1].size > 1048576 then for _, f in ipairs(l) do full_total = full_total + f.size end end end
  total_b = done_b + full_total
  for _, l in pairs(part) do
    if #l > 1 then
      local fulls = {}
      for _, f in ipairs(l) do
        if check_cancel() then R.cancelled = true; return end
        local h = (f.size <= 1048576) and "p" or hash(hasher .. " -- " .. U.shq(f.path))
        if h then fulls[h] = fulls[h] or {}; table.insert(fulls[h], f) end
        if f.size > 1048576 then full_done = full_done + f.size end
        progress("hash", done_b + full_done, total_b)
      end
      for _, g in pairs(fulls) do
        if #g > 1 then
          table.sort(g, function(a, b) return a.path < b.path end)
          groups[#groups + 1] = { size = g[1].size, files = g }
        end
      end
    end
  end
  table.sort(groups, function(a, b) return a.size * (#a.files - 1) > b.size * (#b.files - 1) end)
  local wasted = 0
  for _, g in ipairs(groups) do wasted = wasted + g.size * (#g.files - 1) end
  R.groups, R.wasted = groups, wasted
end

-- ---------------------------------------------------------------------------
local function read_dev(dev, offset, len)
  local cmd = "dd if=" .. U.shq(dev) .. " bs=1 skip=" .. offset .. " count=" .. len .. " 2>/dev/null | od -An -tu1"
  local out = U.capture(cmd) or ""
  if not out:find("%d") then out = U.capture("sudo -n sh -c " .. U.shq(cmd)) or "" end
  local t = {}
  for n in out:gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return #t == len and t or nil
end

local function op_integrity()
  local items = {}
  local function add(level, text, detail) items[#items + 1] = { level = level, text = text, detail = detail } end
  local mounts = M.mounts()
  -- 1) montagem: particao que deveria gravar e esta "somente leitura" (sinal de erro)
  for _, p in ipairs(job.parts or {}) do
    if p.mp then
      if p.ro and p.mp ~= "/boot" then add("problem", "ro", { name = p.name, mp = p.mp })
      else add("ok", "mount", { name = p.name, mp = p.mp, ro = p.ro }) end
    else
      add("info", "unmounted", { name = p.name })
    end
  end
  -- 2) log do kernel
  progress("dmesg", 1, 4)
  local out, code = run("dmesg", true)
  if code ~= 0 or out == "" then
    add("skipped", "dmesg", nil)
  else
    local hits = {}
    local card = job.card or "mmcblk"
    for line in out:gmatch("[^\n]+") do
      local l = line:lower()
      local about_card = l:find(card, 1, true) ~= nil
      local fs_err = (l:find("fat-fs", 1, true) or l:find("exfat", 1, true) or l:find("ext4-fs", 1, true))
        and (l:find("error", 1, true) or l:find("corrupt", 1, true) or l:find("not properly unmounted", 1, true) or l:find("dirty", 1, true))
      local io_err = about_card and (l:find("i/o error", 1, true) or l:find("error", 1, true) or l:find("timeout", 1, true)
        or l:find("crc", 1, true) or l:find("failed", 1, true))
      if (fs_err and (about_card or not l:find("mmcblk", 1, true))) or io_err then hits[#hits + 1] = U.trim(line) end
    end
    if #hits == 0 then add("ok", "dmesg_ok", nil)
    else
      local last = {}
      for i = math.max(1, #hits - 4), #hits do last[#last + 1] = hits[i] end
      add("problem", "dmesg_err", { count = #hits, lines = last })
    end
  end
  -- 3) ext2/3/4: estado gravado no superbloco
  progress("ext4", 2, 4)
  local tool = M.has("dumpe2fs") or M.has("tune2fs")
  for _, p in ipairs(job.parts or {}) do
    if (p.fs or ""):match("^ext%d$") then
      if not tool then add("skipped", "notool", { name = p.name, tool = "dumpe2fs / tune2fs" })
      else
        local cmd = tool:match("dumpe2fs$") and (tool .. " -h " .. U.shq(p.dev)) or (tool .. " -l " .. U.shq(p.dev))
        local o, c = run(cmd, true)
        local st = o:match("Filesystem state:%s*([^\n]+)")
        local errs = tonumber(o:match("FS Error count:%s*(%d+)") or "")
        if not st then add("skipped", "ext_noread", { name = p.name })
        elseif st:find("error") or (errs and errs > 0) then add("problem", "ext_err", { name = p.name, state = U.trim(st), errors = errs })
        elseif st:find("not clean") then
          add(p.mp and "info" or "problem", "ext_notclean", { name = p.name, state = U.trim(st), mounted = p.mp ~= nil })
        else add("ok", "ext_clean", { name = p.name, state = U.trim(st) }) end
      end
    end
  end
  -- 4) exFAT: bit "falha de midia" (e "sujo" so quando desmontada; montada ele fica ligado pelo proprio sistema)
  progress("exfat", 3, 4)
  for _, p in ipairs(job.parts or {}) do
    if p.fs == "exfat" then
      local b = read_dev(p.dev, 106, 2)
      if not b then add("skipped", "exfat_noread", { name = p.name })
      else
        local flags = b[1] + b[2] * 256
        local dirty, media = (flags % 4) >= 2, (flags % 8) >= 4
        if media then add("problem", "exfat_media", { name = p.name })
        elseif dirty and not p.mp then add("problem", "exfat_dirty", { name = p.name })
        else add("ok", "exfat_ok", { name = p.name, mounted = p.mp ~= nil }) end
      end
    elseif p.fs == "vfat" then
      if p.mp then add("info", "fat_mounted", { name = p.name }) else add("info", "fat_unmounted", { name = p.name }) end
    end
  end
  R.items = items
end

-- ---------------------------------------------------------------------------
local function op_fsck()
  -- confere de novo, agora, que a particao NAO esta montada
  for _, m in ipairs(M.mounts()) do
    if m.dev == job.dev then R.refused = "mounted"; R.mp = m.mp; return end
  end
  if not job.tool then R.refused = "notool"; return end
  progress(job.tool, nil, nil)
  local args = job.fs:match("^ext") and " -n -f " or " -n "
  local out, code, sudo = run(job.tool .. args .. U.shq(job.dev), true)
  R.out, R.code, R.sudo = out, code, sudo
  local o = out:lower()
  if o:find("permission denied", 1, true) or o:find("must be root", 1, true) or o:find("sudo:", 1, true) then
    R.result = "noperm"
  elseif code == 0 then R.result = "clean"
  elseif job.fs:match("^ext") and code == 8 then R.result = "failed"
  else R.result = "errors" end
end

-- ---------------------------------------------------------------------------
local function op_trim()
  R.parts = {}
  local tool = M.has("fstrim")
  if not tool then R.error = "notool"; return end
  for i, mp in ipairs(job.mps or {}) do
    progress(mp, i - 1, #job.mps)
    local out, code = run(tool .. " -v " .. U.shq(mp), true)
    local r = { mp = mp, code = code, out = U.trim(out) }
    local lo = out:lower()
    if code == 0 then
      r.ok = true
      r.bytes = tonumber(out:match("%((%d+) bytes%)") or out:match("(%d+) bytes") or "")
    elseif lo:find("not supported", 1, true) then r.unsupported = true
    elseif lo:find("permission", 1, true) or lo:find("not permitted", 1, true) or lo:find("must be root", 1, true) then r.noperm = true end
    R.parts[#R.parts + 1] = r
  end
end

local function op_sync()
  progress("sync", nil, nil)
  R.ok = U.exec_ok("sync")
end

local function op_cleantmp()
  local dir = job.tmp
  local list = U.capture("cd " .. U.shq(dir) .. " 2>/dev/null && ls -1d job_* runtimes_job 2>/dev/null") or ""
  local n, bytes = 0, 0
  for name in list:gmatch("[^\n]+") do
    if name:match("^job_[%w_%-%.]+$") or name == "runtimes_job" then
      local kb = tonumber((U.capture("du -sk " .. U.shq(dir .. "/" .. name) .. " 2>/dev/null") or ""):match("^(%d+)") or "") or 0
      if U.exec_ok("rm -rf -- " .. U.shq(dir .. "/" .. name)) then n, bytes = n + 1, bytes + kb * 1024 end
    end
  end
  R.removed, R.bytes = n, bytes
end

local ok, err = pcall(function()
  if job.op == "analyze" then op_analyze()
  elseif job.op == "dups" then op_dups()
  elseif job.op == "integrity" then op_integrity()
  elseif job.op == "fsck" then op_fsck()
  elseif job.op == "trim" then op_trim()
  elseif job.op == "sync" then op_sync()
  elseif job.op == "cleantmp" then op_cleantmp()
  end
end)
if not ok then R.error = tostring(err) end
R.cancelled = R.cancelled or cancelled
OUT:push(R)
