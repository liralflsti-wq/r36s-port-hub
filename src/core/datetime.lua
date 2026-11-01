-- =============================================================================
--  Data e hora do SISTEMA (dArkOSRE): leitura e alteracoes.
--
--  O que o dArkOSRE usa (verificado no projeto do sistema):
--   * systemd (pacote systemd-sysv) com "timedatectl";
--   * fuso em /etc/localtime (link para /usr/share/zoneinfo/<zona>; o proprio
--     dArkOS le assim no script /usr/local/bin/timezones);
--   * sincronizacao: "timedatectl set-ntp" (os scripts do sistema
--     "Enable/Disable Remote Services" e "Update" usam esse comando);
--   * polkit desativado: alteracoes passam por "sudo -n" (o usuario ark tem
--     sudo sem senha no dArkOS). O hub NUNCA guarda senha.
--  Nada e presumido: cada recurso e detectado; o que faltar fica "indisponivel".
--  Somente comandos fixos, com argumentos validados (fuso existente na base
--  IANA instalada, numeros de data/hora conferidos).
--  As funcoes que mudam algo rodam em threads/datetime_thread.lua.
-- =============================================================================
local U = require("lib.util")

local D = {}

D.ZONEINFO = os.getenv("PORTHUB_ZONEINFO") or "/usr/share/zoneinfo"
D.SUDO = false

local function run(cmd)
  local out = U.capture("{ " .. cmd .. "; } 2>&1; echo \"__EXIT:$?\"") or ""
  local code = tonumber(out:match("__EXIT:(%d+)%s*$"))
  return U.trim((out:gsub("__EXIT:%d+%s*$", ""))), code
end

local function denied(out)
  local o = (out or ""):lower()
  return o:find("interactive authentication", 1, true) or o:find("access denied", 1, true)
    or o:find("permission denied", 1, true) or o:find("not permitted", 1, true)
    or o:find("must be root", 1, true) or o:find("authentication is required", 1, true)
    or o:find("requires root", 1, true) or o:find("not authorized", 1, true)
end

--- comando que altera o sistema: tenta normal e, se negado, com "sudo -n"
local function admin(cmd)
  local out, code = run(cmd)
  if code ~= 0 and denied(out) then
    local o2, c2 = run("sudo -n " .. cmd)
    if not o2:lower():find("sudo:", 1, true) then
      if c2 == 0 then D.SUDO = true end
      return o2, c2, true
    end
    return o2, c2 or 1, "nosudo"
  end
  return out, code, false
end

local function has(tool)
  return U.trim(U.capture("command -v " .. U.shq(tool) .. " 2>/dev/null") or "") ~= ""
end
D.has = has

