-- =============================================================================
--  Brilho da tela (Configuracoes > Brilho da tela)
--
--  Metodo: o mesmo do proprio ArkOS/dArkOS. O servico de atalhos do sistema
--  (ogage, github.com/christianhaitian/ogage) ajusta o brilho com o comando
--  `brightnessctl` ("brightnessctl s +2%", "brightnessctl -n s 2%-"), que atua
--  sobre a luz de fundo do painel em /sys/class/backlight/<dispositivo>.
--
--  Ordem de tentativa (a primeira que FUNCIONAR de verdade e memorizada):
--    1) brightnessctl            2) sudo -n brightnessctl
--    3) escrita direta em /sys/class/backlight/<disp>/brightness
--    4) sudo -n (mesma escrita)
--  Depois de cada ajuste o valor e LIDO de volta; se nao mudou, o controle e
--  desativado e o motivo e mostrado (nada de controle "de mentira").
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")

local B = {
  checked = false, available = false, reason = "",
  method = nil, device = nil, sysdir = nil, max = nil,
  percent = nil,          -- valor atual (lido do sistema)
  target = nil,           -- valor pedido pela interface (aplicado com limite de frequencia)
  timer = 0,
}

local MIN, MAX, STEP = 5, 100, 5   -- nunca 0%: a tela apagaria por completo
local PREF = "brightness.txt"

local function has(cmd) return U.exec_ok("command -v " .. cmd .. " >/dev/null 2>&1") end

--- Leitura pelo brightnessctl (saida -m: dispositivo,classe,atual,porcentagem%,maximo)
local function read_ctl(prefix)
  local cmd = (prefix or "") .. "brightnessctl -m -c backlight" .. (B.device and (" -d " .. U.shq(B.device)) or "") .. " 2>/dev/null"
  local out = U.capture(cmd) or ""
  local dev, cur, max = out:match("^([^,\n]+),[^,]*,(%d+),%d+%%?,(%d+)")
  if dev and tonumber(max) and tonumber(max) > 0 then
    return dev, tonumber(cur), tonumber(max)
  end
end

local function read_sys()
  if not B.sysdir then return nil end
  local cur = tonumber(U.trim(U.read_file(B.sysdir .. "/brightness") or ""))
  local max = tonumber(U.trim(U.read_file(B.sysdir .. "/max_brightness") or ""))
  if cur and max and max > 0 then return cur, max end
end

local function to_pct(cur, max) return math.floor(cur * 100 / max + 0.5) end

--- Le o brilho atual (porcentagem) pelo melhor caminho disponivel
function B.read()
  if B.use_ctl then
    local _, cur, max = read_ctl()
    if cur then B.max = max; return to_pct(cur, max) end
  end
  local cur, max = read_sys()
  if cur then B.max = max; return to_pct(cur, max) end
  return nil
end

function B.detect()
  B.checked = true
  -- dispositivo da luz de fundo (o primeiro em /sys/class/backlight)
  local base = os.getenv("PORTHUB_BACKLIGHT_DIR") or "/sys/class/backlight"
  local list = U.capture("ls -1 " .. U.shq(base) .. " 2>/dev/null") or ""
  for name in list:gmatch("[^\n]+") do
    local d = base .. "/" .. name
    if U.read_file(d .. "/max_brightness") then B.sysdir, B.device = d, name; break end
  end
  B.use_ctl = has("brightnessctl")
  if B.use_ctl then
    local dev = read_ctl()
    if dev then B.device = B.device or dev else B.use_ctl = false end
  end
  B.percent = B.read()
  if not B.percent then
    B.available = false
    B.reason = L("nenhuma luz de fundo encontrada (brightnessctl ou /sys/class/backlight)")
  else
    B.available = true
    B.reason = ""
  end
  U.log("brilho:", B.available and (L("ok, ") .. B.percent .. L("%, dispositivo ") .. tostring(B.device)
    .. (B.use_ctl and ", brightnessctl" or ", sysfs")) or (L("indisponivel: ") .. B.reason))
  return B.available
end

local function close_enough(a, b) return a and b and math.abs(a - b) <= 2 end

--- Aplica uma porcentagem e confirma lendo de volta. Devolve true/false
local function apply(pct)
  local raw = B.max and math.max(1, math.floor(pct * B.max / 100 + 0.5)) or nil
  local tries = {}
  if B.use_ctl then
    local d = B.device and (" -d " .. U.shq(B.device)) or ""
    tries[#tries + 1] = { "brightnessctl", "brightnessctl -q -c backlight" .. d .. " s " .. pct .. "% >/dev/null 2>&1" }
    tries[#tries + 1] = { "sudo brightnessctl", "sudo -n brightnessctl -q -c backlight" .. d .. " s " .. pct .. "% >/dev/null 2>&1" }
  end
  if B.sysdir and raw then
    local f = U.shq(B.sysdir .. "/brightness")
    tries[#tries + 1] = { "sysfs", "echo " .. raw .. " > " .. f .. " 2>/dev/null" }
    tries[#tries + 1] = { "sudo sysfs", "echo " .. raw .. " | sudo -n tee " .. f .. " >/dev/null 2>&1" }
  end
  -- metodo que ja funcionou vai primeiro
  if B.method then
    for i, t in ipairs(tries) do
      if t[1] == B.method then table.remove(tries, i); table.insert(tries, 1, t); break end
    end
  end
  for _, t in ipairs(tries) do
    os.execute(t[2])
    local now = B.read()
    if close_enough(now, pct) then
      if B.method ~= t[1] then U.log("brilho: metodo em uso:", t[1]) end
      B.method = t[1]
      B.percent = now
      return true
    end
  end
  return false
end

function B.load_pref()
  local ok, s = pcall(love.filesystem.read, PREF)
  local v = ok and s and tonumber(s:match("(%d+)")) or nil
  if v then return U.clamp(v, MIN, MAX) end
end

local function save_pref(v)
  pcall(love.filesystem.write, PREF, tostring(v) .. "\n")
end

--- Na abertura do app: reaplica o brilho salvo (se houver)
function B.restore()
  local v = B.load_pref()
  if not v then return end
  if not B.checked then B.detect() end
  if B.available and not close_enough(B.percent, v) then
    if apply(v) then U.log("brilho restaurado:", v .. "%") end
  end
end

--- Ajuste pela interface (esquerda/direita). Aplicado em B.update com limite de frequencia.
function B.nudge(dir)
  if not B.available then return end
  local base = B.target or B.percent or 50
  base = math.floor(base / STEP + 0.5) * STEP
  B.target = U.clamp(base + dir * STEP, MIN, MAX)
end

--- Chamado a cada quadro. Devolve false, motivo se o sistema recusar a mudanca.
function B.update(dt)
  if not B.target then return true end
  B.timer = B.timer - dt
  if B.timer > 0 then return true end
  B.timer = 0.12
  local want = B.target
  if close_enough(B.percent, want) and B.percent == want then B.target = nil; return true end
  if apply(want) then
    save_pref(want)
    if B.target == want then B.target = nil end
    return true
  end
  B.target = nil
  B.available = false
  B.reason = L("o sistema não permitiu alterar o brilho (sem permissão)")
  U.log("brilho: falha ao aplicar", want .. "%")
  return false, B.reason
end

function B.display_value() return B.target or B.percent or 0 end
function B.method_label()
  if B.method then return B.method end
  return B.use_ctl and "brightnessctl" or "sysfs"
end

B.MIN, B.MAX = MIN, MAX
return B
