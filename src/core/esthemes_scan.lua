-- =============================================================================
--  Loja de Temas: reconhecimento dos temas que EXISTEM no console
--
--  Como o dArkOS/dArkOSRE organiza os temas (conferido nos scripts de build):
--   - /etc/emulationstation/themes e um link para /roms/themes (finishing_touches.sh);
--   - com dois cartoes, /home/ark/.emulationstation/themes aponta para /roms2/themes;
--   - os temas de fabrica sao "git clone" colocados em /tempthemes e copiados para
--     /roms/themes no primeiro boot (expandtoexfat.sh): por isso costumam ter .git;
--   - o tema em uso e o ThemeSet de ~/.emulationstation/es_settings.cfg (nome da pasta).
--  Identificacao (da mais forte para a mais fraca): marcador .porthub_theme gravado
--  pelo hub, registro de instalacao do hub, repositorio de origem em .git/config,
--  registro do ThemeMaster (data/<tema>.version) e, por fim, nome da pasta + theme.xml.
--  Somente leitura: nada aqui altera arquivos.
-- =============================================================================
local U = require("lib.util")
local L = require("lib.i18n").L

local S = {}
local ROOT = os.getenv("PORTHUB_ROOTFS") or ""

-- Temas que acompanham a imagem do sistema (fontes: scripts oficiais de build)
--  dArkOS (rk3326, finishing_touches.sh): freeplay, minimal-arkos, nes-box, switch, replica
--  dArkOSRE-R36 (files/ROOTFS/tempthemes): colorful-v2, retrooz (+ a base do dArkOS)
S.FACTORY = {
  darkos = { "es-theme-freeplay", "es-theme-minimal-arkos", "es-theme-nes-box", "es-theme-switch", "es-theme-replica" },
  darkosre = { "es-theme-colorful-v2", "es-theme-retrooz", "es-theme-freeplay", "es-theme-minimal-arkos",
    "es-theme-nes-box", "es-theme-switch", "es-theme-replica" },
}

local function read(p, n)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read(n or "*a")
  f:close()
  return s
end
local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end return false end

