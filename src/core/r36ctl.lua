-- =============================================================================
--  R36 Control (dArkOSRE) dentro do R36S PORT HUB.
--
--  Faz exatamente o que o "R36 Control.sh" do sistema faz, com os mesmos
--  arquivos e comandos do dArkOSRE:
--   * /etc/r36_config.ini           configuracao (variant, active_script, gamma,
--                                   alsa_path, alsa_volume), lida no boot por
--                                   /usr/local/bin/r36_config.sh
--   * /usr/local/bin/r36_config/batt_life_warning/*.py  perfis do LED de aviso
--     da bateria; o escolhido e copiado para /usr/local/bin/batt_life_warning.py
--     e executado pelo servico batt_led.service (o LED fica num pino GPIO, por
--     isso nao aparece em /sys/class/leds)
--   * gamma: gravado no .ini, aplicado no proximo boot
--   * audio: amixer "Playback Path" (SPK_HP / SPK) + troca do ogage e reinicio
--     do ogage.service; volume no boot: alsa_volume no .ini
--  Comandos de administrador via "sudo -n" (o hub nunca pede nem guarda senha).
--  Todo valor e conferido antes (perfil existente na pasta do sistema, gamma
--  da lista, caminho SPK/SPK_HP, volume 10..100 de 5 em 5).
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")

local R = {}

R.ROOT = os.getenv("PORTHUB_ROOTFS") or ""
R.CONFIG = "/etc/r36_config.ini"
R.SCRIPT_DIR = "/usr/local/bin/r36_config/batt_life_warning"
R.TARGET = "/usr/local/bin/batt_life_warning.py"
R.OGAGE_DIR = "/usr/local/bin/r36_config/ogage"

R.GAMMAS = {}
for i = 4, 18 do R.GAMMAS[#R.GAMMAS + 1] = string.format("%d.%d", math.floor(i / 10), i % 10) end
R.VOLUMES = {}
for v = 10, 100, 5 do R.VOLUMES[#R.VOLUMES + 1] = v end
R.PATHS = { "SPK_HP", "SPK" }

local function p(path) return R.ROOT .. path end

local function run(cmd)
  local out = U.capture("{ " .. cmd .. "; } 2>&1; echo \"__EXIT:$?\"") or ""
  local code = tonumber(out:match("__EXIT:(%d+)%s*$"))
  return U.trim((out:gsub("__EXIT:%d+%s*$", ""))), code
end

--- comando de administrador (como no script do sistema)
local function sudo(cmd)
  if R.ROOT ~= "" then return run(cmd) end   -- testes: sem sudo
  return run("sudo -n " .. cmd)
end
R.sudo = sudo

-- ---------------------------------------------------------------------------
--- le o .ini (o arquivo e do root; tenta direto e depois com sudo)
function R.read_config()
  local txt = U.read_file(p(R.CONFIG))
  if not txt then
    local out, code = sudo("cat " .. U.shq(p(R.CONFIG)))
    if code == 0 then txt = out end
  end
  return txt
end

local function ini_get(txt, key)
  if not txt then return nil end
  for line in txt:gmatch("[^\n]+") do
    local k, v = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
    if k == key then return v end
  end
  return nil
end
R.ini_get = ini_get

--- estado atual (somente leitura)
function R.status()
  local s = {}
  s.available = U.is_dir(p(R.SCRIPT_DIR)) or U.exists(p(R.CONFIG))
  local ci = U.read_file(p("/proc/cpuinfo")) or ""
  s.hardware = ci:match("[Hh]ardware%s*:%s*([^\n]+)")
  local txt = R.read_config()
  s.config_found = txt ~= nil
  s.config_text = txt
  s.variant = ini_get(txt, "variant") or "unknown"
  s.active = ini_get(txt, "active_script")
  local g = ini_get(txt, "gamma")
  s.gamma = (g and g ~= "") and g or "1.0"
  s.alsa_path = ini_get(txt, "alsa_path") or "SPK_HP"
  if s.alsa_path == "" then s.alsa_path = "SPK_HP" end
  local v = ini_get(txt, "alsa_volume")
  s.alsa_volume = (v and v ~= "") and tonumber(v) or nil
  -- servico do LED
  s.led_service = U.exec_ok("systemctl is-active --quiet batt_led.service 2>/dev/null")
  -- perfis disponiveis para a variante
  s.profiles = R.profiles(s.variant)
  s.has_ogage = U.exists(p(R.OGAGE_DIR .. "/ogage.SPK")) and U.exists(p(R.OGAGE_DIR .. "/ogage.SPK_HP"))
  return s
end

--- perfis do LED (arquivos .py da pasta do sistema) da variante do aparelho
function R.profiles(variant)
  local prefix = ({ clone = "Clone_", soysauce = "SoySauce_", r36s = "R36S_" })[variant or ""] or ""
  local out = U.capture("ls -1 " .. U.shq(p(R.SCRIPT_DIR)) .. " 2>/dev/null") or ""
  local t = {}
  for n in out:gmatch("[^\n]+") do
    if n:match("^[%w_%-]+%.py$") and n:sub(1, #prefix) == prefix then t[#t + 1] = n end
  end
  table.sort(t)
  return t
end

--- descricao em texto (a partir do nome do perfil do dArkOSRE)
local function cap(s)
  -- primeira letra maiuscula (tambem acentuada/cirilica)
  local first, rest = s:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
  if not first then return s end
  return require("lib.i18n").upper(first) .. rest
end

function R.describe(name)
  return cap(R.describe_raw(name))
end

function R.describe_raw(name)
  local base = (name or ""):gsub("%.py$", "")
  for _, pre in ipairs({ "R36S_", "Clone_", "SoySauce_" }) do      -- tira o prefixo da variante
    if base:sub(1, #pre) == pre then base = base:sub(#pre + 1) break end
  end
  if base == "PMIC_Controlled" then return L("Controlado pelo hardware (o sistema não mexe no LED)") end
  if base == "Red" then return L("Vermelho sempre que estiver usando a bateria") end
  local n = base:match("^Green_(%d+)_Red$")
  if n then return string.format(L("Vermelho com a bateria em %s%% ou menos"), n) end
  local first, a, mid, b = base:match("^(%a+)_(%d+)_(%a+)_(%d+)_Red$")
  local COL = { Blue = L("azul"), Purple = L("roxo"), Pink = L("rosa"), Off = L("apagado") }
  if first then
    return string.format(L("%s acima de %s%%, %s de %s%% a %s%%, vermelho abaixo de %s%%"),
      COL[first] or first, a, COL[mid] or mid, tostring(tonumber(b) + 1), tostring(tonumber(a) - 1), b)
  end
  first, b = base:match("^(%a+)_(%d+)_Red$")
  if first then
    return string.format(L("%s; vermelho abaixo de %s%%"), COL[first] or first, b)
  end
  return name
end

-- ---------------------------------------------------------------------------
-- Alteracoes (rodam em threads/r36ctl_thread.lua)

--- grava "chave = valor" no .ini (mesmo jeito do R36 Control: sed ou acrescenta)
local function ini_set(key, value)
  local cfg = U.shq(p(R.CONFIG))
  local _, has = sudo("grep -q " .. U.shq("^" .. key .. " =") .. " " .. cfg)
  local out, code
  if has == 0 then
    out, code = sudo("sed -i " .. U.shq("s/^" .. key .. " =.*/" .. key .. " = " .. value .. "/") .. " " .. cfg)
  else
    out, code = run("echo " .. U.shq(key .. " = " .. value) .. " | " .. (R.ROOT ~= "" and "" or "sudo -n ") .. "tee -a " .. cfg .. " >/dev/null")
  end
  return code == 0, out
