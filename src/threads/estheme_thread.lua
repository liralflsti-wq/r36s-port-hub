-- =============================================================================
--  Instalacao de tema do EmulationStation (thread)
--  baixar -> conferir ZIP -> conferir entradas (ZIP Slip, links) -> espaco ->
--  extrair em pasta temporaria -> validar theme.xml -> backup da pasta antiga
--  (se existir) -> mover para a pasta de temas. Nenhum script e executado.
-- =============================================================================
require("love.timer")
local job = ...
require("love.filesystem")
local I18N = require("lib.i18n")
I18N.set(job.lang or "pt-BR")
local L = I18N.L
local OUT = love.thread.getChannel(job.out)
local IN = love.thread.getChannel(job.inn)

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end
local function sh(cmd) local r = os.execute(cmd); return r == 0 or r == true end
local function capture(cmd)
  local h = io.popen(cmd)
  if not h then return "" end
  local s = h:read("*a") or ""
  h:close()
  return s
end
local function fsize(p)
  local f = io.open(p, "rb")
  if not f then return 0 end
  local s = f:seek("end")
  f:close()
  return s or 0
end
local function fail(msg) OUT:push({ t = "error", msg = msg }); error("__stop__", 0) end

local W = job.tmp_dir .. "/estheme_job"
local ZIP = W .. "/theme.zip"
local STAGE = W .. "/stage"

