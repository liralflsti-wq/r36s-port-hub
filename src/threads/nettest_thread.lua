-- =============================================================================
--  Diagnostico de rede (thread): le informacoes e faz testes reais de conexao.
--  Nada e alterado no sistema. Cada resultado chega a tela assim que fica pronto.
-- =============================================================================
require("love.filesystem")
require("love.timer")
local out_name, fetch_sh = ...
local OUT = love.thread.getChannel(out_name)
local socket = require("socket")
local Net = require("core.net")
local U = require("lib.util")

local function push(k, v) OUT:push({ t = "set", k = k, v = v }) end

-- 1) informacoes locais
local st = Net.status()
push("ip", st)
local wif, oper = Net.wifi_iface(st.connected and st.wireless and st.iface or nil)
push("wifi", { iface = wif, oper = oper })
local ifname = (st.connected and st.iface ~= "?" and st.iface) or wif
push("ssid", { value = Net.ssid(ifname) })
push("signal", { value = Net.signal(wif) })
local gw = Net.gateway()
push("gateway", { value = gw })
push("dns", { value = Net.dns() })

-- 2) testes
local function tcp(host, port, timeout)
  local c = socket.tcp()
  c:settimeout(timeout or 5)
  local t0 = socket.gettime()
  local ok, err = c:connect(host, port)
  local ms = math.floor((socket.gettime() - t0) * 1000 + 0.5)
  c:close()
  return ok ~= nil, ms, err
end

if not st.connected then
  push("internet", { ok = false, skipped = true })
  push("github", { ok = false, skipped = true })
  OUT:push({ t = "done" })
  return
end

-- internet: conexao por IP (sem DNS) e por nome (com DNS)
local ip_ok, ip_ms, ip_err = tcp("1.1.1.1", 443, 5)
if not ip_ok then ip_ok, ip_ms, ip_err = tcp("8.8.8.8", 53, 5) end
local addr = socket.dns.toip("www.google.com")
local name_ok, name_ms = false, nil
if addr then name_ok, name_ms = tcp(addr, 443, 5) end
push("internet", { ok = ip_ok or name_ok, ip_ok = ip_ok, ip_ms = ip_ms, dns_ok = addr ~= nil, name_ok = name_ok,
  name_ms = name_ms, err = ip_err })

-- GitHub: DNS + TCP 443 + resposta HTTPS (curl ou wget, se existirem)
local gaddr = socket.dns.toip("github.com")
local g = { dns_ok = gaddr ~= nil }
if gaddr then g.tcp_ok, g.tcp_ms = tcp(gaddr, 443, 6) end
local code = U.trim(U.capture("curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 12 https://github.com 2>/dev/null") or "")
if code:match("^%d%d%d$") and code ~= "000" then
  g.https, g.method, g.code = true, "curl", code
elseif U.exec_ok("command -v curl >/dev/null 2>&1") then
  g.https, g.method = false, "curl"
elseif U.exec_ok("command -v wget >/dev/null 2>&1") then
  g.method = "wget"
  g.https = U.exec_ok("wget -q --spider -T 12 https://github.com >/dev/null 2>&1")
end
g.ok = g.dns_ok and g.tcp_ok and (g.https ~= false)
push("github", g)
OUT:push({ t = "done" })
