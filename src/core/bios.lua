-- =============================================================================
--  BIOS do Sistema (Central de Conteudo): estado, pasta de BIOS, operacoes
--  O trabalho pesado fica em threads/bios_thread.lua. O download aparece na
--  Central de Downloads (mesma fila e historico, sem gerenciador novo).
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local C = require("config")
local U = require("lib.util")
local json = require("lib.json")
local Ref = require("core.bios_ref")

local B = {}

B.DIR = C.APP_DIR .. "/bios"                 -- dados do hub (protegido nas atualizacoes)
B.PKG_DIR = B.DIR .. "/pacote"
B.BACKUPS = C.APP_DIR .. "/backups/bios"
local REG, HIST, SCAN, ANALYSIS, INFO, JOURNAL =
  B.DIR .. "/registro.json", B.DIR .. "/historico.json", B.DIR .. "/console.json",
  B.DIR .. "/analise.json", B.DIR .. "/fonte.json", B.DIR .. "/.journal"
local IN, OUT = "hub_bios_in", "hub_bios_out"

local function jread(p)
  local s = U.read_file(p)
  local d = s and json.decode(s) or nil
  return type(d) == "table" and d or nil
end
local function jwrite(p, d)
  U.exec_ok("mkdir -p " .. U.shq(B.DIR))
  if U.write_file(p .. ".tmp", json.encode(d)) then os.rename(p .. ".tmp", p) end
end

-- ---------------------------------------------------------------------------
-- Fonte do pacote
function B.url()
  local s = U.read_file(C.APP_DIR .. "/bios_url.txt")
  s = s and U.trim(s) or ""
  if s:match("^https?://%S+$") then return s, "bios_url.txt" end
  return C.BIOS_URL or "", nil
end

