-- =============================================================================
--  R36S PORT HUB - thread de atualizacao dos runtimes do PortMaster
--
--  Estrutura real do pacote (verificada): runtimes.all.aarch64.zip contem apenas
--  arquivos *.squashfs na raiz (sem pastas). O PortMaster carrega esses arquivos
--  de <PortMaster>/libs/. O ports.json da mesma release traz md5 e tamanho de
--  cada runtime, usados para validar tudo ANTES de mexer na pasta libs.
--
--  Etapas: verificacao (internet, PortMaster, runtimes atuais) -> confirmacao
--  -> download -> validacao do ZIP -> extracao para pasta temporaria + md5
--  -> backup + troca -> limpeza. Em caso de falha na troca, o backup e restaurado.
--  Arquivos que nao sao runtimes nunca sao tocados.
-- =============================================================================
require("love.timer")

local job = ...
local I18N = require("lib.i18n")
I18N.set(job.lang or "pt-BR")
local L = function(t) return I18N.tr(t) end
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
  print("[runtimes] " .. table.concat(t, " "))
  io.stdout:flush()
end
local function send(m) OUT:push(m) end
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
local function free_bytes(path)
  local out = capture("df -Pk " .. shq(path) .. " 2>/dev/null | tail -n 1")
  local avail = out:match("^%S+%s+%d+%s+%d+%s+(%d+)")
  return avail and tonumber(avail) * 1024 or nil
end
local function device_of(path)
  return capture("df -P " .. shq(path) .. " 2>/dev/null | tail -n 1"):match("^(%S+)")
end

local WORK = job.tmp_dir .. "/runtimes_job"
local ZIP = WORK .. "/" .. job.zip_name
local PART = ZIP .. ".part"
local PIDF, RCF = WORK .. "/dl.pid", WORK .. "/dl.rc"

local cancelled = false
local function check_cancel()
  local m = IN:pop()
  while m do
    if m.t == "cancel" then cancelled = true end
    m = IN:pop()
  end
  return cancelled
end

local staging -- pasta temporaria dentro de libs
local function cleanup()
  sh("rm -rf " .. shq(WORK) .. " 2>/dev/null")
  if staging then sh("rm -rf " .. shq(staging) .. " 2>/dev/null") end
end
local function fail(code, detail)
  log("ERRO", code, detail or "")
  cleanup()
  send({ t = "error", code = code, detail = detail or "" })
end
local function cancel_done()
  log("cancelado pelo usuario")
  cleanup()
  send({ t = "cancelled" })
end

--- download bloqueante pequeno (indice/API)
local function fetch_small(url, out, maxt)
  os.remove(out)
  local rcf, pidf = out .. ".rc", out .. ".pid"
  sh("sh " .. shq(job.fetch_sh) .. " get " .. shq(url) .. " " .. shq(out) .. " " .. shq(pidf) .. " "
    .. shq(rcf) .. " " .. tostring(maxt or 60) .. " >/dev/null 2>&1")
  local rc = tonumber((read_all(rcf) or ""):match("%d+") or "1")
  os.remove(rcf); os.remove(pidf)
  return rc == 0 and (fsize(out) or 0) > 0, rc
end

--- download grande, em segundo plano, com progresso e cancelamento
local function fetch_big(url, out, expected, phase)
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
      send({ t = "progress", phase = phase, done = done, total = expected })
      last = done
    end
  end
end

-- md5 de um arquivo (md5sum do coreutils/busybox)
local function md5(path)
  return (capture("md5sum " .. shq(path) .. " 2>/dev/null"):match("^(%x+)") or ""):lower()
end

