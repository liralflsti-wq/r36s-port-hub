-- =============================================================================
--  Central de Downloads: fila + historico em volta do instalador existente.
--  O instalador (core/installer.lua) continua fazendo todo o trabalho; aqui so:
--    - enfileira pedidos (um download por vez, os demais ficam "Aguardando")
--    - impede duplicatas do mesmo port
--    - espelha o progresso REAL do instalador (nada e estimado)
--    - guarda o historico (downloads.json) para consulta
-- =============================================================================
local L = require("lib.i18n").L
local json = require("lib.json")
local U = require("lib.util")
local Installer = require("core.installer")

local D = { list = {}, seq = 0, loaded = false, background = false }
local FILE = "downloads.json"
local HISTORY_MAX = 30

-- estados exibidos
D.LABEL = {
  waiting = L("Aguardando"), downloading = L("Baixando"), extracting = L("Extraindo"),
  installing = L("Instalando"), done = L("Concluído"), error = L("Erro"), cancelled = L("Cancelado"),
}
-- fase do instalador -> estado
local PHASE_STATE = {
  prepare = "downloading", download = "downloading", verify = "downloading",
  extract = "extracting", analyze = "extracting", install = "installing",
}

-- etapas exibidas (cada uma com seu proprio estado e porcentagem real)
D.STAGES = { "download", "extract", "install" }
local STAGE_OF = { prepare = "download", download = "download", verify = "download",
  extract = "extract", analyze = "extract", install = "install" }

--- tipo de operacao (texto) a partir das opcoes do pedido
function D.op_label(opts, section)
  opts = opts or {}
  if opts.mode == "extract" then return L("Extração de arquivo local") end
  if opts.local_file then return L("Instalação de arquivo local") end
  return section == "tools" and L("Download e instalação de utilitário") or L("Download e instalação de jogo")
end

local function stage_copy(st)
  if type(st) ~= "table" then return nil end
  local t = {}
  for k, v in pairs(st) do
    if type(v) == "table" then t[k] = { state = v.state, pct = v.pct } end
  end
  return t
end

local function save()
  local hist = {}
  for _, e in ipairs(D.list) do
    if e.state == "done" or e.state == "error" or e.state == "cancelled" then
      -- sem dados sensiveis: so nome, data, resultado e numeros do download
      hist[#hist + 1] = { id = e.pid, name = e.name, section = e.section, state = e.state,
        error = e.error, date = e.date, size = e.dl_total, op = e.op, stages = stage_copy(e.stages),
        avg = e.avg, elapsed = e.elapsed }
    end
  end
  while #hist > HISTORY_MAX do table.remove(hist) end
  pcall(love.filesystem.write, FILE, json.encode(hist))
end

function D.load()
  D.loaded = true
  local ok, text = pcall(love.filesystem.read, FILE)
  if not (ok and text) then return end
  local d = json.decode(text)
  if type(d) ~= "table" then return end
  for _, h in ipairs(d) do
    if type(h) == "table" and h.name then
      D.seq = D.seq + 1
      D.list[#D.list + 1] = { key = D.seq, pid = h.id, name = h.name, section = h.section or "games",
        state = h.state or "done", error = h.error, date = h.date, dl_total = h.size, from_history = true,
        op = h.op, stages = stage_copy(h.stages), avg = h.avg, elapsed = h.elapsed }
    end
  end
end

--- entrada ativa ou aguardando para este port (evita duplicatas)
function D.pending(pid)
  for _, e in ipairs(D.list) do
    if e.pid == pid and (e.state == "waiting" or e.state == "downloading" or e.state == "extracting"
        or e.state == "installing") then
      return e
    end
  end
end

function D.active()
  for _, e in ipairs(D.list) do
    if e.job then return e end
  end
end

function D.waiting_count()
  local n = 0
  for _, e in ipairs(D.list) do if e.state == "waiting" then n = n + 1 end end
  return n
end

--- Coloca um port na fila. Devolve ok, mensagem, iniciou_agora
function D.enqueue(p, opts)
  if not D.loaded then D.load() end
  if D.pending(p.id) then
    return false, p.name .. L(" já está na Central de Downloads.")
  end
  D.seq = D.seq + 1
  local e = { key = D.seq, pid = p.id, port = p, opts = opts or {}, name = p.name, section = p.section or "games",
    state = "waiting", total = p.size, dl_total = p.size, done = 0, date = os.date("%d/%m/%Y %H:%M"),
    op = D.op_label(opts, p.section), stages = {} }
  -- mais recentes primeiro (depois dos que ja estao na fila)
  local pos = 1
  for i, o in ipairs(D.list) do
    if o.state == "waiting" or o.job then pos = i + 1 end
  end
  table.insert(D.list, pos, e)
  return true, nil
