-- =============================================================================
--  R36S PORT HUB - atualizacoes (thread)
--  Operacoes: probe (pacotes da pasta update), analyze (conteudo sem extrair),
--  install, restore (de um backup) e download (atualizacao via rede).
--
--  Seguranca da instalacao:
--   - formato pelos primeiros bytes; ferramenta testada no console
--   - lista o conteudo ANTES de extrair: recusa ../, caminhos absolutos,
--     links, itens fora do pacote e qualquer arquivo fora do R36S PORT HUB
--     (so "R36S PORT HUB.sh" e r36sporthub/..., nunca as pastas de dados)
--   - teste de integridade do arquivo, extracao numa pasta temporaria,
--     nova conferencia no disco (so arquivos comuns) e SHA-256 de cada arquivo
--   - destino conferido: nenhuma pasta-link levando para fora do hub
--   - nada do pacote e executado
--   - backup dos arquivos trocados + diario; se algo falhar, tudo volta
-- =============================================================================
require("love.timer")
require("love.filesystem")
require("love.data")
local job = ...
local OUT = love.thread.getChannel(job.out_channel)
local IN = love.thread.getChannel(job.in_channel)
local Formats = require("core.updater.formats")
local Rules = require("core.updater.rules")
local Integrity = require("core.updater.integrity")
local Backup = require("core.updater.backup")

local shq, capture = Formats.shq, Formats.capture
local function sh(cmd) local r = os.execute(cmd); return r == 0 or r == true end
local function fsize(p)
  local f = io.open(p, "rb")
  if not f then return 0 end
  local s = f:seek("end") or 0
  f:close()
  return s