-- ---------------------------------------------------------------------------
local function run()
  send({ t = "phase", phase = "check", label = L("Localizando o PortMaster") })
  cleanup()
  if not sh("mkdir -p " .. shq(WORK)) then return fail("no_write", job.tmp_dir) end
  for _, c in ipairs({ "unzip", "md5sum" }) do
    if not sh("command -v " .. c .. " >/dev/null 2>&1") then return fail("missing_tool", c) end
  end

  -- 1) PortMaster: prefere a pasta com control.txt E libs/
  local pm, best = nil, 0
  for _, d in ipairs(job.pm_dirs) do
    if d and d ~= "" and d ~= "/PortMaster" then
      local score = 0
      if sh("test -f " .. shq(d .. "/control.txt")) then score = score + 2 end
      if sh("test -d " .. shq(d .. "/libs")) then score = score + 1 end
      if score > best then pm, best = d, score end
    end
  end
  if not pm then return fail("no_pm") end
  local LIBS = pm .. "/libs"
  if not sh("mkdir -p " .. shq(LIBS)) or not sh("test -w " .. shq(LIBS)) then
    return fail("no_write", LIBS)
  end
  log("PortMaster:", pm)
  send({ t = "info", pm = pm, libs = LIBS })
  if check_cancel() then return cancel_done() end

  -- 2) URL (fixa ou mais recente) + indice com md5/tamanho
  local zip_url, index_url = job.zip_url, job.index_url
  if job.auto_latest and job.api_url ~= "" then
    send({ t = "phase", phase = "check", label = L("Procurando a versão mais recente") })
    local api = WORK .. "/releases.json"
    if fetch_small(job.api_url, api, 30) then
      local text = read_all(api) or ""
      local pat = '"browser_download_url"%s*:%s*"(https://[^"]-/download/([^"/]+)/' .. job.zip_name:gsub("%.", "%%.") .. ')"'
      local u, tag = text:match(pat)
      if u then
        zip_url = u
        index_url = u:gsub("/[^/]+$", "/ports.json")
        log("versao mais recente:", tag)
      end
    end
  end

  send({ t = "phase", phase = "check", label = L("Verificando a conexão com a internet") })
  local INDEX = WORK .. "/ports.json"
  local got, rc = fetch_small(index_url, INDEX, 90)
  if not got then
    if rc == 22 then return fail("index_missing", index_url) end
    return fail("no_internet", tostring(rc))
  end
  local text = read_all(INDEX) or ""
  local utils = text:match('"utils"%s*:%s*(%b{})')
  if not utils then return fail("bad_index") end
  local index = {}
  for name, body in utils:gmatch('"([^"]+%.squashfs)"%s*:%s*(%b{})') do
    local arch = body:match('"runtime_arch"%s*:%s*"([^"]+)"')
    local m = body:match('"md5"%s*:%s*"(%x+)"')
    local sz = tonumber(body:match('"size"%s*:%s*(%d+)'))
    local title = body:match('"name"%s*:%s*"([^"]+)"')
    if m and sz and (arch == nil or arch == job.arch) then
      index[name] = { md5 = m:lower(), size = sz, title = title }
    end
  end
  text, utils = nil, nil
  local names = {}
  for n in pairs(index) do names[#names + 1] = n end
  table.sort(names)
  if #names == 0 then return fail("bad_index") end
  if check_cancel() then return cancel_done() end

  -- 3) compara com os runtimes instalados (tamanho, depois md5)
  local todo, uptodate, newc, updc = {}, {}, 0, 0
  for i, n in ipairs(names) do
    send({ t = "progress", phase = "check", done = i - 1, total = #names, label = L("Conferindo runtimes instalados") })
    local cur = LIBS .. "/" .. n
    local s = fsize(cur)
    local e = index[n]
    if not s then
      todo[#todo + 1] = { name = n, kind = "new" }
      newc = newc + 1
    elseif s ~= e.size or md5(cur) ~= e.md5 then
      todo[#todo + 1] = { name = n, kind = "update" }
      updc = updc + 1
    else
      uptodate[#uptodate + 1] = n
    end
    if check_cancel() then return cancel_done() end
  end
  send({ t = "progress", phase = "check", done = #names, total = #names })
  if #todo == 0 then
    cleanup()
    send({ t = "done", uptodate = true, total = #names, libs = LIBS })
    return
  end

  -- 4) espaco: ZIP na pasta temporaria + runtimes novos na pasta libs
  local zip_size = tonumber(capture("sh " .. shq(job.fetch_sh) .. " head " .. shq(zip_url) .. " 2>/dev/null"):match("(%d+)"))
  if not zip_size then return fail("no_internet", "sem tamanho do pacote") end
  local need_libs = 0
  for _, t in ipairs(todo) do need_libs = need_libs + index[t.name].size end
  local same_fs = device_of(job.tmp_dir) == device_of(LIBS)
  local free_tmp, free_libs = free_bytes(job.tmp_dir), free_bytes(LIBS)
  if same_fs then
    if free_tmp and free_tmp < zip_size + need_libs + job.margin then
      return fail("no_space", string.format("%d|%d", zip_size + need_libs + job.margin, free_tmp))
    end
  else
    if free_tmp and free_tmp < zip_size + job.margin then
      return fail("no_space", string.format("%d|%d", zip_size + job.margin, free_tmp))
    end
    if free_libs and free_libs < need_libs + job.margin then
      return fail("no_space", string.format("%d|%d", need_libs + job.margin, free_libs))
    end
  end

  -- 5) autorizacao do usuario (nada e substituido sem confirmacao)
  local list = {}
  for _, t in ipairs(todo) do list[#list + 1] = "• " .. t.name .. (t.kind == "new" and L("  (novo)") or L("  (atualização)")) end
  send({ t = "confirm", new = newc, update = updc, ok = #uptodate, download = zip_size,
    need = need_libs, libs = LIBS, items = list })
  local answer
  while answer == nil do
    local m = IN:demand(0.5)
    if m then
      if m.t == "answer" then answer = m.yes and true or false
      elseif m.t == "cancel" then answer = false end
    end
  end
  if not answer then return cancel_done() end

  -- 6) download com progresso real
  send({ t = "phase", phase = "download", total = zip_size })
  local r = fetch_big(zip_url, PART, zip_size, "download")
  if r == "cancel" then return cancel_done() end
  if r ~= 0 then
    if r == 23 then return fail("no_space", "") end
    return fail("net_error", tostring(r))
  end

  -- 7) integridade e estrutura do ZIP
  send({ t = "phase", phase = "validate", label = L("Verificando o pacote") })
  local got_size = fsize(PART) or 0
  if got_size ~= zip_size then return fail("size_mismatch", string.format("%d|%d", got_size, zip_size)) end
  local f = io.open(PART, "rb")
  local head = f and f:read(4) or ""
  if f then f:close() end
  if head:sub(1, 2) ~= "PK" then return fail("not_zip") end
  if not os.rename(PART, ZIP) then return fail("no_write", WORK) end

  local members = {}      -- nome do runtime -> caminho dentro do zip
  local ignored = 0
  local listing = capture("unzip -Z1 " .. shq(ZIP) .. " 2>/dev/null")
  local count = 0
  for line in listing:gmatch("[^\n]+") do
    count = count + 1
    if line:sub(1, 1) == "/" or line:find("%.%.") then return fail("unsafe_zip", line) end
    local base = line:match("([^/]+)$")
    if base and base:match("%.squashfs$") and not line:match("/$") then
      -- aceita na raiz ou dentro de uma pasta (ex.: libs/x.squashfs); destino e sempre libs/x
      if members[base] and members[base] ~= line then return fail("dup_runtime", base) end
      members[base] = line
    else
      ignored = ignored + 1
    end
  end
  if count == 0 then return fail("bad_zip") end
  log(string.format("pacote: %d itens, %d ignorados (nao sao runtimes)", count, ignored))
  local missing = {}
  local final = {}
  for _, t in ipairs(todo) do
    if members[t.name] then final[#final + 1] = t else missing[#missing + 1] = t.name end
  end
  if #final == 0 then return fail("nothing_in_zip") end
  if check_cancel() then return cancel_done() end

  -- 8) extracao para pasta temporaria dentro de libs + md5 de cada arquivo
  staging = LIBS .. "/.porthub_staging"
  sh("rm -rf " .. shq(staging))
  if not sh("mkdir -p " .. shq(staging)) then return fail("no_write", LIBS) end
  send({ t = "phase", phase = "extract", total = #final })
  for i, t in ipairs(final) do
    send({ t = "progress", phase = "extract", done = i - 1, total = #final, label = t.name })
    local dst = staging .. "/" .. t.name
    if not sh("unzip -p " .. shq(ZIP) .. " " .. shq(members[t.name]) .. " > " .. shq(dst) .. " 2>/dev/null") then
      return fail("bad_zip", t.name)
    end
    local e = index[t.name]
    if fsize(dst) ~= e.size or md5(dst) ~= e.md5 then return fail("checksum", t.name) end
    if check_cancel() then return cancel_done() end
  end
  send({ t = "progress", phase = "extract", done = #final, total = #final })
  -- o ZIP ja nao e necessario: libera espaco antes da troca
  os.remove(ZIP)

  -- 9) backup + troca (sem cancelamento a partir daqui)
  send({ t = "phase", phase = "install", total = #final })
  local backup = LIBS .. "/.porthub_backup_" .. os.date("%Y%m%d_%H%M%S")
  if not sh("mkdir -p " .. shq(backup)) then return fail("no_write", LIBS) end
  local moved, placed = {}, {}
  local function restore()
    log("restaurando backup...")
    for _, n in ipairs(placed) do os.remove(LIBS .. "/" .. n) end
    for _, n in ipairs(moved) do
      sh("mv -f " .. shq(backup .. "/" .. n) .. " " .. shq(LIBS .. "/" .. n))
    end
    sh("rm -rf " .. shq(backup))
  end
  for i, t in ipairs(final) do
    local cur = LIBS .. "/" .. t.name
    -- arquivo atual e seu .md5 (se existir) vao para o backup
    for _, n in ipairs({ t.name, t.name .. ".md5" }) do
      if sh("test -e " .. shq(LIBS .. "/" .. n)) then
        if not sh("mv -f " .. shq(LIBS .. "/" .. n) .. " " .. shq(backup .. "/" .. n)) then
          restore()
          return fail("install_failed", n)
        end
        moved[#moved + 1] = n
      end
    end
    if not sh("mv -f " .. shq(staging .. "/" .. t.name) .. " " .. shq(cur)) then
      restore()
      return fail("install_failed", t.name)
    end
    placed[#placed + 1] = t.name
    sh("chmod 644 " .. shq(cur) .. " 2>/dev/null")
    -- se havia um .md5 ao lado, grava o md5 novo (mesmo formato do md5sum)
    for _, n in ipairs(moved) do
      if n == t.name .. ".md5" then
        local fh = io.open(cur .. ".md5", "wb")
        if fh then fh:write(index[t.name].md5 .. "  " .. t.name .. "\n"); fh:close(); placed[#placed + 1] = n end
      end
    end
    send({ t = "progress", phase = "install", done = i, total = #final, label = t.name })
  end
  sh("sync")

  -- 10) limpeza
  sh("rm -rf " .. shq(backup))
  cleanup()
  local newn, updn = 0, 0
  for _, t in ipairs(final) do if t.kind == "new" then newn = newn + 1 else updn = updn + 1 end end
  log(string.format("concluido: %d novos, %d atualizados em %s", newn, updn, LIBS))
  send({ t = "done", new = newn, update = updn, ok = #uptodate, missing = missing, libs = LIBS })
end

local okrun, err = pcall(run)
if not okrun then
  log("falha interna:", err)
  pcall(cleanup)
  send({ t = "error", code = "internal", detail = tostring(err) })
end
