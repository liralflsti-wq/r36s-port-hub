-- =============================================================================
--  Conquistas do R36S PORT HUB ("funcoes descobertas")
--  Cada conquista libera uma vez so, quando o usuario usa uma funcao do hub
--  pela primeira vez. Ao liberar aparece a comemoracao (ui/achv_popup.lua) e a
--  carta fica na colecao (Configuracoes > Conquistas).
--  Salvo em achievements.json (pasta de dados do app): { id = os.time() }.
--  O nome do usuario fica nas preferencias (user_name).
--
--  Raridade da carta (rarity): common, uncommon, epic, legendary, unique. A
--  moldura muda com a raridade (ui/achv_card.lua): comum prata, incomum verde,
--  epica roxa com brilho pulsando, lendaria dourada com reflexo e faiscas,
--  unica com borda arco-iris animada e brilho holografico.
--
--  Para criar uma conquista nova: adicione em DEFS (id, nome, descricao, dica,
--  imagem da carta em assets/achievements/<id>.png, raridade) e chame
--  Achievements.unlock("<id>") no ponto do codigo em que a funcao e usada.
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")
local Prefs = require("core.prefs")

local A = {}
local FILE = "achievements.json"

A.RARITY = {
  common = { n = 1, name = L("Comum"), color = { 0.72, 0.74, 0.78 } },
  uncommon = { n = 2, name = L("Incomum"), color = { 0.30, 0.82, 0.42 } },
  epic = { n = 3, name = L("Épica"), color = { 0.66, 0.36, 0.98 } },
  legendary = { n = 4, name = L("Lendária"), color = { 1.0, 0.76, 0.18 } },
  unique = { n = 5, name = L("Única"), color = { 1.0, 0.35, 0.62 } },
}
A.RARITY_ORDER = { "common", "uncommon", "epic", "legendary", "unique" }

-- Temporadas: cada temporada de atualizacao tem o seu album de cartas.
-- As conquistas sem "season" sao da temporada 1.
-- 4 albuns por ano (um por trimestre): year + quarter (1..4) dizem a vaga do
-- album na tela de albuns; released e a data de lancamento (AAAA-MM-DD).
A.SEASONS = {
  { id = 1, name = L("Temporada 1"), title = L("Primeira Jornada"), version = "0.5.5",
    year = 2026, quarter = 4, released = "2026-11-19" },
}

--- temporada pelo id
function A.season(id)
  for _, s in ipairs(A.SEASONS) do if s.id == id then return s end end
  return nil
end

