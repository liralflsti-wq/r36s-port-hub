-- =============================================================================
--  Analisador de Console: compara o que foi lido do aparelho com a base de
--  assinaturas conhecidas (data/console_signatures.json).
--
--  A base vem dos arquivos de hardware (DTB) publicados por projetos que
--  mantem firmware para essas placas (dArkOSRE-R36, ArkOS4Clone, R36S-DTB):
--  nome da placa (model), compatible, assinatura do painel (sha1 da
--  panel-init-sequence) e resolucao. Cada entrada guarda a fonte e o commit.
--
--  Regras:
--   * Nome de firmware e o texto "R36S" NAO provam nada.
--   * A identificacao da placa vem da Device Tree que o sistema carregou
--     (escolhida na instalacao). Um DTB escolhido errado leva a um resultado
--     errado: por isso o resultado e sempre "estimado".
--   * Diferencas (RAM, resolucao, painel) indicam variante/revisao, nunca clone.
--   * Autenticidade NUNCA e confirmada: nao ha fonte que permita isso.
-- =============================================================================
local L = require("lib.i18n").L
local json = require("lib.json")
local U = require("lib.util")
local C = require("config")

local M = {}
local LAST = "console_analysis.json"

-- classes de resultado
M.CLASSES = {
  compatible = { label = L("Compatível com assinaturas conhecidas do R36S"), color = "green",
    text = L("As informações encontradas são compatíveis com uma ou mais configurações conhecidas do R36S.") },
  variant = { label = L("Possível variante ou revisão modificada"), color = "yellow",
    text = L("Foram encontradas diferenças em relação às assinaturas de referência do R36S.") },
  clone = { label = L("Possível clone ou réplica"), color = "orange",
    text = L("As características encontradas correspondem a placas catalogadas como clone do R36S, mas não há evidência suficiente para uma conclusão definitiva.") },
  other = { label = L("Outro modelo identificado"), color = "accent2",
    text = L("As informações coletadas apontam para outro modelo de console.") },
  unknown = { label = L("Modelo não identificado"), color = "dim",
    text = L("Não existem informações suficientes para identificar o aparelho.") },
}
M.CONF = { alta = L("Alta"), media = L("Média"), baixa = L("Baixa"), insuficiente = L("Insuficiente para identificação") }

function M.load_db()
  if M.db then return M.db end
  local ok, s = pcall(love.filesystem.read, "data/console_signatures.json")
  local d = ok and s and json.decode(s) or nil
  M.db = type(d) == "table" and d or { boards = {}, panels = {}, reference = {} }
  return M.db
end

local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

--- faixa de RAM da referencia (1 GB = ~ 900 a 1100 MB visiveis no Linux)
local function ram_ok(mem_kb, ref_mb)
  if not mem_kb or not ref_mb then return nil end
  local mb = mem_kb / 1024
  return mb > ref_mb * 0.80 and mb <= ref_mb * 1.10
end

