-- =============================================================================
--  Loja de Temas: as mesmas fontes do ThemeMaster (JohnIrvine1433/ThemeMaster)
--
--  1) Galeria (modo "Theme Gallery" do ThemeMaster): tabela do README da
--     Emulationstation-OGA-Theme-Gallery (Jetup13), com a imagem de cada tema e
--     se funciona em cada tamanho de tela (Yes / No / Untested).
--  2) Colecoes do GitHub (modo "GitHub Repository" do ThemeMaster): repositorios
--     "es-theme*" de cada autor da lista de colecoes (a padrao do ThemeMaster ou a
--     do ThemeMaster.cfg, se o ThemeMaster estiver instalado no console).
--  Lido com a mesma regra do catalogo: no maximo a cada 6 h, com copia salva para
--  usar sem internet. Quando a galeria ou as colecoes mudam, a loja muda junto,
--  sem precisar de uma versao nova do hub.
-- =============================================================================
local U = require("lib.util")
local json = require("lib.json")
local Fetcher = require("core.fetcher")

local G = {}
G.SIZES = { "480x320", "640x480", "854x480", "960x544", "720x720" }
G.GALLERY_URL = os.getenv("PORTHUB_ES_GALLERY_URL")   -- (so para testes do desenvolvedor)
  or "https://raw.githubusercontent.com/Jetup13/Emulationstation-OGA-Theme-Gallery/main/README.md"
G.GALLERY_PAGE = "https://github.com/Jetup13/Emulationstation-OGA-Theme-Gallery"
G.API_USER = os.getenv("PORTHUB_ES_API_USER") or "https://api.github.com/users/%s/repos?per_page=100"
G.DEFAULT_COLLECTIONS = { "Jetup13", "CodyV59", "farfenkugell", "EmuELEC", "RetroPie" }
local CACHE = "es_gallery_cache.json"
local MAX_AGE = 6 * 3600

G.data = nil      -- { time, gallery = {...}, collections = { user = {...} } }

local STATUS = { yes = "yes", no = "no", untested = "untested" }

--- linhas "| [Nome](https://github.com/conta/repo) | ![](imagem) |Yes|No|...|"
function G.parse_gallery(text)
  local out = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local name, owner, repo = line:match("^|%s*%[([^%]]+)%]%(https://github%.com/([%w%._%-]+)/([%w%._%-]+)/?%)")
    if name then
      local preview = line:match("!%[[^%]]*%]%((https?://[^%)%s]+)%)")
      local cells = {}
      local rest = line:match("^|[^|]*|[^|]*(|.*)$") or ""
      for cell in rest:gmatch("|([^|]*)") do
        local v = U.trim(cell):lower():gsub("[^%a]", "")
        if v ~= "" then cells[#cells + 1] = v end
      end
      local res = {}
      for i, size in ipairs(G.SIZES) do res[size] = STATUS[cells[i] or ""] or "untested" end
      repo = repo:gsub("%.git$", "")
      out[#out + 1] = { name = U.trim(name), owner = owner, repo = repo, preview = preview, res = res,
        url = "https://github.com/" .. owner .. "/" .. repo }
    end
  end
  return out
end

--- resposta da API (lista de repositorios de um usuario): so os "es-theme*", como o ThemeMaster
function G.parse_repos(text, user)
  local d = json.decode(text or "")
  if type(d) ~= "table" then return nil end
  local out = {}
  for _, r in ipairs(d) do
    if type(r) == "table" and type(r.name) == "string" and r.name:lower():match("^es%-theme")
        and r.name:match("^[%w%._%-]+$") and not r.fork and not r.archived then
      out[#out + 1] = { repo = r.name, owner = (type(r.owner) == "table" and r.owner.login) or user,
        url = type(r.html_url) == "string" and r.html_url or ("https://github.com/" .. user .. "/" .. r.name),
        branch = type(r.default_branch) == "string" and r.default_branch:match("^[%w%._%-/]+$") and r.default_branch or nil,
        description = type(r.description) == "string" and r.description or nil,
        updated = type(r.pushed_at) == "string" and r.pushed_at:sub(1, 10) or nil }
    end
  end
  return out
end

--- lista de colecoes: a do ThemeMaster.cfg (quando o ThemeMaster esta no console) ou a padrao dele
function G.collections(tm)
  local list = {}
  local cfg = tm and tm.dir and U.read_file(tm.dir .. "/ThemeMaster.cfg") or ""
  local arr = cfg:match("collections=%(([^%)]*)%)")
  if arr then
    for name in arr:gmatch('"?([%w%._%-]+)"?') do list[#list + 1] = name end
  end
  if #list == 0 then for _, n in ipairs(G.DEFAULT_COLLECTIONS) do list[#list + 1] = n end end
  return list
end

function G.load_cache()
  local ok, text = pcall(love.filesystem.read, CACHE)
  local d = ok and text and json.decode(text) or nil
  if type(d) == "table" and type(d.gallery) == "table" then G.data = d end
  return G.data
end

local function save()
  if G.data then pcall(love.filesystem.write, CACHE, json.encode(G.data)) end
end

--- atualiza (galeria + colecoes). on_done(status): "ok" | "partial" | "failed" | "recent"
function G.refresh(tm, force, on_done)
  G.load_cache()
  if not force and G.data and G.data.time and os.time() - G.data.time < MAX_AGE
      and type(G.data.gallery) == "table" and #G.data.gallery > 0 then
    if on_done then on_done("recent") end
    return
  end
  if G.busy then return end
  G.busy = true
  local dir = love.filesystem.getSaveDirectory()
  local new = { time = os.time(), gallery = G.data and G.data.gallery or {}, collections = G.data and G.data.collections or {} }
  local users = G.collections(tm)
  local okg, failures = false, 0
  local function finish()
    G.busy = false
    if okg or failures < #users then
      G.data = new
      save()
    end
    local st = (okg and failures == 0) and "ok" or ((okg or failures < #users) and "partial" or "failed")
    if on_done then on_done(st) end
  end
  local i = 0
  local function next_user()
    i = i + 1
    local u = users[i]
    if not u then return finish() end
    local out = dir .. "/es_coll_" .. u .. ".dl"
    Fetcher.get("catalog", G.API_USER:format(u), out, function(ok, path)
      local list = ok and G.parse_repos(U.read_file(path)) or nil
      if path then os.remove(path) end
      if list then new.collections[u] = list else failures = failures + 1 end
      next_user()
    end, true)
  end
  Fetcher.get("catalog", G.GALLERY_URL, dir .. "/es_gallery.dl", function(ok, path)
    local list = ok and G.parse_gallery(U.read_file(path)) or nil
    if path then os.remove(path) end
    if list and #list > 0 then new.gallery = list; okg = true end
    next_user()
  end, true)
end

--- tamanho de tela do console mais proximo da lista da galeria
function G.detect_size()
  local ok, Compat = pcall(require, "core.compat")
  local e = ok and Compat.detect() or {}
  local w, h = tostring(e.res or ""):match("^(%d+)x(%d+)$")
  w, h = tonumber(w), tonumber(h)
  if not w then return "640x480", false end
  if h > w then w, h = h, w end   -- painel em pe (retrato)
  local key = w .. "x" .. h
  for _, s in ipairs(G.SIZES) do if s == key then return s, true end end
  return "640x480", false
end

return G
