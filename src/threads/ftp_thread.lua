-- =============================================================================
--  R36S PORT HUB - servidor FTP (thread do proprio app, LuaSocket do LOVE)
--
--  - So modo passivo (PASV/EPSV), o padrao dos clientes Android e do FileZilla.
--  - Login obrigatorio (usuario/senha configurados); anonimo sempre recusado.
--  - Aceita somente clientes da rede local (enderecos privados).
--  - Jaula: todo caminho e normalizado dentro da raiz do cartao SD e o caminho
--    REAL (readlink -f) precisa continuar dentro dela (bloqueia ../ e links).
--  - Recebimento grava em arquivo temporario e so renomeia ao terminar bem.
--  - Exclusao/renomeacao de pastas importantes pede confirmacao NO CONSOLE.
--  - Nunca executa comandos enviados pelo cliente (SITE EXEC etc. recusados).
--  - Envia eventos reais (inicio, progresso, fim) para a interface.
-- =============================================================================
local socket = require("socket")
require("love.timer")

local cfg = ...
require("love.filesystem")
local I18N = require("lib.i18n")
I18N.set(cfg.lang or "pt-BR")
local L = I18N.L
local IN = love.thread.getChannel(cfg.in_channel)
local OUT = love.thread.getChannel(cfg.out_channel)

local ROOT = cfg.root_real          -- raiz real do cartao (sem barra no fim)
local MAX_SESSIONS = 6
local CHUNK = 256 * 1024
local IDLE_TIMEOUT = 900

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end
local function capture(cmd)
  local h = io.popen(cmd)
  if not h then return "" end
  local s = h:read("*a") or ""
  h:close()
  return s
