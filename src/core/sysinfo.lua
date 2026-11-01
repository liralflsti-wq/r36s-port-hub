-- =============================================================================
--  Informacoes do console: SOMENTE leitura de dados reais do sistema
--  (df, /proc/meminfo, /etc/os-release, uname, device-tree, pasta do PortMaster).
--  Nada e alterado. O que nao puder ser lido aparece como "Não disponível".
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")
local C = require("config")
local Runtimes = require("core.runtimes")

local I = {}
local NA = L("Não disponível")
I.NA = NA

local function first_line(s) return s and U.trim(s:match("^[^\n]*") or "") or "" end
local function nz(s) return (s and s ~= "") and s or NA end

local function storage(path, label)
  local out = U.capture("df -Pk " .. U.shq(path) .. " 2>/dev/null | tail -n 1") or ""
  local dev, total, used, avail, _, mnt = out:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s+(%S+)")
  if not total then return { label = label, ok = false } end
  total, used, avail = tonumber(total) * 1024, tonumber(used) * 1024, tonumber(avail) * 1024
  return { label = label, ok = true, path = path, mount = mnt, total = total, used = used, free = avail,
    frac = total > 0 and used / total or 0 }
end

function I.collect()
  local r = { time = os.date("%H:%M:%S") }

  -- armazenamento: cartao com a pasta de ports (e o 2o cartao, se existir)
  r.storage = { storage(C.PORTS_DIR, L("Cartão SD (") .. (C.PORTS_DIR:match("^(/[^/]+)") or C.PORTS_DIR) .. ")") }
  if C.PORTS_DIR:sub(1, 7) ~= "/roms2/" and U.is_dir("/roms2") then
    local s2 = storage("/roms2", L("Cartão 2 (/roms2)"))
    if s2.ok and s2.mount ~= r.storage[1].mount then r.storage[2] = s2 end
  end

  -- memoria RAM (/proc/meminfo, em kB)
  local mi = U.read_file("/proc/meminfo") or ""
  local total = tonumber(mi:match("MemTotal:%s*(%d+)"))
  local avail = tonumber(mi:match("MemAvailable:%s*(%d+)"))
  if total and avail then
    r.mem = { ok = true, total = total * 1024, avail = avail * 1024, used = (total - avail) * 1024,
      frac = (total - avail) / total }
  else
    r.mem = { ok = false }
  end

  -- sistema
  local osr = U.read_file("/etc/os-release") or ""
  r.os = nz(osr:match('PRETTY_NAME="([^"]+)"') or osr:match("PRETTY_NAME=([^\n]+)"))
  r.kernel = nz(first_line(U.capture("uname -r 2>/dev/null")))
  r.arch = nz(first_line(U.capture("uname -m 2>/dev/null")))
  local model = U.read_file("/proc/device-tree/model")
  r.model = nz(model and U.trim((model:gsub("%z", ""))) or nil)
  local cores = tonumber(first_line(U.capture("nproc 2>/dev/null")))
  r.cores = cores and tostring(cores) or NA
  local up = tonumber((U.read_file("/proc/uptime") or ""):match("^(%d+)"))
  r.uptime = up and U.format_time(up) or NA

  -- PortMaster e runtimes (mesma deteccao do atualizador de runtimes)
  local pm = Runtimes.detect_pm()
  r.pm = { installed = pm ~= nil, path = pm }
  if pm then
    local list = U.capture("ls -1 " .. U.shq(pm .. "/libs") .. " 2>/dev/null") or ""
    local names = {}
    for n in list:gmatch("[^\n]+") do if n:match("%.squashfs$") then names[#names + 1] = n end end
    r.pm.runtimes = names
    local ver = U.read_file(pm .. "/version")
    r.pm.version = ver and first_line(ver) or nil
  end
  return r
end

--- temperatura do processador em graus C (so se o sistema informar) ou nil
function I.temperature()
  local base = os.getenv("PORTHUB_THERMAL_DIR") or "/sys/class/thermal"
  local pick
  for i = 0, 7 do
    local dir = base .. "/thermal_zone" .. i
    local t = tonumber(U.trim(U.read_file(dir .. "/temp") or ""))
    if t then
      local tp = (U.read_file(dir .. "/type") or ""):lower()
      local c = t > 1000 and t / 1000 or t
      if c > 0 and c < 150 then
        if tp:match("cpu") or tp:match("soc") then return c end
        pick = pick or c
      end
    end
  end
  return pick
end

return I
