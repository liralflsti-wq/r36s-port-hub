-- =============================================================================
--  R36S PORT HUB - gravacao da tela do hub (thread)
--
--  Dois modos, escolhidos pelo que existe no console:
--   - "mp4": quadros RGBA enviados ao ffmpeg por um pipe (H.264 ou MPEG-4).
--            Ritmo constante: o ultimo quadro e repetido enquanto a tela nao muda.
--   - "r36": arquivo proprio leve (.r36rec), so com os blocos que mudaram
--            e o tempo de cada quadro. Converte para video no navegador do PC
--            (converter_gravacao.html, na pasta das gravacoes).
--  Pausa: o tempo pausado nao entra no video.
-- =============================================================================
require("love.timer")
require("love.image")
require("love.data")
local Codec = require("lib.tilecodec")

-- se o ffmpeg fechar no meio, escrever no pipe nao pode derrubar o app (SIGPIPE):
-- o LuaSocket ignora o sinal ao carregar; o FFI cobre o caso sem LuaSocket
if not pcall(require, "socket") then
  pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, "typedef void (*porthub_sighandler_t)(int); porthub_sighandler_t signal(int, porthub_sighandler_t);")
    ffi.C.signal(13, ffi.cast("porthub_sighandler_t", 1))
  end)
end

local cfg = ...
local CTL = love.thread.getChannel(cfg.ctl)
local OUT = love.thread.getChannel(cfg.out)
local FR = love.thread.getChannel(cfg.frames)
local W, H, FPS = cfg.w, cfg.h, cfg.fps

local function u32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function fsize(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local s = f:seek("end") or 0
  f:close()
  return s
end

local f, ferr
if cfg.mode == "mp4" then
  f, ferr = io.popen(cfg.cmd, "w")
else
  f, ferr = io.open(cfg.path, "wb")
  if f then
    f:write("R36REC1\n", string.format('{"w":%d,"h":%d,"ts":%d,"fps":%d}\n', W, H, Codec.TS, FPS))
  end
end
if not f then
  OUT:push({ t = "error", detail = tostring(ferr) })
  return
end
OUT:push({ t = "started" })

local codec = cfg.mode == "r36" and Codec.new(W, H) or nil
local paused = false
local active = 0              -- segundos gravados (sem as pausas)
local last_t = love.timer.getTime()
local written = 0             -- quadros entregues ao ffmpeg
local raw = nil               -- ultimo quadro (RGBA) para o ffmpeg
local bytes = 0               -- modo r36: bytes escritos
local dropped = 0
local got = 0                 -- quadros recebidos do hub
local failed = nil
local last_stats = 0

local function write(data)
  local ok, e = f:write(data)
  if not ok then failed = tostring(e or "write") end
  return ok
end

local running = true
while running and not failed do
  local m = CTL:pop()
  while m do
    if m == "pause" then paused = true
    elseif m == "resume" then paused = false
    elseif m == "stop" then running = false end
    m = CTL:pop()
  end
  local now = love.timer.getTime()
  if not paused then active = active + (now - last_t) end
  last_t = now

  -- quadro novo (descarta os mais antigos, se houver mais de um)
  local img = FR:pop()
  if img then
    local nxt = FR:pop()
    while nxt do img:release(); img = nxt; nxt = FR:pop() end
  end
  if img then
    got = got + 1
    if not paused then
      if codec then
        local px, keep = Codec.pixels(img)
        local payload = codec:diff(px)
        keep = nil   -- (mantinha viva a copia dos pixels durante a comparacao)
        if payload then
          local z = love.data.compress("string", "zlib", payload, 3)
          local rec = u32(math.floor(active * 1000)) .. u32(#z) .. z
          if write(rec) then bytes = bytes + #rec end
        end
      else
        raw = img:getString()
      end
    end
    img:release()
  end

  -- ffmpeg: ritmo constante de quadros
  if not codec and raw and not paused then
    local due = math.floor(active * FPS)
    if due - written > FPS * 2 then
      -- o codificador nao esta dando conta: pula quadros em vez de acumular atraso
      dropped = dropped + (due - written - 1)
      written = due - 1
    end
    while written < due and not failed do
      write(raw)
      written = written + 1
    end
  end

  if now - last_stats >= 0.5 then
    last_stats = now
    OUT:push({ t = "stats", dur = active, size = codec and bytes or fsize(cfg.path), dropped = dropped, paused = paused })
  end
  love.timer.sleep(codec and 0.01 or 0.005)
end

local img = FR:pop()
while img do img:release(); img = FR:pop() end
local ok_close = f:close()
local size = fsize(cfg.path)
local errtail
if cfg.log then
  local lf = io.open(cfg.log, "r")
  if lf then errtail = (lf:read("*a") or ""):sub(-400); lf:close() end
  if errtail and not errtail:find("%S") then errtail = nil end
end
OUT:push({ t = "done", dur = active, size = size, dropped = dropped, error = failed, frames = got, written = written,
  log = errtail, ok = not failed and size > 0, close = tostring(ok_close) })
