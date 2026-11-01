-- Funcoes utilitarias compartilhadas
local utf8 = require("utf8")

local U = {}

--- Aspas seguras para o shell (sh/bash).
function U.shq(s)
  s = tostring(s or "")
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Executa comando e devolve a saida (texto) ou nil.
function U.capture(cmd)
  local ok, h = pcall(io.popen, cmd)
  if not ok or not h then return nil end
  local out = h:read("*a")
  h:close()
  return out
end

--- os.execute compativel com Lua 5.1 (numero) e 5.2+ (boolean)
function U.exec_ok(cmd)
  local r = os.execute(cmd)
  return r == 0 or r == true
end

function U.exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  -- pode ser diretorio
  return U.exec_ok("test -e " .. U.shq(path))
end

function U.is_dir(path)
  return U.exec_ok("test -d " .. U.shq(path))
end

function U.read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function U.write_file(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

function U.file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:seek("end")
  f:close()
  return s
end

--- Espaco livre (bytes) na particao que contem `path`.
function U.free_space(path)
  local out = U.capture("df -Pk " .. U.shq(path) .. " 2>/dev/null | tail -n 1")
  if not out then return nil end
  local total, used, avail = out:match("^%S+%s+(%d+)%s+(%d+)%s+(%d+)")
  if not avail then return nil end
  return tonumber(avail) * 1024, tonumber(total) * 1024
end

-- unidades exibidas por idioma (o russo usa Б/КБ/МБ/ГБ e с/мин/ч)
local UNITS = {
  default = { B = "B", KB = "KB", MB = "MB", GB = "GB", s = "s", min = "min", h = "h" },
  ru = { B = "Б", KB = "КБ", MB = "МБ", GB = "ГБ", s = "с", min = "мин", h = "ч" },
}
local function units()
  local ok, I = pcall(require, "lib.i18n")
  return (ok and UNITS[I.lang]) or UNITS.default
end

function U.format_bytes(n)
  n = tonumber(n)
  if not n or n < 0 then return "?" end
  local u = units()
  if n < 1024 then return string.format("%d ", n) .. u.B end
  if n < 1024 * 1024 then return string.format("%.0f ", n / 1024) .. u.KB end
  if n < 1024 * 1024 * 1024 then
    local mb = n / (1024 * 1024)
    return (mb < 10 and string.format("%.1f ", mb) or string.format("%.0f ", mb)) .. u.MB
  end
  return string.format("%.2f ", n / (1024 * 1024 * 1024)) .. u.GB
end

--- velocidade (ex.: "2.3 MB/s")
function U.format_speed(n)
  return U.format_bytes(n) .. "/" .. units().s
end

function U.format_time(sec)
  sec = math.floor(tonumber(sec) or 0)
  if sec < 0 then return "--" end
  local u = units()
  if sec < 60 then return sec .. " " .. u.s end
  if sec < 3600 then return string.format("%d %s %02d %s", math.floor(sec / 60), u.min, sec % 60, u.s) end
  return string.format("%d %s %02d %s", math.floor(sec / 3600), u.h, math.floor(sec % 3600 / 60), u.min)
end

--- Converte "160 MB", "1.2 GB", 12345 em bytes.
function U.parse_size(v)
  if type(v) == "number" then return v > 0 and v or nil end
  if type(v) ~= "string" then return nil end
  local num, unit = v:gsub(",", "."):match("([%d%.]+)%s*([KMGTkmgt]?)")
  num = tonumber(num)
  if not num then return nil end
  unit = (unit or ""):upper()
  local mult = ({ [""] = 1, K = 1024, M = 1024 ^ 2, G = 1024 ^ 3, T = 1024 ^ 4 })[unit] or 1
  return math.floor(num * mult)
end

local UPPER = {
  ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["ä"] = "Ä", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê",
  ["í"] = "Í", ["ì"] = "Ì", ["î"] = "Î", ["ó"] = "Ó", ["ò"] = "Ò", ["ô"] = "Ô", ["õ"] = "Õ", ["ö"] = "Ö",
  ["ú"] = "Ú", ["ù"] = "Ù", ["û"] = "Û", ["ü"] = "Ü", ["ç"] = "Ç", ["ñ"] = "Ñ",
}
--- Maiusculas com suporte a acentos (UTF-8)
-- cirilico minusculo (а..я, ё) -> maiusculo
for cp = 0x430, 0x44F do UPPER[utf8.char(cp)] = utf8.char(cp - 0x20) end
UPPER[utf8.char(0x451)] = utf8.char(0x401)

function U.upper(s)
  s = tostring(s or ""):upper()
  return (s:gsub("[\195\208\209][\128-\191]", function(ch) return UPPER[ch] or ch end))
end

function U.trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Texto seguro em UTF-8 (troca bytes invalidos por '?')
function U.safe_utf8(s)
  s = tostring(s or "")
  if utf8.len(s) then return s end
  local out = {}
  local i = 1
  while i <= #s do
    local ok, cp = pcall(utf8.codepoint, s, i)
    if ok and cp then
      local ch = utf8.char(cp)
      out[#out + 1] = ch
      i = i + #ch
    else
      out[#out + 1] = "?"
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Corta o texto para caber em `maxw` pixels (com reticencias).
function U.ellipsize(font, text, maxw)
  text = U.safe_utf8(text)
  if font:getWidth(text) <= maxw then return text end
  local ell = "…"
  local n = utf8.len(text)
  local lo, hi = 0, n
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    local cut = text:sub(1, (utf8.offset(text, mid + 1) or (#text + 1)) - 1)
    if font:getWidth(cut .. ell) <= maxw then lo = mid else hi = mid - 1 end
  end
  return text:sub(1, (utf8.offset(text, lo + 1) or (#text + 1)) - 1) .. ell
end

--- Identificador seguro para nomes de arquivo
local FOLD = {
  ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a",
  ["é"] = "e", ["ê"] = "e", ["è"] = "e", ["É"] = "e", ["Ê"] = "e", ["í"] = "i", ["Í"] = "i",
  ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o",
  ["ú"] = "u", ["ü"] = "u", ["Ú"] = "u", ["ç"] = "c", ["Ç"] = "c", ["ñ"] = "n",
}
function U.slug(s)
  s = tostring(s or ""):gsub("[\195][\128-\191]", function(ch) return FOLD[ch] or ch end)
  s = s:lower():gsub("[^%w%-_%.]", "_")
  if s == "" then s = "item" end
  return s:sub(1, 64)
end

function U.clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

function U.log(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  local line = table.concat(parts, " ")
  print("[porthub] " .. line)
  io.stdout:flush()
  -- ultimas linhas ficam guardadas para o registro de erros (logs/)
  local ok, E = pcall(require, "core.errlog")
  if ok and E then E.remember(line) end
end

return U
