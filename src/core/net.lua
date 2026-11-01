-- =============================================================================
--  Rede: interface, IPv4 local e estado da conexao (somente leitura)
--  Fontes, nesta ordem (nao depende de um comando especifico existir):
--    1) `ip -4 -o addr show`              (iproute2)
--    2) /proc/net/fib_trie + /proc/net/route  (kernel, sem programas extras)
--    3) LuaSocket: endereco local usado para a rota padrao (sem enviar pacotes)
--  Interfaces sem fio: /sys/class/net/<if>/wireless. Loopback (127.x) nunca conta.
-- =============================================================================
local U = require("lib.util")

local N = { last = nil, time = -1 }

local function is_loopback(ip) return ip:match("^127%.") ~= nil end

local function ip_to_num(ip)
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  return ((tonumber(a) * 256 + tonumber(b)) * 256 + tonumber(c)) * 256 + tonumber(d)
end

--- 1) iproute2
local function from_ip_cmd()
  local out = U.capture("ip -4 -o addr show 2>/dev/null") or ""
  local list = {}
  for iface, ip in out:gmatch("%d+:%s+([%w%._%-@]+)%s+inet%s+(%d+%.%d+%.%d+%.%d+)") do
    iface = iface:gsub("@.*", "")
    if not is_loopback(ip) then list[#list + 1] = { iface = iface, ip = ip } end
  end
  return list
end

--- 2) kernel: IPs locais (fib_trie) associados a interface pela tabela de rotas
local function from_proc()
  local trie = U.read_file("/proc/net/fib_trie") or ""
  local ips, seen = {}, {}
  local prev
  for line in trie:gmatch("[^\n]+") do
    local ip = line:match("|%-%-%s+(%d+%.%d+%.%d+%.%d+)")
    if ip then prev = ip
    elseif line:find("/32 host LOCAL", 1, true) and prev and not seen[prev] and not is_loopback(prev) then
      seen[prev] = true
      ips[#ips + 1] = prev
    end
  end
  if #ips == 0 then return {} end
  local routes = {}
  local rt = U.read_file("/proc/net/route") or ""
  for line in rt:gmatch("[^\n]+") do
    local iface, dest, mask = line:match("^(%S+)%s+(%x+)%s+%x+%s+%x+%s+%d+%s+%d+%s+%d+%s+(%x+)")
    if iface and dest ~= "Destination" then
      -- valores em hexadecimal little-endian
      local function le(h)
        local n = tonumber(h, 16) or 0
        local b1, b2, b3, b4 = n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256
        return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
      end
      routes[#routes + 1] = { iface = iface, dest = le(dest), mask = le(mask) }
    end
  end
  local list = {}
  for _, ip in ipairs(ips) do
    local n = ip_to_num(ip)
    local iface = "?"
    for _, r in ipairs(routes) do
      if r.mask ~= 0 and n and (n - n % (4294967296 - r.mask)) == r.dest then iface = r.iface; break end
    end
    list[#list + 1] = { iface = iface, ip = ip }
  end
  return list
end

--- 3) LuaSocket: IP local da rota padrao (UDP "connect" nao envia nada)
local function from_socket()
  local ok, socket = pcall(require, "socket")
  if not ok then return nil end
  local u = socket.udp()
  if not u then return nil end
  local okp = u:setpeername("192.0.2.1", 9) -- endereco de documentacao (RFC 5737)
  local ip = okp and u:getsockname() or nil
  u:close()
  if ip and ip ~= "0.0.0.0" and not is_loopback(ip) then return ip end
end

local function is_wireless(iface)
  return iface and iface ~= "?" and U.exec_ok("test -d /sys/class/net/" .. U.shq(iface) .. "/wireless")
end

--- Estado atual da rede. Devolve { connected, ip, iface, wireless, source }
function N.status()
  local list = from_ip_cmd()
  local src = "ip"
  if #list == 0 then list = from_proc(); src = "kernel" end
  local pick
  for _, e in ipairs(list) do
    if is_wireless(e.iface) or (e.iface or ""):match("^wl") then pick = e; break end
  end
  pick = pick or list[1]
  if not pick then
    local ip = from_socket()
    if ip then pick = { ip = ip, iface = "?" }; src = "socket" end
  end
  local st = { connected = pick ~= nil, ip = pick and pick.ip or nil, iface = pick and pick.iface or nil, source = src }
  st.wireless = pick and (is_wireless(pick.iface) or (pick.iface or ""):match("^wl") ~= nil) or false
  return st
end

--- Versao com cache (no maximo uma consulta a cada `interval` segundos)
function N.get(interval)
  local now = love.timer.getTime()
  if not N.last or now - N.time >= (interval or 3) then
    N.last = N.status()
    N.time = now
  end
  return N.last
end

function N.invalidate()
  N.time = -1
  if N.ctl then N.ctl:push("now") end
end

-- ---------------------------------------------------------------------------
-- Observador em segundo plano (thread): a tela nunca espera por comandos do
-- sistema. N.current() devolve o ultimo estado conhecido sem bloquear.
function N.start_watch(interval)
  if N.watch_thread then return end
  N.out = love.thread.getChannel("hub_net_out")
  N.ctl = love.thread.getChannel("hub_net_ctl")
  N.out:clear(); N.ctl:clear()
  N.watch_thread = love.thread.newThread("threads/net_thread.lua")
  N.watch_thread:start(interval or 4)
end

function N.current()
  if not N.watch_thread then return N.get(3) end
  local st = N.out:pop()
  while st do
    N.last, N.time = st, love.timer.getTime()
    st = N.out:pop()
  end
  if N.watch_thread:getError() then
    print("[porthub] net_thread: " .. tostring(N.watch_thread:getError()))
    N.watch_thread = nil
    return N.get(3)
  end
  return N.last   -- nil enquanto a primeira leitura nao chegou
end

function N.stop_watch()
  if N.ctl then N.ctl:push("stop") end
end

-- ---------------------------------------------------------------------------
-- Detalhes para o Diagnostico de rede (chamado fora da thread principal)
local function first_line(cmd)
  local out = U.capture("{ " .. cmd .. "; } 2>/dev/null") or ""
  out = out:gsub("\r", ""):match("^[^\n]*") or ""
  return U.trim(out)
end

--- gateway padrao da tabela de rotas do kernel
function N.gateway()
  local rt = U.read_file("/proc/net/route") or ""
  for line in rt:gmatch("[^\n]+") do
    local iface, dest, gw = line:match("^(%S+)%s+(%x+)%s+(%x+)")
    if iface and dest == "00000000" and gw ~= "00000000" then
      local n = tonumber(gw, 16)
      return string.format("%d.%d.%d.%d", n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256), iface
    end
  end
  return nil
end

--- servidores DNS configurados (resolv.conf)
function N.dns()
  local list = {}
  local txt = U.read_file("/etc/resolv.conf") or ""
  for ip in txt:gmatch("\n?%s*nameserver%s+([%x%.:]+)") do list[#list + 1] = ip end
  return list
end

--- nome da rede Wi-Fi. Tenta varias ferramentas; nil se nenhuma informar
function N.ssid(iface)
  local tries = {
    "iwgetid -r",
    "iw dev " .. U.shq(iface or "wlan0") .. " link | sed -n 's/^[[:space:]]*SSID: //p'",
    "nmcli -t -f active,ssid dev wifi | sed -n 's/^yes://p'",
    "wpa_cli -i " .. U.shq(iface or "wlan0") .. " status | sed -n 's/^ssid=//p'",
  }
  for _, c in ipairs(tries) do
    local v = first_line(c)
    if v ~= "" then return v, c:match("^(%S+)") end
  end
  return nil
end

-- dBm -> porcentagem (escala usada pelo NetworkManager: -100 dBm = 0%, -50 dBm = 100%)
local function dbm_quality(d)
  return math.max(0, math.min(100, math.floor(2 * (d + 100) + 0.5)))
end

local function valid_dbm(d) return d and d < 0 and d > -110 end

--- sinal do Wi-Fi: /proc/net/wireless; se o driver informar valor invalido
--- (o 8188eu mostra 0 e -256 dBm), tenta "iw" e depois o NetworkManager
function N.signal(iface)
  local txt = U.read_file("/proc/net/wireless") or ""
  for line in txt:gmatch("[^\n]+") do
    local name, rest = line:match("^%s*([%w%._%-]+):%s*(.*)$")
    if name and (not iface or name == iface) then
      local _, link, level = rest:match("^(%x+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
      link, level = tonumber(link), tonumber(level)
      if level and level > 0 and level <= 255 and level >= 146 then level = level - 256 end  -- alguns drivers usam unsigned
      if link and link > 0 then
        return { quality = math.max(0, math.min(100, math.floor(link * 100 / 70 + 0.5))), dbm = valid_dbm(level) and level or nil }
      end
      if valid_dbm(level) then return { quality = dbm_quality(level), dbm = level } end
      break
    end
  end
  local dev = iface or "wlan0"
  local d = tonumber((U.capture("iw dev " .. U.shq(dev) .. " link 2>/dev/null | sed -n 's/^[[:space:]]*signal:[[:space:]]*\\(-*[0-9]*\\).*/\\1/p'") or ""):match("%-?%d+"))
  if valid_dbm(d) then return { quality = dbm_quality(d), dbm = d } end
  local out = U.capture("nmcli -t -f IN-USE,SIGNAL device wifi list ifname " .. U.shq(dev) .. " --rescan no 2>/dev/null") or ""
  for l in out:gmatch("[^\n]+") do
    local q = l:match("^%*:(%d+)")
    if q then return { quality = math.min(100, tonumber(q)) } end
  end
  return nil
end

--- interface sem fio presente no sistema (mesmo sem IP) e estado do enlace.
--- Ignora interfaces virtuais Wi-Fi Direct (p2p0 do driver Realtek) e prefere
--- a interface que esta em uso (prefer), depois a que esta "up".
function N.wifi_iface(prefer)
  local out = U.capture("ls /sys/class/net 2>/dev/null") or ""
  local list = {}
  for name in out:gmatch("%S+") do
    if is_wireless(name) or name:match("^wl") then
      list[#list + 1] = { name = name, oper = U.trim(U.read_file("/sys/class/net/" .. name .. "/operstate") or ""),
        p2p = name:match("^p2p") ~= nil }
    end
  end
  local function find(test) for _, e in ipairs(list) do if test(e) then return e.name, e.oper end end end
  local n, o = find(function(e) return prefer and e.name == prefer end)
  if n then return n, o end
  n, o = find(function(e) return not e.p2p and e.oper == "up" end)
  if n then return n, o end
  n, o = find(function(e) return not e.p2p end)
  if n then return n, o end
  return find(function() return true end)
end

return N