end

local function perm(out)
  local o = (out or ""):lower()
  return o:find("sudo:", 1, true) or o:find("password", 1, true) or o:find("permission denied", 1, true)
end

--- aplica um perfil do LED (mesma sequencia do R36 Control)
function R.apply_led(name)
  local s = R.status()
  local ok_name = false
  for _, n in ipairs(s.profiles) do if n == name then ok_name = true end end
  if not ok_name then return false, "invalid" end
  sudo("systemctl stop batt_led.service")
  love.timer.sleep(1)
  sudo("rm -f " .. U.shq(p(R.TARGET)))
  local out, code = sudo("cp " .. U.shq(p(R.SCRIPT_DIR .. "/" .. name)) .. " " .. U.shq(p(R.TARGET)))
  if code ~= 0 then return false, perm(out) and "perm" or out end
  sudo("chmod +x " .. U.shq(p(R.TARGET)))
  sudo("systemctl start batt_led.service")
  love.timer.sleep(1)
  local active = U.exec_ok("systemctl is-active --quiet batt_led.service 2>/dev/null") or R.ROOT ~= ""
  if not active then return false, "service" end
  ini_set("active_script", name)
  sudo("sync")
  return true
end

function R.set_gamma(g)
  local ok = false
  for _, v in ipairs(R.GAMMAS) do if v == g then ok = true end end
  if not ok then return false, "invalid" end
  local ok2, out = ini_set("gamma", g)
  sudo("sync")
  if not ok2 then return false, perm(out) and "perm" or out end
  return true
