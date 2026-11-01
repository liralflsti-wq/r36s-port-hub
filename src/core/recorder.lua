-- =============================================================================
--  Gravacao da interface do hub (thread principal)
--  Formato: MP4 quando o ffmpeg do console tem um codificador adequado;
--  senao, o formato leve .r36rec (convertido para video no navegador do PC).
--  Nunca inicia sozinha e nunca apaga gravacoes.
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")
local T = require("ui.theme")
local Prefs = require("core.prefs")
local Cap = require("core.screencap")
local Rec = require("core.recordings")

local R = {
  state = "off",      -- off | starting | on | paused | stopping
  thread = nil,
  dur = 0, size = 0, dropped = 0,
  file = nil, path = nil,
  mode = nil,         -- "mp4" | "r36"
  probe = nil,        -- resultado da verificacao do ffmpeg
  last_error = nil,
}

local CTL, OUT, FRAMES = "hub_rec_ctl", "hub_rec_out", "hub_rec_frames"
R.FPS_CHOICES = { 10, 15 }
local MIN_FREE = 64 * 1024 * 1024      -- nao comeca com menos que isto livre
local STOP_FREE = 24 * 1024 * 1024     -- finaliza sozinha (sem apagar) abaixo disto

function R.fps()
  local f = tonumber(Prefs.get("rec_fps") or "")
  for _, c in ipairs(R.FPS_CHOICES) do if c == f then return f end end
  return 10
end

function R.set_fps(f) Prefs.set("rec_fps", tostring(f)) end

--- o ffmpeg existe? qual codificador usar? (uma vez por abertura do app)
function R.detect()
  if R.probe then return R.probe end
  local p = { ffmpeg = nil, encoder = nil }
  local path = os.getenv("PORTHUB_REC_NOFFMPEG") and "" or U.trim(U.capture("command -v ffmpeg 2>/dev/null") or "")
  if path ~= "" then
    p.ffmpeg = path
    local enc = U.capture(U.shq(path) .. " -hide_banner -encoders 2>/dev/null") or ""
    if enc:find("%s libx264%s") then p.encoder = "libx264"
    elseif enc:find("%s mpeg4%s") then p.encoder = "mpeg4" end
  end
  R.probe = p
  U.log("Gravação: ffmpeg", tostring(p.ffmpeg), "codificador", tostring(p.encoder))
  return p
end

function R.format_label()
  local p = R.detect()
  if p.encoder == "libx264" then return L("MP4 (H.264)") end
  if p.encoder == "mpeg4" then return L("MP4 (MPEG-4)") end
  return L(".r36rec (converter no PC)")
end

function R.running() return R.state ~= "off" end
function R.recording() return R.state == "on" or R.state == "paused" end

local function ffmpeg_cmd(p, out, log, fps)
  local enc
  if p.encoder == "libx264" then
    enc = "-c:v libx264 -preset ultrafast -tune zerolatency -crf 24"
  else
    enc = "-c:v mpeg4 -q:v 4"
  end
  return U.shq(p.ffmpeg) .. " -hide_banner -loglevel error -y -f rawvideo -pix_fmt rgba -s " .. T.W .. "x" .. T.H
    .. " -r " .. fps .. " -i - -an " .. enc .. " -pix_fmt yuv420p -g " .. (fps * 2)
    .. " -movflags +frag_keyframe+empty_moov+default_base_moof " .. U.shq(out) .. " 2>" .. U.shq(log)
end

