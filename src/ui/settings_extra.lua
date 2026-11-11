-- =============================================================================
--  Central de Configuracoes (0.4.7): categorias novas e acoes de apoio.
--  Usado por ui/settings_defs.lua. Tudo reaproveita os modulos existentes
--  (catalogo, downloads, manifesto, FTP, atualizador, backup, registros);
--  aqui ficam so a organizacao das linhas e as verificacoes somente leitura.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local U = require("lib.util")
local C = require("config")
local Prefs = require("core.prefs")
local Clock = require("core.clock")

local X = {}

-- ---------------------------------------------------------------------------
-- Ajudantes
local function pref_on(k) return Prefs.get(k) ~= "0" end
X.pref_on = pref_on

--- linha de escolha (esquerda/direita ou A percorre as opcoes)
--- opts = { { id=, label= }, ... }; get() -> id; set(id)
local function choice(label, desc, opts, get, set, extra)
  local row = { kind = "value", label = label, desc = desc }
  row.value = function()
    local cur = get()
    for _, o in ipairs(opts) do if o.id == cur then return I18N.tr(o.label) end end
    return I18N.tr(opts[1].label)
  end
  row.nudge = function(dir, wrap)
    local cur, idx = get(), 1
    for i, o in ipairs(opts) do if o.id == cur then idx = i end end
    local nxt = idx + dir
    if wrap then nxt = (nxt - 1) % #opts + 1 end
    if nxt < 1 or nxt > #opts then return end
    set(opts[nxt].id)
  end
  row.on_a = function() end
  for k, v in pairs(extra or {}) do row[k] = v end
  return row
end
X.choice = choice

local function pref_choice(label, desc, key, opts, default, on_change)
  return choice(label, desc, opts,
    function() return Prefs.get(key) or default end,
    function(v) Prefs.set(key, v); if on_change then on_change(v) end end)
end

local function infolist(p) App.push("infolist", p) end

local STATE_TAG = {
  ok = { L("OK"), function() return T.c.green end },
  warn = { L("ATENÇÃO"), function() return T.c.yellow end },
  error = { L("ERRO"), function() return T.c.red end },
}

-- ---------------------------------------------------------------------------
-- PREFERENCIAS (tela inicial, saida, notificacoes, restaurar)
X.START_SCREENS = {
  { id = "menu", label = L("Menu principal") },
  { id = "store", label = L("Central de Conteúdo") },
  { id = "installed", label = L("Meus Ports") },
  { id = "downloads", label = L("Central de Downloads") },
}

--- abre a tela inicial escolhida (chamado depois do aviso importante)
function X.open_start_screen()
  local s = Prefs.get("start_screen") or "menu"
  if s == "store" then App.push("sections")
  elseif s == "installed" then App.push("store", { mine = true })
  elseif s == "downloads" then App.open_downloads(false) end
end

--- preferencias que "Restaurar preferencias" volta ao padrao (idioma, tema,
--- brilho, FTP, favoritos e historicos ficam como estao)
local RESET_KEYS = { "start_screen", "exit_mode", "anim", "eco", "notif", "notif_info", "notif_alert",
  "notif_downloads", "ftp_notif_done", "ftp_notif_fail", "music", "music_vol", "sfx", "sfx_vol", "notif_sound",
  "font_size", "list_sort", "fav_sort", "cat_auto", "upd_notify", "notif_pos", "rec_fps", "stream_fps" }

local function reset_prefs()
  -- copia do arquivo atual antes de mexer (recuperacao manual, se precisar)
  local ok, cur = pcall(love.filesystem.read, "settings.txt")
  if ok and cur then pcall(love.filesystem.write, "settings.antes_de_restaurar.txt", cur) end
  for _, k in ipairs(RESET_KEYS) do Prefs.set(k, nil) end
  App.apply_restored({ prefs = true })
  App.toast(L("Preferências restauradas para o padrão."), "ok")
end

X.NOTIF_POS = {
  { id = "bottom", label = L("Embaixo, no centro") },
  { id = "top", label = L("Em cima, no centro") },
  { id = "top_right", label = L("Canto superior direito") },
  { id = "bottom_right", label = L("Canto inferior direito") },
}

