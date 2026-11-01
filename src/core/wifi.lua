-- =============================================================================
--  Wi-Fi pelo gerenciador de rede do proprio firmware: NetworkManager (nmcli).
--  O dArkOSRE usa NetworkManager + wpa_supplicant (o "Wifi Toggle" do sistema
--  instala os pacotes network-manager e wpasupplicant e usa nmcli/rfkill).
--  Este modulo NAO e um segundo gerenciador: so pede ao NetworkManager.
--
--  Seguranca:
--   * a senha nunca vai na linha de comando (nao aparece em "ps"): ela e
--     entregue ao editor do nmcli pela entrada padrao (pipe);
--   * a senha fica guardada pelo proprio NetworkManager, em
--     /etc/NetworkManager/system-connections (arquivo so do root);
--   * nada de senha em logs, relatorios ou arquivos do hub.
--
--  As funcoes daqui rodam dentro de threads/wifi_thread.lua (podem demorar).
-- =============================================================================
local U = require("lib.util")

local W = {}

W.SUDO = false          -- passa a usar "sudo -n" se o NetworkManager negar permissao

local function nm(args)
  return (W.SUDO and "sudo -n nmcli " or "nmcli ") .. args
end

--- roda um comando e devolve saida, codigo de saida
local function run(cmd)
  local out = U.capture("{ " .. cmd .. "; } 2>&1; echo \"__EXIT:$?\"") or ""
  local code = tonumber(out:match("__EXIT:(%d+)%s*$"))
  out = out:gsub("__EXIT:%d+%s*$", "")
  return out, code
end

local function denied(out)
  local o = (out or ""):lower()
  return o:find("not authorized", 1, true) or o:find("insufficient privileges", 1, true)
    or o:find("permission denied", 1, true)
end

--- nmcli com nova tentativa via sudo quando o NetworkManager nega permissao
local function nmrun(args)
  local out, code = run(nm(args))
  if code ~= 0 and denied(out) and not W.SUDO then
    W.SUDO = true
    local o2, c2 = run(nm(args))
    if c2 == 0 or not denied(o2) then return o2, c2 end
    W.SUDO = false
  end
  return out, code
end