end
local function phase(name, total) OUT:push({ t = "phase", phase = name, total = total }) end
local function progress(done, total) OUT:push({ t = "progress", done = done, total = total }) end
local function fail(code, detail) OUT:push({ t = "error", code = code, detail = detail }); error("__stop__", 0) end
local function parent(p) return p:match("^(.*)/[^/]+$") end
local function exists(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

local APP, PORTS = job.app_dir, job.ports_dir
local W = job.tmp_dir .. "/update_job"
local STAGE = W .. "/stage"

--- destino real de um caminho do pacote
local function dest(rel) return PORTS .. "/" .. rel end

-- ---------------------------------------------------------------------------
-- Versao de um pacote completo sem manifesto: le config.lua de dentro do game.love
local function game_love_version(tool, ziptool, arch, member)
  if not ziptool then return nil end
  sh("mkdir -p " .. shq(W))
  local tmp = W .. "/probe_game.love"
  local data = Formats.cat(tool, arch, member, 96 * 1024 * 1024)
  if not data or #data < 4 then return nil end
  local f = io.open(tmp, "wb")
  if not f then return nil end
  f:write(data); f:close()
  data = nil
  local cfg = Formats.cat(ziptool, tmp, "config.lua", 256 * 1024) or ""
  os.remove(tmp)
  local num = cfg:match('C%.VERSION_NUM%s*=%s*"([^"]+)"')
  local label = cfg:match('C%.VERSION%s*=%s*L%("([^"]+)"%)') or cfg:match('C%.VERSION%s*=%s*"([^"]+)"')
  return num, label
end

-- ---------------------------------------------------------------------------
-- Analise do conteudo (sem extrair)
local function inspect(arch, full_version)
  local fmt = Formats.detect_magic(arch)
  if not fmt then fail("format") end
  local tool = job.tools[fmt]
  if not tool then fail("no_tool", fmt) end
  local entries, err = Formats.list(tool, arch)
  if not entries then fail("list", err) end
  if #entries > Rules.MAX_FILES then fail("too_many") end

  -- raiz do pacote: onde esta o manifesto (ou r36sporthub/game.love), no maximo 1 pasta abaixo
  local base, mode
  for _, e in ipairs(entries) do
    if not e.dir then
      local b = e.path:match("^(.-)update_manifest%.json$")
      if b and (b == "" or b:match("^[^/]+/$")) then base, mode = b, "manifest"; break end
    end
  end
  if not base then
    for _, e in ipairs(entries) do
      local b = not e.dir and e.path:match("^(.-)r36sporthub/game%.love$")
      if b and (b == "" or b:match("^[^/]+/$")) then base, mode = b, "full"; break end
    end
  end
  local r = { format = fmt, tool = tool.name, mode = mode or "unknown", problems = {}, files = {}, sizes = {}, total = 0 }
  local function problem(code, path) r.problems[#r.problems + 1] = { code = code, path = path } end
  if not base then problem("structure"); return r end
  r.base = base

  for _, e in ipairs(entries) do
    local p = e.path
    if p .. "/" == base then
      -- a propria pasta do pacote
    elseif p:sub(1, #base) ~= base then
      problem("outside", p)
    else
      local rel = p:sub(#base + 1)
      if e.link then problem("link", rel)
      elseif e.dir then
        if rel ~= Rules.APP and not Rules.check_path(rel) then problem("path", rel) end
      elseif Rules.IGNORED_ROOT[rel] then
        -- manifesto e leia-me: lidos, nunca instalados
      else
        local ok, why = Rules.check_path(rel)
        if not ok then problem(why == "protegido" and "protected" or "path", rel)
        else
          r.files[#r.files + 1] = rel
          r.sizes[rel] = e.size
          r.total = r.total + (e.size or 0)
        end
      end
    end
  end
  if r.total > Rules.MAX_TOTAL then problem("too_big") end
  if #r.files == 0 then problem("empty") end
  table.sort(r.files)

  if mode == "manifest" then
    local text = Formats.cat(tool, arch, base .. Rules.MANIFEST, 2 * 1024 * 1024)
    local m, merr = Rules.parse_manifest(text)
    if not m then
      problem("manifest", merr)
    else
      r.manifest = m
      r.version = m.version
      local listed = {}
      for _, rel in ipairs(r.files) do
        listed[rel] = true
        if not m.by_path[rel] then problem("not_in_manifest", rel) end
      end
      for _, f in ipairs(m.files) do
        if not listed[f.path] then problem("missing", f.path)
        elseif f.size and r.sizes[f.path] and f.size ~= r.sizes[f.path] then problem("size", f.path) end
      end
    end
  elseif mode == "full" and full_version then
    local num, label = game_love_version(tool, job.tools.zip, arch, base .. "r36sporthub/game.love")
    r.version, r.version_label = num, label
  end
  return r
end

--- compara com o que esta instalado: o que sera trocado/criado e se o destino e seguro
local function plan_targets(r)
  sh("mkdir -p " .. shq(W))
  local listf = W .. "/targets.txt"
  local f = io.open(listf, "wb")
  for _, rel in ipairs(r.files) do f:write(rel, "\n") end
  f:close()
  local real_app = capture("readlink -f -- " .. shq(APP) .. " 2>/dev/null"):gsub("%s+$", "")
  local real_ports = capture("readlink -f -- " .. shq(PORTS) .. " 2>/dev/null"):gsub("%s+$", "")
  local out = capture("cd " .. shq(PORTS) .. " && while IFS= read -r p; do "
    .. "if [ -L \"$p\" ]; then echo \"L|$p\"; elif [ -d \"$p\" ]; then echo \"D|$p\"; "
    .. "elif [ -e \"$p\" ]; then echo \"E|$(stat -c %s -- \"$p\")|$p\"; fi; "
    .. "d=$(dirname -- \"$p\"); while [ ! -d \"$d\" ] && [ \"$d\" != . ]; do d=$(dirname -- \"$d\"); done; "
    .. "echo \"R|$(readlink -f -- \"$d\")|$p\"; done < " .. shq(listf) .. " 2>/dev/null")
  r.replace, r.new, r.backup_bytes = {}, {}, 0
  local exists = {}
  for line in out:gmatch("[^\n]+") do
    local k = line:sub(1, 1)
    if k == "L" then r.problems[#r.problems + 1] = { code = "dest_link", path = line:sub(3) }
    elseif k == "D" then r.problems[#r.problems + 1] = { code = "dest_dir", path = line:sub(3) }
    elseif k == "E" then
      local size, p = line:match("^E|(%d+)|(.+)$")
      if p then exists[p] = true; r.backup_bytes = r.backup_bytes + tonumber(size) end
    elseif k == "R" then
      local real, p = line:match("^R|(.-)|(.+)$")
      if p then
        local okd = (p == Rules.LAUNCHER and real == real_ports)
          or (p ~= Rules.LAUNCHER and real_app ~= "" and (real == real_app or real:sub(1, #real_app + 1) == real_app .. "/"))
        if not okd then r.problems[#r.problems + 1] = { code = "dest_outside", path = p } end
      end
    end
  end
  for _, rel in ipairs(r.files) do
    if exists[rel] then r.replace[#r.replace + 1] = rel else r.new[#r.new + 1] = rel end
  end
  os.remove(listf)
end

local function compat(r)
  if r.manifest then
    local ok, why = Rules.compat(r.manifest, job.current_version)
    if not ok then r.problems[#r.problems + 1] = { code = why } end
  end
  if r.version then r.cmp = Rules.compare(r.version, job.current_version) end
end

local function public(r)
  local m = r.manifest
  return { format = r.format, tool = r.tool, mode = r.mode, version = r.version, version_label = r.version_label,
    name = m and m.name, label = m and m.version_label, date = m and m.date, description = m and m.description,
    min_version = m and m.min_version, max_version = m and m.max_version,
    files = #r.files, total = r.total, replace = r.replace and #r.replace, new = r.new and #r.new,
    backup_bytes = r.backup_bytes, problems = r.problems, cmp = r.cmp,
    changes = m and m.changes, fixes = m and m.fixes }
end

-- ---------------------------------------------------------------------------
-- Troca de arquivos e desfazer
local function chmod_exec(rel)
  if rel:match("%.sh$") or rel:match("^" .. Rules.APP .. "/bin/") then
    sh("chmod +x " .. shq(dest(rel)) .. " 2>/dev/null")
  end
end

--- copia um arquivo para o lugar por renomeacao (o arquivo antigo continua valido ate a troca)
local function place_copy(src, dst)
  local tmp = dst .. ".porthub_new"
  if not sh("mkdir -p " .. shq(parent(dst)) .. " && cp -p " .. shq(src) .. " " .. shq(tmp) .. " 2>/dev/null") then
    os.remove(tmp); return false
  end
  if not os.rename(tmp, dst) then os.remove(tmp); return false end
  return true
end

--- devolve os arquivos de um backup (usado ao falhar e no "restaurar")
local function restore_from(id, meta)
  local B = Backup.dir(APP) .. "/" .. id .. "/files/"
  local ok = true
  for _, rel in ipairs(meta.added or {}) do
    if Rules.check_path(rel) then os.remove(dest(rel)) end
  end
  for _, rel in ipairs(meta.files or {}) do
    if Rules.check_path(rel) then
      if not place_copy(B .. rel, dest(rel)) then ok = false end
      chmod_exec(rel)
    end
  end
  sh("sync")
  return ok
end

--- backup dos arquivos que vao mudar. Devolve o meta
local function make_backup(id, replace, added, info)
  local B = Backup.dir(APP) .. "/" .. id
  if not sh("mkdir -p " .. shq(B .. "/files")) then fail("backup") end
  local meta = { id = id, created = os.time(), from = job.current_version, from_label = job.current_label,
    to = info.to, package = info.package, origin = info.origin, files = replace, added = added, state = "incomplete", size = 0 }
  Backup.write_meta(APP, id, meta)
  phase("backup", #replace)
  for i, rel in ipairs(replace) do
    local dst = B .. "/files/" .. rel
    if not sh("mkdir -p " .. shq(parent(dst)) .. " && cp -p " .. shq(dest(rel)) .. " " .. shq(dst) .. " 2>/dev/null") then
      fail("backup", rel)
    end
    meta.size = meta.size + fsize(dst)
    if i % 5 == 0 then progress(i, #replace) end
  end
  local f = io.open(B .. "/added.txt", "wb")
  if f then for _, rel in ipairs(added) do f:write(rel, "\n") end f:close() end
  Backup.write_meta(APP, id, meta)
  sh("sync")
  return meta
end

local function space_check(need)
  local out = capture("df -Pk " .. shq(APP) .. " 2>/dev/null | tail -n 1")
  local avail = tonumber(out:match("^%S+%s+%d+%s+%d+%s+(%d+)") or "")
  if avail and avail * 1024 < need then fail("space", tostring(need)) end
end

-- ---------------------------------------------------------------------------
local ops = {}

function ops.probe()
  local res = {}
  for i, p in ipairs(job.packages) do
    local ok, r = pcall(function()
      local fmt = Formats.detect_magic(p.path)
      if not fmt then return { error = "format" } end
      local tool = job.tools[fmt]
      if not tool then return { format = fmt, error = "no_tool" } end
      local entries = Formats.list(tool, p.path)
      if not entries then return { format = fmt, error = "list" } end
      for _, e in ipairs(entries) do
        local b = not e.dir and e.path:match("^(.-)update_manifest%.json$")
        if b and (b == "" or b:match("^[^/]+/$")) then
          local m = Rules.parse_manifest(Formats.cat(tool, p.path, e.path, 2 * 1024 * 1024))
          if m then return { format = fmt, mode = "manifest", version = m.version, label = m.version_label, name = m.name } end
          return { format = fmt, mode = "manifest", error = "manifest" }
        end
      end
      for _, e in ipairs(entries) do
        local b = not e.dir and e.path:match("^(.-)r36sporthub/game%.love$")
        if b and (b == "" or b:match("^[^/]+/$")) then return { format = fmt, mode = "full" } end
      end
      return { format = fmt, mode = "unknown" }
    end)
    if not ok then
      if r == "__stop__" then r = { error = "list" } else r = { error = "internal", detail = tostring(r) } end
    end
    res[p.path] = r
    progress(i, #job.packages)
  end
  OUT:push({ t = "done", probe = res })
end

function ops.analyze()
  phase("verify")
  local r = inspect(job.archive, true)
  if r.base then plan_targets(r) end
  compat(r)
  sh("rm -rf " .. shq(W))
  OUT:push({ t = "done", report = public(r) })
end

function ops.install()
  local arch = job.archive
  -- 1) conteudo, caminhos e compatibilidade
  phase("verify")
  local r = inspect(arch, true)
  if r.base then plan_targets(r) end
  compat(r)
  if #r.problems > 0 then OUT:push({ t = "error", code = "invalid", report = public(r) }); error("__stop__", 0) end
  if r.mode == "unknown" then fail("structure") end
  local tool = job.tools[r.format]

  -- 2) integridade do arquivo compactado
  phase("integrity")
  local okt, terr = Formats.test(tool, arch)
  if not okt then fail("integrity", terr) end

  -- 3) espaco: extracao + backup + folga
  space_check(r.total + r.backup_bytes + 16 * 1024 * 1024)

  -- 4) extracao numa pasta temporaria
  phase("extract")
  sh("rm -rf " .. shq(W) .. " && mkdir -p " .. shq(STAGE))
  local okx, xerr = Formats.extract(tool, arch, STAGE)
  if not okx then sh("rm -rf " .. shq(W)); fail("extract", xerr) end
  local odd = capture("cd " .. shq(STAGE) .. " && find . ! -type f ! -type d 2>/dev/null | head -n 3")
  if odd:find("%S") then sh("rm -rf " .. shq(W)); fail("link", odd) end
  local root = STAGE .. "/" .. r.base
  local nfiles = tonumber(capture("cd " .. shq(STAGE) .. " && find . -type f | wc -l"):match("%d+") or "0")
  local expected = #r.files
  for name in pairs(Rules.IGNORED_ROOT) do if exists(root .. name) then expected = expected + 1 end end
  if nfiles ~= expected then sh("rm -rf " .. shq(W)); fail("extract_mismatch", nfiles .. "/" .. expected) end

  -- 5) SHA-256 de cada arquivo (pacotes com manifesto)
  if r.manifest then
    phase("hash", r.total)
    local done = 0
    for _, f in ipairs(r.manifest.files) do
      local sum = Integrity.sha256_file(root .. f.path)
      if not sum or sum ~= f.sha256 then sh("rm -rf " .. shq(W)); fail("hash", f.path) end
      done = done + fsize(root .. f.path)
      progress(done, r.total)
    end
  else
    for _, rel in ipairs(r.files) do
      if not exists(root .. rel) then sh("rm -rf " .. shq(W)); fail("extract_mismatch", rel) end
    end
  end

  -- 6) backup + diario
  local to = r.version or "?"
  local id = Backup.new_id(job.current_version)
  local meta = make_backup(id, r.replace, r.new, { to = to, package = job.package, origin = job.origin })
  Backup.journal_write(APP, { state = "applying", backup = id, from = job.current_version, to = to,
    origin = job.origin, package = job.package })

  -- 7) instalacao (troca por renomeacao; desfaz tudo se algo falhar)
  phase("install", #r.files)
  for i, rel in ipairs(r.files) do
    local src, dst = root .. rel, dest(rel)
    local ok = sh("mkdir -p " .. shq(parent(dst)))
      and (os.rename(src, dst) or place_copy(src, dst))
    if not ok or (i > 1 and IN:pop() == "__simulate_fail__") then
      phase("restore")
      local rok = restore_from(id, meta)
      if rok then
        Backup.journal_clear(APP)
        Backup.delete(APP, id)
      end
      sh("rm -rf " .. shq(W))
      fail(rok and "install_restored" or "install_restore_failed", rel)
    end
    chmod_exec(rel)
    if i % 3 == 0 then progress(i, #r.files) end
  end
  progress(#r.files, #r.files)

  -- 8) finalizacao
  phase("finalize")
  sh("sync")
  meta.state = "complete"
  Backup.write_meta(APP, id, meta)
  Backup.journal_write(APP, { state = "pending", backup = id, from = job.current_version, to = to,
    origin = job.origin, package = job.package })
  Backup.prune(APP, Backup.KEEP, id)
  sh("rm -rf " .. shq(W))
  OUT:push({ t = "done", to = to, to_label = r.version_label or (r.manifest and r.manifest.version_label), from_label = job.current_label,
    backup = id, replaced = #r.replace, added = #r.new,
    description = r.manifest and r.manifest.description, changes = r.manifest and r.manifest.changes,
    fixes = r.manifest and r.manifest.fixes })
end

function ops.restore()
  local id = job.backup
  if not Backup.valid_id(id) then fail("backup_missing") end
  local meta = Backup.read_meta(APP, id)
  if not meta or meta.state ~= "complete" then fail("backup_missing") end
  phase("verify")
  local B = Backup.dir(APP) .. "/" .. id .. "/files/"
  local all = {}
  for _, rel in ipairs(meta.files or {}) do
    if not Rules.check_path(rel) then fail("path", rel) end
    if not exists(B .. rel) then fail("backup_missing", rel) end
    all[#all + 1] = rel
  end
  for _, rel in ipairs(meta.added or {}) do
    if not Rules.check_path(rel) then fail("path", rel) end
    all[#all + 1] = rel
  end
  -- backup do estado atual (a restauracao tambem pode ser desfeita)
  local r = { files = all, problems = {} }
  plan_targets(r)
  for _, p in ipairs(r.problems) do fail(p.code, p.path) end
  space_check(r.backup_bytes + 8 * 1024 * 1024)
  local id2 = Backup.new_id(job.current_version)
  local meta2 = make_backup(id2, r.replace, r.new, { to = meta.from, package = "backup " .. id, origin = "backup" })
  Backup.journal_write(APP, { state = "applying", backup = id2, from = job.current_version, to = meta.from, origin = "backup", package = id })
  phase("install", #all)
  local ok = restore_from(id, meta)
  if not ok then
    phase("restore")
    local rok = restore_from(id2, meta2)
    if rok then Backup.journal_clear(APP); Backup.delete(APP, id2) end
    fail(rok and "install_restored" or "install_restore_failed")
  end
  phase("finalize")
  meta2.state = "complete"
  Backup.write_meta(APP, id2, meta2)
  Backup.journal_write(APP, { state = "pending", backup = id2, from = job.current_version, to = meta.from, origin = "backup", package = id })
  Backup.prune(APP, Backup.KEEP, id2)
  OUT:push({ t = "done", to = meta.from, to_label = meta.from_label, backup = id2 })
end

function ops.download()
  sh("rm -rf " .. shq(W) .. " && mkdir -p " .. shq(W))
  local part = job.dest .. ".part"
  os.remove(part)
  phase("download", job.size > 0 and job.size or nil)
  local rcf, pidf = W .. "/dl.rc", W .. "/dl.pid"
  sh("( sh " .. shq(job.fetch_sh) .. " get " .. shq(job.url) .. " " .. shq(part) .. " " .. shq(pidf) .. " "
    .. shq(rcf) .. " 0 >/dev/null 2>&1 & )")
  local total = job.size > 0 and job.size or nil
  if not total then
    total = tonumber(capture("sh " .. shq(job.fetch_sh) .. " head " .. shq(job.url) .. " 2>/dev/null"):match("%d+") or "")
  end
  while true do
    local rc = io.open(rcf, "r")
    if rc then
      local code = tonumber((rc:read("*a") or ""):match("%d+") or "1")
      rc:close()
      if code == 143 or code == 137 then os.remove(part); OUT:push({ t = "cancelled" }); error("__stop__", 0) end
      if code ~= 0 then os.remove(part); fail("download", tostring(code)) end
      break
    end
    if IN:pop() == "cancel" then
      local p = io.open(pidf, "r")
      local pid = p and (p:read("*a") or ""):match("%d+")
      if p then p:close() end
      if pid then sh("kill " .. pid .. " 2>/dev/null") end
      love.timer.sleep(0.3)
      os.remove(part)
      sh("rm -rf " .. shq(W))
      OUT:push({ t = "cancelled" })
      error("__stop__", 0)
    end
    progress(fsize(part), total)
    love.timer.sleep(0.25)
  end
  local got = fsize(part)
  progress(got, total)
  phase("integrity")
  if got == 0 then os.remove(part); fail("empty_download") end
  if job.size > 0 and got ~= job.size then os.remove(part); fail("download_size", got .. "/" .. job.size) end
  if job.sha256 ~= "" then
    local sum = Integrity.sha256_file(part)
    if sum ~= job.sha256 then os.remove(part); fail("download_hash") end
  end
  if not Formats.detect_magic(part) then os.remove(part); fail("format") end
  if not os.rename(part, job.dest) then os.remove(part); fail("download_save") end
  sh("rm -rf " .. shq(W))
  OUT:push({ t = "done", path = job.dest })
end

local ok, err = pcall(ops[job.op])
if not ok and err ~= "__stop__" then
  OUT:push({ t = "error", code = "internal", detail = tostring(err) })
end
