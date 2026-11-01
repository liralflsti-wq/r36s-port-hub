-- =============================================================================
--  Atualizacao dos runtimes do PortMaster (lado da interface)
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")

local R = { job = nil, seq = 0 }

local ERRORS = {
  no_pm = L("PortMaster não encontrado no console.\nInstale o PortMaster antes de atualizar os runtimes."),
  no_write = L("Sem permissão para gravar em: %s"),
  missing_tool = L("Ferramenta do sistema ausente: %s"),
  no_internet = L("Sem conexão com a internet. Verifique o Wi-Fi e tente de novo."),
  index_missing = L("O índice de runtimes não foi encontrado no servidor."),
  bad_index = L("O índice de runtimes recebido é inválido."),
  no_space = L("Espaço insuficiente no cartão SD."),
  net_error = L("A conexão caiu durante o download. Tente de novo (o download continua de onde parou)."),
  size_mismatch = L("Download incompleto: o tamanho do pacote não confere."),
  not_zip = L("O arquivo baixado não é um ZIP válido."),
  bad_zip = L("O pacote de runtimes está corrompido."),
  unsafe_zip = L("O pacote contém caminhos inseguros e foi recusado."),
  dup_runtime = "O pacote contém runtimes duplicados (%s) e foi recusado.",
  nothing_in_zip = L("O pacote não contém os runtimes que precisam ser atualizados."),
  checksum = L("Arquivo corrompido no pacote (md5 não confere): %s"),
  install_failed = L("Falha ao instalar %s. O backup foi restaurado; os runtimes antigos continuam funcionando."),
  internal = L("Erro interno na atualização dos runtimes."),
}

function R.error_text(code, detail)
  local msg = ERRORS[code] and require("lib.i18n").tr(ERRORS[code]) or (L("Erro: ") .. tostring(code))
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

function R.busy() return R.job ~= nil and not R.job.finished end

--- URL do pacote: runtimes_url.txt (opcional) > config.lua
local function urls()
  local zip, index = C.RUNTIMES_ZIP_URL, C.RUNTIMES_INDEX_URL
  local s = U.read_file(C.APP_DIR .. "/runtimes_url.txt")
  if s then
    local l1, l2 = s:match("^%s*(%S+)"), s:match("^[^\n]*\n%s*(%S+)")
    if l1 and l1:match("^https?://") then
      zip = l1
      index = (l2 and l2:match("^https?://")) and l2 or l1:gsub("/[^/]+$", "/ports.json")
    end
  end
  return zip, index
end

function R.start()
  if R.busy() then return false, L("A atualização dos runtimes já está em andamento.") end
  R.seq = R.seq + 1
  local zip, index = urls()
  local j = {
    phase = "check", label = "", done = 0, total = nil, speed = 0, eta = nil, samples = {},
    finished = false, result = nil, confirm = nil,
    out = "hub_rt_out_" .. R.seq, inn = "hub_rt_in_" .. R.seq,
  }
  j.out_ch = love.thread.getChannel(j.out)
  j.in_ch = love.thread.getChannel(j.inn)
  j.out_ch:clear(); j.in_ch:clear()
  local dirs = {}
  for _, d in ipairs(C.PORTMASTER_DIRS) do if d and d ~= "" then dirs[#dirs + 1] = d end end
  j.thread = love.thread.newThread("threads/runtimes_thread.lua")
  j.thread:start({ lang = require("lib.i18n").lang,
    out_channel = j.out, in_channel = j.inn,
    zip_url = zip, index_url = index, zip_name = C.RUNTIMES_ZIP_NAME, arch = C.RUNTIMES_ARCH,
    auto_latest = C.RUNTIMES_AUTO_LATEST, api_url = C.RUNTIMES_API_URL or "",
    pm_dirs = dirs, tmp_dir = C.TMP_DIR, fetch_sh = C.FETCH_SH, margin = C.SPACE_MARGIN,
  })
  R.job = j
  U.log("atualizacao de runtimes iniciada:", zip)
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

function R.update()
  local j = R.job
  if not j or j.finished then return end
  local err = j.thread:getError()
  if err then
    U.log("thread de runtimes falhou:", err)
    j.finished, j.result, j.error = true, "error", R.error_text("internal")
    return
  end
  local m = j.out_ch:pop()
  while m do
    if m.t == "phase" then
      j.phase, j.done, j.label = m.phase, 0, m.label or ""
      j.total = m.total
      if m.phase == "download" then j.samples, j.speed, j.eta = {}, 0, nil end
    elseif m.t == "progress" then
      j.phase = m.phase or j.phase
      j.done, j.total = m.done or 0, m.total or j.total
      if m.label then j.label = m.label end
      if j.phase == "download" then speed(j, love.timer.getTime()) end
    elseif m.t == "info" then
      j.pm, j.libs = m.pm, m.libs
    elseif m.t == "confirm" then
      j.confirm = m
      j.asked = m
    elseif m.t == "done" then
      j.finished, j.result, j.summary = true, "done", m
    elseif m.t == "error" then
      j.finished, j.result, j.error_code = true, "error", m.code
      j.error = R.error_text(m.code, m.detail)
    elseif m.t == "cancelled" then
      j.finished, j.result = true, "cancelled"
    end
    m = j.out_ch:pop()
  end
end

function R.cancel()
  local j = R.job
  if not j or j.finished then return end
  j.cancelling = true
  j.in_ch:push({ t = "cancel" })
end

function R.answer(yes)
  local j = R.job
  if not j or not j.confirm then return end
  j.confirm = nil
  j.in_ch:push({ t = "answer", yes = yes and true or false })
end

function R.clear() if R.job and R.job.finished then R.job = nil end end

--- Pasta do PortMaster que sera usada (para mostrar nas Configuracoes)
function R.detect_pm()
  local best, score = nil, 0
  for _, d in ipairs(C.PORTMASTER_DIRS) do
    if d and d ~= "" and d ~= "/PortMaster" then
      local s = 0
      if U.exec_ok("test -f " .. U.shq(d .. "/control.txt")) then s = s + 2 end
      if U.exec_ok("test -d " .. U.shq(d .. "/libs")) then s = s + 1 end
      if s > score then best, score = d, s end
    end
  end
  return best
end

--- Na abertura: conclui com seguranca uma atualizacao interrompida (ex.: bateria)
--- Arquivo que ficou so no backup volta para libs; temporarios sao apagados.
function R.recover()
  local pm = R.detect_pm()
  if not pm then return end
  local libs = U.shq(pm .. "/libs")
  os.execute("cd " .. libs .. " 2>/dev/null && { rm -rf .porthub_staging; "
    .. "for b in .porthub_backup_*; do [ -d \"$b\" ] || continue; "
    .. "for f in \"$b\"/*; do [ -e \"$f\" ] || continue; n=$(basename \"$f\"); "
    .. "[ -e \"$n\" ] || mv -f \"$f\" \"$n\"; done; rm -rf \"$b\"; "
    .. "echo \"[runtimes] backup restaurado: $b\"; done; }")
end

return R
