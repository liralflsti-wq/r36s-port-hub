-- =============================================================================
--  R36S PORT HUB (BETA)
--  Ports para o R36S - feito pela comunidade, para a comunidade.
--  Runtime: LOVE 11.5 (PortMaster)  |  Resolucao logica: 640x480
-- =============================================================================
-- idioma salvo: definido antes de carregar o resto (textos ja saem traduzidos)
local I18N = require("lib.i18n")
local Prefs = require("core.prefs")
local Clock = require("core.clock")
do
  local saved = Prefs.get("language")
  I18N.set(I18N.valid(saved) and saved or "pt-BR")   -- sem preferencia: portugues (seguranca)
end
local L = I18N.L
local C = require("config")
local U = require("lib.util")
local T = require("ui.theme")
local G = require("ui.gfx")
local Input = require("core.input")
local Catalog = require("core.catalog")
local Manifest = require("core.manifest")
local Covers = require("core.covers")
local Fetcher = require("core.fetcher")
local Installer = require("core.installer")
local Overlay = require("ui.overlay")
local Music = require("core.music")
local Sfx = require("core.sfx")
local Runtimes = require("core.runtimes")
local PM = require("core.pmmanager")
local Uninstall = require("core.uninstall")
local Downloads = require("core.downloads")
local Ftp = require("core.ftp")
local Stream = require("core.stream")
local Recorder = require("core.recorder")
local Cap = require("core.screencap")
local UpdMgr = require("core.updater.manager")
local Update = require("core.update")

local lg = love.graphics

local App = {
  t = 0,
  stack = {},
  screens = {},
  toast_msg = nil,
  dialog = nil,
  quitting = false,
  free = nil, total = nil,
}
_G.App = App

local SCREEN_NAMES = { "disclaimer", "menu", "store", "categories", "details", "about", "settings", "files", "sections", "search", "downloads", "news", "console", "ftp", "ftp_activity", "ftp_help", "textinput", "sdanalyzer", "integrity", "netdiag", "update", "themes", "sdcheck", "esthemes", "splash", "language", "settings_cat", "tester", "consoleid", "wifi", "wifi_connect", "r36control", "sdmaint", "sdmaint_run", "compat", "datetime", "tzpicker", "datetime_edit", "pmmanager", "streamrec", "recordings", "updmgr", "upd_local", "upd_pkg", "upd_history", "upd_backups", "upd_notes", "bios", "bios_list", "bios_pkg", "bios_hist", "folderpick", "battery", "infolist", "library", "library_games", "textview" }

