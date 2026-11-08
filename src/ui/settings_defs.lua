-- =============================================================================
--  Categorias de Configuracoes: o que cada uma mostra e faz.
--  Usado pela central (ui/screens/settings.lua) e pela tela de cada categoria
--  (ui/screens/settings_cat.lua). Todo controle executa uma acao real; dados
--  que o sistema nao informa nao aparecem (ou aparecem como "Não disponível").
--
--  Tipos de linha:
--    toggle  get() -> bool, set(bool)
--    slider  get() -> 0..100, nudge(-1|1), available() opcional, unit opcional
--    value   value() -> texto em etiqueta, on_a()          (lista / escolha)
--    action  value() opcional (texto discreto), on_a()     (abre / executa)
--    info    value() -> texto, color() opcional            (somente leitura)
--  label/desc podem ser texto ou funcao; enabled() opcional (linha esmaecida).
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local U = require("lib.util")
local C = require("config")
local Prefs = require("core.prefs")
local Music = require("core.music")
local Sfx = require("core.sfx")
local Brightness = require("core.brightness")
local Themes = require("core.themes")
local Net = require("core.net")
local Ftp = require("core.ftp")
local Battery = require("core.battery")
local Catalog = require("core.catalog")
local Cats = require("core.categories")
local Downloads = require("core.downloads")
local Runtimes = require("core.runtimes")
local Backup = require("core.backup")
local SysInfo = require("core.sysinfo")
local X = require("ui.settings_extra")

local D = {}

local function theme_name()
  local cur = Themes.by_id and Themes.by_id[Themes.current]
  return L(cur and cur.name or "Tema Padrão")
end

local function lang_name()
  for _, l in ipairs(I18N.LANGS) do if l.id == I18N.lang then return l.short end end
  return "?"
end

local function fmt_date(t) return require("core.clock").datetime(t) end

-- ---------------------------------------------------------------------------
-- APARENCIA E PERSONALIZACAO
local appearance = {
  id = "appearance", icon = "set_appearance", color = "accent",
  name = L("Aparência e personalização"),
  desc = L("Tema, texto, brilho e animações."),
  status = function()
    local fl = ""
    for _, l in ipairs(T.FONT_LEVELS) do if l.id == T.font_level then fl = I18N.tr(l.label) end end
    return theme_name() .. (fl ~= "" and ("  •  " .. fl) or "")
  end,
  enter = function() if not Brightness.checked then Brightness.detect() end end,
  update = function(dt)
    local ok, why = Brightness.update(dt)
    if ok == false then App.toast(L("O brilho não pôde ser alterado: ") .. tostring(why), "error") end
  end,
  rows = {
    { kind = "value", label = L("Tema"), desc = L("Escolha a aparência do R36S PORT HUB. A mudança vale na hora."),
      value = theme_name, on_a = function() App.push("themes") end },
    { kind = "value", label = L("Tamanho do texto"), icon = "set_text",
      desc = L("Esquerda/direita aumenta ou diminui o texto de todo o aplicativo. Se um texto não couber no espaço da tela, ele diminui sozinho até o tamanho padrão e, se ainda assim não couber, é encurtado com reticências. A escolha fica salva."),
      value = function()
        for _, l in ipairs(T.FONT_LEVELS) do
          if l.id == T.font_level then return I18N.tr(l.label) end
        end
        return "?"
      end,
      nudge = function(dir, wrap)
        local cur = 2
        for i, l in ipairs(T.FONT_LEVELS) do if l.id == T.font_level then cur = i end end
        local n = #T.FONT_LEVELS
        local nxt = cur + dir
        if wrap then nxt = (nxt - 1) % n + 1 end
        if nxt < 1 or nxt > n then return end
        App.set_font_level(T.FONT_LEVELS[nxt].id)
      end,
      on_a = function(scr) end },
    { kind = "slider", label = L("Brilho da tela"),
      desc = function()
        if not Brightness.available then
          return L("Não foi possível controlar o brilho neste sistema:") .. " " .. I18N.tr(Brightness.reason or "")
        end
        return L("Esquerda/direita ajusta o brilho (5% a 100%). A escolha fica salva.")
      end,
      available = function() return Brightness.available end,
      get = function() return Brightness.display_value() end,
      min = 5,
      nudge = function(dir)
        if not Brightness.available then
          App.toast(L("Controle de brilho indisponível: ") .. I18N.tr(Brightness.reason or ""), "warn")
          return
        end
        Brightness.nudge(dir)
      end },
    { kind = "action", label = L("Ajustes do console (R36 Control)"), icon = "set_led",
      desc = L("LED de aviso da bateria, correção de gama, saída de áudio e volume ao ligar (mesmos ajustes do R36 Control do dArkOSRE)."),
      value = function() return "R36 Control" end,
      on_a = function() App.push("r36control") end },
    { kind = "toggle", label = L("Animações da interface"),
      desc = function()
        local d = L("Pulsos de destaque e troca automática do destaque no menu. Desligadas, economizam processamento.")
        if App.eco then d = d .. " " .. L("O modo econômico está ligado e mantém as animações desligadas.") end
        return d
      end,
      get = function() return App.anim end,
      set = function(v) App.anim = v; Prefs.set("anim", v and "1" or "0") end },
    { kind = "action", label = L("Restaurar aparência original"),
      desc = L("Volta ao Tema Padrão, ao tamanho de texto padrão e liga as animações. Brilho e idioma não mudam."),
      on_a = function()
        App.show_dialog({ title = L("Restaurar aparência?"), kind = "warn",
          body = L("O hub volta ao Tema Padrão, com o tamanho de texto padrão e as animações ligadas."),
          buttons = { { label = L("RESTAURAR"), fn = function()
            if Themes.current ~= Themes.DEFAULT then Themes.apply(Themes.DEFAULT, true) end
            App.set_font_level("normal")
            App.anim = true; Prefs.set("anim", "1")
            App.toast(L("Aparência original restaurada."), "ok")
          end }, { label = L("CANCELAR") } } })
      end },
  },
}

