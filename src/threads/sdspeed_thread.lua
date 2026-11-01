-- =============================================================================
--  Teste de velocidade do cartao (thread). Leve: grava um arquivo de teste de
--  poucos MB na pasta temporaria do hub (mesmo cartao dos ports), le de volta
--  e apaga. Nao toca em nenhum outro arquivo.
--  Leitura: so e informada se for possivel evitar o cache do sistema
--  (leitura direta ou limpeza do cache); senao, aparece como indisponivel.
-- =============================================================================
require("love.timer")
local job = ...
require("love.filesystem")
local I18N = require("lib.i18n")
I18N.set(job.lang or "pt-BR")
local L = I18N.L
local OUT = love.thread.getChannel(job.out)

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end
local function sh(cmd) local r = os.execute(cmd); return r == 0 or r == true end
local now = love.timer.getTime

local FILE = job.dir .. "/.porthub_speedtest.tmp"
local MB = job.mb
local res = { mb = MB }

sh("mkdir -p " .. shq(job.dir))
os.remove(FILE)

-- gravacao (com fsync: so termina quando os dados estao no cartao)
OUT:push({ t = "phase", phase = "write" })
local t0 = now()
local okw = sh("dd if=/dev/zero of=" .. shq(FILE) .. " bs=1M count=" .. MB .. " conv=fsync >/dev/null 2>&1")
local tw = now() - t0
if not okw then
  -- dd sem conv=fsync (versoes muito simples): grava e forca o sync
  t0 = now()
  okw = sh("dd if=/dev/zero of=" .. shq(FILE) .. " bs=1M count=" .. MB .. " >/dev/null 2>&1 && sync")
  tw = now() - t0
end
local f = io.open(FILE, "rb")
local size = f and f:seek("end") or 0
if f then f:close() end
if not okw or size < MB * 1024 * 1024 then
  os.remove(FILE)
  OUT:push({ t = "done", ok = false, error = L("Não foi possível gravar o arquivo de teste (espaço livre ou permissão).") })
  return
end
res.write = (MB * 1024 * 1024) / math.max(tw, 0.001)

-- leitura sem cache: 1) leitura direta (O_DIRECT)  2) limpar o cache (precisa de permissao)
OUT:push({ t = "phase", phase = "read" })
local function timed(cmd)
  local a = now()
  local ok = sh(cmd)
  return ok, now() - a
end
local okr, tr = timed("dd if=" .. shq(FILE) .. " of=/dev/null bs=1M iflag=direct >/dev/null 2>&1")
if okr then
  res.read, res.read_method = (MB * 1024 * 1024) / math.max(tr, 0.001), L("leitura direta")
else
  local dropped = sh("sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null")
    or sh("sync && sudo -n sh -c 'echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1")
  if dropped then
    okr, tr = timed("dd if=" .. shq(FILE) .. " of=/dev/null bs=1M >/dev/null 2>&1")
    if okr then res.read, res.read_method = (MB * 1024 * 1024) / math.max(tr, 0.001), L("cache limpo antes") end
  end
end
os.remove(FILE)
res.ok = true
res.t = "done"
OUT:push(res)
