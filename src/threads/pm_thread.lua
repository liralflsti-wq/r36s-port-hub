-- =============================================================================
--  R36S PORT HUB - thread do Gerenciador do PortMaster
--
--  Operacoes: check (descobre a versao estavel), install, update, verify, repair.
--  Fluxo seguro (install/update/repair):
--    download temporario -> validacao (md5 oficial e sha256 quando a API informa,
--    teste do ZIP, caminhos, estrutura, arquitetura e sistema) -> extracao para
--    pasta temporaria (mesma particao do destino) -> backup dos arquivos que vao
--    mudar -> aplicacao (arquivo novo + rename, seguro com programas abertos) ->
--    validacao (md5 de cada arquivo) -> limpeza so depois do sucesso.
--  Se a aplicacao falhar, o backup e restaurado e a restauracao e conferida (md5).
--  Um diario (.porthub_pm/state) permite concluir a restauracao na proxima
--  abertura se o console desligar no meio.
--  Nunca: executa scripts baixados, usa sudo, apaga ports/saves/configuracoes,
--  remove runtimes (libs/*.squashfs) ou mexe fora da pasta do PortMaster.
-- =============================================================================
require("love.timer")

local job = ...
local I18N = require("lib.i18n")
I18N.set(job.lang or "pt-BR")
local json = require("lib.json")
local P = require("core.pmcore")
local OUT = love.thread.getChannel(job.out_channel)
local IN = love.thread.getChannel(job.in_channel)

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end
local function ok(r) return r == 0 or r == true end
local function sh(cmd) return ok(os.execute(cmd)) end
local function capture(cmd)
  local h = io.popen(cmd)
  if not h then return "" end
  local s = h:read("*a") or ""
  h:close()
  return s
end
local function log(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  print("[portmaster] " .. table.concat(t, " "))
  io.stdout:flush()
end
local function send(m) OUT:push(m) end
local function exists(p) return sh("test -e " .. shq(p)) end
local function isdir(p) return sh("test -d " .. shq(p)) end
local function isfile(p) return sh("test -f " .. shq(p)) end
local function fsize(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:seek("end")
  f:close()
  return s
end
local function read_all(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function write_all(p, s)
  local f = io.open(p, "wb")
  if not f then return false end
  f:write(s)
  f:close()
  return true
end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function free_bytes(path)
  local out = capture("df -Pk " .. shq(path) .. " 2>/dev/null | tail -n 1")
  local avail = out:match("^%S+%s+%d+%s+%d+%s+(%d+)")
  return avail and tonumber(avail) * 1024 or nil
end
local function fs_type(path)
  return trim(capture("stat -f -c %T " .. shq(path) .. " 2>/dev/null")):lower()
end
--- ext2/3/4 (stat mostra "ext2/ext3"), overlay, btrfs, xfs: tem permissoes Unix
local function posix_fs(t)
  return t:find("ext") ~= nil or t == "overlayfs" or t == "overlay" or t == "btrfs" or t == "xfs" or t == "f2fs"
end
local function parent(p) return p:match("^(.*)/[^/]+$") or "" end
local function have(c) return sh("command -v " .. c .. " >/dev/null 2>&1") end

local WORK = job.tmp_dir .. "/pm_job"
local ZIP = WORK .. "/" .. P.ASSET
local PART = ZIP .. ".part"
local PIDF, RCF = WORK .. "/dl.pid", WORK .. "/dl.rc"
local SRC = P.sources()

-- ---------------------------------------------------------------------------
local cancelled, no_cancel = false, false
local function check_cancel()
  local m = IN:pop()
  while m do
    if m.t == "cancel" and not no_cancel then cancelled = true end
    m = IN:pop()
  end
  return cancelled
end

local staging -- pasta temporaria de extracao (apagada no fim)
local function cleanup()
  sh("rm -rf " .. shq(WORK) .. " 2>/dev/null")
  if staging then sh("rm -rf " .. shq(staging) .. " 2>/dev/null") end
end
local function fail(code, detail, extra)
  log("ERRO", code, detail or "")
  cleanup()
  local m = { t = "error", code = code, detail = detail or "" }
  for k, v in pairs(extra or {}) do m[k] = v end
  send(m)
end
local function cancel_done()
  log("cancelado pelo usuario")
  cleanup()
  send({ t = "cancelled" })
end
local function phase(ph, label, total) send({ t = "phase", phase = ph, label = label, total = total }) end

local function ask(m)
  m.t = "confirm"
  send(m)
  while true do
    local r = IN:demand(0.5)
    if r then
      if r.t == "answer" then return r.yes and true or false end
      if r.t == "cancel" then return false end
    end
  end
end

-- ---------------------------------------------------------------------------
-- rede
local function fetch_small(url, out, maxt)
  os.remove(out)
  local rcf, pidf = out .. ".rc", out .. ".pid"
  sh("sh " .. shq(job.fetch_sh) .. " get " .. shq(url) .. " " .. shq(out) .. " " .. shq(pidf) .. " "
    .. shq(rcf) .. " " .. tostring(maxt or 30) .. " >/dev/null 2>&1")
  local rc = tonumber((read_all(rcf) or ""):match("%d+") or "1")
  os.remove(rcf); os.remove(pidf)
  return rc == 0 and (fsize(out) or 0) > 0, rc
end

local function fetch_big(url, out, expected)
  os.remove(RCF); os.remove(PIDF)
  sh("sh " .. shq(job.fetch_sh) .. " get " .. shq(url) .. " " .. shq(out) .. " " .. shq(PIDF) .. " "
    .. shq(RCF) .. " >" .. shq(WORK .. "/fetch.log") .. " 2>&1 &")
  local last = -1
  while true do
    love.timer.sleep(0.3)
    local s = read_all(RCF)
    if s and s:match("%d+") then return tonumber(s:match("%d+")) end
    if check_cancel() then
      local pid = (read_all(PIDF) or ""):match("%d+")
      if pid then sh("kill " .. pid .. " 2>/dev/null") end
      for _ = 1, 50 do love.timer.sleep(0.1); if read_all(RCF) then break end end
      return "cancel"
    end
    local done = fsize(out) or 0
    if done ~= last then
      send({ t = "progress", phase = "download", done = done, total = expected })
      last = done
    end
  end
end

local function md5(path) return (capture("md5sum " .. shq(path) .. " 2>/dev/null"):match("^(%x+)") or ""):lower() end
local function sha256(path) return (capture("sha256sum " .. shq(path) .. " 2>/dev/null"):match("^(%x+)") or ""):lower() end

-- ---------------------------------------------------------------------------
-- instalacao existente
local function score_dir(d)
  local s = 0
  if isfile(d .. "/control.txt") then s = s + 2 end
  if isfile(d .. "/pugwash") then s = s + 2 end
  if isfile(d .. "/version") then s = s + 1 end
  return s
end

--- pasta do PortMaster: a com mais arquivos do PortMaster; pasta vazia nao conta
local function find_pm()
  local seen, best, bs = {}, nil, -1
  local list = {}
  for _, d in ipairs(job.pm_dirs or {}) do list[#list + 1] = d end
  if job.tools then list[#list + 1] = job.tools .. "/PortMaster" end
  for _, d in ipairs(list) do
    if d and d ~= "" and d ~= "/PortMaster" and not seen[d] then
      seen[d] = true
      if isdir(d) then
        local nonempty = trim(capture("ls -A " .. shq(d) .. " 2>/dev/null | head -n 1")) ~= ""
        local s = score_dir(d)
        if nonempty and s > bs then best, bs = d, s end
      end
    end
  end
  return best
end

--- onde fica o PortMaster.sh (iniciador). No ArkOS/dArkOS ele sai da pasta PortMaster.
local function launcher_of(dir)
  local up = parent(dir) .. "/PortMaster.sh"
  if isfile(up) then return up, true end
  if isfile(dir .. "/PortMaster.sh") then return dir .. "/PortMaster.sh", false end
  -- nenhum: no ArkOS/dArkOS o oficial fica na pasta de Ferramentas
  if job.tools and parent(dir) == job.tools then return up, true end
  return dir .. "/PortMaster.sh", false
end

--- caminho de destino de um arquivo do pacote ("PortMaster/x")
local function target_of(dir, launcher, rel)
  if rel == "PortMaster/PortMaster.sh" then return launcher end
  return dir .. rel:sub(#"PortMaster" + 1)
end

--- conferencia sem internet
local function inspect(dir)
  local r = { dir = dir, missing = {}, noexec = {}, deps = {} }
  r.readable = sh("test -r " .. shq(dir) .. " -a -x " .. shq(dir))
  if not r.readable then return r end
  r.version = trim((read_all(dir .. "/version") or ""):match("^[^\n]*"))
  if r.version == "" then r.version = nil end
  r.launcher, r.relocated = launcher_of(dir)
  r.fs = fs_type(dir)
  r.posix = posix_fs(r.fs)
  for _, f in ipairs(P.essentials(job.arch, job.os_id)) do
    if not exists(dir .. "/" .. f) then r.missing[#r.missing + 1] = f end
  end
  if not (isfile(dir .. "/pylibs.zip") or isdir(dir .. "/pylibs")) then r.missing[#r.missing + 1] = "pylibs.zip / pylibs/" end
  if not isfile(r.launcher) then r.missing[#r.missing + 1] = r.launcher:match("[^/]+$") .. " (" .. parent(r.launcher) .. ")" end
  if r.posix then
    local exe = P.executables(job.arch)
    exe[#exe + 1] = "@launcher"
    for _, f in ipairs(exe) do
      local p = f == "@launcher" and r.launcher or (dir .. "/" .. f)
      if isfile(p) and not sh("test -x " .. shq(p)) then r.noexec[#r.noexec + 1] = f == "@launcher" and "PortMaster.sh" or f end
    end
  end
  for _, c in ipairs({ "python3", "bash", "unzip" }) do
    if not have(c) then r.deps[#r.deps + 1] = c end
  end
  r.libs = tonumber(trim(capture("ls -1 " .. shq(dir .. "/libs") .. " 2>/dev/null | grep -c '\\.squashfs$'"))) or 0
  return r
end

-- ---------------------------------------------------------------------------
-- descoberta (fontes oficiais)
local function discover(need_api)
  phase("discover", I18N.tr("Consultando as releases oficiais do PortMaster"))
  if not sh("mkdir -p " .. shq(WORK)) then return nil, "no_write", job.tmp_dir end
  local d = { src = SRC.vjson }
  local VJ = WORK .. "/version.json"
  local got, rc = fetch_small(SRC.vjson, VJ, 30)
  if got then
    local v = P.parse_vjson(read_all(VJ), json, SRC.base)
    if v then d.channels = v end
  end
  if check_cancel() then return nil, "cancel" end
  -- API: canal pelo nome da release, pre-release e sha256 (opcional: limite de consultas)
  local API = WORK .. "/releases.json"
  if need_api ~= false and fetch_small(SRC.api, API, 25) then
    d.api = P.parse_api(read_all(API), json, SRC.base)
  end
  if check_cancel() then return nil, "cancel" end
  if not d.channels and not d.api then
    return nil, (rc == 22) and "server_error" or "no_internet", tostring(rc)
  end
  local st = d.channels and d.channels.stable
  if st then
    st.src = "version.json"
    local r = d.api and P.api_find(d.api, st.version)
    if r and r.asset then
      st.size, st.sha256 = r.asset.size, r.asset.sha256
      st.api_channel, st.prerelease = r.channel, r.prerelease
    end
  elseif d.api then
    -- sem version.json: release estavel da API + PortMaster.zip.md5 da mesma release
    local r = P.api_stable(d.api)
    if r then
      st = { version = r.tag, url = r.asset.url, size = r.asset.size, sha256 = r.asset.sha256,
        channel = "stable", api_channel = r.channel, src = "api" }
      local MF = WORK .. "/asset.md5"
      if fetch_small(r.asset.url .. ".md5", MF, 20) then
        local m = (read_all(MF) or ""):match("(%x+)")
        if m and #m == 32 then st.md5 = m:lower() end
      end
    end
  end
  d.stable = st
  -- versoes mais novas fora do canal estavel (so informacao: nunca instaladas aqui)
  d.others = {}
  for _, ch in ipairs({ "beta", "alpha" }) do
    local e = d.channels and d.channels[ch]
    if e and st and (P.vcmp(e.version, st.version) or 0) > 0 then d.others[#d.others + 1] = { channel = ch, version = e.version } end
  end
  if not d.channels and d.api and st then
    for _, r in ipairs(d.api) do
      if r.channel ~= "stable" and (P.vcmp(r.tag, st.version) or 0) > 0 then
        d.others[#d.others + 1] = { channel = r.channel or (r.prerelease and "pre-release") or "?", version = r.tag }
      end
    end
  end
  log("estavel:", st and st.version or "?", "fonte:", st and st.src or "-", "sha256:", st and st.sha256 and "sim" or "nao")
  return d
end

--- referencia de uma versao especifica (reparo): URL oficial + md5 da release
local function reference_for(ver, d)
  local ref = { version = ver, url = P.asset_url(SRC.base, ver) }
  local r = d and d.api and P.api_find(d.api, ver)
  if r and r.asset then ref.size, ref.sha256 = r.asset.size, r.asset.sha256 end
  if d and d.channels then
    for _, e in pairs(d.channels) do if e.version == ver then ref.md5 = e.md5 end end
  end
  if not ref.md5 then
    local MF = WORK .. "/ref.md5"
    if fetch_small(ref.url .. ".md5", MF, 20) then
      local m = (read_all(MF) or ""):match("(%x+)")
      if m and #m == 32 then ref.md5 = m:lower() end
    end
  end
  return ref
end

local function remote_size(ref)
  if ref.size then return ref.size end
  local s = tonumber(capture("sh " .. shq(job.fetch_sh) .. " head " .. shq(ref.url) .. " 2>/dev/null"):match("(%d+)"))
  ref.size = s
  return s
end

-- ---------------------------------------------------------------------------
-- download + validacao do pacote
local function download(ref)
  phase("download", nil, ref.size)
  local r = fetch_big(ref.url, PART, ref.size)
  if r == "cancel" then return "cancel" end
  if r ~= 0 then
    if r == 22 then return "server_error", tostring(r) end
    if r == 23 then return "no_space_dl", tostring(r) end
    return "net_error", tostring(r)
  end
  os.rename(PART, ZIP)
  return true
end

local function list_zip(path)
  local names, total = {}, 0
  for line in capture("unzip -l " .. shq(path) .. " 2>/dev/null"):gmatch("[^\n]+") do
    local sz, name = line:match("^%s*(%d+)%s+%d[%d%-/]+%s+%d%d:%d%d%s+(.+)$")
    if sz and name then
      names[#names + 1] = name
      total = total + tonumber(sz)
    end
  end
  return names, total
end

--- nada e extraido sem passar aqui
local function validate_zip(ref)
  phase("verify", I18N.tr("Validando o pacote baixado"))
  local s = fsize(ZIP)
  if not s or s == 0 then return nil, "empty" end
  if ref.size and s ~= ref.size then return nil, "size_mismatch", string.format("%d|%d", s, ref.size) end
  local method = {}
  if ref.sha256 then
    if not have("sha256sum") then return nil, "missing_tool", "sha256sum" end
    local h = sha256(ZIP)
    if h ~= ref.sha256 then return nil, "checksum", "sha256" end
    method[#method + 1] = "sha256"
  end
  if ref.md5 then
    if md5(ZIP) ~= ref.md5 then return nil, "checksum", "md5" end
    method[#method + 1] = "md5"
  end
  if #method == 0 then return nil, "no_checksum" end
  if not sh("unzip -tqq " .. shq(ZIP) .. " >/dev/null 2>&1") then return nil, "bad_zip" end
  local names, total = list_zip(ZIP)
  if #names == 0 then return nil, "bad_zip" end
  local set = {}
  for _, n in ipairs(names) do
    if n:sub(1, 1) == "/" or n:find("%.%.") or n:sub(1, #"PortMaster/") ~= "PortMaster/" then
      return nil, "unsafe_zip", n
    end
    set[n] = true
  end
  local okp, why, what = P.package_supports(set, job.arch, job.os_id)
  if not okp then return nil, "incompatible", (why or "") .. "|" .. (what or "") end
  return { names = names, total = total, set = set, method = table.concat(method, " + ") }
end

local function extract(into, ver)
  phase("extract", I18N.tr("Extraindo para uma pasta temporária"))
  staging = into
  sh("rm -rf " .. shq(staging))
  if not sh("mkdir -p " .. shq(staging)) then return nil, "no_write", parent(staging) end
  if not sh("unzip -qq -o " .. shq(ZIP) .. " -d " .. shq(staging) .. " >" .. shq(WORK .. "/unzip.log") .. " 2>&1") then
    return nil, "extract_failed", trim((read_all(WORK .. "/unzip.log") or ""):sub(1, 200))
  end
  if trim(capture("find " .. shq(staging) .. " -type l 2>/dev/null | head -n 1")) ~= "" then
    return nil, "unsafe_zip", "symlink"
  end
  local v = trim((read_all(staging .. "/PortMaster/version") or ""):match("^[^\n]*"))
  if v ~= ver then return nil, "version_mismatch", v .. "|" .. ver end
  -- md5 de referencia de cada arquivo do pacote
  local ref = {}
  local n = 0
  for line in capture("cd " .. shq(staging) .. " && find PortMaster -type f -exec md5sum {} + 2>/dev/null"):gmatch("[^\n]+") do
    local h, f = line:match("^(%x+)%s+(.+)$")
    if h then ref[f] = h:lower(); n = n + 1 end
  end
  if n == 0 then return nil, "extract_failed", "0" end
  return ref, n
end

-- ---------------------------------------------------------------------------
-- conferencia por md5 (lista "md5  caminho")
local function md5_check(map) -- map: destino -> md5
  local missing, changed = {}, {}
  local tmp = WORK .. "/check.md5"
  local lines = {}
  for p, h in pairs(map) do lines[#lines + 1] = h .. "  " .. p end
  write_all(tmp, table.concat(lines, "\n") .. "\n")
  for line in capture("md5sum -c " .. shq(tmp) .. " 2>/dev/null"):gmatch("[^\n]+") do
    local f, st = line:match("^(.+): (%S+)")
    if f and st ~= "OK" then
      if exists(f) then changed[#changed + 1] = f else missing[#missing + 1] = f end
    end
  end
  -- md5sum -c nao lista arquivos ausentes em algumas versoes: confere de novo
  local seen = {}
  for _, f in ipairs(missing) do seen[f] = true end
  for p in pairs(map) do if not seen[p] and not exists(p) then missing[#missing + 1] = p end end
  table.sort(missing); table.sort(changed)
  return missing, changed
end

-- ---------------------------------------------------------------------------
-- preservacao: impressao digital do que NUNCA pode mudar
local function snapshot(dir)
  local s = {}
  local ports = job.ports_dir
  -- a pasta do PortMaster (se estiver em ports) e a do proprio hub (temporarios) ficam de fora
  local skip = (parent(dir) == ports) and dir:match("[^/]+$") or ""
  local app = (job.app_dir and parent(job.app_dir) == ports) and job.app_dir:match("[^/]+$") or ""
  s.ports = trim(capture("cd " .. shq(ports) .. " 2>/dev/null && for e in * .[!.]*; do [ -e \"$e\" ] || continue; "
    .. "[ \"$e\" = " .. shq(skip) .. " ] && continue; [ \"$e\" = " .. shq(app) .. " ] && continue; "
    .. "ls -lAR -- \"$e\"; done 2>/dev/null | md5sum"))
  -- runtimes: nome, tamanho e data de cada libs/*.squashfs (e .md5)
  -- (sem as permissoes: o ajuste oficial chmod -R 777 nao muda o conteudo)
  s.libs = trim(capture("cd " .. shq(dir .. "/libs") .. " 2>/dev/null && for f in *.squashfs *.squashfs.md5; do [ -e \"$f\" ] && stat -c '%n %s %Y' -- \"$f\"; done 2>/dev/null | md5sum"))
  s.config = trim(capture("cd " .. shq(dir) .. " 2>/dev/null && find config themes autoinstall -type f -exec md5sum {} + 2>/dev/null | sort | md5sum"))
  s.ports_count = tonumber(trim(capture("ls -1A " .. shq(ports) .. " 2>/dev/null | wc -l"))) or 0
  return s
end

local function snapshot_diff(a, b)
  local d = {}
  for _, k in ipairs({ "ports", "libs", "config" }) do if a[k] ~= b[k] then d[#d + 1] = k end end
  return d
end

-- ---------------------------------------------------------------------------
-- diario + backup + aplicacao (scripts sh simples, sem nada baixado)
local function J(dir) return parent(dir) .. "/.porthub_pm" end

local function jwrite(jd, name, s) return write_all(jd .. "/" .. name, s) end

--- plano: { {kind="B"|"N", src, dst, bk} }
local function write_plan(jd, plan)
  local t = {}
  for _, e in ipairs(plan) do t[#t + 1] = e.kind .. "\t" .. e.src .. "\t" .. e.dst .. "\t" .. (e.bk or "") end
  return jwrite(jd, "plan.tsv", table.concat(t, "\n") .. "\n")
end

local SCRIPT_BACKUP = [[
set -u
J="$1"; n=0
while IFS='	' read -r k s d b; do
  [ "$k" = "B" ] || continue
  mkdir -p "$(dirname "$b")" || exit 3
  cp -p "$d" "$b" || exit 4
  n=$((n+1)); echo "$n" > "$J/progress"
done < "$J/plan.tsv"
sync
exit 0
]]

local SCRIPT_APPLY = [[
set -u
J="$1"; n=0
while IFS='	' read -r k s d b; do
  [ -n "$k" ] || continue
  mkdir -p "$(dirname "$d")" || exit 3
  rm -f "$d.phnew"
  cp -p "$s" "$d.phnew" || { rm -f "$d.phnew"; exit 4; }
  mv -f "$d.phnew" "$d" || { rm -f "$d.phnew"; exit 5; }
  n=$((n+1)); echo "$n" > "$J/progress"
done < "$J/plan.tsv"
sync
exit 0
]]

local SCRIPT_ROLLBACK = P.ROLLBACK_SH

local function run_script(jd, body, name, total, ph)
  write_all(jd .. "/" .. name .. ".sh", body)
  os.remove(jd .. "/progress"); os.remove(jd .. "/rc")
  sh("( sh " .. shq(jd .. "/" .. name .. ".sh") .. " " .. shq(jd) .. " >" .. shq(jd .. "/" .. name .. ".log")
    .. " 2>&1; echo $? > " .. shq(jd .. "/rc") .. " ) &")
  local last = -1
  while true do
    love.timer.sleep(0.15)
    local rc = read_all(jd .. "/rc")
    if rc and rc:match("%d+") then
      send({ t = "progress", phase = ph, done = total, total = total })
      return tonumber(rc:match("%d+"))
    end
    local n = tonumber((read_all(jd .. "/progress") or ""):match("%d+") or "")
    if n and n ~= last then send({ t = "progress", phase = ph, done = n, total = total }); last = n end
    check_cancel()
  end
end

--- desfaz e CONFERE: so diz "restaurado" se o md5 de cada arquivo voltou
local function rollback(jd)
  local rc = run_script(jd, SCRIPT_ROLLBACK, "rollback", 0, "apply")
  local okr = rc == 0
  local expect = {}
  for line in (read_all(jd .. "/backup.md5") or ""):gmatch("[^\n]+") do
    local h, f = line:match("^(%x+)%s+(.+)$")
    if h then expect[f] = h end
  end
  local miss, chg = md5_check(expect)
  if #miss > 0 or #chg > 0 then okr = false end
  for line in (read_all(jd .. "/plan.tsv") or ""):gmatch("[^\n]+") do
    local k, _, d = line:match("^(%S)\t([^\t]*)\t([^\t]*)")
    if k == "N" and exists(d) then okr = false end
  end
  jwrite(jd, "state", okr and "rolledback\n" or "rollback_failed\n")
  log("restauracao do backup:", okr and "confirmada" or "NAO confirmada")
  return okr
end

--- aplica um plano com backup; devolve true ou (false, codigo, recuperado?)
local function apply_plan(dir, plan, op, from, to)
  local jd = J(dir)
  local st = trim(read_all(jd .. "/state") or "")
  if st == "applying" or st == "backup" or st == "rollback_failed" then return false, "pending_recovery" end
  sh("rm -rf " .. shq(jd))
  if not sh("mkdir -p " .. shq(jd .. "/backup")) then return false, "no_write", parent(dir) end
  local nb = 0
  for _, e in ipairs(plan) do
    if e.kind == "B" then
      nb = nb + 1
      e.bk = jd .. "/backup/" .. tostring(nb)
    end
  end
  write_plan(jd, plan)
  jwrite(jd, "info", string.format("op=%s\nfrom=%s\nto=%s\ndir=%s\ntime=%d\n", op, from or "", to or "", dir, os.time()))
  -- 1) backup
  jwrite(jd, "state", "backup\n")
  phase("backup", I18N.tr("Fazendo backup dos arquivos que vão mudar"), nb)
  if run_script(jd, SCRIPT_BACKUP, "backup", nb, "backup") ~= 0 then
    sh("rm -rf " .. shq(jd))
    return false, "backup_failed"
  end
  -- md5 do backup = md5 dos originais (a restauracao e conferida contra isto)
  local lines = {}
  for _, e in ipairs(plan) do
    if e.kind == "B" then
      local h = md5(e.bk)
      if h == "" or h ~= md5(e.dst) then sh("rm -rf " .. shq(jd)); return false, "backup_failed" end
      lines[#lines + 1] = h .. "  " .. e.dst
    end
  end
  jwrite(jd, "backup.md5", table.concat(lines, "\n") .. "\n")
  -- 2) aplicacao (a partir daqui nao da para cancelar)
  no_cancel = true
  jwrite(jd, "state", "applying\n")
  phase("apply", I18N.tr("Aplicando os arquivos oficiais"), #plan)
  if job.test_fail == "apply" then
    -- teste do desenvolvedor: simula falha no meio da aplicacao
    local half = {}
    for i = 1, math.floor(#plan / 2) do half[#half + 1] = plan[i] end
    write_plan(jd, half)
    run_script(jd, SCRIPT_APPLY, "apply", #half, "apply")
    write_plan(jd, plan)
    return false, "apply_failed", rollback(jd)
  end
  if job.test_fail == "interrupt" then
    -- teste: o console "desliga" no meio (o diario fica em applying)
    local half = {}
    for i = 1, math.floor(#plan / 2) do half[#half + 1] = plan[i] end
    write_plan(jd, half)
    run_script(jd, SCRIPT_APPLY, "apply", #half, "apply")
    write_plan(jd, plan)
    return false, "interrupted_test"
  end
  local rc = run_script(jd, SCRIPT_APPLY, "apply", #plan, "apply")
  if rc ~= 0 then return false, "apply_failed", rollback(jd) end
  jwrite(jd, "state", "validating\n")
  return true, jd
end

--- permissoes como o PortMaster oficial faz (chmod -R 777 so em ext/overlay)
local function fix_perms(dir, launcher)
  local t = fs_type(dir)
  if not posix_fs(t) then return "skip" end
  local okp = sh("chmod -R 777 " .. shq(dir) .. " 2>/dev/null")
  if launcher and isfile(launcher) then okp = sh("chmod 777 " .. shq(launcher) .. " 2>/dev/null") and okp end
  return okp and "ok" or "failed"
end

--- modo do gamecontrollerdb escolhido no PortMaster (padrao/xbox) e mantido
local function restore_gcd(dir)
  local cfg = read_all(dir .. "/config/config.json") or ""
  local mode = cfg:match('"gcd%-mode"%s*:%s*"(%w+)"')
  local src = mode == "xbox" and "/.Backup/donottouch_x.txt" or (mode == "standard" and "/.Backup/donottouch.txt") or nil
  if src and isfile(dir .. src) then
    sh("cp -p " .. shq(dir .. src) .. " " .. shq(dir .. "/gamecontrollerdb.txt.phnew") .. " && mv -f "
      .. shq(dir .. "/gamecontrollerdb.txt.phnew") .. " " .. shq(dir .. "/gamecontrollerdb.txt"))
    return mode
  end
end

--- referencia gravada pelo hub (para conferir sem internet depois)
local function save_manifest(ver, dir, launcher, ref)
  local t = { "version=" .. ver, "dir=" .. dir, "launcher=" .. launcher }
  local keys = {}
  for f in pairs(ref) do keys[#keys + 1] = f end
  table.sort(keys)
  for _, f in ipairs(keys) do t[#t + 1] = ref[f] .. "  " .. f end
  write_all(job.manifest_file, table.concat(t, "\n") .. "\n")
end

local function load_manifest(ver)
  local s = read_all(job.manifest_file or "")
  if not s then return nil end
  if s:match("^version=([^\n]*)") ~= ver then return nil end
  local ref = {}
  for h, f in s:gmatch("\n(%x+)  ([^\n]+)") do ref[f] = h end
  return next(ref) and ref or nil
end

local function space_ok(path, need)
  local free = free_bytes(path)
  if free and free < need then return false, string.format("%d|%d", need, free) end
  return true
end

local function tools_needed()
  for _, c in ipairs({ "unzip", "md5sum" }) do if not have(c) then return c end end
  if not (have("curl") or have("wget")) then return "curl/wget" end
end

-- ---------------------------------------------------------------------------
-- operacoes
local function op_check()
  local d, code, det = discover(true)
  if not d then if code == "cancel" then return cancel_done() end return fail(code, det) end
  cleanup()
  send({ t = "done", op = "check", stable = d.stable, others = d.others, src = d.src })
end

local function download_validate(ref)
  if ref.size then
    local okk, det = space_ok(job.tmp_dir, ref.size + job.margin)
    if not okk then return nil, "no_space", det end
  end
  local r, det = download(ref)
  if r == "cancel" then return nil, "cancel" end
  if r ~= true then return nil, r, det end
  if check_cancel() then return nil, "cancel" end
  local v, code, d2 = validate_zip(ref)
  if not v then return nil, code, d2 end
  return v
end

local function op_install()
  phase("check", I18N.tr("Verificando o console"))
  local miss = tools_needed()
  if miss then return fail("missing_tool", miss) end
  if not job.tools then return fail("unsupported_os") end
  if job.arch ~= "aarch64" and job.arch ~= "armhf" then return fail("arch", tostring(job.arch)) end
  local found = find_pm()
  if found then return fail("already_installed", found) end
  if not sh("test -w " .. shq(job.tools)) then return fail("no_write", job.tools) end
  local d, code, det = discover(true)
  if not d then if code == "cancel" then return cancel_done() end return fail(code, det) end
  local st = d.stable
  if not st then return fail("no_stable") end
  if not st.md5 and not st.sha256 then return fail("no_checksum") end
  remote_size(st)
  local dest = job.tools .. "/PortMaster"
  if not ask({ kind = "install", version = st.version, size = st.size, dest = dest,
      launcher = job.tools .. "/PortMaster.sh", sha256 = st.sha256 ~= nil, md5 = st.md5 ~= nil,
      others = d.others, free = free_bytes(job.tools) }) then
    return cancel_done()
  end
  local v, c2, d2 = download_validate(st)
  if not v then if c2 == "cancel" then return cancel_done() end return fail(c2, d2) end
  local okk, sp = space_ok(job.tools, v.total + job.margin)
  if not okk then return fail("no_space", sp) end
  local ref, n, edet = extract(job.tools .. "/.porthub_pm_staging", st.version)
  if not ref then return fail(n, edet) end
  if check_cancel() then return cancel_done() end
  -- aplicacao: move a pasta pronta (rename na mesma particao) e o iniciador
  no_cancel = true
  phase("apply", I18N.tr("Instalando o PortMaster"), 2)
  if exists(dest) then return fail("already_installed", dest) end
  local jd = job.tools .. "/.porthub_pm"
  sh("rm -rf " .. shq(jd)); sh("mkdir -p " .. shq(jd .. "/backup"))
  jwrite(jd, "info", string.format("op=install\nto=%s\ndir=%s\ntime=%d\n", st.version, dest, os.time()))
  jwrite(jd, "state", "installing\n")
  local launcher = job.tools .. "/PortMaster.sh"
  local had_launcher = isfile(launcher)
  if had_launcher then
    -- iniciador solto de outra instalacao: guardado antes de ser substituido
    if not sh("cp -p " .. shq(launcher) .. " " .. shq(jd .. "/backup/PortMaster.sh")) then return fail("backup_failed") end
  end
  if not sh("mv " .. shq(staging .. "/PortMaster") .. " " .. shq(dest)) then return fail("apply_failed", "mv") end
  send({ t = "progress", phase = "apply", done = 1, total = 2 })
  local okl = sh("mv -f " .. shq(dest .. "/PortMaster.sh") .. " " .. shq(launcher))
  send({ t = "progress", phase = "apply", done = 2, total = 2 })
  local perm = fix_perms(dest, launcher)
  -- validacao: cada arquivo instalado confere com o pacote
  phase("validate", I18N.tr("Conferindo a instalação"))
  local map = {}
  for f, h in pairs(ref) do map[target_of(dest, launcher, f)] = h end
  local m1, c1 = md5_check(map)
  local ins = inspect(dest)
  if not okl or #m1 > 0 or #c1 > 0 or #ins.missing > 0 or perm == "failed" then
    -- desfaz SO o que este hub acabou de criar (pasta nova, ainda sem dados do usuario)
    local extra = trim(capture("cd " .. shq(dest) .. " && find . -type f | wc -l"))
    local recovered = false
    if tonumber(extra) and tonumber(extra) <= n then
      recovered = sh("rm -rf " .. shq(dest)) and not exists(dest)
      if had_launcher then sh("cp -p " .. shq(jd .. "/backup/PortMaster.sh") .. " " .. shq(launcher))
      elseif okl then os.remove(launcher) end
    end
    jwrite(jd, "state", recovered and "rolledback\n" or "rollback_failed\n")
    return fail("validate_failed", tostring(#m1 + #c1 + #ins.missing), { recovered = recovered, missing = m1, changed = c1 })
  end
  save_manifest(st.version, dest, launcher, ref)
  sh("rm -rf " .. shq(jd))
  if had_launcher then
    -- o iniciador antigo fica guardado (nao apagamos nada do usuario)
    sh("mkdir -p " .. shq(jd .. "/backup") .. " && echo done > " .. shq(jd .. "/state"))
  end
  cleanup()
  sh("sync")
  log("instalado", st.version, "em", dest)
  send({ t = "done", op = "install", version = st.version, dir = dest, launcher = launcher, files = n,
    perms = perm, method = v.method, src = st.src, url = st.url, others = d.others })
end

local function op_update()
  phase("check", I18N.tr("Verificando a instalação atual"))
  local miss = tools_needed()
  if miss then return fail("missing_tool", miss) end
  local dir = find_pm()
  if not dir then return fail("not_installed") end
  local ins = inspect(dir)
  if not ins.readable then return fail("no_read", dir) end
  if not sh("test -w " .. shq(dir) .. " -a -w " .. shq(parent(dir))) then return fail("no_write", dir) end
  local d, code, det = discover(true)
  if not d then if code == "cancel" then return cancel_done() end return fail(code, det) end
  local st = d.stable
  if not st then return fail("no_stable") end
  if not st.md5 and not st.sha256 then return fail("no_checksum") end
  local cmp = ins.version and P.vcmp(ins.version, st.version)
  if cmp and cmp >= 0 then
    cleanup()
    return send({ t = "done", op = "update", uptodate = true, newer_installed = cmp > 0,
      version = ins.version, stable = st.version, others = d.others })
  end
  remote_size(st)
  if not ask({ kind = "update", from = ins.version, to = st.version, size = st.size, dest = dir,
      sha256 = st.sha256 ~= nil, md5 = st.md5 ~= nil, libs = ins.libs, others = d.others }) then
    return cancel_done()
  end
  local v, c2, d2 = download_validate(st)
  if not v then if c2 == "cancel" then return cancel_done() end return fail(c2, d2) end
  local okk, sp = space_ok(parent(dir), v.total * 2 + job.margin)
  if not okk then return fail("no_space", sp) end
  local ref, n, edet = extract(parent(dir) .. "/.porthub_pm_staging", st.version)
  if not ref then return fail(n, edet) end
  if check_cancel() then return cancel_done() end
  -- plano: so os arquivos do pacote (config/, themes/, libs/*.squashfs nao estao nele)
  local launcher = ins.launcher
  local plan, nb, nn = {}, 0, 0
  local keys = {}
  for f in pairs(ref) do keys[#keys + 1] = f end
  table.sort(keys)
  for _, f in ipairs(keys) do
    local dst = target_of(dir, launcher, f)
    local kind = exists(dst) and "B" or "N"
    if kind == "B" then nb = nb + 1 else nn = nn + 1 end
    plan[#plan + 1] = { kind = kind, src = staging .. "/" .. f, dst = dst }
  end
  local before = snapshot(dir)
  local okp, pcode, recovered = apply_plan(dir, plan, "update", ins.version, st.version)
  if not okp then
    if pcode == "interrupted_test" then return send({ t = "error", code = "interrupted_test" }) end
    return fail(pcode, "", { recovered = recovered })
  end
  local jd = pcode
  local perm = fix_perms(dir, launcher)
  local gcd = restore_gcd(dir)
  phase("validate", I18N.tr("Conferindo a atualização"))
  local map = {}
  for f, h in pairs(ref) do
    if not (f == "PortMaster/gamecontrollerdb.txt" and gcd) then map[target_of(dir, launcher, f)] = h end
  end
  local m1, c1 = md5_check(map)
  local after = snapshot(dir)
  local diff = snapshot_diff(before, after)
  if #m1 > 0 or #c1 > 0 or #diff > 0 or perm == "failed" then
    log("validacao falhou:", #m1, #c1, table.concat(diff, ","))
    local rec = rollback(jd)
    if #m1 + #c1 == 0 and #diff > 0 then
      return fail("preserve_failed", table.concat(diff, ","), { recovered = rec })
    end
    return fail("validate_failed", tostring(#m1 + #c1), { recovered = rec, preserved_changed = diff })
  end
  jwrite(jd, "state", "done\n")
  save_manifest(st.version, dir, launcher, ref)
  cleanup()
  sh("sync")
  log("atualizado", ins.version or "?", "->", st.version)
  send({ t = "done", op = "update", from = ins.version, version = st.version, dir = dir, replaced = nb, added = nn,
    backup = jd .. "/backup", perms = perm, gcd = gcd, preserved = true, method = v.method, src = st.src, url = st.url,
    others = d.others, ports_count = after.ports_count })
end

--- compara a instalacao com a referencia (pacote oficial da versao instalada)
local function compare(dir, launcher, ref)
  local map = {}
  for f, h in pairs(ref) do
    if not P.SELF_MANAGED[f] then map[target_of(dir, launcher, f)] = h end
  end
  local m, c = md5_check(map)
  -- pylibs.zip: o PortMaster o extrai e apaga; so falta se pylibs/ tambem nao existir
  if ref["PortMaster/pylibs.zip"] and not isfile(dir .. "/pylibs.zip") and not isdir(dir .. "/pylibs") then
    m[#m + 1] = dir .. "/pylibs.zip"
  end
  if ref["PortMaster/gamecontrollerdb.txt"] and not isfile(dir .. "/gamecontrollerdb.txt") then
    m[#m + 1] = dir .. "/gamecontrollerdb.txt"
  end
  return m, c
end

local function classify(ins, res)
  local cls = {}
  if not ins.readable then return { "unverifiable" } end
  if not ins.version or #ins.missing >= 4 then cls[#cls + 1] = "incomplete" end
  if #ins.missing > 0 or (res.missing and #res.missing > 0) then cls[#cls + 1] = "missing" end
  if #ins.noexec > 0 then cls[#cls + 1] = "perms" end
  if #ins.deps > 0 then cls[#cls + 1] = "dependency" end
  if res.update == "available" then cls[#cls + 1] = "update" end
  if #cls == 0 then cls[1] = "ok" end
  return cls
end

local function op_verify()
  phase("check", I18N.tr("Conferindo a instalação"))
  local dir = find_pm()
  if not dir then
    cleanup()
    return send({ t = "done", op = "verify", installed = false })
  end
  local ins = inspect(dir)
  local res = { method = "essentials" }
  if ins.readable and ins.version then
    local ref = load_manifest(ins.version)
    if ref then
      phase("validate", I18N.tr("Comparando cada arquivo com o pacote oficial (md5)"))
      sh("mkdir -p " .. shq(WORK))
      res.missing, res.changed = compare(dir, ins.launcher, ref)
      res.method = "manifest"
      res.files = 0
      for _ in pairs(ref) do res.files = res.files + 1 end
    elseif job.deep then
      -- verificacao completa: baixa o pacote oficial DA VERSAO INSTALADA
      local d = discover(false)
      local r = reference_for(ins.version, d)
      if not r.md5 and not r.sha256 then return fail("no_reference", ins.version) end
      remote_size(r)
      local v, c2, d2 = download_validate(r)
      if not v then if c2 == "cancel" then return cancel_done() end return fail(c2, d2) end
      local ref2, n, edet = extract(job.tmp_dir .. "/pm_job/ref", ins.version)
      if not ref2 then return fail(n, edet) end
      phase("validate", I18N.tr("Comparando cada arquivo com o pacote oficial (md5)"))
      res.missing, res.changed = compare(dir, ins.launcher, ref2)
      res.method, res.files = "download", n
      save_manifest(ins.version, dir, ins.launcher, ref2)
    end
  end
  -- atualizacao (consulta pequena; sem internet fica "nao verificado")
  if not job.offline then
    local d = discover(false)
    if d and d.stable and ins.version then
      local c = P.vcmp(ins.version, d.stable.version)
      res.update = c and (c < 0 and "available" or "current") or nil
      res.stable = d.stable.version
    end
  end
  cleanup()
  send({ t = "done", op = "verify", installed = true, dir = dir, version = ins.version, launcher = ins.launcher,
    inspect = ins, result = res, classes = classify(ins, res) })
end

local function op_repair()
  phase("check", I18N.tr("Conferindo a instalação"))
  local miss = tools_needed()
  if miss then return fail("missing_tool", miss) end
  local dir = find_pm()
  if not dir then return fail("not_installed") end
  local ins = inspect(dir)
  if not ins.readable then return fail("no_read", dir) end
  if not ins.version or not P.valid_version(ins.version) then return fail("version_unknown") end
  if not sh("test -w " .. shq(dir) .. " -a -w " .. shq(parent(dir))) then return fail("no_write", dir) end
  local d = discover(true)
  if check_cancel() then return cancel_done() end
  local r = reference_for(ins.version, d)
  if not r.md5 and not r.sha256 then return fail("no_reference", ins.version) end
  remote_size(r)
  if not ask({ kind = "repair_download", version = ins.version, size = r.size, dest = dir,
      sha256 = r.sha256 ~= nil, md5 = r.md5 ~= nil }) then
    return cancel_done()
  end
  local v, c2, d2 = download_validate(r)
  if not v then if c2 == "cancel" then return cancel_done() end return fail(c2, d2) end
  local ref, n, edet = extract(parent(dir) .. "/.porthub_pm_staging", ins.version)
  if not ref then return fail(n, edet) end
  phase("validate", I18N.tr("Comparando cada arquivo com o pacote oficial (md5)"))
  local m, c = compare(dir, ins.launcher, ref)
  -- mapa destino -> arquivo do pacote
  local back = {}
  for f in pairs(ref) do back[target_of(dir, ins.launcher, f)] = f end
  local plan = {}
  for _, p in ipairs(m) do
    local f = back[p] or (p == dir .. "/pylibs.zip" and "PortMaster/pylibs.zip") or (p == dir .. "/gamecontrollerdb.txt" and "PortMaster/gamecontrollerdb.txt")
    if f then plan[#plan + 1] = { kind = "N", src = staging .. "/" .. f, dst = p } end
  end
  for _, p in ipairs(c) do
    if back[p] then plan[#plan + 1] = { kind = "B", src = staging .. "/" .. back[p], dst = p } end
  end
  local need_perm = #ins.noexec > 0
  if #plan == 0 and not need_perm then
    save_manifest(ins.version, dir, ins.launcher, ref)
    cleanup()
    return send({ t = "done", op = "repair", nothing = true, version = ins.version, files = n })
  end
  local names = {}
  for _, e in ipairs(plan) do names[#names + 1] = (e.kind == "N" and "+ " or "~ ") .. e.dst:gsub("^" .. parent(dir):gsub("%p", "%%%0") .. "/", "") end
  if not ask({ kind = "repair", version = ins.version, missing = #m, changed = #c, perms = need_perm, items = names }) then
    return cancel_done()
  end
  local jd
  if #plan > 0 then
    local okp, pcode, recovered = apply_plan(dir, plan, "repair", ins.version, ins.version)
    if not okp then
      if pcode == "interrupted_test" then return send({ t = "error", code = "interrupted_test" }) end
      return fail(pcode, "", { recovered = recovered })
    end
    jd = pcode
  end
  local perm = fix_perms(dir, ins.launcher)
  phase("validate", I18N.tr("Conferindo o reparo"))
  local m2, c2b = compare(dir, ins.launcher, ref)
  -- arquivos que o usuario escolheu manter alterados nao existem aqui: tudo que estava no plano precisa conferir
  local bad = #m2 + #c2b
  if bad > 0 or perm == "failed" then
    local rec = jd and rollback(jd) or nil
    return fail("validate_failed", tostring(bad), { recovered = rec })
  end
  if jd then jwrite(jd, "state", "done\n") end
  save_manifest(ins.version, dir, ins.launcher, ref)
  cleanup()
  sh("sync")
  send({ t = "done", op = "repair", version = ins.version, restored = #m, replaced = #c, perms = perm,
    backup = jd and (jd .. "/backup") or nil, method = v.method, url = r.url, items = names })
end

local OPS = { check = op_check, install = op_install, update = op_update, verify = op_verify, repair = op_repair }
local okrun, err = pcall(OPS[job.op] or function() fail("internal", "op") end)
if not okrun then
  log("erro interno:", err)
  cleanup()
  send({ t = "error", code = "internal", detail = tostring(err) })
end