-- ---------------------------------------------------------------------------
-- AUDIO
local audio = {
  id = "audio", icon = "set_audio", color = "yellow",
  name = L("Áudio"),
  desc = L("Música de fundo e efeitos sonoros."),
  status = function()
    return Music.enabled and string.format(L("Música %d%%"), Music.volume_pct()) or L("Música desligada")
  end,
  rows = {
    { kind = "toggle", label = L("Música de fundo"), desc = L("Trilha sonora do R36S PORT HUB. A escolha fica salva no console."),
      get = function() return Music.enabled end, set = function(v) Music.set_enabled(v) end },
    { kind = "slider", label = L("Volume da música"), desc = L("Esquerda/direita ajusta o volume da trilha sonora. A escolha fica salva."),
      enabled = function() return Music.enabled end,
      get = function() return Music.volume_pct() end,
      nudge = function(dir) Music.set_volume_pct(math.floor(Music.volume_pct() / 5 + 0.5) * 5 + dir * 5) end },
    { kind = "toggle", label = L("Efeitos sonoros"), desc = L("Sons curtos ao navegar, confirmar e voltar."),
      get = function() return Sfx.enabled end,
      set = function(v) Sfx.set_enabled(v); if v then Sfx.preview() end end },
    { kind = "slider", label = L("Volume dos efeitos"), desc = L("Esquerda/direita ajusta o volume dos efeitos e das notificações. Um som de teste toca a cada ajuste."),
      get = function() return Sfx.volume end,
      nudge = function(dir) Sfx.set_volume(math.floor(Sfx.volume / 5 + 0.5) * 5 + dir * 5); Sfx.preview() end },
  },
}

