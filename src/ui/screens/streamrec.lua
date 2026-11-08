-- =============================================================================
--  Configuracoes > Rede > Transmissao e gravacao
--  Esquerda: acoes | Direita: estado real da transmissao (IP, porta, endereco,
--  QR Code, computadores) e da gravacao (formato, duracao, tamanho, arquivo).
--  So a interface do hub e transmitida/gravada. Nada inicia sozinho.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Net = require("core.net")
local Stream = require("core.stream")
local Recorder = require("core.recorder")
local Rec = require("core.recordings")
local lg = love.graphics

local S = {}
-- painel com posicoes fixas e muita informacao: texto sempre no tamanho padrao
-- (Configuracoes > Aparencia > Tamanho do texto nao se aplica a esta tela)
S.fixed_text = true

-- G.tag traduz o texto; a largura usa o mesmo texto traduzido
local function I18N_tr(s) return require("lib.i18n").tr(s) end

local ITEMS = {
  { id = "s_start", label = L("INICIAR TRANSMISSÃO") },
  { id = "s_stop", label = L("ENCERRAR TRANSMISSÃO") },
  { id = "r_start", label = L("INICIAR GRAVAÇÃO") },
  { id = "r_pause", label = L("PAUSAR GRAVAÇÃO") },
  { id = "r_stop", label = L("FINALIZAR GRAVAÇÃO") },
  { id = "info", label = L("Informações da transmissão") },
  { id = "list", label = L("Gravações salvas") },
  { id = "folder", label = L("Abrir pasta das gravações") },
  { id = "s_fps", label = L("Quadros da transmissão") },
  { id = "r_fps", label = L("Quadros da gravação") },
}

function S:enter()
  self.sel = 1
  self.qr, self.qr_for = nil, nil
  self.probe_wait = 2      -- verifica o ffmpeg depois do primeiro quadro (sem travar a abertura)
  Net.invalidate()
end

function S:update()
  self.net = Net.current() or Net.get(3)
  if self.probe_wait then
    self.probe_wait = self.probe_wait - 1
    if self.probe_wait <= 0 then self.probe_wait = nil; Recorder.detect() end
  end
  local addr = Stream.address(self.net)
  if addr ~= self.qr_for then
    self.qr_for, self.qr = addr, nil
    if addr then
      local ok, qrlib = pcall(require, "lib.qrencode")
      if ok then
        local okq, tab = qrlib.qrcode(addr)
        if okq and type(tab) == "table" then self.qr = tab end
      end
    end
  end
end

local function stream_state()
  local st = Stream.state
  if st == "on" then return L("AO VIVO"), T.c.green
  elseif st == "starting" then return L("INICIANDO..."), T.c.yellow
  elseif st == "stopping" then return L("ENCERRANDO..."), T.c.yellow end
  return L("DESLIGADA"), T.c.red
end

local function rec_state()
  local st = Recorder.state
  if st == "on" then return L("GRAVANDO"), T.c.red
  elseif st == "paused" then return L("PAUSADA"), T.c.yellow
  elseif st == "starting" then return L("INICIANDO..."), T.c.yellow
  elseif st == "stopping" then return L("FINALIZANDO..."), T.c.yellow end
  return L("DESLIGADA"), T.c.dim
end

local function disabled(id)
  if id == "s_start" then return Stream.running() end
  if id == "s_stop" then return not Stream.running() end
  if id == "r_start" then return Recorder.running() end
  if id == "r_pause" then return not Recorder.recording() end
  if id == "r_stop" then return not Recorder.recording() end
  return false
end

local function item_label(it)
  if it.id == "r_pause" and Recorder.state == "paused" then return L("RETOMAR GRAVAÇÃO") end
  return it.label
end

local function item_value(it)
  if it.id == "s_fps" then return Stream.fps() .. " FPS" end
  if it.id == "r_fps" then return Recorder.fps() .. " FPS" end
