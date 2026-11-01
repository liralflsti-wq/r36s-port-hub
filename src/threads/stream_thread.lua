-- =============================================================================
--  R36S PORT HUB - transmissao da tela do hub (thread, LuaSocket do LOVE)
--
--  Servidor HTTP minimo, somente leitura:
--    GET /<codigo>     -> pagina de visualizacao (HTML embutido, sem arquivos)
--    GET /<codigo>/s   -> fluxo continuo de quadros (blocos que mudaram, zlib)
--    qualquer outra coisa -> 404. Nada e lido do cartao SD.
--  - Aceita so enderecos da rede local (privados) e Host numerico (IP).
--  - O codigo muda a cada transmissao; o navegador nao envia comandos.
--  - Cliente lento: os quadros dele sao descartados e ele recebe um quadro
--    completo quando alcancar (a imagem nunca fica corrompida).
--  Mensagens do fluxo: 1 byte tipo ('F' quadro, 'K' sinal de vida,
--  'E' encerrado) + u32 big-endian tamanho + dados.
-- =============================================================================
local socket = require("socket")
require("love.timer")
require("love.image")
require("love.data")
local Codec = require("lib.tilecodec")

local cfg = ...
local CTL = love.thread.getChannel(cfg.ctl)
local OUT = love.thread.getChannel(cfg.out)
local FR = love.thread.getChannel(cfg.frames)
local TOKEN = cfg.token
local W, H = cfg.w, cfg.h
local MAX_VIEWERS = 3
local MAX_PENDING = 8
local REQ_TIMEOUT = 5
local QUEUE_LIMIT = 1536 * 1024

local function msg(kind, data)
  local n = #data
  return kind .. string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) .. data
end

local function private_ip(ip)
  if not ip then return false end
  local a, b = ip:match("^(%d+)%.(%d+)%.%d+%.%d+$")
  a, b = tonumber(a), tonumber(b)
  if not a then return false end
  return a == 10 or a == 127 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) or (a == 169 and b == 254)
end

local server, err = socket.bind("*", cfg.port)
if not server then
  OUT:push({ t = "error", code = tostring(err):find("in use") and "port_in_use" or "bind", detail = tostring(err) })
  return
end
server:settimeout(0)
OUT:push({ t = "started", port = cfg.port })

local codec = Codec.new(W, H)
local pending = {}   -- conexoes lendo o pedido
local viewers = {}   -- conexoes recebendo o fluxo
local sent_bytes, frames_out, frames_in = 0, 0, 0
local last_stats, last_alive = love.timer.getTime(), love.timer.getTime()

local function close(c) pcall(c.sock.close, c.sock) end

local function respond(status, ctype, body, extra)
  local h = "HTTP/1.1 " .. status .. "\r\nContent-Type: " .. ctype .. "\r\nCache-Control: no-store\r\n"
    .. "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\n"
    .. (extra or "")
  if body then h = h .. "Content-Length: " .. #body .. "\r\nConnection: close\r\n\r\n" .. body
  else h = h .. "Connection: close\r\n\r\n" end
  return h
end

local PAGE_HEADERS = "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'\r\n"