--- pastas de temas que o EmulationStation le neste console (sem repetir o mesmo destino)
function S.roots(catalog_dir, tm)
  local cands = {}
  if catalog_dir then cands[#cands + 1] = catalog_dir end
  cands[#cands + 1] = "/etc/emulationstation/themes"
  cands[#cands + 1] = "/home/ark/.emulationstation/themes"
  if tm and tm.themes_location then cands[#cands + 1] = (tm.themes_location:gsub("/+$", "")) end
  local out, seen = {}, {}
  for _, d in ipairs(cands) do
    local p = ROOT .. d
    if U.exec_ok("test -d " .. U.shq(p)) then
      local real = U.trim(U.capture("readlink -f -- " .. U.shq(p) .. " 2>/dev/null") or "")
      if real == "" then real = p end
      if not seen[real] then
        seen[real] = true
        out[#out + 1] = { path = p, real = real, readable = U.exec_ok("test -r " .. U.shq(p) .. " -a -x " .. U.shq(p)) }
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- ThemeMaster (JohnIrvine1433/ThemeMaster): pasta, configuracao e registros
local TM_DIRS = { "/opt/system/Tools/ThemeMaster", "/roms/tools/ThemeMaster", "/roms2/tools/ThemeMaster" }

function S.thememaster(ports_dir)
  local list = {}
  for _, d in ipairs(TM_DIRS) do list[#list + 1] = ROOT .. d end
  if ports_dir then list[#list + 1] = ports_dir .. "/ThemeMaster" end
  for _, d in ipairs(list) do
    if exists(d .. "/ThemeMaster") then
      local tm = { dir = d, versions = {}, gallery = {} }
      local cfg = read(d .. "/ThemeMaster.cfg") or ""
      tm.themes_location = cfg:match('themes_location="([^"]*)"')
      if tm.themes_location == "" then tm.themes_location = nil end
      local ver = (read(d .. "/ThemeMaster") or ""):match('current_app_version="([^"]+)"')
      tm.version = ver
      -- data/<tema>.version: data do ultimo commit instalado pelo ThemeMaster
      local names = U.capture("ls -1 " .. U.shq(d .. "/data") .. " 2>/dev/null") or ""
      for n in names:gmatch("[^\n]+") do
        local theme = n:match("^(.+)%.version$")
        if theme and theme ~= "gallery" then
          tm.versions[theme] = U.trim(read(d .. "/data/" .. n) or "")
        end
        local png = n:match("^(.+)%.png$")
        if png then tm.gallery[png] = tm.gallery[png] or {}; tm.gallery[png].preview = d .. "/data/" .. n end
      end
      -- data/gallery.db: "conta repositorio 480x320 640x480 854x480 960x544 720x720"
      local db = read(d .. "/data/gallery.db") or ""
      local first = true
      for line in db:gmatch("[^\n]+") do
        if first then first = false
        else
          local acc, repo, _, r640 = line:match("^(%S+)%s+(%S+)%s+(%S*)%s*(%S*)")
          if acc and repo then
            tm.gallery[repo] = tm.gallery[repo] or {}
            tm.gallery[repo].author, tm.gallery[repo].r640 = acc, r640
          end
        end
      end
      return tm
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
--- repositorio de origem (dono/repo) em .git/config, se houver
local function git_repo(path)
  local cfg = read(path .. "/.git/config")
  if not cfg then return nil end
  local url = cfg:match('%[remote "origin"%][^%[]-url%s*=%s*([^\r\n]+)')
  if not url then return nil end
  local owner, repo = url:match("github%.com[:/]([^/%s]+)/([^/%s]+)")
  if not owner then return nil, url end
  repo = repo:gsub("%.git$", "")
  return (owner .. "/" .. repo):lower(), url
end

--- estrutura: theme.xml na raiz (com os <include> existentes) ou nas pastas de sistema
local function structure(path)
  local xml = read(path .. "/theme.xml")
  local r = { missing = {} }
  if xml then
    r.root_xml = true
    r.xml_ok = xml:find("<theme") ~= nil
    for inc in xml:gmatch("<include>%s*([^<]-)%s*</include>") do
      if not inc:find("%$") and not inc:find("^/") then
        local rel = inc:gsub("^%./", "")
        if not rel:find("%.%.") and not exists(path .. "/" .. rel) then r.missing[#r.missing + 1] = rel end
      end
    end
    return r
  end
  local sub = U.trim(U.capture("find " .. U.shq(path) .. " -mindepth 2 -maxdepth 2 -name theme.xml 2>/dev/null | head -n 1") or "")
  r.sub_xml = sub ~= ""
  r.xml_ok = r.sub_xml
  return r
end

--- imagem do proprio tema (so arquivos que o tema traz)
local function own_preview(path)
  local out = U.capture("cd " .. U.shq(path) .. " 2>/dev/null && ls -1 2>/dev/null | grep -iE '^(preview|screenshot|theme)[^/]*\\.(png|jpg)$|gamelist\\.png$' | head -n 1") or ""
  local f = U.trim(out)
  return f ~= "" and (path .. "/" .. f) or nil
end

--- varre as pastas. registry: temas instalados pelo hub (id -> {folder, dir})
function S.scan(roots, os_id, registry, tm)
  local res = { list = {}, by_folder = {}, unreadable = {} }
  local factory = {}
  for _, f in ipairs(S.FACTORY[os_id or ""] or {}) do factory[f] = true end
  local hub_folders = {}
  for id, rec in pairs(registry or {}) do
    if type(rec) == "table" and rec.folder then hub_folders[rec.folder] = id end
  end
  for _, r in ipairs(roots) do
    if not r.readable then
      res.unreadable[#res.unreadable + 1] = r.path
    else
      -- um "ls -l" por pasta de temas: tipo (pasta/link) e nome
      local out = U.capture("ls -1ApL " .. U.shq(r.path) .. " 2>/dev/null") or ""
      for name in out:gmatch("[^\n]+") do
        local folder = name:match("^(.-)/$")
        if folder and folder:sub(1, 1) ~= "." then
          local path = r.path .. "/" .. folder
          if not res.by_folder[folder] then
            local loc = { folder = folder, path = path, root = r.path, root_real = r.real }
            loc.is_link = U.trim(U.capture("test -L " .. U.shq(path) .. " && echo L") or "") == "L"
            loc.readable = U.exec_ok("test -r " .. U.shq(path) .. " -a -x " .. U.shq(path))
            if loc.readable then
              local st = structure(path)
              loc.xml_ok, loc.missing = st.xml_ok, st.missing
              loc.incomplete = (not st.xml_ok) or #st.missing > 0
              loc.marker = U.trim((read(path .. "/.porthub_theme") or ""):match("^[^\n]*") or "")
              if loc.marker == "" then loc.marker = nil end
              loc.repo, loc.git_url = git_repo(path)
              loc.preview = own_preview(path)
            end
            -- origem (evidencia registrada para mostrar ao usuario)
            if loc.marker or hub_folders[folder] then
              loc.origin, loc.evidence = "hub", loc.marker and ".porthub_theme" or "es_themes_installed.json"
              loc.hub_id = loc.marker or hub_folders[folder]
            elseif tm and tm.versions[folder] then
              loc.origin, loc.evidence = "thememaster", "ThemeMaster/data/" .. folder .. ".version"
              loc.tm_version = tm.versions[folder]
            elseif factory[folder] then
              loc.origin = "firmware"
              loc.evidence = loc.repo and (".git: " .. loc.repo) or L("lista de build do sistema")
            else
              loc.origin, loc.evidence = "user", loc.repo and (".git: " .. loc.repo) or nil
            end
            res.by_folder[folder] = loc
            res.list[#res.list + 1] = loc
          end
        end
      end
    end
  end
  table.sort(res.list, function(a, b) return a.folder:lower() < b.folder:lower() end)
  return res
end

--- repositorio "dono/repo" a partir da URL do projeto no catalogo
function S.repo_of(url)
  if type(url) ~= "string" then return nil end
  local o, r = url:match("github%.com/([^/%s]+)/([^/%s#?]+)")
  if not o then return nil end
  return (o .. "/" .. r:gsub("%.git$", "")):lower()
end

return S