--- conquistas de uma temporada (na ordem do album)
function A.defs_of(season)
  local out = {}
  for _, d in ipairs(A.DEFS) do if (d.season or 1) == season then out[#out + 1] = d end end
  return out
end

--- data de lancamento no formato do usuario (dd/mm/aaaa)
function A.release_label(s)
  local y, m, d = tostring(s and s.released or ""):match("^(%d+)-(%d+)-(%d+)")
  if not y then return "?" end
  return string.format("%02d/%02d/%04d", tonumber(d), tonumber(m), tonumber(y))
end

A.DEFS = {
  {
    id = "explorer",
    name = L("Explorador"),
    desc = L("Mergulhou na Central de Conteúdo pela primeira vez. Um universo de ports!"),
    hint = L("Todo universo começa com uma primeira porta."),
    card = "assets/achievements/explorer.jpg", fill = true,
    rarity = "common",
    shout = L("UAAAU!"),
  },
  {
    id = "library_play",
    name = L("Hora de jogar"),
    desc = L("Abriu um jogo pela Biblioteca de jogos do hub. Diversão garantida!"),
    hint = L("Os livros desta estante não se leem: se jogam."),
    card = "assets/achievements/library_play.jpg", fill = true,
    rarity = "common",
    shout = L("BORA JOGAR!"),
  },
  {
    id = "goodbye",
    name = L("Até logo"),
    desc = L("Saiu do hub pela primeira vez. Ele ficou com saudade..."),
    hint = L("Ele chora toda vez que você vai embora."),
    card = "assets/achievements/goodbye.jpg", fill = true,
    rarity = "common",
    shout = L("VOLTA LOGO!"),
  },
  {
    id = "first_install",
    name = L("Primeira instalação"),
    desc = L("Instalou um port pelo hub pela primeira vez. Mandou bem!"),
    hint = L("O primeiro passo de toda coleção."),
    card = "assets/achievements/first_install.png",
    rarity = "common",
    shout = L("INSTALADO!"),
  },
  {
    id = "search",
    name = L("Detetive"),
    desc = L("Usou a pesquisa e achou o que procurava. Nada escapa!"),
    hint = L("Quem procura, acha. Mas tem que procurar."),
    card = "assets/achievements/search.jpg", fill = true,
    rarity = "common",
    shout = L("ACHEI!"),
  },
  {
    id = "favorite",
    name = L("Carta de amor"),
    desc = L("Marcou o primeiro port como favorito. Foi amor à primeira vista!"),
    hint = L("Um botão esquecido guarda uma estrela."),
    card = "assets/achievements/favorite.jpg", fill = true,
    rarity = "common",
    shout = L("FAVORITO!"),
  },
  {
    id = "uninstall",
    name = L("Arrancou pela raiz"),
    desc = L("Desinstalou um port pelo hub. Saiu tudo, até a raiz!"),
    hint = L("O que foi plantado também pode ser colhido."),
    card = "assets/achievements/uninstall.jpg", fill = true,
    rarity = "common",
    shout = L("ARRANCADO!"),
  },
  {
    id = "cancel_download",
    name = L("Arrependido"),
    desc = L("Cancelou um download no meio do caminho. Mudou de ideia?"),
    hint = L("Nem todo caminho precisa chegar ao fim."),
    card = "assets/achievements/cancel_download.jpg", fill = true,
    rarity = "common",
    shout = L("NÃÃÃO!"),
  },
  {
    id = "background_download",
    name = L("Multitarefa"),
    desc = L("Deixou um download rodando em segundo plano e ele terminou sozinho enquanto você descansava."),
    hint = L("Enquanto você descansa, alguém trabalha por você."),
    card = "assets/achievements/background_download.jpg", fill = true,
    rarity = "uncommon",
    shout = L("TERMINOU!"),
  },
  {
    id = "language",
    name = L("Poliglota"),
    desc = L("Trocou o idioma do hub. Fala outras línguas com charme!"),
    hint = L("Hello, olá... qual delas é a sua?"),
    card = "assets/achievements/language.jpg", fill = true,
    rarity = "uncommon",
    shout = L("BONJOUR!"),
  },
  {
    id = "padtest",
    name = L("Dedos de aço"),
    desc = L("Testou todos os botões do controle no teste de controles. Rodou tudo!"),
    hint = L("Nenhum botão pode ficar com ciúmes."),
    card = "assets/achievements/padtest.jpg", fill = true,
    rarity = "uncommon",
    shout = L("GIROU TUDO!"),
  },
  {
    id = "speedtest",
    name = L("Velocista"),
    desc = L("Mediu a velocidade da internet do console no diagnóstico de rede."),
    hint = L("Quão rápido corre o que você não vê?"),
    card = "assets/achievements/speedtest.jpg", fill = true,
    rarity = "uncommon",
    shout = L("VOANDO!"),
  },
  {
    id = "wifi_connect",
    name = L("Conectado"),
    desc = L("Conectou o console no Wi-Fi pela tela do hub. Energia total!"),
    hint = L("Uma senha invisível no ar, digitada com as próprias mãos."),
    card = "assets/achievements/wifi_connect.jpg", fill = true,
    rarity = "uncommon",
    shout = L("CONECTADO!"),
  },
  {
    id = "low_battery",
    name = L("No osso"),
    desc = L("Usou o hub com a bateria em 10% ou menos, sem carregador. Vive perigosamente!"),
    hint = L("Viva perigosamente, longe da tomada."),
    card = "assets/achievements/low_battery.jpg", fill = true,
    rarity = "uncommon",
    shout = L("SOCORRO!"),
  },
  {
    id = "theme_change",
    name = L("Repaginado"),
    desc = L("Trocou o tema do hub pela primeira vez. Que estilo!"),
    hint = L("Até o hub cansa de usar a mesma roupa."),
    card = "assets/achievements/theme_change.jpg", fill = true,
    rarity = "uncommon",
    shout = L("QUE ESTILO!"),
  },
  {
    id = "first_error",
    name = L("Deu ruim"),
    desc = L("Deu o primeiro erro no hub e ele foi para o registro de erros. Acontece com os melhores!"),
    hint = L("Às vezes é preciso errar para ser lembrado."),
    card = "assets/achievements/first_error.jpg", fill = true,
    rarity = "epic",
    shout = L("DEU RUIM!"),
  },
  {
    id = "password_install",
    name = L("Arrombador"),
    desc = L("Instalou um arquivo protegido digitando a senha no teclado da tela. Abriu na força!"),
    hint = L("Nenhum cadeado resiste a quem sabe a palavra."),
    card = "assets/achievements/password_install.jpg", fill = true,
    rarity = "epic",
    shout = L("ABRIU!"),
  },
  {
    id = "backup",
    name = L("Guardiã"),
    desc = L("Fez um backup das configurações e dados do hub. Nada se perde!"),
    hint = L("Quem guarda, tem. Quem não guarda..."),
    card = "assets/achievements/backup.jpg", fill = true,
    rarity = "epic",
    shout = L("PROTEGIDO!"),
  },
  {
    id = "local_install",
    name = L("Contrabandista"),
    desc = L("Instalou um port a partir de um arquivo seu, fora do catálogo. De onde veio isso?!"),
    hint = L("Nem tudo que é instalado vem da loja."),
    card = "assets/achievements/local_install.jpg", fill = true,
    rarity = "epic",
    shout = L("DE ONDE VEIO?!"),
  },
  {
    id = "sd_maint",
    name = L("Mecânico"),
    desc = L("Fez a manutenção do cartão SD pelo hub. Nada de sair quebrando as coisas!"),
    hint = L("Até a memória precisa de um médico às vezes."),
    card = "assets/achievements/sd_maint.jpg", fill = true,
    rarity = "epic",
    shout = L("CONSERTADO!"),
  },
  {
    id = "bios_install",
    name = L("BIOS em dia"),
    desc = L("Instalou uma BIOS pelo hub. Os emuladores ganharam vida!"),
    hint = L("Alguns emuladores dormem até alguém acordá-los."),
    card = "assets/achievements/bios_install.jpg", fill = true,
    rarity = "epic",
    shout = L("GANHOU VIDA!"),
  },
  {
    id = "collector",
    name = L("Colecionador"),
    desc = L("Tem 10 ports instalados pelo hub ao mesmo tempo. Que coleção!"),
    hint = L("Um só é pouco. Dois é bom. Dez é coleção."),
    card = "assets/achievements/collector.jpg", fill = true,
    rarity = "epic",
    shout = L("COLEÇÃO!"),
  },
  {
    id = "daily",
    name = L("Fã número 1"),
    desc = L("Abriu o hub em 7 dias diferentes. A plateia vai à loucura!"),
    hint = L("Uma semana de fidelidade, um dia de cada vez."),
    card = "assets/achievements/daily.jpg", fill = true,
    rarity = "legendary",
    shout = L("FÃ Nº 1!"),
  },
  {
    id = "ftp_transfer",
    name = L("Mestre do FTP"),
    desc = L("Passou um arquivo entre o PC e o console pelo servidor FTP do hub."),
    hint = L("Existe uma ponte invisível entre o console e outro mundo."),
    card = "assets/achievements/ftp_transfer.jpg", fill = true,
    rarity = "legendary",
    shout = L("TRANSFERIDO!"),
  },
  {
    id = "restore",
    name = L("Ressurreição"),
    desc = L("Restaurou um backup e trouxe de volta as configurações e os dados do hub."),
    hint = L("O que foi guardado um dia pode se erguer de novo."),
    card = "assets/achievements/restore.jpg", fill = true,
    rarity = "legendary",
    shout = L("ERGA-SE!"),
  },
  {
    id = "hub_update",
    name = L("Atualizado"),
    desc = L("Atualizou o R36S PORT HUB para uma versão nova. Lágrimas de alegria!"),
    hint = L("O hub também cresce. Deixe-o evoluir."),
    card = "assets/achievements/hub_update.jpg", fill = true,
    rarity = "legendary",
    shout = L("ATUALIZADO!"),
  },
  {
    id = "supporter",
    name = L("Apoiador do projeto"),
    desc = L("Abriu o QR Code do Pix para apoiar o R36S PORT HUB. Muito obrigado!"),
    hint = L("Quem cria também precisa de um empurrãozinho."),
    card = "assets/achievements/supporter.jpg", fill = true,
    rarity = "unique",
    shout = L("VALEU!!"),
  },
  {
    -- EASTER EGG (opcional): o codigo classico na tela Sobre o Projeto
    -- (cima, cima, baixo, baixo, esquerda, direita, esquerda, direita, B, A)
    id = "mascot_lyro", optional = true, secret = true,
    name = L("Lyro, o mascote"),
    desc = L("Você digitou o código secreto e encontrou o Lyro, o mascote do R36S PORT HUB! Poucos chegam até aqui."),
    hint = L("Um código antigo, digitado na página de quem criou tudo, chama um amigo peludo."),
    card = "assets/achievements/mascot_lyro.jpg", fill = true,
    rarity = "unique",
    shout = L("ACHOU O LYRO!"),
  },
  {
    -- tempo de jogo (jogos e ports abertos pelo hub): 1 h, 10 h e 50 h somados
    id = "playtime_1h",
    name = L("Tempo de jogo"),
    desc = L("Somou 1 hora jogando pelo hub. A diversão começou de verdade!"),
    hint = L("O relógio só corre quando o jogo começa pelo hub."),
    card = "assets/achievements/playtime_1h.jpg", fill = true,
    rarity = "uncommon",
    shout = L("1 HORA!"),
  },
  {
    id = "playtime_10h",
    name = L("Tempo de jogo extenso"),
    desc = L("Somou 10 horas jogando pelo hub. Já pode chamar de hobby!"),
    hint = L("Dez voltas completas do ponteiro pequeno... e algumas a mais."),
    card = "assets/achievements/playtime_10h.jpg", fill = true,
    rarity = "epic",
    shout = L("10 HORAS!"),
  },
  {
    -- opcional: nao conta para a carta final "Lenda"
    id = "playtime_50h", optional = true,
    name = L("Tempo de jogo lendário"),
    desc = L("Somou 50 horas jogando pelo hub. Uma lenda dos games!"),
    hint = L("Só os mais dedicados chegam a ver este troféu."),
    card = "assets/achievements/playtime_50h.jpg", fill = true,
    rarity = "legendary",
    shout = L("50 HORAS!"),
  },
  {
    -- so no dia do aniversario (Meu perfil > Aniversário). Opcional: nao conta
    -- para a carta final "Lenda".
    id = "birthday", optional = true,
    name = L("Feliz aniversário"),
    desc = L("Abriu o hub no dia do seu aniversário. Parabéns! Que a vida continue cheia de jogos, alegria e conquistas!"),
    hint = L("Uma vez por ano, o hub prepara uma festa só para você."),
    card = "assets/achievements/birthday.jpg", fill = true,
    rarity = "unique",
    shout = L("PARABÉNS!"),
  },
  {
    -- libera sozinha quando todas as outras estiverem liberadas
    id = "legend", final = true,
    name = L("Lenda do R36S PORT HUB"),
    desc = L("Liberou todas as conquistas do R36S PORT HUB. Agora você é a lenda!"),
    hint = L("Só quem completou a jornada inteira conhece este rosto."),
    card = "assets/achievements/legend.jpg", fill = true,
    rarity = "unique",
    shout = L("LENDA!"),
  },
}
A.BY_ID = {}
function A.index()
  A.BY_ID = {}
  for i, d in ipairs(A.DEFS) do
    d.n = i
    d.season = d.season or 1
    d.rarity = A.RARITY[d.rarity or ""] and d.rarity or "common"
    d.color = d.color or A.RARITY[d.rarity].color
    A.BY_ID[d.id] = d
  end
end
A.index()

--- dados da raridade da conquista
function A.rarity(def) return A.RARITY[def and def.rarity or "common"] or A.RARITY.common end

local state = nil

-- ---------------------------------------------------------------------------
-- Assinatura: as conquistas ficam "presas" a este console. O arquivo guarda a
-- lista e uma assinatura (hash da lista + identificador do aparelho). Um
-- arquivo copiado de outro console nao bate a assinatura e e ignorado (fica
-- guardado como achievements_invalid.json). Arquivos antigos, sem assinatura,
-- sao aceitos e assinados na proxima gravacao.
local SALT = "r36s-port-hub/achv/v1"
local device_key
local function device_id()
  if device_key then return device_key end
  local id = U.read_file and (U.read_file("/etc/machine-id") or "") or ""
  id = id:gsub("%s", "")
  if id == "" then
    local ci = U.read_file and (U.read_file("/proc/cpuinfo") or "") or ""
    id = ci:match("Serial%s*:%s*(%w+)") or ""
  end
  if id == "" then id = "r36s" end
  device_key = id
  return id
end

local bxor = (rawget(_G, "bit") and bit.bxor) or function(a, b)
  local r, m = 0, 1
  while a > 0 or b > 0 do
    if (a % 2) ~= (b % 2) then r = r + m end
    a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
  end
  return r
end

--- hash FNV-1a de 32 bits (texto -> 8 digitos hexa)
local function fnv(str)
  local h = 2166136261
  for i = 1, #str do
    h = bxor(h, str:byte(i))
    if h < 0 then h = h + 4294967296 end
    h = ((h % 256) * 16777216 + h * 403) % 4294967296   -- h * 16777619 (2^24 + 403) mod 2^32, sem perder precisao
  end
  return string.format("%08x", h)
end

local function sign(list)
  local keys = {}
  for k in pairs(list) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(list[k]) end
  local body = table.concat(parts, ";")
  return fnv(SALT .. "|" .. device_id() .. "|" .. body) .. fnv(body .. "|" .. device_id())
end

local function load()
  if state then return state end
  state = {}
  local ok, txt = pcall(love.filesystem.read, FILE)
  if ok and txt then
    local okj, d = pcall(require("lib.json").decode, txt)
    if okj and type(d) == "table" then
      local list, legit = d, true
      if type(d.list) == "table" then
        list = d.list
        legit = d.sig == sign(list)
      end
      if legit then
        for k, v in pairs(list) do if A.BY_ID[k] then state[k] = tonumber(v) or 0 end end
      else
        U.log("conquistas: assinatura nao confere (arquivo de outro console?); ignorado")
        pcall(love.filesystem.write, "achievements_invalid.json", txt)
      end
    end
  end
  return state
end

local function save()
  local list = state or {}
  local ok, txt = pcall(require("lib.json").encode, { list = list, sig = sign(list) })
  if ok then
    local okw, err = pcall(love.filesystem.write, FILE, txt)
    if not okw then U.log("conquistas: falha ao salvar:", tostring(err)) end
  end
end

--- data (os.time) em que liberou, ou nil
function A.unlocked(id) return load()[id] end

function A.count(season)
  local n, t = 0, 0
  for _, d in ipairs(A.DEFS) do
    if not season or d.season == season then
      t = t + 1
      if load()[d.id] then n = n + 1 end
    end
  end
  return n, t
end

--- libera a conquista (so na primeira vez). Devolve true se foi liberada agora.
function A.unlock(id)
  local d = A.BY_ID[id]
  if not d then return false end
  local st = load()
  if st[id] then return false end
  st[id] = os.time()
  save()
  U.log("conquista liberada:", id)
  pcall(function() require("ui.achv_popup").show(d) end)
  pcall(function() require("core.assistant").event("achievement", require("lib.i18n").tr(d.name)) end)
  A.check_final()
  return true
end

--- conquista final ("Lenda"): libera quando todas as outras ja foram liberadas
function A.check_final()
  local st = load()
  for _, d in ipairs(A.DEFS) do
    if not d.final and not d.optional and not st[d.id] then return false end
  end
  for _, d in ipairs(A.DEFS) do
    if d.final and not st[d.id] then A.unlock(d.id) end
  end
  return true
end

--- libera sem comemorar agora (ex.: o hub vai fechar): a comemoracao aparece na
--- proxima abertura, por A.show_pending()
function A.unlock_later(id)
  local d = A.BY_ID[id]
  local st = load()
  if not d or st[id] then return end
  st[id] = os.time()
  save()
  Prefs.set("achv_pending", ((Prefs.get("achv_pending") or "") .. "," .. id):gsub("^,", ""))
end

function A.show_pending()
  local p = Prefs.get("achv_pending")
  if not p or p == "" then return end
  Prefs.set("achv_pending", "")
  for id in p:gmatch("[^,]+") do
    local d = A.BY_ID[id]
    if d then pcall(function() require("ui.achv_popup").show(d) end) end
  end
  A.check_final()
end

--- dias diferentes em que o hub foi aberto (conquista "Fa numero 1": 7 dias)
function A.track_day()
  local today = os.date("%Y-%m-%d")
  local list = Prefs.get("achv_days") or ""
  if not list:find(today, 1, true) then
    list = (list == "" and today) or (list .. "," .. today)
    local n, keep = 0, {}
    for d in list:gmatch("[^,]+") do keep[#keep + 1] = d end
    while #keep > 7 do table.remove(keep, 1) end
    list = table.concat(keep, ",")
    Prefs.set("achv_days", list)
  end
  local n = 0
  for _ in list:gmatch("[^,]+") do n = n + 1 end
  if n >= 7 then A.unlock("daily") end
end

--- carta "Feliz aniversário": libera se hoje for o aniversario do perfil
function A.check_birthday()
  local ok, P = pcall(require, "core.profile")
  if ok and P.is_birthday() then return A.unlock("birthday") end
  return false
end

--- apaga as conquistas (usado so pelo autoteste)
function A.reset()
  state = {}
  save()
end

-- ---------------------------------------------------------------------------
-- nome do usuario
function A.user_name()
  local v = Prefs.get("user_name")
  if v and v ~= "" then return v end
  return nil
end

function A.set_user_name(v)
  v = U.trim(v or "")
  if v == "" then return false end
  Prefs.set("user_name", v)
  return true
end

--- pergunta o nome (primeira abertura, ou ao trocar em Conquistas)
--- first = true: e a pergunta da abertura (cancelar pergunta de novo na proxima)
function A.ask_name(first, done)
  local Th = require("lib.i18n")
  App.push("textinput", {
    title = first and L("Bem-vindo ao R36S PORT HUB!") or L("Seu nome"),
    label = L("Como você quer ser chamado? (aparece nas suas conquistas)"),
    value = A.user_name() or "", mode = "full", max = 20,
    validate = function(v)
      if U.trim(v or "") == "" then return false, L("Digite pelo menos uma letra.") end
      return true
    end,
    on_ok = function(v)
      A.set_user_name(v)
      App.toast(string.format(Th.tr(L("Olá, %s!")), A.user_name() or ""), "ok")
      if done then done() end
    end,
    on_cancel = function() if done then done() end end,
  })
end

return A
