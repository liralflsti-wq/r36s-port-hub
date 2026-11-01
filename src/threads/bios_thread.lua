-- =============================================================================
--  R36S PORT HUB - BIOS do Sistema (thread)
--  Operacoes: info (fonte), download, scan (BIOS do console), analyze (pacote),
--  install, restore (backup) e clean (arquivos de instalacao).
--
--  Seguranca:
--   - so le/grava dentro da pasta de BIOS detectada, da pasta de ROMs ao lado
--     dela (so para as excecoes da wiki) e de r36sporthub/bios e backups/bios
--   - pacote: formato pelos primeiros bytes, lista ANTES de extrair (recusa
--     ../, caminhos absolutos e links), teste de integridade, extracao numa
--     pasta temporaria registrada; nada do pacote e executado
--   - instalacao: backup de toda BIOS que sera trocada, diario (.journal) e
--     conferencia do MD5 depois de copiar; se algo falhar, tudo volta
--   - limpeza: so o que o proprio hub registrou (pacote e pastas temporarias)
-- =============================================================================
require("love.timer")
require("love.data")
local job = ...
local OUT = love.thread.getChannel(job.out_channel)
local IN = love.thread.getChannel(job.in_channel)
local Formats = require("core.updater.formats")
local Ref = require("core.bios_ref")
local json = require("lib.json")

local shq, capture = Formats.shq, Formats.capture
local function sh(cmd) local r = os.execute(cmd); return r == 0 or r == true end
local function phase(name, total) OUT:push({ t = "phase", phase = name, total = total }) end
local function progress(done, total) OUT:push({ t = "progress", done = done, total = total }) end
local function fail(code, detail, extra)
  local m = { t = "error", code = code, detail = detail }
  for k, v in pairs(extra or {}) do m[k] = v end
  OUT:push(m)
  error("__stop__", 0)
