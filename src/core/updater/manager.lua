-- =============================================================================
--  Gerenciador de atualizacoes do R36S PORT HUB (thread principal)
--  Uma operacao por vez (analise, instalacao, restauracao, download), feita
--  em threads/updater_thread.lua. Aqui ficam o estado, as mensagens
--  traduzidas, o historico e a recuperacao na abertura do app.
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")
local Formats = require("core.updater.formats")
local Backup = require("core.updater.backup")
local History = require("core.updater.history")
local Folder = require("core.updater.folder")

local M = { job = nil, tools_cache = nil, restart_needed = nil, boot_notes = nil }
local NOTES_FILE = "update_notes.json"

--- a atualizacao trouxe texto do que mudou/foi corrigido?
function M.has_notes(n)
  return n ~= nil and ((n.description and tostring(n.description):find("%S"))
    or (type(n.changes) == "table" and #n.changes > 0) or (type(n.fixes) == "table" and #n.fixes > 0)) and true or false
end
local IN, OUT = "hub_updater_in", "hub_updater_out"

--- ferramentas de extracao realmente disponiveis (testadas uma vez)
function M.tools()
  if not M.tools_cache then
    M.tools_cache = Formats.detect_tools({ bundled = C.APP_DIR .. "/bin/7zzs", env = os.getenv("PORTHUB_7Z") })
    local av = {}
    for _, f in ipairs({ "zip", "7z", "rar" }) do av[#av + 1] = f .. "=" .. tostring(M.tools_cache[f] and M.tools_cache[f].name) end
    U.log("Atualizações: ferramentas", table.concat(av, " "))
  end
  return M.tools_cache
end

--- "ZIP, 7Z" (formatos com ferramenta) e "RAR" (sem ferramenta)
function M.formats_text()
  local t = M.tools()
  local ok, no = {}, {}
  for _, f in ipairs({ "zip", "7z", "rar" }) do
    if t[f] then ok[#ok + 1] = Formats.LABEL[f] else no[#no + 1] = Formats.LABEL[f] end
  end
  return table.concat(ok, ", "), table.concat(no, ", ")
end

--- o hub esta na estrutura esperada (<ports>/r36sporthub)?
function M.layout_ok()
  if M.layout == nil then
    local a = U.trim(U.capture("readlink -f -- " .. U.shq(C.APP_DIR) .. " 2>/dev/null") or "")
    local p = U.trim(U.capture("readlink -f -- " .. U.shq(C.PORTS_DIR) .. " 2>/dev/null") or "")
    M.layout = a ~= "" and a == p .. "/r36sporthub"
  end
  return M.layout
end

function M.busy() return M.job ~= nil and M.job.state == "running" end

--- versao que esta no cartao agora (difere da que esta rodando depois de instalar/restaurar)
function M.disk_version()
  local r = M.restart_needed
  if r and r.to then return tostring(r.to), tostring(r.to_label or r.to) end
  return C.VERSION_NUM, C.VERSION
end

--- inicia uma operacao. args conforme a operacao. on_done(job) ao terminar
function M.start(op, args, on_done)
  if M.busy() then return false, L("Já existe uma operação de atualização em andamento.") end
  -- os arquivos do hub ja foram trocados: o app em execucao nao consegue mais
  -- ler o proprio pacote (threads e modulos novos). So depois de reiniciar.
  if M.restart_needed then return false, L("Atualização instalada: reinicie o app antes de continuar.") end
  if op ~= "probe" and op ~= "download" and not M.layout_ok() then
    return false, L("A pasta do R36S PORT HUB não está na estrutura esperada (ports/r36sporthub). Atualização bloqueada por segurança.")
  end
  local tools = M.tools()
  local function plain(t) return t and { kind = t.kind, bin = t.bin, name = t.name } or nil end
  local job = {
    op = op, lang = require("lib.i18n").lang, out_channel = OUT, in_channel = IN,
    app_dir = C.APP_DIR, ports_dir = C.PORTS_DIR, tmp_dir = C.TMP_DIR, fetch_sh = C.FETCH_SH,
    current_version = (M.disk_version()), current_label = select(2, M.disk_version()),
    tools = { zip = plain(tools.zip), ["7z"] = plain(tools["7z"]), rar = plain(tools.rar) },
  }
  for k, v in pairs(args or {}) do job[k] = v end
  love.thread.getChannel(OUT):clear()
  love.thread.getChannel(IN):clear()
  M.out_ch, M.in_ch = love.thread.getChannel(OUT), love.thread.getChannel(IN)
  M.job = { op = op, from_version = job.current_version, state = "running", phase = nil, done = 0, total = nil, args = args or {}, on_done = on_done,
    t0 = love.timer.getTime(), speed = 0 }
  M.thread = love.thread.newThread("threads/updater_thread.lua")
  M.thread:start(job)
  return true
end

function M.cancel()
  if M.busy() and M.job.op == "download" and M.in_ch then M.in_ch:push("cancel") end
end

-- ---------------------------------------------------------------------------
-- Textos
M.PHASE = {
  verify = L("Verificando o pacote"), integrity = L("Validando a integridade"), extract = L("Extraindo os arquivos"),
  hash = L("Conferindo o SHA-256 de cada arquivo"), backup = L("Preparando o backup"),
  install = L("Instalando a atualização"), restore = L("Restaurando o backup"), finalize = L("Finalizando"),
  download = L("Baixando o pacote"),
}

local MSG = {
  format = L("O arquivo não é um ZIP, 7Z ou RAR válido."),
  no_tool = L("Este console não tem uma ferramenta para abrir este formato."),
  list = L("Não foi possível ler o conteúdo do pacote (arquivo danificado ou incompleto)."),
  too_many = L("O pacote tem arquivos demais."),
  structure = L("Estrutura desconhecida: o pacote não tem update_manifest.json nem a pasta r36sporthub com o game.love."),
  invalid = L("O pacote não passou na validação. Nada foi alterado."),
  integrity = L("O arquivo compactado está danificado (falhou no teste de integridade). Nada foi alterado."),
  space = L("Espaço livre insuficiente no cartão SD para extrair o pacote e guardar o backup."),
  extract = L("Falha ao extrair o pacote. Nada foi alterado."),
  link = L("O pacote contém links ou arquivos especiais, que não são permitidos. Nada foi alterado."),
  extract_mismatch = L("O conteúdo extraído não confere com a lista do pacote. Nada foi alterado."),
  hash = L("Um arquivo do pacote não confere com o SHA-256 do manifesto: "),
  backup = L("Não foi possível criar o backup. Nada foi alterado."),
  install_restored = L("Falha ao instalar um arquivo. A versão anterior foi restaurada: "),
  install_restore_failed = L("Falha ao instalar e ao restaurar automaticamente. Abra Gerenciar backups e restaure o último backup."),
  backup_missing = L("O backup está incompleto ou não existe mais."),
  path = L("Caminho não permitido: "),
  dest_link = L("O destino é um link: "),
  dest_dir = L("O destino é uma pasta: "),
  dest_outside = L("O destino fica fora da pasta do hub: "),
  download = L("Falha no download (código "),
  download_size = L("Download incompleto. Tente de novo."),
  download_hash = L("O arquivo baixado não confere com o SHA-256 informado pela fonte."),
  download_save = L("Não foi possível salvar o pacote na pasta update."),
  empty_download = L("O arquivo baixado veio vazio."),
  internal = L("Erro interno na atualização."),
}

function M.message(code, detail)
  local m = MSG[code] or (L("Erro: ") .. tostring(code))
  if code == "no_tool" and detail then m = m .. " (" .. (Formats.LABEL[detail] or detail) .. ")" end
  if (code == "hash" or code == "path" or code == "dest_link" or code == "dest_dir" or code == "dest_outside"
      or code == "install_restored") and detail then m = m .. tostring(detail) end
  if code == "download" and detail then m = m .. tostring(detail) .. ")." end
  return m
end

M.PROBLEM = {
  structure = L("estrutura desconhecida"), outside = L("item fora da pasta do pacote"), link = L("link (não permitido)"),
  path = L("caminho não permitido"), protected = L("dados do usuário (protegido)"), too_big = L("pacote grande demais"),
  empty = L("nenhum arquivo para instalar"), manifest = L("manifesto inválido"), not_in_manifest = L("arquivo fora do manifesto"),
  missing = L("arquivo do manifesto ausente"), size = L("tamanho diferente do manifesto"),
  too_old = L("versão instalada antiga demais para este pacote"), too_new = L("versão instalada nova demais para este pacote"),
  dest_link = L("destino é um link"), dest_dir = L("destino é uma pasta"), dest_outside = L("destino fora da pasta do hub"),
}

function M.problem_text(p)
  return (M.PROBLEM[p.code] or p.code) .. (p.path and (": " .. tostring(p.path)) or "")
end

-- ---------------------------------------------------------------------------
local function finish(state)
  local j = M.job
  j.state = state
  local a = j.args
  if j.op == "install" or j.op == "restore" or j.op == "recover" then
    local origin = a.origin or (j.op == "restore" and "backup" or "recuperacao")
    if state == "done" then
      local res = j.result
      History.add({ from = j.from_version, to = res.to, origin = origin, package = a.package, result = "ok", backup = res.backup,
        description = res.description, changes = res.changes, fixes = res.fixes })
      M.restart_needed = res
      -- notas da versao: aparecem na primeira abertura da versao nova
      if j.op == "install" and M.has_notes(res) then
        pcall(love.filesystem.write, NOTES_FILE, require("lib.json").encode({ to = res.to, to_label = res.to_label,
          description = res.description, changes = res.changes, fixes = res.fixes }))
      end
    elseif state == "error" then
      History.add({ from = j.from_version, to = a.version, origin = origin, package = a.package,
        result = (j.error_code == "install_restored") and "restaurado" or "erro", error = M.message(j.error_code, j.detail) })
    end
  end
  if j.on_done then pcall(j.on_done, j) end
end

function M.update()
  if not M.busy() then return end
  local e = M.thread:getError()
  if e then
    U.log("Atualizações: erro na thread:", e)
    M.job.error_code, M.job.detail = "internal", tostring(e)
    finish("error")
    return
  end
  local j = M.job
  local m = M.out_ch:pop()
  while m do
    if m.t == "phase" then j.phase = m.phase; j.done, j.total = 0, m.total
    elseif m.t == "progress" then
      local now = love.timer.getTime()
      if j.op == "download" and j.last_t and now > j.last_t then
        local inst = (m.done - (j.last_done or 0)) / (now - j.last_t)
        j.speed = j.speed > 0 and (j.speed * 0.7 + inst * 0.3) or inst
      end
      j.last_t, j.last_done = now, m.done
      j.done = m.done
      if m.total and m.total > 0 then j.total = m.total end
    elseif m.t == "done" then
      j.result = m
      U.log("Atualizações:", j.op, "concluída")
      finish("done")
      return
    elseif m.t == "error" then
      j.error_code, j.detail, j.report = m.code, m.detail, m.report
      U.log("Atualizações:", j.op, "falhou:", tostring(m.code), tostring(m.detail))
      finish("error")
      return
    elseif m.t == "cancelled" then
      finish("cancelled")
      return
    end
    m = M.out_ch:pop()
  end
end

-- ---------------------------------------------------------------------------
-- Abertura do app: confirma a versao nova ou conclui uma recuperacao
--- devolve texto para avisar o usuario (ou nil)
function M.on_boot()
  local notice
  -- o lancador restaurou a versao anterior (o app nao abriu depois da atualizacao)
  local rec = C.APP_DIR .. "/backups/.last_recovery"
  local txt = U.read_file(rec)
  if txt then
    local r = {}
    for k, v in txt:gmatch("([%w_]+)=([^\n]*)") do r[k] = v end
    History.add({ from = r.to, to = r.from, origin = "recuperacao", package = r.package, result = "restaurado",
      error = L("O app não abriu depois da atualização; a versão anterior foi restaurada automaticamente.") })
    os.remove(rec)
    notice = { L("A atualização anterior não abriu corretamente e foi desfeita automaticamente. A versão anterior está de volta."), "warn" }
  end
  local j = Backup.journal_read(C.APP_DIR)
  if j then
    if j.state == "booting" or j.state == "pending" then
      -- a versao nova abriu: confirma
      Backup.journal_clear(C.APP_DIR)
      U.log("Atualizações: versão", C.VERSION_NUM, "confirmada na abertura")
      if j.state == "booting" then notice = notice or { L("Atualização concluída: R36S PORT HUB ") .. C.VERSION .. ".", "ok" } end
      -- novidades da versao que acabou de abrir (mostradas depois do aviso inicial)
      local okr, txt = pcall(love.filesystem.read, NOTES_FILE)
      local n = okr and txt and require("lib.json").decode(txt) or nil
      if type(n) == "table" and tostring(n.to) == C.VERSION_NUM and M.has_notes(n) then M.boot_notes = n end
      -- sem o arquivo de notas (ex.: instalada por uma versao anterior do hub):
      -- le as notas direto do manifesto do pacote que ficou na pasta update
      if not M.boot_notes and j.package and j.origin ~= "backup" and not j.package:find("/", 1, true) then
        pcall(function()
          local path = Folder.DIR .. "/" .. j.package
          local fmt = Formats.detect_magic(path)
          local tool = fmt and M.tools()[fmt]
          if not tool then return end
          local m = require("core.updater.rules").parse_manifest(Formats.cat(tool, path, "update_manifest.json", 2 * 1024 * 1024))
          if m and m.version == C.VERSION_NUM and M.has_notes(m) then
            M.boot_notes = { to = m.version, to_label = m.version_label, description = m.description, changes = m.changes, fixes = m.fixes }
          end
        end)
      end
    elseif j.state == "applying" and Backup.valid_id(j.backup or "") then
      -- instalacao interrompida e o lancador nao restaurou: restaura agora
      local meta = Backup.read_meta(C.APP_DIR, j.backup)
      if meta then
        meta.state = "complete"
        Backup.write_meta(C.APP_DIR, j.backup, meta)
        Backup.journal_clear(C.APP_DIR)
        M.start("restore", { backup = j.backup, origin = "recuperacao", package = j.package })
        notice = { L("Uma atualização foi interrompida. Restaurando a versão anterior..."), "warn" }
      end
    end
    if j.state == "applying" and Backup.journal_read(C.APP_DIR) then
      -- diario sem backup valido: nada a restaurar
      U.log("Atualizações: diário sem backup válido; descartado")
      Backup.journal_clear(C.APP_DIR)
    end
  end
  -- as notas aparecem uma vez so (ou ja nao valem para esta versao)
  pcall(love.filesystem.remove, NOTES_FILE)
  Folder.ensure_dir()
  return notice
end

return M