end

--- Inicia o proximo da fila quando nada mais estiver ocupando o console.
--- can_start(): checagem externa (runtimes/exclusao em andamento)
function D.pump(can_start)
  if Installer.busy() or D.active() then return end
  if can_start and not can_start() then return end
  for _, e in ipairs(D.list) do
    if e.state == "waiting" then
      local ok, err = Installer.start(e.port, e.opts)
      if ok then
        e.job = Installer.job
        e.job.download_entry = e
        e.job.background = D.background
        e.state = "downloading"
      else
        e.state, e.error = "error", err
        save()
      end
      return e
    end
  end
end

--- Espelha o progresso real do instalador
function D.update()
  local e = D.active()
  if not e or e.ext then return end
  local j = e.job
  if j.finished then return end
  e.state = PHASE_STATE[j.phase] or e.state
  local stg = STAGE_OF[j.phase]
  -- arquivo que ja esta no cartao: nao ha download (etapa pulada)
  if e.opts and e.opts.local_file and stg == "download" then
    stg = nil
    e.state = "extracting"
  end
  -- etapas: a anterior fica concluida quando a seguinte comeca
  if stg then
    e.stages = e.stages or {}
    if e.cur_stage and e.cur_stage ~= stg and e.stages[e.cur_stage] then
      -- a etapa anterior so termina quando a seguinte comeca: concluida de fato
      local prev = e.stages[e.cur_stage]
      prev.state = "ok"
      if prev.pct then prev.pct = 100 end
    end
    if j.phase == "download" and not e.dl_t0 then e.dl_t0 = love.timer.getTime() end
    if stg ~= "download" and e.dl_t0 and not e.dl_t1 then e.dl_t1 = love.timer.getTime() end
    e.cur_stage = stg
    local st = e.stages[stg] or { state = "active" }
    e.stages[stg] = st
    st.state = "active"
    if (j.phase == "download" or j.phase == "extract" or j.phase == "install") and j.total and j.total > 0 then
      st.pct = math.floor(U.clamp((j.done or 0) / j.total, 0, 1) * 100)
    end
  end
  if not e.started then e.started = love.timer.getTime() end
  e.phase = j.phase
  e.done, e.total = j.done, j.total
  if j.phase == "download" and j.total and j.total > 0 then e.dl_total = j.total end
  e.speed = (j.phase == "download") and j.speed or nil
  if j.phase == "download" and j.speed and j.speed > 0 then e.last_speed = j.speed end
  e.eta = (j.phase == "download") and j.eta or nil
end

--- Chamado quando o instalador termina (antes das mensagens na tela)
function D.on_finished(j)
  local e = j.download_entry
  if not e then return end
  e.job = nil
  e.speed, e.eta = nil, nil
  e.elapsed = e.started and (love.timer.getTime() - e.started) or nil
  e.stages = e.stages or {}
  if j.result == "done" then
    e.state = "done"
    -- sucesso: cada etapa necessaria foi concluida; as desnecessarias foram puladas
    -- (arquivo local nao tem download; "so extrair" nao tem instalacao em ports)
    local o = e.opts or {}
    local need = { download = not o.local_file, extract = true, install = o.mode ~= "extract" }
    -- operacao so de download (ex.: pacote de BIOS): extrair e instalar sao etapas a parte
    if o.download_only then need.extract, need.install = false, false end
    for _, k in ipairs(D.STAGES) do
      local st = e.stages[k] or {}
      e.stages[k] = st
      if need[k] then
        st.state = "ok"
        if st.pct then st.pct = 100 end   -- etapa terminou de fato
      else
        st.state, st.pct = "skip", nil
      end
    end
  elseif j.result == "cancelled" then
    e.state = "cancelled"
  else
    e.state = "error"
    e.error = j.error
    pcall(function()
      require("core.netlog").add(L("Download: ") .. tostring(e.name), e.port and e.port.download_url, j.error)
    end)
  end
  if j.result ~= "done" and e.cur_stage and e.stages[e.cur_stage] then
    e.stages[e.cur_stage].state = j.result == "cancelled" and "cancel" or "fail"
  end
  -- velocidade media real do download (bytes recebidos / tempo da etapa de download)
  if e.dl_t0 and e.dl_total and e.dl_total > 0 and e.stages.download and e.stages.download.state == "ok" then
    local t1 = e.dl_t1 or love.timer.getTime()
    if t1 > e.dl_t0 then e.avg = e.dl_total / (t1 - e.dl_t0) end
  end
  e.date = os.date("%d/%m/%Y %H:%M")
  save()
