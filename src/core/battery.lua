-- =============================================================================
--  Bateria (somente leitura) - fonte: /sys/class/power_supply/
--    <bateria>/type     = "Battery"
--    <bateria>/capacity = 0..100   (percentual informado pelo kernel)
--    <bateria>/status   = Charging | Discharging | Full | Not charging | Unknown
--    <carregador>/type = Mains | USB | ...  e  <carregador>/online = 1 quando ligado
--  Nada e estimado: sem "capacity" legivel, a bateria fica INDISPONIVEL.
--  As leituras sao arquivos pequenos do kernel (sem processos), a cada 20 s.
-- =============================================================================
local U = require("lib.util")

local B = { info = nil, t = -1, INTERVAL = 20 }
local ROOT = os.getenv("PORTHUB_POWER_DIR") or "/sys/class/power_supply"

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  return s and U.trim(s) or nil
end

--- procura as fontes de energia uma vez (os nomes nao mudam com o uso)
local function discover()
  B.batteries, B.chargers = {}, {}
  local out = U.capture("ls -1 " .. U.shq(ROOT) .. " 2>/dev/null") or ""
  for name in out:gmatch("[^\n]+") do
    local dir = ROOT .. "/" .. name
    local tp = (read(dir .. "/type") or ""):lower()
    if tp == "battery" then
      -- ignora baterias de controles/perifericos (scope = Device)
      if (read(dir .. "/scope") or ""):lower() ~= "device" then B.batteries[#B.batteries + 1] = dir end
    elseif tp == "mains" or tp:match("^usb") or tp == "wireless" then
      B.chargers[#B.chargers + 1] = dir
    end
  end
  B.discovered = true
end

--- leitura atual. Devolve { ok, pct, charging, full, source } ou { ok = false }
function B.read_now()
  if not B.discovered then discover() end
  for _, dir in ipairs(B.batteries) do
    local cap = tonumber(read(dir .. "/capacity"))
    if cap and cap >= 0 and cap <= 100 then
      local status = (read(dir .. "/status") or ""):lower()
      local charging = status == "charging"
      local full = status == "full"
      -- sem status confiavel: um carregador ligado indica carga
      if status == "" or status == "unknown" then
        for _, c in ipairs(B.chargers) do
          if read(c .. "/online") == "1" then charging = true end
        end
      end
      return { ok = true, pct = math.floor(cap + 0.5), charging = charging, full = full, source = dir }
    end
  end
  return { ok = false }
end

--- versao com cache (no maximo uma leitura a cada INTERVAL segundos)
function B.get()
  local now = love.timer.getTime()
  if not B.info or now - B.t >= B.INTERVAL then
    local ok, r = pcall(B.read_now)
    B.info = ok and r or { ok = false }
    B.t = now
  end
  return B.info
end

--- detalhes extras (somente o que o kernel informar), para Configuracoes > Bateria.
--- Devolve { voltage (V), health, temp (C), charger = { type, online } }; campos ausentes = nil
function B.details()
  if not B.discovered then discover() end
  local d = {}
  local dir = B.batteries[1]
  if dir then
    local uv = tonumber(read(dir .. "/voltage_now") or "")
    if uv and uv > 0 then d.voltage = uv > 1000 and uv / 1000000 or uv end   -- uV -> V
    local h = read(dir .. "/health")
    if h and h ~= "" then d.health = h end
    local t = tonumber(read(dir .. "/temp") or "")
    if t then d.temp = t / 10 end                                           -- decimos de grau
  end
  for _, c in ipairs(B.chargers) do
    local online = read(c .. "/online")
    if online then
      local tp = read(c .. "/type") or ""
      if online == "1" or not d.charger then d.charger = { type = tp, online = online == "1" } end
    end
  end
  return d
end

--- nivel para o icone: high | medium | low | critical
function B.level(pct)
  if pct >= 75 then return "high" elseif pct >= 40 then return "medium" elseif pct >= 15 then return "low" end
  return "critical"
end

return B