---------------------------------------------------------------------------
-- Navegacao
---------------------------------------------------------------------------
function App.current() return App.stack[#App.stack] end

function App.push(name, params)
  local s = App.screens[name]
  local inst = setmetatable({ name = name }, { __index = s })
  App.stack[#App.stack + 1] = inst
  if inst.enter then inst:enter(params or {}) end
  Input.reset()
end

function App.pop()
  if #App.stack <= 1 then return end
  local s = table.remove(App.stack)
  if s.leave then s:leave() end
  local top = App.current()
  if top.resume then top:resume() end
  Input.reset()
end

function App.reset_to(name, params)
  for i = #App.stack, 1, -1 do
    local s = App.stack[i]
    if s.leave then s:leave() end
  end
  App.stack = {}
  App.push(name, params)
end

---------------------------------------------------------------------------
-- Mensagens
---------------------------------------------------------------------------
--- Notificacoes rapidas. Respeitam Configuracoes > Notificacoes:
---   notif (1/0) liga/desliga todas; notif_info = confirmacoes e informacoes;
---   notif_alert = alertas e erros. Dialogos de confirmacao sempre aparecem.
function App.notify_allowed(kind)
  if Prefs.get("notif") == "0" then return false end
  if kind == "warn" or kind == "error" then return Prefs.get("notif_alert") ~= "0" end
  return Prefs.get("notif_info") ~= "0"
end

function App.toast(msg, kind)
  kind = kind or "info"
  if not App.notify_allowed(kind) then return end
  App.toast_msg = { text = msg, kind = kind, t = 3.2 }
  Sfx.notify(kind)
end

--- Animacoes decorativas (pulsos, troca automatica do destaque).
--- Desligadas pelo usuario ou pelo modo economico.
function App.animations() return App.anim and not App.eco end
--- valor de um pulso: fixo (base) quando as animacoes estao desligadas
function App.pulse(base, amp, speed)
  if not App.animations() then return base end
  return base + amp * math.sin(App.t * speed)
end
App.anim = Prefs.get("anim") ~= "0"
App.eco = Prefs.get("eco") == "1"

--- Dialogo modal: { title=, body=, kind="info|ok|error|warn", buttons={ {label=, fn=}, ... }, sel= }
function App.show_dialog(d)
  -- falha mostrada ao usuario: tambem vai para o registro do dia (logs/)
  if d.kind == "error" then
    pcall(function()
      require("core.errlog").problem(I18N.tr(d.title or ""), I18N.tr(d.body or ""))
    end)
  end
  d.sel = d.sel or 1
  d.buttons = d.buttons or { { label = "OK" } }
  App.dialog = d
  Input.reset()
end

function App.close_dialog()
  App.dialog = nil
end

---------------------------------------------------------------------------
-- Catalogo
---------------------------------------------------------------------------
local function catalog_snapshot()
  local snap = {}
  for _, p in ipairs(Catalog.ports) do
    snap[p.id] = table.concat({ p.name, p.version, p.description, p.category_id, p.download_url, p.cover,
      tostring(p.size) }, "\1")
  end
  return snap
end

--- Atualiza o catalogo. on_done(ok, mensagem) e opcional (usado pelas Configuracoes).
--- Os ports instalados sao preservados: o registro de instalados nao e tocado.
function App.refresh_catalog(user_initiated, on_done)
  if user_initiated then Manifest.rescan(true) end
  local url = Catalog.get_remote_url()
  Catalog.remote_url = url
  if not url then
    -- brilho salvo pelo usuario (Configuracoes > Brilho da tela)
  pcall(require("core.brightness").restore)

  Catalog.load_local()
    Manifest.invalidate()
    local msg = L("Nenhum endereço de catálogo online configurado.\nUsando: ") .. Catalog.source_label()
      .. L(".\n\nPara configurar, grave a URL do catalog.json em:\n") .. C.APP_DIR .. "/catalog_url.txt"
    if on_done then on_done(false, msg)
    elseif user_initiated then App.toast(L("Nenhum catálogo online configurado. Usando: ") .. Catalog.source_label(), "warn") end
    App.on_catalog_changed()
    return
  end
  if Catalog.remote_state == "loading" and on_done then
    on_done(false, L("O catálogo já está sendo atualizado. Aguarde."))
    return
  end
  local before = catalog_snapshot()
  local before_updated = Catalog.updated
  Catalog.remote_state = "loading"
  local out = love.filesystem.getSaveDirectory() .. "/catalog_download.json"
  Fetcher.get("catalog", url, out, function(ok, path, reason)
    local okp, err = Catalog.on_remote(ok, path or out, reason)
    if okp then
      Prefs.set("cat_last", tostring(os.time()))
      Manifest.invalidate()
      Covers.retry_failed()
      local after = catalog_snapshot()
      local added, changed, removed = 0, 0, 0
      for id, sig in pairs(after) do
        if not before[id] then added = added + 1 elseif before[id] ~= sig then changed = changed + 1 end
      end
      for id in pairs(before) do if not after[id] then removed = removed + 1 end end
      if user_initiated then
        -- capas podem ter sido trocadas no servidor com o mesmo endereco: baixa de novo
        Covers.clear_disk()
      end
      local msg
      if added + changed + removed == 0 and before_updated == Catalog.updated and next(before) then
        msg = string.format(L("O catálogo já está atualizado.\n%d ports disponíveis."), #Catalog.ports)
      else
        msg = string.format(L("Catálogo atualizado com sucesso!\n%d ports disponíveis  •  %d novos  •  %d alterados  •  %d removidos"),
          #Catalog.ports, added, changed, removed)
        if Catalog.updated ~= "" then msg = msg .. L("\nVersão do catálogo: ") .. Catalog.updated end
      end
      msg = msg .. L("\n\nSeus ports instalados foram preservados.")
      if on_done then on_done(true, msg)
      elseif user_initiated then App.toast(string.format(L("Catálogo atualizado: %d ports"), #Catalog.ports), "ok") end
    else
      U.log("catalogo online falhou:", reason or "", err or "")
      -- falha sem o usuario pedir (ex.: Wi-Fi ainda conectando na abertura):
      -- tenta de novo sozinho quando a rede estiver conectada
      if not user_initiated and not on_done then App.cat_retry = App.cat_retry or { tries = 0, t = 0 } end
      pcall(function() require("core.netlog").add(L("Catálogo de ports"), url, err or reason) end)
      if on_done then
        on_done(false, err .. L("\nContinuando com: ") .. Catalog.source_label() .. ".")
      elseif user_initiated or Catalog.source == "none" or Catalog.source == "example" then
        App.toast(err .. L(" Usando: ") .. Catalog.source_label(), "warn")
      end
    end
    App.on_catalog_changed()
  end, true)
end

--- nova tentativa do catalogo online depois de uma falha na abertura:
--- a cada 20 s, so com a rede conectada, ate 3 vezes (silenciosa)
function App.catalog_retry_update(dt)
  local r = App.cat_retry
  if not r then return end
  if Catalog.source == "online" or Prefs.get("cat_auto") == "0" then App.cat_retry = nil; return end
  if Catalog.remote_state == "loading" then return end
  r.t = r.t + dt
  if r.t < 20 then return end
  r.t = 0
  local st = require("core.net").current()
  if not (st and st.connected) then return end
  if r.tries >= 3 then App.cat_retry = nil; return end
  r.tries = r.tries + 1
  U.log("catalogo: nova tentativa online (" .. r.tries .. "/3)")
  App.refresh_catalog(false)
end

function App.on_catalog_changed()
  for _, s in ipairs(App.stack) do
    if s.on_catalog then s:on_catalog() end
  end
end

function App.update_free_space()
  App.free, App.total = U.free_space(C.PORTS_DIR)
end

function App.status(p) return Manifest.status(p) end

---------------------------------------------------------------------------
-- Instalacao
---------------------------------------------------------------------------
-- downloads so comecam quando nada mais estiver usando o cartao
local function can_start_download()
  return not Runtimes.busy() and not Uninstall.busy() and not Update.busy() and not PM.busy()
end

--- Pedido de download/instalacao: passa pela Central de Downloads (fila).
--- Se nada estiver em andamento, comeca na hora (com a janela de progresso).
function App.install(p, opts)
  local ok, msg = Downloads.enqueue(p, opts)
  if not ok then App.toast(msg, "warn"); return end
  local idle = not Installer.busy() and can_start_download()
  if idle then Downloads.background = false end
  local e = Downloads.pump(can_start_download)
  if e and e.pid == p.id and e.state == "error" then
    App.show_dialog({ title = L("Não foi possível baixar"), body = e.error or "", kind = "error" })
    return
  end
  if not (Installer.job and Installer.job.download_entry and Installer.job.download_entry.pid == p.id) then
    App.toast(p.name .. L(" adicionado à Central de Downloads (aguardando)."), "info")
  end
end

function App.update_runtimes()
  if Installer.busy() or Runtimes.busy() or PM.busy() then App.toast(L("Aguarde a operação atual terminar."), "warn"); return end
  local ok, err = Runtimes.start()
  if not ok then App.show_dialog({ title = L("Runtimes"), body = err, kind = "error" }) end
end

--- Meus Ports > X: mostra exatamente o que sera apagado e pede confirmacao
function App.ask_uninstall(p)
  if Installer.busy() or Runtimes.busy() or Uninstall.busy() or PM.busy() then
    App.toast(L("Aguarde a operação atual terminar."), "warn"); return
  end
  local plan, why, info = Uninstall.plan(p)
  if not plan then
    if info and info.nothing then
      -- .sh e pasta nao existem mais: so limpa o registro, se o usuario quiser
      App.show_dialog({ title = L("Desinstalar port"), kind = "warn",
        body = why .. "\n\n" .. L("Deseja tirar este jogo da lista de Meus Ports? Nenhum arquivo será apagado."),
        buttons = {
          { label = L("LIMPAR REGISTRO"), fn = function()
            Uninstall.clear_record(p)
            App.on_catalog_changed()
            App.toast(L("Registro removido da lista. Nenhum arquivo foi apagado."), "ok")
          end },
          { label = L("CANCELAR") },
        }, sel = 2 })
    else
      App.show_dialog({ title = L("Desinstalação não realizada"), kind = "error", body = why })
    end
    return
  end
  App.confirm_uninstall(plan)
end

--- janela de confirmacao (tambem usada depois de escolher a pasta a mao)
function App.confirm_uninstall(plan)
  local p = plan.port
  local lines = {}
  local shown = 0
  for _, n in ipairs(plan.targets) do
    shown = shown + 1
    if shown > 6 then lines[#lines + 1] = string.format(L("… e mais %d itens"), #plan.targets - 6); break end
    local sz = plan.sizes[n] and ("  (" .. U.format_bytes(plan.sizes[n]) .. ")") or ""
    local kind
    if n:lower():match("%.sh$") and not plan.is_dir(n) then kind = L("Arquivo de inicialização: ")
    elseif plan.is_dir(n) then kind = L("Pasta do jogo: ")
    else kind = L("Arquivo do jogo: ") end
    lines[#lines + 1] = "• " .. kind .. "\"" .. n .. (plan.is_dir(n) and "/" or "") .. "\"" .. sz
  end
  local body = L("Você está prestes a remover:") .. "\n" .. table.concat(lines, "\n")
  if plan.manual_dir then
    body = body .. "\n" .. L("Pasta escolhida: ") .. plan.base .. "/" .. plan.manual_dir
  elseif plan.missing_dir then
    body = body .. "\n" .. (plan.expected_dir
      and (L("A pasta do jogo (\"") .. plan.expected_dir .. L("/\") não foi localizada: só o arquivo .sh será removido."))
      or L("A pasta do jogo não foi localizada: só o arquivo .sh será removido.")) .. "\n" .. L("Y: localizar a pasta manualmente.")
  end
  if #plan.evidence > 0 then body = body .. "\n" .. L("Identificado por: ") .. table.concat(plan.evidence, ", ") end
  body = body .. "\n\n" .. L("Essa operação removerá os arquivos selecionados do cartão SD (saves dentro da pasta do jogo também). Não pode ser desfeita.")
    .. "\n\n" .. L("Deseja continuar?")
  local buttons = {
    { label = L("CONFIRMAR"), danger = true, fn = function() Uninstall.start(plan) end },
    { label = L("CANCELAR") },
  }
  if plan.missing_dir then
    table.insert(buttons, 2, { label = L("Y: LOCALIZAR PASTA"), key = "y", fn = function() App.pick_port_folder(plan) end })
  end
  App.show_dialog({ title = L("DESINSTALAR PORT"), kind = "error", body = body, buttons = buttons, sel = 1,
    cancel = function() App.toast(L("Desinstalação cancelada. Nada foi apagado."), "info") end })
end

--- escolher a pasta do jogo no navegador de pastas
function App.pick_port_folder(plan)
  App.push("folderpick", {
    title = L("Localizar pasta do jogo"),
    start = plan.base, root = plan.base:match("^(.*)/[^/]+$") or plan.base,
    info = plan.scripts[1],
    on_cancel = function() App.toast(L("Desinstalação cancelada. Nada foi apagado."), "info") end,
    on_pick = function(abs)
      local name, why = Uninstall.check_folder(plan, abs)
      if not name then
        App.show_dialog({ title = L("Pasta não aceita"), kind = "error", body = why .. "\n\n" .. L("Nada foi apagado.") })
        return false
      end
      App.show_dialog({ title = L("Usar esta pasta?"), kind = "warn",
        body = L("Pasta escolhida:") .. "\n" .. plan.base .. "/" .. name .. "\n\n"
          .. L("Ela será apagada junto com o arquivo ") .. "\"" .. plan.scripts[1] .. "\".",
        buttons = {
          { label = L("SIM, USAR"), fn = function()
            Uninstall.add_folder(plan, name)
            App.pop()
            App.confirm_uninstall(plan)
          end },
          { label = L("ESCOLHER OUTRA") },
        }, sel = 1 })
      return true
    end,
  })
end

function App.request_es_restart()
  if C.OS_MODE then
    -- R36 Hub OS: a lista de jogos e o proprio hub (nada para reiniciar)
    App.toast(L("No R36 Hub OS os ports instalados já aparecem em Meus Ports."), "info")
    return
  end
  -- o launcher verifica este arquivo depois que o app fecha
  os.execute("mkdir -p " .. U.shq(C.APP_DIR .. "/conf") .. " 2>/dev/null")
  U.write_file(C.APP_DIR .. "/conf/.restart_es", "1")
  App.quit()
end

--- desligar/reiniciar o console: o app fecha normalmente (com as mesmas
--- verificacoes de "Sair") e o launcher executa o pedido depois.
function App.power_request(kind)
  if kind ~= "poweroff" and kind ~= "reboot" then return end
  App.power_pending = kind
  App.quit()
end

function App.quit(force)
  local pending = App.power_pending
  App.power_pending = nil
  -- operacao do PortMaster: nao sai no meio (gravacao com backup) nem a interrompe sem aviso
  if PM.busy() then
    App.toast(L("Aguarde a operação do PortMaster terminar (ou cancele-a em Gerenciar PortMaster)."), "warn")
    return
  end
  -- atualizacao do sistema em andamento: nao deixa sair no meio da troca de arquivos
  if Update.busy() then
    App.toast(L("Aguarde a atualização do sistema terminar."), "warn")
    return
  end
  local ESth = package.loaded["core.esthemes"]
  if ESth and ESth.job and not ESth.job.finished then
    App.toast(L("Aguarde a instalação do tema terminar."), "warn")
    return
  end
  -- downloads/instalacoes ativos ou na fila: o app nao consegue continuar depois de fechado
  if not force and (Installer.busy() or Downloads.waiting_count() > 0) then
    local a = Downloads.active()
    local w = Downloads.waiting_count()
    App.show_dialog({
      title = L("Downloads em andamento"), kind = "warn",
      body = (a and (a.name .. L(" ainda está em andamento.")) or L("Há operações em andamento."))
        .. (w > 0 and ("\n" .. w .. L(" item(ns) aguardando na fila.")) or "")
        .. L("\n\nOs downloads só continuam com o R36S PORT HUB aberto. Se sair agora, a operação atual é interrompida (os arquivos temporários são apagados e nada fica pela metade) e a fila é descartada."),
      buttons = { { label = L("SAIR MESMO ASSIM"), fn = function() App.power_pending = pending; App.quit("downloads") end }, { label = L("VOLTAR") } },
      sel = 2,
    })
    return
  end
  -- servidor FTP ativo: pergunta antes de sair (e para o servidor)
  if force ~= true and Ftp.running() then
    local n = Ftp.active_count()
    App.show_dialog({
      title = L("Servidor FTP ativo"), kind = "warn",
      body = L("O servidor FTP está ligado") .. (Ftp.clients > 0 and (L(" com ") .. Ftp.clients .. L(" cliente(s) conectado(s)")) or "") .. "."
        .. (n > 0 and ("\n" .. n .. L(" transferência(s) em andamento serão interrompidas.")) or "")
        .. L("\n\nParar o servidor e sair?"),
      buttons = { { label = L("PARAR E SAIR"), fn = function() Ftp.stop_wait(); App.power_pending = pending; App.quit(true) end }, { label = L("VOLTAR") } },
      sel = 2,
    })
    return
  end
  if pending then
    os.execute("mkdir -p " .. U.shq(C.APP_DIR .. "/conf") .. " 2>/dev/null")
    if not U.write_file(C.APP_DIR .. "/conf/.power", pending .. "\n") then
      App.toast(L("Não foi possível pedir o desligamento (pasta do app somente leitura?)."), "error")
      return
    end
  end
  App.quitting = true
  love.event.quit()
end

--- Abre a Central de Downloads (START ou menu principal). Uma so tela.
function App.open_downloads(from_start)
  local cur = App.current()
  if not cur or cur.name == "disclaimer" or cur.name == "splash" or (cur.name == "language" and cur.first) then return end      -- abertura/idioma/aviso vem primeiro
  -- janelas que pedem uma resposta (dialogos, confirmacoes, exclusao, runtimes)
  if App.dialog or Uninstall.job or Runtimes.job then
    if from_start then App.toast(L("Responda a mensagem na tela antes de abrir os downloads."), "info") end
    return
  end
  local j = Installer.job
  if j and not j.background then
    if j.finished or j.confirm or j.ask_cancel then return end
    -- a janela de progresso vai para segundo plano: o download continua
    j.background = true
    Downloads.background = true
  end
  if cur.name == "downloads" then return end                  -- ja aberta: nao duplica
  -- se a central ja estiver na pilha (embaixo), volta ate ela em vez de abrir outra
  for i = #App.stack - 1, 1, -1 do
    if App.stack[i].name == "downloads" then
      while App.current().name ~= "downloads" do App.pop() end
      return
    end
  end
  App.push("downloads")
end

--- pedidos de confirmacao do servidor FTP (excluir/renomear pastas importantes)
local function ftp_confirm_dialog()
  if App.dialog or #Ftp.confirms == 0 then return end
  local c = Ftp.confirms[1]
  local body = L("Um computador/celular da rede (") .. tostring(c.peer) .. L(") quer ") .. c.op .. ":\n" .. c.path
  if c.tree then body = body .. L("\n\nEssa pasta é importante para o sistema (") .. c.tree .. L("). Se permitir, outras alterações nela ficam liberadas por 10 minutos para esse cliente.") end
  App.show_dialog({
    title = L("Confirmar operação FTP"), kind = "warn", body = body, sel = 2, ftp_confirm = c.id,
    buttons = { { label = L("PERMITIR"), fn = function() Ftp.answer_confirm(c.id, true) end },
      { label = L("NEGAR"), fn = function() Ftp.answer_confirm(c.id, false) end } },
    cancel = function() Ftp.answer_confirm(c.id, false) end,
  })
end

---------------------------------------------------------------------------
-- Entrada
---------------------------------------------------------------------------
--- Print da tela (botao FN): salva PNG em <cartao>/print (ex.: /roms/print)
local function take_screenshot()
  local base = C.PORTS_DIR:match("^(.*)/[^/]+$") or C.PORTS_DIR
  local dir = (os.getenv("PORTHUB_PRINT_DIR") or (base .. "/print"))
  App.capturing = true   -- o aviso rapido nao entra no print
  love.graphics.captureScreenshot(function(img)
    App.capturing = false
    os.execute("mkdir -p " .. U.shq(dir) .. " 2>/dev/null")
    local name = "print_" .. os.date("%Y%m%d_%H%M%S")
    local path = dir .. "/" .. name .. ".png"
    local n = 1
    while U.exists(path) do n = n + 1; path = dir .. "/" .. name .. "_" .. n .. ".png" end
    local okp, fd = pcall(function() return img:encode("png") end)
    local f = okp and fd and io.open(path, "wb")
    if f then
      local okw = f:write(fd:getString())
      f:close()
      if okw then
        App.toast(L("Print salvo: ") .. path, "ok")
        U.log("print salvo:", path)
        return
      end
      os.remove(path)
    end
    App.toast(L("Não foi possível salvar o print em ") .. dir .. L(" (cartão cheio ou somente leitura?)."), "error")
  end)
end

local function on_action(act)
  -- FN: print da tela em qualquer situacao (nao interfere em nada)
  if act == "shot" then
    take_screenshot()
    return
  end
  Sfx.on_action(act)
  -- START: abre a Central de Downloads em Segundo Plano (unica funcao).
  -- Nao cancela, nao reinicia e nao interrompe nada; nunca duplica a central.
  if act == "start" then
    -- telas com uso proprio do START (ex.: Sobre o Projeto = apoio via Pix)
    local cur = App.current()
    if cur and cur.on_start and not App.dialog and not (Installer.job and not Installer.job.background)
        and not Runtimes.job and not Uninstall.job then
      cur:on_start()
      return
    end
    App.open_downloads(true)
    return
  end
  if App.dialog then
    Overlay.dialog_action(App, act)
    return
  end
  if Installer.job and not Installer.job.background then
    Overlay.install_action(App, act)
    return
  end
  if Runtimes.job then
    Overlay.runtimes_action(App, act)
    return
  end
  if Uninstall.job then return end -- exclusao em andamento: sem entrada
  local s = App.current()
  if s and s.action then s:action(act) end
end

---------------------------------------------------------------------------
-- LOVE
---------------------------------------------------------------------------
function love.load(args)
  love.mouse.setVisible(false)
  lg.setDefaultFilter("linear", "linear")
  T.load()
  G.build_background()
  local theme_warn = require("core.themes").init()   -- ultimo tema escolhido (ou o padrao)
  for _, n in ipairs(SCREEN_NAMES) do App.screens[n] = require("ui.screens." .. n) end
  Input.handler = on_action

  -- canvas logico 640x480 se a tela tiver outro tamanho (ex.: testes no PC)
  local w, h = lg.getDimensions()
  if w ~= T.W or h ~= T.H then
    App.canvas = lg.newCanvas(T.W, T.H)
    App.canvas:setFilter("linear", "linear")
  end

  -- etapas reais da inicializacao (a tela de abertura mostra o andamento)
  local steps = {
    { L("Carregando configurações..."), function() Covers.init(); Music.init(); Sfx.load() end },
    { L("Lendo ports instalados..."), function() Manifest.load(); Downloads.load(); Manifest.rescan() end },
    { L("Preparando ferramentas..."), function()
      Ftp.load()
      require("core.net").start_watch(4)   -- estado do Wi-Fi (rodape do menu) sem travar a tela
      Ftp.on_notify = function(text, kind) App.toast(text, kind) end
      Stream.on_notify = function(text, kind) App.toast(text, kind) end
      Recorder.on_notify = function(text, kind) App.toast(text, kind) end
      os.execute("mkdir -p " .. U.shq(C.TMP_DIR) .. " 2>/dev/null")
      -- restos de instalacoes interrompidas (ex.: console desligado no meio)
      os.execute("rm -rf " .. U.shq(C.TMP_DIR) .. "/job_* " .. U.shq(C.TMP_DIR) .. "/runtimes_job 2>/dev/null")
      pcall(Runtimes.recover)
      -- Gerenciador do PortMaster: conclui (e confere) uma operacao interrompida
      pcall(PM.recover)
      -- BIOS: instalacao interrompida (console desligou no meio) e desfeita
      local okb, bmsg = pcall(require("core.bios").recover)
      if okb and bmsg then App.bios_boot_notice = bmsg elseif not okb then U.log("BIOS: falha na recuperação:", tostring(bmsg)) end
      -- Verificador de compatibilidade: identifica o console uma vez (sem internet)
      pcall(function() require("core.compat").detect() end)
      -- versao anterior do hub: remove o servico de LED que ela pode ter criado
      pcall(function() require("core.r36ctl").cleanup_old_led_service() end)
      -- capa/logo do hub na lista de Ports do EmulationStation (so a entrada do hub)
      local okg, what, gerr = pcall(require("core.esgamelist").ensure)
      if okg and what then
        App.boot_gamelist = what
        U.log("gamelist.xml: entrada do hub", what)
      elseif okg and gerr then U.log("gamelist.xml:", gerr)
      elseif not okg then U.log("gamelist.xml: erro", tostring(what)) end
    end },
    { L("Carregando catálogo..."), function()
      U.log("R36S PORT HUB", C.VERSION, "| ports:", C.PORTS_DIR, "| app:", C.APP_DIR)
      U.log("dados:", love.filesystem.getSaveDirectory())
      Catalog.load_local()
      -- Configuracoes > Catalogo > Atualizar ao abrir o hub (ligado por padrao)
      if Prefs.get("cat_auto") ~= "0" then App.refresh_catalog(false)
      else U.log("catalogo: atualizacao automatica desligada; usando", Catalog.source_label()) end
    end },
    { L("Verificando espaço livre..."), function() App.update_free_space() end },
  }
  App.push("splash", { steps = steps, on_done = function()
    App.after_boot()
    -- avisos da abertura: so depois do aviso importante (nao cobrem o botao dele)
    App.boot_toasts = {}
    -- aviso de versao nova no alto da tela inicial (consulta leve em segundo plano)
    pcall(function() require("core.updnotice").start() end)
    -- atualizacao: confirma a versao nova (o app abriu) ou conclui uma recuperacao
    local okn, notice = pcall(UpdMgr.on_boot)
    if okn and notice then App.boot_toasts[#App.boot_toasts + 1] = notice
    elseif not okn then U.log("Atualizações: falha na verificação de abertura:", tostring(notice)) end
    if theme_warn then App.boot_toasts[#App.boot_toasts + 1] = { theme_warn, "warn" } end
    if PM.boot_notice == "ok" then
      App.boot_toasts[#App.boot_toasts + 1] = { L("PortMaster: a operação interrompida foi desfeita e conferida (veja o histórico)."), "info" }
    elseif PM.boot_notice then
      App.boot_toasts[#App.boot_toasts + 1] = { L("PortMaster: uma operação foi interrompida. Abra Gerenciar PortMaster > Verificar instalação."), "warn" }
    end
    if App.bios_boot_notice then App.boot_toasts[#App.boot_toasts + 1] = { App.bios_boot_notice, "warn" } end
    local cur = App.current()
    if cur and cur.name ~= "disclaimer" and cur.name ~= "language" then App.flush_boot_toasts() end
  end })

  if os.getenv("PORTHUB_INSTALLTEST") then
    App.itest = require("dev.installtest")
    App.itest.start(os.getenv("PORTHUB_INSTALLTEST"))
  end
  if os.getenv("PORTHUB_AUTOTEST") then
    App.autotest = require("dev.autotest")
    App.autotest.start(App, os.getenv("PORTHUB_AUTOTEST"))
  end
end

---------------------------------------------------------------------------
-- Inicializacao: abertura -> idioma (1o acesso) -> aviso (ate confirmar) -> menu
---------------------------------------------------------------------------
--- Ferramentas externas (rodam com o app fechado; o launcher reabre o app depois)
App.TOOLS = { analog_tester = "tools/R36S_Analog_Tester.sh" }

function App.tool_path(id) return App.TOOLS[id] and (C.APP_DIR .. "/" .. App.TOOLS[id]) end

--- Fecha o hub, abre a ferramenta e volta para `from` ("settings" ou "store") ao sair dela
function App.launch_tool(id, from)
  local path = App.tool_path(id)
  if not path or not U.exists(path) then
    App.show_dialog({ title = L("Ferramenta não encontrada"), kind = "error",
      body = L("Os arquivos do teste não estão na pasta do app:\n") .. tostring(path) .. L("\n\nReinstale o R36S PORT HUB para recuperá-los.") })
    return
  end
  local ESth = package.loaded["core.esthemes"]
  if Installer.busy() or Downloads.waiting_count() > 0 or Runtimes.job or Update.busy() or PM.busy()
      or (ESth and ESth.job and not ESth.job.finished) then
    App.show_dialog({ title = L("Aguarde"), kind = "warn",
      body = L("Termine ou cancele os downloads e instalações em andamento antes de abrir o teste. O R36S PORT HUB fecha enquanto o teste estiver aberto.") })
    return
  end
  local function go()
    os.execute("mkdir -p " .. U.shq(C.APP_DIR .. "/conf") .. " 2>/dev/null")
    if not U.write_file(C.APP_DIR .. "/conf/.run_tool", id .. "|" .. (from or "settings") .. "\n") then
      App.toast(L("Não foi possível abrir o teste (pasta do app somente leitura?)."), "error")
      return
    end
    App.quit(true)
  end
  if Ftp.running() then
    App.show_dialog({ title = L("Servidor FTP ativo"), kind = "warn",
      body = L("O servidor FTP será parado para abrir o teste."),
      buttons = { { label = L("PARAR E ABRIR"), fn = function() Ftp.stop_wait(); go() end }, { label = "VOLTAR" } }, sel = 2 })
    return
  end
  go()
end

--- script .sh do port instalado (na raiz da pasta de ports), ou nil
function App.port_script(p)
  if not p or p.builtin or App.status(p) == "none" then return nil end
  for _, n in ipairs(Manifest.found(p) or {}) do
    n = tostring(n)
    if not n:find("/") and not n:find("%.%.") and n:lower():match("%.sh$") and U.exists(C.PORTS_DIR .. "/" .. n) then
      return n
    end
  end
  return nil
end

--- ha algo que impede o hub de fechar para abrir um jogo? (mostra o aviso)
local function blocked_for_game()
  local ESth = package.loaded["core.esthemes"]
  if Installer.busy() or Downloads.waiting_count() > 0 or Runtimes.job or Update.busy() or PM.busy()
      or (ESth and ESth.job and not ESth.job.finished) then
    App.show_dialog({ title = L("Aguarde"), kind = "warn",
      body = L("Termine ou cancele os downloads e instalações em andamento antes de iniciar um jogo. O R36S PORT HUB fecha enquanto o jogo estiver aberto.") })
    return true
  end
  return false
end

--- Biblioteca: abre um jogo de emulador com o comando do es_systems.cfg
function App.launch_game(sys, game)
  if blocked_for_game() then return end
  local function go()
    local ok, err = require("core.library").launch(sys, game)
    if not ok then App.toast(err, "error"); return end
    App.quit(true)
  end
  if Ftp.running() then
    App.show_dialog({ title = L("Servidor FTP ativo"), kind = "warn",
      body = L("O servidor FTP será parado para abrir o jogo."),
      buttons = { { label = L("PARAR E JOGAR"), fn = function() Ftp.stop_wait(); go() end }, { label = "VOLTAR" } }, sel = 2 })
    return
  end
  go()
end

--- Iniciar um port pelo hub: o hub fecha, o launcher roda o script do port
--- (com o ambiente original do sistema) e, ao sair do jogo, abre o hub de novo.
function App.launch_port(p)
  local script = App.port_script(p)
  if not script then
    App.toast(L("Não encontrei o script deste port na pasta de ports. Reinstale-o ou abra pela lista de Ports."), "warn")
    return
  end
  if blocked_for_game() then return end
  local function go()
    os.execute("mkdir -p " .. U.shq(C.APP_DIR .. "/conf") .. " 2>/dev/null")
    if not U.write_file(C.APP_DIR .. "/conf/.run_port", script .. "|" .. tostring(p.id) .. "\n") then
      App.toast(L("Não foi possível iniciar o jogo (pasta do app somente leitura?)."), "error")
      return
    end
    U.log("iniciar port:", p.id, script)
    App.quit(true)
  end
  local body = string.format(L("O R36S PORT HUB vai fechar e %s vai abrir.\nAo sair do jogo, o hub abre de novo.\n\nScript: %s"), p.name, script)
  if Ftp.running() then body = body .. L("\n\nO servidor FTP será parado.") end
  App.show_dialog({ title = L("Iniciar o jogo?"), kind = "info", body = body,
    buttons = { { label = L("INICIAR"), fn = function() if Ftp.running() then Ftp.stop_wait() end; go() end },
      { label = L("CANCELAR") } } })
end

--- volta para a tela de onde a ferramenta foi aberta (depois que o launcher reabre o app)
local function return_from_tool()
  local req = os.getenv("PORTHUB_RETURN")
  if not req or req == "" or App.returned then return false end
  App.returned = true
  local id, from = req:match("^([%w_]+)|?([%w_%-]*)")
  -- volta de um jogo iniciado pelo hub: abre a pagina do port
  -- volta de um jogo da biblioteca: abre a biblioteca no mesmo sistema
  if id == "game" then
    App.reset_to("menu")
    App.push("library", { system = from })
    return true
  end
  if id == "port" then
    App.reset_to("menu")
    local p = Catalog.by_id[from]
    if p then App.push("details", { port = p }) end
    return true
  end
  if id ~= "analog_tester" then return false end
  App.reset_to("menu")
  if from == "store" then
    App.push("store", { section = "tools", filter = "cat:testes_de_controles" })
  else
    App.push("settings", { cat = "controls" })
    App.push("settings_cat", { id = "controls" })
  end
  App.push("tester", { from = from ~= "" and from or "settings", returned = true })
  return true
end

function App.after_boot()
  if I18N.valid(Prefs.get("language")) and Prefs.get("disclaimer_ok") == "1" and return_from_tool() then return end
  -- o idioma so e escolhido no primeiro acesso; o aviso aparece toda vez que o app abre
  if not I18N.valid(Prefs.get("language")) then
    App.reset_to("language", { first = true })
  else
    App.reset_to("disclaimer")
  end
end

--- depois de escolher o idioma no primeiro acesso
function App.after_language()
  App.reset_to("disclaimer", { from_language = true })
end

--- o usuario confirmou a leitura do aviso
function App.disclaimer_accepted()
  Prefs.set("disclaimer_ok", "1")
  App.reset_to("menu")
  -- Configuracoes > Preferencias > Tela ao abrir
  pcall(function() require("ui.settings_extra").open_start_screen() end)
  App.flush_boot_toasts()
end

function App.flush_boot_toasts()
  local t = App.boot_toasts
  App.boot_toasts = nil
  for _, m in ipairs(t or {}) do App.toast(m[1], m[2]) end
  -- primeira abertura depois de uma atualizacao: o que mudou e o que foi corrigido
  local notes = UpdMgr.boot_notes
  if notes then
    UpdMgr.boot_notes = nil
    notes.first = true
    App.push("upd_notes", notes)
  end
end

--- troca de idioma na hora: salva, aplica e refaz os textos das telas abertas
--- Aplica, sem reiniciar, o que foi restaurado de um backup
--- (done = { prefs = true, favorites = true, ftp = true, history = true })
function App.apply_restored(done)
  if done.prefs then
    Prefs.load()
    local lang = Prefs.get("language")
    if I18N.valid(lang) and lang ~= I18N.lang then App.set_language(lang) end
    local Themes = require("core.themes")
    local okr, tid = pcall(love.filesystem.read, "theme.txt")
    tid = okr and tid and U.trim(tid) or nil
    -- backup/exportacao antiga com o id antigo do tema (ex.: xbox): aplica e grava o id novo
    if tid and Themes.ALIASES[tid] then tid = Themes.resolve(tid); pcall(love.filesystem.write, "theme.txt", tid) end
    if tid and tid ~= "" and tid ~= Themes.current then Themes.apply(tid, false) end
    Music.init()
    Music.set_enabled(Music.enabled)
    Sfx.load()
    App.anim = Prefs.get("anim") ~= "0"
    App.eco = Prefs.get("eco") == "1"
    local fl = Prefs.get("font_size")
    App.set_font_level(T.valid_font_level(fl) and fl or "normal")
    pcall(require("core.brightness").restore)
  end
  if done.favorites then require("core.favorites").load() end
  if done.catalog then
    Manifest.load()
    Catalog.load_local()
    Manifest.invalidate()
    App.on_catalog_changed()
  end
  if done.ftp then Ftp.cfg = nil; Ftp.load(); Ftp.save() end
  if done.history then
    -- troca so os registros finalizados; a restauracao e bloqueada com downloads ativos
    for i = #Downloads.list, 1, -1 do Downloads.list[i] = nil end
    Downloads.load()
    local okh, th = pcall(love.filesystem.read, "ftp_history.json")
    local h = okh and th and require("lib.json").decode(th) or nil
    Ftp.history = type(h) == "table" and h or {}
  end
end

--- Tamanho do texto (Configuracoes > Aparencia): troca as fontes na hora, salva
--- e refaz as medidas das telas abertas (as mesmas chamadas da troca de idioma)
function App.set_font_level(id)
  if not T.valid_font_level(id) then return end
  T.set_font_level(id)
  Prefs.set("font_size", id)
  for _, s in ipairs(App.stack) do
    if s.on_font then pcall(s.on_font, s)
    elseif s.on_language then pcall(s.on_language, s)
    elseif s.layout then pcall(s.layout, s) end
  end
end

function App.set_language(id)
  if not I18N.valid(id) then return end
  I18N.set(id)
  Prefs.set("language", id)
  -- nomes ja montados (categorias do catalogo, ferramentas integradas) passam
  -- para o novo idioma; nomes de jogos nao sao tocados
  local function reloc(list, fields)
    for _, it in ipairs(list or {}) do
      for _, f in ipairs(fields) do
        if type(it[f]) == "string" then it[f] = I18N.tr(it[f]) end
      end
    end
  end
  local Cats = require("core.categories")
  reloc(Catalog.ports, { "category" })
  reloc(Catalog.categories, { "name", "short" })
  reloc(Cats.SECTIONS, { "name", "short" })
  reloc(Cats.LIST, { "name" })
  reloc(Cats.TEST_TYPES, { "name", "short" })
  reloc(require("core.tools").LIST, { "name", "short", "category", "size_label" })
  for _, s in ipairs(App.stack) do
    if s.on_language then pcall(s.on_language, s)
    elseif s.layout then pcall(s.layout, s) end
  end
  if App.dialog then App.dialog.body = I18N.tr(App.dialog.body); App.dialog.title = I18N.tr(App.dialog.title) end
end

function love.update(dt)
  dt = math.min(dt, 0.1)
  App.t = App.t + dt
  Clock.tick()   -- diferenca para UTC do sistema (fuso/horario de verao), a cada 10 min
  Input.update(dt)
  Fetcher.update()
  local was_busy = Installer.job and not Installer.job.finished
  Installer.update()
  Downloads.update()
  if Installer.job and Installer.job.confirm and Installer.job.background then
    Installer.job.background = false   -- a confirmacao de sobrescrita sempre aparece
  end
  if was_busy and Installer.job and Installer.job.finished and not App.itest then
    Downloads.on_finished(Installer.job)
    Overlay.on_install_finished(App, Installer.job)
  end
  if not App.itest then
    local nxt = Downloads.pump(can_start_download)
    if nxt and nxt.state == "error" then App.toast(L("Falha: ") .. nxt.name .. L(" - veja a Central de Downloads."), "error") end
  end
  local rt_busy = Runtimes.job and not Runtimes.job.finished
  Runtimes.update()
  if rt_busy and Runtimes.job and Runtimes.job.finished and not App.itest then
    Overlay.on_runtimes_finished(App, Runtimes.job)
  end
  -- Gerenciador do PortMaster (confirmacoes aparecem em qualquer tela)
  -- BIOS do Sistema (download, analise, instalacao em segundo plano)
  require("core.bios").update()
  local pm_busy = PM.busy()
  PM.update()
  if PM.job and PM.job.confirm and not PM.job.confirm.shown and not App.dialog and not App.itest then
    PM.job.confirm.shown = true
    App.screens.pmmanager.confirm_dialog(App, PM.job.confirm)
  end
  if pm_busy and PM.job and PM.job.finished and not App.itest then
    local j = PM.job
    PM.clear()
    App.update_free_space()
    App.screens.pmmanager.on_finished(App, j)
  end
  local del_busy = Uninstall.job and not Uninstall.job.finished
  Uninstall.update()
  if del_busy and Uninstall.job and Uninstall.job.finished and not App.itest then
    local j = Uninstall.job
    Uninstall.clear()
    App.update_free_space()
    App.on_catalog_changed()     -- atualiza Meus Ports sem reiniciar a loja
    if j.ok then
      App.show_dialog({ title = L("Jogo desinstalado"), kind = "ok",
        body = j.plan.port.name .. L(" foi removido do console.\n\nReinicie o EmulationStation (Sair > Reiniciar lista) para ele sumir da lista de Ports.") })
    else
      App.show_dialog({ title = L("Desinstalação incompleta"), kind = "error",
        body = (j.error or L("Alguns itens não puderam ser apagados:")) .. "\n" .. table.concat(j.failed or {}, ", ") })
    end
  end
  Ftp.update()
  require("core.shjob").update()
  require("core.updnotice").update(dt)
  App.catalog_retry_update(dt)
  Stream.update()
  Recorder.update()
  Update.update()
  UpdMgr.update()
  -- confirmacao vencida (a thread nega sozinha em 60 s): fecha o dialogo
  if App.dialog and App.dialog.ftp_confirm then
    local alive = false
    for _, c in ipairs(Ftp.confirms) do if c.id == App.dialog.ftp_confirm then alive = true end end
    if alive then
      for _, c in ipairs(Ftp.confirms) do
        if c.id == App.dialog.ftp_confirm and not c.t0 then c.t0 = App.t end
        if c.id == App.dialog.ftp_confirm and App.t - c.t0 > 58 then Ftp.answer_confirm(c.id, false); App.close_dialog() end
      end
    else App.close_dialog() end
  end
  ftp_confirm_dialog()
  local s = App.current()
  if s and s.update then s:update(dt) end

  -- trilha: download durante a instalacao; tema principal no aviso/menu; navegacao no resto
  local busy = (Installer.job and not Installer.job.finished) or (Runtimes.job and not Runtimes.job.finished) or PM.busy()
  if busy then Music.play("download")
  elseif s and (s.name == "disclaimer" or s.name == "menu" or s.name == "splash" or s.name == "language") then Music.play("main")
  else Music.play("nav") end
  Music.update(dt)

  if App.toast_msg then
    App.toast_msg.t = App.toast_msg.t - dt
    if App.toast_msg.t <= 0 then App.toast_msg = nil end
  end
  if App.autotest then App.autotest.update(dt) end
  if App.itest then App.itest.update(dt) end
end

local function draw_scene()
  G.background()
  local s = App.current()
  if s and s.draw then
    -- telas (ou partes delas) com posicoes fixas pedem o texto no tamanho padrao
    local fixed = s.fixed_text
    if type(fixed) == "function" then fixed = fixed(s) end
    if fixed then T.with_base_fonts(s.draw, s) else s:draw() end
  end
  -- paineis de progresso (instalar, runtimes, desinstalar): posicoes fixas
  if Installer.job then T.with_base_fonts(Overlay.draw_install, App, Installer.job) end
  if Runtimes.job then T.with_base_fonts(Overlay.draw_runtimes, App, Runtimes.job) end
  if Uninstall.job then T.with_base_fonts(Overlay.draw_uninstall, App, Uninstall.job) end
  if App.dialog then Overlay.draw_dialog(App, App.dialog) end
  if App.toast_msg and not App.capturing then Overlay.draw_toast(App, App.toast_msg) end
end

--- indicadores de transmissao/gravacao: desenhados so na tela do console
--- (depois da captura), entao nao aparecem no video nem no navegador
local function draw_live_badges()
  local items = {}
  if Recorder.recording() or Recorder.state == "stopping" then
    local paused = Recorder.state == "paused"
    items[#items + 1] = { (paused and L("PAUSA") or "REC") .. " " .. require("core.recordings").format_dur(Recorder.dur),
      paused and T.c.yellow or T.c.red, not paused }
  end
  if Stream.state == "on" then
    items[#items + 1] = { L("AO VIVO") .. (Stream.viewers > 0 and (" " .. Stream.viewers) or ""), T.c.accent2, false }
  end
  if #items == 0 then return end
  local f = T.f.small
  local x = T.W - 8
  local by = T.H - 58      -- canto inferior direito, logo acima da barra de dicas
  for _, it in ipairs(items) do
    local tw = f:getWidth(it[1])
    local w = tw + 26
    x = x - w
    lg.setColor(0, 0, 0, 0.72)
    lg.rectangle("fill", x, by, w, 20, 6, 6)
    local c = it[2]
    local on = not it[3] or math.floor(App.t * 2) % 2 == 0
    lg.setColor(c[1], c[2], c[3], on and 1 or 0.35)
    lg.circle("fill", x + 10, by + 10, 4)
    lg.setColor(1, 1, 1, 1)
    lg.print(it[1], f, x + 18, by + math.floor((20 - f:getHeight()) / 2))
    x = x - 6
  end
end

function love.draw()
  -- canvas logico: no PC (tela de outro tamanho) ou enquanto a interface e capturada
  local cv = App.canvas or (Cap.active() and Cap.get_canvas()) or nil
  if cv then
    lg.setCanvas(cv)
    lg.clear(T.c.bg0)
    draw_scene()
    lg.setCanvas()
    Cap.after_draw(cv)
    local w, h = lg.getDimensions()
    local sc = math.min(w / T.W, h / T.H)
    local ox, oy = math.floor((w - T.W * sc) / 2), math.floor((h - T.H * sc) / 2)
    lg.clear(0, 0, 0, 1)
    lg.setColor(1, 1, 1, 1)
    lg.draw(cv, ox, oy, 0, sc, sc)
    lg.push()
    lg.translate(ox, oy)
    lg.scale(sc, sc)
    draw_live_badges()
    lg.pop()
  else
    draw_scene()
  end
  if App.autotest then App.autotest.after_draw() end
end

love.gamepadpressed = Input.gamepadpressed
love.gamepadreleased = Input.gamepadreleased
love.gamepadaxis = Input.gamepadaxis
love.keypressed = Input.keypressed
love.keyreleased = Input.keyreleased

function love.quit()
  if Ftp.running() then Ftp.stop_wait() end
  if Stream.running() then Stream.stop_wait() end
  if Recorder.running() then Recorder.stop_wait() end   -- o video e fechado e fica salvo
  require("core.net").stop_watch()
  Music.stop_all()
  Fetcher.stop()
  if Runtimes.busy() then Runtimes.cancel() end
  if PM.busy() and PM.can_cancel() then PM.cancel() end
  if Installer.busy() then
    -- interrompe o download em andamento; os temporarios sao limpos na proxima abertura
    Installer.cancel()
  end
  return false
end

-- no LOVE 11.5 a tela de erro padrao e love.errhand (love.errorhandler ainda nao
-- existe quando este arquivo carrega): sem o "or", a tela de erro nunca aparecia
-- e o hub so fechava
local default_errhand = love.errorhandler or love.errhand
function love.errorhandler(msg)
  local trace = debug.traceback()
  print("[porthub] ERRO FATAL: " .. tostring(msg) .. "\n" .. trace)
  io.stdout:flush()
  -- arquivo de erro em r36sporthub/logs/ (antes da tela de erro do LOVE)
  local saved
  pcall(function()
    local path = require("core.errlog").crash(L("erro fatal do aplicativo"), msg, trace)
    if path then print("[porthub] registro do erro salvo em " .. path); io.stdout:flush(); saved = path end
  end)
  -- a tela de erro do LOVE tambem diz onde o registro ficou salvo
  if saved then
    pcall(function()
      msg = tostring(msg) .. "\n\n" .. I18N.tr(L("O registro deste erro foi salvo em:")) .. "\n" .. saved
    end)
  end
  pcall(function() msg = tostring(msg) .. "\n\n" .. I18N.tr(L("Aperte START para fechar o R36S PORT HUB.")) end)
  if not default_errhand then return nil end   -- sem tela padrao: fecha (o registro ja foi salvo)
  local loop = default_errhand(msg)
  -- a tela padrao so fecha com o teclado (Esc): no R36S, START fecha
  -- (depois de 1 s, para um botao que ja estava apertado nao fechar na hora)
  local t0 = love.timer and love.timer.getTime() or 0
  return function()
    local r = loop()
    if r ~= nil then return r end
    local ok, pressed = pcall(function()
      if not (love.joystick and love.timer) or love.timer.getTime() - t0 < 1 then return false end
      for _, j in ipairs(love.joystick.getJoysticks()) do
        if j:isGamepad() and j:isGamepadDown("start") then return true end
        for b = 1, j:getButtonCount() do
          if j:isDown(b) and not j:isGamepad() then return true end
        end
      end
      return false
    end)
    if ok and pressed then return 1 end
  end
end

--- erro dentro de uma tarefa em segundo plano (thread): registra e segue
function love.threaderror(thread, err)
  print("[porthub] erro em tarefa de segundo plano: " .. tostring(err))
  io.stdout:flush()
  local saved
  pcall(function() saved = require("core.errlog").crash(L("erro em tarefa de segundo plano"), err, nil) end)
  -- o app continua; avisa que o erro foi registrado (no maximo um aviso a cada 10 s,
  -- para uma sequencia de falhas nao encher a tela de avisos)
  if saved then
    local now = love.timer.getTime()
    if not App.last_bg_error or now - App.last_bg_error > 10 then
      App.last_bg_error = now
      pcall(App.toast, L("Uma tarefa em segundo plano falhou. Detalhes em Configurações > Informações do console > Registro de erros."), "error")
    end
  end
end

-- Laco principal com limite de FPS (economia de CPU e bateria)
function love.run()
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
  if love.timer then love.timer.step() end
  return function()
    local start = love.timer.getTime()
    -- modo economico (Configuracoes > Bateria e energia): menos quadros por segundo
    local frame = 1 / (App.eco and C.ECO_FPS or C.MAX_FPS)
    love.event.pump()
    for name, a, b, c, d, e, f in love.event.poll() do
      if name == "quit" then
        if not love.quit or not love.quit() then return a or 0 end
      end
      love.handlers[name](a, b, c, d, e, f)
    end
    local dt = love.timer.step()
    love.update(dt)
    if lg.isActive() then
      lg.origin()
      lg.clear(T.c.bg0)
      love.draw()
      lg.present()
    end
    local spent = love.timer.getTime() - start
    if spent < frame then love.timer.sleep(frame - spent) end
  end
end