function R.start()
  if R.thread and R.thread:isRunning() then return false, L("A gravação já está em andamento.") end
  if not Rec.ensure_dir() then return false, L("Não foi possível criar a pasta das gravações no cartão SD.") end
  local free = U.free_space(Rec.DIR)
  if free and free < MIN_FREE then
    return false, L("Pouco espaço livre no cartão SD (menos de 64 MB). Libere espaço antes de gravar.")
  end
  local p = R.detect()
  local fps = R.fps()
  local mode = p.encoder and "mp4" or "r36"
  local name = Rec.new_name(mode == "mp4" and "mp4" or "r36rec")
  local path = Rec.DIR .. "/" .. name
  local log = C.TMP_DIR .. "/ffmpeg_gravacao.log"
  os.execute("mkdir -p " .. U.shq(C.TMP_DIR) .. " 2>/dev/null; rm -f " .. U.shq(log))
  local ctl, out, fr = love.thread.getChannel(CTL), love.thread.getChannel(OUT), love.thread.getChannel(FRAMES)
  ctl:clear(); out:clear()
  local img = fr:pop()
  while img do img:release(); img = fr:pop() end
  R.ctl, R.out, R.frames = ctl, out, fr
  R.file, R.path, R.mode = name, path, mode
  R.dur, R.size, R.dropped, R.last_error = 0, 0, 0, nil
  R.rec_fps = fps
  R.thread = love.thread.newThread("threads/rec_thread.lua")
  R.thread:start({ ctl = CTL, out = OUT, frames = FRAMES, w = T.W, h = T.H, fps = fps, mode = mode, path = path,
    cmd = mode == "mp4" and ffmpeg_cmd(p, path, log, fps) or nil, log = mode == "mp4" and log or nil })
  R.state = "starting"
  U.log("Gravação: iniciando", name, mode, fps .. " fps")
  return true
end

function R.pause()
  if R.state == "on" then R.ctl:push("pause"); R.state = "paused" end
end

function R.resume()
  if R.state == "paused" then R.ctl:push("resume"); R.state = "on" end
end

function R.stop()
  Cap.release("rec")
  if R.thread and R.thread:isRunning() then
    R.ctl:push("stop")
    R.state = "stopping"
  else
    R.state = "off"
  end
end

--- finaliza ao sair do app (espera o MP4 ser fechado; no maximo ~6 s)
function R.stop_wait()
  R.stop()
  local t0 = love.timer.getTime()
  while R.thread and R.thread:isRunning() and love.timer.getTime() - t0 < 6 do love.timer.sleep(0.02) end
  R.update()
  R.state = "off"
end

local function notify(text, kind) if R.on_notify then R.on_notify(text, kind) end end

local free_t = 0
function R.update()
  local th = R.thread
  if th then
    local e = th:getError()
    if e then
      U.log("Gravação: erro na thread:", e)
      R.thread = nil
      R.state = "off"
      Cap.release("rec")
      R.last_error = L("Erro interno da gravação.")
      notify(L("A gravação parou por um erro interno. O que já foi gravado continua no cartão."), "error")
    end
  end
  if not R.out then return end
  local m = R.out:pop()
  while m do
    if m.t == "started" then
      R.state = "on"
      Cap.want("rec", R.rec_fps, R.frames, 2)
      notify(L("Gravação iniciada."), "ok")
    elseif m.t == "error" then
      R.state = "off"
      Cap.release("rec")
      R.last_error = L("Não foi possível iniciar a gravação: ") .. tostring(m.detail)
      notify(R.last_error, "error")
    elseif m.t == "stats" then
      R.dur, R.size, R.dropped = m.dur, m.size, m.dropped
    elseif m.t == "done" then
      R.state = "off"
      Cap.release("rec")
      R.dur, R.size, R.dropped = m.dur, m.size, m.dropped
      Rec.remember(R.file, { dur = m.dur, fps = R.rec_fps, codec = R.mode == "mp4" and (R.probe and R.probe.encoder) or "r36rec" })
      if m.ok then
        R.last_error = nil
        notify(L("Gravação salva: ") .. R.file, "ok")
      else
        R.last_error = m.error and (L("Falha ao gravar: ") .. m.error) or (m.log and (L("O ffmpeg informou: ") .. m.log))
          or L("O arquivo da gravação ficou vazio.")
        U.log("Gravação: falha", tostring(m.error), tostring(m.log))
        notify(L("A gravação não foi concluída. Veja os detalhes na tela de transmissão e gravação."), "error")
      end
      if R.on_done then R.on_done(m) end
    end
    m = R.out:pop()
  end
  if R.state ~= "off" and R.thread and not R.thread:isRunning() and R.out:getCount() == 0 then
    R.state = "off"
    Cap.release("rec")
  end
  -- cartao quase cheio: finaliza (o arquivo fica salvo)
  if R.recording() then
    local now = love.timer.getTime()
    if now - free_t > 10 then
      free_t = now
      local free = U.free_space(Rec.DIR)
      if free and free < STOP_FREE then
        R.stop()
        notify(L("Cartão SD quase cheio: a gravação foi finalizada e salva."), "warn")
      end
    end
  end
end

return R