local function enqueue(v, data)
  v.q[#v.q + 1] = data
  v.qbytes = v.qbytes + #data
  if v.qbytes > QUEUE_LIMIT then
    -- cliente lento: mantem so a mensagem que ja comecou a ser enviada
    local keep = v.off > 0 and v.q[1] or nil
    v.q = { keep }
    v.qbytes = keep and #keep or 0
    v.need_key = true
  end
end

local function handle_request(c)
  local head = c.buf
  local method, path = head:match("^(%u+) (%S+) HTTP/1%.[01]\r\n")
  local host = head:match("\r\n[Hh][Oo][Ss][Tt]:%s*([^\r\n]+)")
  -- Host precisa ser um IP (protege contra paginas de fora apontando um nome para o console)
  if not method or not host or not host:match("^%d+%.%d+%.%d+%.%d+:?%d*$") then
    c.sock:send(respond("400 Bad Request", "text/plain; charset=utf-8", "400\n")); close(c); return
  end
  if method ~= "GET" then
    c.sock:send(respond("405 Method Not Allowed", "text/plain; charset=utf-8", "405\n", "Allow: GET\r\n")); close(c); return
  end
  path = path:gsub("%?.*$", "")
  if path == "/" .. TOKEN or path == "/" .. TOKEN .. "/" then
    c.sock:settimeout(1)
    c.sock:send(respond("200 OK", "text/html; charset=utf-8", cfg.page, PAGE_HEADERS))
    close(c); return
  end
  if path == "/" .. TOKEN .. "/s" then
    if #viewers >= MAX_VIEWERS then
      c.sock:send(respond("503 Service Unavailable", "text/plain; charset=utf-8", "busy\n")); close(c); return
    end
    local v = { sock = c.sock, peer = c.peer, q = {}, qbytes = 0, off = 0, need_key = true }
    enqueue(v, respond("200 OK", "application/octet-stream", nil))
    v.need_key = true
    viewers[#viewers + 1] = v
    OUT:push({ t = "viewers", n = #viewers, peer = c.peer })
    return
  end
  if path == "/" then
    c.sock:send(respond("200 OK", "text/html; charset=utf-8", cfg.page_root, PAGE_HEADERS)); close(c); return
  end
  c.sock:send(respond("404 Not Found", "text/plain; charset=utf-8", "404\n")); close(c)
end

local function remove_viewer(i)
  close(viewers[i])
  table.remove(viewers, i)
  OUT:push({ t = "viewers", n = #viewers })
end

local running = true
while running do
  local busy = false
  -- controle
  local m = CTL:pop()
  while m do
    if m == "stop" or (type(m) == "table" and m.t == "stop") then running = false end
    m = CTL:pop()
  end
  if not running then break end

  -- novos quadros (o ultimo da fila)
  local img = FR:pop()
  if img then
    busy = true
    frames_in = frames_in + 1
    local px, keep = Codec.pixels(img)
    local any = #viewers > 0
    local payload = codec:diff(px, not any)
    keep = nil   -- (mantinha viva a copia dos pixels durante a comparacao)
    img:release()
    if payload then
      local z = msg("F", love.data.compress("string", "zlib", payload, 1))
      for _, v in ipairs(viewers) do
        if not v.need_key then enqueue(v, z) end
      end
      frames_out = frames_out + 1
    end
  end

  -- conexoes novas
  for _ = 1, 4 do
    local s = server:accept()
    if not s then break end
    busy = true
    s:settimeout(0)
    local peer = s:getpeername()
    if not private_ip(peer) or #pending >= MAX_PENDING then
      s:close()
    else
      pending[#pending + 1] = { sock = s, peer = peer, buf = "", t0 = love.timer.getTime() }
    end
  end

  -- pedidos em leitura
  local now = love.timer.getTime()
  for i = #pending, 1, -1 do
    local c = pending[i]
    local data, e, part = c.sock:receive(2048)
    data = data or part
    if data and #data > 0 then c.buf = c.buf .. data; busy = true end
    if c.buf:find("\r\n\r\n", 1, true) then
      table.remove(pending, i)
      handle_request(c)
    elseif e == "closed" or #c.buf > 8192 or now - c.t0 > REQ_TIMEOUT then
      table.remove(pending, i)
      close(c)
    end
  end

  -- sinal de vida (detecta navegador fechado)
  if now - last_alive > 2 then
    last_alive = now
    for _, v in ipairs(viewers) do if #v.q == 0 then enqueue(v, msg("K", "")) end end
  end

  -- envio
  for i = #viewers, 1, -1 do
    local v = viewers[i]
    if #v.q == 0 and v.need_key and codec.has then
      v.need_key = false
      local kf = codec:keyframe()
      if kf then enqueue(v, msg("F", love.data.compress("string", "zlib", kf, 1))) end
    end
    local dead = false
    local loops = 0
    while #v.q > 0 and loops < 8 do
      loops = loops + 1
      local data = v.q[1]
      local last, e, lastpart = v.sock:send(data, v.off + 1)
      local upto = last or lastpart or v.off
      if upto > v.off then sent_bytes = sent_bytes + (upto - v.off); busy = true end
      if upto >= #data then
        table.remove(v.q, 1)
        v.qbytes = v.qbytes - #data
        v.off = 0
      else
        v.off = upto
        if e == "closed" then dead = true end
        break
      end
    end
    -- leitura so para perceber que o navegador fechou (nada do que ele envia e usado)
    local _, e2 = v.sock:receive(64)
    if e2 == "closed" then dead = true end
    if dead then remove_viewer(i) end
  end

  if now - last_stats >= 1 then
    OUT:push({ t = "stats", viewers = #viewers, kbps = sent_bytes * 8 / 1000 / (now - last_stats),
      fps = frames_in / (now - last_stats) })
    sent_bytes, frames_in, frames_out = 0, 0, 0
    last_stats = now
  end

  if not busy then
    -- espera curta por comando ou quadro novo
    love.timer.sleep(0.008)
  end
end

-- encerramento: avisa os navegadores e fecha tudo
for _, v in ipairs(viewers) do
  pcall(function()
    v.sock:settimeout(0.3)
    if v.off > 0 and v.q[1] then v.sock:send(v.q[1], v.off + 1) end
    v.sock:send(msg("E", ""))
  end)
  close(v)
end
for _, c in ipairs(pending) do close(c) end
server:close()
local img = FR:pop()
while img do img:release(); img = FR:pop() end
OUT:push({ t = "stopped" })
