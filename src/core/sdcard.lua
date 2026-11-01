-- =============================================================================
--  Verificador do cartao SD: identificacao (o que o proprio cartao informa ao
--  sistema) e pistas. Somente leitura. Fonte: /sys/block/mmcblkN/device/
--    name, manfid, oemid, date, serial, type, hwrev, fwrev  +  /sys/block/mmcblkN/size
--  Estas informacoes NAO comprovam capacidade real: so um teste completo de
--  gravacao/leitura comprova (nao incluido, por ser pesado para o R36S).
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")
local C = require("config")

local S = {}
local BLOCK = os.getenv("PORTHUB_BLOCK_DIR") or "/sys/block"

-- Codigos de fabricante (manfid) de cartoes SD amplamente documentados
local MANUFACTURERS = {
  [0x01] = "Panasonic", [0x02] = L("Toshiba / Kioxia"), [0x03] = "SanDisk", [0x1b] = "Samsung",
  [0x1d] = "ADATA", [0x27] = L("Phison (várias marcas)"), [0x28] = "Lexar", [0x31] = L("Silicon Power"),
  [0x41] = "Kingston", [0x74] = "Transcend", [0x76] = "Patriot", [0x82] = "Sony",
}

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  s = s and U.trim(s) or nil
  if s == "" then return nil end
  return s
end

--- cartao (mmcblkN) onde ficam os ports, a partir do dispositivo do df
function S.ports_device()
  local out = U.capture("df -P " .. U.shq(C.PORTS_DIR) .. " 2>/dev/null") or ""
  local dev = out:match("\n(/dev/%S+)")
  if not dev then return nil end
  return dev:match("/dev/(mmcblk%d+)")
end

