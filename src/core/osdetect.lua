-- =============================================================================
--  Identificacao do sistema operacional do console (somente leitura)
--  Nunca decide por uma informacao isolada: soma evidencias e informa o nivel
--  de confianca. So "alta" (2+ evidencias independentes) conta como confirmado.
--    dArkOSRE / dArkOS / ArkOS: /usr/share/plymouth/themes/text.plymouth (title=...)
--        + /home/ark/.config/.VERSION + /etc/emulationstation/themes -> /roms/themes
--    AmberELEC / ROCKNIX / JELOS / KNULLI / Batocera: /etc/os-release (NAME/ID)
--        + pastas e arquivos proprios de cada sistema
--  PORTHUB_ROOTFS (so testes) prefixa todos os caminhos.
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")

local D = {}
local R = os.getenv("PORTHUB_ROOTFS") or ""

D.NAMES = { darkosre = "dArkOSRE", darkos = "dArkOS", arkos = "ArkOS", amberelec = "AmberELEC",
  rocknix = "ROCKNIX", knulli = "KNULLI", jelos = "JELOS", batocera = "Batocera" }
D.ORDER = { "darkosre", "darkos", "arkos", "amberelec", "rocknix", "knulli", "jelos", "batocera" }

local function read(p, n)
  local f = io.open(R .. p, "r")
  if not f then return nil end
  local s = f:read(n or "*a")
  f:close()
  return s
end
local function exists(p) return U.exec_ok("test -e " .. U.shq(R .. p)) end
local function is_dir(p) return U.exec_ok("test -d " .. U.shq(R .. p)) end
local function link_target(p)
  local t = U.capture("readlink " .. U.shq(R .. p) .. " 2>/dev/null") or ""
  return U.trim(t)
end

local function os_release()
  local t = {}
  for line in (read("/etc/os-release") or ""):gmatch("[^\n]+") do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k then t[k] = (v:gsub('^"(.*)"$', "%1")) end
  end
  return t
end

--- Devolve { id, name, version, confidence = "alta"|"media"|"baixa"|nil,
---           confirmed = bool, evidence = { textos } }
function D.detect()
  local ev = {}
  local scores = {}
  local versions = {}
  local function add(id, pts, why)
    scores[id] = (scores[id] or 0) + pts
    ev[id] = ev[id] or {}
    ev[id][#ev[id] + 1] = why
  end

  -- familia ArkOS: titulo de boot gravado pelo proprio sistema
  local title = (read("/usr/share/plymouth/themes/text.plymouth") or ""):match("title=([^\n]*)")
  local ark_ver = U.trim(read("/home/ark/.config/.VERSION") or "")
  local fam
  if title then
    local tl = title:lower()
    if tl:match("^darkosre") then fam = "darkosre"
    elseif tl:match("^darkos") then fam = "darkos"
    elseif tl:match("^arkos") then fam = "arkos" end
    if fam then
      add(fam, 2, L("título do sistema: ") .. U.trim(title))
      versions[fam] = title:match("%(([^%)]+)%)") or title:match("(%d%d+[%d%.]*)")
    end
  end
  if fam then
    if ark_ver ~= "" then add(fam, 1, L("versão em /home/ark/.config/.VERSION: ") .. ark_ver); versions[fam] = versions[fam] or ark_ver end
    local lt = link_target("/etc/emulationstation/themes")
    if lt:match("/roms/themes") then add(fam, 1, L("temas do EmulationStation apontam para /roms/themes")) end
  end

  -- sistemas baseados em os-release
  local osr = os_release()
  local name = ((osr.NAME or "") .. " " .. (osr.ID or "")):lower()
  local function osr_match(id, pat, extra_paths)
    if name:find(pat) then
      add(id, 2, "/etc/os-release: " .. (osr.PRETTY_NAME or osr.NAME or id))
      versions[id] = osr.VERSION_ID or osr.VERSION
      for _, p in ipairs(extra_paths or {}) do
        if exists(p) then add(id, 1, L("encontrado ") .. p) break end
      end
    end
  end
  osr_match("amberelec", "amberelec", { "/storage/.config/emulationstation", "/storage/roms" })
  osr_match("rocknix", "rocknix", { "/storage/.emulationstation", "/storage/roms" })
  osr_match("jelos", "jelos", { "/storage/.config/emulationstation", "/storage/roms" })
  osr_match("knulli", "knulli", { "/userdata/themes", "/userdata/roms" })
  if not name:find("knulli") then
    osr_match("batocera", "batocera", { "/usr/share/batocera/batocera.version", "/userdata/roms" })
  end
  local bv = U.trim(read("/usr/share/batocera/batocera.version") or "")
  if bv ~= "" and not scores.knulli then add("batocera", 1, L("batocera.version: ") .. bv); versions.batocera = versions.batocera or bv end

  -- melhor resultado
  local best, bs = nil, 0
  for _, id in ipairs(D.ORDER) do
    if (scores[id] or 0) > bs then best, bs = id, scores[id] end
  end
  if not best then return { confidence = nil, confirmed = false, evidence = {} } end
  local conf = bs >= 3 and "alta" or (bs == 2 and "media" or "baixa")
  return { id = best, name = D.NAMES[best], version = versions[best], confidence = conf,
    confirmed = conf == "alta", evidence = ev[best] or {} }
end

--- pasta de temas do EmulationStation para um sistema, so se existir de fato
function D.themes_dir(id, catalog_dir)
  local dir = catalog_dir
  if not dir then return nil, L("pasta de temas não definida para este sistema") end
  if not is_dir(dir) then return nil, L("a pasta ") .. dir .. L(" não existe neste console") end
  return R .. dir
end

--- tema em uso no EmulationStation (ThemeSet do es_settings.cfg), se encontrado
function D.active_theme()
  for _, p in ipairs({ "/home/ark/.emulationstation/es_settings.cfg", "/storage/.config/emulationstation/es_settings.cfg",
      "/storage/.emulationstation/es_settings.cfg", "/userdata/system/configs/emulationstation/es_settings.cfg" }) do
    local s = read(p)
    if s then
      local v = s:match('name="ThemeSet"%s+value="([^"]*)"')
      if v then return v end
    end
  end
  return nil
end

return D