function X.prefs_category()
  return {
    id = "prefs", icon = "set_prefs", color = "accent",
    name = L("Preferências"),
    desc = L("Idioma, tela inicial, notificações e restaurar padrões."),
    status = function()
      local lb = "?"
      for _, l in ipairs(I18N.LANGS) do if l.id == I18N.lang then lb = l.label end end
      return lb .. "  •  " .. (pref_on("notif") and I18N.tr(L("avisos ligados")) or I18N.tr(L("avisos desligados")))
    end,
    rows = {
      -- idioma: A abre a tela de escolha (bandeiras), a mesma da primeira abertura
      { kind = "action", label = L("Idioma"),
        desc = L("Idioma de todo o aplicativo: Português (Brasil), English e Русский. A abre a tela de escolha; a mudança vale na hora, sem reiniciar."),
        value = function()
          for _, l in ipairs(I18N.LANGS) do if l.id == I18N.lang then return l.label end end
          return "?"
        end,
        on_a = function() App.push("language", { first = false }) end },
      pref_choice(L("Tela ao abrir"), L("Tela que abre depois do aviso importante. O menu principal continua a um B de distância."),
        "start_screen", X.START_SCREENS, "menu"),
      pref_choice(L("Botão B no menu principal"), L("O que acontece ao apertar B no menu principal. A opção Sair do menu sempre mostra todas as escolhas."),
        "exit_mode", { { id = "ask", label = L("Perguntar o que fazer") }, { id = "quit", label = L("Sair direto") } }, "ask"),
      { kind = "toggle", label = L("Notificações na tela"),
        desc = L("Mensagens rápidas que aparecem por alguns segundos. Janelas de confirmação sempre aparecem."),
        get = function() return pref_on("notif") end, set = function(v) Prefs.set("notif", v and "1" or "0") end },
      pref_choice(L("Posição das notificações"), L("Onde as mensagens rápidas aparecem na tela. Uma notificação de exemplo mostra o lugar escolhido."),
        "notif_pos", X.NOTIF_POS, "bottom", function() App.toast(L("As notificações vão aparecer aqui."), "info") end),
      { kind = "toggle", label = L("Confirmações e informações"),
        desc = L("Ex.: download adicionado, catálogo atualizado, print salvo."),
        enabled = function() return pref_on("notif") end,
        get = function() return pref_on("notif_info") end, set = function(v) Prefs.set("notif_info", v and "1" or "0") end },
      { kind = "toggle", label = L("Alertas e erros"),
        desc = L("Ex.: falha de conexão, espaço insuficiente, brilho indisponível."),
        enabled = function() return pref_on("notif") end,
        get = function() return pref_on("notif_alert") end, set = function(v) Prefs.set("notif_alert", v and "1" or "0") end },
      { kind = "toggle", label = L("Aviso de nova versão do hub"),
        desc = L("Ao abrir o hub, confere o link oficial em segundo plano. Se houver versão nova, um aviso desliza no alto da tela inicial até você atualizar (SELECT abre a atualização). Nada é baixado sozinho."),
        get = function() return pref_on("upd_notify") end, set = function(v) Prefs.set("upd_notify", v and "1" or "0") end },
      { kind = "toggle", label = L("Som das notificações"),
        desc = L("Toca um aviso curto quando uma notificação aparece."),
        get = function() return require("core.sfx").notif end,
        set = function(v) local Sfx = require("core.sfx"); Sfx.set_notify(v); if v then Sfx.notify("info") end end },
      { kind = "action", label = L("Testar notificação"), desc = L("Mostra uma notificação de exemplo com as opções atuais."),
        on_a = function() App.toast(L("Esta é uma notificação de teste."), "info") end },
      { kind = "action", label = L("Restaurar preferências"),
        desc = L("Volta ao padrão a tela inicial, a saída, as notificações, o som, a música, as animações, o tamanho do texto, a ordenação das listas e a gravação. Idioma, tema, brilho, FTP, favoritos e históricos não mudam."),
        on_a = function()
          App.show_dialog({ title = L("Restaurar preferências?"), kind = "warn",
            body = L("As preferências voltam ao padrão. Idioma, tema, brilho, FTP, favoritos, históricos e ports instalados não são alterados.\n\nUma cópia das preferências atuais fica em settings.antes_de_restaurar.txt."),
            buttons = { { label = L("RESTAURAR"), fn = reset_prefs }, { label = L("CANCELAR") } } })
        end },
    },
  }
end

-- ---------------------------------------------------------------------------
-- CATALOGO DE PORTS
local FAV_SORTS = {
  { id = "catalog", label = L("Ordem do catálogo") },
  { id = "name", label = L("Nome (A-Z)") },
  { id = "installed", label = L("Instalados primeiro") },
}
X.SORTS = {
  { id = "catalog", label = L("Ordem do catálogo") },
  { id = "name", label = L("Nome (A-Z)") },
  { id = "size", label = L("Tamanho (menor primeiro)") },
  { id = "installed", label = L("Instalados primeiro") },
}

--- ordena uma lista de ports conforme a preferencia (estavel)
function X.sort_ports(list, key)
  local mode = Prefs.get(key or "list_sort") or "catalog"
  if mode == "catalog" then return list end
  local idx = {}
  for i, p in ipairs(list) do idx[p] = i end
  local status = App.status
  table.sort(list, function(a, b)
    if mode == "name" then
      local na, nb = tostring(a.name or ""):lower(), tostring(b.name or ""):lower()
      if na ~= nb then return na < nb end
    elseif mode == "size" then
      local sa, sb = tonumber(a.size) or math.huge, tonumber(b.size) or math.huge
      if sa ~= sb then return sa < sb end
    elseif mode == "installed" and status then
      local ia, ib = status(a) ~= "none", status(b) ~= "none"
      if ia ~= ib then return ia end
    end
    return idx[a] < idx[b]
  end)
  return list
end

local function covers_size()
  local s = U.capture("du -sk " .. U.shq(love.filesystem.getSaveDirectory() .. "/covers") .. " 2>/dev/null")
  local kb = tonumber((s or ""):match("^(%d+)"))
  return kb and kb * 1024 or 0
end

