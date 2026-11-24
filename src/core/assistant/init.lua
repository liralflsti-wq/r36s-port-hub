-- =============================================================================
--  Assistente do R36S PORT HUB (substitui o antigo mascote)
--  Um assistente LOCAL (sem internet e sem IA pesada): acompanha tudo o que
--  acontece no hub (diario em core/assistant/journal.lua), le os dados reais
--  (catalogo, ports instalados, downloads, log de erros, cartao SD, bateria,
--  Wi-Fi, atualizacoes) e responde rapido e com precisao
--  (core/assistant/knowledge.lua). E educado: cumprimenta conforme a hora,
--  avisa ports novos, explica erros e lembra do que falta fazer
--  (core/assistant/brain.lua).
--  Visual: o robo de armadura azul (assets/assistant/), no canto da tela e na
--  tela do assistente (L2 abre de qualquer lugar).
--  Estado em assistant.json: nome, ligado, tamanho, falas, portas ja vistas.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")

local A = {}
local FILE = "assistant.json"
local state

A.SIZES = { "small", "medium", "large" }
A.SIZE_NAMES = { small = L("Pequeno"), medium = L("Médio"), large = L("Grande") }
A.SIZE_SCALE = { small = 0.75, medium = 1.0, large = 1.35 }
A.TALK = { "often", "normal", "rare", "off" }
A.TALK_NAMES = { often = L("Bastante"), normal = L("Normal"), rare = L("Pouco"), off = L("Em silêncio") }

local function defaults()
  return { name = "Nexo", enabled = true, size = "medium", talk = "normal", last_seen = 0, brief_day = "" }
end

function A.load()
  if state then return state end
  state = defaults()
  local ok, txt = pcall(love.filesystem.read, FILE)
  if ok and txt then
    local okj, d = pcall(require("lib.json").decode, txt)
    if okj and type(d) == "table" then for k, v in pairs(d) do state[k] = v end end
  end
  if type(state.name) ~= "string" or state.name == "" then state.name = "Nexo" end
  return state
end

function A.save()
  local ok, txt = pcall(require("lib.json").encode, A.load())
  if ok then pcall(love.filesystem.write, FILE, txt) end
end

function A.get(k) return A.load()[k] end
function A.set(k, v) A.load()[k] = v; A.save() end
function A.enabled() return A.load().enabled ~= false end
function A.talk() return A.load().talk or "normal" end
function A.name() return A.load().name or "Nexo" end

--- nome de quem usa o hub (Meu perfil) ou "amigo"
function A.user()
  local ok, Ach = pcall(require, "core.achievements")
  local n = ok and Ach.user_name() or nil
  return n or I18N.tr(L("amigo"))
end