end

function R.set_path(path)
  if path ~= "SPK" and path ~= "SPK_HP" then return false, "invalid" end
  local ok2, out = ini_set("alsa_path", path)
  if not ok2 then return false, perm(out) and "perm" or out end
  sudo("amixer -c 0 cset iface=MIXER,name='Playback Path' " .. path .. " >/dev/null 2>&1")
  if U.exists(p(R.OGAGE_DIR .. "/ogage." .. path)) then
    sudo("systemctl stop ogage.service")
    sudo("cp " .. U.shq(p(R.OGAGE_DIR .. "/ogage." .. path)) .. " " .. U.shq(p("/usr/local/bin/ogage")))
    sudo("chmod +x " .. U.shq(p("/usr/local/bin/ogage")))
    sudo("systemctl start ogage.service")
  end
  sudo("sync")
  return true
end

--- volume no boot: numero 10..100 ou nil (= manual, apaga a linha)
function R.set_boot_volume(v)
  local cfg = U.shq(p(R.CONFIG))
  if v == nil then
    local out, code = sudo("sed -i " .. U.shq("/^alsa_volume[ \t]*=/d") .. " " .. cfg)
    sudo("sync")
    if code ~= 0 then return false, perm(out) and "perm" or out end
    return true
  end
  if type(v) ~= "number" or v < 10 or v > 100 or v % 5 ~= 0 then return false, "invalid" end
  local ok2, out = ini_set("alsa_volume", tostring(v))
  sudo("sync")
  if not ok2 then return false, perm(out) and "perm" or out end
  sudo("amixer -c 0 -M sset 'Playback' " .. v .. "% >/dev/null 2>&1")
  return true
end

--- apaga o .ini (o sistema recria com os valores padrao no proximo boot)
function R.delete_config()
  local out, code = sudo("rm -f " .. U.shq(p(R.CONFIG)))
  sudo("sync")
  if code ~= 0 then return false, perm(out) and "perm" or out end
  return true
end

-- ---------------------------------------------------------------------------
--- remove o servico de LED de uma versao anterior do hub (usava /sys/class/leds,
--- que nao controla o LED do R36S). So mexe no arquivo criado pelo proprio hub.
function R.cleanup_old_led_service()
  if R.ROOT ~= "" then return end
  local f = "/etc/systemd/system/r36sporthub-led.service"
  if not U.exists(f) then return end
  run("sudo -n systemctl disable r36sporthub-led.service >/dev/null 2>&1; sudo -n rm -f " .. f
    .. " && sudo -n systemctl daemon-reload >/dev/null 2>&1")
end

return R
