-- =============================================================================
--  Relogio do R36S PORT HUB: hora REAL do sistema, mostrada no formato que o
--  usuario escolheu (12/24 h e ordem da data).
--
--  Por que um deslocamento proprio: um programa em execucao nao percebe quando
--  o fuso horario do sistema muda (a biblioteca C le /etc/localtime so uma vez).
--  Por isso a diferenca para UTC e lida do proprio sistema ("date +%z") na
--  abertura, depois de trocar o fuso e a cada 10 minutos (horario de verao).
--  O instante continua sendo o do sistema (os.time()); so a exibicao muda.
-- =============================================================================
local U = require("lib.util")
local Prefs = require("core.prefs")

local K = { offset = nil, zone = nil, abbr = nil, t_check = -1 }

K.DATE_FORMATS = { "dmy", "mdy", "ymd" }

function K.fmt24() return (Prefs.get("time_format") or "24") ~= "12" end
function K.datefmt()
  local d = Prefs.get("date_format") or "dmy"
  if d ~= "mdy" and d ~= "ymd" then d = "dmy" end
  return d
end

--- le a diferenca para UTC do sistema agora (ex.: -0300 -> -10800 s)
function K.refresh()
  -- "env -u TZ": sempre o fuso do SISTEMA (/etc/localtime), nunca uma variavel de ambiente
  local out = U.trim(U.capture("env -u TZ date +'%z %Z' 2>/dev/null") or "")
  local sign, hh, mm, abbr = out:match("^([%+%-])(%d%d)(%d%d)%s*(%S*)")
  if sign then
    K.offset = (tonumber(hh) * 3600 + tonumber(mm) * 60) * (sign == "-" and -1 or 1)
    K.abbr = abbr ~= "" and abbr or nil
  end
  K.t_check = love.timer and love.timer.getTime() or 0
end

--- chamado no love.update: confere o deslocamento a cada 10 minutos
function K.tick()
  local now = love.timer.getTime()
  if K.t_check < 0 or now - K.t_check > 600 then K.refresh() end
end

--- tabela de data/hora local (instante t ou agora)
function K.parts(t, off)
  t = t or os.time()
  off = off or K.offset
  if off then return os.date("!*t", t + off) end
  return os.date("*t", t)
end

local function two(n) return string.format("%02d", n) end

--- off (opcional): mostra a hora de outro fuso (segundos em relacao ao UTC)
function K.time(t, secs, off)
  local p = K.parts(t, off)
  local s = secs and (":" .. two(p.sec)) or ""
  if K.fmt24() then return two(p.hour) .. ":" .. two(p.min) .. s end
  local h = p.hour % 12
  if h == 0 then h = 12 end
  return two(h) .. ":" .. two(p.min) .. s .. (p.hour < 12 and " AM" or " PM")
end

--- data completa (short = sem o ano)
function K.date(t, short)
  local p = K.parts(t)
  local f = K.datefmt()
  if f == "mdy" then return two(p.month) .. "/" .. two(p.day) .. (short and "" or ("/" .. p.year)) end
  if f == "ymd" then return (short and "" or (p.year .. "-")) .. two(p.month) .. "-" .. two(p.day) end
  return two(p.day) .. "/" .. two(p.month) .. (short and "" or ("/" .. p.year))
end

--- formata valores avulsos (ex.: o que o usuario esta escolhendo no ajuste manual)
function K.format_values(y, mo, d, h, mi, sec)
  local f = K.datefmt()
  local date = (f == "mdy") and string.format("%02d/%02d/%04d", mo, d, y)
    or ((f == "ymd") and string.format("%04d-%02d-%02d", y, mo, d) or string.format("%02d/%02d/%04d", d, mo, y))
  local tm
  if K.fmt24() then tm = string.format("%02d:%02d:%02d", h, mi, sec)
  else
    local hh = h % 12
    if hh == 0 then hh = 12 end
    tm = string.format("%02d:%02d:%02d %s", hh, mi, sec, h < 12 and "AM" or "PM")
  end
  return date .. " " .. tm
end

function K.datetime(t, short) return K.date(t, short) .. " " .. K.time(t) end

--- dia da semana (1 = domingo)
function K.wday(t) return K.parts(t).wday end

--- "UTC-03:00"
function K.offset_label(off)
  off = off or K.offset
  if not off then return "UTC" end
  local sign = off < 0 and "-" or "+"
  off = math.abs(off)
  return string.format("UTC%s%02d:%02d", sign, math.floor(off / 3600), math.floor(off % 3600 / 60))
end

return K