--- separa uma linha do modo -t (campos com ":" escapados como "\:")
function W.split(line)
  local t, cur, i = {}, {}, 1
  while i <= #line do
    local ch = line:sub(i, i)
    if ch == "\\" and i < #line then
      cur[#cur + 1] = line:sub(i + 1, i + 1); i = i + 2
    elseif ch == ":" then
      t[#t + 1] = table.concat(cur); cur = {}; i = i + 1
    else
      cur[#cur + 1] = ch; i = i + 1
    end
  end
  t[#t + 1] = table.concat(cur)
  return t
end

local function lines(s)
  local t = {}
  for l in (s or ""):gmatch("[^\n]+") do t[#t + 1] = l end
  return t
end

-- ---------------------------------------------------------------------------
--- Estado geral: nmcli presente, adaptador, radio e conexao ativa
function W.status()
  local st = {}
  if not U.exec_ok("command -v nmcli >/dev/null 2>&1") then
    st.nmcli = false
    return st
  end
  st.nmcli = true
  local out, code = nmrun("-t -f RUNNING general status")
  st.nm_running = code == 0 and U.trim(out):lower():find("running", 1, true) ~= nil
  out = nmrun("radio wifi")
  local r = U.trim(out):lower()
  if r == "enabled" then st.radio = true elseif r == "disabled" then st.radio = false end
  out = nmrun("-t -f DEVICE,TYPE,STATE,CONNECTION device")
  for _, l in ipairs(lines(out)) do
    local f = W.split(l)
    if f[2] == "wifi" then
      st.iface, st.dev_state, st.connection = f[1], f[3], f[4] ~= "" and f[4] ~= "--" and f[4] or nil
      break
    end
  end
  if st.iface then
    out = nmrun("-t -f GENERAL.STATE,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show " .. U.shq(st.iface))
    st.dns = {}
    for _, l in ipairs(lines(out)) do
      local k, v = l:match("^([^:]+):(.*)$")
      if k == "GENERAL.STATE" then st.state_code = tonumber(v:match("^(%d+)"))
      elseif k and k:match("^IP4%.ADDRESS") then st.ip = st.ip or v:match("^([%d%.]+)")
      elseif k == "IP4.GATEWAY" and v ~= "" and v ~= "--" then st.gateway = v
      elseif k and k:match("^IP4%.DNS") and v ~= "" then st.dns[#st.dns + 1] = v end
    end
    if st.ip and st.ip:match("^127%.") then st.ip = nil end   -- nunca mostra loopback como Wi-Fi
    st.connected = st.state_code == 100 and st.ip ~= nil
  end
  return st
end

--- Pesquisa redes proximas. Devolve lista { ssid, signal, security, in_use, bssid } (uma por SSID)
function W.scan(iface)
  local base = "-t -f IN-USE,SSID,SIGNAL,SECURITY,BSSID device wifi list" .. (iface and (" ifname " .. U.shq(iface)) or "")
  local out, code = nmrun(base .. " --rescan yes")
  if code ~= 0 then out, code = nmrun(base) end           -- sem permissao de nova pesquisa: lista atual
  if code ~= 0 then return nil, U.trim(out) end
  local by = {}
  local list = {}
  for _, l in ipairs(lines(out)) do
    local f = W.split(l)
    local ssid = f[2]
    if ssid and ssid ~= "" and ssid ~= "--" then
      local e = {
        ssid = ssid, signal = tonumber(f[3]) or 0, security = (f[4] ~= "--" and f[4] or ""),
        in_use = U.trim(f[1] or "") == "*", bssid = f[5],
      }
      local cur = by[ssid]
      if not cur then by[ssid] = e; list[#list + 1] = e
      else
        if e.signal > cur.signal then cur.signal, cur.bssid = e.signal, e.bssid end
        cur.in_use = cur.in_use or e.in_use
        if cur.security == "" then cur.security = e.security end
      end
    end
  end
  table.sort(list, function(a, b)
    if a.in_use ~= b.in_use then return a.in_use end
    return a.signal > b.signal
  end)
  return list
end

--- Redes salvas (perfis Wi-Fi do NetworkManager). Nao le senhas.
function W.saved()
  local out, code = nmrun("-t -f NAME,UUID,TYPE,DEVICE connection show")
  if code ~= 0 then return nil, U.trim(out) end
  local t = {}
  for _, l in ipairs(lines(out)) do
    local f = W.split(l)
    if f[3] == "802-11-wireless" or f[3] == "wifi" then
      local ssid = U.trim((nmrun("-g 802-11-wireless.ssid connection show uuid " .. U.shq(f[2]))))
      t[#t + 1] = { name = f[1], uuid = f[2], active = f[4] ~= "" and f[4] ~= "--", ssid = ssid ~= "" and ssid or f[1] }
    end
  end
  return t
end

--- tipo de seguranca para o NetworkManager (nil = sem suporte aqui)
function W.key_mgmt(security)
  local s = (security or ""):upper()
  if s == "" then return "none" end
  if s:find("802.1X", 1, true) or s:find("EAP", 1, true) then return nil, "enterprise" end
  if s:find("WPA2", 1, true) or s:find("WPA1", 1, true) or s:match("WPA[^3]") or s == "WPA" then return "wpa-psk" end
  if s:find("WPA3", 1, true) or s:find("SAE", 1, true) then return "sae" end
  if s:find("WEP", 1, true) then return nil, "wep" end
  return "wpa-psk"
end

--- grava a senha no perfil pelo editor do nmcli (senha so pela entrada padrao)
local function set_psk(uuid, psk)
  local tmp = os.tmpname()
  local cmd = "{ " .. nm("connection edit uuid " .. U.shq(uuid)) .. "; } >" .. U.shq(tmp) .. " 2>&1"
  local p = io.popen(cmd, "w")
  if not p then os.remove(tmp); return false end
  p:write("set wifi-sec.psk " .. psk .. "\n", "save persistent\n", "quit\n")
  p:close()
  local out = U.read_file(tmp) or ""
  os.remove(tmp)
  -- se o editor ecoar a linha digitada, a senha nao sai daqui
  out = out:gsub("[^\n]*wifi%-sec%.psk[^\n]*", "set wifi-sec.psk ***")
  if #psk > 0 then
    local i = out:find(psk, 1, true)
    while i do out = out:sub(1, i - 1) .. "***" .. out:sub(i + #psk); i = out:find(psk, 1, true) end
  end
  local o = out:lower()
  return not (o:find("error", 1, true) or o:find("failed", 1, true)), out
end

--- classifica a saida de uma tentativa de conexao
local function failure(out, code)
  local o = (out or ""):lower()
  if o:find("secrets were required", 1, true) or o:find("no-secrets", 1, true) or o:find("supplicant", 1, true)
      or o:find("password", 1, true) or o:find("psk", 1, true) or o:find("authentication", 1, true) then
    return "auth"
  end
  if code == 10 or o:find("no network with ssid", 1, true) or o:find("not found", 1, true) then return "unavailable" end
  if code == 3 or o:find("timeout", 1, true) or o:find("timed out", 1, true) then return "timeout" end
  if denied(out) then return "permission" end
  if o:find("deactivated", 1, true) or o:find("disconnected", 1, true) then return "cancelled" end
  return "failed"
end

--- espera o estado real: dispositivo conectado (100) e IP valido
local function wait_connected(iface, secs)
  for _ = 1, secs * 2 do
    local st = W.status()
    if st.iface == iface and st.connected then return st end
    love.timer.sleep(0.5)
  end
  return nil
end

--- Conecta. net = { ssid, security }, opts = { iface, psk, uuid (perfil salvo) }
--- Devolve { ok, state, ip, ssid, created_uuid, detail }
function W.connect(net, opts)
  local iface = opts.iface
  local res = { ssid = net.ssid }
  local uuid = opts.uuid
  local km, why = W.key_mgmt(net.security)
  if not uuid and not km then res.state = why; return res end

  if not uuid and km == "none" then
    -- rede aberta: o NetworkManager cria o perfil sozinho
    local out, code = nmrun("--wait 40 device wifi connect " .. U.shq(net.ssid) .. (iface and (" ifname " .. U.shq(iface)) or ""))
    if code ~= 0 then res.state = failure(out, code); res.detail = U.trim(out); return res end
  else
    if not uuid then
      -- rede protegida nova: perfil sem senha + senha pelo editor (entrada padrao)
      local args = "connection add type wifi con-name " .. U.shq(net.ssid) .. " ssid " .. U.shq(net.ssid)
        .. (iface and (" ifname " .. U.shq(iface)) or "") .. " wifi-sec.key-mgmt " .. km
      local out, code = nmrun(args)
      uuid = out:match("%(([%x%-]+)%)")
      if code ~= 0 or not uuid then res.state = failure(out, code); res.detail = U.trim(out); return res end
      res.created_uuid = uuid
    end
    if opts.psk and opts.psk ~= "" then
      local ok = set_psk(uuid, opts.psk)
      if not ok then res.state = "failed"; return res end
    end
    local out, code = nmrun("--wait 40 connection up uuid " .. U.shq(uuid) .. (iface and (" ifname " .. U.shq(iface)) or ""))
    if code ~= 0 then res.state = failure(out, code); res.detail = U.trim(out); return res end
  end
  -- so conta como conectado quando a interface esta mesmo conectada e com IP
  local st = wait_connected(iface, 15)
  if not st then res.state = "timeout"; return res end
  res.ok, res.state, res.ip = true, "connected", st.ip
  return res
end

function W.disconnect(iface)
  local out, code = nmrun("device disconnect " .. U.shq(iface))
  return code == 0, U.trim(out)
end

function W.reconnect(uuid, iface)
  local out, code = nmrun("--wait 40 connection up uuid " .. U.shq(uuid) .. (iface and (" ifname " .. U.shq(iface)) or ""))
  if code ~= 0 then return { state = failure(out, code), detail = U.trim(out) } end
  local st = wait_connected(iface, 15)
  if not st then return { state = "timeout" } end
  return { ok = true, state = "connected", ip = st.ip }
end

function W.forget(uuid)
  local out, code = nmrun("connection delete uuid " .. U.shq(uuid))
  return code == 0, U.trim(out)
end

function W.radio(on)
  local out, code = nmrun("radio wifi " .. (on and "on" or "off"))
  return code == 0, U.trim(out)
end

return W
