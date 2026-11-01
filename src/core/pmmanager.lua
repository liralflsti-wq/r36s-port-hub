-- =============================================================================
--  Gerenciador do PortMaster (lado da interface)
--  Instalar / atualizar / verificar / reparar o PortMaster com a distribuicao
--  oficial (veja core/pmcore.lua e threads/pm_thread.lua). Os runtimes dos
--  ports continuam com o atualizador de runtimes existente (core/runtimes.lua).
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local C = require("config")
local U = require("lib.util")
local json = require("lib.json")
local P = require("core.pmcore")

local M = { job = nil, seq = 0 }

local HIST = "pm_history.json"
local CHECK = "pm_check.json"
local RTST = "pm_runtimes.json"
local HIST_MAX = 40

local ROOT = os.getenv("PORTHUB_ROOTFS") or ""
local function sh_rm(p) os.execute("rm -rf " .. U.shq(p) .. " 2>/dev/null") end

local ERRORS = {
  no_internet = L("Sem conexão com a internet (ou o GitHub não respondeu). Verifique o Wi-Fi e tente de novo."),
  server_error = L("O servidor oficial do PortMaster recusou o pedido (arquivo não encontrado ou limite de consultas). Tente mais tarde."),
  no_stable = L("Nenhuma versão estável do PortMaster foi encontrada nas fontes oficiais."),
  no_checksum = L("A fonte oficial não informou md5 nem sha256 deste pacote. Sem como conferir o arquivo, nada foi instalado."),
  no_reference = L("O pacote oficial da versão instalada (%s) não foi encontrado com md5/sha256 nas releases. Use Atualizar."),
  version_unknown = L("A versão instalada não pôde ser lida (arquivo version ausente ou inválido). Use Atualizar para reinstalar os arquivos oficiais."),
  unsupported_os = L("Este sistema não é da família ArkOS/dArkOS (pasta /opt/system/Tools não encontrada). Use o instalador oficial do seu sistema."),
  arch = L("Arquitetura do console não suportada pelo pacote: %s"),
  already_installed = L("O PortMaster já está instalado em:\n%s\n\nNada foi alterado. Use Atualizar ou Reparar."),
  not_installed = L("O PortMaster não foi encontrado neste console. Use Instalar."),
  no_write = L("Sem permissão para gravar em: %s"),
  no_read = L("Sem permissão para ler: %s"),
  missing_tool = L("Ferramenta do sistema ausente: %s"),
  no_space = L("Espaço insuficiente no cartão SD."),
  no_space_dl = L("O cartão ficou sem espaço durante o download."),
  net_error = L("A conexão caiu durante o download. Nada foi instalado; tente de novo."),
  size_mismatch = L("Download incompleto: o tamanho do arquivo não confere."),
  checksum = L("O arquivo baixado não confere com o %s oficial. Ele foi apagado e nada foi instalado."),
  empty = L("O arquivo baixado está vazio."),
  bad_zip = L("O pacote baixado está corrompido (teste do ZIP falhou). Nada foi extraído."),
  unsafe_zip = L("O pacote contém caminhos inseguros e foi recusado: %s"),
  incompatible = L("O pacote encontrado não é compatível com este console (%s). Nada foi instalado."),
  extract_failed = L("Falha ao extrair o pacote. Nada foi alterado na instalação. %s"),
  version_mismatch = L("A versão dentro do pacote não confere com a release. Nada foi instalado."),
  backup_failed = L("Não foi possível fazer o backup dos arquivos. Nada foi alterado."),
  apply_failed = L("Falha ao gravar os arquivos novos."),
  validate_failed = L("A conferência depois da gravação encontrou %s arquivo(s) com problema."),
  preserve_failed = L("A conferência final notou mudança em dados que deveriam ficar intactos (%s). Por segurança, a atualização foi desfeita."),
  pending_recovery = L("Há uma operação anterior do PortMaster que não terminou. Feche e abra o hub para concluir a restauração antes de continuar."),
  interrupted_test = L("Operação interrompida (teste)."),
  internal = L("Erro interno no gerenciador do PortMaster: %s"),
}