--- Compara e classifica. Devolve o resultado (tabela simples, salva em JSON).
function M.classify(info)
  local db = M.load_db()
  local ref = db.reference or {}
  local r = { time = info.time or os.time(), diffs = {}, evidence = {}, notes = {} }
  local res = info.drm_res or info.dt_res

  -- 1) placa: nome exato da Device Tree (ou "Hardware" do /proc/cpuinfo no dArkOSRE)
  local cands = {}
  for _, b in ipairs(db.boards or {}) do
    local m = b.match or {}
    local name_ok = m.model and (m.model == info.model or m.model == info.hardware)
    local comp_ok = not m.compatible or has(info.compatible, m.compatible)
    if name_ok and comp_ok then cands[#cands + 1] = b end
  end
  local board
  if #cands > 0 then
    board = cands[1]
    for _, b in ipairs(cands) do
      if info.panel_sha1 and b.panel_sha1 == info.panel_sha1 then board = b; break end
    end
  end

  -- 2) painel: em quais placas catalogadas esta mesma assinatura aparece
  local pkinds, plabels = {}, {}
  local plist = info.panel_sha1 and db.panels and db.panels[info.panel_sha1]
  if plist then
    for _, p in ipairs(plist) do
      pkinds[p.kind] = true
      if p.kind == "r36s" and not plabels[p.label] then plabels[p.label] = true; plabels[#plabels + 1] = p.label end
    end
  end
  r.panel_known = plist ~= nil

  -- 3) diferencas em relacao a referencia do R36S (so faz sentido para R36S)
  local function check_ref()
    if info.soc and ref.soc and info.soc ~= ref.soc then
      r.diffs[#r.diffs + 1] = string.format(L("Processador (SoC) %s; a referência do R36S é %s."), info.soc:upper(), ref.soc:upper())
    end
    if info.cores and ref.cores and info.cores ~= ref.cores then
      r.diffs[#r.diffs + 1] = string.format(L("%d núcleos de CPU; a referência do R36S tem %d."), info.cores, ref.cores)
    end
    local rk = ram_ok(info.mem_kb, ref.ram_mb)
    if rk == false then
      r.diffs[#r.diffs + 1] = string.format(L("Memória RAM de cerca de %d MB; a referência do R36S tem 1 GB."), math.floor(info.mem_kb / 1024 + 0.5))
    end
    if res and ref.resolution and res ~= ref.resolution then
      r.diffs[#r.diffs + 1] = string.format(L("Resolução da tela %s; a referência do R36S é %s."), res, ref.resolution)
    end
    if info.emmc and ref.emmc == false then
      r.diffs[#r.diffs + 1] = L("Memória interna (eMMC) presente; o R36S de referência não tem eMMC.")
    end
    if board and board.panel_sha1 and info.panel_sha1 and board.panel_sha1 ~= info.panel_sha1 then
      r.diffs[#r.diffs + 1] = L("Assinatura do painel diferente da cadastrada para esta placa.")
    end
  end

  -- quantos dados basicos foram lidos (qualidade da coleta)
  local got = 0
  for _, v in ipairs({ info.soc, info.cores, info.mem_kb, res, info.panel_sha1, info.model }) do if v then got = got + 1 end end
  r.data_quality = got

  if not info.dt and not info.cores then
    r.class, r.conf = "unknown", "insuficiente"
  elseif info.soc and ref.soc and info.soc ~= ref.soc then
    -- outro SoC: com certeza nao e um R36S de referencia
    r.class = "other"
    r.model = board and board.name or info.model or (L("Aparelho com ") .. info.soc:upper())
    r.conf = (board or info.model) and "alta" or "media"
    r.evidence[#r.evidence + 1] = string.format(L("Processador %s (o R36S usa %s)."), info.soc:upper(), ref.soc:upper())
  elseif board then
    r.board, r.source = board.board, board.source
    r.evidence[#r.evidence + 1] = L("Placa encontrada na base: ") .. board.board .. " (" .. (board.source and board.source.name or "?") .. ")."
    if info.panel_sha1 and board.panel_sha1 == info.panel_sha1 then
      r.evidence[#r.evidence + 1] = L("Assinatura do painel igual à cadastrada para esta placa.")
    end
    if board.kind == "r36s" then
      check_ref()
      r.model = "R36S"
      if #r.diffs == 0 then
        r.class = "compatible"
        r.conf = (got >= 5 and (not board.panel_sha1 or board.panel_sha1 == info.panel_sha1)) and "alta" or "media"
      else
        r.class, r.conf = "variant", "media"
      end
    elseif board.kind == "variant" then
      check_ref()
      r.class, r.model, r.conf = "variant", board.name, got >= 5 and "alta" or "media"
      r.notes[#r.notes + 1] = L("Placa Soy Sauce (Y3506): família vendida como R36S, com placa diferente da de referência.")
    elseif board.kind == "clone" then
      check_ref()
      r.class, r.model, r.conf = "clone", board.name, "media"
    else
      r.class, r.model = "other", board.name
      r.conf = (board.resolution == nil or board.resolution == res) and "alta" or "media"
    end
  elseif info.soc == ref.soc and plist then
    -- sem placa catalogada: decide pelo painel, com confianca baixa
    check_ref()
    if pkinds.r36s and #r.diffs == 0 then
      r.class, r.model, r.conf = "compatible", "R36S", (not pkinds.clone and not pkinds.other and not pkinds.variant) and "media" or "baixa"
      r.evidence[#r.evidence + 1] = L("Painel com assinatura de R36S: ") .. table.concat(plabels, ", ") .. "."
      if pkinds.clone or pkinds.other or pkinds.variant then
        r.notes[#r.notes + 1] = L("Essa assinatura de painel também aparece em outros aparelhos ou clones.")
      end
    elseif pkinds.r36s then
      r.class, r.model, r.conf = "variant", "R36S", "baixa"
      r.evidence[#r.evidence + 1] = L("Painel com assinatura de R36S: ") .. table.concat(plabels, ", ") .. "."
    elseif pkinds.variant and not pkinds.clone and not pkinds.other then
      r.class, r.model, r.conf = "variant", L("R36S Soy Sauce (Y3506)"), "baixa"
    elseif pkinds.clone and not pkinds.other then
      r.class, r.model, r.conf = "clone", L("Clone de R36S"), "baixa"
    else
      r.class, r.conf = "unknown", "insuficiente"
      r.notes[#r.notes + 1] = L("O painel aparece em vários aparelhos diferentes; não dá para saber qual é este.")
    end
  elseif info.soc == ref.soc then
    check_ref()
    r.class, r.conf = "unknown", "insuficiente"
    if res == ref.resolution and ram_ok(info.mem_kb, ref.ram_mb) then
      r.notes[#r.notes + 1] = L("O hardware lido é da mesma família do R36S (RK3326, 640x480), mas a placa e o painel não estão na base.")
    end
  else
    r.class, r.conf = "unknown", "insuficiente"
  end
  r.firmware_note = L("O nome do firmware não foi usado para decidir o resultado, nem o texto \"R36S\" no nome do aparelho.")
  return r
end

-- ---------------------------------------------------------------------------
-- ultimo resultado (so o necessario para mostrar de novo e exportar)
function M.save_last(info, res)
  pcall(love.filesystem.write, LAST, json.encode({ info = info, result = res }))
end

function M.load_last()
  local ok, s = pcall(love.filesystem.read, LAST)
  local d = ok and s and json.decode(s) or nil
  if type(d) == "table" and type(d.info) == "table" and type(d.result) == "table" then return d end
end

-- ---------------------------------------------------------------------------
-- relatorio TXT (no idioma atual)
local function NA() return L("Não foi possível identificar este componente.") end

--- linhas "rotulo: valor" das informacoes coletadas, por secao
function M.sections(info)
  local function v(x) return x or NA() end
  local res = info.drm_res or info.dt_res
  local s = {}
  s[#s + 1] = { title = L("IDENTIFICAÇÃO DO SISTEMA"), rows = {
    { L("Nome do dispositivo (Device Tree)"), v(info.model) },
    { L("Identificador da placa (/proc/cpuinfo)"), v(info.hardware) },
    { L("Distribuição Linux"), v(info.os) },
    { L("Firmware"), v(info.firmware) },
    { L("Kernel"), v(info.kernel) },
    { L("Arquitetura"), v(info.arch) },
  } }
  s[#s + 1] = { title = L("PROCESSADOR E HARDWARE"), rows = {
    { L("SoC"), info.soc and info.soc:upper() or NA() },
    { L("Processador"), v(info.cpu) },
    { L("Núcleos"), info.cores and tostring(info.cores) or NA() },
    { L("Memória RAM"), info.mem_kb and U.format_bytes(info.mem_kb * 1024) or NA() },
    { L("GPU"), v(info.gpu) },
  } }
  s[#s + 1] = { title = L("PLACA E COMPONENTES"), rows = {
    { L("Compatible (Device Tree)"), (info.compatible and #info.compatible > 0) and table.concat(info.compatible, ", ") or NA() },
    { L("Painel de tela"), (info.panel_compat and #info.panel_compat > 0) and table.concat(info.panel_compat, ", ") or NA() },
    { L("Assinatura do painel"), info.panel_sha1 and (info.panel_sha1:sub(1, 12) .. " (" .. info.panel_len .. " bytes)") or NA() },
    { L("Resolução da tela"), res and (res .. (info.connector and ("  (" .. info.connector .. ")") or "")) or NA() },
    { L("Bateria"), info.battery and (
      (info.battery.technology and (info.battery.technology .. "  ") or "")
      .. (info.battery.design_mah and (info.battery.design_mah .. " mAh  ") or "")
      .. (info.battery.voltage and string.format(L("%.2f V"), info.battery.voltage) or "")) or NA() },
  } }
  local disks = {}
  for _, d in ipairs(info.disks or {}) do
    disks[#disks + 1] = d.dev .. " (" .. (d.type == "MMC" and L("memória interna") or (d.type == "SD" and L("cartão SD") or (d.type or "?")))
      .. (d.bytes and (", " .. U.format_bytes(d.bytes)) or "") .. (d.name and (", " .. d.name) or "") .. ")"
  end
  s[#s + 1] = { title = L("ARMAZENAMENTO"), rows = {
    { L("Dispositivos"), #disks > 0 and table.concat(disks, "; ") or NA() },
    { L("Capacidade total"), info.sd and U.format_bytes(info.sd.total) or NA() },
    { L("Espaço utilizado"), info.sd and U.format_bytes(info.sd.used) or NA() },
    { L("Espaço livre"), info.sd and U.format_bytes(info.sd.free) or NA() },
  } }
  return s
end

function M.report_text(info, r)
  local cls = M.CLASSES[r.class] or M.CLASSES.unknown
  local t = {}
  t[#t + 1] = "R36S PORT HUB " .. C.VERSION .. " - " .. L("ANALISADOR DE CONSOLE")
  t[#t + 1] = L("Data da análise: ") .. os.date("%d/%m/%Y %H:%M:%S", r.time)
  t[#t + 1] = ""
  t[#t + 1] = L("Modelo estimado: ") .. (r.model or L("não identificado"))
  t[#t + 1] = L("Classificação: ") .. cls.label
  t[#t + 1] = L("Confiança: ") .. (M.CONF[r.conf] or r.conf)
  if r.board then t[#t + 1] = L("Placa: ") .. r.board end
  t[#t + 1] = ""
  t[#t + 1] = cls.text
  for _, e in ipairs(r.evidence or {}) do t[#t + 1] = "+ " .. e end
  for _, e in ipairs(r.notes or {}) do t[#t + 1] = "* " .. e end
  if #(r.diffs or {}) > 0 then
    t[#t + 1] = ""
    t[#t + 1] = L("DIFERENÇAS EM RELAÇÃO À REFERÊNCIA")
    for _, e in ipairs(r.diffs) do t[#t + 1] = "- " .. e end
  end
  for _, sec in ipairs(M.sections(info)) do
    t[#t + 1] = ""
    t[#t + 1] = sec.title
    for _, row in ipairs(sec.rows) do t[#t + 1] = "  " .. row[1] .. ": " .. row[2] end
  end
  t[#t + 1] = ""
  t[#t + 1] = L("Observação: a identificação é estimada a partir do que o sistema informa e não comprova a autenticidade nem o fabricante do aparelho.")
  t[#t + 1] = r.firmware_note or ""
  local db = M.load_db()
  t[#t + 1] = L("Base de assinaturas: ") .. #(db.boards or {}) .. L(" placas, gerada em ") .. tostring(db.generated or "?")
  for _, s in ipairs(db.sources or {}) do t[#t + 1] = "  - " .. s.name .. ": " .. s.url end
  return table.concat(t, "\n") .. "\n"
end

--- grava o relatorio TXT na pasta do app (acessivel pelo FTP e pelo gerenciador de arquivos)
function M.export(info, r)
  local dir = C.APP_DIR .. "/relatorios"
  os.execute("mkdir -p " .. U.shq(dir) .. " 2>/dev/null")
  local path = dir .. "/analise_console_" .. os.date("%Y%m%d_%H%M%S", r.time) .. ".txt"
  if U.write_file(path, M.report_text(info, r)) then return path end
  return nil
end

return M