--- lista os cartoes SD presentes (ignora boot/rpmb de eMMC)
function S.list()
  local cards = {}
  local out = U.capture("ls -1 " .. U.shq(BLOCK) .. " 2>/dev/null") or ""
  for name in out:gmatch("[^\n]+") do
    if name:match("^mmcblk%d+$") then cards[#cards + 1] = S.info(name) end
  end
  return cards
end

--- dados de um cartao
function S.info(name)
  local dev = BLOCK .. "/" .. name .. "/device"
  local c = { dev = name }
  c.name = read(dev .. "/name")
  c.manfid = tonumber(read(dev .. "/manfid") or "")
  c.oemid = tonumber(read(dev .. "/oemid") or "")
  c.date = read(dev .. "/date")
  c.serial = read(dev .. "/serial")
  c.type = read(dev .. "/type")
  c.hwrev = read(dev .. "/hwrev")
  c.fwrev = read(dev .. "/fwrev")
  -- classe de velocidade: registro SSR do cartao (o kernel mostra em "ssr" nas versoes novas)
  c.ssr = read(dev .. "/ssr")
  c.class = S.parse_ssr(c.ssr)
  local sectors = tonumber(read(BLOCK .. "/" .. name .. "/size") or "")
  c.bytes = sectors and sectors * 512 or nil
  c.maker = c.manfid and MANUFACTURERS[c.manfid] or nil
  -- OEM: dois caracteres ASCII (ex.: "SD", "SM", "TM")
  if c.oemid and c.oemid > 0 then
    local a, b = math.floor(c.oemid / 256), c.oemid % 256
    if a >= 32 and a < 127 and b >= 32 and b < 127 then c.oem_txt = string.char(a, b) end
  end
  c.hints = S.hints(c)
  return c
end

-- ---------------------------------------------------------------------------
-- SSR (SD Status, 512 bits) - especificacao SD, campos usados:
--   SPEED_CLASS [447:440]  0=Classe 0, 1=Classe 2, 2=Classe 4, 3=Classe 6, 4=Classe 10
--   UHS_SPEED_GRADE [399:396]  0=nenhuma, 1=U1, 3=U3
--   VIDEO_SPEED_CLASS [391:384]  0, 6, 10, 30, 60, 90 (V6..V90)
--   APP_PERF_CLASS [339:336]  0=nenhuma, 1=A1, 2=A2
-- Minimo de gravacao sequencial de cada classe (MB/s): Classe N = N; U1 = 10;
-- U3 = 30; Vn = n.
local SPEED = { [0] = 0, [1] = 2, [2] = 4, [3] = 6, [4] = 10 }

function S.parse_ssr(hex)
  hex = tostring(hex or ""):gsub("[^%x]", "")
  if #hex ~= 128 then return nil end
  local bits = {}
  for i = 1, #hex do
    local v = tonumber(hex:sub(i, i), 16)
    for k = 3, 0, -1 do bits[#bits + 1] = math.floor(v / 2 ^ k) % 2 end
  end
  local function field(hi, lo)
    local v = 0
    for b = hi, lo, -1 do v = v * 2 + bits[512 - b] end
    return v
  end
  local sc, uhs, vsc, app = field(447, 440), field(399, 396), field(391, 384), field(339, 336)
  if sc == 0 and uhs == 0 and vsc == 0 and app == 0 then return { none = true } end
  local r = { parts = {}, min_mb = 0 }
  if SPEED[sc] and SPEED[sc] > 0 then
    r.parts[#r.parts + 1] = L("Classe ") .. SPEED[sc]; r.min_mb = math.max(r.min_mb, SPEED[sc])
  end
  if uhs == 1 or uhs == 3 then
    r.parts[#r.parts + 1] = "U" .. uhs; r.min_mb = math.max(r.min_mb, uhs == 1 and 10 or 30)
  end
  if vsc == 6 or vsc == 10 or vsc == 30 or vsc == 60 or vsc == 90 then
    r.parts[#r.parts + 1] = "V" .. vsc; r.min_mb = math.max(r.min_mb, vsc)
  end
  if app == 1 or app == 2 then r.parts[#r.parts + 1] = "A" .. app end
  r.text = table.concat(r.parts, " ")
  if r.text == "" then r.none = true end
  return r
end

--- pistas (nao sao prova). Devolve lista { text, level = "ok"|"warn"|"info" }
function S.hints(c)
  local h = {}
  if not c.manfid and not c.name then
    h[#h + 1] = { level = "info", text = L("O sistema não informou os dados de identificação deste cartão.") }
    return h
  end
  if c.manfid == 0 or c.manfid == 0xff then
    h[#h + 1] = { level = "warn", text = L("Fabricante não informado (código 0x") .. string.format("%02X", c.manfid) .. L("): comum em cartões genéricos ou falsificados.") }
  elseif c.maker then
    h[#h + 1] = { level = "ok", text = L("Fabricante reconhecido: ") .. c.maker .. L(". Confira se é a mesma marca impressa no cartão.") }
  elseif c.manfid then
    h[#h + 1] = { level = "warn", text = string.format(L("Código de fabricante 0x%02X fora da lista de marcas conhecidas."), c.manfid) }
  end
  local mm, yy = (c.date or ""):match("^(%d+)/(%d+)$")
  yy = tonumber(yy)
  if yy then
    local now = tonumber(os.date("%Y"))
    if yy > now then
      h[#h + 1] = { level = "warn", text = L("Data de fabricação no futuro (") .. c.date .. L("): informação inconsistente.") }
    elseif yy <= 2000 then
      h[#h + 1] = { level = "warn", text = L("Data de fabricação zerada ou muito antiga (") .. c.date .. ")." }
    end
  end
  local nm = (c.name or ""):gsub("%s", "")
  if nm == "" or nm:match("^0+$") or nm:match("^[%.%-_]+$") then
    h[#h + 1] = { level = "warn", text = L("Nome do modelo vazio ou genérico.") }
  end
  if c.serial and (c.serial:lower() == "0x00000000" or c.serial:lower() == "0xffffffff") then
    h[#h + 1] = { level = "warn", text = L("Número de série zerado.") }
  end
  if c.class and c.class.none then
    h[#h + 1] = { level = "warn", text = L("O cartão não declara nenhuma classe de velocidade: comum em cartões genéricos.") }
  elseif c.class and c.class.text then
    h[#h + 1] = { level = "info", text = L("Classe declarada pelo cartão: ") .. c.class.text .. L(". Confira se é a mesma impressa no cartão e faça o teste de velocidade.") }
  end
  return h
end

return S
