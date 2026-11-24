-- =============================================================================
--  O que o assistente fala por conta propria (com dados reais do hub)
--    B.on_screen(nome, params)  fala ao entrar em QUALQUER tela ou aba de
--                               Configuracoes (com dados reais quando ha),
--                               sempre com um gesto (aponta, acena, pensa...)
--    B.update(dt)               ports novos, versao nova do hub, lembrete das
--                               pendencias (1x por dia), dicas de tempos em tempos
--  Ritmo (Meu perfil > Falas do assistente):
--    bastante/normal: fala em toda troca de tela (a nova substitui a anterior
--    na hora); dica a cada 25 s / 45 s | pouco: 8 s entre falas, metade das
--    telas, dica a cada 2 min | em silencio: nada
--  As falas de cada tela se revezam (nao repete a mesma em seguida); trocar de
--  tela substitui o balao anterior.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local U = require("lib.util")

local B = {}
-- troca de tela: a fala nova substitui a anterior na hora (so evita repetir
-- em telas que abrem e fecham juntas); no modo "pouco", espera um pouco mais
local GAP = { often = 0.3, normal = 0.3, rare = 8 }
local CHANCE = { often = 1, normal = 1, rare = 0.5 }
local CHATTER = { often = 25, normal = 45, rare = 120 }

local last_talk = -999
local rot = {}            -- revezamento das falas por tela
local catalog_sig
local told_update = false
B.pending = nil