-- ---------------------------------------------------------------------------
--- estado do sistema (somente leitura)
function D.status()
  local st = { now = os.time() }
  st.timedatectl = has("timedatectl")
  st.systemd = U.exec_ok("test -d /run/systemd/system")
  if st.timedatectl then
    local out, code = run("timedatectl show")
    if code == 0 and out:find("Timezone=", 1, true) then
      local kv = {}
      for k, v in out:gmatch("([%w]+)=([^\n]*)") do kv[k] = v end
      st.zone = kv.Timezone ~= "" and kv.Timezone or nil
      st.ntp = kv.NTP == "yes"
      st.synced = kv.NTPSynchronized == "yes"
      st.can_ntp = kv.CanNTP == "yes"
      st.local_rtc = kv.LocalRTC == "yes"
      st.rtc_usec = tonumber(kv.RTCTimeUSec or "")
      st.source = "timedatectl"
    else
      st.td_error = out
    end
  end
  if not st.zone then
    local l = U.trim(U.capture("readlink -f /etc/localtime 2>/dev/null") or "")
    st.zone = l:match("/zoneinfo/(.+)$")
    if not st.zone then
      local tz = U.trim(U.read_file("/etc/timezone") or "")
      st.zone = tz ~= "" and tz or nil
    end
    st.source = st.source or "/etc/localtime"
  end
  -- relogio de hardware (RTC)
  if U.exec_ok("test -e /sys/class/rtc/rtc0") then
    st.rtc = U.trim(U.read_file("/sys/class/rtc/rtc0/name") or "")
    if st.rtc == "" then st.rtc = "rtc0" end
  end
  -- servico de sincronizacao ativo
  for _, svc in ipairs({ "systemd-timesyncd", "chrony", "chronyd", "ntp", "ntpsec", "openntpd" }) do
    if st.systemd and U.exec_ok("systemctl is-active --quiet " .. svc .. " 2>/dev/null") then st.service = svc; break end
  end
  if not st.service then
    for _, p in ipairs({ "systemd-timesyncd", "chronyd", "ntpd" }) do
      if U.exec_ok("pidof " .. p .. " >/dev/null 2>&1") then st.service = p; break end
    end
  end
  -- ferramentas para uma sincronizacao avulsa (so se nao houver servico)
  st.tools = {}
  for _, t in ipairs({ "chronyc", "ntpdate", "sntp" }) do if has(t) then st.tools[#st.tools + 1] = t end end
  -- ultima sincronizacao gravada pelo systemd-timesyncd
  local m = tonumber(U.trim(U.capture("stat -c %Y " .. U.shq(os.getenv("PORTHUB_TIMESYNC_CLOCK") or "/var/lib/systemd/timesync/clock") .. " 2>/dev/null") or ""))
  if m and m > 0 then st.last_sync = m end
  if st.timedatectl and (st.service == "systemd-timesyncd") then
    local srv = U.trim(U.capture("timedatectl show-timesync -p ServerName --value 2>/dev/null") or "")
    if srv ~= "" then st.server = srv end
  end
  -- o que pode ser feito
  st.can_set_tz = st.timedatectl or U.exec_ok("test -d " .. U.shq(D.ZONEINFO))
  st.can_auto = (st.timedatectl and st.can_ntp) or false
  st.can_sync = st.service ~= nil or #st.tools > 0
  return st
end

-- ---------------------------------------------------------------------------
-- Fusos horarios (base IANA instalada no sistema)
local function valid_name(z)
  return type(z) == "string" and z ~= "" and #z < 64 and z:match("^[%w_%+%-/]+$") ~= nil
    and not z:find("%.%.") and z:sub(1, 1) ~= "/"
end

function D.valid_zone(z)
  if not valid_name(z) then return false end
  return U.exec_ok("test -f " .. U.shq(D.ZONEINFO .. "/" .. z))
end

--- lista de zonas: zone1970.tab + zone.tab (+ UTC); se faltar, timedatectl
function D.zones()
  local set, list = {}, {}
  local function add(z)
    if valid_name(z) and not set[z] then set[z] = true; list[#list + 1] = z end
  end
  for _, f in ipairs({ "zone1970.tab", "zone.tab" }) do
    local txt = U.read_file(D.ZONEINFO .. "/" .. f) or ""
    for line in txt:gmatch("[^\n]+") do
      if line:sub(1, 1) ~= "#" then
        local z = line:match("^%S+%s+%S+%s+(%S+)")
        if z then add(z) end
      end
    end
  end
  if #list == 0 and has("timedatectl") then
    for z in (U.capture("timedatectl list-timezones 2>/dev/null") or ""):gmatch("[^\n]+") do add(U.trim(z)) end
  end
  if U.exec_ok("test -f " .. U.shq(D.ZONEINFO .. "/UTC")) then add("UTC") end
  table.sort(list)
  return list
end

--- deslocamento de uma zona agora (para mostrar ao escolher)
function D.zone_offset(z)
  if not valid_name(z) then return nil end
  local out = U.trim(U.capture("TZ=" .. U.shq(":" .. z) .. " date +%z 2>/dev/null") or "")
  local sign, hh, mm = out:match("^([%+%-])(%d%d)(%d%d)")
  if not sign then return nil end
  return (tonumber(hh) * 3600 + tonumber(mm) * 60) * (sign == "-" and -1 or 1)
end

-- ---------------------------------------------------------------------------
-- Alteracoes (chamadas pela thread)

--- muda o fuso; o instante UTC do relogio nao muda (so a hora local)
function D.set_timezone(z)
  if not D.valid_zone(z) then return false, "invalid" end
  if has("timedatectl") then
    local out, code, how = admin("timedatectl set-timezone " .. U.shq(z))
    if code == 0 then return true end
    return false, (how == "nosudo") and "perm" or out
  end
  -- sem timedatectl: o mesmo que o dArkOS faz (link de /etc/localtime)
  local out, code, how = admin("ln -sf " .. U.shq(D.ZONEINFO .. "/" .. z) .. " /etc/localtime")
  if code ~= 0 then return false, (how == "nosudo") and "perm" or out end
  if U.exec_ok("test -f /etc/timezone") then admin("sh -c " .. U.shq("echo " .. z .. " > /etc/timezone")) end
  return true
end

--- liga/desliga a sincronizacao automatica do proprio sistema
function D.set_ntp(on)
  if not has("timedatectl") then return false, "notool" end
  local out, code, how = admin("timedatectl set-ntp " .. (on and "true" or "false"))
  if code == 0 then return true end
  if out:lower():find("not supported", 1, true) then return false, "unsupported" end
  return false, (how == "nosudo") and "perm" or out
end

--- pede uma sincronizacao agora e espera o resultado (ate 30 s)
function D.sync_now(progress)
  local st = D.status()
  local before = st.last_sync or 0
  if st.service == "systemd-timesyncd" then
    local out, code, how = admin("systemctl restart systemd-timesyncd")
    if code ~= 0 then return false, (how == "nosudo") and "perm" or out end
    for i = 1, 30 do
      if progress then progress(i, 30) end
      love.timer.sleep(1)
      local s2 = D.status()
      -- so conta como feito quando o sistema registra uma sincronizacao NOVA
      if s2.last_sync and s2.last_sync > before then return true, s2 end
      if not s2.last_sync and before == 0 and s2.synced and i >= 2 then return true, s2 end
    end
    return false, "timeout"
  elseif st.service and st.service:find("chrony") and has("chronyc") then
    local out, code, how = admin("chronyc -a makestep")
    if code == 0 then return true, D.status() end
    return false, (how == "nosudo") and "perm" or out
  elseif st.service then
    return false, "service_only"          -- outro servico (ntpd): ele mesmo sincroniza
  else
    for _, t in ipairs(st.tools) do
      local cmd = (t == "ntpdate") and "ntpdate -u pool.ntp.org" or (t == "sntp" and "sntp -sS pool.ntp.org")
      if cmd then
        local out, code, how = admin(cmd)
        if code == 0 then return true, D.status() end
        if how == "nosudo" then return false, "perm" end
        return false, out
      end
    end
  end
  return false, "nosync"
end

--- data e hora manual (hora LOCAL do fuso atual). Desliga a sincronizacao antes.
function D.set_time(y, mo, d, h, mi, s)
  local function ok(n, a, b) return type(n) == "number" and n == math.floor(n) and n >= a and n <= b end
  if not (ok(y, 2000, 2099) and ok(mo, 1, 12) and ok(d, 1, 31) and ok(h, 0, 23) and ok(mi, 0, 59) and ok(s, 0, 59)) then
    return false, "invalid"
  end
  local txt = string.format("%04d-%02d-%02d %02d:%02d:%02d", y, mo, d, h, mi, s)
  if has("timedatectl") then
    local st = D.status()
    if st.ntp then
      local ok2, why = D.set_ntp(false)
      if not ok2 then return false, why end
    end
    local out, code, how = admin("timedatectl set-time " .. U.shq(txt))
    if code == 0 then return true end
    return false, (how == "nosudo") and "perm" or out
  end
  local out, code, how = admin("date -s " .. U.shq(txt))
  if code ~= 0 then return false, (how == "nosudo") and "perm" or out end
  -- grava tambem no relogio de hardware, se existir (sem timedatectl ninguem faz isso)
  if U.exec_ok("test -e /dev/rtc0") and has("hwclock") then admin("hwclock -w") end
  return true
end

return D