end
local function ok(r) return r == 0 or r == true end
local function sh(cmd) return ok(os.execute(cmd)) end
local function now() return socket.gettime() end
local function log(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  print("[ftp] " .. table.concat(t, " "))
  io.stdout:flush()
end
local function emit(m) OUT:push(m) end

-- ---------------------------------------------------------------------------
-- Rede local apenas
local function is_private(ip)
  if not ip then return false end
  local a, b = ip:match("^(%d+)%.(%d+)%.")
  a, b = tonumber(a), tonumber(b)
  if a then
    return a == 10 or a == 127 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
      or (a == 169 and b == 254)
  end
  local l = ip:lower()
  return l == "::1" or l:match("^fe80:") ~= nil or l:match("^f[cd]") ~= nil
    or l:match("^::ffff:10%.") ~= nil or l:match("^::ffff:192%.168%.") ~= nil
end

-- ---------------------------------------------------------------------------
-- Caminhos
--- normaliza um caminho virtual ("/a/../b") sem nunca subir acima da raiz
local function vnorm(cwd, arg)
  local p = arg or ""
  if p:sub(1, 1) ~= "/" then p = cwd .. "/" .. p end
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif seg ~= "." and seg ~= "" then
      parts[#parts + 1] = seg
    end
  end
  return "/" .. table.concat(parts, "/")
end

local function real_of(vpath) return vpath == "/" and ROOT or (ROOT .. vpath) end

local function inside(real)
  return real == ROOT or real:sub(1, #ROOT + 1) == ROOT .. "/"
end

--- caminho real resolvido (links seguidos). nil se nao existir
local function resolve(real)
  local r = capture("readlink -f -- " .. shq(real) .. " 2>/dev/null"):gsub("\n$", "")
  if r == "" then return nil end
  return r
end

--- valida um caminho virtual. must_exist: o alvo precisa existir.
--- Devolve real (nao resolvido, para operar) ou nil, motivo
local function check(vpath, must_exist)
  if vpath:find("%z") or vpath:find("[\r\n]") then return nil, L("nome invalido") end
  local real = real_of(vpath)
  local exists = sh("test -e " .. shq(real) .. " -o -L " .. shq(real))
  if must_exist and not exists then return nil, L("nao encontrado") end
  if exists then
    local r = resolve(real)
    if not r or not inside(r) then return nil, L("fora do cartao SD") end
  else
    -- alvo novo: a pasta-mae real precisa estar dentro da raiz
    local parent = real:match("^(.*)/[^/]+$") or ROOT
    local r = resolve(parent)
    if not r or not inside(r) then return nil, L("fora do cartao SD") end
  end
  return real
end

local function is_dir(real) return sh("test -d " .. shq(real)) end
local function fsize(real)
  local f = io.open(real, "rb")
  if not f then return nil end
  local s = f:seek("end")
  f:close()
  return s
end

-- Protecao de pastas importantes (caminhos virtuais vindos do app):
--  trees: arvores de sistema (o hub, PortMaster, bios...). Excluir, renomear
--         ou sobrescrever QUALQUER item dentro delas pede confirmacao no console
--         (uma aprovacao vale 10 min para aquela arvore, naquela sessao).
--  selfs: pastas que pedem confirmacao para serem excluidas/renomeadas.
--         Todas as pastas do primeiro nivel do cartao tambem entram aqui.
local TREES = cfg.trees or {}
local SELFS = {}
for _, v in ipairs(cfg.selfs or {}) do SELFS[v] = true end
local function tree_of(v)
  for _, t in ipairs(TREES) do
    if v == t or v:sub(1, #t + 1) == t .. "/" then return t end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Listagem (stat em lote: uma chamada por diretorio)
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function entries(real_dir, single)
  local cmd
  if single then
    cmd = "stat -L -c '%A|%s|%Y|%n' -- " .. shq(real_dir) .. " 2>/dev/null"
  else
    cmd = "cd " .. shq(real_dir) .. " 2>/dev/null && stat -L -c '%A|%s|%Y|%n' -- * .[!.]* ..?* 2>/dev/null"
  end
  local out = capture(cmd)
  local list = {}
  for line in out:gmatch("[^\n]+") do
    local perm, size, mtime, name = line:match("^([^|]+)|(%d+)|(%d+)|(.*)$")
    if name then
      if single then name = name:match("([^/]+)$") or name end
      list[#list + 1] = { perm = perm, size = tonumber(size), mtime = tonumber(mtime), name = name,
        dir = perm:sub(1, 1) == "d" }
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return list
end

local function list_unix(es)
  local nowt = os.time()
  local lines = {}
  for _, e in ipairs(es) do
    local t = os.date("*t", e.mtime)
    local when
    if math.abs(nowt - e.mtime) < 180 * 86400 then
      when = string.format("%s %2d %02d:%02d", MONTHS[t.month], t.day, t.hour, t.min)
    else
      when = string.format("%s %2d  %4d", MONTHS[t.month], t.day, t.year)
    end
    local perm = e.perm
    if perm:sub(1, 1) == "l" then perm = "-" .. perm:sub(2) end
    lines[#lines + 1] = string.format("%s 1 r36s r36s %12d %s %s", perm, e.size, when, e.name)
  end
  return table.concat(lines, "\r\n") .. (#lines > 0 and "\r\n" or "")
end

local function fact_time(t) return os.date("!%Y%m%d%H%M%S", t) end
local function mlsx_line(e, name)
  return string.format(L("type=%s;size=%d;modify=%s;perm=%s; %s"), e.dir and "dir" or "file", e.size,
    fact_time(e.mtime), e.dir and "elcdmfp" or "rwadf", name or e.name)
end

-- ---------------------------------------------------------------------------
-- Sessoes
local server, err = socket.bind("*", cfg.port)
if not server then
  emit({ t = "error", code = (tostring(err):find("in use") and "port_in_use" or "bind_failed"), detail = tostring(err) })
  return
end
server:settimeout(0)
log("ouvindo na porta", cfg.port, "raiz", ROOT)
emit({ t = "started", port = cfg.port })

local sessions = {}
local xfer_seq = 0
local confirm_seq = 0
local running = true

local function reply(s, code, text)
  local line = code .. " " .. text .. "\r\n"
  s.ctrl:settimeout(5)
  s.ctrl:send(line)
  s.ctrl:settimeout(0)
end

local function reply_multi(s, code, lines, last)
  local buf = { code .. "-" .. lines[1] }
  for i = 2, #lines do buf[#buf + 1] = " " .. lines[i] end
  buf[#buf + 1] = code .. " " .. last
  s.ctrl:settimeout(5)
  s.ctrl:send(table.concat(buf, "\r\n") .. "\r\n")
  s.ctrl:settimeout(0)
end

local function count_clients()
  local n = 0
  for _, s in ipairs(sessions) do if s.authed then n = n + 1 end end
  return n
end

local function close_data(s)
  if s.data then pcall(s.data.close, s.data); s.data = nil end
  if s.pasv then pcall(s.pasv.close, s.pasv); s.pasv = nil end
end

--- termina uma transferencia. result: done | error | cancelled
local function end_xfer(s, result, reason)
  local x = s.xfer
  if not x then return end
  s.xfer = nil
  if x.file then pcall(x.file.close, x.file); x.file = nil end
  local elapsed = math.max(0.001, now() - x.t0)
  if x.kind == "STOR" then
    if result == "done" then
      -- confere o tamanho gravado antes de considerar concluido
      local got = fsize(x.tmp)
      if got ~= x.done + (x.offset or 0) then
        result, reason = "error", L("tamanho gravado nao confere")
      elseif x.tmp ~= x.real and not os.rename(x.tmp, x.real) then
        result, reason = "error", L("nao foi possivel salvar o arquivo")
      end
    end
    if result ~= "done" and x.tmp ~= x.real then os.remove(x.tmp) end
  end
  close_data(s)
  if x.id then
    emit({ t = "xfer_end", id = x.id, result = result, reason = reason or "", done = x.done,
      total = x.total, elapsed = elapsed, avg = x.done / elapsed })
  end
  if result == "done" then
    reply(s, 226, L("Transferencia concluida."))
  elseif result == "cancelled" then
    reply(s, 426, L("Transferencia interrompida."))
  else
    reply(s, 451, L("Falha: ") .. (reason or "erro"))
  end
end

local function close_session(s, why)
  if s.xfer then end_xfer(s, "cancelled", why or L("conexao encerrada")) end
  close_data(s)
  pcall(s.ctrl.close, s.ctrl)
  s.closed = true
  log("cliente desconectado", s.peer, why or "")
end

--- prepara a conexao de dados e comeca uma transferencia
local function begin_xfer(s, x)
  if not s.pasv and not s.data then
    reply(s, 425, L("Use PASV ou EPSV primeiro."))
    if x.file then x.file:close() end
    if x.tmp and x.tmp ~= x.real then os.remove(x.tmp) end
    return
  end
  x.t0 = now()
  x.done = 0
  x.last_t, x.last_done, x.speed = x.t0, 0, 0
  if x.kind == "RETR" or x.kind == "STOR" then
    xfer_seq = xfer_seq + 1
    x.id = xfer_seq
    emit({ t = "xfer_start", id = x.id, name = x.name, path = x.vpath, op = x.kind == "STOR" and "recv" or "send",
      total = x.total, peer = s.peer })
  end
  s.xfer = x
  reply(s, 150, L("Abrindo conexao de dados."))
end

-- ---------------------------------------------------------------------------
-- Comandos
local CMD = {}

CMD.USER = function(s, arg)
  s.user = arg
  s.authed = false
  if arg:lower() == "anonymous" or arg:lower() == "ftp" then
    reply(s, 530, L("Acesso anonimo nao permitido."))
    s.user = nil
    return
  end
  reply(s, 331, L("Informe a senha."))
end

CMD.PASS = function(s, arg)
  if not s.user then reply(s, 503, L("Informe o usuario primeiro.")); return end
  if s.user == cfg.user and arg == cfg.pass then
    s.authed = true
    s.fails = 0
    reply(s, 230, L("Login efetuado. Raiz: cartao SD."))
    log("login ok", s.peer)
    emit({ t = "clients", n = count_clients() })
  else
    s.fails = (s.fails or 0) + 1
    s.user = nil
    reply(s, 530, L("Usuario ou senha incorretos."))
    log("login falhou", s.peer, s.fails)
    if s.fails >= 3 then close_session(s, L("muitas tentativas de login")) end
  end
end

CMD.SYST = function(s) reply(s, 215, L("UNIX Type: L8")) end
CMD.NOOP = function(s) reply(s, 200, "OK") end
CMD.FEAT = function(s)
  reply_multi(s, 211, { L("Recursos:"), "PASV", "EPSV", "SIZE", "MDTM", L("REST STREAM"), L("MLST type*;size*;modify*;perm*;"), "UTF8" }, L("Fim"))
end
CMD.OPTS = function(s, arg)
  if arg:upper():match("^UTF8") then reply(s, 200, L("UTF8 ativo.")) else reply(s, 501, L("Opcao nao suportada.")) end
end
CMD.TYPE = function(s, arg)
  local t = arg:upper():sub(1, 1)
  if t == "I" or t == "A" or t == "L" then s.type = t; reply(s, 200, L("Tipo ") .. t) else reply(s, 504, L("Tipo nao suportado.")) end
end
CMD.MODE = function(s, arg) if arg:upper() == "S" then reply(s, 200, L("Modo S.")) else reply(s, 504, L("Somente modo S.")) end end
CMD.STRU = function(s, arg) if arg:upper() == "F" then reply(s, 200, L("Estrutura F.")) else reply(s, 504, L("Somente F.")) end end
CMD.ALLO = function(s) reply(s, 202, L("Nao necessario.")) end
CMD.PWD = function(s) reply(s, 257, '"' .. s.cwd:gsub('"', '""') .. '" e a pasta atual.') end
CMD.XPWD = CMD.PWD

CMD.CWD = function(s, arg)
  local v = vnorm(s.cwd, arg)
  local real, why = check(v, true)
  if not real or not is_dir(real) then reply(s, 550, L("Pasta indisponivel: ") .. (why or L("nao e pasta"))); return end
  s.cwd = v
  reply(s, 250, L("Pasta: ") .. v)
end
CMD.XCWD = CMD.CWD
CMD.CDUP = function(s) CMD.CWD(s, "..") end
CMD.XCUP = CMD.CDUP

local function open_pasv(s, extended)
  close_data(s)
  local ip = s.ctrl:getsockname()
  local l = socket.bind(ip, 0)
  if not l then reply(s, 425, L("Nao foi possivel abrir a porta de dados.")); return end
  l:settimeout(0)
  s.pasv = l
  local _, port = l:getsockname()
  port = tonumber(port)
  if extended then
    reply(s, 229, L("Modo passivo estendido (|||") .. port .. "|)")
  else
    local a, b, c, d = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then reply(s, 425, L("Use EPSV.")); return end
    reply(s, 227, string.format("Modo passivo (%s,%s,%s,%s,%d,%d)", a, b, c, d, math.floor(port / 256), port % 256))
  end
end
CMD.PASV = function(s) open_pasv(s, false) end
CMD.EPSV = function(s, arg)
  if arg:upper() == "ALL" then reply(s, 200, L("EPSV ALL ok.")); return end
  open_pasv(s, true)
end
CMD.PORT = function(s) reply(s, 502, L("Modo ativo nao suportado; use o modo passivo.")) end
CMD.EPRT = CMD.PORT

CMD.REST = function(s, arg)
  local n = tonumber(arg)
  if not n or n < 0 then reply(s, 501, L("Posicao invalida.")); return end
  s.rest = n
  reply(s, 350, L("Reinicio na posicao ") .. n .. ".")
end

local function do_list(s, arg, kind)
  -- ignora opcoes estilo ls (-la, -a)
  local path = (arg or ""):gsub("^%-%a+%s*", "")
  local v = vnorm(s.cwd, path)
  local real, why = check(v, true)
  if not real then reply(s, 550, L("Indisponivel: ") .. why); return end
  local text
  if is_dir(real) then
    local es = entries(real)
    if kind == "NLST" then
      local names = {}
      for _, e in ipairs(es) do names[#names + 1] = e.name end
      text = table.concat(names, "\r\n") .. (#names > 0 and "\r\n" or "")
    elseif kind == "MLSD" then
      local lines = {}
      for _, e in ipairs(es) do lines[#lines + 1] = mlsx_line(e) end
      text = table.concat(lines, "\r\n") .. (#lines > 0 and "\r\n" or "")
    else
      text = list_unix(es)
    end
  else
    local es = entries(real, true)
    text = kind == "MLSD" and "" or (kind == "NLST" and (v:match("([^/]+)$") .. "\r\n") or list_unix(es))
  end
  begin_xfer(s, { kind = "LIST", buf = text, pos = 1, total = #text, name = L("(listagem)") })
end
CMD.LIST = function(s, arg) do_list(s, arg, "LIST") end
CMD.NLST = function(s, arg) do_list(s, arg, "NLST") end
CMD.MLSD = function(s, arg) do_list(s, arg, "MLSD") end
CMD.MLST = function(s, arg)
  local v = vnorm(s.cwd, arg)
  local real, why = check(v, true)
  if not real then reply(s, 550, L("Indisponivel: ") .. why); return end
  local e = entries(real, true)[1]
  if not e then reply(s, 550, L("Indisponivel.")); return end
  reply_multi(s, 250, { L("Info:"), mlsx_line(e, v) }, L("Fim"))
end

CMD.SIZE = function(s, arg)
  local real, why = check(vnorm(s.cwd, arg), true)
  if not real or is_dir(real) then reply(s, 550, L("Indisponivel: ") .. (why or L("e uma pasta"))); return end
  reply(s, 213, tostring(fsize(real) or 0))
end
CMD.MDTM = function(s, arg)
  local real, why = check(vnorm(s.cwd, arg), true)
  if not real then reply(s, 550, L("Indisponivel: ") .. why); return end
  local e = entries(real, true)[1]
  if not e then reply(s, 550, L("Indisponivel.")); return end
  reply(s, 213, fact_time(e.mtime))
end

--- operacoes destrutivas em itens importantes aguardam confirmacao no console.
--- Devolve a chave a confirmar (ou nil se nao precisa)
local function needs_confirm(s, v)
  local t = tree_of(v)
  if t then
    local okt = s.allowed and s.allowed[t]
    if okt and now() - okt < 600 then return nil end
    return t, true
  end
  if SELFS[v] or (v:match("^/[^/]+$") and is_dir(real_of(v))) then return v, false end
  return nil
end

--- executa run() direto ou depois da confirmacao no console
local function guarded(s, op, v, shown, run)
  local key, is_tree = needs_confirm(s, v)
  if not key then run(); return end
  confirm_seq = confirm_seq + 1
  s.waiting = { id = confirm_seq, t = now(), op = op, path = shown or v,
    run = function()
      if is_tree then s.allowed = s.allowed or {}; s.allowed[key] = now() end
      run()
    end }
  emit({ t = "confirm", id = confirm_seq, op = op, path = shown or v, tree = is_tree and key or nil, peer = s.peer })
end

CMD.RETR = function(s, arg)
  local v = vnorm(s.cwd, arg)
  local real, why = check(v, true)
  if not real or is_dir(real) then reply(s, 550, L("Arquivo indisponivel: ") .. (why or L("e uma pasta"))); return end
  local f = io.open(real, "rb")
  if not f then reply(s, 550, L("Sem permissao para ler.")); return end
  local total = f:seek("end")
  local off = s.rest or 0
  s.rest = nil
  if off > total then off = 0 end
  f:seek("set", off)
  begin_xfer(s, { kind = "RETR", file = f, total = total - off, name = v:match("([^/]+)$"), vpath = v, real = real })
end

local do_store_go
local function do_store(s, arg, append)
  local v = vnorm(s.cwd, arg)
  if v == "/" then reply(s, 553, L("Nome invalido.")); return end
  local real, why = check(v, false)
  if not real then reply(s, 553, L("Destino recusado: ") .. why); return end
  if is_dir(real) then reply(s, 553, L("Ja existe uma pasta com esse nome.")); return end
  local off = s.rest or 0
  s.rest = nil
  local exists = sh("test -e " .. shq(real))
  if exists and tree_of(v) then
    guarded(s, L("substituir o arquivo"), v, nil, function() s.rest = off; do_store_go(s, v, real, append, off) end)
    return
  end
  do_store_go(s, v, real, append, off)
end

do_store_go = function(s, v, real, append, off)
  s.rest = nil
  local f, tmp
  local base = append and (fsize(real) or 0) or off
  if append or off > 0 then
    -- continuacao: grava direto no arquivo (necessario para retomar)
    tmp = real
    f = io.open(real, append and "ab" or "r+b") or io.open(real, "wb")
    if f and not append then f:seek("set", off) end
  else
    local dir, bname = real:match("^(.*)/([^/]+)$")
    tmp = dir .. "/." .. bname .. ".porthub-part"
    f = io.open(tmp, "wb")
  end
  if not f then reply(s, 553, L("Sem permissao para gravar.")); return end
  begin_xfer(s, { kind = "STOR", file = f, tmp = tmp, real = real, offset = base, total = nil,
    name = v:match("([^/]+)$"), vpath = v })
end
CMD.STOR = function(s, arg) do_store(s, arg, false) end
CMD.APPE = function(s, arg) do_store(s, arg, true) end

CMD.MKD = function(s, arg)
  local v = vnorm(s.cwd, arg)
  local real, why = check(v, false)
  if not real or v == "/" then reply(s, 550, L("Recusado: ") .. (why or L("nome invalido"))); return end
  if sh("mkdir " .. shq(real) .. " 2>/dev/null") then
    reply(s, 257, '"' .. v .. '" criada.')
  else
    reply(s, 550, L("Nao foi possivel criar a pasta."))
  end
end
CMD.XMKD = CMD.MKD

CMD.DELE = function(s, arg)
  local v = vnorm(s.cwd, arg)
  local real, why = check(v, true)
  if not real or is_dir(real) then reply(s, 550, L("Recusado: ") .. (why or L("e uma pasta; use RMD"))); return end
  local function run()
    if os.remove(real) then reply(s, 250, L("Arquivo excluido.")) else reply(s, 550, L("Nao foi possivel excluir.")) end
  end
  guarded(s, L("excluir o arquivo"), v, nil, run)
end

CMD.RMD = function(s, arg)
  local v = vnorm(s.cwd, arg)
  if v == "/" then reply(s, 550, L("A raiz do cartao SD nao pode ser excluida.")); return end
  local real, why = check(v, true)
  if not real or not is_dir(real) then reply(s, 550, L("Recusado: ") .. (why or L("nao e pasta"))); return end
  -- se for um link para pasta, remove so o link
  local function run()
    local okr
    if sh("test -L " .. shq(real)) then okr = os.remove(real) else okr = sh("rmdir " .. shq(real) .. " 2>/dev/null") end
    if okr then reply(s, 250, L("Pasta excluida.")) else reply(s, 550, L("A pasta precisa estar vazia (o cliente apaga o conteudo antes).")) end
  end
  guarded(s, L("excluir a pasta"), v, nil, run)
end
CMD.XRMD = CMD.RMD

CMD.RNFR = function(s, arg)
  local v = vnorm(s.cwd, arg)
  if v == "/" then reply(s, 550, L("A raiz nao pode ser renomeada.")); return end
  local real, why = check(v, true)
  if not real then reply(s, 550, L("Recusado: ") .. why); return end
  s.rnfr = { v = v, real = real }
  reply(s, 350, L("Informe o novo nome."))
end
CMD.RNTO = function(s, arg)
  local from = s.rnfr
  s.rnfr = nil
  if not from then reply(s, 503, L("Use RNFR antes.")); return end
  local v = vnorm(s.cwd, arg)
  local real, why = check(v, false)
  if not real or v == "/" then reply(s, 553, L("Destino recusado: ") .. (why or "")); return end
  local function run()
    if os.rename(from.real, real) then reply(s, 250, L("Renomeado.")) else reply(s, 553, L("Nao foi possivel renomear.")) end
  end
  -- origem e destino passam pela protecao
  guarded(s, L("renomear/mover"), from.v, from.v .. " -> " .. v, function()
    if tree_of(v) and not tree_of(from.v) then guarded(s, L("mover para"), v, from.v .. " -> " .. v, run) else run() end
  end)
end

CMD.ABOR = function(s)
  if s.xfer then
    end_xfer(s, "cancelled", L("cancelado pelo cliente"))
    reply(s, 226, L("Abortado."))
  else
    close_data(s)
    reply(s, 226, L("Nada para abortar."))
  end
end
CMD.STAT = function(s) reply(s, 211, L("R36S PORT HUB FTP - ") .. count_clients() .. L(" cliente(s).")) end
CMD.HELP = function(s) reply(s, 214, L("Comandos: USER PASS PWD CWD CDUP LIST NLST MLSD MLST RETR STOR APPE REST SIZE MDTM MKD RMD DELE RNFR RNTO PASV EPSV TYPE NOOP QUIT")) end
CMD.SITE = function(s) reply(s, 502, L("Comandos SITE nao sao permitidos.")) end
CMD.QUIT = function(s) reply(s, 221, L("Ate logo.")); close_session(s, "saiu") end

local OPEN_CMDS = { USER = true, PASS = true, QUIT = true, SYST = true, FEAT = true, OPTS = true, NOOP = true, HELP = true }

local function handle(s, line)
  local cmd, arg = line:match("^(%S+)%s?(.*)$")
  if not cmd then return end
  cmd = cmd:upper()
  arg = arg or ""
  s.last = now()
  if not s.authed and not OPEN_CMDS[cmd] then reply(s, 530, L("Faca login primeiro.")); return end
  if s.xfer and cmd ~= "ABOR" and cmd ~= "STAT" and cmd ~= "NOOP" and cmd ~= "QUIT" then
    reply(s, 425, L("Transferencia em andamento."))
    return
  end
  if cmd ~= "REST" and cmd ~= "RETR" and cmd ~= "STOR" and cmd ~= "APPE" then s.rest = nil end
  local f = CMD[cmd]
  if not f then reply(s, 502, L("Comando nao suportado.")); return end
  local okc, e = pcall(f, s, arg)
  if not okc then
    log("erro no comando", cmd, e)
    pcall(reply, s, 451, L("Erro interno."))
  end
end

-- ---------------------------------------------------------------------------
-- Transferencias (nao bloqueantes)
local function step_send(s)
  local x = s.xfer
  local budget = 4 * CHUNK
  while budget > 0 do
    if not x.pending then
      if x.kind == "LIST" then
        if x.pos > #x.buf then end_xfer(s, "done"); return end
        x.pending = x.buf:sub(x.pos, x.pos + CHUNK - 1)
        x.pos = x.pos + #x.pending
      else
        local data = x.file:read(CHUNK)
        if not data then end_xfer(s, "done"); return end
        x.pending = data
      end
      x.pidx = 1
    end
    local last, e, partial = s.data:send(x.pending, x.pidx)
    local sent_to = last or partial or (x.pidx - 1)
    local n = sent_to - x.pidx + 1
    if n > 0 then
      x.done = x.done + n
      budget = budget - n
    end
    if last then
      x.pending = nil
    else
      x.pidx = sent_to + 1
      if e == "closed" then end_xfer(s, "error", L("o cliente fechou a conexao de dados")); return end
      return -- timeout: socket cheio, continua no proximo ciclo
    end
  end
end

local function step_recv(s)
  local x = s.xfer
  local budget = 4 * CHUNK
  while budget > 0 do
    local data, e, partial = s.data:receive(CHUNK)
    local chunk = data or partial
    if chunk and #chunk > 0 then
      local okw, werr = x.file:write(chunk)
      if not okw then end_xfer(s, "error", L("falha ao gravar (cartao cheio?) ") .. tostring(werr)); return end
      x.done = x.done + #chunk
      budget = budget - #chunk
    end
    if e == "closed" then
      local okf = x.file:flush()
      if not okf then end_xfer(s, "error", L("falha ao gravar")); return end
      -- fim dos dados. Espera um instante antes de confirmar: se o cliente
      -- mandar ABOR ou cair nesse meio tempo, o arquivo parcial e descartado
      x.eof = now()
      return
    elseif e == "timeout" then
      return
    elseif e then
      end_xfer(s, "error", L("conexao de dados: ") .. tostring(e))
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- Laco principal
local last_report = 0
while running do
  -- comandos da interface
  local m = IN:pop()
  while m do
    if m.t == "stop" then running = false
    elseif m.t == "confirm_answer" then
      for _, s in ipairs(sessions) do
        if s.waiting and s.waiting.id == m.id then
          local w = s.waiting
          s.waiting = nil
          if m.yes then pcall(w.run) else reply(s, 550, L("Operacao negada no console.")) end
        end
      end
    elseif m.t == "cancel_xfer" then
      for _, s in ipairs(sessions) do
        if s.xfer and s.xfer.id == m.id then end_xfer(s, "cancelled", L("cancelado no console")) end
      end
    end
    m = IN:pop()
  end
  if not running then break end

  local recvt, sendt = { server }, {}
  for _, s in ipairs(sessions) do
    if not s.closed then
      if not s.waiting then recvt[#recvt + 1] = s.ctrl end
      if s.pasv and not s.data then recvt[#recvt + 1] = s.pasv end
      if s.xfer and s.data then
        if s.xfer.kind == "STOR" then
          if not s.xfer.eof then recvt[#recvt + 1] = s.data end
        else sendt[#sendt + 1] = s.data end
      end
    end
  end
  local r, w = socket.select(recvt, sendt, 0.02)

  -- novas conexoes
  if r[server] then
    local c = server:accept()
    if c then
      local peer = c:getpeername()
      if not is_private(peer) then
        c:send("530 Somente a rede local pode acessar este servidor.\r\n")
        c:close()
        log("recusado (fora da rede local):", peer)
      elseif #sessions >= MAX_SESSIONS then
        c:send("421 Muitas conexoes. Tente mais tarde.\r\n")
        c:close()
      else
        c:settimeout(0)
        c:setoption("tcp-nodelay", true)
        local s = { ctrl = c, peer = peer, cwd = "/", buf = "", last = now(), type = "I" }
        sessions[#sessions + 1] = s
        reply(s, 220, L("R36S PORT HUB - servidor FTP. Somente rede local."))
        log("conexao de", peer)
      end
    end
  end

  for _, s in ipairs(sessions) do
    if not s.closed then
      -- controle
      if r[s.ctrl] then
        while true do
          local line, e, partial = s.ctrl:receive("*l")
          if line then
            local full = s.buf .. line
            s.buf = ""
            handle(s, (full:gsub("\r$", "")))
            if s.closed or s.waiting then break end
          else
            if e == "timeout" then s.buf = s.buf .. (partial or "")
            else close_session(s, L("conexao fechada")) end
            break
          end
        end
      end
      -- aceite da conexao de dados
      if not s.closed and s.pasv and not s.data and r[s.pasv] then
        local d = s.pasv:accept()
        if d then
          d:settimeout(0)
          s.data = d
          pcall(s.pasv.close, s.pasv)
          s.pasv = nil
        end
      end
      -- transferencia
      if not s.closed and s.xfer and s.data then
        if s.xfer.kind == "STOR" then
          if s.xfer.eof then
            if now() - s.xfer.eof > 0.4 then end_xfer(s, "done") end
          elseif r[s.data] then step_recv(s) end
        elseif w[s.data] then
          step_send(s)
        end
      end
      -- confirmacao sem resposta em 60 s: nega
      if s.waiting and now() - s.waiting.t > 60 then
        s.waiting = nil
        reply(s, 550, L("Sem confirmacao no console; operacao negada."))
      end
      if not s.closed and not s.xfer and now() - s.last > IDLE_TIMEOUT then
        reply(s, 421, L("Tempo esgotado."))
        close_session(s, "inativo")
      end
    end
  end

  -- remove sessoes encerradas
  local alive, changed = {}, false
  for _, s in ipairs(sessions) do
    if s.closed then changed = true else alive[#alive + 1] = s end
  end
  sessions = alive
  if changed then emit({ t = "clients", n = count_clients() }) end

  -- progresso real (a cada 0,25 s)
  local t = now()
  if t - last_report >= 0.25 then
    last_report = t
    local list = {}
    for _, s in ipairs(sessions) do
      local x = s.xfer
      if x and x.id then
        local dt = t - x.last_t
        if dt >= 0.5 then
          x.speed = (x.done - x.last_done) / dt
          x.last_t, x.last_done = t, x.done
        end
        list[#list + 1] = { id = x.id, done = x.done, total = x.total, speed = x.speed,
          elapsed = t - x.t0, avg = x.done / math.max(0.001, t - x.t0) }
      end
    end
    if #list > 0 then emit({ t = "progress", list = list }) end
  end
end

-- parada: encerra tudo
for _, s in ipairs(sessions) do
  pcall(reply, s, 421, L("Servidor encerrado no console."))
  close_session(s, L("servidor parado"))
end
pcall(server.close, server)
emit({ t = "stopped" })
log("servidor parado")