M.CLASS = {
  ok = { L("INSTALAÇÃO ÍNTEGRA"), "green" },
  update = { L("ATUALIZAÇÃO DISPONÍVEL"), "accent2" },
  missing = { L("ARQUIVOS AUSENTES"), "red" },
  incomplete = { L("INSTALAÇÃO INCOMPLETA"), "red" },
  perms = { L("PERMISSÕES INCORRETAS"), "yellow" },
  dependency = { L("DEPENDÊNCIA AUSENTE"), "yellow" },
  unverifiable = { L("NÃO FOI POSSÍVEL VERIFICAR"), "yellow" },
}

M.OP_LABEL = {
  install = L("Instalação do PortMaster"), update = L("Atualização do PortMaster"),
  repair = L("Reparo do PortMaster"), verify = L("Verificação do PortMaster"),
  check = L("Consulta de versão do PortMaster"), recover = L("Recuperação após operação interrompida"),
  runtimes = L("Verificação de runtimes"),
}

function M.error_text(code, detail)
  local msg = ERRORS[code] and I18N.tr(ERRORS[code]) or (L("Erro: ") .. tostring(code))
  if code == "incompatible" and detail then
    local why, what = detail:match("^([^|]*)|?(.*)$")
    local w = why == "arch" and L("arquitetura") or (why == "cfw" and L("sistema") or L("estrutura"))
    detail = w .. (what ~= "" and (": " .. what) or "")
  end
  if code == "preserve_failed" and detail then
    local names = { ports = L("ports e saves"), libs = L("runtimes"), config = L("configurações e temas") }
    local t = {}
    for k in detail:gmatch("[^,]+") do t[#t + 1] = names[k] or k end
    detail = table.concat(t, ", ")
  end
  if msg:find("%%s") then msg = msg:format(detail or "") end
  if code == "no_space" and detail and detail:match("^%d+|%d+$") then
    local need, have = detail:match("^(%d+)|(%d+)$")
    msg = msg .. string.format(L("\nNecessário: %s   Livre: %s"), U.format_bytes(tonumber(need)), U.format_bytes(tonumber(have)))
  elseif code == "size_mismatch" and detail and detail:match("^%d+|%d+$") then
    local got, exp = detail:match("^(%d+)|(%d+)$")
    msg = msg .. string.format(L("\nRecebido: %s de %s"), U.format_bytes(tonumber(got)), U.format_bytes(tonumber(exp)))
  end
  return msg
end

-- ---------------------------------------------------------------------------
-- caminhos
function M.tools_dir()
  local t = ROOT .. "/opt/system/Tools"
  if U.exec_ok("test -d " .. U.shq(t)) then return t end
  return nil
end

function M.manifest_file() return love.filesystem.getSaveDirectory() .. "/pm_manifest.txt" end

local function pm_dirs()
  local t = {}
  for _, d in ipairs(C.PORTMASTER_DIRS) do if d and d ~= "" then t[#t + 1] = d end end
  return t
end

--- estado rapido, sem internet (tela principal)
function M.quick_status()
  local dirs = pm_dirs()
  local td = M.tools_dir()
  if td then dirs[#dirs + 1] = td .. "/PortMaster" end
  local best, bs = nil, -1
  local seen = {}
  for _, d in ipairs(dirs) do
    if d ~= "/PortMaster" and not seen[d] then
      seen[d] = true
      local out = U.capture("cd " .. U.shq(d) .. " 2>/dev/null && ls -A | head -n 1; "
        .. "for f in control.txt pugwash version harbourmaster; do [ -f " .. U.shq(d) .. "/$f ] && echo \"F:$f\"; done") or ""
      if out ~= "" then
        local s = 0
        for f in out:gmatch("F:(%S+)") do s = s + ((f == "control.txt" or f == "pugwash") and 2 or 1) end
        if s > bs then best, bs = d, s end
      end
    end
  end
  if not best then return { state = "missing" } end
  local ver = U.trim((U.read_file(best .. "/version") or ""):match("^[^\n]*") or "")
  local st = (bs >= 6 and P.valid_version(ver)) and "installed" or "incomplete"
  return { state = st, dir = best, version = ver ~= "" and ver or nil }
end

--- ambiente do console (tudo lido do sistema; o que nao der para ler fica nil)
function M.env()
  local ok, Compat = pcall(require, "core.compat")
  local e = ok and Compat.detect() or {}
  local r = {
    model = e.model, arch = e.arch, pkg_arch = e.pkg_arch, kernel = e.kernel,
    os_id = e.os_id, os_name = e.os_name, os_version = e.os_version,
  }
  local okr, R36 = pcall(require, "core.r36ctl")
  if okr then
    local s = R36.status and R36.status() or {}
    r.variant = s.variant
  end
  r.tools = M.tools_dir()
  local q = M.quick_status()
  r.pm_dir = q.dir
  local probe = q.dir or r.tools
  if probe then
    r.free = U.free_space(probe)
    r.writable = U.exec_ok("test -w " .. U.shq(probe))
    r.fs = U.trim(U.capture("stat -f -c %T " .. U.shq(probe) .. " 2>/dev/null") or "")
    if r.fs == "" then r.fs = nil end
  end
  if q.dir then
    local parent = q.dir:match("^(.*)/[^/]+$") or ""
    r.launcher = U.exec_ok("test -f " .. U.shq(parent .. "/PortMaster.sh")) and (parent .. "/PortMaster.sh")
      or (U.exec_ok("test -f " .. U.shq(q.dir .. "/PortMaster.sh")) and (q.dir .. "/PortMaster.sh") or nil)
    r.libs = tonumber(U.trim(U.capture("ls -1 " .. U.shq(q.dir .. "/libs") .. " 2>/dev/null | grep -c '\\.squashfs$'") or "")) or 0
  end
  return r
end

-- ---------------------------------------------------------------------------
-- historico (sem senhas/tokens: so datas, versoes, fontes, arquivos e resultados)
function M.history()
  local okr, text = pcall(love.filesystem.read, HIST)
  if not okr or not text then return {} end
  local d = json.decode(text)
  return type(d) == "table" and d or {}
end

function M.add_history(e)
  local h = M.history()
  e.time = e.time or os.time()
  table.insert(h, 1, e)
  while #h > HIST_MAX do table.remove(h) end
  pcall(love.filesystem.write, HIST, json.encode(h))
end

function M.clear_history() pcall(love.filesystem.write, HIST, "[]") end

-- ultima consulta de versao (com data; nunca inventada)
function M.last_check()
  if M._check then return M._check end
  local okr, text = pcall(love.filesystem.read, CHECK)
  if okr and text then
    local d = json.decode(text)
    if type(d) == "table" and d.stable then M._check = d end
  end
  return M._check
end

local function save_check(m)
  local d = { time = os.time(), stable = m.stable and m.stable.version, url = m.stable and m.stable.url,
    src = m.stable and m.stable.src, others = m.others }
  M._check = d
  pcall(love.filesystem.write, CHECK, json.encode(d))
end

-- ---------------------------------------------------------------------------
-- runtimes: estado vem do atualizador de runtimes existente
function M.runtimes_state()
  local okr, text = pcall(love.filesystem.read, RTST)
  local d = okr and text and json.decode(text) or nil
  if type(d) ~= "table" then return "needed" end
  -- a pasta libs mudou desde a ultima verificacao: precisa verificar de novo
  local q = M.quick_status()
  local libs = q.dir and U.trim(U.capture("ls -1 " .. U.shq(q.dir .. "/libs") .. " 2>/dev/null | grep '\\.squashfs$' | md5sum") or "") or ""
  if d.libs ~= libs or d.dir ~= q.dir then return "needed" end
  return d.state or "needed", d
end

function M.set_runtimes_state(state, detail)
  local q = M.quick_status()
  local libs = q.dir and U.trim(U.capture("ls -1 " .. U.shq(q.dir .. "/libs") .. " 2>/dev/null | grep '\\.squashfs$' | md5sum") or "") or ""
  pcall(love.filesystem.write, RTST, json.encode({ state = state, time = os.time(), dir = q.dir, libs = libs, detail = detail }))
  M.add_history({ op = "runtimes", result = state == "ok" and "ok" or (state == "incomplete" and "warn" or "error"),
    note = detail })
end

-- ---------------------------------------------------------------------------
function M.busy() return M.job ~= nil and not M.job.finished end

function M.start(op, opts)
  opts = opts or {}
  if M.busy() then return false, L("Já existe uma operação do PortMaster em andamento.") end
  local Installer, Runtimes = require("core.installer"), require("core.runtimes")
  if Installer.busy() or Runtimes.busy() or require("core.uninstall").busy() then
    return false, L("Aguarde os downloads e instalações em andamento terminarem (veja a Central de Downloads).")
  end
  M.seq = M.seq + 1
  local Compat = require("core.compat")
  local env = Compat.detect()
  local j = {
    op = op, phase = "check", label = "", done = 0, total = nil, speed = 0, eta = nil, samples = {},
    finished = false, result = nil, confirm = nil, started = os.time(),
    out = "hub_pm_out_" .. M.seq, inn = "hub_pm_in_" .. M.seq,
  }
  j.out_ch = love.thread.getChannel(j.out)
  j.in_ch = love.thread.getChannel(j.inn)
  j.out_ch:clear(); j.in_ch:clear()
  j.thread = love.thread.newThread("threads/pm_thread.lua")
  j.thread:start({ op = op, lang = I18N.lang,
    out_channel = j.out, in_channel = j.inn,
    tmp_dir = C.TMP_DIR, fetch_sh = C.FETCH_SH, margin = C.SPACE_MARGIN,
    pm_dirs = pm_dirs(), tools = M.tools_dir(), root = ROOT,
    arch = env.arch, os_id = env.os_id, ports_dir = C.PORTS_DIR, app_dir = C.APP_DIR,
    manifest_file = M.manifest_file(), deep = opts.deep, offline = opts.offline,
    test_fail = os.getenv("PORTHUB_PM_TESTFAIL"),
  })
  M.job = j
  U.log("portmaster:", op, "iniciado")
  return true
end

local function speed(j, now)
  local s = j.samples
  s[#s + 1] = { now, j.done }
  while #s > 2 and now - s[1][1] > 4 do table.remove(s, 1) end
  if #s >= 2 and s[#s][1] > s[1][1] then
    j.speed = (s[#s][2] - s[1][2]) / (s[#s][1] - s[1][1])
    j.eta = (j.total and j.total > 0 and j.speed > 0) and (j.total - j.done) / j.speed or nil
  end
end

-- Central de Downloads: a operacao aparece la (mesma fila/historico, sem gerenciador novo)
local function dl_entry(j)
  if j.dl then return j.dl end
  local D = require("core.downloads")
  j.dl = D.ext_begin({ pid = "portmaster_app", name = "PortMaster" .. (j.version and (" " .. j.version) or ""),
    op = M.OP_LABEL[j.op], cancel = M.cancel, opts = j.op == "verify" and { mode = "extract" } or nil })
  return j.dl
end

local function dl_sync(j)
  if not j.dl then return end
  require("core.downloads").ext_progress(j.dl, j.phase, j.done, j.total, j.phase == "download" and j.speed or nil,
    j.phase == "download" and j.eta or nil)
end

local function finish_history(j)
  local e = { op = j.op, time = os.time(), src = j.src }
  local s = j.summary
  if j.result == "done" and s then
    e.result = "ok"
    e.from, e.to = s.from, s.version
    if s.op == "install" then e.from = nil
      e.note = string.format(L("%d arquivo(s) instalados em %s"), s.files or 0, s.dir or "")
    elseif s.op == "update" then
      if s.uptodate then e.result, e.from, e.to = "info", s.version, s.stable; e.note = L("Já estava atualizado")
      else e.note = string.format(L("%d substituído(s), %d novo(s); backup: %s"), s.replaced or 0, s.added or 0, s.backup or "") end
    elseif s.op == "repair" then
      e.from = s.version
      e.note = s.nothing and L("Nenhum arquivo oficial ausente ou alterado")
        or string.format(L("%d restaurado(s), %d substituído(s)"), s.restored or 0, s.replaced or 0)
    elseif s.op == "verify" then
      e.from = s.version
      local cl = {}
      for _, c in ipairs(s.classes or {}) do cl[#cl + 1] = M.CLASS[c] and M.CLASS[c][1] or c end
      e.note = s.installed == false and L("PortMaster não instalado") or table.concat(cl, ", ")
      e.result = (s.classes and s.classes[1] == "ok") and "ok" or "warn"
    elseif s.op == "check" then
      e.to = s.stable and s.stable.version
      e.note = L("Última versão estável consultada")
    end
    e.url = s.url
    e.method = s.method
  elseif j.result == "error" then
    e.result = "error"
    e.error = j.error
    if j.recovered ~= nil then
      e.note = j.recovered and L("Backup restaurado e conferido (md5).") or L("A restauração do backup NÃO pôde ser confirmada.")
    end
  else
    e.result = "cancelled"
  end
  M.add_history(e)
end

function M.update()
  local j = M.job
  if not j or j.finished then return end
  local err = j.thread:getError()
  if err then
    U.log("thread do portmaster falhou:", err)
    j.finished, j.result, j.error = true, "error", M.error_text("internal", err)
    if j.dl then require("core.downloads").ext_finish(j.dl, "error", j.error) end
    finish_history(j)
    return
  end
  local m = j.out_ch:pop()
  while m do
    if m.t == "phase" then
      j.phase, j.done, j.label = m.phase, 0, m.label or ""
      j.total = m.total
      if m.phase == "download" then j.samples, j.speed, j.eta = {}, 0, nil; dl_entry(j) end
      dl_sync(j)
    elseif m.t == "progress" then
      j.phase = m.phase or j.phase
      j.done, j.total = m.done or 0, m.total or j.total
      if j.phase == "download" then speed(j, love.timer.getTime()) end
      dl_sync(j)
    elseif m.t == "confirm" then
      j.confirm = m
      j.version = m.to or m.version
    elseif m.t == "done" then
      j.finished, j.result, j.summary = true, "done", m
      j.src = m.src
      if m.op == "check" or m.op == "install" or m.op == "update" then
        if m.op == "check" then save_check(m)
        elseif m.version and not m.uptodate then
          -- a consulta que acabou de ser feita vale como "ultima versao estavel"
          if m.op == "install" or m.op == "update" then save_check({ stable = { version = m.version, url = m.url, src = m.src }, others = m.others }) end
        elseif m.uptodate then save_check({ stable = { version = m.stable }, others = m.others }) end
      elseif m.op == "verify" and m.result and m.result.stable then
        save_check({ stable = { version = m.result.stable } })
      end
      if j.dl then require("core.downloads").ext_finish(j.dl, "done") end
      pcall(function() require("core.compat").invalidate() end)
      finish_history(j)
    elseif m.t == "error" then
      j.finished, j.result, j.error_code = true, "error", m.code
      j.error = M.error_text(m.code, m.detail)
      j.recovered = m.recovered
      j.detail = m
      if j.dl then require("core.downloads").ext_finish(j.dl, "error", j.error) end
      finish_history(j)
    elseif m.t == "cancelled" then
      j.finished, j.result = true, "cancelled"
      if j.dl then require("core.downloads").ext_finish(j.dl, "cancelled") end
      finish_history(j)
    end
    m = j.out_ch:pop()
  end
end

function M.cancel()
  local j = M.job
  if not j or j.finished then return end
  j.cancelling = true
  j.in_ch:push({ t = "cancel" })
end

--- pode cancelar? (backup/gravacao/conferencia nao sao interrompidos)
function M.can_cancel()
  local j = M.job
  return j and not j.finished and not (j.phase == "backup" or j.phase == "apply" or j.phase == "validate")
end

function M.answer(yes)
  local j = M.job
  if not j or not j.confirm then return end
  j.confirm = nil
  j.in_ch:push({ t = "answer", yes = yes and true or false })
end

function M.clear() if M.job and M.job.finished then M.job = nil end end

-- ---------------------------------------------------------------------------
-- Na abertura: conclui uma operacao interrompida (ex.: bateria acabou)
-- So informa "restaurado" se o md5 de cada arquivo voltou ao original.
function M.recover()
  sh_rm(C.TMP_DIR .. "/pm_job")
  local q = M.quick_status()
  local bases = {}
  if q.dir then bases[#bases + 1] = q.dir:match("^(.*)/[^/]+$") end
  local td = M.tools_dir()
  if td then bases[#bases + 1] = td end
  local seen = {}
  for _, b in ipairs(bases) do
    if b and not seen[b] then
      seen[b] = true
      -- pasta de extracao temporaria que sobrou
      sh_rm(b .. "/.porthub_pm_staging")
      local jd = b .. "/.porthub_pm"
      local st = U.trim(U.read_file(jd .. "/state") or "")
      local info = U.read_file(jd .. "/info") or ""
      if st == "applying" or st == "validating" or st == "backup" then
        -- o mesmo script de restauracao da thread (so copia do backup e remove o que foi adicionado)
        U.write_file(jd .. "/rollback.sh", P.ROLLBACK_SH)
        local rc = U.exec_ok("sh " .. U.shq(jd .. "/rollback.sh") .. " " .. U.shq(jd) .. " >/dev/null 2>&1")
        -- confere: arquivos do backup voltaram (md5) e os adicionados sumiram
        local okc = rc
        if st ~= "backup" then
          local out = U.capture("md5sum -c " .. U.shq(jd .. "/backup.md5") .. " 2>/dev/null | grep -vc ': OK$'") or ""
          if (tonumber(U.trim(out)) or 1) > 0 then okc = false end
        end
        for line in (U.read_file(jd .. "/plan.tsv") or ""):gmatch("[^\n]+") do
          local k, _, d = line:match("^(%S)\t([^\t]*)\t([^\t]*)")
          if k == "N" and U.exists(d) then okc = false end
        end
        U.write_file(jd .. "/state", okc and "rolledback\n" or "rollback_failed\n")
        M.add_history({ op = "recover", result = okc and "ok" or "error",
          from = info:match("from=([^\n]*)"), to = info:match("to=([^\n]*)"),
          note = okc and L("Operação interrompida desfeita: arquivos originais restaurados e conferidos (md5).")
            or L("A restauração do backup NÃO pôde ser confirmada. Use Verificar instalação.") })
        U.log("portmaster: recuperacao", okc and "confirmada" or "NAO confirmada")
        M.boot_notice = okc and "ok" or "error"
      elseif st == "installing" then
        M.add_history({ op = "recover", result = "warn", to = info:match("to=([^\n]*)"),
          note = L("A instalação foi interrompida. Use Verificar instalação; se faltar algo, use Reparar.") })
        U.write_file(jd .. "/state", "interrupted\n")
        M.boot_notice = "warn"
      end
    end
  end
end

return M