function X.catalog_category()
  local Catalog = require("core.catalog")
  return {
    id = "catalog", icon = "set_catalog", color = "yellow",
    name = L("Catálogo de ports"),
    desc = L("Atualização, conteúdo e ordenação das listas."),
    status = function() return string.format(I18N.tr(L("%d ports")), #Catalog.ports) .. "  •  " .. Catalog.source_label() end,
    rows = {
      { kind = "action", label = L("Atualizar catálogo agora"),
        desc = function()
          local url = Catalog.get_remote_url()
          return L("Baixa a lista de ports com as descrições, capas, tamanhos e categorias mais recentes. Seus ports instalados e dados locais são preservados.\nFonte: ")
            .. (url or L("nenhuma URL configurada (catalog_url.txt)"))
        end,
        value = function() return Catalog.remote_state == "loading" and L("Atualizando catálogo...") or Catalog.source_label() end,
        on_a = function()
          if Catalog.remote_state == "loading" then return end
          App.update_free_space()
          App.refresh_catalog(true, function(okc, msg)
            App.show_dialog({ title = okc and L("Catálogo") or L("Falha ao atualizar"), kind = okc and "ok" or "error", body = msg })
          end)
        end },
      { kind = "toggle", label = L("Atualizar ao abrir o hub"),
        desc = L("Busca o catálogo online toda vez que o hub abre. Desligado, o hub usa o último catálogo baixado até você atualizar à mão."),
        get = function() return pref_on("cat_auto") end, set = function(v) Prefs.set("cat_auto", v and "1" or "0") end },
      { kind = "info", label = L("Última atualização online"), desc = L("Quando o catálogo foi baixado com sucesso pela última vez."),
        value = function()
          local t = tonumber(Prefs.get("cat_last") or "")
          return t and Clock.datetime(t, true) or L("ainda não registrada")
        end },
      { kind = "info", label = L("Conteúdo"), desc = L("Ports e categorias do catálogo carregado agora."),
        value = function()
          return string.format(I18N.tr(L("%d ports  •  %d categorias")), #Catalog.ports, #Catalog.categories)
            .. (Catalog.updated ~= "" and ("  •  v" .. Catalog.updated) or "")
        end },
      pref_choice(L("Ordenação das listas"), L("Ordem dos ports na Central de Conteúdo, nas categorias e em Meus Ports. A pesquisa continua por nome."),
        "list_sort", X.SORTS, "catalog", function() App.on_catalog_changed() end),
      pref_choice(L("Ordenar favoritos"), L("Ordem da lista de Favoritos."), "fav_sort", FAV_SORTS, "catalog"),
    },
  }
end

-- ---------------------------------------------------------------------------
-- DOWNLOADS
local function retry_failed()
  local Downloads = require("core.downloads")
  local Catalog = require("core.catalog")
  if not Downloads.loaded then Downloads.load() end
  local by = {}
  for _, p in ipairs(Catalog.ports) do by[p.id] = p end
  local n, missing = 0, 0
  local seen = {}
  for _, e in ipairs(Downloads.list) do
    if e.state == "error" and e.pid and not seen[e.pid] then
      seen[e.pid] = true
      local p = by[e.pid]
      if p and not Downloads.pending(p.id) then
        if Downloads.enqueue(p, {}) then n = n + 1 end
      elseif not p then
        missing = missing + 1
      end
    end
  end
  if n > 0 then
    App.toast(string.format(L("%d download(s) voltaram para a fila."), n), "ok")
  elseif missing > 0 then
    App.toast(L("Os ports com falha não estão mais no catálogo."), "warn")
  else
    App.toast(L("Nenhum download com falha para repetir."), "info")
  end
end

function X.downloads_rows(dl_status)
  local Downloads = require("core.downloads")
  local function counts()
    if not Downloads.loaded then Downloads.load() end
    local d, e = 0, 0
    for _, x in ipairs(Downloads.list) do
      if x.state == "done" then d = d + 1 elseif x.state == "error" then e = e + 1 end
    end
    return d, e
  end
  return {
    { kind = "action", label = L("Central de Downloads"),
      desc = L("Downloads, extrações e instalações feitos pelo hub aparecem aqui, com progresso, velocidade e tamanho reais.\nPressione START em qualquer tela para voltar a esta central."),
      value = dl_status, on_a = function() App.open_downloads(true) end },
    { kind = "toggle", label = L("Avisos de downloads em segundo plano"),
      desc = L("Mostra um aviso quando um download em segundo plano termina ou falha. Os detalhes continuam na Central de Downloads."),
      get = function() return pref_on("notif_downloads") end,
      set = function(v) Prefs.set("notif_downloads", v and "1" or "0") end },
    { kind = "info", label = L("Histórico"), desc = L("Downloads concluídos e com falha guardados no histórico (até 30)."),
      value = function()
        local d, e = counts()
        return string.format(I18N.tr(L("%d concluído(s)  •  %d com falha")), d, e)
      end,
      color = function() local _, e = counts(); return e > 0 and T.c.yellow or T.c.text end },
    { kind = "action", label = L("Repetir downloads com falha"),
      desc = L("Coloca de novo na fila os ports do histórico cujo download falhou. Um de cada vez, como sempre."),
      enabled = function() local _, e = counts(); return e > 0 end,
      on_a = retry_failed },
    { kind = "action", label = L("Limpar histórico"),
      desc = L("Apaga só a lista de downloads finalizados. Ports instalados e arquivos não são tocados."),
      enabled = function() return Downloads.history_count() > 0 end,
      on_a = function()
        App.show_dialog({ title = L("Limpar histórico?"), kind = "warn",
          body = L("A lista de downloads finalizados será apagada. Os ports instalados não são alterados."),
          buttons = { { label = L("LIMPAR"), fn = function() Downloads.clear_history(); App.toast(L("Histórico limpo."), "ok") end },
            { label = L("CANCELAR") } } })
      end },
  }
end

-- ---------------------------------------------------------------------------
-- MEUS PORTS
local function port_space()
  local Manifest = require("core.manifest")
  local Scan = require("core.scan")
  Manifest.rescan(true)
  -- cada port: o .sh e a pasta encontrados (registro do hub ou varredura)
  local entries = {}
  local Catalog = require("core.catalog")
  for _, p in ipairs(Catalog.ports) do
    if Manifest.status(p) ~= "none" then entries[#entries + 1] = { name = p.name, items = Manifest.found(p) or {} } end
  end
  for _, lp in ipairs(Manifest.local_ports(Catalog.ports)) do
    entries[#entries + 1] = { name = lp.name, items = lp.local_items or {} }
  end
  infolist({ title = L("Espaço ocupado pelos ports"), sub = L("Somente leitura"),
    empty = L("Nenhum port instalado encontrado."),
    load = function(scr)
      if #entries == 0 then scr.items = {}; return end
      scr.loading = L("Calculando o espaço...")
      local cmds = {}
      for _, e in ipairs(entries) do
        local paths = {}
        for _, n in ipairs(e.items) do paths[#paths + 1] = U.shq(C.PORTS_DIR .. "/" .. n) end
        cmds[#cmds + 1] = #paths > 0 and ("du -sck " .. table.concat(paths, " ") .. " | tail -n 1") or "echo 0"
      end
      require("core.shjob").start(cmds, function(res)
        scr.loading = nil
        local items, total = {}, 0
        for i, e in ipairs(entries) do
          local kb = res and res[i] and tonumber((res[i].out or ""):match("(%d+)")) or nil
          local b = kb and kb * 1024 or nil
          total = total + (b or 0)
          items[#items + 1] = { text = e.name, size = b or -1,
            sub = (b and U.format_bytes(b) or I18N.tr(L("não foi possível medir"))) .. "  •  " .. table.concat(e.items, ", "),
            detail = table.concat(e.items, "\n") }
        end
        table.sort(items, function(a, b) return a.size > b.size end)
        scr.items = items
        scr.p.sub = I18N.tr(L("Total: ")) .. U.format_bytes(total)
      end)
    end })
end

local function show_incomplete()
  local Diag = require("core.diag")
  local inc = Diag.incomplete_ports()
  local items = {}
  for _, e in ipairs(inc) do
    items[#items + 1] = { tag = L("INCOMPLETO"), tagc = T.c.yellow, text = e.name,
      sub = I18N.tr(L("Faltando: ")) .. table.concat(e.missing, ", "),
      detail = I18N.tr(L("Itens registrados na instalação que não estão mais no cartão:\n")) .. table.concat(e.missing, "\n")
        .. I18N.tr(L("\n\nReinstale o port pela Central de Conteúdo ou desinstale em Meus Ports (X).")) }
  end
  infolist({ title = L("Instalações incompletas"), empty = L("Nenhuma instalação incompleta: todos os ports instalados pelo hub estão com os arquivos no lugar."),
    items = items })
end

function X.myports_category()
  local Manifest = require("core.manifest")
  local function counts()
    local n = 0
    for _ in pairs(Manifest.data or {}) do n = n + 1 end
    return n, require("core.scan").count or 0
  end
  return {
    id = "myports", icon = "set_myports", color = "green",
    name = L("Meus Ports"),
    desc = L("Instalados, favoritos, integridade e remoção."),
    status = function() local n, s = counts(); return string.format(I18N.tr(L("%d pelo hub  •  %d no cartão")), n, s) end,
    rows = {
      { kind = "action", label = L("Abrir Meus Ports"),
        desc = L("Lista dos ports instalados, com capa e informações. X desinstala (só os arquivos daquele port, sempre com confirmação)."),
        on_a = function() App.push("store", { mine = true }) end },
      { kind = "action", label = L("Abrir Favoritos"),
        desc = L("Ports marcados com estrela. Na loja, SELECT marca ou desmarca um port."),
        value = function() return tostring(require("core.favorites").count()) end,
        on_a = function() App.push("store", { favs = true }) end },
      { kind = "info", label = L("Ports encontrados"),
        desc = L("Instalados pelo hub (registro de instalação) e scripts .sh encontrados na pasta de ports (PortMaster, cópia manual)."),
        value = function() local n, s = counts(); return string.format(I18N.tr(L("%d pelo hub  •  %d scripts no cartão")), n, s) end },
      { kind = "action", label = L("Verificador de integridade"),
        desc = L("Confere scripts, pastas e runtimes dos ports instalados. Somente leitura."),
        on_a = function() App.push("integrity") end },
      { kind = "action", label = L("Instalações incompletas"),
        desc = L("Ports instalados pelo hub com parte dos arquivos faltando no cartão."),
        value = function()
          local n = #require("core.diag").incomplete_ports()
          return n == 0 and L("nenhuma") or string.format(I18N.tr(L("%d encontrada(s)")), n)
        end,
        on_a = show_incomplete },
      { kind = "action", label = L("Atualizar informações"),
        desc = L("Procura de novo os ports na pasta de ports (reconhece o que foi instalado ou removido por fora do hub)."),
        on_a = function()
          Manifest.rescan(true)
          App.on_catalog_changed()
          local n, s = counts()
          App.toast(string.format(L("Informações atualizadas: %d scripts na pasta de ports."), s), "ok")
        end },
      { kind = "action", label = L("Limpar favoritos"),
        desc = L("Tira a estrela de todos os ports. Nada é desinstalado."),
        enabled = function() return require("core.favorites").count() > 0 end,
        on_a = function()
          local Fav = require("core.favorites")
          App.show_dialog({ title = L("Limpar favoritos?"), kind = "warn",
            body = L("Todos os ports deixam de ser favoritos. Nenhum port é desinstalado."),
            buttons = { { label = L("LIMPAR"), fn = function()
              if not Fav.loaded then Fav.load() end
              Fav.ids = {}
              pcall(love.filesystem.write, "favorites.json", "[]")
              App.on_catalog_changed()
              App.toast(L("Favoritos limpos."), "ok")
            end }, { label = L("CANCELAR") } } })
        end },
    },
  }
end

-- ---------------------------------------------------------------------------
-- REDE: repositorios e historico de erros
local function repo_check()
  local Catalog = require("core.catalog")
  local targets = {}
  local cu = Catalog.get_remote_url()
  if cu then targets[#targets + 1] = { name = L("Catálogo de ports"), url = cu } end
  local okU, Upd = pcall(require, "core.update")
  local uu = okU and Upd.source_url() or nil
  if uu then targets[#targets + 1] = { name = L("Atualizações do hub"), url = uu } end
  local Bios = package.loaded["core.bios"] or require("core.bios")
  local bu = Bios.url_ok and Bios.url_ok() and (Bios.url()) or nil
  if bu then targets[#targets + 1] = { name = L("Pacote de BIOS"), url = bu } end
  local tu = U.read_file(C.APP_DIR .. "/es_themes_url.txt")
  tu = tu and U.trim(tu:match("^[^\r\n]*") or "") or (C.ES_THEMES_URL or "")
  if tu:match("^https?://") then targets[#targets + 1] = { name = L("Loja de Temas"), url = tu } end
  infolist({ title = L("Verificação dos repositórios"), sub = L("Testa se cada endereço responde"),
    empty = L("Nenhum endereço configurado."),
    load = function(scr)
      if #targets == 0 then scr.items = {}; return end
      scr.loading = L("Testando os endereços...")
      local cmds = {}
      for _, t in ipairs(targets) do
        cmds[#cmds + 1] = "curl -sIL -o /dev/null -w '%{http_code}' --max-time 15 -A 'R36S-PORT-HUB' " .. U.shq(t.url)
          .. " || wget -q --spider -T 15 " .. U.shq(t.url) .. " && echo 200"
      end
      require("core.shjob").start(cmds, function(res)
        scr.loading = nil
        local items = {}
        local Net = require("core.netlog")
        for i, t in ipairs(targets) do
          local r = res and res[i]
          local code = r and tonumber((r.out or ""):match("(%d%d%d)")) or nil
          local ok = code and code >= 200 and code < 400
          if not ok then Net.add(t.name, t.url, code and ("HTTP " .. code) or L("sem resposta")) end
          items[#items + 1] = { tag = ok and L("OK") or L("FALHOU"), tagc = ok and T.c.green or T.c.red, text = t.name,
            sub = (t.url:match("^%a+://([^/]+)") or t.url) .. "  •  " .. (code and ("HTTP " .. code) or I18N.tr(L("sem resposta")))
              .. (r and string.format("  •  %.1f s", r.secs) or ""),
            detail = t.url }
        end
        scr.items = items
      end)
    end,
    keys = { { key = "y", label = L("Testar de novo"), fn = function(scr) scr.p.load(scr) end } } })
end

local function net_history()
  local Net = require("core.netlog")
  local function build(scr)
    local items = {}
    for _, e in ipairs(Net.all()) do
      items[#items + 1] = { text = I18N.tr(e.what) .. (e.host ~= "" and ("  •  " .. e.host) or ""),
        sub = Clock.datetime(e.time, true) .. (e.reason ~= "" and ("  •  " .. I18N.tr(e.reason)) or "") }
    end
    scr.items = items
  end
  infolist({ title = L("Erros de comunicação"), sub = L("Mais recentes primeiro"),
    empty = L("Nenhuma falha de comunicação registrada."), load = build,
    keys = { { key = "x", label = L("Limpar"), enabled = function() return Net.count() > 0 end,
      fn = function(scr) Net.clear(); build(scr); App.toast(L("Histórico limpo."), "ok") end } } })
end

function X.network_extra_rows()
  return {
    { kind = "action", label = L("Verificação dos repositórios"),
      desc = L("Testa se o catálogo de ports, as atualizações do hub, o pacote de BIOS e a Loja de Temas respondem pela internet."),
      on_a = repo_check },
  }
end

-- ---------------------------------------------------------------------------
-- SERVIDOR FTP
function X.ftp_category()
  local Ftp = require("core.ftp")
  local Net = require("core.net")
  local function cfg() if not Ftp.cfg then Ftp.load() end return Ftp.cfg or {} end
  return {
    id = "ftp", icon = "set_ftp", color = "orange",
    name = L("Servidor FTP"),
    desc = L("Envie e receba arquivos pelo celular ou PC."),
    status = function()
      if Ftp.state == "on" then return I18N.tr(L("ATIVADO")) .. "  •  " .. I18N.tr(L("porta ")) .. tostring(cfg().port) end
      return I18N.tr(L("DESATIVADO"))
    end,
    rows = {
      { kind = "toggle", label = L("Servidor FTP"),
        desc = L("Liga ou desliga o servidor FTP do hub. Precisa de Wi-Fi. Exige usuário e senha."),
        get = function() return Ftp.state == "on" or Ftp.state == "starting" end,
        set = function(v)
          if v then
            local ok, why = Ftp.start()
            if not ok then App.show_dialog({ title = L("Não foi possível iniciar"), kind = "error", body = why or "" }) end
          else
            Ftp.stop()
          end
        end },
      { kind = "info", label = L("Endereço"), desc = L("Use este endereço no app de FTP do celular ou do computador."),
        value = function()
          local st = Net.current()
          return (st and st.ip) and ("ftp://" .. st.ip .. ":" .. tostring(cfg().port)) or "—"
        end },
      { kind = "info", label = L("Usuário"), desc = L("Usuário do servidor FTP."), value = function() return tostring(cfg().user or "—") end },
      { kind = "info", label = L("Senha"), desc = L("A senha aparece em Configurar servidor FTP. Ela nunca vai para os registros nem para as exportações."),
        value = function() return cfg().pass and "••••••" or "—" end },
      { kind = "info", label = L("Estado"), desc = L("Situação atual do servidor e clientes conectados."),
        value = function()
          if Ftp.state == "on" then return I18N.tr(L("ATIVADO")) .. "  •  " .. tostring(Ftp.clients or 0) .. I18N.tr(L(" cliente(s)")) end
          if Ftp.running() then return L("AGUARDE") end
          return L("DESATIVADO")
        end,
        color = function() return Ftp.state == "on" and T.c.green or (Ftp.running() and T.c.yellow or T.c.red) end },
      { kind = "action", label = L("Configurar servidor FTP"),
        desc = L("Porta, usuário, senha, pastas que podem ser acessadas e QR Code de conexão."),
        on_a = function() App.push("ftp") end },
      { kind = "action", label = L("Tutorial (celular e computador)"),
        desc = L("Passo a passo para conectar pelo celular e pelo computador."),
        on_a = function() App.push("ftp_help") end },
      { kind = "action", label = L("Transferências e histórico"),
        desc = L("Arquivos sendo enviados e recebidos, velocidade e histórico das transferências."),
        on_a = function() App.push("ftp_activity") end },
      { kind = "toggle", label = L("Avisar transferências concluídas"),
        desc = L("Mostra um aviso quando um arquivo termina de ser enviado ou recebido."),
        get = function() return pref_on("ftp_notif_done") end, set = function(v) Prefs.set("ftp_notif_done", v and "1" or "0") end },
      { kind = "toggle", label = L("Avisar falhas de transferência"),
        desc = L("Mostra um aviso quando uma transferência falha ou é cancelada."),
        get = function() return pref_on("ftp_notif_fail") end, set = function(v) Prefs.set("ftp_notif_fail", v and "1" or "0") end },
    },
  }
end

-- ---------------------------------------------------------------------------
-- ATUALIZACOES DO HUB
function X.updates_category()
  local Mgr = require("core.updater.manager")
  return {
    id = "updates", icon = "set_updates", color = "accent2",
    name = L("Atualizações do hub"),
    desc = L("Versão, verificar, instalar, histórico e recuperação."),
    status = function() return "v" .. C.VERSION .. (Mgr.restart_needed and ("  •  " .. I18N.tr(L("reinicie o app"))) or "") end,
    rows = {
      { kind = "info", label = L("Versão instalada"), desc = L("Versão do R36S PORT HUB em uso."),
        value = function() return C.VERSION .. (Mgr.restart_needed and ("  •  " .. I18N.tr(L("reinicie o app"))) or "") end },
      { kind = "action", label = L("Atualização via rede"),
        desc = L("Verifica a versão disponível no link oficial, mostra as novidades e baixa o pacote para a pasta update."),
        on_a = function() App.push("update") end },
      { kind = "action", label = L("Atualização local"),
        desc = L("Instala um pacote colocado na pasta update. Confere o SHA-256 e faz backup antes de trocar os arquivos."),
        on_a = function() App.push("upd_local") end },
      { kind = "action", label = L("Histórico de atualizações"), desc = L("Versões instaladas, data, origem e resultado."),
        on_a = function() App.push("upd_history") end },
      { kind = "action", label = L("Backups e recuperação"),
        desc = L("Volta para uma versão anterior a partir dos backups feitos antes de cada atualização."),
        on_a = function() App.push("upd_backups") end },
    },
  }
end

-- ---------------------------------------------------------------------------
-- FERRAMENTAS (componentes do hub e dos ports)
local function hub_modules()
  local app = C.APP_DIR
  local cmds = {
    "unzip -tq " .. U.shq(app .. "/game.love"),
    "sh -n " .. U.shq(app .. "/bin/fetch.sh") .. " && echo ok",
    "[ -x " .. U.shq(app .. "/bin/7zzs") .. " ] && " .. U.shq(app .. "/bin/7zzs") .. " i 2>/dev/null | head -n 3",
    "command -v curl || command -v wget",
    "command -v unzip",
    "command -v ffmpeg",
  }
  infolist({ title = L("Componentes do hub"), sub = L("Somente leitura"),
    load = function(scr)
      scr.loading = L("Verificando os componentes...")
      require("core.shjob").start(cmds, function(res)
        scr.loading = nil
        local function r(i) return res and res[i] or { out = "", rc = 1 } end
        local Runtimes = require("core.runtimes")
        local pm = Runtimes.detect_pm()
        local pmv = pm and U.read_file(pm .. "/version")
        local maj, min, rev = love.getVersion()
        local zip7 = (r(3).out or ""):match("7%-Zip[^\n]*")
        local function st(ok) return ok and L("OK") or L("ERRO"), ok and T.c.green or T.c.red end
        local items = {}
        local t, c = st(r(1).rc == 0)
        items[#items + 1] = { tag = t, tagc = c, text = "game.love  •  " .. C.VERSION,
          sub = r(1).rc == 0 and I18N.tr(L("pacote do app íntegro")) or I18N.tr(L("o pacote do app está danificado: reinstale o hub")) }
        t, c = st(r(2).rc == 0)
        items[#items + 1] = { tag = t, tagc = c, text = "bin/fetch.sh", sub = I18N.tr(L("downloads (curl/wget)")) }
        local has7 = zip7 ~= nil
        items[#items + 1] = { tag = has7 and L("OK") or L("AUSENTE"), tagc = has7 and T.c.green or T.c.yellow, text = "bin/7zzs",
          sub = zip7 or I18N.tr(L("extração de 7z e RAR indisponível")) }
        items[#items + 1] = { tag = L("INFO"), tagc = T.c.accent2, text = "LÖVE " .. maj .. "." .. min .. "." .. rev,
          sub = I18N.tr(L("motor do aplicativo")) }
        local hasdl = (r(4).out or ""):find("%S") ~= nil
        items[#items + 1] = { tag = hasdl and L("OK") or L("ERRO"), tagc = hasdl and T.c.green or T.c.red,
          text = hasdl and U.trim(r(4).out) or "curl / wget", sub = I18N.tr(L("usado nos downloads")) }
        local hasun = (r(5).out or ""):find("%S") ~= nil
        items[#items + 1] = { tag = hasun and L("OK") or L("AUSENTE"), tagc = hasun and T.c.green or T.c.yellow,
          text = hasun and U.trim(r(5).out) or "unzip", sub = I18N.tr(L("extração de ZIP")) }
        local hasff = (r(6).out or ""):find("%S") ~= nil
        items[#items + 1] = { tag = hasff and L("OK") or L("AUSENTE"), tagc = hasff and T.c.green or T.c.faint,
          text = hasff and U.trim(r(6).out) or "ffmpeg", sub = I18N.tr(L("gravação em MP4 (opcional)")) }
        items[#items + 1] = { tag = pm and L("OK") or L("AUSENTE"), tagc = pm and T.c.green or T.c.yellow,
          text = "PortMaster" .. (pmv and ("  •  " .. U.trim(pmv:match("^[^\n]*"))) or ""), sub = pm or I18N.tr(L("não instalado")) }
        scr.items = items
      end)
    end,
    keys = { { key = "y", label = L("Verificar de novo"), fn = function(scr) scr.p.load(scr) end } } })
end

function X.tools_category(runtimes_row)
  local Runtimes = require("core.runtimes")
  return {
    id = "tools", icon = "set_tools", color = "orange",
    name = L("PortMaster e runtimes"),
    desc = L("Instalar, atualizar e reparar o PortMaster e os runtimes dos ports."),
    status = function() return Runtimes.detect_pm() and "PortMaster" or I18N.tr(L("PortMaster não encontrado")) end,
    enter = function(scr) scr.pm = Runtimes.detect_pm() end,
    resume = function(scr) scr.pm = Runtimes.detect_pm() end,
    rows = {
      { kind = "action", label = L("Gerenciar PortMaster"),
        desc = L("Instalar, atualizar, verificar e reparar o PortMaster com a versão estável oficial.\nBackup antes de mudar; ports, saves, configurações e runtimes são preservados."),
        value = function() return require("core.pmmanager").busy() and L("em andamento") or "" end,
        on_a = function() App.push("pmmanager") end },
      runtimes_row,
    },
  }
end

-- ---------------------------------------------------------------------------
-- ARMAZENAMENTO (cartao microSD, memoria e cache)
function X.storage_category()
  local SysInfo = require("core.sysinfo")
  local function rows_for(scr)
    local rows = {}
    local info = scr.sinfo
    if not info then
      rows[#rows + 1] = { kind = "info", label = L("Lendo o cartão..."), desc = L("Somente leitura: nada é alterado."),
        value = function() return "" end }
    else
      for _, st in ipairs(info.storage or {}) do
        if st.ok then
          rows[#rows + 1] = { kind = "info", label = (st.label and st.label ~= "") and st.label or L("Cartão SD"),
            desc = L("Espaço do cartão (total, usado e livre). Abaixo de 200 MB livres, downloads e atualizações podem falhar."),
            value = function()
              return string.format(I18N.tr(L("%s livres de %s")), U.format_bytes(st.free), U.format_bytes(st.total))
                .. string.format("  (%d%%)", math.floor(st.frac * 100 + 0.5))
            end,
            color = function() return st.frac > 0.9 and T.c.red or (st.frac > 0.75 and T.c.yellow or T.c.green) end }
        end
      end
      if #rows == 0 then
        rows[#rows + 1] = { kind = "info", label = L("Cartão SD"), desc = L("O sistema não informou o espaço do cartão."),
          value = function() return SysInfo.NA end }
      end
      rows[#rows + 1] = { kind = "info", label = L("Memória RAM"), desc = L("Memória livre para uso agora e o total do console."),
        value = function()
          local m = info.mem
          return (m and m.ok) and string.format(I18N.tr(L("%s livres de %s")), U.format_bytes(m.avail), U.format_bytes(m.total)) or SysInfo.NA
        end }
    end
    rows[#rows + 1] = { kind = "action", label = L("Espaço ocupado pelos ports"),
      desc = L("Mede quanto cada port instalado ocupa no cartão SD. Somente leitura."), on_a = port_space }
    rows[#rows + 1] = { kind = "action", label = L("Cache de capas"),
      desc = L("Capas dos ports guardadas no console. A apaga só esse cache: as capas são baixadas de novo quando aparecerem (precisa de internet). Ports instalados e o catálogo não mudam."),
      value = function() return U.format_bytes(scr.csize or 0) end,
      on_a = function()
        App.show_dialog({ title = L("Limpar o cache de capas?"), kind = "warn",
          body = L("As capas guardadas no console serão apagadas e baixadas de novo quando aparecerem na tela. Ports instalados e o catálogo não mudam."),
          buttons = { { label = L("LIMPAR"), fn = function()
            require("core.covers").clear_disk()
            scr.csize = covers_size()
            App.update_free_space()
            App.toast(L("Cache de capas limpo."), "ok")
          end }, { label = L("CANCELAR") } } })
      end }
    rows[#rows + 1] = { kind = "action", label = L("Baixar todas as capas do catálogo"),
      desc = L("Baixa de uma vez as capas do catálogo que ainda não estão no console, em segundo plano (pode sair desta tela). Depois, as capas aparecem mesmo sem internet. A de novo cancela."),
      value = function()
        local J = require("core.covers").bulk
        if J then return string.format(I18N.tr(L("baixando %d de %d")), J.i, J.total) end
        if scr.cmiss == nil then return "" end
        return scr.cmiss == 0 and I18N.tr(L("todas no console")) or string.format(I18N.tr(L("%d faltando")), scr.cmiss)
      end,
      color = function() return require("core.covers").bulk and T.c.accent2 or nil end,
      on_a = function()
        local Covers = require("core.covers")
        if Covers.bulk then
          App.show_dialog({ title = L("Cancelar o download das capas?"), kind = "warn",
            body = L("A capa em andamento termina e o download para. As capas já baixadas ficam no console."),
            buttons = { { label = L("CANCELAR DOWNLOAD"), fn = function() Covers.bulk_cancel() end }, { label = L("CONTINUAR") } }, sel = 2 })
          return
        end
        local Catalog = require("core.catalog")
        local miss = #Covers.missing(Catalog.ports)
        scr.cmiss = miss
        if miss == 0 then App.toast(L("Todas as capas do catálogo já estão no console."), "info"); return end
        local st = require("core.net").current()
        if st and not st.connected then App.toast(L("Sem internet: conecte o Wi-Fi para baixar as capas."), "warn"); return end
        App.show_dialog({ title = L("Baixar as capas?"), kind = "info",
          body = string.format(I18N.tr(L("%d capas do catálogo ainda não estão no console. Elas serão baixadas uma por vez, em segundo plano, e ficam guardadas no Cache de capas.")), miss),
          buttons = { { label = L("BAIXAR"), fn = function()
            Covers.bulk_start(Catalog.ports, function(job)
              scr.csize = covers_size()
              scr.cmiss = #Covers.missing(Catalog.ports)
              App.update_free_space()
              if job.cancel then
                App.toast(string.format(I18N.tr(L("Download das capas cancelado: %d baixadas.")), job.ok), "info")
              elseif job.failed > 0 then
                App.toast(string.format(I18N.tr(L("Capas: %d baixadas, %d falharam.")), job.ok, job.failed), "warn")
              else
                App.toast(string.format(I18N.tr(L("Capas: %d baixadas.")), job.ok), "ok")
              end
            end)
          end }, { label = L("CANCELAR") } } })
      end }
    rows[#rows + 1] = { kind = "action", label = L("Gerenciador de arquivos"),
      desc = L("Navegue pelo cartão SD: copiar, recortar, colar, excluir e extrair arquivos ZIP, RAR e 7z."),
      on_a = function() App.push("files", { path = C.PORTS_DIR }) end }
    rows[#rows + 1] = { kind = "action", label = L("Otimizador e manutenção do microSD"), icon = "set_sdmaint",
      desc = L("Analise o espaço, verifique a integridade e cuide do cartão microSD sem colocar seus jogos em risco."),
      on_a = function() App.push("sdmaint") end }
    rows[#rows + 1] = { kind = "action", label = L("Verificador do cartão SD"), icon = "set_sdmaint",
      desc = L("Fabricante, modelo, classe de velocidade e data que o próprio cartão informa, pistas de cartão falsificado e teste rápido de velocidade."),
      on_a = function() App.push("sdcheck") end }
    return rows
  end
  return {
    id = "storage", icon = "set_storage", color = "yellow",
    name = L("Armazenamento"),
    desc = L("Cartão microSD, memória, cache e arquivos."),
    status = function()
      return App.free and (U.format_bytes(App.free) .. I18N.tr(L(" livres"))) or I18N.tr(L("Cartão microSD"))
    end,
    -- leitura depois do 1o quadro (a tela abre na hora)
    enter = function(scr) scr.sinfo = nil; scr.sload = 2; scr.csize = covers_size(); scr.cmiss = nil end,
    resume = function(scr) scr.csize = covers_size(); scr.sinfo = nil; scr.sload = 2; scr.cmiss = nil end,
    update = function(dt, scr)
      if scr.sload then
        scr.sload = scr.sload - 1
        if scr.sload <= 0 then
          scr.sload = nil
          scr.sinfo = SysInfo.collect()
          scr.cmiss = #require("core.covers").missing(require("core.catalog").ports)
          scr:rebuild()
        end
      end
    end,
    rows = rows_for,
  }
end

-- ---------------------------------------------------------------------------
-- DIAGNOSTICO E SUPORTE
--- registro de erros: abre o leitor direto no arquivo mais recente.
--- Esquerda/direita troca de arquivo; B volta para Diagnostico e suporte.
local function errlog_open()
  local dir = require("core.errlog").dir()
  local out = U.capture("ls -1t " .. U.shq(dir) .. " 2>/dev/null | grep -E '^(erro_|problemas_|relatorio_suporte_).*\\.txt$'") or ""
  local files = {}
  for name in out:gmatch("[^\n]+") do files[#files + 1] = { name = name, path = dir .. "/" .. name } end
  if #files == 0 then App.toast(L("Nenhum erro registrado até agora."), "info"); return end
  App.push("textview", { title = L("Registro de erros"), files = files, idx = 1 })
end

local function run_diag()
  local Diag = require("core.diag")
  local last
  local function build(scr)
    last = Diag.run()
    local items = {}
    for _, e in ipairs(last) do
      local tg = STATE_TAG[e.state] or STATE_TAG.ok
      items[#items + 1] = { tag = tg[1], tagc = tg[2](), text = I18N.tr(e.area), sub = I18N.tr(e.text), detail = I18N.tr(e.text) }
    end
    scr.items = items
  end
  infolist({ title = L("Diagnóstico do aplicativo"), sub = L("Somente leitura"), load = build,
    keys = {
      { key = "y", label = L("Verificar de novo"), fn = function(scr) build(scr); App.toast(L("Diagnóstico atualizado."), "info") end },
      { key = "x", label = L("Exportar relatório"), fn = function()
        local path = require("core.errlog").report(Diag.text(last))
        if path then
          App.show_dialog({ title = L("Relatório exportado"), kind = "ok",
            body = L("O relatório para o suporte foi salvo em:\n") .. path .. L("\n\nCopie pelo FTP ou pelo Gerenciador de arquivos. Senhas não entram no relatório.") })
        else
          App.show_dialog({ title = L("Não foi possível exportar"), kind = "error", body = L("Não foi possível gravar o relatório na pasta logs.") })
        end
      end },
    } })
end

function X.diag_category()
  return {
    id = "diag", icon = "set_diag", color = "red",
    name = L("Diagnóstico e suporte"),
    desc = L("Verificações do app, registros e relatório."),
    status = function()
      local n = require("core.errlog").count()
      return n == 0 and I18N.tr(L("nenhum erro registrado")) or string.format(I18N.tr(L("%d arquivo(s) de erro")), n)
    end,
    rows = {
      { kind = "action", label = L("Executar diagnóstico"),
        desc = L("Verifica catálogo, downloads, ports instalados, FTP, atualizações, ferramentas do sistema e registros. X exporta um relatório para o suporte."),
        on_a = run_diag },
      { kind = "action", label = L("Registro de erros"), icon = "set_console",
        desc = L("Erros e avisos do R36S PORT HUB e relatórios para o suporte. A abre o mais recente para ler; esquerda/direita troca de arquivo e B volta para esta tela."),
        value = function()
          local n = require("core.errlog").count()
          return n == 0 and L("nenhum erro registrado") or string.format(I18N.tr(L("%d arquivo(s)")), n)
        end,
        on_a = errlog_open },
      { kind = "action", label = L("Histórico de erros de comunicação"),
        desc = L("Últimas falhas do hub ao acessar a internet: catálogo, atualizações, downloads e repositórios."),
        value = function()
          local n = require("core.netlog").count()
          return n == 0 and L("nenhum") or string.format(I18N.tr(L("%d registro(s)")), n)
        end,
        on_a = net_history },
      { kind = "action", label = L("Componentes do hub"),
        desc = L("Confere o pacote do app, o script de downloads, o 7-Zip e as ferramentas do sistema usadas pelo hub, com as versões."),
        on_a = hub_modules },
      { kind = "info", label = L("Informações para o suporte"),
        desc = L("Ao pedir ajuda, envie o relatório exportado e o arquivo de erro (pasta logs). Eles trazem a versão, o sistema e as últimas linhas do registro, sem senhas."),
        value = function() return "v" .. C.VERSION end },
    },
  }
end

-- ---------------------------------------------------------------------------
-- SOBRE O PROJETO
function X.about_category()
  return {
    id = "about", icon = "set_about", color = "accent",
    name = L("Sobre o projeto"),
    desc = L("Versão, desenvolvedor, créditos, licenças e avisos."),
    status = function() return "R36S PORT HUB  •  v" .. C.VERSION end,
    rows = {
      { kind = "info", label = L("Nome"), desc = L("Nome do aplicativo."), value = function() return "R36S PORT HUB" end },
      { kind = "info", label = L("Versão"), desc = L("Versão instalada."), value = function() return C.VERSION end },
      { kind = "info", label = L("Desenvolvedor"), desc = L("Criador e mantenedor do projeto."), value = function() return "LagdoLira" end },
      { kind = "action", label = L("Sobre o R36S PORT HUB"),
        desc = L("Apresentação do projeto, créditos, canal do YouTube e apoio ao projeto."),
        on_a = function() App.push("about") end },
      { kind = "action", label = L("Licenças"),
        desc = L("Licenças dos componentes de terceiros incluídos no hub (pasta licenses)."),
        on_a = function() App.push("files", { path = C.APP_DIR .. "/licenses" }) end },
      { kind = "action", label = L("Aviso importante"),
        desc = L("O aviso legal mostrado ao abrir o hub: jogos, ports e BIOS pertencem aos seus autores."),
        on_a = function() App.push("disclaimer", { view_only = true }) end },
      { kind = "info", label = L("Comunidade"),
        desc = L("Novidades, vídeos e suporte pelo canal do YouTube. O grupo da comunidade será adicionado numa próxima versão."),
        value = function() return "youtube.com/@lagdolira" end },
    },
  }
end

return X
