-- =============================================================================
--  Teste de velocidade da internet (thread), usando os servidores publicos do
--  teste da Cloudflare (speed.cloudflare.com):
--    latencia  -> conexoes TCP no servidor (mediana de 5)
--    download  -> GET  /__down?bytes=N   (curl, limite de tempo)
--    upload    -> POST /__up             (curl, dados gerados na hora)
--  Os numeros sao os que o curl mede de verdade; nada e estimado.
--  Consome dados: ate ~25 MB de download e ~8 MB de upload por teste.
-- =============================================================================
require("love.filesystem")
require("love.timer")
local out_name, lang = ...
local I18N = require("lib.i18n")
I18N.set(lang or "pt-BR")
local L = I18N.L
local OUT = love.thread.getChannel(out_name)
local socket = require("socket")
local U = require("lib.util")

local BASE = os.getenv("PORTHUB_SPEED_BASE") or "https://speed.cloudflare.com"   -- override so para testes
local HOST, PORT = BASE:match("^%a+://([^:/]+):?(%d*)")
PORT = tonumber(PORT) or (BASE:match("^https") and 443 or 80)
local DOWN_BYTES = 25000000
local UP_BYTES = 8000000
local MAX_TIME = 12

local function push(t) OUT:push(t) end

if not U.exec_ok("command -v curl >/dev/null 2>&1") then
  push({ t = "error", msg = L("O teste de velocidade precisa do curl, que não foi encontrado no sistema.") })
  return
end

-- latencia: tempo de conexao TCP (mediana)
push({ t = "phase", phase = "latency" })
local addr = socket.dns.toip(HOST)
if not addr then
  push({ t = "error", msg = L("Não foi possível encontrar o servidor do teste (DNS). Verifique a conexão.") })
  return
end
local samples = {}
for _ = 1, 5 do
  local c = socket.tcp()
  c:settimeout(4)
  local t0 = socket.gettime()
  local ok = c:connect(addr, PORT)
  if ok then samples[#samples + 1] = (socket.gettime() - t0) * 1000 end
  c:close()
end
if #samples == 0 then
  push({ t = "error", msg = L("O servidor do teste não respondeu. Verifique a conexão.") })
  return
end
table.sort(samples)
local lat = samples[math.floor((#samples + 1) / 2)]
local jit = samples[#samples] - samples[1]
push({ t = "result", k = "latency", v = lat, jitter = jit })

local function parse(out)
  local a, b, c, code = (out or ""):match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+(%d+)")
  return tonumber(a), tonumber(b), tonumber(c), code
end

-- download
push({ t = "phase", phase = "download" })
local id = tostring(os.time()) .. tostring(math.random(1000, 9999))
local cmd = string.format("curl -s -o /dev/null --connect-timeout 8 --max-time %d "
  .. "-w '%%{speed_download} %%{size_download} %%{time_total} %%{http_code}' %s 2>/dev/null",
  MAX_TIME, U.shq(BASE .. "/__down?measId=" .. id .. "&bytes=" .. DOWN_BYTES))
local spd, size, time, code = parse(U.capture(cmd))
if not spd or not size or size < 100000 then
  push({ t = "error", msg = L("O download do teste falhou") .. (code and code ~= "000" and (" (HTTP " .. code .. ")") or "") .. "." })
  return
end
push({ t = "result", k = "download", v = spd, bytes = size, time = time })

-- upload (dados gerados na hora, sem arquivo temporario)
push({ t = "phase", phase = "upload" })
cmd = string.format("head -c %d /dev/zero | curl -s -o /dev/null --connect-timeout 8 --max-time %d "
  .. "-H 'Content-Type: application/octet-stream' --data-binary @- "
  .. "-w '%%{speed_upload} %%{size_upload} %%{time_total} %%{http_code}' %s 2>/dev/null",
  UP_BYTES, MAX_TIME, U.shq(BASE .. "/__up?measId=" .. id))
spd, size, time, code = parse(U.capture(cmd))
if not spd or not size or size < 100000 then
  push({ t = "result", k = "upload", failed = true, code = code })
else
  push({ t = "result", k = "upload", v = spd, bytes = size, time = time })
end
push({ t = "done" })
