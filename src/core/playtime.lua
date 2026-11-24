-- =============================================================================
--  Tempo de jogo dos jogos abertos PELO HUB (Biblioteca e ports)
--    PT.start(key, name, kind)  antes do hub fechar para abrir o jogo
--    PT.finish()                na volta: le conf/.play_time (o launcher grava
--                               inicio e fim do jogo) e soma a sessao.
--                               Devolve { key, name, secs, total, sessions } ou nil
--    PT.get(key) / PT.total() / PT.top(n) / PT.format(secs)
--  Salvo em playtime.json (pasta de dados do app):
--    { games = { [key] = { name, kind, secs, sessions, last } } }
--  Sem o arquivo do launcher, mede pela hora em que o hub fechou e reabriu.
--  Sessoes com menos de 10 s ou mais de 24 h sao ignoradas (relogio errado).
-- =============================================================================
local C = require("config")
local U = require("lib.util")
local J = require("lib.json")
local Prefs = require("core.prefs")
local L = require("lib.i18n").L
local I18N = require("lib.i18n")

local PT = {}
local FILE = "playtime.json"
local data

local function load()
  if data then return data end
  local s = love.filesystem.read(FILE)
  local ok, t = pcall(J.decode, s or "")
  data = (ok and type(t) == "table") and t or {}
  data.games = type(data.games) == "table" and data.games or {}
  return data
end

local function save() pcall(love.filesystem.write, FILE, J.encode(load())) end

function PT.start(key, name, kind)
  if not key then return end
  os.remove(C.APP_DIR .. "/conf/.play_time")   -- sobra de uma sessao antiga
  Prefs.set("play_pending", J.encode({ key = tostring(key), name = name or tostring(key), kind = kind or "game", t = os.time() }))
end

function PT.finish()
  local raw = Prefs.get("play_pending")
  if not raw or raw == "" then return nil end
  Prefs.set("play_pending", "")
  local ok, p = pcall(J.decode, raw)
  if not ok or type(p) ~= "table" or not p.key then return nil end
  local f = C.APP_DIR .. "/conf/.play_time"
  local s = U.read_file and U.read_file(f) or nil
  if not s then
    local h = io.open(f, "r")
    if h then s = h:read("*a"); h:close() end
  end
  os.remove(f)
  local t0, t1 = tostring(s or ""):match("(%d+)%s+(%d+)")
  t0, t1 = tonumber(t0), tonumber(t1)
  local secs
  if t0 and t1 then
    secs = t1 - t0                      -- medido pelo launcher (mais preciso)
  elseif tonumber(p.t) then
    -- launcher antigo (ainda rodando a versao de antes do update) ou sem o
    -- arquivo: usa a hora em que o hub fechou e a hora em que abriu de novo,
    -- descontando uns segundos de abertura do jogo e do hub
    secs = os.time() - tonumber(p.t) - 8
    U.log("tempo de jogo: sem .play_time, usando a hora do hub")
  else
    return nil
  end
  if secs < 10 or secs > 24 * 3600 then return nil end
  local d = load()
  local g = d.games[p.key] or { name = p.name, kind = p.kind, secs = 0, sessions = 0 }
  g.name = p.name or g.name
  g.secs = (g.secs or 0) + secs
  g.sessions = (g.sessions or 0) + 1
  g.last = os.time()
  d.games[p.key] = g
  save()
  U.log("tempo de jogo:", p.key, secs, "s (total " .. g.secs .. " s)")
  PT.check_achievements()
  return { key = p.key, name = g.name, secs = secs, total = g.secs, sessions = g.sessions }
end

--- conquistas de tempo de jogo (1 h, 10 h, 50 h somados)
function PT.check_achievements()
  local t = PT.total()
  local A = require("core.achievements")
  if t >= 3600 then A.unlock("playtime_1h") end
  if t >= 10 * 3600 then A.unlock("playtime_10h") end
  if t >= 50 * 3600 then A.unlock("playtime_50h") end
end

function PT.get(key) return load().games[tostring(key)] end

function PT.total()
  local n = 0
  for _, g in pairs(load().games) do n = n + (g.secs or 0) end
  return n
end

--- jogos mais jogados (maior tempo primeiro)
function PT.top(n)
  local list = {}
  for k, g in pairs(load().games) do list[#list + 1] = { key = k, name = g.name, secs = g.secs or 0, sessions = g.sessions or 0, last = g.last } end
  table.sort(list, function(a, b) return a.secs > b.secs end)
  if n then while #list > n do table.remove(list) end end
  return list
end

--- 3h 05min | 12min | menos de 1 min
function PT.format(secs)
  secs = math.floor(tonumber(secs) or 0)
  if secs < 60 then return I18N.tr(L("menos de 1 min")) end
  local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
  if h > 0 then return string.format("%dh %02dmin", h, m) end
  return string.format("%dmin", m)
end

--- tela com o resumo e o ranking (Meu perfil > Tempo de jogo)
function PT.open_list() App.push("playtime") end

return PT