local function Asst() return require("core.assistant") end
local function K() return require("core.assistant.knowledge") end
local function now() return (App and App.t) or 0 end
local function tr(s) return I18N.tr(L(s)) end
local function pick(t) return t[math.random(#t)] end
B.pick = pick

local function say(text, mood, dur)
  if not text then return end
  last_talk = now()
  B.chat = nil
  pcall(function() require("lib.util").log("assistente:", text) end)
  Asst().say(text, mood, dur or math.max(3.5, math.min(7, #text / 16)))
end

-- ---------------------------------------------------------------- dados
local function catalog() local ok, C = pcall(require, "core.catalog"); return ok and C or nil end
local function battery()
  local ok, Bt = pcall(require, "core.battery")
  local i = ok and Bt.get and Bt.get() or nil
  return (type(i) == "table" and i.ok) and i or nil
end
local function wifi()
  local ok, N = pcall(require, "core.net")
  return ok and N.get and N.get(5) or nil
end
local function free() return (App and App.free) and U.format_bytes(App.free) or nil end
local function wifi_line(w)
  return w.connected and (tr("Wi-Fi conectado") .. (w.ip and (" (" .. w.ip .. ")") or "") .. ".") or tr("Wi-Fi desconectado.")
end
local function temp_line()
  local okI, I = pcall(require, "core.sysinfo")
  local t = okI and I.temperature and I.temperature()
  return t and string.format(tr("O processador está a %d °C."), math.floor(t + 0.5)) or nil
end
local function bat_line()
  local i = battery()
  if not (i and i.pct) then return nil end
  return string.format(tr("Bateria em %d%%."), i.pct) .. (i.charging and (" " .. tr("Carregando.")) or "")
end

-- cada tela: funcao(params) -> lista de falas (as com dados reais primeiro) e o gesto
local S = {}

S.menu = function()
  local out = {}
  local todo = K().todo()
  if #todo > 0 then out[#out + 1] = string.format(tr("Você tem %d pendência(s). Aperte L2 que eu mostro."), #todo) end
  local n = #K().new_ports()
  if n > 0 then out[#out + 1] = string.format(tr("Ainda tem %d port(s) novo(s) esperando na Central."), n) end
  out[#out + 1] = tr("Estou por aqui se precisar. É só apertar L2.")
  out[#out + 1] = tr("Tudo em ordem. Quer uma dica? Aperte L2.")
  return out, "wave"
end

S.store = function(prm)
  if prm and prm.mine then
    local out = { tr("Aqui ficam os ports que você instalou.") }
    for _, t in ipairs(K().todo()) do if t.go and t.go[1] == L("Meus Ports") then table.insert(out, 1, t[1]) end end
    return out, "point"
  end
  if prm and prm.favs then
    local okf, F = pcall(require, "core.favorites")
    local n = okf and F.count() or 0
    return { n > 0 and string.format(tr("%d favoritos. SELECT tira ou coloca um port na lista."), n)
      or tr("Nenhum favorito ainda. SELECT marca um port!") }, "point"
  end
  local out = {}
  local n = #K().new_ports()
  if n > 0 then out[#out + 1] = string.format(tr("Tem %d port(s) novo(s) aqui. Procure a etiqueta NOVO."), n) end
  local C = catalog()
  if C then out[#out + 1] = string.format(tr("O catálogo tem %d ports. Bora escolher um?"), #(C.ports or {})) end
  out[#out + 1] = tr("L1 e R1 trocam a categoria; Y atualiza o catálogo.")
  return out, "point"
end

S.details = function(prm)
  local p = prm and prm.port
  if not p then return nil end
  local out = {}
  local okm, Man = pcall(require, "core.manifest")
  local st = okm and select(2, pcall(Man.status, p)) or "none"
  if st == "update" then out[#out + 1] = string.format(tr("%s tem atualização disponível."), p.name)
  elseif st == "installed" then out[#out + 1] = string.format(tr("%s já está instalado no seu console."), p.name)
  elseif p.size_label and p.size_label ~= "?" and free() then
    out[#out + 1] = string.format(tr("%s ocupa %s. Você tem %s livres."), p.name, p.size_label, free())
  end
  out[#out + 1] = string.format(tr("Categoria de %s: %s."), p.name, p.category or "?")
  return out, "point"
end

S.downloads = function()
  local ok, D = pcall(require, "core.downloads")
  local out = {}
  if ok and D.active() then out[#out + 1] = tr("Estou acompanhando o download. Pode navegar à vontade.") end
  if ok and D.waiting_count() > 0 then out[#out + 1] = string.format(tr("%d download(s) na fila."), D.waiting_count()) end
  out[#out + 1] = tr("START abre esta tela de qualquer lugar.")
  out[#out + 1] = tr("Downloads continuam em segundo plano enquanto você usa o hub.")
  return out, "point"
end

S.library = function()
  local out = {}
  local okP, PT = pcall(require, "core.playtime")
  local top = okP and PT.top(1)[1]
  if top and top.secs >= 600 then
    out[#out + 1] = string.format(tr(L("Seu jogo mais jogado é %s, com %s. Ninguém te segura!")), top.name, PT.format(top.secs))
  end
  local ok, Lib = pcall(require, "core.library")
  if ok and Lib.recent then
    local r = Lib.recent()
    if r[1] then out[#out + 1] = string.format(tr("Da última vez você jogou %s."), r[1].name) end
  end
  if ok and Lib.systems then out[#out + 1] = string.format(tr("Você tem %d jogos de emulador na biblioteca."), Lib.total_games()) end
  out[#out + 1] = tr("Escolha um sistema para ver os jogos dele.")
  return out, "point"
end
S.library_games = function() return { tr("A abre o jogo; o hub fecha e volta quando você sair dele."), tr("SELECT marca o jogo como favorito.") }, "point" end
S.categories = function() return { tr("Escolha uma categoria e eu mostro só o que interessa."),
  tr("As categorias ajudam a achar ports parecidos com os que você gosta.") }, "point" end
S.search = function() return { tr("Digite parte do nome: eu procuro em todo o catálogo.") }, "think" end
S.about = function() return { tr("Este projeto é feito pela comunidade. Obrigado por usar!"), tr("START aqui abre o apoio via Pix.") }, "wave" end
S.settings = function()
  return { tr("Escolha uma aba. Eu explico cada uma quando você entrar."), tr("Dica: faça um backup antes de mudar muita coisa.") }, "point"
end
S.themes = function()
  local okT, Th = pcall(require, "core.themes")
  local out = {}
  local th = okT and Th.by_id and Th.by_id[Th.current]
  if th and th.name then out[#out + 1] = string.format(tr("Tema atual: %s. Os outros aparecem na prévia."), I18N.tr(th.name)) end
  out[#out + 1] = tr("Mudar de tema muda a cara do hub inteiro, inclusive a música em alguns.")
  out[#out + 1] = tr("Teste os temas à vontade: a escolha fica salva.")
  return out, "point"
end
S.esthemes = function() return { tr("Aqui ficam os temas do EmulationStation, separados dos temas do hub.") }, "point" end
S.wifi = function()
  local w = wifi()
  local out = {}
  if w then out[#out + 1] = wifi_line(w) end
  out[#out + 1] = tr("Sem Wi-Fi, o catálogo e as atualizações não chegam.")
  return out, "point"
end
S.wifi_connect = function() return { tr("Escolha a rede e digite a senha com calma. Eu aviso se der erro.") }, "think" end
S.netdiag = function() return { tr("Vou te ajudar a entender a conexão: veja a velocidade e se o catálogo responde.") }, "think" end
S.ftp = function()
  local w = wifi()
  local out = {}
  if w and w.ip then out[#out + 1] = string.format(tr("No PC, conecte o FTP no endereço %s."), w.ip) end
  out[#out + 1] = tr("Pelo FTP você manda arquivos do PC direto para o console.")
  return out, "point"
end
S.ftp_activity = function() return { tr("Aqui aparecem as transferências do FTP em tempo real.") }, "point" end
S.ftp_help = function() return { tr("Siga o passo a passo: em poucos minutos o PC fala com o console.") }, "point" end
S.bios = function() return { tr("Alguns emuladores só funcionam com o BIOS certo. Aqui você confere e instala.") }, "think" end
S.bios_list = S.bios
S.sdmaint = function()
  local out = {}
  if free() then out[#out + 1] = string.format(tr("Você tem %s livres no cartão."), free()) end
  out[#out + 1] = tr("Manutenção do SD libera espaço e evita erros. Vale rodar de vez em quando.")
  return out, "point"
end
S.sdanalyzer = function() return { tr("Vou mostrar o que mais ocupa espaço no cartão.") }, "think" end
S.sdcheck = function() return { tr("A verificação procura erros no cartão. Não desligue o console durante o teste.") }, "alert" end
S.integrity = function() return { tr("Confiro se os arquivos do hub estão inteiros e sem corrupção.") }, "think" end
S.updmgr = function()
  local ok, N = pcall(require, "core.updnotice")
  if ok and N.pending() then return { string.format(tr("Tem a versão %s esperando. Recomendo atualizar."), N.label or N.version or "") }, "alert" end
  return { tr("Você está na versão mais recente que eu conheço."), tr("Atualizações ficam guardadas: dá para voltar se algo der errado.") }, "point"
end
S.update = S.updmgr
S.upd_history = function() return { tr("Aqui fica o histórico de todas as atualizações do hub.") }, "point" end
S.upd_backups = function() return { tr("Cópias de segurança das versões anteriores, para voltar se precisar.") }, "point" end
S.battery = function()
  local out = {}
  local b = bat_line()
  if b then out[#out + 1] = b end
  out[#out + 1] = tr("Brilho alto e Wi-Fi ligado são o que mais gastam bateria.")
  return out, "point"
end
S.padtest = function() return { tr("Aperte todos os botões: eu mostro se algum falhar.") }, "point" end
S.tester = S.padtest
S.pendports = function() return { tr("Esses são arquivos de port que estão no cartão esperando instalação.") }, "point" end
S.recordings = function() return { tr("Suas gravações de tela ficam aqui.") }, "point" end
S.streamrec = function() return { tr("Grave a tela do console para mostrar no seu canal.") }, "point" end
S.albums = function()
  local A = require("core.achievements")
  local a, b = A.count()
  if a >= b then return { tr("Álbum completo! Você é lenda.") }, "happy" end
  return { string.format(tr("Faltam %d cartas no seu álbum."), b - a), tr("Cada temporada traz um álbum novo de cartas.") }, "point"
end
S.achievements = S.albums
S.playtime = function()
  local okP, PT = pcall(require, "core.playtime")
  local top = okP and PT.top(1)[1]
  if top then return { string.format(tr(L("Seu campeão de tempo é %s, com %s. Você joga muito!")), top.name, PT.format(top.secs)) }, "happy" end
  return { tr("Abra um jogo pelo hub e eu começo a contar o seu tempo.") }, "point"
end
S.avatar_pick = function() return { tr("Escolha uma foto que tenha a sua cara!"), tr("Dá para usar imagens suas: copie para a pasta avatares pelo FTP.") }, "point" end
S.birthday = function() return { tr("Me conta quando é o seu aniversário. No dia eu preparo uma surpresa!") }, "happy" end
S.compat = function() return { tr("Aqui você vê se o sistema do console é compatível com o hub.") }, "think" end
S.datetime = function() return { tr("Data e hora certas evitam erro de certificado nos downloads.") }, "point" end
S.consoleid = function() return { tr("Esta é a identificação do seu console.") }, "point" end
S.pmmanager = function() return { tr("Aqui você cuida do PortMaster: instalar, verificar e consertar.") }, "point" end
S.news = function() return { tr("As novidades do projeto ficam aqui.") }, "point" end
S.upd_notes = function() return { tr("Essas são as novidades da versão. Leia com calma!") }, "happy" end
S.r36control = function() return { tr("Ajustes avançados do console. Mude com cuidado.") }, "alert" end
S.files = function() return { tr("Navegue pelos arquivos do cartão com cuidado.") }, "point" end
S.console = function()
  local out = {}
  local t = temp_line()
  if t then out[#out + 1] = t end
  out[#out + 1] = tr("Aqui ficam as informações do seu console.")
  return out, "point"
end

-- abas de Configuracoes (settings_cat, params.id)
local CAT = {}
CAT.appearance = function()
  local okT, Th = pcall(require, "core.themes")
  local th = okT and Th.by_id and Th.by_id[Th.current]
  local out = {}
  if th and th.name then out[#out + 1] = string.format(tr("Tema atual: %s."), I18N.tr(th.name)) end
  out[#out + 1] = tr("Aparência: tema, tamanho do texto e brilho. Tudo muda na hora.")
  return out
end
CAT.audio = function()
  local out = {}
  local okM, Mu = pcall(require, "core.music")
  local okS, Sf = pcall(require, "core.sfx")
  if okM and okS then
    out[#out + 1] = string.format(tr("Música %s em %d%%; efeitos em %d%%."), Mu.enabled and tr("ligada") or tr("desligada"),
      Mu.volume_pct and Mu.volume_pct() or 0, Sf.volume or 0)
  end
  out[#out + 1] = tr("Áudio: música de fundo e sons da interface.")
  return out
end
CAT.network = function()
  local w = wifi()
  local out = {}
  if w then out[#out + 1] = wifi_line(w) end
  out[#out + 1] = tr("Rede: Wi-Fi, FTP e o teste de conexão.")
  return out
end
CAT.battery = function()
  local out = {}
  local b = bat_line()
  if b then out[#out + 1] = b end
  out[#out + 1] = tr("O modo econômico reduz animações e gasta menos bateria.")
  return out
end
CAT.controls = function() return { tr("Controles: teste os botões e ajuste o analógico."), tr("Se um botão falhar, o teste de controles mostra qual.") } end
CAT.downloads = function()
  local ok, D = pcall(require, "core.downloads")
  local out = {}
  if ok and D.history_count then out[#out + 1] = string.format(tr("Seu histórico tem %d download(s)."), D.history_count()) end
  out[#out + 1] = tr("Downloads: catálogo, pasta dos ports e o histórico.")
  return out
end
CAT.backup = function()
  local okB, Bk = pcall(require, "core.backup")
  local info = okB and Bk.info and Bk.info()
  local out = {}
  if info and info.time then out[#out + 1] = string.format(tr("Seu último backup foi em %s."), os.date("%d/%m/%Y", info.time))
  else out[#out + 1] = tr("Você ainda não tem backup. Recomendo fazer um agora.") end
  out[#out + 1] = tr("O backup guarda configurações, favoritos e histórico. Os ports não entram.")
  return out
end
CAT.notifications = function() return { tr("Notificações: escolha o que aparece e se toca som."), tr("Avisos de erro sempre valem a pena deixar ligados.") } end
CAT.console = function()
  local out = {}
  if free() then out[#out + 1] = string.format(tr("Você tem %s livres no cartão."), free()) end
  local t = temp_line()
  if t then out[#out + 1] = t end
  out[#out + 1] = tr("Console: informações, manutenção do SD e atualizações.")
  return out
end
CAT.achievements = function()
  local A = require("core.achievements")
  local a, b = A.count()
  return { string.format(tr("Seu perfil: %d de %d cartas."), a, b), tr("Aqui você troca o seu nome e o meu também.") }
end

CAT.prefs = function() return { tr("Preferências: idioma, avisos na tela e som de notificação."), tr("Avisos de erro sempre valem a pena deixar ligados.") } end
CAT.ftp = function()
  local w = wifi()
  local out = {}
  if w and w.ip then out[#out + 1] = string.format(tr("No PC, conecte o FTP no endereço %s."), w.ip) end
  out[#out + 1] = tr("Pelo FTP você manda arquivos do PC direto para o console.")
  return out
end
CAT.catalog = function()
  local C = catalog()
  local out = {}
  if C then out[#out + 1] = string.format(tr("O catálogo tem %d ports. Bora escolher um?"), #(C.ports or {})) end
  out[#out + 1] = tr("Catálogo: de onde vêm os ports e quando ele se atualiza.")
  return out
end
CAT.myports = function() return { tr("Aqui ficam os ports que você instalou."), tr("Meus ports: atualizar, verificar e remover o que já está no cartão.") } end
CAT.storage = function()
  local out = {}
  if free() then out[#out + 1] = string.format(tr("Você tem %s livres no cartão."), free()) end
  out[#out + 1] = tr("Manutenção do SD libera espaço e evita erros. Vale rodar de vez em quando.")
  return out
end
CAT.updates = function() local l = S.updmgr(); return l end
CAT.tools = function() return { tr("Ferramentas: utilitários extras para cuidar do console."), tr("Ajustes avançados do console. Mude com cuidado.") } end
CAT.diag = function()
  local out = {}
  local t = temp_line()
  if t then out[#out + 1] = t end
  local e = K().errors_today and K().errors_today() or {}
  out[#out + 1] = (#e > 0) and string.format(tr("Hoje registrei %d problema(s). Aperte L2 que eu explico."), #e)
    or tr("Diagnóstico: nenhum problema registrado hoje.")
  return out
end
CAT.about = function() return { tr("Este projeto é feito pela comunidade. Obrigado por usar!"), tr("START aqui abre o apoio via Pix.") } end

S.settings_cat = function(prm)
  local id = prm and (prm.id or (prm.cat and prm.cat.id))
  local fn = id and CAT[id]
  if not fn then return nil end
  local ok, out = pcall(fn)
  return ok and out or nil, "point"
end

-- telas sem fala propria: um aviso de que esta por perto ou uma dica
local function generic()
  return { tr("Estou de olho. Se precisar, aperte L2."), K().answer("tip").lines[1] }
end

local GESTURE = { point = { "point", 1.5 }, wave = { "wave", 1.8 }, think = { "think", 1.0 }, happy = { "happy", 1.6 },
  alert = { "alert", 1.6 }, talk = { "point", 1.2 } }

function B.on_screen(name, params)
  if not name or name == "assistant" or name == "splash" or name == "disclaimer" or name == "textinput" then return end
  if params and params.first then return end   -- primeiro acesso: o assistente se apresenta depois do aviso
  local A = Asst()
  if not A.enabled() or A.talk() == "off" then return end
  if now() - last_talk < (GAP[A.talk()] or 4) then return end
  if A.hold and now() < A.hold then return end
  if math.random() > (CHANCE[A.talk()] or 1) then return end
  local fn = S[name]
  local ok, lines, gesture = true, nil, nil
  if fn then ok, lines, gesture = pcall(fn, params) end
  if not ok or type(lines) ~= "table" or #lines == 0 then lines, gesture = generic(), "talk" end
  -- revezamento por tela (a chave inclui a aba ou o port)
  local key = name .. ":" .. tostring(params and (params.id or (params.port and params.port.id)) or "")
  local i = ((rot[key] or 0) % #lines) + 1
  local text = lines[i]
  if text == B.last_text and #lines > 1 then i = i % #lines + 1; text = lines[i] end
  rot[key] = i
  B.last_text = text
  A.bubble = nil
  say(text, "talk")
  local g = GESTURE[gesture or "point"]
  if g then A.play(g[1], g[2]) end
end

-- ---------------------------------------------------------------- vigilancia
local function check_new_ports()
  local C = catalog()
  if not C or not C.ports or #C.ports == 0 then return end
  local sig = #C.ports .. "|" .. tostring(C.updated or "")
  if sig == catalog_sig then return end
  catalog_sig = sig
  local A = Asst()
  local st = A.load()
  local ids, set = {}, {}
  for _, p in ipairs(C.ports) do if not p.builtin and p.id then ids[#ids + 1] = p.id; set[p.id] = p end end
  if type(st.seen_ports) ~= "table" then st.seen_ports = ids; A.save(); return end
  local old = {}
  for _, id in ipairs(st.seen_ports) do old[id] = true end
  local fresh = {}
  for _, id in ipairs(ids) do if not old[id] then fresh[#fresh + 1] = id end end
  st.seen_ports = ids
  A.save()
  if #fresh > 0 then
    A.fresh = A.fresh or {}
    for _, id in ipairs(fresh) do A.fresh[#A.fresh + 1] = id end
    A.event("catalog", #fresh)
    local p = set[fresh[1]]
    B.pending = { #fresh == 1 and string.format(tr("Chegou um port novo no catálogo: %s!"), p.name)
      or string.format(tr("Chegaram %d ports novos no catálogo! Um deles é %s."), #fresh, p.name), "happy" }
  end
end

function B.update(dt)
  local A = Asst()
  B.t = (B.t or 3) - dt
  if B.t <= 0 then
    B.t = 5
    pcall(check_new_ports)
    if not told_update then
      local ok, N = pcall(require, "core.updnotice")
      if ok and N.pending() then
        told_update = true
        B.pending = B.pending or { string.format(tr("Saiu a versão %s do hub! Vá em Configurações > Atualizações."), N.label or N.version or ""), "alert" }
      end
    end
    if now() > 25 and A.load().todo_day ~= os.date("%Y-%m-%d") and not B.pending then
      local todo = K().todo()
      A.set("todo_day", os.date("%Y-%m-%d"))
      if #todo > 0 then B.pending = { tr("Lembrete: ") .. todo[1][1], "think" } end
    end
  end
  local cur = App and App.current and App.current()
  local quiet = cur and (cur.name == "splash" or cur.name == "disclaimer" or cur.name == "textinput" or cur.name == "language"
    or (cur.name == "birthday" and cur.p and cur.p.first))
  if B.pending and not quiet and not A.bubble and A.talk() ~= "off" and A.enabled() then
    local p = B.pending
    B.pending = nil
    say(p[1], p[2], 7)
  end
  -- dica de tempos em tempos (so quando parado numa tela, sem balao)
  local every = CHATTER[A.talk()]
  if every and not quiet and A.enabled() then
    B.chat = (B.chat or every) - dt
    if B.chat <= 0 then
      B.chat = every * (0.8 + math.random() * 0.4)
      if not A.bubble then
        local r = K().answer("tip")
        local line = pick(r.lines)
        -- de vez em quando, tira onda com o tempo de jogo
        local okP, PT = pcall(require, "core.playtime")
        local top = okP and PT.top(1)[1]
        if top and top.secs >= 1800 and math.random() < 0.35 then
          line = string.format(tr(pick({ L("Já são %s de %s. Você só vive jogando, hein?"),
            L("%s em %s! Tô curtindo, continue assim."), L("Você é incrível: %s jogando %s.") })), PT.format(top.secs), top.name)
        end
        say(line, "talk")
        A.play(pick({ "think", "point", "wave" }), 1.4)
      end
    end
  end
end

return B
