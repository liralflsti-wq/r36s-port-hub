-- =============================================================================
--  Conhecimento do assistente: respostas rapidas com DADOS REAIS do hub
--  Nada inventado: cada resposta le o catalogo, os ports instalados, os
--  downloads, o log de erros do dia, o cartao SD, a bateria, o Wi-Fi, o
--  historico de atualizacoes e o diario de atividades.
--    K.TOPICS                  perguntas do menu do assistente
--    K.answer(id) -> { title, lines = {..}, go = { label, fn } }
--    K.short_brief()           resumo curto para o cumprimento
--    K.explain(texto_do_erro)  explicacao + o que fazer (ou nil)
--  Para ligar uma IA no futuro: K.provider = function(id) -> resposta|nil
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local U = require("lib.util")

local K = {}
local tr = function(s) return I18N.tr(L(s)) end

K.TOPICS = {
  { id = "brief", q = L("Resumo do dia") },
  { id = "news", q = L("Tem port novo?") },
  { id = "errors", q = L("Deu algum erro?") },
  { id = "todo", q = L("O que falta fazer?") },
  { id = "today", q = L("O que eu fiz hoje?") },
  { id = "console", q = L("Como está meu console?") },
  { id = "changes", q = L("O que mudou na versão?") },
  { id = "tip", q = L("Me dá uma dica") },
}

K.provider = nil

-- ---------------------------------------------------------------- dados
local function catalog() local ok, C = pcall(require, "core.catalog"); return ok and C or nil end