end
local function cancelled() return IN:pop() == "cancel" end
local function fsize(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:seek("end") or 0
  f:close()
  return s
end
local function read(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function write(p, s)
  local f = io.open(p .. ".tmp", "wb")
  if not f then return false end
  f:write(s)
  f:close()
  return os.rename(p .. ".tmp", p) and true or false
end
local function is_dir(p) return sh("test -d " .. shq(p)) end
local function is_link(p) return sh("test -L " .. shq(p)) end
local function realpath(p) return (capture("readlink -f -- " .. shq(p) .. " 2>/dev/null"):gsub("%s+$", "")) end
local function parent(p) return p:match("^(.*)/[^/]+$") end
local function free_space(p)
  local out = capture("df -Pk " .. shq(p) .. " 2>/dev/null | tail -n 1")
  local avail = out:match("^%S+%s+%d+%s+%d+%s+(%d+)")
  return avail and tonumber(avail) * 1024 or nil
end

local A = job.app_bios            -- r36sporthub/bios
local REG = A .. "/registro.json"
local JOURNAL = A .. "/.journal"
local HIST = A .. "/historico.json"
local BK = job.backups_dir        -- r36sporthub/backups/bios
local IN_MEMORY = 64 * 1024 * 1024

-- ---------------------------------------------------------------------------
-- Hashes (o LOVE calcula; so arquivos grandes usam md5sum/sha256sum do sistema)
local function hex(b) return love.data.encode("string", "hex", b):lower() end
local function hashes(path, want_sha)
  local size = fsize(path)
  if not size then return nil end
  if size <= IN_MEMORY then
    local d = read(path) or ""
    return hex(love.data.hash("md5", d)), want_sha and hex(love.data.hash("sha256", d)) or nil, size
  end
  local m = capture("md5sum " .. shq(path) .. " 2>/dev/null"):match("^(%x+)")
  local s = want_sha and capture("sha256sum " .. shq(path) .. " 2>/dev/null"):match("^(%x+)") or nil
  return m and m:lower() or nil, s and s:lower() or nil, size
end

-- ---------------------------------------------------------------------------
-- Registro do que o hub criou (a limpeza so apaga o que esta aqui)
local function reg_load()
  local d = json.decode(read(REG) or "") or {}
  d.items = type(d.items) == "table" and d.items or {}
  return d
end
local function reg_add(path, kind, extra)
  local d = reg_load()
  for _, it in ipairs(d.items) do if it.path == path then return end end
  local it = { path = path, kind = kind, time = os.time() }
  for k, v in pairs(extra or {}) do it[k] = v end
  d.items[#d.items + 1] = it
  write(REG, json.encode(d))
end
local function reg_remove(path)
  local d = reg_load()
  for i = #d.items, 1, -1 do if d.items[i].path == path then table.remove(d.items, i) end end
  write(REG, json.encode(d))
end

local function hist_add(e)
  local d = json.decode(read(HIST) or "") or {}
  if type(d) ~= "table" then d = {} end
  table.insert(d, 1, e)
  while #d > 50 do table.remove(d) end
  write(HIST, json.encode(d))
end

-- ---------------------------------------------------------------------------
-- Destinos: caminho da tabela -> caminho real (sem diferenciar maiusculas, como
-- o exFAT do cartao). "@pasta/arq" fica na pasta de ROMs ao lado da de BIOS.
local function root_of(rel)
  if rel:sub(1, 1) == "@" then return job.roms_dir, rel:sub(2) end
  return job.bios_dir, rel
end

local DIRCACHE = {}
local function list_dir(dir)
  if DIRCACHE[dir] then return DIRCACHE[dir] end
  local t = {}
  local h = io.popen("ls -1A -- " .. shq(dir) .. " 2>/dev/null")
  if h then for l in h:lines() do t[#t + 1] = l end h:close() end
  DIRCACHE[dir] = t
  return t
end

--- devolve caminho real existente (ou nil), o caminho que sera usado para criar,
--- e se a pasta-mae ja existe
local function locate(rel)
  local root, r = root_of(rel)
  local cur = root
  local parts = {}
  for p in r:gmatch("[^/]+") do parts[#parts + 1] = p end
  for i, p in ipairs(parts) do
    local found
    for _, name in ipairs(list_dir(cur)) do
      if name == p then found = name; break end
    end
    if not found then
      for _, name in ipairs(list_dir(cur)) do
        if name:lower() == p:lower() then found = name; break end
      end
    end
    if not found then
      local rest = table.concat(parts, "/", i)
      return nil, cur .. "/" .. rest, i == #parts
    end
    cur = cur .. "/" .. found
  end
  return cur, cur, true
end

--- o destino fica mesmo dentro da raiz (sem pasta-link levando para fora)?
local function inside(root, path)
  local rr = realpath(root)
  local pp = parent(path)
  while pp and not is_dir(pp) do pp = parent(pp) end
  if not pp or rr == "" then return false end
  local rp = realpath(pp)
  return rp == rr or rp:sub(1, #rr + 1) == rr .. "/"
end

-- ---------------------------------------------------------------------------
local ops = {}

--- nome e tamanho do pacote (o tamanho vem do cabecalho do arquivo)
function ops.info()
  sh("mkdir -p " .. shq(A))
  local url = job.url
  local function unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
  local name = unesc((url:gsub("[?#].*$", ""):match("([^/]+)$") or "bios"))
  local res = { url = url, name = name }
  phase("source")
  res.size = tonumber(capture("sh " .. shq(job.fetch_sh) .. " head " .. shq(url) .. " 2>/dev/null"):match("%d+") or "")
  if not res.size then fail("source") end
  OUT:push({ t = "done", info = res })
end

function ops.download()
  sh("mkdir -p " .. shq(job.pkg_dir))
  local dest = job.pkg_dir .. "/" .. job.name:gsub("/", "_")
  local part = dest .. ".part"
  os.remove(part)
  local need = (job.size or 0) + 16 * 1024 * 1024
  local free = free_space(job.pkg_dir)
  if job.size and free and free < need then fail("space", tostring(need)) end
  reg_add(part, "part")
  phase("download", job.size)
  local rcf, pidf = A .. "/.dl.rc", A .. "/.dl.pid"
  os.remove(rcf); os.remove(pidf)
  sh("( sh " .. shq(job.fetch_sh) .. " get " .. shq(job.url) .. " " .. shq(part) .. " " .. shq(pidf) .. " "
    .. shq(rcf) .. " 0 >/dev/null 2>&1 & )")
  while true do
    local rc = io.open(rcf, "r")
    if rc then
      local code = tonumber((rc:read("*a") or ""):match("%d+") or "1")
      rc:close()
      if code == 143 or code == 137 then os.remove(part); reg_remove(part); OUT:push({ t = "cancelled" }); error("__stop__", 0) end
      if code ~= 0 then os.remove(part); reg_remove(part); fail("download", tostring(code)) end
      break
    end
    if cancelled() then
      local p = io.open(pidf, "r")
      local pid = p and (p:read("*a") or ""):match("%d+")
      if p then p:close() end
      if pid then sh("kill " .. pid .. " 2>/dev/null") end
      love.timer.sleep(0.3)
      os.remove(part); reg_remove(part)
      OUT:push({ t = "cancelled" })
      error("__stop__", 0)
    end
    progress(fsize(part) or 0, job.size)
    love.timer.sleep(0.25)
  end
  os.remove(rcf); os.remove(pidf)
  local got = fsize(part) or 0
  progress(got, job.size)
  phase("verify")
  local function bad(code, d) os.remove(part); reg_remove(part); fail(code, d) end
  if got == 0 then bad("empty") end
  if job.size and got ~= job.size then bad("size", got .. "/" .. job.size) end
  if not Formats.detect_magic(part) then bad("format") end
  local md5 = job.md5 and hashes(part) or nil
  if job.md5 and md5 ~= job.md5 then bad("md5") end
  -- pacote anterior com o mesmo nome: substituido (o registro continua o mesmo)
  os.remove(dest)
  if not os.rename(part, dest) then bad("save") end
  reg_remove(part)
  reg_add(dest, "package", { size = got, md5 = md5 })
  OUT:push({ t = "done", path = dest, size = got, md5 = md5, checked = job.md5 ~= nil })
end

-- ---------------------------------------------------------------------------
-- BIOS do console: so os arquivos que a tabela conhece (rapido)
local function scan_targets()
  local out = {}
  for k, t in pairs(Ref.targets()) do
    local real = locate(t.path)
    if real then
      local e = { path = t.path, real = real }
      if is_link(real) or is_dir(real) then
        e.special = true
      else
        e.md5, _, e.size = hashes(real)
        e.verified = Ref.md5_known_for(t.path, e.md5)
        local sizes = Ref.sizes_for(t.path)
        e.wrong = (not e.verified) and sizes ~= nil and e.size ~= nil and not sizes[e.size] or nil
      end
      out[k] = e
    end
  end
  return out
end

function ops.scan()
  phase("scan")
  if not is_dir(job.bios_dir) then fail("no_bios_dir") end
  local files = scan_targets()
  -- outros arquivos na pasta (so a contagem; nada e tocado)
  local n = tonumber((capture("find " .. shq(job.bios_dir) .. " -type f 2>/dev/null | wc -l"):match("%d+")) or "0")
  -- sistemas com jogos (pasta de ROMs com algum arquivo alem do gamelist)
  local games = {}
  for _, s in ipairs(Ref.SYSTEMS) do
    local d = job.roms_dir .. "/" .. s.id
    if is_dir(d) then
      local c = capture("find " .. shq(d) .. " -maxdepth 1 -type f ! -iname 'gamelist.xml' ! -name '.*' 2>/dev/null | head -n 1")
      if c:find("%S") then games[s.id] = true end
    end
  end
  OUT:push({ t = "done", scan = { time = os.time(), files = files, total_files = n, games = games,
    bios_dir = job.bios_dir, roms_dir = job.roms_dir } })
end

-- ---------------------------------------------------------------------------
-- Pacote: lista, testa, extrai numa pasta temporaria e identifica cada arquivo
function ops.analyze()
  local pkg = job.pkg
  local fmt = Formats.detect_magic(pkg)
  if not fmt then fail("format") end
  local tool = job.tools[fmt]
  if not tool then fail("no_tool", Formats.LABEL[fmt]) end
  phase("list")
  local entries, lerr = Formats.list(tool, pkg)
  if not entries then fail("list", lerr) end
  if #entries > 20000 then fail("too_many") end
  local total = 0
  for _, e in ipairs(entries) do
    local p = e.path
    if p:sub(1, 1) == "/" or p:find("%.%.") and (p == ".." or p:match("^%.%./") or p:match("/%.%./") or p:match("/%.%.$")) then
      fail("path", p)
    end
    if e.link then fail("link", p) end
    total = total + (e.size or 0)
  end
  phase("test")
  local tok, terr = Formats.test(tool, pkg)
  if not tok then fail("integrity", terr) end
  local free = free_space(A)
  if free and total > 0 and free < total + 32 * 1024 * 1024 then fail("space", tostring(total)) end
  -- pasta temporaria: registrada ANTES de criar (a limpeza a reconhece)
  local id = os.date("%Y%m%d-%H%M%S")
  local tmp = A .. "/tmp/" .. id
  sh("mkdir -p " .. shq(A .. "/tmp"))
  reg_add(tmp, "tmp", { pkg = pkg })
  sh("rm -rf " .. shq(tmp) .. " && mkdir -p " .. shq(tmp))
  phase("extract")
  local xok, xerr = Formats.extract(tool, pkg, tmp)
  if not xok then fail("extract", xerr) end
  -- nada de links ou arquivos especiais depois de extrair
  local special = capture("find " .. shq(tmp) .. " ! -type f ! -type d 2>/dev/null | head -n 1")
  if special:find("%S") then sh("rm -rf " .. shq(tmp)); reg_remove(tmp); fail("link", special:gsub("%s+$", "")) end
  -- arquivos extraidos
  local files = {}
  local h = io.popen("cd " .. shq(tmp) .. " && find . -type f 2>/dev/null")
  if h then for l in h:lines() do files[#files + 1] = l:gsub("^%./", "") end h:close() end
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  phase("hash", #files)
  local items, seen = {}, {}
  for i, rel in ipairs(files) do
    if cancelled() then OUT:push({ t = "cancelled" }); error("__stop__", 0) end
    local abs = tmp .. "/" .. rel
    local md5, sha, size = hashes(abs, true)
    local c = Ref.classify(rel, size, md5)
    local it = { rel = rel, size = size, md5 = md5, sha256 = sha, kind = c.kind, target = c.target,
      verified = c.verified or false, system = c.system }
    if c.kind == "bios" or c.kind == "name" then
      if seen[md5] then
        it.kind, it.dup_of = "dup", seen[md5]
      else
        seen[md5] = rel
      end
    end
    -- destino: existe? e identico?
    if it.target and it.kind ~= "dup" then
      local targets = { it.target }
      local tinfo = Ref.targets()[it.target:lower()]
      for _, sys in ipairs(tinfo and tinfo.systems or {}) do
        for _, s in ipairs(Ref.SYSTEMS) do
          if s.id == sys then for _, cp in ipairs((s.copies or {})[tinfo.path] or {}) do targets[#targets + 1] = cp end end
        end
      end
      it.dests = {}
      for _, t in ipairs(targets) do
        local root, r = root_of(t)
        local real, create = locate(t)
        local d = { target = t, real = real, create = create }
        if t:sub(1, 1) == "@" then
          -- pasta de ROMs do sistema precisa existir (a wiki manda por la; o hub nao cria)
          local sysdir = root .. "/" .. (r:match("^([^/]+)/") or "")
          d.no_folder = not is_dir(sysdir)
        end
        if real then
          if is_link(real) or is_dir(real) then d.special = true
          else
            d.md5 = hashes(real)
            d.verified = Ref.md5_known_for(t, d.md5)
            d.same = d.md5 == md5
          end
        end
        d.inside = inside(root, create)
        it.dests[#it.dests + 1] = d
      end
    end
    items[#items + 1] = it
    progress(i, #files)
  end
  OUT:push({ t = "done", analysis = { id = id, tmp = tmp, pkg = pkg, pkg_name = pkg:match("([^/]+)$"), time = os.time(),
    format = fmt, tool = tool.name, items = items, bios_dir = job.bios_dir, roms_dir = job.roms_dir, db = Ref.db().source } })
end

-- ---------------------------------------------------------------------------
-- Instalacao com backup e diario
local function copy_file(src, dst)
  local fi = io.open(src, "rb")
  if not fi then return false end
  local fo = io.open(dst, "wb")
  if not fo then fi:close(); return false end
  while true do
    local b = fi:read(1024 * 1024)
    if not b then break end
    if not fo:write(b) then fi:close(); fo:close(); return false end
  end
  fi:close()
  fo:close()
  return true
end

--- caminho dentro do backup que preserva a estrutura: bios/<...> ou roms/<...>
local function bk_rel(target)
  if target:sub(1, 1) == "@" then return "roms/" .. target:sub(2) end
  return "bios/" .. target
end

local function rollback(done, bkdir, made_dirs)
  for i = #done, 1, -1 do
    local d = done[i]
    if d.existed then
      local b = bkdir .. "/files/" .. bk_rel(d.target)
      if copy_file(b, d.path .. ".porthub_restore") then os.rename(d.path .. ".porthub_restore", d.path) end
    else
      os.remove(d.path)
    end
  end
  -- pastas criadas por esta instalacao: so saem se ficaram vazias
  for i = #(made_dirs or {}), 1, -1 do sh("rmdir " .. shq(made_dirs[i]) .. " 2>/dev/null") end
end

function ops.install()
  local items = job.items or {}
  if #items == 0 then fail("nothing") end
  local stamp = os.date("%Y%m%d-%H%M%S")
  local bkdir = BK .. "/" .. stamp
  -- conferencias antes de mexer em qualquer coisa
  phase("check", #items)
  for i, it in ipairs(items) do
    local md5 = hashes(it.src)
    if md5 ~= it.md5 then fail("src_changed", it.rel) end
    local root = it.target:sub(1, 1) == "@" and job.roms_dir or job.bios_dir
    local real, create = locate(it.target)
    it.path = real or create
    if not inside(root, it.path) then fail("outside", it.target) end
    if real and (is_link(real) or is_dir(real)) then fail("special", it.target) end
    it.existed = real ~= nil
    if real then
      local cur = hashes(real)
      if cur == it.md5 then it.skip = true end
      it.old_md5 = cur
      if not it.skip and not it.replace then fail("not_confirmed", it.target) end
    end
    progress(i, #items)
  end
  local need = 0
  for _, it in ipairs(items) do if not it.skip then need = need + (fsize(it.src) or 0) * 2 end end
  local free = free_space(job.bios_dir)
  if free and free < need + 8 * 1024 * 1024 then fail("space", tostring(need)) end
  -- backup de tudo que sera trocado
  phase("backup")
  local meta = { id = stamp, time = os.time(), bios_dir = job.bios_dir, roms_dir = job.roms_dir, files = {}, state = "partial",
    package = job.pkg_name }
  local has_backup = false
  for _, it in ipairs(items) do
    if it.existed and not it.skip then
      local b = bkdir .. "/files/" .. bk_rel(it.target)
      sh("mkdir -p " .. shq(parent(b)))
      if not copy_file(it.path, b) then fail("backup", it.target) end
      local m, s, size = hashes(b, true)
      if m ~= it.old_md5 then fail("backup", it.target) end
      meta.files[#meta.files + 1] = { target = it.target, path = it.path, size = size, md5 = m, sha256 = s, date = os.date("%Y-%m-%d %H:%M:%S") }
      has_backup = true
    end
  end
  if has_backup then
    meta.state = "complete"
    if not write(bkdir .. "/meta.json", json.encode(meta)) then fail("backup", "meta.json") end
  end
  -- diario: se o console desligar no meio, a proxima abertura desfaz o que ficou pela metade
  local jr = { state = "installing", backup = has_backup and stamp or nil, time = os.time(), items = {} }
  for _, it in ipairs(items) do
    if not it.skip then jr.items[#jr.items + 1] = { target = it.target, path = it.path, existed = it.existed, md5 = it.md5 } end
  end
  write(JOURNAL, json.encode(jr))
  phase("install", #items)
  local done, results, made = {}, {}, {}
  local fail_at = tonumber(job.simulate_fail or "")
  for i, it in ipairs(items) do
    local r = { target = it.target, rel = it.rel, md5 = it.md5, old_md5 = it.old_md5 }
    if it.skip then
      r.action = "same"
    else
      local ok = true
      local dir = parent(it.path)
      if not is_dir(dir) then
        -- guarda cada pasta que nao existia (para desfazer se falhar)
        local miss, p = {}, dir
        while p and not is_dir(p) do table.insert(miss, 1, p); p = parent(p) end
        ok = sh("mkdir -p " .. shq(dir))
        for _, m in ipairs(miss) do made[#made + 1] = m end
      end
      local tmpf = it.path .. ".porthub_new"
      ok = ok and copy_file(it.src, tmpf)
      if fail_at and i == fail_at then ok = false; os.remove(tmpf) end
      if ok then
        if not os.rename(tmpf, it.path) then ok = false; os.remove(tmpf) end
      end
      if ok then
        done[#done + 1] = { target = it.target, path = it.path, existed = it.existed }
        local m = hashes(it.path)
        if m ~= it.md5 then ok = false end
      end
      if not ok then
        phase("restore")
        rollback(done, bkdir, made)
        os.remove(JOURNAL)
        hist_add({ time = os.time(), op = "install", result = "error", failed = it.target, backup = has_backup and stamp or nil,
          package = job.pkg_name, items = { { target = it.target, action = "error" } } })
        fail("install_restored", it.target)
      end
      r.action = it.existed and "replace" or "new"
    end
    results[#results + 1] = r
    progress(i, #items)
  end
  os.remove(JOURNAL)
  hist_add({ time = os.time(), op = "install", result = "ok", backup = has_backup and stamp or nil, package = job.pkg_name, items = results })
  OUT:push({ t = "done", results = results, backup = has_backup and stamp or nil })
end

--- volta os arquivos de um backup (cada um conferido pelo MD5 gravado)
function ops.restore()
  local bkdir = BK .. "/" .. job.backup
  local meta = json.decode(read(bkdir .. "/meta.json") or "")
  if type(meta) ~= "table" or meta.state ~= "complete" or type(meta.files) ~= "table" then fail("backup_missing") end
  phase("restore", #meta.files)
  local results = {}
  for i, f in ipairs(meta.files) do
    local b = bkdir .. "/files/" .. bk_rel(f.target)
    if hashes(b) ~= f.md5 then fail("backup_missing", f.target) end
    local root = f.target:sub(1, 1) == "@" and job.roms_dir or job.bios_dir
    if f.path:sub(1, #root + 1) ~= root .. "/" or not inside(root, f.path) then fail("outside", f.target) end
    if is_link(f.path) or is_dir(f.path) then fail("special", f.target) end
    sh("mkdir -p " .. shq(parent(f.path)))
    if not copy_file(b, f.path .. ".porthub_restore") or not os.rename(f.path .. ".porthub_restore", f.path) then
      fail("restore", f.target)
    end
    if hashes(f.path) ~= f.md5 then fail("restore", f.target) end
    results[#results + 1] = { target = f.target, action = "restored", md5 = f.md5 }
    progress(i, #meta.files)
  end
  hist_add({ time = os.time(), op = "restore", result = "ok", backup = job.backup, items = results })
  OUT:push({ t = "done", results = results })
end

--- limpeza: so os itens do registro, conferidos de novo (dentro de r36sporthub/bios, sem links)
function ops.clean()
  phase("clean")
  local root = realpath(A)
  local removed, freed = {}, 0
  for _, p in ipairs(job.paths or {}) do
    local listed = false
    for _, it in ipairs(reg_load().items) do if it.path == p then listed = true end end
    local rp = realpath(p)
    local ok = listed and root ~= "" and rp ~= "" and rp ~= root and rp:sub(1, #root + 1) == root .. "/" and not is_link(p)
      and not p:find("/%.%./") and p:sub(1, #A + 1) == A .. "/"
    if ok then
      local kb = tonumber((capture("du -sk " .. shq(p) .. " 2>/dev/null"):match("^(%d+)")) or "0")
      if sh("rm -rf " .. shq(p)) then
        freed = freed + kb * 1024
        removed[#removed + 1] = p
        reg_remove(p)
      end
    elseif listed and rp == "" then
      reg_remove(p)     -- ja nao existe
    end
  end
  hist_add({ time = os.time(), op = "clean", result = "ok", freed = freed, count = #removed })
  OUT:push({ t = "done", removed = removed, freed = freed })
end

local ok, err = pcall(ops[job.op])
if not ok and err ~= "__stop__" then
  OUT:push({ t = "error", code = "internal", detail = tostring(err) })
end
