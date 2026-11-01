-- =============================================================================
--  Configuracoes > Servidor FTP
--  Esquerda: acoes e campos | Direita: estado real, endereco e QR Code
--  Y mostra/oculta a senha. Nada inicia sozinho: so com INICIAR.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Ftp = require("core.ftp")
local Net = require("core.net")
local lg = love.graphics

local S = {}
-- painel com posicoes fixas e muita informacao: texto sempre no tamanho padrao
-- (Configuracoes > Aparencia > Tamanho do texto nao se aplica a esta tela)
S.fixed_text = true

local ITEMS = {
  { id = "start", label = L("INICIAR") },
  { id = "stop", label = L("PARAR") },
  { id = "test", label = L("TESTAR CONEXÃO") },
  { id = "port", label = L("Porta") },
  { id = "user", label = L("Usuário") },
  { id = "pass", label = L("Senha") },
  { id = "save", label = L("SALVAR CONFIGURAÇÕES") },
  { id = "activity", label = L("Atividade FTP") },
  { id = "history", label = L("Histórico FTP") },
  { id = "phone", label = L("Conectar pelo celular") },
  { id = "pc", label = L("Conectar pelo computador") },
}

function S:enter()
  Ftp.load()
  self.sel = 1
  self.reveal = false
  self.draft = { port = Ftp.cfg.port, user = Ftp.cfg.user, pass = Ftp.cfg.pass }
  self.qr, self.qr_for = nil, nil
  Net.invalidate()
end

function S:dirty()
  local d, c = self.draft, Ftp.cfg
  return d.port ~= c.port or d.user ~= c.user or d.pass ~= c.pass
end

function S:update()
  self.net = Net.current() or Net.get(3)
  -- QR Code so com o endereco (nunca a senha); refeito quando IP/porta mudam
  local addr = self.net.connected and ("ftp://" .. self.net.ip .. ":" .. Ftp.cfg.port) or nil
  if addr ~= self.qr_for then
    self.qr_for = addr
    self.qr = nil
    if addr then
      local ok, qrlib = pcall(require, "lib.qrencode")
      if ok then
        local okq, tab = qrlib.qrcode(addr)
        if okq and type(tab) == "table" then self.qr = tab end
      end
    end
  end
end

local function state_info()
  local st = Ftp.state
  if st == "on" then return L("ATIVADO"), T.c.green
  elseif st == "starting" then return L("INICIANDO..."), T.c.yellow
  elseif st == "stopping" then return L("PARANDO..."), T.c.yellow
  end
  return L("DESATIVADO"), T.c.red
end