local function run()
  if not job.folder:match("^[%w%._%-]+$") then fail(L("Nome de pasta do tema inválido.")) end
  if not sh("test -d " .. shq(job.dest)) then fail(L("A pasta de temas ") .. job.dest .. L(" não existe.")) end
  sh("rm -rf " .. shq(W) .. " && mkdir -p " .. shq(STAGE))

  -- 1) download para a pasta temporaria
  OUT:push({ t = "phase", phase = "download", total = job.size > 0 and job.size or nil })
  local rcf, pidf = W .. "/dl.rc", W .. "/dl.pid"
  sh("( sh " .. shq(job.fetch_sh) .. " get " .. shq(job.url) .. " " .. shq(ZIP) .. " " .. shq(pidf) .. " "
    .. shq(rcf) .. " 0 >/dev/null 2>&1 & )")
  local total = job.size > 0 and job.size or nil
  while true do
    local rc = io.open(rcf, "r")
    if rc then
      local code = tonumber((rc:read("*a") or ""):match("%d+") or "1")
      rc:close()
      if code == 143 or code == 137 then OUT:push({ t = "cancelled" }); error("__stop__", 0) end
      if code ~= 0 then fail(L("Falha no download do tema (código ") .. code .. L("). Verifique o Wi-Fi.")) end
      break
    end
    if IN:pop() == "cancel" then
      local p = io.open(pidf, "r")
      local pid = p and (p:read("*a") or ""):match("%d+")
      if p then p:close() end
      if pid then sh("kill " .. pid .. " 2>/dev/null") end
      love.timer.sleep(0.3)
      OUT:push({ t = "cancelled" })
      error("__stop__", 0)
    end
    OUT:push({ t = "progress", done = fsize(ZIP), total = total })
    love.timer.sleep(0.25)
  end
  local got = fsize(ZIP)
  OUT:push({ t = "progress", done = got, total = total })

  -- 2) arquivo integro?
  OUT:push({ t = "phase", phase = "verify" })
  if got == 0 then fail(L("O arquivo baixado veio vazio.")) end
  if job.size > 0 and got ~= job.size then fail(L("Download incompleto: o tamanho não confere.")) end
  if job.sha256 ~= "" then
    local sum = capture("sha256sum " .. shq(ZIP) .. " 2>/dev/null"):match("^(%x+)")
    if not sum or sum:lower() ~= job.sha256 then fail(L("O arquivo baixado não confere (sha256).")) end
  end
  local head = capture("head -c 4 " .. shq(ZIP) .. " | od -An -tx1 2>/dev/null"):gsub("%s", "")
  if head ~= "504b0304" then fail(L("O arquivo baixado não é um ZIP válido.")) end
  if not sh("command -v unzip >/dev/null 2>&1") then fail(L("O comando unzip não está disponível no sistema.")) end
  if not sh("unzip -tqq " .. shq(ZIP) .. " >/dev/null 2>&1") then fail(L("O ZIP está corrompido (teste de integridade falhou).")) end

  -- 3) conteudo seguro: nada fora da pasta (ZIP Slip) e nenhum link simbolico
  local names = capture("unzip -Z1 " .. shq(ZIP) .. " 2>/dev/null")
  local tops, n = {}, 0
  for name in names:gmatch("[^\n]+") do
    n = n + 1
    if name:sub(1, 1) == "/" or name:find("\\", 1, true) or name == ".." or name:match("^%.%./")
        or name:find("/%.%./") or name:match("/%.%.$") then
      fail(L("O ZIP tem um caminho inseguro (") .. name .. L("). Instalação recusada."))
    end
    tops[name:match("^([^/]+)") or name] = true
  end
  if n == 0 then fail(L("O ZIP está vazio.")) end
  for line in capture("unzip -Z " .. shq(ZIP) .. " 2>/dev/null"):gmatch("[^\n]+") do
    if line:match("^l[rwx%-]") then fail(L("O ZIP contém links simbólicos. Instalação recusada.")) end
  end

  -- 4) espaco livre (tamanho descompactado + margem)
  local unc = tonumber(capture("unzip -Zt " .. shq(ZIP) .. " 2>/dev/null"):match("(%d+) bytes uncompressed") or "0") or 0
  local avail = tonumber(capture("df -Pk " .. shq(job.dest) .. " 2>/dev/null | tail -n 1"):match("^%S+%s+%d+%s+%d+%s+(%d+)") or "0") * 1024
  if avail > 0 and avail < unc + job.margin then
    fail(string.format(L("Espaço insuficiente: o tema precisa de %.0f MB livres."), (unc + job.margin) / 1048576))
  end

  -- 5) extrair na pasta temporaria
  OUT:push({ t = "phase", phase = "extract" })
  local h = capture("unzip -o -q " .. shq(ZIP) .. " -d " .. shq(STAGE) .. " >/dev/null 2>&1; echo $?")
  if (tonumber(h:match("%d+") or "9") or 9) > 1 then fail(L("Falha ao extrair o tema (arquivo corrompido ou cartão cheio).")) end
  local count = 0
  for _ in pairs(tops) do count = count + 1 end
  local root = STAGE
  if count == 1 then
    local only = next(tops)
    if sh("test -d " .. shq(STAGE .. "/" .. only)) then root = STAGE .. "/" .. only end
  end
  -- links criados de alguma forma? recusa
  if capture("find " .. shq(STAGE) .. " -type l 2>/dev/null | head -n 1"):match("%S") then
    fail(L("O tema contém links simbólicos. Instalação recusada."))
  end
  -- estrutura: theme.xml na raiz ou em pastas de sistema (1 nivel)
  local has_xml = sh("test -f " .. shq(root .. "/theme.xml"))
    or capture("find " .. shq(root) .. " -mindepth 2 -maxdepth 2 -name theme.xml 2>/dev/null | head -n 1"):match("%S")
  if not has_xml then fail(L("O pacote não tem theme.xml: não parece um tema do EmulationStation.")) end

  -- 6) instalar (backup da pasta existente, troca por renomeacao)
  OUT:push({ t = "phase", phase = "install" })
  local dst = job.dest .. "/" .. job.folder
  local backup
  if sh("test -e " .. shq(dst)) then
    sh("mkdir -p " .. shq(job.tmp_dir .. "/estheme_backups"))
    backup = job.tmp_dir .. "/estheme_backups/" .. job.folder .. "-" .. os.date("%Y%m%d%H%M%S")
    if not sh("mv " .. shq(dst) .. " " .. shq(backup)) then fail(L("Não foi possível fazer o backup do tema existente.")) end
  end
  if not sh("mv " .. shq(root) .. " " .. shq(dst)) then
    -- outra particao: copia
    if not sh("cp -a " .. shq(root) .. " " .. shq(dst)) then
      sh("rm -rf " .. shq(dst))
      if backup then sh("mv " .. shq(backup) .. " " .. shq(dst)) end
      fail(L("Não foi possível copiar o tema para ") .. job.dest .. L(". Nada foi alterado."))
    end
  end
  -- confirma a instalacao: o tema precisa estar no destino com o theme.xml
  local placed = sh("test -f " .. shq(dst .. "/theme.xml"))
    or capture("find " .. shq(dst) .. " -mindepth 2 -maxdepth 2 -name theme.xml 2>/dev/null | head -n 1"):match("%S")
  if not placed then
    sh("rm -rf " .. shq(dst))
    if backup then sh("mv " .. shq(backup) .. " " .. shq(dst)) end
    fail(L("O tema não ficou completo no destino. A versão anterior (se havia) foi restaurada."))
  end
  local mk = io.open(dst .. "/.porthub_theme", "w")
  if mk then mk:write(job.id .. "\n"); mk:close() end
  sh("rm -rf " .. shq(W))
  OUT:push({ t = "done", backup = backup })
end

local ok, err = pcall(run)
if not ok and err ~= "__stop__" then OUT:push({ t = "error", msg = L("Erro interno: ") .. tostring(err) }) end
if not ok then sh("rm -rf " .. shq(W)) end