end

function S:draw()
  G.header(L("Transmissão e gravação"), L("Somente rede local"))
  local x, y, w, rh = 12, 50, 250, 31
  for i, it in ipairs(ITEMS) do
    local on = i == self.sel
    local dis = disabled(it.id)
    G.rect(x, y, w, rh - 3, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(x, y, w, rh - 3, T.c.accent, 5, 2); G.rect(x, y + 6, 3, rh - 15, T.c.accent, 1) end
    local tc = dis and T.c.faint or (on and T.c.text or T.c.dim)
    local v = item_value(it)
    if v then
      local vw = T.f.bodyb:getWidth(v)
      G.text_fit(T.f.small, it.label, x + 12, y + 7, w - vw - 34, on and T.c.text or T.c.dim)
      G.text(T.f.bodyb, v, x + w - 12 - vw, y + 5, T.c.accent2)
    elseif i <= 5 then
      G.text_fit(T.f.pix8, U.upper(item_label(it)), x + 12, y + 10, w - 24, tc)
    else
      G.text_fit(T.f.bodyb, it.label, x + 12, y + 5, w - 24, tc)
    end
    y = y + rh
    if it.id == "s_stop" or it.id == "r_stop" or it.id == "folder" then y = y + 5 end
  end

  -- painel de estado
  local px, py, pw, ph = 274, 50, T.W - 286, 390
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  local slbl, scol = stream_state()
  G.rect(px, py, pw, 4, scol, 2)
  G.text(T.f.pix8, L("TRANSMISSÃO"), px + 14, py + 15, T.c.faint)
  G.tag(slbl, px + pw - 14 - (T.f.pix8:getWidth(I18N_tr(slbl)) + 12), py + 9, scol, T.c.bg0, T.f.pix8)
  local cy = py + 34
  local function row(k, v, c)
    G.text_fit(T.f.small, k, px + 14, cy, 98, T.c.faint)
    G.text_fit(T.f.bodyb, v, px + 118, cy - 2, pw - 132, c or T.c.text)
    cy = cy + 19
  end
  local net = self.net or Net.get(3)
  if net.connected then row(L("IP do console"), net.ip, T.c.accent2)
  else row(L("IP do console"), L("IP INDISPONÍVEL"), T.c.red) end
  row(L("Porta"), Stream.state == "on" and tostring(Stream.port) or "—")
  row(L("Computadores"), Stream.state == "on" and (Stream.viewers .. L(" assistindo")) or "—")
  row(L("Dados"), Stream.state == "on" and Stream.viewers > 0 and string.format("%.0f kbit/s", Stream.kbps) or "—")

  cy = cy + 2
  local addr = Stream.address(net)
  if addr then
    local size = 0
    local qr = self.qr
    if qr then
      local n = #qr
      local m = math.max(1, math.floor(92 / (n + 8)))
      size = (n + 8) * m
      local qx, qy = px + 14, cy
      lg.setColor(1, 1, 1, 1)
      lg.rectangle("fill", qx, qy, size, size)
      lg.setColor(0, 0, 0, 1)
      for ix = 1, n do
        for iy = 1, n do
          if qr[ix][iy] > 0 then lg.rectangle("fill", qx + (ix + 3) * m, qy + (iy + 3) * m, m, m) end
        end
      end
    end
    local tx = px + 14 + size + 12
    local tw = px + pw - 14 - tx
    G.text(T.f.small, L("Abra no navegador do computador:"), tx, cy, T.c.faint, "left", tw)
    G.text_fit(T.f.bodyb, addr, tx, cy + 18, tw, T.c.accent2)
    G.text(T.f.small, L("O código no fim muda a cada transmissão."), tx, cy + 42, T.c.dim, "left", tw)
    cy = cy + math.max(size, 74) + 6
  else
    local msg = net.connected and L("Use INICIAR TRANSMISSÃO para ver o endereço aqui.")
      or L("Sem rede: conecte o R36S ao Wi-Fi para transmitir.")
    if Stream.last_error and Stream.state == "off" then msg = Stream.last_error end
    G.text(T.f.small, msg, px + 14, cy, Stream.last_error and T.c.orange or T.c.dim, "left", pw - 28)
    cy = cy + 40
  end

  G.rect(px + 12, cy, pw - 24, 1, T.c.line)
  cy = cy + 8
  local rlbl, rcol = rec_state()
  G.text(T.f.pix8, L("GRAVAÇÃO"), px + 14, cy + 6, T.c.faint)
  G.tag(rlbl, px + pw - 14 - (T.f.pix8:getWidth(I18N_tr(rlbl)) + 12), cy, rcol, T.c.bg0, T.f.pix8)
  cy = cy + 26
  local probe = Recorder.probe
  row(L("Formato"), probe and Recorder.format_label() or L("Verificando..."))
  local active = Recorder.running()
  row(L("Duração"), active and Rec.format_dur(Recorder.dur) or "—", Recorder.state == "on" and T.c.red or nil)
  row(L("Tamanho"), active and (Recorder.size or 0) >= 1024 and U.format_bytes(Recorder.size) or (active and L("calculando...") or "—"))
  row(L("Arquivo"), (active or Recorder.file) and Recorder.file or "—")
  local note
  if Recorder.last_error and not active then note, rcol = Recorder.last_error, T.c.orange
  elseif active and (Recorder.dropped or 0) > 0 then note, rcol = L("O console não está dando conta de todos os quadros. Use menos quadros por segundo."), T.c.yellow
  elseif probe and not probe.encoder then note, rcol = L("Sem ffmpeg no console: grava em .r36rec. A página converter_gravacao.html, na pasta das gravações, transforma em vídeo no PC."), T.c.dim
  else note, rcol = L("Salvo em r36sporthub/gravacoes. Nada é apagado automaticamente."), T.c.dim end
  G.text(T.f.small, note, px + 14, cy + 2, rcol, "left", pw - 28)

  G.hints({ { "dpad", L("Navegar") }, { "a", L("Selecionar") }, { "b", L("Voltar") } })
end

-- ---------------------------------------------------------------------------
local function cycle(list, cur, dir)
  for i, v in ipairs(list) do
    if v == cur then return list[(i - 1 + dir) % #list + 1] end
  end
  return list[1]
end

local function show_info()
  local net = Net.status()
  local addr = Stream.address(net)
  local body
  if Stream.state == "on" and addr then
    body = L("Endereço: ") .. addr
      .. L("\nIP do console: ") .. tostring(net.ip) .. L("\nPorta: ") .. Stream.port
      .. L("\nComputadores assistindo: ") .. Stream.viewers .. L(" (máx. 3)")
      .. L("\nQuadros por segundo: ") .. Stream.fps()
      .. L("\n\nNo computador, conectado à MESMA rede Wi-Fi, abra o Firefox ou o Chromium e digite o endereço completo.")
      .. L(" A página só mostra a tela do hub: ela não controla o console e não dá acesso aos arquivos.")
      .. L(" Ao entrar num jogo o hub fecha e a transmissão termina.")
  else
    body = L("A transmissão está desligada.")
      .. L("\n\nUse INICIAR TRANSMISSÃO: o console mostra aqui o IP real, a porta e o endereço para abrir no navegador do computador.")
      .. L(" Funciona só na rede local, sem internet e sem programas extras no computador.")
  end
  App.show_dialog({ title = L("Informações da transmissão"), kind = "info", body = body })
end

local function start_rec()
  local function go()
    local ok, why = Recorder.start()
    if not ok then App.show_dialog({ title = L("Não foi possível gravar"), kind = "error", body = why }) end
  end
  local p = Recorder.detect()
  if not p.encoder then
    App.show_dialog({ title = L("Gravar sem MP4?"), kind = "warn",
      body = (p.ffmpeg and L("O ffmpeg do console não tem um codificador de vídeo compatível.")
          or L("Este console não tem o ffmpeg instalado, então o MP4 não está disponível."))
        .. L("\n\nA gravação será salva no formato leve .r36rec. Para ver ou transformar em vídeo, copie o arquivo para o PC")
        .. L(" e abra a página converter_gravacao.html (que fica na mesma pasta) no Firefox ou Chromium."),
      buttons = { { label = L("GRAVAR"), fn = go }, { label = "VOLTAR" } }, sel = 1 })
    return
  end
  go()
end

--- aviso ao escolher 30 FPS na gravacao
local function rec_fps_hint()
  if Recorder.fps() < 30 then return end
  if App.eco then
    App.toast(L("No modo econômico a tela do hub tem no máximo 20 quadros por segundo."), "info")
  else
    App.toast(L("30 FPS usa mais o processador. Se o vídeo ficar travado, use 15 FPS."), "info")
  end
end

function S:action(act)
  local it = ITEMS[self.sel]
  local id = it.id
  if act == "up" then self.sel = (self.sel - 2) % #ITEMS + 1
  elseif act == "down" then self.sel = self.sel % #ITEMS + 1
  elseif act == "b" then App.pop()
  elseif (act == "left" or act == "right") and (id == "s_fps" or id == "r_fps") then
    local dir = act == "left" and -1 or 1
    if id == "s_fps" then Stream.set_fps(cycle(Stream.FPS_CHOICES, Stream.fps(), dir))
    else
      if Recorder.running() then App.toast(L("Vale para a próxima gravação."), "info") end
      Recorder.set_fps(cycle(Recorder.FPS_CHOICES, Recorder.fps(), dir))
      rec_fps_hint()
    end
  elseif act == "a" then
    if disabled(id) then
      local why = {
        s_start = L("A transmissão já está ligada."), s_stop = L("A transmissão já está desligada."),
        r_start = L("A gravação já está em andamento."), r_pause = L("Nenhuma gravação em andamento."),
        r_stop = L("Nenhuma gravação em andamento."),
      }
      App.toast(why[id] or "", "info")
      return
    end
    if id == "s_start" then
      local ok, why = Stream.start()
      if not ok then App.show_dialog({ title = L("Não foi possível transmitir"), kind = "error", body = why }) end
    elseif id == "s_stop" then
      if Stream.viewers > 0 then
        App.show_dialog({ title = L("Encerrar a transmissão?"), kind = "warn",
          body = Stream.viewers .. L(" computador(es) assistindo agora vão parar de receber a imagem."),
          buttons = { { label = L("ENCERRAR"), fn = Stream.stop }, { label = "VOLTAR" } }, sel = 2 })
      else
        Stream.stop()
      end
    elseif id == "r_start" then start_rec()
    elseif id == "r_pause" then
      if Recorder.state == "paused" then Recorder.resume(); App.toast(L("Gravação retomada."), "info")
      else Recorder.pause(); App.toast(L("Gravação pausada."), "info") end
    elseif id == "r_stop" then Recorder.stop()
    elseif id == "info" then show_info()
    elseif id == "list" then App.push("recordings")
    elseif id == "folder" then
      if not Rec.ensure_dir() then App.toast(L("Não foi possível criar a pasta das gravações no cartão SD."), "error"); return end
      App.push("files", { path = Rec.DIR })
    elseif id == "s_fps" then Stream.set_fps(cycle(Stream.FPS_CHOICES, Stream.fps(), 1))
    elseif id == "r_fps" then
      if Recorder.running() then App.toast(L("Vale para a próxima gravação."), "info") end
      Recorder.set_fps(cycle(Recorder.FPS_CHOICES, Recorder.fps(), 1))
      rec_fps_hint()
    end
  end
end

return S
