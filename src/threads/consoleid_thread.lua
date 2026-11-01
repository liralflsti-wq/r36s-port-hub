-- =============================================================================
--  Analisador de Console (thread): SOMENTE leitura de informacoes do sistema.
--  Le /proc, /sys, a Device Tree carregada e /etc/os-release. Nao grava nada
--  fora da pasta do app, nao altera configuracoes e nao usa a internet.
--  Nada de dados pessoais: numeros de serie e enderecos MAC nao sao lidos.
--  Cada etapa avisa a tela quando comeca (progresso real: etapa N de M).
-- =============================================================================
require("love.filesystem")
require("love.data")
local out_name, lang = ...
local I18N = require("lib.i18n")
I18N.set(lang or "pt-BR")
local OUT = love.thread.getChannel(out_name)
local U = require("lib.util")

local R = os.getenv("PORTHUB_ROOTFS") or ""   -- so testes: raiz falsa
local function rd(path, binary)
  local f = io.open(R .. path, binary and "rb" or "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function line1(s) return s and U.trim((s:match("^[^\n]*") or "")) or nil end
local function nz(s) if s and s ~= "" then return s end end
--- texto de propriedade da Device Tree (strings separadas por \0)
local function dt_strings(s)
  local t = {}
  if not s then return t end
  for part in s:gmatch("[^%z]+") do t[#t + 1] = part end
  return t
end
local function u32(s)
  if not s or #s < 4 then return nil end
  local a, b, c, d = s:byte(1, 4)
  return ((a * 256 + b) * 256 + c) * 256 + d
end
local function ls(dir)
  local out = U.capture("ls -1 " .. U.shq(R .. dir) .. " 2>/dev/null") or ""
  local t = {}
  for n in out:gmatch("[^\n]+") do t[#t + 1] = n end
  return t
end

local STEPS = { "system", "cpu", "memory", "devicetree", "display", "battery", "storage" }
local info = { time = os.time() }
local function step(i) OUT:push({ t = "step", i = i, n = #STEPS, id = STEPS[i] }) end

-- 1) sistema (firmware e software: NAO identificam o hardware)
step(1)
local osr = rd("/etc/os-release") or ""
info.os = nz(osr:match('PRETTY_NAME="([^"]+)"') or osr:match("PRETTY_NAME=([^\n]+)"))
local okd, d = pcall(function() return require("core.osdetect").detect() end)
if okd and d and d.id and d.id ~= "unknown" then
  info.firmware = d.name .. ((d.version and d.version ~= "") and (" " .. d.version) or "")
end
info.kernel = nz(line1(U.capture("uname -r 2>/dev/null")))
info.arch = nz(line1(U.capture("uname -m 2>/dev/null")))

-- 2) processador
step(2)
local cpu = rd("/proc/cpuinfo") or ""
local cores, parts = 0, {}
for _ in cpu:gmatch("\nprocessor%s*:") do cores = cores + 1 end
if cpu:match("^processor%s*:") then cores = cores + 1 end
for p in cpu:gmatch("CPU part%s*:%s*(0x%x+)") do parts[p:lower()] = true end
local PART = { ["0xd03"] = "Cortex-A53", ["0xd04"] = "Cortex-A35", ["0xd05"] = "Cortex-A55", ["0xd07"] = "Cortex-A57",
  ["0xd08"] = "Cortex-A72", ["0xd09"] = "Cortex-A73", ["0xd0a"] = "Cortex-A75", ["0xd0b"] = "Cortex-A76" }
local names = {}
for p in pairs(parts) do names[#names + 1] = PART[p] or p end
table.sort(names)
info.cores = cores > 0 and cores or nil
info.cpu = #names > 0 and table.concat(names, " + ") or nil
info.hardware = nz(U.trim(cpu:match("\nHardware%s*:%s*([^\n]+)") or ""))   -- dArkOSRE: identificador da placa

-- 3) memoria
step(3)
local mi = rd("/proc/meminfo") or ""
local mt = tonumber(mi:match("MemTotal:%s*(%d+)"))
info.mem_kb = mt

-- 4) Device Tree carregada pelo sistema (escolhida na instalacao do firmware)
step(4)
local base
-- /proc/device-tree costuma ser um link para /sys/firmware/devicetree/base
for _, b in ipairs({ "/sys/firmware/devicetree/base", "/proc/device-tree" }) do
  if rd(b .. "/compatible", true) then base = b; break end
end
info.dt = base ~= nil
if base then
  info.model = nz(U.trim((rd(base .. "/model", true) or ""):gsub("%z", "")))
  info.compatible = dt_strings(rd(base .. "/compatible", true))
  for _, c in ipairs(info.compatible) do
    local soc = c:match("^rockchip,(rk%d+)$") or c:match("^allwinner,(sun%w+)$") or c:match("^amlogic,(%w+)$")
    if soc then info.soc = soc end
  end
  -- painel de tela: no com panel-init-sequence (sequencia de inicializacao do controlador)
  local p = line1(U.capture("find " .. U.shq(R .. base .. "/") .. " -maxdepth 5 -name panel-init-sequence 2>/dev/null | head -n 1"))
  if p and p ~= "" then
    local dir = p:sub(#R + 1):gsub("//+", "/"):match("^(.*)/[^/]+$")
    local seq = rd(dir .. "/panel-init-sequence", true)
    if seq and #seq > 0 then
      info.panel_sha1 = love.data.encode("string", "hex", love.data.hash("sha1", seq))
      info.panel_len = #seq
    end
    info.panel_compat = dt_strings(rd(dir .. "/compatible", true))
    -- resolucao declarada no painel (display-timings)
    local t = line1(U.capture("find " .. U.shq(R .. dir .. "/") .. " -maxdepth 3 -name hactive 2>/dev/null | head -n 1"))
    if t and t ~= "" then
      local tdir = t:sub(#R + 1):gsub("//+", "/"):match("^(.*)/[^/]+$")
      local w, h = u32(rd(tdir .. "/hactive", true)), u32(rd(tdir .. "/vactive", true))
      if w and h then info.dt_res = w .. "x" .. h end
    end
  end
  -- GPU
  for _, n in ipairs(ls(base)) do
    if n:match("^gpu@") then
      local c = dt_strings(rd(base .. "/" .. n .. "/compatible", true))
      if #c > 0 then info.gpu = table.concat(c, ", ") end
    end
  end
end

-- 5) tela: modo ativo informado pelo driver (DRM)
step(5)
for _, n in ipairs(ls("/sys/class/drm")) do
  if n:match("^card%d+%-") then
    local st = line1(rd("/sys/class/drm/" .. n .. "/status"))
    local mode = line1(rd("/sys/class/drm/" .. n .. "/modes"))
    if st == "connected" and mode and mode ~= "" then
      info.drm_res = mode:match("^(%d+x%d+)")
      info.connector = n:gsub("^card%d+%-", "")
      break
    end
  end
end

-- 6) bateria (somente o que o kernel informar)
step(6)
for _, n in ipairs(ls("/sys/class/power_supply")) do
  local dir = "/sys/class/power_supply/" .. n
  if (line1(rd(dir .. "/type")) or ""):lower() == "battery" and (line1(rd(dir .. "/scope")) or ""):lower() ~= "device" then
    local b = {}
    b.capacity = tonumber(line1(rd(dir .. "/capacity")))
    b.technology = nz(line1(rd(dir .. "/technology")))
    local v = tonumber(line1(rd(dir .. "/voltage_now")))
    if v and v > 0 then b.voltage = v > 1000 and v / 1000000 or v end
    local cf = tonumber(line1(rd(dir .. "/charge_full_design")))
    if cf and cf > 0 then b.design_mah = math.floor(cf / 1000 + 0.5) end
    info.battery = b
    break
  end
end

-- 7) armazenamento (cartoes e memoria interna); sem numero de serie
step(7)
info.disks = {}
for _, n in ipairs(ls("/sys/block")) do
  if n:match("^mmcblk%d+$") then
    local dir = "/sys/block/" .. n
    local typ = line1(rd(dir .. "/device/type"))
    local sectors = tonumber(line1(rd(dir .. "/size")))
    info.disks[#info.disks + 1] = {
      dev = n, type = typ, bytes = sectors and sectors * 512 or nil,
      name = nz(line1(rd(dir .. "/device/name"))),
      manfid = nz(line1(rd(dir .. "/device/manfid"))),
    }
    if typ == "MMC" then info.emmc = true end
  end
end
local okc, C = pcall(require, "config")
local path = (okc and C.PORTS_DIR) or "/roms/ports"
local df = U.capture("df -Pk " .. U.shq(path) .. " 2>/dev/null | tail -n 1") or ""
local tot, used, avail = df:match("^%S+%s+(%d+)%s+(%d+)%s+(%d+)")
if tot then info.sd = { total = tonumber(tot) * 1024, used = tonumber(used) * 1024, free = tonumber(avail) * 1024 } end

OUT:push({ t = "done", info = info })
