-- =============================================================================
--  Temas visuais (Configuracoes > Temas)
--  Cada tema e SO DADOS (theme.json: cores, botoes, estilo + preview.png).
--  Nenhum codigo e executado a partir de um tema.
--    - Temas que acompanham o app:  themes/<id>/            (dentro do game.love)
--    - Temas baixados (futuro):     <dados do app>/user_themes/<id>/
--      (fora dos arquivos do app; instalar/remover nunca toca nos temas inclusos)
--  O tema escolhido fica salvo em theme.txt (pasta de dados do app).
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")
local json = require("lib.json")
local T = require("ui.theme")

local M = { list = {}, current = "default", DEFAULT = "default" }
-- ids antigos -> ids atuais (quem usava o tema antigo continua com ele, ja renomeado)
M.ALIASES = { xbox = "neongrid" }
local function resolve(id) return M.ALIASES[id] or id end
M.resolve = resolve
local PREF = "theme.txt"
local BUILTIN_DIR = "themes"
M.USER_DIR = "user_themes"

local COLOR_KEYS = { "bg0", "bg1", "bg2", "bg3", "line", "text", "dim", "faint", "accent", "accent2",
  "yellow", "green", "red", "orange", "black", "shadow" }
local BUTTON_KEYS = { "a", "b", "x", "y", "l1", "r1", "start", "select", "dpad" }

--- le e valida um theme.json. Devolve tema ou nil, motivo
local function load_def(dir, builtin)
  local ok, text = pcall(love.filesystem.read, dir .. "/theme.json")
  if not ok or not text then return nil, L("theme.json não encontrado") end
  local d = json.decode(text)
  if type(d) ~= "table" then return nil, L("theme.json inválido") end
  if type(d.id) ~= "string" or not d.id:match("^[%w_%-]+$") then return nil, L("id inválido") end
  if type(d.colors) ~= "table" then return nil, L("sem cores") end
  local th = { id = d.id, name = tostring(d.name or d.id), description = tostring(d.description or ""),
    version = tostring(d.version or ""), author = tostring(d.author or ""), dir = dir, builtin = builtin,
    colors = {}, buttons = {}, style = {} }
  -- todas as cores sao obrigatorias: um tema incompleto nao e aplicado
  for _, k in ipairs(COLOR_KEYS) do
    local c = T.parse_hex(d.colors[k])
    if not c then return nil, L("cor \"") .. k .. L("\" ausente ou inválida") end
    th.colors[k] = c
  end
  for _, k in ipairs(BUTTON_KEYS) do
    local c = T.parse_hex(type(d.buttons) == "table" and d.buttons[k] or nil)
    if c then th.buttons[k] = c end
  end
  local st = type(d.style) == "table" and d.style or {}
  th.style.background = (st.background == "modern" or st.background == "neongrid") and st.background or "retro"
  -- layout da tela inicial: "dashboard" (NEON GRID) ou o classico
  th.style.layout = (st.layout == "dashboard") and "dashboard" or nil
  th.style.round = U.clamp(tonumber(st.round) or 1, 0, 1.5)
  th.style.glow = T.parse_hex(st.glow) or th.colors.accent
  th.style.scanlines = st.scanlines ~= false
  -- logo propria do tema (opcional): logo_header.png, logo_menu.png, logo_about.png
  if love.filesystem.getInfo(dir .. "/logo_menu.png") then th.style.logo_dir = dir end
  if type(d.preview) == "string" and d.preview:match("^[%w_%-%.]+%.png$") then
    th.preview = dir .. "/" .. d.preview
  end
  return th
end

--- procura os temas inclusos e os instalados pelo usuario
function M.scan()
  M.list, M.by_id, M.errors = {}, {}, {}
  local function add(dir, builtin)
    local th, err = load_def(dir, builtin)
    if th and not M.by_id[th.id] then
      M.list[#M.list + 1] = th
      M.by_id[th.id] = th
    elseif not th then
      M.errors[#M.errors + 1] = dir .. ": " .. tostring(err)
      U.log("tema ignorado:", dir, err)
    end
  end
  -- inclusos: padrao primeiro
  add(BUILTIN_DIR .. "/default", true)
  for _, n in ipairs(love.filesystem.getDirectoryItems(BUILTIN_DIR)) do
    if n ~= "default" then add(BUILTIN_DIR .. "/" .. n, true) end
  end
  -- instalados (futuro: baixados do catalogo de temas)
  if love.filesystem.getInfo(M.USER_DIR, "directory") then
    for _, n in ipairs(love.filesystem.getDirectoryItems(M.USER_DIR)) do add(M.USER_DIR .. "/" .. n, false) end
  end
end

--- aplica um tema (sem reiniciar). Devolve true ou false, motivo
function M.apply(id, save)
  id = resolve(id)
  local th = M.by_id and M.by_id[id]
  if not th then return false, L("tema não encontrado") end
  T.apply_palette(th.colors, th.buttons, th.style)
  require("ui.gfx").build_background()
  M.current = id
  if save then pcall(love.filesystem.write, PREF, id) end
  return true
end

--- na abertura: aplica o ultimo tema escolhido; se falhar, volta ao padrao
--- Devolve uma mensagem de aviso (ou nil)
function M.init()
  M.scan()
  local ok, saved = pcall(love.filesystem.read, PREF)
  saved = ok and saved and U.trim(saved) or M.DEFAULT
  if saved == "" then saved = M.DEFAULT end
  -- migracao: tema salvo com o id antigo (ex.: xbox -> neongrid) e regravado com o novo
  if M.ALIASES[saved] then
    U.log("tema: id antigo", saved, "migrado para", resolve(saved))
    saved = resolve(saved)
    pcall(love.filesystem.write, PREF, saved)
  end
  if saved ~= M.DEFAULT then
    local applied = M.apply(saved, false)
    if applied then return nil end
    U.log("tema salvo indisponivel:", saved)
    M.apply(M.DEFAULT, true)
    return L("O tema escolhido não pôde ser carregado. Usando o Tema Padrão.")
  end
  if not M.apply(M.DEFAULT, false) then
    -- sem o theme.json padrao: continua com as cores embutidas em ui/theme.lua
    M.current = M.DEFAULT
  end
  return nil
end

--- endereco do catalogo de temas (futuro): config.lua ou themes_url.txt
function M.catalog_url()
  local s = U.read_file(C.APP_DIR .. "/themes_url.txt")
  if s then
    s = U.trim(s:match("^[^\r\n]*") or "")
    if s:match("^https?://") then return s end
  end
  if C.THEMES_CATALOG_URL and C.THEMES_CATALOG_URL:match("^https?://") then return C.THEMES_CATALOG_URL end
  return nil
end

return M