--- ports novos: os que entraram desde a ultima visita + os marcados NOVO
function K.new_ports()
  local C = catalog()
  if not C or not C.ports then return {} end
  local Asst = require("core.assistant")
  local fresh = {}
  for _, id in ipairs(Asst.fresh or {}) do fresh[id] = true end
  local out = {}
  for _, p in ipairs(C.ports) do
    if not p.builtin and (fresh[p.id] or (C.is_new and C.is_new(p))) then out[#out + 1] = p end
  end
  return out
end

local function installed()
  local C = catalog()
  local okm, Man = pcall(require, "core.manifest")
  local inst, upd = {}, {}
  if not C or not okm then return inst, upd end
  for _, p in ipairs(C.ports or {}) do
    local ok, st = pcall(Man.status, p)
    if ok and st == "installed" then inst[#inst + 1] = p
    elseif ok and st == "update" then inst[#inst + 1] = p; upd[#upd + 1] = p end
  end
  return inst, upd
end

--- problemas registrados hoje (logs/problemas_AAAA-MM-DD.txt)
function K.errors_today()
  local out = {}
  local ok, dir = pcall(function() return require("core.errlog").dir() end)
  if not ok then return out end
  local f = io.open(dir .. "/problemas_" .. os.date("%Y-%m-%d") .. ".txt", "r")
  if not f then return out end
  local cur
  for line in f:lines() do
    local hh, title = line:match("^%[(%d%d:%d%d):%d%d%] (.+)$")
    if hh then
      title = title:gsub("%s+%(tela: [^)]*%)$", "")
      cur = { time = hh, title = title, body = "" }
      out[#out + 1] = cur
    elseif cur and line ~= "" and #cur.body < 300 then
      cur.body = cur.body .. " " .. line
    end
  end
  f:close()
  return out
end

local function downloads()
  local ok, D = pcall(require, "core.downloads")
  local waiting, failed, active = 0, {}, nil
  if not ok then return waiting, failed, active end
  for _, e in ipairs(D.list or {}) do
    if e.state == "waiting" then waiting = waiting + 1
    elseif e.state == "error" then failed[#failed + 1] = e
    elseif e.job then active = e end
  end
  return waiting, failed, active
end

local function battery()
  local ok, B = pcall(require, "core.battery")
  local info = ok and B.get and B.get() or nil
  return (type(info) == "table" and info.ok) and info or nil
end

local function wifi()
  local ok, N = pcall(require, "core.net")
  local st = ok and N.get and N.get(5) or nil
  return st
end

local function hub_update()
  local ok, N = pcall(require, "core.updnotice")
  if ok and N.pending() then return N.label or N.version end
  return nil
end

-- ---------------------------------------------------------------- erros
local RULES = {
  { { "conex", "internet", "rede", "dns", "timeout", "tempo esgotado", "rc=7", "resolve", "connection" },
    L("Parece problema de internet: confira o Wi-Fi em Configurações e tente de novo.") },
  { { "espaço", "no space", "cheio", "space left" },
    L("Falta espaço no cartão SD: apague ports que não usa ou rode a Manutenção do SD.") },
  { { "sha", "checksum", "corromp", "integridade", "crc" },
    L("O arquivo veio corrompido: baixe de novo. Se repetir, o servidor pode estar com problema.") },
  { { "senha", "password" },
    L("Esse arquivo pede senha: confira a senha do grupo e tente de novo.") },
  { { "permiss", "permission", "read-only", "somente leitura" },
    L("Sem permissão para gravar: o cartão pode estar com erro. Rode a Verificação do SD.") },
  { { "7z", "extra", "unzip", "descompact" },
    L("Falha ao descompactar: o arquivo pode ter vindo incompleto. Baixe de novo.") },
  { { "404", "não encontrado", "not found" },
    L("O arquivo não está mais nesse endereço: atualize o catálogo e tente de novo.") },
  { { "bateria", "battery" }, L("Coloque o console para carregar.") },
}

function K.explain(text)
  local s = tostring(text or ""):lower()
  for _, r in ipairs(RULES) do
    for _, k in ipairs(r[1]) do
      if s:find(k, 1, true) then return I18N.tr(r[2]) end
    end
  end
  return nil
end

-- ---------------------------------------------------------------- resumos
--- pendencias reais: lista de { texto, go = {label, fn} }
function K.todo()
  local out = {}
  local _, upd = installed()
  if #upd > 0 then
    local names = {}
    for i = 1, math.min(3, #upd) do names[i] = upd[i].name end
    out[#out + 1] = { string.format(tr("%d port(s) com atualização: %s."), #upd, table.concat(names, ", ")),
      go = { L("Meus Ports"), function() App.push("store", { mine = true }) end } }
  end
  local hv = hub_update()
  if hv then
    out[#out + 1] = { string.format(tr("Versão nova do hub disponível: %s."), hv),
      go = { L("Atualizações"), function() App.push("updmgr") end } }
  end
  local waiting, failed = downloads()
  if waiting > 0 then out[#out + 1] = { string.format(tr("%d download(s) na fila."), waiting),
    go = { L("Downloads"), function() App.push("downloads") end } } end
  for i = 1, math.min(2, #failed) do
    out[#out + 1] = { string.format(tr("O download de %s falhou."), failed[i].name or "?"),
      go = { L("Downloads"), function() App.push("downloads") end } }
  end
  local okp, PP = pcall(require, "core.pendports")
  if okp and PP.count and PP.count() > 0 then
    out[#out + 1] = { string.format(tr("%d arquivo(s) de port no cartão esperando instalação."), PP.count()),
      go = { L("Instalar"), function() App.push("pendports") end } }
  end
  if App and App.ports_changed then
    out[#out + 1] = { tr("Reinicie a lista do EmulationStation para ver os ports novos (menu Sair).") }
  end
  if App and App.free and App.free < 1024 ^ 3 then
    out[#out + 1] = { string.format(tr("Pouco espaço no cartão: %s livres."), U.format_bytes(App.free)),
      go = { L("Manutenção do SD"), function() App.push("sdmaint") end } }
  end
  local b = battery()
  if b and b.pct and b.pct <= 20 and not b.charging then
    out[#out + 1] = { string.format(tr("Bateria em %d%%: coloque para carregar."), b.pct) }
  end
  local w = wifi()
  if w and not w.connected then
    out[#out + 1] = { tr("Sem Wi-Fi: o catálogo e as atualizações não chegam."),
      go = { L("Wi-Fi"), function() App.push("wifi") end } }
  end
  local okA, Ach = pcall(require, "core.achievements")
  if okA and not Ach.user_name() then
    out[#out + 1] = { tr("Você ainda não disse seu nome. Defina em Meu perfil."),
      go = { L("Nome"), function() Ach.ask_name(false) end } }
  end
  return out
end

function K.short_brief()
  local parts = {}
  local n = #K.new_ports()
  if n > 0 then parts[#parts + 1] = string.format(tr("%d port(s) novo(s)"), n) end
  local _, upd = installed()
  if #upd > 0 then parts[#parts + 1] = string.format(tr("%d atualização(ões) de port"), #upd) end
  if hub_update() then parts[#parts + 1] = tr("versão nova do hub") end
  local e = #K.errors_today()
  if e > 0 then parts[#parts + 1] = string.format(tr("%d erro(s) hoje"), e) end
  if #parts == 0 then return tr("Tudo em dia por aqui.") end
  return tr("Tenho novidades: ") .. table.concat(parts, ", ") .. ". " .. tr("Aperte L2 para ver.")
end

-- ---------------------------------------------------------------- respostas
local A = {}

function A.brief()
  local Asst = require("core.assistant")
  local lines = { Asst.greeting() }
  local n = #K.new_ports()
  local inst, upd = installed()
  local e = K.errors_today()
  local todo = K.todo()
  lines[#lines + 1] = string.format(tr("Ports instalados pelo hub: %d. Novos no catálogo: %d."), #inst, n)
  lines[#lines + 1] = #upd > 0 and string.format(tr("Atualizações de port esperando: %d."), #upd) or tr("Seus ports estão atualizados.")
  lines[#lines + 1] = #e > 0 and string.format(tr("Erros hoje: %d (pergunte \"Deu algum erro?\")."), #e) or tr("Nenhum erro hoje.")
  lines[#lines + 1] = #todo > 0 and string.format(tr("Pendências: %d (pergunte \"O que falta fazer?\")."), #todo) or tr("Nenhuma pendência.")
  local J = require("core.assistant.journal")
  local today = J.today()
  if #today > 0 then lines[#lines + 1] = string.format(tr("Atividades registradas hoje: %d."), #today) end
  return { title = tr("Resumo do dia"), lines = lines }
end

function A.news()
  local list = K.new_ports()
  local C = catalog()
  if #list == 0 then
    return { title = tr("Ports novos"), lines = { string.format(tr("Nenhum port novo desde a sua última visita. O catálogo tem %d ports."), C and #(C.ports or {}) or 0) },
      go = { L("Central"), function() App.push("store") end } }
  end
  local lines = { string.format(tr("Encontrei %d port(s) novo(s):"), #list) }
  for i = 1, math.min(8, #list) do
    local p = list[i]
    lines[#lines + 1] = "• " .. p.name .. "  —  " .. (p.category or "?") .. ((p.size_label and p.size_label ~= "?") and (", " .. p.size_label) or "")
  end
  if #list > 8 then lines[#lines + 1] = string.format(tr("e mais %d."), #list - 8) end
  return { title = tr("Ports novos"), lines = lines, go = { L("Ver na Central"), function() App.push("store") end } }
end

function A.errors()
  local list = K.errors_today()
  local _, failed = downloads()
  if #list == 0 and #failed == 0 then
    return { title = tr("Erros"), lines = { tr("Nenhum erro hoje. Tudo funcionando!") } }
  end
  local lines = {}
  for i = #list, math.max(1, #list - 4), -1 do
    local e = list[i]
    lines[#lines + 1] = "• " .. e.time .. "  " .. e.title
    local tip = K.explain(e.title .. " " .. e.body)
    if tip then lines[#lines + 1] = "   " .. tip end
  end
  for i = 1, math.min(3, #failed) do
    lines[#lines + 1] = "• " .. string.format(tr("Download de %s: %s"), failed[i].name or "?", tostring(failed[i].error or "?"))
    local tip = K.explain(failed[i].error)
    if tip then lines[#lines + 1] = "   " .. tip end
  end
  return { title = string.format(tr("Erros de hoje: %d"), #list + #failed), lines = lines }
end

function A.todo()
  local list = K.todo()
  if #list == 0 then return { title = tr("O que falta fazer"), lines = { tr("Nada pendente. Tudo em dia!") } } end
  local lines, go = {}, nil
  for _, t in ipairs(list) do
    lines[#lines + 1] = "• " .. t[1]
    go = go or t.go
  end
  return { title = string.format(tr("Pendências: %d"), #list), lines = lines, go = go }
end

local KIND = {
  install = L("Instalou %s"), uninstall = L("Removeu %s"), cancel = L("Cancelou o download de %s"),
  error = L("Erro: %s"), achievement = L("Ganhou a carta %s"), update = L("Atualizou o hub para %s"),
  play = L("Jogou %s"), ftp = L("Transferência FTP: %s"), catalog = L("Catálogo trouxe %s port(s) novo(s)"),
}

function A.today()
  local J = require("core.assistant.journal")
  local list = J.today()
  if #list == 0 then return { title = tr("Hoje"), lines = { tr("Ainda não registrei nenhuma atividade hoje.") } } end
  local lines = {}
  for i = #list, math.max(1, #list - 9), -1 do
    local e = list[i]
    lines[#lines + 1] = os.date("%H:%M", e.t) .. "  " .. string.format(I18N.tr(KIND[e.k] or "%s"), e.x)
  end
  return { title = string.format(tr("Hoje: %d atividade(s)"), #list), lines = lines }
end

function A.console()
  local lines = {}
  local Cfg = require("config")
  lines[#lines + 1] = tr("Versão do hub: ") .. tostring(Cfg.VERSION)
  if App and App.free then
    lines[#lines + 1] = string.format(tr("Cartão SD: %s livres de %s."), U.format_bytes(App.free), App.total and U.format_bytes(App.total) or "?")
  end
  local b = battery()
  if b and b.pct then lines[#lines + 1] = string.format(tr("Bateria: %d%%%s."), b.pct, b.charging and I18N.tr(L(" (carregando)")) or "") end
  local w = wifi()
  if w then lines[#lines + 1] = w.connected and (tr("Wi-Fi: conectado") .. (w.ip and (" (" .. w.ip .. ")") or "") .. ".") or tr("Wi-Fi: desconectado.") end
  local inst = installed()
  lines[#lines + 1] = string.format(tr("Ports instalados pelo hub: %d."), #inst)
  local okL, Lib = pcall(require, "core.library")
  if okL and Lib.systems then lines[#lines + 1] = string.format(tr("Jogos de emulador na biblioteca: %d."), Lib.total_games()) end
  local okF, F = pcall(require, "core.favorites")
  if okF then lines[#lines + 1] = string.format(tr("Favoritos: %d."), F.count()) end
  local okA, Ach = pcall(require, "core.achievements")
  if okA then local a, t = Ach.count(); lines[#lines + 1] = string.format(tr("Cartas do álbum: %d de %d."), a, t) end
  return { title = tr("Seu console"), lines = lines }
end

function A.changes()
  local lines = {}
  local ok, txt = pcall(love.filesystem.read, "update_notes.json")
  local n = ok and txt and select(2, pcall(require("lib.json").decode, txt)) or nil
  local Cfg = require("config")
  if type(n) == "table" then
    lines[#lines + 1] = string.format(tr("Novidades da versão %s:"), tostring(n.to_label or n.to or Cfg.VERSION))
    for _, c in ipairs(type(n.changes) == "table" and n.changes or {}) do lines[#lines + 1] = "• " .. tostring(type(c) == "table" and (c.text or c[1]) or c) end
    for _, c in ipairs(type(n.fixes) == "table" and n.fixes or {}) do lines[#lines + 1] = "• " .. tr("Correção: ") .. tostring(type(c) == "table" and (c.text or c[1]) or c) end
    if #lines == 1 and n.description then lines[#lines + 1] = tostring(n.description) end
  end
  local okH, H = pcall(require, "core.updater.history")
  local last = okH and H.recent()[1] or nil
  if last then
    lines[#lines + 1] = string.format(tr("Última atualização: %s → %s em %s."), tostring(last.from or "?"), tostring(last.to or "?"), os.date("%d/%m/%Y", last.time or 0))
  end
  if #lines == 0 then lines[1] = string.format(tr("Você está na versão %s. Ainda não há notas de atualização neste console."), tostring(Cfg.VERSION)) end
  return { title = tr("O que mudou"), lines = lines, go = { L("Histórico"), function() App.push("upd_history") end } }
end

local TIPS = {
  L("START abre os downloads de qualquer tela."),
  L("SELECT marca um port como favorito."),
  L("L2 me chama de qualquer tela."),
  L("Segure B por 3 segundos para sair do teste de controles."),
  L("Faça backup das suas configurações de vez em quando."),
  L("Pelo FTP você manda arquivos do PC direto para o console."),
  L("Depois de instalar ports, reinicie a lista do EmulationStation no menu Sair."),
  L("No álbum, A abre a carta inteira."),
  L("Ports marcados como NOVO entraram no catálogo nos últimos dias."),
  L("Se um download falhar, ele fica em Downloads para tentar de novo."),
  L("A Manutenção do SD encontra arquivos que sobraram e libera espaço."),
  L("Você pode instalar ports de arquivos que já estão no cartão, sem baixar de novo."),
  L("O teste de controles mostra se algum botão ou analógico está com defeito."),
  L("Em Meu perfil você troca o seu nome e o meu também."),
  L("Com pouca bateria, evite instalar ports grandes: uma queda de energia pode corromper o arquivo."),
  L("Favoritos aparecem na Biblioteca para você achar rápido."),
  L("O hub avisa sozinho quando sai versão nova. É só aceitar a atualização."),
  L("Se o EmulationStation não mostrar um port novo, reinicie a lista pelo menu Sair."),
}

function A.tip()
  local lines = { I18N.tr(TIPS[math.random(#TIPS)]) }
  local C = catalog()
  if C and C.ports and #C.ports > 0 then
    local p = C.ports[math.random(#C.ports)]
    if p and not p.builtin then
      lines[#lines + 1] = string.format(tr("Sugestão de jogo: %s (%s)."), p.name, p.category or "?")
    end
  end
  return { title = tr("Dica"), lines = lines }
end

function K.answer(id)
  if K.provider then
    local ok, r = pcall(K.provider, id)
    if ok and type(r) == "table" then return r end
  end
  local fn = A[id] or A.brief
  local ok, r = pcall(fn)
  if ok and r then return r end
  return { title = tr("Ops"), lines = { tr("Não consegui ler essa informação agora.") } }
end

return K
