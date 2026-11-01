-- =============================================================================
--  Verificador de integridade dos ports (thread). SOMENTE LEITURA.
--  Recebe a lista de ports encontrados pela varredura (scan.lua) e confere cada
--  um. Cada verificacao tem um estado:
--    ok   = confirmado que esta certo        warn = confirmado, merece atencao
--    err  = confirmado que esta errado       unk  = nao foi possivel confirmar
-- =============================================================================
require("love.timer")
local job = ...
require("love.filesystem")
local I18N = require("lib.i18n")
I18N.set(job.lang or "pt-BR")
local L = I18N.L
local OUT = love.thread.getChannel(job.out)
local CTL = love.thread.getChannel(job.ctl)
local PORTS = job.ports_dir
local PM = job.pm_dir

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function capture(cmd)
  local h = io.popen(cmd)
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end
local function test(flag, path)
  local r = os.execute("test " .. flag .. " " .. shq(path))
  return r == 0 or r == true
end

local function read_head(path, n)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read(n or 65536)
  f:close()
  return s or ""
end

local function check_port(p)
  local checks = {}
  local function add(state, label, detail) checks[#checks + 1] = { state = state, label = label, detail = detail or "" } end
  local spath = PORTS .. "/" .. p.script

  -- 1) script
  local f = io.open(spath, "rb")
  local size = f and f:seek("end") or nil
  if f then f:close() end
  local text = read_head(spath)
  if not text then
    add("err", "Script", L("não foi possível ler ") .. p.script)
  elseif size == 0 then
    add("err", "Script", p.script .. L(" está vazio (0 bytes)"))
  else
    add("ok", "Script", p.script .. " (" .. size .. L(" bytes)"))
    if text:sub(1, 2) == "#!" then
      add("ok", L("Início do script"), L("começa com #! (interpretador definido)"))
    else
      add("warn", L("Início do script"), L("não começa com #! na primeira linha"))
    end
    if text:find("\r\n", 1, true) then
      add("err", L("Quebras de linha"), L("formato do Windows (CRLF): o bash costuma falhar com este script"))
    else
      add("ok", L("Quebras de linha"), L("formato Linux (LF)"))
    end
  end

  -- 2) pasta de dados
  local dir = p.dir
  if dir and test("-d", PORTS .. "/" .. dir) then
    local src = ({ ["port.json"] = L("port.json do PortMaster"), GAMEDIR = L("linha GAMEDIR do script"), nome = L("mesmo nome do script") })[p.dir_source or ""] or "detectada"
    add("ok", "Pasta de dados", dir .. " (" .. src .. ")")
    local any = capture("ls -A " .. shq(PORTS .. "/" .. dir) .. " 2>/dev/null | head -n 1") or ""
    if any:gsub("%s", "") == "" then add("err", L("Conteúdo da pasta"), dir .. L(" está vazia")) end
    -- links quebrados dentro da pasta
    local broken = capture("find " .. shq(PORTS .. "/" .. dir) .. " -type l 2>/dev/null | while IFS= read -r l; do [ -e \"$l\" ] || echo \"$l\"; done | head -n 3")
    if broken == nil then
      add("unk", L("Links"), L("não foi possível procurar links quebrados"))
    elseif broken:gsub("%s", "") ~= "" then
      local first = broken:match("[^\n]+"):gsub("^" .. PORTS:gsub("%p", "%%%0") .. "/", "")
      add("warn", L("Links"), L("link quebrado: ") .. first)
    end
    -- restos de transferencias/instalacoes interrompidas
    local part = capture("find " .. shq(PORTS .. "/" .. dir) .. " -name '*.porthub-part' 2>/dev/null | head -n 1") or ""
    if part:gsub("%s", "") ~= "" then add("warn", L("Arquivos temporários"), L("há arquivo incompleto (.porthub-part) na pasta")) end
  elseif p.gamedir then
    add("err", "Pasta de dados", L("o script usa GAMEDIR \"") .. p.gamedir .. L("\", mas essa pasta não existe"))
  else
    add("unk", "Pasta de dados", L("não foi possível identificar a pasta do jogo (alguns ports são só o script)"))
  end

  -- 3) itens declarados pelo PortMaster (port.json)
  if p.pm_items and #p.pm_items > 0 then
    local missing = {}
    for _, it in ipairs(p.pm_items) do
      if not test("-e", PORTS .. "/" .. it) then missing[#missing + 1] = it end
    end
    if #missing > 0 then
      add("err", L("Itens do PortMaster"), L("faltando: ") .. table.concat(missing, ", "))
    else
      add("ok", L("Itens do PortMaster"), #p.pm_items .. L(" item(ns) do port.json presentes"))
    end
  end

  -- 4) registro do hub (instalado por aqui)
  if p.hub_entries then
    local missing = {}
    for _, it in ipairs(p.hub_entries) do
      if not test("-e", PORTS .. "/" .. it) then missing[#missing + 1] = it end
    end
    if #missing > 0 then add("err", L("Instalação do hub"), L("faltando: ") .. table.concat(missing, ", "))
    else add("ok", L("Instalação do hub"), L("todos os itens instalados pelo hub presentes")) end
  end

  -- 5) dependencia do PortMaster e runtime
  if text and text:find("control.txt", 1, true) then
    if PM then
      add("ok", "PortMaster", L("o script usa o PortMaster, encontrado em ") .. PM)
    else
      add("err", "PortMaster", L("o script precisa do PortMaster, que não foi encontrado no console"))
    end
  end
  local runtimes, seen = {}, {}
  local function addrt(r)
    r = r and r:gsub("%.squashfs$", "")
    if r and r ~= "" and not r:find("[%$%s/]") and not seen[r] then seen[r] = true; runtimes[#runtimes + 1] = r end
  end
  if text then
    for r in text:gmatch("\n%s*runtime%s*=%s*[\"']?([%w%._%-]+)") do addrt(r) end
  end
  if dir then
    local pj = read_head(PORTS .. "/" .. dir .. "/port.json", 16384) or ""
    local blk = pj:match('"runtime"%s*:%s*(%b[])')
    if blk then for r in blk:gmatch('"([^"]+)"') do addrt(r) end end
    addrt(pj:match('"runtime"%s*:%s*"([^"]+)"'))
  end
  for _, r in ipairs(runtimes) do
    if not PM then
      add("unk", L("Runtime ") .. r, L("PortMaster não encontrado: não dá para conferir"))
    elseif test("-e", PM .. "/libs/" .. r .. ".squashfs") or test("-e", PM .. "/libs/" .. r) then
      add("ok", L("Runtime ") .. r, L("presente em libs/"))
    else
      add("warn", L("Runtime ") .. r, L("não está em libs/ (o PortMaster pode baixar ao abrir, se houver internet; ou use Atualizar runtimes)"))
    end
  end

  -- estado geral
  local state = "ÍNTEGRO"
  for _, c in ipairs(checks) do
    if c.state == "err" then state = "ERRO"; break end
    if c.state == "warn" then state = "ATENÇÃO" end
    -- sem pasta identificada nao da para afirmar que esta integro
    if c.state == "unk" and c.label == "Pasta de dados" and state == "ÍNTEGRO" then state = "ATENÇÃO" end
  end
  return { script = p.script, title = p.title, source = p.source, state = state, checks = checks }
end

for i, p in ipairs(job.ports) do
  if CTL:pop() == "cancel" then OUT:push({ t = "cancelled" }); return end
  local ok, r = pcall(check_port, p)
  if not ok then
    r = { script = p.script, title = p.title, source = p.source, state = "ATENÇÃO",
      checks = { { state = "unk", label = L("Verificação"), detail = L("falha ao verificar: ") .. tostring(r) } } }
  end
  OUT:push({ t = "port", i = i, n = #job.ports, result = r })
end
OUT:push({ t = "done" })