end

--- Cancela: tira da fila (aguardando) ou interrompe o download ativo
function D.cancel(e)
  if e.state == "waiting" then
    e.state = "cancelled"
    e.date = os.date("%d/%m/%Y %H:%M")
    save()
  elseif e.ext and e.job and not e.job.finished then
    if e.cancel_fn then e.cancel_fn() end
  elseif e.job and not e.job.finished then
    Installer.cancel()
  end
end

-- ---------------------------------------------------------------------------
-- Operacoes externas ao instalador (ex.: Gerenciador do PortMaster) aparecem na
-- mesma central, com as mesmas etapas, progresso real e historico. Enquanto uma
-- estiver ativa, a fila espera (um download por vez, nada e interrompido).
local EXT_STAGE = { download = "download", verify = "download", extract = "extract",
  backup = "install", apply = "install", validate = "install" }
local EXT_STATE = { download = "downloading", extract = "extracting", install = "installing" }

function D.ext_begin(info)
  if not D.loaded then D.load() end
  D.seq = D.seq + 1
  local e = { key = D.seq, pid = info.pid, name = info.name, section = "tools", state = "downloading",
    done = 0, date = os.date("%d/%m/%Y %H:%M"), op = info.op, stages = {}, ext = true,
    cancel_fn = info.cancel, opts = info.opts or {} }
  e.job = { finished = false, ext = true }
  local pos = 1
  for i, o in ipairs(D.list) do
    if o.state == "waiting" or o.job then pos = i + 1 end
  end
  table.insert(D.list, pos, e)
  return e
end

function D.ext_progress(e, phase, done, total, speed, eta)
  local stg = EXT_STAGE[phase]
  if not stg then return end
  e.stages = e.stages or {}
  if e.cur_stage and e.cur_stage ~= stg and e.stages[e.cur_stage] then
    local prev = e.stages[e.cur_stage]
    prev.state = "ok"
    if prev.pct then prev.pct = 100 end
  end
  if phase == "download" and not e.dl_t0 then e.dl_t0 = love.timer.getTime() end
  if stg ~= "download" and e.dl_t0 and not e.dl_t1 then e.dl_t1 = love.timer.getTime() end
  e.cur_stage = stg
  local st = e.stages[stg] or { state = "active" }
  e.stages[stg] = st
  st.state = "active"
  e.state = EXT_STATE[stg]
  -- a fase de download/extracao/instalacao usa os nomes que a central ja exibe
  e.phase = (phase == "download" or phase == "verify" or phase == "extract") and phase or "install"
  e.done, e.total = done or 0, total
  if phase == "backup" or phase == "validate" or phase == "verify" then e.total = nil end
  if (phase == "download" or phase == "apply") and total and total > 0 then
    st.pct = math.floor(U.clamp((done or 0) / total, 0, 1) * 100)
  end
  if phase == "download" and total and total > 0 then e.dl_total = total end
  if not e.started then e.started = love.timer.getTime() end
  e.speed, e.eta = speed, eta
  if speed and speed > 0 then e.last_speed = speed end
end

function D.ext_finish(e, result, err)
  if not e or not e.job then return end
  e.job.finished = true
  D.on_finished({ download_entry = e, result = result, error = err })
end

--- quantos itens finalizados (historico) existem
function D.history_count()
  local n = 0
  for _, e in ipairs(D.list) do
    if not (e.state == "waiting" or e.job) then n = n + 1 end
  end
  return n
end

--- Remove do historico os itens finalizados (somente os registros: nenhum
--- arquivo baixado ou instalado e apagado; ativos e na fila continuam)
function D.clear_history()
  local keep = {}
  for _, e in ipairs(D.list) do
    if e.state == "waiting" or e.job then keep[#keep + 1] = e end
  end
  D.list = keep
  save()
end

--- porcentagem REAL (nil quando o total nao e conhecido ou a fase nao tem medida)
function D.percent(e)
  if e.state == "done" then return 100 end
  if not e.job then return nil end
  if e.total and e.total > 0 and (e.phase == "download" or e.phase == "extract" or e.phase == "install") then
    return math.floor(U.clamp(e.done / e.total, 0, 1) * 100)
  end
  return nil
end

return D
