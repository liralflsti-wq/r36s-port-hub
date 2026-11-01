-- =============================================================================
--  Gravacoes salvas (pasta r36sporthub/gravacoes no cartao SD)
--  Lista os arquivos, guarda duracao/modo num indice e nunca apaga nada.
-- =============================================================================
local C = require("config")
local U = require("lib.util")
local json = require("lib.json")

local R = {}

R.DIR = C.APP_DIR .. "/gravacoes"
R.CONVERTER = "converter_gravacao.html"
local INDEX = "recordings.json"     -- pasta de dados do app (duracao de cada arquivo)

function R.ensure_dir()
  os.execute("mkdir -p " .. U.shq(R.DIR) .. " 2>/dev/null")
  if not U.is_dir(R.DIR) then return false end
  -- pagina de conversao ao lado das gravacoes (copiada so se faltar)
  local src = C.APP_DIR .. "/tools/" .. R.CONVERTER
  if U.exists(src) and not U.exists(R.DIR .. "/" .. R.CONVERTER) then
    os.execute("cp " .. U.shq(src) .. " " .. U.shq(R.DIR .. "/" .. R.CONVERTER) .. " 2>/dev/null")
  end
  return true
end

local function load_index()
  local ok, text = pcall(love.filesystem.read, INDEX)
  local d = ok and text and json.decode(text) or nil
  return type(d) == "table" and d or {}
end

function R.remember(name, info)
  local d = load_index()
  d[name] = info
  pcall(love.filesystem.write, INDEX, json.encode(d))
end

--- nome automatico com data e hora (sem repetir)
function R.new_name(ext)
  local base = "gravacao_" .. os.date("%Y-%m-%d_%H-%M-%S")
  local name = base .. "." .. ext
  local i = 2
  while U.exists(R.DIR .. "/" .. name) do
    name = base .. "_" .. i .. "." .. ext
    i = i + 1
  end
  return name
end

--- gravacoes existentes (mais recentes primeiro)
function R.list()
  local out = U.capture("cd " .. U.shq(R.DIR) .. " 2>/dev/null && for f in *.mp4 *.r36rec; do [ -f \"$f\" ] && stat -c '%s|%Y|%n' -- \"$f\"; done 2>/dev/null") or ""
  local idx = load_index()
  local t = {}
  for line in out:gmatch("[^\n]+") do
    local size, mtime, name = line:match("^(%d+)|(%d+)|(.+)$")
    if name then
      local info = idx[name] or {}
      t[#t + 1] = { name = name, path = R.DIR .. "/" .. name, size = tonumber(size), mtime = tonumber(mtime),
        dur = tonumber(info.dur), fps = tonumber(info.fps), codec = info.codec,
        kind = name:match("%.mp4$") and "mp4" or "r36" }
    end
  end
  table.sort(t, function(a, b) return a.mtime > b.mtime end)
  return t
end

function R.format_dur(sec)
  if not sec then return "—" end
  sec = math.floor(sec + 0.5)
  local h, m, s = math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%02d:%02d", m, s)
end

return R