local function pick(t) return t[math.random(#t)] end

--- "Bom dia" / "Boa tarde" / "Boa noite" conforme a hora
function A.greeting()
  local h = tonumber(os.date("%H"))
  local g = (h >= 5 and h < 12) and L("Bom dia, %s!") or ((h >= 12 and h < 18) and L("Boa tarde, %s!") or L("Boa noite, %s!"))
  return string.format(I18N.tr(g), A.user())
end

-- complemento do cumprimento: hora do dia e dia da semana
local EXTRA = {
  morning = { L("Pronto para começar o dia?"), L("Café na mão e console carregado?"), L("Vamos ver o que tem de novo hoje.") },
  afternoon = { L("Como está a tarde?"), L("Hora de uma partida rápida?"), L("Tudo certo por aí?") },
  evening = { L("Uma partida antes de dormir?"), L("Que bom te ver por aqui à noite."), L("Vamos deixar tudo em ordem para amanhã?") },
  late = { L("Já é tarde. Não esqueça de descansar."), L("Jogando de madrugada? Cuide da bateria.") },
  weekend = { L("Bom fim de semana!"), L("Fim de semana é perfeito para testar ports novos.") },
  monday = { L("Começo de semana: vamos organizar a biblioteca?") },
  friday = { L("Sexta-feira! Que tal separar uns jogos para o fim de semana?") },
}
function A.greeting_extra()
  local h = tonumber(os.date("%H"))
  local wd = tonumber(os.date("%w"))
  local pool = {}
  local function addp(t) for _, x in ipairs(t) do pool[#pool + 1] = x end end
  if h < 5 then addp(EXTRA.late) elseif h < 12 then addp(EXTRA.morning) elseif h < 18 then addp(EXTRA.afternoon) else addp(EXTRA.evening) end
  if wd == 0 or wd == 6 then addp(EXTRA.weekend) elseif wd == 1 then addp(EXTRA.monday) elseif wd == 5 then addp(EXTRA.friday) end
  return I18N.tr(pick(pool))
end

-- ------------------------------------------------------------------ fala
A.bubble = nil        -- { text, t }
A.mood = "idle"       -- idle, talk, happy, alert, sad
A.mood_t = 0
-- animacao 3D (core/assistant3d/anim.lua)
local Anim = require("core.assistant3d.anim")
local ctl
function A.ctl()
  if not ctl then ctl = Anim.new() end
  return ctl
end
--- toca uma animacao: idle, talk, wave, point, think, alert, happy, sleep
function A.play(name, dur) Anim.play(A.ctl(), name, dur) end

local MOOD_ANIM = { happy = { "happy", 1.8 }, alert = { "alert", 2.2 }, wave = { "wave", 2.2 }, think = { "think", 1.2 } }

function A.say(text, mood, dur)
  if not text or text == "" then return end
  dur = dur or math.max(3.5, math.min(9, #text / 15))
  if A.talk() ~= "off" then A.bubble = { text = text, t = dur } end
  -- falas importantes (saudacao, fim de jogo, avisos) ficam uns segundos sem
  -- ser trocadas pelo comentario de tela
  if dur >= 7 then A.hold = ((App and App.t) or 0) + 4 end
  A.mood, A.mood_t = mood or "talk", dur
  local a = MOOD_ANIM[mood or ""]
  if a then A.play(a[1], a[2]) end
end

--- compatibilidade com o desenho antigo
function A.turn() end

local function J() return require("core.assistant.journal") end
local function K() return require("core.assistant.knowledge") end

-- ------------------------------------------------------------------ eventos
--- chamado depois do aviso inicial: cumprimenta e da o resumo curto do dia
function A.on_boot()
  local st = A.load()
  local now = os.time()
  local away = (st.last_seen or 0) > 0 and (now - st.last_seen) or 0
  st.last_seen = now
  A.save()
  local hello = A.greeting()
  if (st.boots or 0) == 0 then
    hello = hello .. " " .. string.format(I18N.tr(L("Eu sou %s, seu assistente. Vou acompanhar o hub e te avisar do que for importante.")), A.name())
  elseif away > 7 * 86400 then hello = hello .. " " .. I18N.tr(L("Faz tempo! Senti falta de você por aqui."))
  elseif away > 2 * 86400 then hello = hello .. " " .. I18N.tr(L("Que bom te ver de volta!"))
  else hello = hello .. " " .. A.greeting_extra() end
  st.boots = (st.boots or 0) + 1
  A.save()
  -- voltou de um jogo aberto pelo hub: comenta o tempo de jogo
  if App and App.play_session then
    local s = App.play_session
    App.play_session = nil
    A.event("played", s)
    return
  end
  local okP, P = pcall(require, "core.profile")
  if okP and P.is_birthday() then
    local who = A.user()
    hello = (who and string.format(I18N.tr(L("Feliz aniversário, %s!")), who) or I18N.tr(L("Feliz aniversário!")))
      .. " " .. I18N.tr(L("Hoje o dia é seu: que venham muitos jogos e conquistas!"))
    A.say(hello, "happy", 9)
    return
  end
  local short = K().short_brief()
  A.say(hello .. (short and (" " .. short) or ""), "wave", 8)
end

--- eventos do hub (tambem vao para o diario)
--  install(nome) cancel(nome) uninstall(nome) error(titulo, corpo)
--  achievement(nome) update(notas) goodbye() play(jogo) ftp(arquivo)
--  catalog(n_novos)
function A.event(kind, a, b)
  local tr = I18N.tr
  if kind == "install" then
    J().add("install", a)
    local n = J().count("install", os.time() - 86400)
    local msg = pick({ L("Pronto! %s foi instalado. Reinicie a lista do EmulationStation para ele aparecer."),
      L("%s instalado com sucesso. Para ele aparecer no EmulationStation, reinicie a lista no menu Sair."),
      L("Instalação concluída: %s. Bom jogo!") })
    local txt = string.format(tr(msg), a or "?")
    if n >= 3 then txt = txt .. " " .. string.format(tr(L("Já são %d instalações hoje.")), n) end
    A.say(txt, "happy", 6)
  elseif kind == "played" then
    -- a = { name, secs, total, sessions }: comenta a partida, tirando onda
    local s = a or {}
    local PT = require("core.playtime")
    local name, dur, tot = s.name or "?", PT.format(s.secs), PT.format(s.total)
    local top = PT.top(1)[1]
    local msg, mood
    if (s.secs or 0) >= 3600 then
      msg = string.format(tr(pick({ L("Cara, %s de %s sem parar! Você só vive jogando, hein?"),
        L("Olha ele! %s de %s. Você joga muito!"), L("%s de %s seguidos? Tô curtindo, continue assim!") })), dur, name)
      mood = "happy"
    elseif (s.secs or 0) < 300 then
      msg = string.format(tr(pick({ L("Partida rápida de %s: %s. Deu para aquecer os dedos?"),
        L("%s por %s. Só uma passadinha, né?") })), name, dur)
      mood = "talk"
    else
      msg = string.format(tr(pick({ L("Você jogou %s por %s. Mandou bem!"), L("%s por %s. Tô curtindo ver você jogar!"),
        L("Boa sessão de %s: %s. Continue assim!") })), name, dur)
      mood = "happy"
    end
    if top and top.key == s.key and (s.sessions or 0) >= 3 then
      msg = msg .. " " .. string.format(tr(pick({ L("%s é o seu favorito: já são %s no total. Você é incrível!"),
        L("Ninguém joga %s como você: %s no total!") })), name, tot)
    elseif (s.total or 0) >= 5 * 3600 then
      msg = msg .. " " .. string.format(tr(L("Já são %s nesse jogo. Você joga muito!")), tot)
    end
    J().add("played", name .. " (" .. dur .. ")")
    A.say(msg, mood, 8)
  elseif kind == "cancel" then
    J().add("cancel", a)
    A.say(string.format(tr(pick({ L("Download de %s cancelado. Nada foi alterado no console."),
      L("Tudo bem, cancelei %s. O console ficou como estava.") })), a or "?"), "talk", 4)
  elseif kind == "uninstall" then
    J().add("uninstall", a)
    local free = App and App.free and require("lib.util").format_bytes(App.free)
    A.say(string.format(tr(L("%s foi removido do console.")), a or "?") .. (free and (" " .. string.format(tr(L("Agora você tem %s livres.")), free)) or ""), "talk", 5)
  elseif kind == "error" then
    J().add("error", a)
    local tip = K().explain(tostring(a or "") .. " " .. tostring(b or ""))
    A.say(tr(L("Deu um erro: ")) .. tostring(a or "") .. (tip and (". " .. tip) or (". " .. tr(L("Se repetir, me pergunte \"Deu algum erro?\" para ver os detalhes.")))), "alert", 9)
  elseif kind == "achievement" then
    J().add("achievement", a)
    local okA, Ach = pcall(require, "core.achievements")
    local got, tot = 0, 0
    if okA then got, tot = Ach.count() end
    A.say(string.format(tr(L("Parabéns! Você ganhou a carta %s.")), a or "?") .. (tot > 0 and (" " .. string.format(tr(L("Seu álbum está com %d de %d.")), got, tot)) or ""), "happy", 5)
  elseif kind == "update" then
    J().add("update", require("config").VERSION)
    A.say(string.format(tr(L("O hub foi atualizado para a versão %s. Pergunte \"O que mudou?\" que eu te conto.")), require("config").VERSION), "happy", 6)
  elseif kind == "goodbye" then
    A.say(string.format(tr(pick({ L("Até logo, %s! Bom jogo."), L("Até a próxima, %s. Deixei tudo anotado."),
      L("Bom jogo, %s! Estarei aqui quando voltar.") })), A.user()), "wave", 6)
  elseif kind == "play" then
    J().add("play", a)
  elseif kind == "ftp" then
    J().add("ftp", a)
  elseif kind == "catalog" then
    if (a or 0) > 0 then J().add("catalog", tostring(a)) end
  end
end

function A.update(dt)
  local c = A.ctl()
  -- base da animacao: falando enquanto ha balao; dormindo de madrugada sem atividade
  local h = tonumber(os.date("%H"))
  -- parado sem uso por 2 minutos: cochila (acorda no primeiro botao)
  local idle = App and App.last_input and (App.t - App.last_input) or 0
  Anim.set_base(c, A.bubble and "talk" or (idle > 120 and "sleep" or "idle"))
  if App and App.animations and App.animations() then Anim.update(c, dt) end
  if A.bubble then
    A.bubble.t = A.bubble.t - dt
    if A.bubble.t <= 0 then A.bubble = nil end
  end
  if A.mood_t > 0 then
    A.mood_t = A.mood_t - dt
    if A.mood_t <= 0 then A.mood = "idle" end
  end
  pcall(require("core.assistant.brain").update, dt)
end

return A
