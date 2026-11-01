-- =============================================================================
--  Registro de erros do R36S PORT HUB
--  Tudo fica dentro da pasta do port: r36sporthub/logs/
--    - erro_AAAAMMDD_HHMMSS.txt : uma travada do app (erro fatal) ou de uma tarefa
--      em segundo plano, com a mensagem, onde aconteceu (traceback), tela aberta,
--      versao, idioma, sistema e as ultimas linhas do registro do app;
--    - problemas_AAAA-MM-DD.txt : um arquivo por dia com as falhas mostradas na tela
--      (download que falhou, instalacao recusada, sem internet...).
--  Sem senhas: a senha do FTP e chaves de Wi-Fi sao apagadas do texto antes de gravar.
--  Mantem os 30 arquivos mais recentes (os mais antigos sao apagados).
-- =============================================================================
local M = {}

local MAX_FILES = 30
local RING = 200

M.ring = {}

--- guarda as ultimas linhas do registro do app (chamado pelo U.log)
function M.remember(line)
  local r = M.ring
  r[#r + 1] = os.date("%H:%M:%S ") .. line
  if #r > RING then table.remove(r, 1) end
end

local function C() return require("config") end

function M.dir() return C().APP_DIR .. "/logs" end

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end

--- tira dados sensiveis do texto
local function scrub(s)
  s = tostring(s or "")
  local ok, Ftp = pcall(require, "core.ftp")
  local pass = ok and Ftp and Ftp.cfg and Ftp.cfg.pass
  if type(pass) == "string" and #pass >= 3 then s = s:gsub(pass:gsub("%p", "%%%0"), "******") end
  s = s:gsub("([Pp][Ss][Kk][%s=:]+)%S+", "%1******")
  s = s:gsub("(802%-11%-wireless%-security%.psk%s+)%S+", "%1******")
  s = s:gsub("([Ss]enha[%s=:]+)%S+", "%1******")
  s = s:gsub("([Pp]assword[%s=:]+)%S+", "%1******")
  s = s:gsub("(PASS )%S+", "%1******")
  return s
end

local function prune()
  local d = M.dir()
  -- apaga so os nossos arquivos mais antigos (erro_*/problemas_*), nunca outra coisa
  os.execute("cd " .. shq(d) .. " 2>/dev/null && ls -1t erro_*.txt problemas_*.txt 2>/dev/null | tail -n +"
    .. (MAX_FILES + 1) .. " | while read -r f; do rm -f -- \"$f\"; done")
end

local function write(path, text, append)
  os.execute("mkdir -p " .. shq(M.dir()) .. " 2>/dev/null")
  local f = io.open(path, append and "ab" or "wb")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

--- cabecalho comum: versao, idioma, sistema, tela aberta
local function header()
  local t = {}
  local okc, cfg = pcall(C)
  t[#t + 1] = "R36S PORT HUB " .. tostring(okc and cfg.VERSION or "?")
  t[#t + 1] = "Data: " .. os.date("%Y-%m-%d %H:%M:%S")
  local okl, I18N = pcall(require, "lib.i18n")
  t[#t + 1] = "Idioma: " .. tostring(okl and I18N.lang or "?")
  local okp, cp = pcall(function() return package.loaded["core.compat"] and package.loaded["core.compat"].env end)
  local e = okp and cp or nil
  if e then
    t[#t + 1] = "Sistema: " .. tostring(e.os_name or "?") .. " " .. tostring(e.os_version or "")
      .. "  |  Kernel: " .. tostring(e.kernel or "?") .. "  |  Arquitetura: " .. tostring(e.arch or "?")
      .. "  |  Modelo: " .. tostring(e.model or "?")
  end
  local app = rawget(_G, "App")
  if type(app) == "table" and type(app.stack) == "table" then
    local names = {}
    for _, s in ipairs(app.stack) do names[#names + 1] = tostring(s.name) end
    t[#t + 1] = "Telas abertas: " .. table.concat(names, " > ")
  end
  return table.concat(t, "\n")
end

--- erro grave (travada do app ou de uma tarefa): um arquivo por ocorrencia
function M.crash(kind, msg, trace)
  local ok, res = pcall(function()
    local base = M.dir() .. "/erro_" .. os.date("%Y%m%d_%H%M%S")
    local path, n = base .. ".txt", 1
    while io.open(path, "rb") do n = n + 1; path = base .. "_" .. n .. ".txt" end
    local text = header() .. "\n"
      .. "Tipo: " .. tostring(kind) .. "\n"
      .. string.rep("=", 60) .. "\n"
      .. "ERRO:\n" .. scrub(msg) .. "\n\n"
      .. (trace and ("ONDE ACONTECEU:\n" .. scrub(trace) .. "\n\n") or "")
      .. "ULTIMAS LINHAS DO REGISTRO DO APP:\n" .. scrub(table.concat(M.ring, "\n")) .. "\n"
    if write(path, text) then prune(); return path end
  end)
  return ok and res or nil
end

--- problema mostrado ao usuario (sem travar): vai para o arquivo do dia
local last_key, last_t = nil, 0
function M.problem(title, body)
  pcall(function()
    local key = tostring(title) .. "|" .. tostring(body)
    -- a mesma mensagem repetida em seguida nao enche o arquivo
    if key == last_key and os.time() - last_t < 10 then return end
    last_key, last_t = key, os.time()
    local path = M.dir() .. "/problemas_" .. os.date("%Y-%m-%d") .. ".txt"
    local exists = io.open(path, "rb")
    if exists then exists:close() end
    local app = rawget(_G, "App")
    local cur = type(app) == "table" and app.current and app.current()
    local text = (exists and "" or (header() .. "\n" .. string.rep("=", 60) .. "\n"))
      .. "\n[" .. os.date("%H:%M:%S") .. "] " .. scrub(title)
      .. (cur and ("  (tela: " .. tostring(cur.name) .. ")") or "") .. "\n"
      .. scrub(body) .. "\n"
    if write(path, text, true) and not exists then prune() end
  end)
end

--- quantos arquivos de erro existem (para mostrar nas Configuracoes)
function M.count()
  local h = io.popen("ls -1 " .. shq(M.dir()) .. " 2>/dev/null | grep -cE '^(erro_|problemas_).*\\.txt$'")
  if not h then return 0 end
  local n = tonumber((h:read("*a") or ""):match("%d+")) or 0
  h:close()
  return n
end

return M