-- ---------------------------------------------------------------------------
-- REDE E CONECTIVIDADE
local function net() return Net.current() end
local network = {
  id = "network", icon = "set_network", color = "accent2",
  name = L("Rede e conectividade"),
  desc = L("Wi-Fi, IP local, diagnóstico, repositórios e transmissão."),
  status = function()
    local st = net()
    local s
    if not st then s = L("Verificando...")
    elseif st.connected then s = L("Conectado") .. (st.ip and ("  •  " .. st.ip) or "")
    else s = L("Desconectado") end
    if Ftp.state == "on" then s = s .. "  •  FTP" end
    local St, Rc = package.loaded["core.stream"], package.loaded["core.recorder"]
    if St and St.state == "on" then s = s .. "  •  " .. L("AO VIVO") end
    if Rc and Rc.recording() then s = s .. "  •  REC" end
    return s
  end,
  -- detalhes da conexao (nome da rede, gateway, DNS) vem do NetworkManager em
  -- segundo plano, a cada 6 s, so enquanto esta categoria esta aberta
  enter = function(scr) scr.wjob = require("core.wifijob").start("status"); scr.wt = 0 end,
  resume = function(scr) scr.wt = 99 end,
  update = function(dt, scr)
    local J = require("core.wifijob")
    if scr.wjob then
      local r = J.poll(scr.wjob)
      if r then scr.wjob = nil; scr.wst = r.status; Net.invalidate() end
    else
      scr.wt = (scr.wt or 0) + dt
      if scr.wt > 6 then scr.wt = 0; scr.wjob = J.start("status") end
    end
  end,
  rows = {
    { kind = "action", label = L("Gerenciar Wi-Fi"), icon = "set_network",
      desc = L("Pesquise redes próximas, selecione uma rede e conecte seu console à internet."),
      value = function(scr)
        local w = scr.wst
        if not w then return "" end
        if not w.nmcli then return L("indisponível") end
        if w.radio == false then return L("Wi-Fi desativado") end
        return w.connected and (w.connection or "") or L("não conectado")
      end,
      on_a = function() App.push("wifi") end },
    { kind = "info", label = L("Rede Wi-Fi"), desc = L("Nome da rede Wi-Fi conectada, informado pelo NetworkManager."),
      value = function(scr)
        local w = scr.wst
        if not w then return L("Verificando...") end
        return (w.connected and w.connection) or "—"
      end },
    { kind = "info", label = L("Sinal"), desc = L("Intensidade do sinal Wi-Fi informada pelo sistema."),
      value = function(scr)
        local st = net()
        local iface = (scr.wst and scr.wst.iface) or (st and st.iface)
        if not (st and st.connected and st.wireless) then return "—" end
        local now = love.timer.getTime()
        if not scr.sig_t or now - scr.sig_t > 3 then scr.sig_t = now; scr.sig = Net.signal(iface) end
        local s = scr.sig
        return s and (s.quality .. "%" .. (s.dbm and string.format("  (%d dBm)", s.dbm) or "")) or L("Não disponível")
      end },
    { kind = "info", label = L("Conexão"), desc = L("Estado da rede, atualizado sozinho a cada poucos segundos."),
      value = function()
        local st = net()
        if not st then return L("Verificando...") end
        return st.connected and L("CONECTADO") or L("DESCONECTADO")
      end,
      color = function() local st = net(); return st and (st.connected and T.c.green or T.c.red) or T.c.dim end },
    { kind = "info", label = L("IP local"), desc = L("Endereço do console na rede local (usado pelo FTP)."),
      value = function() local st = net(); return st and st.ip or "—" end },
    { kind = "action", label = L("Diagnóstico de rede"),
      desc = L("Todos os detalhes da conexão (interface, gateway, DNS, sinal) e testes de acesso à internet e ao GitHub."),
      on_a = function() App.push("netdiag") end },
    { kind = "action", label = L("Velocidade da internet"),
      desc = L("Mede latência, download e upload com os servidores do teste da Cloudflare. Usa cerca de 33 MB de dados por teste."),
      value = function()
        local dn, _, _, tm = (Prefs.get("speed_last") or ""):match("^(%-?%d+)|(%-?%d+)|(%-?%d+)|(%d+)$")
        if not dn then return L("nunca testada") end
        return string.format("%.1f Mbps", tonumber(dn) * 8 / 1000000) .. "  •  " .. require("core.clock").date(tonumber(tm), true)
      end,
      on_a = function() App.push("netdiag", { speed = true }) end },
    { kind = "action", label = L("Transmissão e gravação"),
      desc = L("Veja a tela do hub ao vivo no navegador do computador (rede local) e grave vídeos da interface no cartão SD."),
      value = function()
        local St, Rc = package.loaded["core.stream"], package.loaded["core.recorder"]
        local t = {}
        if St and St.state == "on" then t[#t + 1] = L("AO VIVO") end
        if Rc and Rc.recording() then t[#t + 1] = Rc.state == "paused" and L("PAUSADA") or L("GRAVANDO") end
        return #t > 0 and table.concat(t, "  •  ") or L("desligadas")
      end,
      on_a = function() App.push("streamrec") end },
    X.network_extra_rows()[1],
  },
}

-- ---------------------------------------------------------------------------
-- BATERIA E ENERGIA
local HEALTH = { good = L("Boa"), overheat = L("Superaquecida"), dead = L("Esgotada"), cold = L("Fria"),
  ["over voltage"] = L("Tensão alta"), unknown = L("Desconhecida") }
local battery = {
  id = "battery", icon = "set_battery", color = "green",
  name = L("Bateria e energia"),
  desc = L("Carga, carregamento, análise da bateria e modo econômico."),
  status = function()
    local b = Battery.get()
    if not b.ok then return L("Bateria indisponível") end
    return b.pct .. "%  •  " .. (b.charging and L("Carregando") or (b.full and L("Carga completa") or L("Na bateria")))
  end,
  enter = function(scr) Battery.info = nil; scr.bat = Battery.details(); scr.bat_t = 0 end,
  update = function(dt, scr)
    scr.bat_t = (scr.bat_t or 0) + dt
    if scr.bat_t > 10 then scr.bat_t = 0; scr.bat = Battery.details(); Battery.info = nil end
  end,
  rows = function(scr)
    local rows = {
      { kind = "info", label = L("Carga"), desc = L("Percentual informado pelo sistema."),
        value = function() local b = Battery.get(); return b.ok and (b.pct .. "%") or L("Não disponível") end,
        color = function()
          local b = Battery.get()
          if not b.ok then return T.c.dim end
          return b.pct < 15 and T.c.red or (b.pct < 40 and T.c.yellow or T.c.green)
        end },
      { kind = "info", label = L("Estado"), desc = L("Situação do carregamento."),
        value = function()
          local b = Battery.get()
          if not b.ok then return L("Não disponível") end
          if b.charging then return L("Carregando") end
          if b.full then return L("Carga completa") end
          return L("Descarregando")
        end },
    }
    local d = scr.bat or {}
    if d.charger then
      rows[#rows + 1] = { kind = "info", label = L("Alimentação"), desc = L("Fonte de energia informada pelo sistema."),
        value = function()
          local c = (scr.bat or {}).charger
          if not c then return L("Não disponível") end
          return c.online and (L("Carregador conectado") .. (c.type ~= "" and (" (" .. c.type .. ")") or "")) or L("Somente bateria")
        end }
    end
    if d.voltage then
      rows[#rows + 1] = { kind = "info", label = L("Tensão"), desc = L("Tensão atual da bateria."),
        value = function() local v = (scr.bat or {}).voltage; return v and string.format(L("%.2f V"), v) or L("Não disponível") end }
    end
    if d.health then
      rows[#rows + 1] = { kind = "info", label = L("Saúde"), desc = L("Condição da bateria informada pelo sistema."),
        value = function() local h = (scr.bat or {}).health or ""; return HEALTH[h:lower()] or h end }
    end
    if d.temp then
      rows[#rows + 1] = { kind = "info", label = L("Temperatura da bateria"), desc = L("Temperatura informada pelo sensor da bateria."),
        value = function() local t = (scr.bat or {}).temp; return t and string.format("%.1f °C", t) or L("Não disponível") end }
    end
    rows[#rows + 1] = { kind = "action", label = L("Análise da bateria"), icon = "set_battery",
      desc = L("Nível, estado, tensão, corrente e capacidade que o sistema informa, e o tempo estimado para a carga completa. Somente leitura."),
      on_a = function() App.push("battery") end }
    rows[#rows + 1] = { kind = "toggle", label = L("Modo econômico"),
      desc = L("Reduz a tela de 30 para 20 quadros por segundo e desliga as animações decorativas, diminuindo o uso do processador. Não altera o brilho."),
      get = function() return App.eco end,
      set = function(v) App.eco = v; Prefs.set("eco", v and "1" or "0") end }
    return rows
  end,
}

-- ---------------------------------------------------------------------------
-- CONTROLES
local BUTTON_MAP = function()
  return L("Direcional / analógico esquerdo: navegar") .. "\n"
    .. L("A: selecionar / confirmar") .. "\n"
    .. L("B: voltar / cancelar") .. "\n"
    .. L("X: excluir, limpar ou cancelar (conforme a tela)") .. "\n"
    .. L("Y: atualizar ou ação extra (conforme a tela)") .. "\n"
    .. L("L1 / R1: trocar aba ou categoria") .. "\n"
    .. L("SELECT: favoritar") .. "\n"
    .. L("START: Central de Downloads (em Sobre: apoiar o projeto)") .. "\n"
    .. L("FN: salvar um print da tela")
end
local controls = {
  id = "controls", icon = "set_controls", color = "orange",
  name = L("Controles"),
  desc = L("Teste de analógicos e botões, relatório e mapa dos botões."),
  status = function() return "R36S Analog Tester" end,
  enter = function(scr) scr.rep_text = U.read_file(C.APP_DIR .. "/tools/r36s_analog_tester/relatorio_controles.txt") end,
  resume = function(scr) scr.rep_text = U.read_file(C.APP_DIR .. "/tools/r36s_analog_tester/relatorio_controles.txt") end,
  rows = {
    { kind = "action", label = L("Testar analógicos e botões"),
      desc = L("Abre o R36S Analog Tester (por LagdoLira): analógicos, zona morta, deriva e todos os botões. O hub fecha durante o teste e volta sozinho quando você sair."),
      value = function() return "R36S Analog Tester" end,
      on_a = function() App.push("tester", { from = "settings" }) end },
    { kind = "info", label = L("Último relatório"), desc = L("Resultado salvo pelo R36S Analog Tester na última vez que você voltou ao menu dele."),
      value = function(scr)
        local t = scr.rep_text
        if not t then return L("Nenhum ainda") end
        local d = t:match("\n(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d)")
        local y, mo, da, hm = (d or ""):match("(%d+)%-(%d+)%-(%d+) (%d+:%d+)")
        local ok = t:find("Nenhuma falha detectada.", 1, true)
        return (y and (da .. "/" .. mo .. " " .. hm .. "  •  ") or "") .. (ok and L("sem falhas") or L("com pendências"))
      end,
      color = function(scr)
        local t = scr.rep_text
        if not t then return T.c.dim end
        return t:find("Nenhuma falha detectada.", 1, true) and T.c.green or T.c.yellow
      end },
    { kind = "action", label = L("Todos os testes de controles"), desc = L("Lista de testes de controles da loja, com os três tipos identificados."),
      on_a = function() App.push("store", { section = "tools", filter = "cat:testes_de_controles" }) end },
    { kind = "action", label = L("Mapa dos botões"), desc = L("O que cada botão do R36S faz no R36S PORT HUB."),
      on_a = function()
        App.show_dialog({ title = L("Mapa dos botões"), kind = "info", body = BUTTON_MAP() })
      end },
  },
}

-- ---------------------------------------------------------------------------
-- DOWNLOADS E ATUALIZACOES
local function dl_status()
  local act = Downloads.active()
  local w = Downloads.waiting_count()
  if not act and w == 0 then return L("nada em andamento") end
  local s = act and L("1 em andamento") or ""
  if w > 0 then s = s .. (s ~= "" and "  •  " or "") .. string.format(L("%d na fila"), w) end
  return s
end
local runtimes_row = { kind = "action", label = L("Atualizar runtimes"),
      desc = function(scr)
        local where = scr.pm and (L("PortMaster: ") .. scr.pm .. "/libs") or L("PortMaster não encontrado neste console")
        return L("Pacote: ") .. C.RUNTIMES_ZIP_NAME .. L("  (release ") .. C.RUNTIMES_RELEASE .. L(")  •  backup e md5 de cada arquivo") .. "\n" .. where
      end,
      value = function(scr) return scr.pm and "PortMaster" or L("PortMaster não encontrado") end,
      on_a = function(scr)
        if not scr.pm then
          App.show_dialog({ title = L("PortMaster não encontrado"), kind = "error",
            body = L("Instale o PortMaster no console antes de atualizar os runtimes.\nPastas verificadas: ") .. C.PORTS_DIR .. "/PortMaster, /opt/system/Tools/PortMaster e /opt/tools/PortMaster." })
          return
        end
        App.show_dialog({
          title = L("Atualizar runtimes"), kind = "info",
          body = L("O hub vai conferir os runtimes instalados em:\n") .. scr.pm .. "/libs\n\n"
            .. L("Se houver novos ou desatualizados, você verá a lista e o tamanho do download (o pacote completo tem cerca de 1,95 GB) antes de qualquer alteração. Conecte o console à energia e ao Wi-Fi."),
          buttons = { { label = L("VERIFICAR"), fn = App.update_runtimes }, { label = "VOLTAR" } },
        })
      end }

local downloads = {
  id = "downloads", icon = "set_downloads", color = "accent2",
  name = L("Downloads"),
  desc = L("Fila, progresso, histórico, avisos e falhas."),
  status = dl_status,
  rows = X.downloads_rows(dl_status),
}

-- ---------------------------------------------------------------------------
-- BACKUP E RESTAURACAO
local function backup_status()
  local info = Backup.info()
  return info and (L("Último: ") .. require("core.clock").datetime(info.time, true)) or L("Nenhum backup ainda")
end
local function group_names(groups)
  local t = {}
  for _, g in ipairs(groups) do
    local def = Backup.BY_ID[g.id or g]
    if def then t[#t + 1] = L(def.label) end
  end
  return table.concat(t, ", ")
end
local function do_backup(scr)
  local ok, res = Backup.create(Backup.selected())
  if ok then
    scr.binfo = Backup.info()
    App.toast(string.format(L("Backup concluído: %d arquivo(s)."), res), "ok")
  else
    App.show_dialog({ title = L("Backup não realizado"), kind = "error", body = res })
  end
end
local function do_restore(scr)
  local info = Backup.info()
  if not info then App.toast(L("Nenhum backup encontrado."), "warn"); return end
  local has = {}
  for _, g in ipairs(info.groups) do has[g.id] = true end
  if (has.history and (Downloads.active() or Downloads.waiting_count() > 0)) then
    App.show_dialog({ title = L("Aguarde"), kind = "warn", body = L("Aguarde os downloads e instalações em andamento terminarem.") })
    return
  end
  if has.ftp and Ftp.running() then
    App.show_dialog({ title = L("Aguarde"), kind = "warn", body = L("Pare o servidor FTP antes de restaurar a configuração do FTP.") })
    return
  end
  App.show_dialog({
    title = L("Restaurar backup?"), kind = "warn",
    body = L("Backup de ") .. fmt_date(info.time) .. " (v" .. tostring(info.version or "?") .. ")\n\n"
      .. L("Serão substituídos: ") .. group_names(info.groups) .. ".\n\n"
      .. L("Os ports instalados e os arquivos dos jogos não são alterados."),
    buttons = {
      { label = L("RESTAURAR"), fn = function()
        local ok, done = Backup.restore()
        if ok then
          App.apply_restored(done)
          if scr.rebuild then scr:rebuild() end
          App.toast(L("Backup restaurado."), "ok")
        else
          App.show_dialog({ title = L("Falha na restauração"), kind = "error", body = done })
        end
      end },
      { label = L("CANCELAR") },
    },
  })
end
local backup = {
  id = "backup", icon = "set_backup", color = "green",
  name = L("Backup e restauração"),
  desc = L("Salvar, restaurar, exportar e importar configurações."),
  status = backup_status,
  enter = function(scr) scr.binfo = Backup.info(); scr.bsel = Backup.selected() end,
  rows = function(scr)
    local rows = {
      { kind = "info", label = L("Último backup"), desc = L("Data do backup guardado na pasta de dados do app."),
        value = function() return scr.binfo and fmt_date(scr.binfo.time) or L("Nenhum backup ainda") end,
        color = function() return scr.binfo and T.c.text or T.c.dim end },
    }
    for _, g in ipairs(Backup.GROUPS) do
      rows[#rows + 1] = { kind = "toggle", label = L("Incluir: ") .. L(g.label), desc = L(g.desc),
        get = function() return scr.bsel[g.id] == true end,
        set = function(v) scr.bsel[g.id] = v or nil; Backup.set_selected(scr.bsel) end }
    end
    rows[#rows + 1] = { kind = "action", label = L("Fazer backup agora"),
      desc = L("Copia os itens marcados acima. Os ports instalados e os arquivos dos jogos não entram no backup."),
      on_a = function()
        if scr.binfo then
          App.show_dialog({ title = L("Substituir o backup?"), kind = "warn",
            body = L("Já existe um backup de ") .. fmt_date(scr.binfo.time) .. L(". Ele será substituído pelo novo."),
            buttons = { { label = L("SUBSTITUIR"), fn = function() do_backup(scr) end }, { label = L("CANCELAR") } } })
        else
          do_backup(scr)
        end
      end }
    rows[#rows + 1] = { kind = "action", label = L("Restaurar backup"),
      desc = L("Volta as configurações salvas no último backup. Pede confirmação antes de substituir."),
      enabled = function() return scr.binfo ~= nil end,
      on_a = function() do_restore(scr) end }
    rows[#rows + 1] = { kind = "action", label = L("Exportar para o cartão"),
      desc = function()
        return L("Grava uma cópia dos itens marcados acima numa pasta nova, que dá para copiar pelo FTP ou guardar no PC:\n")
          .. Backup.EXPORT_DIR .. L("\nA senha do FTP nunca é exportada. Jogos, BIOS e saves não entram.")
      end,
      on_a = function()
        local ok, name, n = Backup.export(scr.bsel)
        if ok then
          App.show_dialog({ title = L("Preferências exportadas"), kind = "ok",
            body = string.format(L("%d arquivo(s) exportado(s) para:\n"), n) .. Backup.EXPORT_DIR .. "/" .. name })
        else
          App.show_dialog({ title = L("Não foi possível exportar"), kind = "error", body = name })
        end
      end }
    rows[#rows + 1] = { kind = "action", label = L("Importar do cartão"),
      desc = function() return L("Restaura uma das exportações da pasta:\n") .. Backup.EXPORT_DIR .. L("\nPede confirmação antes de substituir.") end,
      value = function() local n = #Backup.exports(); return n == 0 and L("nenhuma exportação") or string.format(I18N.tr(L("%d exportação(ões)")), n) end,
      on_a = function()
        local list = Backup.exports()
        if #list == 0 then App.toast(L("Nenhuma exportação encontrada na pasta configuracoes."), "info"); return end
        if Downloads.active() or Downloads.waiting_count() > 0 or Ftp.running() then
          App.show_dialog({ title = L("Aguarde"), kind = "warn", body = L("Pare o FTP e aguarde os downloads terminarem antes de importar.") })
          return
        end
        local buttons = {}
        for k = 1, math.min(5, #list) do
          local e = list[k]
          buttons[#buttons + 1] = { label = require("core.clock").datetime(e.time, true), sub = "v" .. tostring(e.version or "?") .. "  •  " .. group_names(e.groups),
            fn = function()
              App.show_dialog({ title = L("Importar estas preferências?"), kind = "warn",
                body = L("Exportação de ") .. fmt_date(e.time) .. " (v" .. tostring(e.version or "?") .. ")\n\n" .. L("Serão substituídos: ")
                  .. group_names(e.groups) .. ".\n\n" .. L("Os ports instalados e os arquivos dos jogos não são alterados."),
                buttons = { { label = L("IMPORTAR"), fn = function()
                  local ok, done = Backup.import(e.name)
                  if ok then
                    App.apply_restored(done)
                    if scr.rebuild then scr:rebuild() end
                    App.toast(L("Preferências importadas."), "ok")
                  else
                    App.show_dialog({ title = L("Falha na importação"), kind = "error", body = done })
                  end
                end }, { label = L("CANCELAR") } } })
            end }
        end
        buttons[#buttons + 1] = { label = L("Voltar") }
        App.show_dialog({ title = L("Importar do cartão"), kind = "info", list = true, body = L("Escolha a exportação:"), buttons = buttons })
      end }
    rows[#rows + 1] = { kind = "action", label = L("Histórico de backups"),
      desc = L("Backup interno e exportações encontradas no cartão, com data, versão e itens."),
      on_a = function()
        local items = {}
        local info = Backup.info()
        if info then
          items[#items + 1] = { tag = L("INTERNO"), tagc = T.c.accent2, text = fmt_date(info.time),
            sub = "v" .. tostring(info.version or "?") .. "  •  " .. group_names(info.groups) }
        end
        for _, e in ipairs(Backup.exports()) do
          items[#items + 1] = { tag = L("CARTÃO"), tagc = T.c.green, text = fmt_date(e.time),
            sub = "v" .. tostring(e.version or "?") .. "  •  " .. group_names(e.groups), detail = Backup.EXPORT_DIR .. "/" .. e.name }
        end
        App.push("infolist", { title = L("Histórico de backups"), items = items, empty = L("Nenhum backup ainda.") })
      end }
    return rows
  end,
}

-- ---------------------------------------------------------------------------
-- NOTIFICACOES
local function pref_on(k) return Prefs.get(k) ~= "0" end
local notifications = {
  id = "notifications", icon = "set_notify", color = "yellow",
  name = L("Notificações"),
  desc = L("Mensagens rápidas na tela e som de aviso."),
  status = function() return pref_on("notif") and L("Ativadas") or L("Desativadas") end,
  rows = {
    { kind = "toggle", label = L("Notificações na tela"),
      desc = L("Mensagens rápidas no rodapé da tela. Janelas de confirmação sempre aparecem."),
      get = function() return pref_on("notif") end, set = function(v) Prefs.set("notif", v and "1" or "0") end },
    { kind = "toggle", label = L("Confirmações e informações"),
      desc = L("Ex.: download adicionado, catálogo atualizado, print salvo."),
      enabled = function() return pref_on("notif") end,
      get = function() return pref_on("notif_info") end, set = function(v) Prefs.set("notif_info", v and "1" or "0") end },
    { kind = "toggle", label = L("Alertas e erros"),
      desc = L("Ex.: falha de conexão, espaço insuficiente, brilho indisponível."),
      enabled = function() return pref_on("notif") end,
      get = function() return pref_on("notif_alert") end, set = function(v) Prefs.set("notif_alert", v and "1" or "0") end },
    { kind = "toggle", label = L("Som das notificações"),
      desc = L("Toca um aviso curto quando uma notificação aparece."),
      get = function() return Sfx.notif end, set = function(v) Sfx.set_notify(v); if v then Sfx.notify("info") end end },
    { kind = "action", label = L("Testar notificação"), desc = L("Mostra uma notificação de exemplo com as opções atuais."),
      on_a = function() App.toast(L("Esta é uma notificação de teste."), "info") end },
  },
}

-- processador e resolucao (lidos do sistema; so o que for identificado)
local function cpu_text()
  local n = 0
  for _ in (U.read_file("/proc/cpuinfo") or ""):gmatch("\nprocessor%s*:") do n = n + 1 end
  if (U.read_file("/proc/cpuinfo") or ""):match("^processor%s*:") then n = n + 1 end
  local mhz = tonumber(U.trim(U.read_file("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq") or ""))
  local last = require("core.consoleid").load_last()
  local name = last and last.info and last.info.cpu or nil
  local t = {}
  if name then t[#t + 1] = name end
  if n > 0 then t[#t + 1] = string.format(I18N.tr(L("%d núcleos")), n) end
  if mhz then t[#t + 1] = string.format("%.2f GHz", mhz / 1000000) end
  return #t > 0 and table.concat(t, "  •  ") or SysInfo.NA
end
local function resolution_text()
  local m = U.capture("cat /sys/class/drm/card*-*/modes 2>/dev/null | head -n 1") or ""
  m = m:match("(%d+x%d+)")
  if m then return m end
  local okd, w, h = pcall(love.window.getDesktopDimensions)
  if okd and w and w > 0 then return w .. "x" .. h end
  return SysInfo.NA
end

-- ---------------------------------------------------------------------------
-- INFORMACOES DO CONSOLE (dados lidos so ao abrir a categoria)
local console = {
  id = "console", icon = "set_console", color = "accent",
  name = L("Informações do console"),
  desc = L("Modelo, processador, tela, sistema, data e hora."),
  status = function()
    local last = require("core.consoleid").load_last()
    return (last and last.info and last.info.model) or (C.OS_MODE and C.OS_NAME) or "R36S"
  end,
  enter = function(scr) scr.info = nil; scr.loading = 2 end,     -- coleta depois do 1o quadro desenhado
  resume = function(scr) scr:rebuild() end,
  update = function(dt, scr)
    if scr.loading then
      scr.loading = scr.loading - 1
      if scr.loading <= 0 then
        scr.loading = nil
        scr.info = SysInfo.collect()
        local okd, os_ = pcall(require("core.osdetect").detect)
        scr.osd = okd and os_ or nil
        scr.temp = SysInfo.temperature()
        scr:rebuild()
      end
    end
  end,
  rows = function(scr)
    local r = scr.info
    local last = require("core.consoleid").load_last()
    local analyzer = { kind = "action", label = L("Analisador de Console"), icon = "set_analyzer",
      desc = L("Verifique informações de hardware e tente identificar o modelo do seu aparelho."),
      value = function()
        if not last then return "" end
        return require("core.clock").datetime(last.result.time, true)
      end,
      on_a = function() App.push("consoleid") end }
    local datetime = { kind = "action", label = L("Data e hora"), icon = "set_clock",
      desc = L("Data, hora, fuso horário, sincronização pela internet e formatos de exibição."),
      value = function() local K = require("core.clock"); return K.date(nil, true) .. "  " .. K.time() end,
      on_a = function() App.push("datetime") end }
    if not r then
      return { analyzer, datetime, { kind = "info", label = L("Lendo informações..."), desc = L("Somente leitura: nada é alterado no console."),
        value = function() return "" end } }
    end
    local NA = SysInfo.NA
    local rows = {
      analyzer,
      datetime,
      { kind = "info", label = L("Dispositivo"), desc = L("Modelo informado pelo sistema."), value = function() return r.model end },
      { kind = "info", label = L("Processador"), desc = L("Processador informado pelo sistema (nome identificado pelo Analisador de Console, quando já usado)."),
        value = function() if not scr.cpu then scr.cpu = cpu_text() end return scr.cpu end },
      { kind = "info", label = L("Resolução da tela"), desc = L("Resolução informada pelo sistema de vídeo."),
        value = function() if not scr.res then scr.res = resolution_text() end return scr.res end },
      { kind = "info", label = L("Arquitetura"), desc = L("Arquitetura do processador."), value = function() return r.arch end },
      { kind = "info", label = L("Sistema"), desc = L("Sistema operacional (firmware) instalado."),
        value = function()
          local o = scr.osd
          if o and o.name and o.name ~= "" and o.id ~= "unknown" then return o.name .. ((o.version and o.version ~= "") and (" " .. o.version) or "") end
          return r.os
        end },
    }
    if scr.temp then
      rows[#rows + 1] = { kind = "info", label = L("Temperatura do processador"), desc = L("Temperatura informada pelo sensor do sistema."),
        value = function() return string.format("%.1f °C", scr.temp) end,
        color = function() return scr.temp >= 80 and T.c.red or (scr.temp >= 65 and T.c.yellow or T.c.text) end }
    end
    rows[#rows + 1] = { kind = "action", label = L("Todos os detalhes"),
      desc = L("Relatório completo do console: sistema, armazenamento, memória RAM e PortMaster."),
      on_a = function() App.push("console") end }
    return rows
  end,
}

-- notificacoes passaram para Preferencias (a tabela fica para referencia)
local _ = notifications
D.LIST = {
  X.prefs_category(), appearance, audio,
  network, X.ftp_category(),
  X.catalog_category(), downloads, X.myports_category(),
  X.storage_category(), battery, controls, console,
  X.updates_category(), X.tools_category(runtimes_row), backup,
  X.diag_category(), X.about_category(),
}
D.BY_ID = {}
for _, c in ipairs(D.LIST) do D.BY_ID[c.id] = c end

return D
