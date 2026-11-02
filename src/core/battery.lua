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

-- ---------------------------------------------------------------------------
-- Analise da bateria (Configuracoes > Informacoes do console > Analise da bateria)
-- Le TODOS os atributos que o kernel oferece, so quando a tela esta aberta.
-- Unidades do kernel (ABI power_supply): tensao uV, corrente uA, carga uAh,
-- energia uWh, potencia uW, tempo em segundos. Nada e escrito no sistema.

local ATTRS = { "capacity", "status", "voltage_now", "voltage_avg", "current_now", "current_avg", "charge_full",
  "charge_full_design", "charge_now", "energy_full", "energy_full_design", "energy_now", "power_now",
  "time_to_full_now", "time_to_full_avg", "health", "temp", "technology", "present", "constant_charge_current" }

--- leitura completa: { ok, dir, name, raw = {attr = valor}, avail = {lista}, chargers = {...} }
function B.snapshot()
  if not B.discovered then discover() end
  local snap = { ok = false, raw = {}, avail = {}, chargers = {}, t = love and love.timer and love.timer.getTime() or os.time() }
  local dir = B.batteries[1]
  if dir then
    snap.dir, snap.name = dir, dir:match("([^/]+)$")
    for _, a in ipairs(ATTRS) do
      local v = read(dir .. "/" .. a)
      if v and v ~= "" then snap.raw[a] = v; snap.avail[#snap.avail + 1] = a end
    end
    local cap = tonumber(snap.raw.capacity or "")
    if cap and cap >= 0 and cap <= 100 then snap.ok = true; snap.pct = cap end
  end
  for _, c in ipairs(B.chargers) do
    snap.chargers[#snap.chargers + 1] = { name = c:match("([^/]+)$"), type = read(c .. "/type"), online = read(c .. "/online"),
      voltage = tonumber(read(c .. "/voltage_now") or ""), current_max = tonumber(read(c .. "/current_max") or "") }
  end
  return snap
end

local function num(v) return tonumber(v or "") end

--- valores ja convertidos (V, mA, mAh, mWh, s); so os que existem e fazem sentido
function B.values(snap)
  local r, v = snap.raw, {}
  local status = (r.status or ""):lower()
  v.status = status
  v.pct = snap.pct
  local uv = num(r.voltage_now) or num(r.voltage_avg)
  if uv and uv > 0 then v.voltage = uv > 1000 and uv / 1e6 or uv end
  local ua = num(r.current_now) or num(r.current_avg)
  -- uA pelo ABI do kernel; o sinal varia entre drivers (carga +/-), entao usa o modulo
  if ua and ua ~= 0 then v.current = math.abs(ua) / 1000; v.current_raw = ua end
  local cf, cfd, cn = num(r.charge_full), num(r.charge_full_design), num(r.charge_now)
  if cf and cf > 0 then v.charge_full = cf / 1000 end
  if cfd and cfd > 0 then v.charge_design = cfd / 1000 end
  if cn and cn >= 0 then v.charge_now = cn / 1000 end
  local ef, efd, en = num(r.energy_full), num(r.energy_full_design), num(r.energy_now)
  if ef and ef > 0 then v.energy_full = ef / 1000 end
  if efd and efd > 0 then v.energy_design = efd / 1000 end
  if en and en >= 0 then v.energy_now = en / 1000 end
  local pw = num(r.power_now)
  if pw and pw ~= 0 then v.power = math.abs(pw) / 1000 end            -- mW
  local tf = num(r.time_to_full_now) or num(r.time_to_full_avg)
  if tf and tf > 0 then v.time_to_full = tf end
  -- carregador: algum "online = 1"? (nil = o sistema nao informa)
  for _, c in ipairs(snap.chargers) do
    if c.online == "1" then v.charger = true elseif c.online == "0" and v.charger == nil then v.charger = false end
  end
  if v.charger == nil and (status == "charging" or status == "full") then v.charger = true end
  if v.charger == nil and status == "discharging" then v.charger = false end
  return v
end

-- fase final da carga (tensao constante): a corrente cai. Acima de TAPER_AT %
-- a corrente media considerada e TAPER_FACTOR da corrente em carga normal.
B.TAPER_AT, B.TAPER_FACTOR = 80, 0.5
-- tempo minimo de observacao para a estimativa aproximada (testes no PC podem encurtar)
B.OBS_MIN_SECS = tonumber(os.getenv("PORTHUB_BATT_OBS_SECS") or "") or 120

--- tempo (s) para ir de pct a 100% com corrente I (mA) e capacidade C (mAh).
--- Se a leitura ja foi feita na fase final, a corrente medida ja esta reduzida.
local function time_with_taper(pct, cap_mah, i_ma)
  if pct >= B.TAPER_AT then
    return (100 - pct) / 100 * cap_mah / i_ma * 3600
  end
  local cc = (B.TAPER_AT - pct) / 100 * cap_mah / i_ma
  local cv = (100 - B.TAPER_AT) / 100 * cap_mah / (i_ma * B.TAPER_FACTOR)
  return (cc + cv) * 3600
end
B.time_with_taper = time_with_taper

--- Estimativa do tempo para carga completa.
--- samples = { {t = s, pct = n}, ... } observados com a tela aberta (opcional).
--- Devolve { kind = "full"|"not_charging"|"kernel"|"current"|"observed"|"measuring"|"none", secs, note, ... }
function B.estimate(v, samples)
  if v.pct == nil then return { kind = "none" } end
  if v.status == "full" or v.pct >= 100 then return { kind = "full" } end
  local charging = v.status == "charging" or (v.status ~= "discharging" and v.charger == true)
  if not charging then return { kind = "not_charging" } end
  -- 1) o proprio sistema informa
  if v.time_to_full then return { kind = "kernel", secs = v.time_to_full } end
  -- 2) corrente real + capacidade real
  local cap, cap_src = v.charge_full, "charge_full"
  if not cap and v.energy_full and v.voltage then cap, cap_src = v.energy_full / v.voltage, "energy_full / voltage_now" end
  local i = v.current
  if cap and i and i >= 10 and i <= 5000 then
    local pct = v.pct
    -- carga real (charge_now) e mais precisa que o percentual, quando existe
    if v.charge_now and v.charge_full and v.charge_full > 0 then pct = math.min(99.9, v.charge_now / v.charge_full * 100) end
    return { kind = "current", secs = time_with_taper(pct, cap, i), cap = cap, cap_src = cap_src, current = i }
  end
  -- 3) variacao do percentual observada com a tela aberta (aproximada)
  if samples and #samples >= 2 then
    local a, b = samples[1], samples[#samples]
    local dt, dp = b.t - a.t, b.pct - a.pct
    if dp >= 2 and dt >= B.OBS_MIN_SECS then
      local rate = dp / dt                                   -- % por segundo
      local secs
      if b.pct >= B.TAPER_AT then secs = (100 - b.pct) / rate
      else secs = (B.TAPER_AT - b.pct) / rate + (100 - B.TAPER_AT) / (rate * B.TAPER_FACTOR) end
      return { kind = "observed", secs = secs, rate_h = rate * 3600, minutes = dt / 60 }
    end
    return { kind = "measuring", minutes = dt / 60, delta = dp }
  end
  return { kind = "measuring", minutes = 0, delta = 0 }
end

--- nivel para o icone: high | medium | low | critical
function B.level(pct)
  if pct >= 75 then return "high" elseif pct >= 40 then return "medium" elseif pct >= 15 then return "low" end
  return "critical"
end

return B
