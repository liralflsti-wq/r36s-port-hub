-- =============================================================================
--  Biblioteca de jogos (emuladores do sistema)
--  Le o es_systems.cfg do PROPRIO console (dArkOS / dArkOSRE): sistemas,
--  pastas de ROMs, extensoes, comando e emuladores/cores. Os jogos abrem com
--  o mesmo comando que o EmulationStation usaria (%ROM%, %EMULATOR%, %CORE%,
--  %GOVERNOR%), pelo launcher do hub, com o app fechado.
--  Nomes e capas: gamelist.xml de cada pasta (formato do EmulationStation).
--  Nada e gravado nas pastas de ROMs nem no gamelist.xml.
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")
local C = require("config")
local json = require("lib.json")

local Lib = { systems = {}, by_name = {}, state = "idle", error = nil, scanned = false }

-- arquivo de sistemas (o caminho pode ser trocado para testes)
Lib.CFG_PATHS = { os.getenv("PORTHUB_ES_SYSTEMS") or "", "/etc/emulationstation/es_systems.cfg",
  (os.getenv("HOME") or "/home/ark") .. "/.emulationstation/es_systems.cfg" }
local CHOICES = "library_choices.json"   -- emulador/core escolhidos (sistema e jogo)
local FAVS = "library_favorites.json"
local RECENT = "library_recent.json"
local MAX_DEPTH = 3                        -- subpastas dentro da pasta do sistema

local function xml_unescape(s)
  s = tostring(s or "")
  s = s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&apos;", "'"):gsub("&#(%d+);", function(n)
    local c = tonumber(n); return c and c < 128 and string.char(c) or ""
  end):gsub("&amp;", "&")
  return s
end

local function tag(block, name)
  local v = block:match("<" .. name .. ">%s*(.-)%s*</" .. name .. ">")
  return v and xml_unescape(v) or nil
end

local function load_json(name, default)
  local ok, text = pcall(love.filesystem.read, name)
  local d = ok and text and json.decode(text)
  return type(d) == "table" and d or default
end

local function save_json(name, data)
  pcall(love.filesystem.write, name, json.encode(data))
end

--- caminho do es_systems.cfg usado (o primeiro que existir)
function Lib.cfg_path()
  for _, p in ipairs(Lib.CFG_PATHS) do
    if p ~= "" and U.exists(p) then return p end
  end
  return nil
end