--- existe um link valido para o pacote de BIOS?
function B.url_ok()
  return (B.url()):match("^https?://%S+$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Pasta de BIOS: a configuracao real do RetroArch do console; sem ela, o padrao
-- documentado do dArkOS (/roms/bios; /roms2/bios com dois cartoes). Nada e criado.
local function ra_value(path)
  local s = U.read_file(path)
  if not s then return nil end
  local v = s:match("\n%s*system_directory%s*=%s*\"([^\"]*)\"") or s:match("^%s*system_directory%s*=%s*\"([^\"]*)\"")
  if not v or v == "" or v == "default" then return nil end
  if v:sub(1, 1) == "~" then v = (os.getenv("HOME") or "/home/ark") .. v:sub(2) end
  return v
end

function B.detect_dir(force)
  if B.dir_info and not force then return B.dir_info end
  local info = {}
  local env = os.getenv("PORTHUB_BIOS_DIR")
  if env and env ~= "" then
    info.dir, info.source = env, L("teste (PORTHUB_BIOS_DIR)")
  else
    local cfgs = {}
    local envcfg = os.getenv("PORTHUB_RA_CFG")
    if envcfg and envcfg ~= "" then cfgs = { envcfg }
    else
      local home = os.getenv("PORTHUB_XDG_ORIG") and "/home/ark" or (os.getenv("HOME") or "/home/ark")
      cfgs = { "/home/ark/.config/retroarch/retroarch.cfg", "/home/ark/.config/retroarch32/retroarch.cfg" }
      if home ~= "/home/ark" then table.insert(cfgs, 1, home .. "/.config/retroarch/retroarch.cfg") end
    end
    local vals = {}
    for _, c in ipairs(cfgs) do
      local v = ra_value(c)
      if v then vals[#vals + 1] = { cfg = c, dir = v:gsub("/+$", "") } end
    end
    for _, v in ipairs(vals) do
      if U.is_dir(v.dir) then info.dir, info.source = v.dir, v.cfg:match("([^/]+/[^/]+)$"); break end
    end
    if #vals > 1 and vals[1].dir ~= vals[2].dir then info.differs = vals[1].dir .. " / " .. vals[2].dir end
    if not info.dir then
      local dual = C.PORTS_DIR:sub(1, 7) == "/roms2/"
      if dual and U.is_dir("/roms2/bios") then info.dir, info.source = "/roms2/bios", L("padrão do dArkOS (2 cartões)")
      elseif U.is_dir("/roms/bios") then info.dir, info.source = "/roms/bios", L("padrão do dArkOS")
      end
    end
  end
  if info.dir then info.roms = info.dir:match("^(.*)/[^/]+$") end
  B.dir_info = info
  return info
end

-- ---------------------------------------------------------------------------
-- Dados guardados
function B.registry() local d = jread(REG) or {}; d.items = d.items or {}; return d end
function B.history() local d = jread(HIST); return d or {} end
function B.scan() if B._scan == nil then B._scan = jread(SCAN) or false end return B._scan or nil end
function B.analysis() if B._an == nil then B._an = jread(ANALYSIS) or false end return B._an or nil end
function B.info() if B._info == nil then B._info = jread(INFO) or false end return B._info or nil end

--- pacote baixado (registrado pelo hub e ainda no cartao)
function B.package()
  for _, it in ipairs(B.registry().items) do
    if it.kind == "package" and U.exists(it.path) then return it end
  end
end

--- a analise ainda vale? (pasta temporaria existe e o pacote e o mesmo)
function B.analysis_ready()
  local a = B.analysis()
  return a and a.tmp and U.is_dir(a.tmp) and true or false
end

--- itens que a limpeza pode apagar, com tamanho
function B.clean_plan()
  local out, total = {}, 0
  for _, it in ipairs(B.registry().items) do
    if U.exists(it.path) then
      local kb = tonumber(((U.capture("du -sk " .. U.shq(it.path) .. " 2>/dev/null") or ""):match("^(%d+)")) or "0")
      out[#out + 1] = { path = it.path, kind = it.kind, size = kb * 1024 }
      total = total + kb * 1024
    end
  end
  return out, total
end

-- ---------------------------------------------------------------------------
-- Estados (por arquivo e por sistema)
B.ST = {
  installed = { L("INSTALADA"), "green" },
  missing = { L("AUSENTE"), "red" },
  update = { L("ATUALIZAÇÃO DISPONÍVEL"), "accent2" },
  pending = { L("VERIFICAÇÃO PENDENTE"), "yellow" },
  incompatible = { L("INCOMPATÍVEL"), "orange" },
  error = { L("ERRO NA INSTALAÇÃO"), "red" },
  optional = { L("OPCIONAL"), "faint" },
}

local function last_errors()
  local errs, ok = {}, {}
  for _, h in ipairs(B.history()) do
    for _, it in ipairs(h.items or {}) do
      local k = tostring(it.target or ""):lower()
      if not ok[k] and not errs[k] then
        if it.action == "error" then errs[k] = true else ok[k] = true end
      end
    end
  end
  return errs
end

--- melhor arquivo do pacote (reconhecido pelo hash) para cada destino
local function pkg_by_target()
  local a = B.analysis_ready() and B.analysis() or nil
  local t = {}
  for _, it in ipairs(a and a.items or {}) do
    if it.target and (it.kind == "bios" or it.kind == "name") then
      local k = it.target:lower()
      if not t[k] or (it.verified and not t[k].verified) then t[k] = it end
    end
  end
  return t
end

function B.file_state(path, opt, ctx)
  local k = path:lower()
  local scan = ctx.scan
  local e = scan and scan.files and scan.files[k]
  local p = ctx.pkg[k]
  if not scan then return "pending", e, p end
  if ctx.errs[k] and not (e and e.verified) then return "error", e, p end
  if not e then return opt and "optional" or "missing", e, p end
  if e.special then return "incompatible", e, p end
  if e.verified then return "installed", e, p end
  if p and p.verified and p.md5 ~= e.md5 then return "update", e, p end
  if e.wrong then return "incompatible", e, p end
  return "pending", e, p
end

local RANK = { error = 1, incompatible = 2, update = 3, missing = 4, pending = 5, installed = 6, optional = 7 }

--- linhas por sistema: { sys, state, present, total, files = { {path, state, opt, e, p} }, games }
function B.rows()
  local ctx = { scan = B.scan(), pkg = pkg_by_target(), errs = last_errors() }
  local rows = {}
  for _, s in ipairs(Ref.SYSTEMS) do
    local files, present, total = {}, 0, 0
    local states = {}
    for _, f in ipairs(Ref.files_of(s)) do
      local opt = s.opt and s.opt[f] or false
      local st, e, p = B.file_state(f, opt, ctx)
      files[#files + 1] = { path = f, state = st, opt = opt, e = e, p = p }
      total = total + 1
      if e then present = present + 1 end
      states[f] = st
      for _, cp in ipairs((s.copies or {})[f] or {}) do
        local st2, e2, p2 = B.file_state(cp, true, ctx)
        files[#files + 1] = { path = cp, state = st2, opt = true, e = e2, p = p2, copy = true }
      end
    end
    local function has(f) local st = states[f]; return st == "installed" or st == "pending" or st == "update" or st == "incompatible" end
    local missing
    if not ctx.scan then missing = false
    elseif s.rule == "all" then
      for _, f in ipairs(s.files) do if not (s.opt and s.opt[f]) and not has(f) then missing = true end end
    elseif s.rule == "groups" then
      for _, g in ipairs(s.groups) do
        local any = false
        for _, f in ipairs(g) do if has(f) then any = true end end
        if not any then missing = true end
      end
    else
      local req, any = false, false
      for _, f in ipairs(s.files) do
        if not (s.opt and s.opt[f]) then req = true end
        if has(f) then any = true end
      end
      missing = not any
      if missing and not req then missing = "optional" end
    end
    local st = "installed"
    for _, f in ipairs(files) do
      if not f.copy and (f.state == "error" or f.state == "incompatible" or f.state == "update") and RANK[f.state] < RANK[st] then st = f.state end
    end
    if st == "installed" then
      if not ctx.scan then st = "pending"
      elseif missing == "optional" then st = "optional"
      elseif missing then st = "missing"
      else
        for _, f in ipairs(files) do if not f.copy and f.state == "pending" then st = "pending" end end
      end
    end
    rows[#rows + 1] = { sys = s, state = st, present = present, total = total, files = files,
      games = ctx.scan and ctx.scan.games and ctx.scan.games[s.id] or false }
  end
  -- sistemas com jogos primeiro; depois por estado e nome
  table.sort(rows, function(a, b)
    if a.games ~= b.games then return a.games end
    if RANK[a.state] ~= RANK[b.state] then return RANK[a.state] < RANK[b.state] end
    return a.sys.name < b.sys.name
  end)
  return rows
end

--- resumo: quantos sistemas por estado
function B.summary()
  local n = { installed = 0, missing = 0, update = 0, pending = 0, incompatible = 0, error = 0, optional = 0 }
  for _, r in ipairs(B.rows()) do n[r.state] = (n[r.state] or 0) + 1 end
  return n
end

-- ---------------------------------------------------------------------------
-- Operacoes (uma por vez)
function B.busy() return B.job ~= nil and B.job.state == "running" end

local function tools()
  local Mgr = require("core.updater.manager")
  local t = Mgr.tools()
  local function plain(x) return x and { kind = x.kind, bin = x.bin, name = x.name } or nil end
  return { zip = plain(t.zip), ["7z"] = plain(t["7z"]), rar = plain(t.rar) }
end

--- inicia uma operacao da thread. on_done(job) ao terminar (sucesso ou nao)
function B.start(op, args, on_done)
  if B.busy() then return false, L("Já existe uma operação de BIOS em andamento.") end
  local d = B.detect_dir()
  if (op == "scan" or op == "analyze" or op == "install" or op == "restore") and not d.dir then
    return false, L("A pasta de BIOS do console não foi encontrada. Nada foi feito.")
  end
  if (op == "info" or op == "download") and not B.url_ok() then
    return false, L("O link do pacote de BIOS não foi configurado (bios_url.txt). Nada foi feito.")
  end
  U.exec_ok("mkdir -p " .. U.shq(B.DIR))
  local job = { op = op, out_channel = OUT, in_channel = IN, app_bios = B.DIR, pkg_dir = B.PKG_DIR, backups_dir = B.BACKUPS,
    bios_dir = d.dir, roms_dir = d.roms, fetch_sh = C.FETCH_SH, url = (B.url()), tools = tools(),
    simulate_fail = os.getenv("PORTHUB_BIOS_FAIL_AT") }
  for k, v in pairs(args or {}) do job[k] = v end
  love.thread.getChannel(OUT):clear()
  love.thread.getChannel(IN):clear()
  B.out_ch, B.in_ch = love.thread.getChannel(OUT), love.thread.getChannel(IN)
  B.job = { op = op, state = "running", phase = nil, done = 0, total = nil, on_done = on_done, t0 = love.timer.getTime(),
    speed = 0, samples = {} }
  B.thread = love.thread.newThread("threads/bios_thread.lua")
  B.thread:start(job)
  if op == "download" then
    local D = require("core.downloads")
    B.job.dl = D.ext_begin({ pid = "bios_package", name = job.name or L("Pacote de BIOS"), op = L("Download de BIOS"),
      cancel = B.cancel, opts = { download_only = true, screen = "bios" } })
  end
  U.log("BIOS: operação", op, "iniciada")
  return true
end

function B.cancel()
  if B.busy() and B.in_ch then B.in_ch:push("cancel") end
end

B.PHASE = {
  source = L("Consultando a fonte"), download = L("Baixando o pacote"), verify = L("Conferindo o arquivo baixado"),
  scan = L("Verificando as BIOS do console"), list = L("Lendo o conteúdo do pacote"), test = L("Testando a integridade do pacote"),
  extract = L("Extraindo numa pasta temporária"), hash = L("Identificando os arquivos"), check = L("Conferindo os arquivos"),
  backup = L("Fazendo backup das BIOS atuais"), install = L("Instalando"), restore = L("Restaurando o backup"),
  clean = L("Apagando os arquivos de instalação"),
}

local MSG = {
  source = L("A fonte não respondeu. Confira a internet e tente de novo."),
  not_found = L("O arquivo não foi encontrado na fonte: "),
  space = L("Espaço livre insuficiente no cartão SD."),
  download = L("Falha no download (código "),
  empty = L("O arquivo baixado veio vazio."),
  size = L("Download incompleto (tamanho diferente do informado pela fonte). Tente de novo."),
  format = L("O arquivo não é um ZIP, 7Z ou RAR válido."),
  md5 = L("O arquivo baixado não confere com o MD5 informado pela fonte. Tente de novo."),
  save = L("Não foi possível salvar o pacote."),
  no_bios_dir = L("A pasta de BIOS do console não foi encontrada."),
  no_tool = L("Este console não tem uma ferramenta para abrir este formato: "),
  list = L("Não foi possível ler o conteúdo do pacote (arquivo danificado ou incompleto)."),
  too_many = L("O pacote tem arquivos demais."),
  path = L("O pacote tem um caminho não permitido: "),
  link = L("O pacote contém links ou arquivos especiais, que não são permitidos: "),
  integrity = L("O pacote está danificado (falhou no teste de integridade)."),
  extract = L("Falha ao extrair o pacote."),
  nothing = L("Nenhuma BIOS selecionada."),
  src_changed = L("Um arquivo extraído mudou depois da análise. Analise o pacote de novo: "),
  outside = L("O destino fica fora da pasta permitida: "),
  special = L("O destino é uma pasta ou um link: "),
  not_confirmed = L("Substituição não confirmada: "),
  backup = L("Não foi possível criar o backup. Nada foi alterado: "),
  install_restored = L("Falha ao instalar. Os arquivos anteriores foram restaurados. Arquivo: "),
  backup_missing = L("O backup está incompleto ou não existe mais."),
  restore = L("Falha ao restaurar: "),
  internal = L("Erro interno no Gerenciador de BIOS."),
}

function B.message(code, detail)
  local m = MSG[code] or MSG.internal
  local s = I18N.tr(m)
  if code == "download" then return s .. tostring(detail or "?") .. ")." end
  if detail and (m:sub(-2) == ": " or m:sub(-1) == ":") then return s .. tostring(detail) end
  if code == "space" and detail and tonumber(detail) then return s .. " " .. string.format(I18N.tr(L("Necessário: %s.")), U.format_bytes(tonumber(detail))) end
  return s
end

local function finish(result)
  local j = B.job
  j.state = result
  j.finished = true
  if j.dl then
    local D = require("core.downloads")
    D.ext_finish(j.dl, result == "done" and "done" or (result == "cancelled" and "cancelled" or "error"),
      result == "error" and B.message(j.error_code, j.detail) or nil)
  end
  local r = j.result or {}
  if result == "done" then
    if j.op == "info" then B._info = r.info; B._info.time = os.time(); jwrite(INFO, B._info)
    elseif j.op == "scan" then B._scan = r.scan; jwrite(SCAN, r.scan)
    elseif j.op == "analyze" then B._an = r.analysis; jwrite(ANALYSIS, r.analysis)
    elseif j.op == "download" then B._an = false; os.remove(ANALYSIS)   -- pacote novo: analisar de novo
    elseif j.op == "install" or j.op == "restore" then
      B._scan = nil; os.remove(SCAN)
      local a = B.analysis()
      if a and j.op == "restore" then B._an = false; os.remove(ANALYSIS)   -- destinos mudaram: analisar de novo
      elseif a then
        -- o resumo do pacote passa a mostrar o que ja foi instalado
        local got = {}
        for _, x in ipairs(r.results or {}) do got[tostring(x.target):lower()] = x.md5 end
        for _, it in ipairs(a.items or {}) do
          for _, d in ipairs(it.dests or {}) do
            local m = got[tostring(d.target):lower()]
            if m then
              d.real = d.real or d.create
              d.md5, d.same = m, (m == it.md5)
              d.verified = Ref.md5_known_for(d.target, m)
            end
          end
        end
        jwrite(ANALYSIS, a)
      end
    elseif j.op == "clean" then
      local a = B.analysis()
      if a and a.tmp and not U.is_dir(a.tmp) then B._an = false; os.remove(ANALYSIS) end
    end
  elseif result == "error" then
    pcall(function()
      require("core.errlog").problem(I18N.tr(L("BIOS do Sistema")), B.message(j.error_code, j.detail))
    end)
  end
  U.log("BIOS:", j.op, result, tostring(j.error_code or ""), tostring(j.detail or ""))
  if j.on_done then pcall(j.on_done, j) end
end

function B.update()
  if not B.busy() then return end
  local e = B.thread:getError()
  if e then
    B.job.error_code, B.job.detail = "internal", tostring(e)
    finish("error")
    return
  end
  local j = B.job
  local m = B.out_ch:pop()
  while m do
    if m.t == "phase" then j.phase = m.phase; j.done, j.total = 0, m.total; j.samples = {}
    elseif m.t == "progress" then
      j.done = m.done
      if m.total and m.total > 0 then j.total = m.total end
      if j.phase == "download" then
        local now = love.timer.getTime()
        local s = j.samples
        s[#s + 1] = { now, m.done }
        while #s > 2 and now - s[1][1] > 4 do table.remove(s, 1) end
        if #s >= 2 and s[#s][1] > s[1][1] then j.speed = (s[#s][2] - s[1][2]) / (s[#s][1] - s[1][1]) end
        j.eta = (j.total and j.speed and j.speed > 0) and (j.total - j.done) / j.speed or nil
      end
    elseif m.t == "done" then j.result = m; finish("done"); return
    elseif m.t == "error" then j.error_code, j.detail = m.code, m.detail; finish("error"); return
    elseif m.t == "cancelled" then finish("cancelled"); return
    end
    m = B.out_ch:pop()
  end
  if j.dl then
    require("core.downloads").ext_progress(j.dl, j.phase == "verify" and "verify" or "download", j.done, j.total,
      j.phase == "download" and j.speed or nil, j.phase == "download" and j.eta or nil)
  end
end

-- ---------------------------------------------------------------------------
-- Abertura do app: instalacao interrompida (console desligou no meio)
local function md5_of(path)
  local d = U.read_file(path)
  if not d then return nil end
  return love.data.encode("string", "hex", love.data.hash("md5", d)):lower()
end

--- desfaz uma instalacao que ficou pela metade. Devolve texto para avisar (ou nil)
function B.recover()
  local jr = jread(JOURNAL)
  if not jr or jr.state ~= "installing" then return nil end
  local okall = true
  for _, it in ipairs(jr.items or {}) do
    if it.existed then
      local b = B.BACKUPS .. "/" .. tostring(jr.backup) .. "/files/" .. (it.target:sub(1, 1) == "@" and ("roms/" .. it.target:sub(2)) or ("bios/" .. it.target))
      local data = U.read_file(b)
      if data and U.write_file(it.path .. ".porthub_restore", data) and os.rename(it.path .. ".porthub_restore", it.path) then
      else okall = false end
    elseif U.exists(it.path) and md5_of(it.path) == it.md5 then
      os.remove(it.path)    -- so o arquivo que o proprio hub gravou
    end
    os.remove(it.path .. ".porthub_new")
  end
  os.remove(JOURNAL)
  local h = B.history()
  table.insert(h, 1, { time = os.time(), op = "recover", result = okall and "ok" or "error", backup = jr.backup, items = {} })
  jwrite(HIST, h)
  B._scan = nil
  U.log("BIOS: instalação interrompida desfeita", okall and "ok" or "com falhas")
  return okall and L("Uma instalação de BIOS foi interrompida. Os arquivos anteriores foram restaurados.")
    or L("Uma instalação de BIOS foi interrompida e nem tudo pôde ser restaurado. Veja o histórico em BIOS do Sistema.")
end

return B