local function value_of(self, id)
  local d = self.draft
  if id == "port" then return tostring(d.port)
  elseif id == "user" then return d.user
  elseif id == "pass" then return self.reveal and d.pass or string.rep("*", #d.pass)
  end
end

function S:draw()
  local lbl, col = state_info()
  G.header(L("Servidor FTP"), L("Somente rede local"))
  -- lista de acoes
  local x, y, w = 12, 50, 250
  local rh = 32
  for i, it in ipairs(ITEMS) do
    local on = i == self.sel
    local disabled = (it.id == "start" and Ftp.running()) or (it.id == "stop" and not Ftp.running())
      or (it.id == "test" and Ftp.state ~= "on")
    G.rect(x, y, w, rh - 3, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(x, y, w, rh - 3, T.c.accent, 5, 2); G.rect(x, y + 6, 3, rh - 15, T.c.accent, 1) end
    local tc = disabled and T.c.faint or (on and T.c.text or T.c.dim)
    local v = value_of(self, it.id)
    if v then
      G.text(T.f.small, it.label, x + 12, y + 8, T.c.faint)
      local changed = (it.id == "port" and self.draft.port ~= Ftp.cfg.port) or (it.id == "user" and self.draft.user ~= Ftp.cfg.user)
        or (it.id == "pass" and self.draft.pass ~= Ftp.cfg.pass)
      local vx = math.max(76, T.f.small:getWidth(it.label) + 20)
      G.text_fit(T.f.bodyb, v, x + vx, y + 6, w - vx - 12, changed and T.c.yellow or T.c.text)
    else
      local f = (it.id == "start" or it.id == "stop" or it.id == "test" or it.id == "save") and T.f.pix8 or T.f.bodyb
      local ty = f == T.f.pix8 and y + 11 or y + 6
      local label = it.label
      if it.id == "save" and self:dirty() then label = label .. " *" end
      G.text(f, U.upper(label), x + 12, ty, it.id == "save" and self:dirty() and T.c.yellow or tc)
    end
    y = y + rh
    if it.id == "test" or it.id == "save" then y = y + 4 end
  end

  -- painel de estado
  local px, py, pw, ph = 274, 50, T.W - 286, 390
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  G.rect(px, py, pw, 4, col, 2)
  G.text(T.f.pix8, L("STATUS"), px + 14, py + 16, T.c.faint)
  G.tag(lbl, px + 80, py + 10, col, T.c.bg0, T.f.pix8)
  local cy = py + 40
  local function row(k, v, c)
    G.text_fit(T.f.small, k, px + 14, cy, 92, T.c.faint)
    G.text_fit(T.f.bodyb, v, px + 112, cy - 2, pw - 126, c or T.c.text)
    cy = cy + 21
  end
  local net = self.net or Net.get(3)
  if net.connected then
    row(L("IP do console"), net.ip, T.c.accent2)
    row(L("Rede"), (net.wireless and "Wi-Fi" or L("Cabo/outra")) .. " (" .. tostring(net.iface) .. ")")
  else
    row(L("IP do console"), L("IP INDISPONÍVEL"), T.c.red)
    row(L("Rede"), L("DESCONECTADO — ligue o Wi-Fi"), T.c.red)
  end
  row(L("Porta"), tostring(Ftp.cfg.port))
  row(L("Usuário"), Ftp.cfg.user)
  row(L("Senha"), self.reveal and Ftp.cfg.pass or string.rep("*", #Ftp.cfg.pass) .. L("   (Y mostra)"))
  row(L("Clientes"), Ftp.state == "on" and (Ftp.clients .. L(" conectado(s)")) or "—")
  local act = Ftp.active_count()
  row(L("Transferências"), act > 0 and (act .. L(" em andamento")) or L("nenhuma agora"), act > 0 and T.c.yellow or T.c.text)
  row(L("Pasta raiz"), Ftp.root or (Ftp.detect_root() or L("não encontrada")))

  -- endereco + QR
  cy = cy + 4
  G.rect(px + 12, cy, pw - 24, 1, T.c.line)
  cy = cy + 8
  if net.connected then
    local addr = "ftp://" .. net.ip .. ":" .. Ftp.cfg.port
    local qr = self.qr
    local size = 0
    if qr then
      local n = #qr
      local m = math.max(1, math.floor(112 / (n + 8)))
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
    local tx = px + 14 + size + 14
    local tw = px + pw - 14 - tx
    G.text(T.f.small, L("Endereço"), tx, cy, T.c.faint)
    G.text_fit(T.f.bodyb, addr, tx, cy + 16, tw, T.c.accent2)
    G.text(T.f.small, L("O QR Code tem só o endereço. Usuário e senha são digitados no aparelho."), tx, cy + 40, T.c.dim, "left", tw)
  else
    G.text(T.f.small, L("Sem rede: conecte o R36S ao Wi-Fi para ver o endereço e o QR Code."), px + 14, cy, T.c.dim, "left", pw - 28)
  end
  -- aviso de seguranca
  local warn = L("FTP não criptografa senha nem arquivos: use apenas na sua rede de casa e pare o servidor ao terminar.")
  local wl = #G.wrap(T.f.small, warn, pw - 28)
  G.text(T.f.small, warn, px + 14, py + ph - 8 - wl * T.f.small:getHeight(), T.c.orange, "left", pw - 28)

  G.hints({ { "dpad", L("Navegar") }, { "a", L("Selecionar") }, { "y", self.reveal and L("Ocultar senha") or L("Mostrar senha") }, { "b", L("Voltar") } })
end

-- ---------------------------------------------------------------------------
local function edit_port(self)
  App.push("textinput", {
    title = L("Porta do FTP"), label = L("Porta (1024 a 65535; padrão 2121):"), value = tostring(self.draft.port),
    mode = "digits", max = 5,
    validate = function(v)
      local ok, why = Ftp.valid_port(v)
      if not ok then return false, why end
      if tonumber(v) ~= Ftp.cfg.port or not Ftp.running() then
        if not Ftp.port_free(v) then return false, L("A porta ") .. v .. L(" já está em uso por outro programa.") end
      end
      return true
    end,
    on_ok = function(v) self.draft.port = tonumber(v) end,
  })
end

local function edit_user(self)
  App.push("textinput", {
    title = L("Usuário do FTP"), label = L("Usuário (mín. 3 caracteres):"), value = self.draft.user, max = 32,
    validate = Ftp.valid_user,
    on_ok = function(v) self.draft.user = v end,
  })
end

local function edit_pass(self)
  App.push("textinput", {
    title = L("Senha do FTP"), label = L("Nova senha (mín. 6 caracteres):"), value = "", secret = true, max = 64,
    hint = L("Anote a senha: ela será pedida no celular/computador."),
    validate = Ftp.valid_pass,
    on_ok = function(first)
      App.push("textinput", {
        title = L("Confirmar senha"), label = L("Digite a mesma senha de novo:"), value = "", secret = true, max = 64,
        validate = function(v) if v ~= first then return false, L("As senhas não conferem.") end return true end,
        on_ok = function() self.draft.pass = first; App.toast(L("Senha alterada. Use SALVAR CONFIGURAÇÕES."), "info") end,
      })
    end,
  })
end

local function save(self)
  if not self:dirty() then App.toast(L("Nada para salvar."), "info"); return end
  local d = self.draft
  local ok, why = Ftp.valid_port(d.port)
  if ok then ok, why = Ftp.valid_user(d.user) end
  if ok then ok, why = Ftp.valid_pass(d.pass) end
  if not ok then App.toast(why, "error"); return end
  local function apply(restart)
    Ftp.set_config(d.port, d.user, d.pass)
    if restart then Ftp.restart(); App.toast(L("Configurações salvas. Reiniciando o servidor..."), "ok")
    else App.toast(L("Configurações salvas."), "ok") end
  end
  if Ftp.running() then
    App.show_dialog({
      title = L("Reiniciar o servidor?"), kind = "warn",
      body = L("O servidor FTP está ligado. Para usar a nova configuração ele precisa reiniciar: clientes conectados")
        .. L(" e transferências em andamento serão interrompidos."),
      buttons = { { label = L("SALVAR E REINICIAR"), fn = function() apply(true) end }, { label = "VOLTAR" } },
      sel = 2,
    })
  else
    apply(false)
  end
end

function S:action(act)
  local id = ITEMS[self.sel].id
  if act == "up" then self.sel = (self.sel - 2) % #ITEMS + 1
  elseif act == "down" then self.sel = self.sel % #ITEMS + 1
  elseif act == "y" then self.reveal = not self.reveal
  elseif act == "b" then
    if self:dirty() then
      App.show_dialog({ title = L("Alterações não salvas"), kind = "warn",
        body = L("Você mudou porta, usuário ou senha e não salvou. Descartar as alterações?"),
        buttons = { { label = L("DESCARTAR"), fn = function() App.pop() end }, { label = "VOLTAR" } }, sel = 2 })
    else
      App.pop()
    end
  elseif act == "a" then
    if id == "start" then
      if Ftp.running() then App.toast(L("O servidor já está ligado."), "info"); return end
      if self:dirty() then App.toast(L("Salve ou descarte as alterações antes de iniciar."), "warn"); return end
      local ok, why = Ftp.start()
      if not ok then App.show_dialog({ title = L("Não foi possível iniciar"), kind = "error", body = why }) end
    elseif id == "stop" then
      if not Ftp.running() then App.toast(L("O servidor já está desligado."), "info"); return end
      local n = Ftp.active_count()
      if n > 0 then
        App.show_dialog({ title = L("Parar o servidor?"), kind = "warn",
          body = n .. L(" transferência(s) em andamento serão interrompidas. Arquivos recebidos pela metade são descartados."),
          buttons = { { label = L("PARAR"), fn = Ftp.stop }, { label = "VOLTAR" } }, sel = 2 })
      else
        Ftp.stop()
      end
    elseif id == "test" then
      local net = Net.status()
      local ok, msg = Ftp.self_test(net.connected and net.ip or nil)
      App.show_dialog({ title = ok and L("Conexão OK") or L("Teste falhou"), kind = ok and "ok" or "error",
        body = msg .. (ok and L("\n\nEste teste é feito pelo próprio console. Se o celular/computador não conectar, confira se ele está na MESMA rede Wi-Fi.") or "") })
    elseif id == "port" then edit_port(self)
    elseif id == "user" then edit_user(self)
    elseif id == "pass" then edit_pass(self)
    elseif id == "save" then save(self)
    elseif id == "activity" then App.push("ftp_activity", { tab = 1 })
    elseif id == "history" then App.push("ftp_activity", { tab = 2 })
    elseif id == "phone" then App.push("ftp_help", { tab = 1 })
    elseif id == "pc" then App.push("ftp_help", { tab = 2 })
    end
  end
end

return S