--- le o es_systems.cfg. Devolve true ou false, motivo
function Lib.load_systems()
  Lib.systems, Lib.by_name = {}, {}
  local path = Lib.cfg_path()
  if not path then
    Lib.error = L("Este sistema não tem o arquivo de sistemas do EmulationStation (es_systems.cfg).")
    return false, Lib.error
  end
  local text = U.read_file(path) or ""
  text = text:gsub("<!%-%-.-%-%->", "")    -- comentarios
  for block in text:gmatch("<system>(.-)</system>") do
    local s = {
      name = tag(block, "name"), fullname = tag(block, "fullname"), path = tag(block, "path"),
      command = tag(block, "command"), platform = tag(block, "platform"), theme = tag(block, "theme"),
      manufacturer = tag(block, "manufacturer"), release = tag(block, "release"),
      exts = {}, emulators = {},
    }
    for e in (tag(block, "extension") or ""):gmatch("%S+") do s.exts[e:lower()] = true end
    local emus = block:match("<emulators>(.-)</emulators>")
    if emus then
      for ename, eb in emus:gmatch("<emulator%s+name=\"([^\"]+)\"%s*>(.-)</emulator>") do
        local cores = {}
        for core in eb:gmatch("<core>%s*(.-)%s*</core>") do cores[#cores + 1] = xml_unescape(core) end
        s.emulators[#s.emulators + 1] = { name = xml_unescape(ename), cores = cores }
      end
      -- emulador sem lista de cores (<emulator name="x"/>)
      for ename in emus:gmatch("<emulator%s+name=\"([^\"]+)\"%s*/>") do
        s.emulators[#s.emulators + 1] = { name = xml_unescape(ename), cores = {} }
      end
    end
    if s.name and s.path and s.command then
      s.path = s.path:gsub("/+$", "")
      s.fullname = s.fullname or s.name
      -- ports ficam em Meus Ports (o hub ja cuida deles)
      local ports = s.path == C.PORTS_DIR:gsub("/+$", "") or s.name == "ports"
      if not ports and not Lib.by_name[s.name .. "|" .. s.path] then
        s.key = s.name .. "|" .. s.path
        s.games = {}
        Lib.systems[#Lib.systems + 1] = s
        Lib.by_name[s.key] = s
      end
    end
  end
  Lib.cfg = path
  Lib.error = nil
  return true
end

-- ---------------------------------------------------------------------------
-- varredura das pastas (em segundo plano, sem travar a tela)
-- ---------------------------------------------------------------------------
local IGNORE = { ["gamelist.xml"] = true }
local IGNORE_DIRS = { images = true, videos = true, manuals = true, media = true, snap = true, snaps = true }

local function parse_gamelist(sys)
  local info = {}
  local text = U.read_file(sys.path .. "/gamelist.xml")
  if not text then return info end
  for block in text:gmatch("<game[%s>].-</game>") do
    local p = tag(block, "path")
    if p then
      p = p:gsub("^%./", "")
      local img = tag(block, "image") or tag(block, "thumbnail")
      if img then img = img:gsub("^%./", sys.path .. "/") end
      info[p] = { name = tag(block, "name"), image = img, desc = tag(block, "desc"),
        developer = tag(block, "developer"), genre = tag(block, "genre"), players = tag(block, "players"),
        releasedate = tag(block, "releasedate") }
    end
  end
  return info
end

local function add_game(sys, rel, size, glist)
  local base = rel:match("([^/]+)$") or rel
  if IGNORE[base:lower()] or base:sub(1, 1) == "." then return end
  local top = rel:match("^([^/]+)/")
  if top and IGNORE_DIRS[top:lower()] then return end
  local ext = base:match("(%.[^%.]+)$")
  if not ext or not sys.exts[ext:lower()] then return end
  local gi = glist[rel] or {}
  local name = gi.name or base:gsub("%.[^%.]+$", "")
  sys.games[#sys.games + 1] = { file = sys.path .. "/" .. rel, rel = rel, name = name, size = size,
    image = gi.image, desc = gi.desc, developer = gi.developer, genre = gi.genre, players = gi.players,
    releasedate = gi.releasedate, system = sys.key }
end

--- varre todas as pastas dos sistemas (find em segundo plano). on_done() ao terminar
function Lib.scan(on_done)
  if Lib.state == "scanning" then return end
  if #Lib.systems == 0 then
    local ok = Lib.load_systems()
    if not ok then Lib.state = "error"; if on_done then on_done() end; return end
  end
  local paths, seen = {}, {}
  for _, s in ipairs(Lib.systems) do
    if not seen[s.path] then seen[s.path] = true; paths[#paths + 1] = U.shq(s.path) end
  end
  Lib.state = "scanning"
  -- tamanho<TAB>caminho; so arquivos, sem seguir links de pastas
  local cmd = "find " .. table.concat(paths, " ") .. " -maxdepth " .. MAX_DEPTH
    .. " -type f -printf '%s\\t%p\\n' 2>/dev/null"
  require("core.shjob").start({ cmd }, function(results)
    local out = results and results[1] and results[1].out or ""
    for _, s in ipairs(Lib.systems) do s.games = {} end
    -- sistema por pasta (varios sistemas podem dividir a mesma pasta)
    local by_path = {}
    for _, s in ipairs(Lib.systems) do
      by_path[s.path] = by_path[s.path] or {}
      table.insert(by_path[s.path], s)
    end
    local glists = {}
    for line in out:gmatch("[^\n]+") do
      local size, file = line:match("^(%d+)\t(.+)$")
      if file then
        -- pasta do sistema = maior prefixo conhecido
        local dir = file
        local list, rel
        while true do
          dir = dir:match("^(.*)/[^/]*$")
          if not dir or dir == "" then break end
          if by_path[dir] then list = by_path[dir]; rel = file:sub(#dir + 2); break end
        end
        if list then
          for _, s in ipairs(list) do
            glists[s.path] = glists[s.path] or parse_gamelist(s)
            add_game(s, rel, tonumber(size), glists[s.path])
          end
        end
      end
    end
    for _, s in ipairs(Lib.systems) do
      table.sort(s.games, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    Lib.state, Lib.scanned, Lib.scan_time = "done", true, os.time()
    local n = 0
    for _, s in ipairs(Lib.systems) do n = n + #s.games end
    U.log("biblioteca: " .. #Lib.systems .. " sistemas, " .. n .. " jogos (" .. tostring(Lib.cfg) .. ")")
    if on_done then on_done() end
  end)
end

--- sistemas com pelo menos um jogo, na ordem do es_systems.cfg
function Lib.with_games()
  local out = {}
  for _, s in ipairs(Lib.systems) do if #s.games > 0 then out[#out + 1] = s end end
  return out
end

function Lib.total_games()
  local n = 0
  for _, s in ipairs(Lib.systems) do n = n + #s.games end
  return n
end

-- ---------------------------------------------------------------------------
-- emulador / core
-- ---------------------------------------------------------------------------
local choices
local function get_choices()
  choices = choices or load_json(CHOICES, { systems = {}, games = {} })
  choices.systems = choices.systems or {}
  choices.games = choices.games or {}
  return choices
end

--- emulador e core em uso para o jogo (escolha do jogo > do sistema > primeiro da lista)
function Lib.choice(sys, game)
  local c = get_choices()
  local pick = (game and c.games[game.file]) or c.systems[sys.key] or {}
  local emu = sys.emulators[1]
  for _, e in ipairs(sys.emulators) do if e.name == pick.emulator then emu = e end end
  if not emu then return nil, nil end
  local core = emu.cores[1]
  for _, k in ipairs(emu.cores) do if k == pick.core then core = k end end
  return emu.name, core
end

--- grava a escolha (game = nil para o sistema; emulator = nil volta ao padrao)
function Lib.set_choice(sys, game, emulator, core)
  local c = get_choices()
  local t = game and c.games or c.systems
  local k = game and game.file or sys.key
  t[k] = emulator and { emulator = emulator, core = core } or nil
  save_json(CHOICES, c)
end

function Lib.has_game_choice(game) return get_choices().games[game.file] ~= nil end

--- opcoes "emulador / core" do sistema, na ordem do es_systems.cfg
function Lib.options(sys)
  local out = {}
  for _, e in ipairs(sys.emulators) do
    if #e.cores == 0 then out[#out + 1] = { emulator = e.name }
    else for _, k in ipairs(e.cores) do out[#out + 1] = { emulator = e.name, core = k } end end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- favoritos e recentes (arquivos proprios do hub)
-- ---------------------------------------------------------------------------
local favs
local function get_favs() favs = favs or load_json(FAVS, {}); return favs end
function Lib.is_fav(game) return get_favs()[game.file] == true end
function Lib.toggle_fav(game)
  local f = get_favs()
  f[game.file] = (not f[game.file]) or nil
  save_json(FAVS, f)
  return f[game.file] == true
end

function Lib.recent() return load_json(RECENT, {}) end
local function push_recent(sys, game)
  local list = load_json(RECENT, {})
  for i = #list, 1, -1 do if list[i].file == game.file then table.remove(list, i) end end
  table.insert(list, 1, { file = game.file, name = game.name, system = sys.key, sysname = sys.fullname,
    image = game.image, t = os.time() })
  while #list > 30 do table.remove(list) end
  save_json(RECENT, list)
end

function Lib.find_game(file)
  for _, s in ipairs(Lib.systems) do
    for _, g in ipairs(s.games) do if g.file == file then return s, g end end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- comando do jogo (igual ao do EmulationStation)
-- ---------------------------------------------------------------------------
function Lib.command(sys, game)
  local emu, core = Lib.choice(sys, game)
  local cmd = sys.command
  local function rep(k, v) cmd = cmd:gsub("%%" .. k .. "%%", function() return v end) end
  rep("ROM", U.shq(game.file))
  rep("BASENAME", U.shq((game.file:match("([^/]+)$") or ""):gsub("%.[^%.]+$", "")))
  rep("ROM_RAW", game.file)
  rep("EMULATOR", emu or "")
  rep("CORE", core or "")
  rep("GOVERNOR", "")       -- o EmulationStation passa vazio quando nao ha escolha
  return cmd, emu, core
end

--- abre o jogo: o hub fecha, o launcher roda o comando e reabre o hub depois
function Lib.launch(sys, game)
  local cmd, emu, core = Lib.command(sys, game)
  os.execute("mkdir -p " .. U.shq(C.APP_DIR .. "/conf") .. " 2>/dev/null")
  local ret = (sys.name or "x"):gsub("[^%w_%-]", "")
  if not U.write_file(C.APP_DIR .. "/conf/.run_game", ret .. "\n" .. cmd .. "\n") then
    return false, L("Não foi possível abrir o jogo (pasta do app somente leitura?).")
  end
  push_recent(sys, game)
  U.log("biblioteca: abrindo", sys.name, game.rel, tostring(emu), tostring(core))
  return true
end

return Lib
