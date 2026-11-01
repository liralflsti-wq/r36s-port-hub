-- =============================================================================
--  Servidor FTP - gerenciador (thread principal)
--  Configuracao em ftp.json (pasta de dados do app, permissao 600).
--  Historico em ftp_history.json (sem credenciais). Inicio/parada manuais.
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")
local json = require("lib.json")
local Net = require("core.net")

local F = {
  cfg = nil,
  thread = nil,
  state = "off",          -- off | starting | on | stopping
  clients = 0,
  xfers = {},             -- transferencias ativas e recentes (por id)
  order = {},             -- ids na ordem de chegada (mais recente no fim)
  history = {},
  confirms = {},          -- pedidos de confirmacao vindos dos clientes
  last_error = nil,
  root = nil,
}

local CFG_FILE = "ftp.json"
local HIST_FILE = "ftp_history.json"
local HIST_MAX = 60
local IN_CH, OUT_CH = "hub_ftp_in", "hub_ftp_out"

F.DEFAULT_PORT = 2121

local function save_dir_path(name) return love.filesystem.getSaveDirectory() .. "/" .. name end

local function random_pass(n)
  local chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  local t = {}
  for i = 1, n do
    local k = love.math.random(1, #chars)
    t[i] = chars:sub(k, k)
  end
  return table.concat(t)
end

local function restrict(name)
  os.execute("chmod 600 " .. U.shq(save_dir_path(name)) .. " 2>/dev/null")
end

function F.load()
  if F.cfg then return F.cfg end
  local ok, text = pcall(love.filesystem.read, CFG_FILE)
  local d = ok and text and json.decode(text) or nil
  if type(d) ~= "table" or type(d.user) ~= "string" or type(d.pass) ~= "string" then
    -- primeira vez: usuario padrao e senha aleatoria (nunca fica no codigo)
    d = { port = F.DEFAULT_PORT, user = "r36s", pass = random_pass(8) }
    F.cfg = d
    F.save()
  end
  d.port = tonumber(d.port) or F.DEFAULT_PORT
  F.cfg = d
  local okh, th = pcall(love.filesystem.read, HIST_FILE)
  local h = okh and th and json.decode(th) or nil
  F.history = type(h) == "table" and h or {}
  return d
end

function F.save()
  pcall(love.filesystem.write, CFG_FILE, json.encode({ port = F.cfg.port, user = F.cfg.user, pass = F.cfg.pass }))
  restrict(CFG_FILE)
end

local function save_history()
  while #F.history > HIST_MAX do table.remove(F.history, 1) end
  pcall(love.filesystem.write, HIST_FILE, json.encode(F.history))
end

function F.clear_history()
  F.history = {}
  save_history()
end

-- ---------------------------------------------------------------------------
-- Validacao
function F.valid_port(p)
  p = tonumber(p)
  if not p or p ~= math.floor(p) then return false, L("Porta inválida.") end
  if p == 21 then return false, L("A porta 21 não é usada (exige privilégios). Use 2121, por exemplo.") end
  if p < 1024 or p > 65535 then return false, L("Use uma porta entre 1024 e 65535.") end
  return true
end

function F.valid_user(u)
  if not u or #u < 3 then return false, L("O usuário precisa ter pelo menos 3 caracteres.") end
  if #u > 32 then return false, L("Usuário muito longo (máx. 32).") end
  if not u:match("^[%w%._%-]+$") then return false, L("Use só letras, números, ponto, hífen e sublinhado no usuário.") end
  local l = u:lower()
  if l == "anonymous" or l == "ftp" then return false, L("Esse nome é reservado para acesso anônimo, que não é permitido.") end
  return true
end

function F.valid_pass(p)
  if not p or #p < 6 then return false, L("A senha precisa ter pelo menos 6 caracteres.") end
  if #p > 64 then return false, L("Senha muito longa (máx. 64).") end
  if p:find("[%c]") then return false, L("A senha tem caracteres inválidos.") end
  return true
end

--- a porta esta livre agora? (tenta abrir e fecha em seguida)
function F.port_free(p)
  local ok, socket = pcall(require, "socket")
  if not ok then return true end
  local s = socket.bind("*", tonumber(p))
  if s then s:close(); return true end
  return false
end

-- ---------------------------------------------------------------------------
-- Raiz: ponto de montagem do cartao que guarda os ports (detectado)
function F.detect_root()
  local out = U.capture("df -P " .. U.shq(C.PORTS_DIR) .. " 2>/dev/null") or ""
  local mount
  for line in out:gmatch("[^\n]+") do
    local m = line:match("%%%s+(/.*)$")
    if m then mount = m end
  end
  local root = mount
  if not root or root == "/" then
    -- cartao unico (sem particao propria): usa a pasta acima de ports
    root = C.PORTS_DIR:match("^(.*)/[^/]+$")
    if not root or root == "" then root = C.PORTS_DIR end
  end
  local real = (U.capture("readlink -f -- " .. U.shq(root) .. " 2>/dev/null") or ""):gsub("%s+$", "")
  if real == "" then real = root end
  real = real:gsub("/+$", "")
  if real == "" then return nil end   -- nunca a raiz do sistema
  return real
end

--- converte um caminho real em virtual (relativo a raiz do cartao)
local function virt(root, real)
  if not real or real == "" then return nil end
  local r = (U.capture("readlink -f -- " .. U.shq(real) .. " 2>/dev/null") or ""):gsub("%s+$", "")
  if r == "" then r = real end
  if r == root then return "/" end
  if r:sub(1, #root + 1) == root .. "/" then return r:sub(#root + 1) end
  return nil
end

-- ---------------------------------------------------------------------------
-- Ciclo de vida
function F.running() return F.state == "on" or F.state == "starting" or F.state == "stopping" end

--- inicia o servidor. Devolve true ou false, motivo
function F.start()
  F.load()
  if F.thread and F.thread:isRunning() then return false, L("O servidor já está em execução.") end
  local okp, why = F.valid_port(F.cfg.port)
  if not okp then return false, why end
  local okv = F.valid_user(F.cfg.user) and F.valid_pass(F.cfg.pass)
  if not okv then return false, L("Defina usuário e senha válidos antes de iniciar.") end
  local net = Net.status()
  if not net.connected then return false, L("Sem conexão de rede. Conecte o console ao Wi-Fi.") end
  if not F.port_free(F.cfg.port) then
    return false, L("A porta ") .. F.cfg.port .. L(" já está em uso. Escolha outra porta.")
  end
  local root = F.detect_root()
  if not root or not U.is_dir(root) then return false, L("Não foi possível localizar o cartão SD.") end
  F.root = root

  local trees, selfs = {}, {}
  local function add(list, real)
    local v = virt(root, real)
    if v and v ~= "/" then list[#list + 1] = v end
  end
  add(trees, C.APP_DIR)
  for _, d in ipairs(C.PORTMASTER_DIRS) do add(trees, d) end
  add(trees, root .. "/bios")
  add(selfs, C.PORTS_DIR)

  -- canais limpos (sem restos de uma execucao anterior)
  local inn, out = love.thread.getChannel(IN_CH), love.thread.getChannel(OUT_CH)
  inn:clear(); out:clear()
  F.in_ch, F.out_ch = inn, out
  F.confirms = {}
  F.clients = 0
  F.last_error = nil
  F.thread = love.thread.newThread("threads/ftp_thread.lua")
  F.thread:start({ lang = require("lib.i18n").lang,
    in_channel = IN_CH, out_channel = OUT_CH, port = F.cfg.port,
    user = F.cfg.user, pass = F.cfg.pass, root_real = root, trees = trees, selfs = selfs,
  })
  F.state = "starting"
  U.log("FTP: iniciando na porta", F.cfg.port, "raiz", root)
  return true
end

function F.stop()
  if F.thread and F.thread:isRunning() then
    F.in_ch:push({ t = "stop" })
    F.state = "stopping"
  else
    F.state = "off"
  end
end

--- parada sincrona (usada ao sair do app). Espera no maximo ~2 s
function F.stop_wait()
  F.stop()
  local t0 = love.timer.getTime()
  while F.thread and F.thread:isRunning() and love.timer.getTime() - t0 < 2 do
    love.timer.sleep(0.02)
  end
  F.update()
  F.state = "off"
end

function F.answer_confirm(id, yes)
  if F.in_ch then F.in_ch:push({ t = "confirm_answer", id = id, yes = yes and true or false }) end
  for i, c in ipairs(F.confirms) do
    if c.id == id then table.remove(F.confirms, i); break end
  end
end

--- teste real: conecta no proprio servidor, confere a saudacao e o login.
--- Devolve ok, mensagem
function F.self_test(ip)
  if F.state ~= "on" then return false, L("O servidor está desativado. Use INICIAR primeiro.") end
  local ok, socket = pcall(require, "socket")
  if not ok then return false, L("LuaSocket indisponível.") end
  local host = ip or "127.0.0.1"
  local c = socket.tcp()
  c:settimeout(3)
  local t0 = socket.gettime()
  local okc, e = c:connect(host, F.cfg.port)
  if not okc then c:close(); return false, L("Não foi possível conectar em ") .. host .. ":" .. F.cfg.port .. " (" .. tostring(e) .. ")." end
  local function line()
    local l, er = c:receive("*l")
    -- respostas de varias linhas: le ate a linha final "NNN "
    while l and l:match("^%d%d%d%-") do l = c:receive("*l") end
    return l, er
  end
  local banner = line()
  local res
  if not banner or not banner:match("^220") then
    res = { false, L("O servidor não respondeu corretamente (") .. tostring(banner) .. ")." }
  else
    c:send(L("USER ") .. F.cfg.user .. "\r\n")
    local r1 = line() or ""
    c:send(L("PASS ") .. F.cfg.pass .. "\r\n")
    local r2 = line() or ""
    c:send("QUIT\r\n")
    line()
    local ms = math.floor((socket.gettime() - t0) * 1000 + 0.5)
    if r1:match("^331") and r2:match("^230") then
      res = { true, string.format(L("Servidor respondendo em %s:%d e login aceito (%d ms)."), host, F.cfg.port, ms) }
    else
      res = { false, L("O servidor respondeu, mas o login falhou: ") .. r2 }
    end
  end
  c:close()
  return res[1], res[2]
end

function F.cancel_xfer(id)
  if F.in_ch then F.in_ch:push({ t = "cancel_xfer", id = id }) end
end

--- muda credenciais/porta. Devolve true; se o servidor estiver ativo, o
--- chamador decide reiniciar (F.restart)
function F.set_config(port, user, pass)
  F.load()
  F.cfg.port, F.cfg.user, F.cfg.pass = tonumber(port), user, pass
  F.save()
end

function F.restart()
  F.pending_restart = true
  F.stop()
end

-- ---------------------------------------------------------------------------
-- Eventos vindos da thread
local function notify(text, kind) if F.on_notify then F.on_notify(text, kind) end end

local function hist_add(x)
  F.history[#F.history + 1] = {
    name = x.name, path = x.path, op = x.op, size = x.done, total = x.total,
    status = x.status, reason = x.reason, time = os.time(), elapsed = x.elapsed, avg = x.avg,
  }
  save_history()
end

local OPLBL = { recv = L("Recebendo"), send = L("Enviando") }

function F.update()
  local th = F.thread
  if th then
    local e = th:getError()
    if e then
      U.log("FTP: erro na thread:", e)
      F.last_error = L("Erro interno do servidor FTP.")
      notify(L("Servidor FTP parou por um erro interno."), "error")
      F.thread = nil
      F.state = "off"
    end
  end
  if not F.out_ch then return end
  local m = F.out_ch:pop()
  while m do
    if m.t == "started" then
      F.state = "on"
      notify(L("Servidor FTP ativado na porta ") .. m.port .. ".", "ok")
    elseif m.t == "error" then
      F.state = "off"
      F.last_error = m.code == "port_in_use" and (L("A porta ") .. F.cfg.port .. L(" já está em uso."))
        or (L("Não foi possível iniciar: ") .. tostring(m.detail))
      notify(F.last_error, "error")
    elseif m.t == "stopped" then
      F.state = "off"
      F.clients = 0
      for _, x in pairs(F.xfers) do
        if x.status == "AGUARDANDO" or x.status == "TRANSFERINDO" then x.status = "CANCELADO" end
      end
      if F.pending_restart then
        F.pending_restart = false
        local ok, why = F.start()
        if not ok then notify(why, "error") end
      else
        notify(L("Servidor FTP desativado."), "info")
      end
    elseif m.t == "clients" then
      F.clients = m.n
    elseif m.t == "confirm" then
      F.confirms[#F.confirms + 1] = m
    elseif m.t == "xfer_start" then
      local x = { id = m.id, name = m.name, path = m.path, op = m.op, total = m.total, done = 0, speed = 0, avg = 0,
        elapsed = 0, status = "AGUARDANDO", peer = m.peer, t0 = love.timer.getTime() }
      F.xfers[m.id] = x
      F.order[#F.order + 1] = m.id
      while #F.order > 20 do F.xfers[table.remove(F.order, 1)] = nil end
      notify(OPLBL[m.op] .. ": " .. m.name, "info")
    elseif m.t == "progress" then
      for _, p in ipairs(m.list) do
        local x = F.xfers[p.id]
        if x then
          x.done, x.speed, x.elapsed, x.avg = p.done, p.speed, p.elapsed, p.avg
          if p.total then x.total = p.total end
          if p.done > 0 and x.status == "AGUARDANDO" then x.status = "TRANSFERINDO" end
        end
      end
    elseif m.t == "xfer_end" then
      local x = F.xfers[m.id]
      if x then
        x.done, x.elapsed, x.avg = m.done, m.elapsed, m.avg
        x.speed = 0
        if x.op == "recv" and m.result == "done" then x.total = m.done end
        x.status = m.result == "done" and "CONCLUÍDO" or (m.result == "cancelled" and "CANCELADO" or "ERRO")
        x.reason = m.reason
        hist_add(x)
        if m.result == "done" then
          notify((x.op == "recv" and L("Recebido: ") or L("Enviado: ")) .. x.name, "ok")
        elseif m.result == "cancelled" then
          notify(L("Transferência cancelada: ") .. x.name, "warn")
        else
          notify(L("Falha na transferência: ") .. x.name .. " (" .. (m.reason or "erro") .. ")", "error")
        end
      end
    end
    m = F.out_ch:pop()
  end
  if F.state ~= "off" and F.thread and not F.thread:isRunning() and F.out_ch:getCount() == 0 then
    if F.state ~= "stopping" then F.state = "off" end
  end
end

--- transferencias para a tela (mais recentes primeiro)
function F.list()
  local t = {}
  for i = #F.order, 1, -1 do
    local x = F.xfers[F.order[i]]
    if x then t[#t + 1] = x end
  end
  return t
end

function F.active_count()
  local n = 0
  for _, x in pairs(F.xfers) do if x.status == "TRANSFERINDO" or x.status == "AGUARDANDO" then n = n + 1 end end
  return n
end

return F
