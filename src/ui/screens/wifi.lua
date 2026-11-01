-- =============================================================================
--  Configuracoes > Rede e conectividade > Gerenciar Wi-Fi
--  Abas: REDES DISPONIVEIS | REDES SALVAS (L1/R1). Tudo pelo NetworkManager.
--  A: escolher | Y: pesquisar de novo | B: voltar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Icons = require("ui.icons")
local J = require("core.wifijob")
local Net = require("core.net")
local lg = love.graphics

local S = {}

local LIST_Y, ROW_H, VISIBLE = 156, 40, 7

-- ---------------------------------------------------------------------------
-- utilitarios compartilhados com a tela de conexao
local W = {}
S.W = W

function W.bars(sig)
  sig = sig or 0
  return sig >= 75 and 4 or (sig >= 50 and 3 or (sig >= 25 and 2 or 1))
end
function W.signal_label(sig)
  local b = W.bars(sig)
  return ({ L("Fraco"), L("Razoável"), L("Bom"), L("Excelente") })[b]
end
function W.draw_bars(x, y, sig, c, dim)
  local b = W.bars(sig)
  for i = 1, 4 do
    local h = 4 + i * 4
    G.rect(x + (i - 1) * 6, y + 16 - h, 4, h, i <= b and c or dim, 1)
  end
end
function W.security_label(sec)
  if not sec or sec == "" then return L("Aberta") end
  return L("Protegida") .. " (" .. sec .. ")"
end
function W.lock(x, y, c)
  G.color(c)
  lg.setLineWidth(2)
  lg.arc("line", "open", x + 5, y + 6, 4, math.pi, 2 * math.pi)
  lg.setLineWidth(1)
  lg.rectangle("fill", x, y + 6, 10, 8, 1, 1)
end
--- mensagem de cada estado de conexao
function W.state_text(state)
  local M = {
    connected = L("Conectado."),
    auth = L("Senha incorreta ou autenticação recusada."),
    unavailable = L("Rede indisponível."),
    timeout = L("Tempo limite excedido."),
    failed = L("Falha na conexão."),
    cancelled = L("Conexão cancelada."),
    permission = L("O sistema não permitiu a alteração da rede (sem permissão)."),
    enterprise = L("Redes corporativas (802.1X/EAP) não são suportadas por aqui."),
    wep = L("Redes WEP não são suportadas por aqui."),
    noadapter = L("Adaptador Wi-Fi não encontrado."),
  }
  return M[state] or M.failed
end
--- aviso antes de trocar de rede com download em andamento
function W.guard(fn)
  local Installer = require("core.installer")
  local Downloads = require("core.downloads")
  if Installer.busy() or Downloads.active() then
    App.show_dialog({ title = L("Download em andamento"), kind = "warn",
      body = L("Trocar ou desligar a rede pode interromper o download atual. Ele não é cancelado pelo hub, mas a conexão pode cair durante a troca.\n\nContinuar?"),
      buttons = { { label = L("CONTINUAR"), fn = fn }, { label = L("CANCELAR") } }, sel = 2 })
    return
  end
  fn()
end

-- ---------------------------------------------------------------------------
function S:enter()
  self.tab, self.sel, self.top = 1, 1, 0
  self.nets, self.saved = nil, nil
  self.status = J.last
  self:request("scan")
end

function S:resume()
  -- voltando da tela de conexao: atualiza estado, lista e salvas
  self:request(self.tab == 1 and "scan" or "saved")
end

function S:request(op, params)
  if self.job then self.pending = { op, params }; return end   -- um pedido por vez
  self.busy = op
  self.job = J.start(op, params)
end

function S:update()
  if not self.job then return end
  local r = J.poll(self.job)
  if not r then return end
  self.job, self.busy = nil, nil
  if self.pending then
    local p = self.pending
    self.pending = nil
    self:request(p[1], p[2])
  end
  if r.status then self.status = r.status end
  if r.error and not r.list and r.op ~= "status" then self.err = r.error end
  if r.op == "scan" then
    self.nets = r.list or self.nets
    if r.list then self.err = nil end
    if not self.saved then self:request("saved") end
  elseif r.op == "saved" or r.op == "forget" then
    self.saved = r.list or self.saved
    if r.op == "forget" then App.toast(r.ok and L("Rede esquecida.") or (L("Falha: ") .. tostring(r.detail)), r.ok and "ok" or "error") end
  elseif r.op == "radio" then
    if not r.ok then App.toast(L("Não foi possível alterar o Wi-Fi: ") .. tostring(r.detail), "error")
    elseif self.status and self.status.radio then self:request("scan")
    elseif self.status and self.status.radio == false then self.nets = {} end
    Net.invalidate()
  elseif r.op == "disconnect" then
    App.toast(r.ok and L("Desconectado.") or (L("Falha: ") .. tostring(r.detail)), r.ok and "ok" or "error")
    Net.invalidate()
    self:request("saved")
  elseif r.op == "reconnect" then
    local res = r.result or {}
    if res.ok then
      App.toast(L("Conectado.") .. (res.ip and ("  IP " .. res.ip) or ""), "ok")
    else
      App.toast(W.state_text(res.state), "error")
    end
    Net.invalidate()
    self:request("saved")
  end
end

-- itens navegaveis da aba atual
function S:items()
  local t = { { kind = "switch" } }
  if self.tab == 1 then
    t[#t + 1] = { kind = "scan" }
    for _, n in ipairs(self.nets or {}) do t[#t + 1] = { kind = "net", net = n } end
  else
    for _, s in ipairs(self.saved or {}) do t[#t + 1] = { kind = "saved", saved = s } end
  end
  return t
end

local function saved_for(self, ssid)
  for _, s in ipairs(self.saved or {}) do if s.ssid == ssid then return s end end
end

-- ---------------------------------------------------------------------------
function S:draw_unavailable(title, body)
  G.panel(12, 50, 640 - 24, 386, { bg = T.c.bg1 })
  G.text(T.f.pix16, title, 12, 120, T.c.orange, "center", 640 - 24)
  local y = 160
  for _, l in ipairs(G.wrap(T.f.small, body, 560)) do
    G.text(T.f.small, l, 40, y, T.c.dim); y = y + G.step(T.f.small, 16)
  end
end

function S:draw()
  local st = self.status
  G.header(L("Gerenciar Wi-Fi"), self.busy == "scan" and L("Pesquisando redes...") or "")
  if not st then
    self:draw_unavailable(L("VERIFICANDO..."), L("Consultando o gerenciador de rede do sistema..."))
    G.hints({ { "b", L("Voltar") } })
    return
  end
  if not st.nmcli then
    self:draw_unavailable(L("GERENCIADOR DE REDE NÃO ENCONTRADO"),
      L("O R36S PORT HUB usa o gerenciador de rede do próprio sistema (NetworkManager, comando nmcli), que não foi encontrado neste console.\n\nNo dArkOSRE, use a opção \"Wifi Toggle\" do sistema para instalar e ativar o Wi-Fi. Depois volte aqui."))
    G.hints({ { "b", L("Voltar") } })
    return
  end
  if st.nm_running == false then
    self:draw_unavailable(L("GERENCIADOR DE REDE PARADO"),
      L("O NetworkManager está instalado, mas não está em execução. Ative o Wi-Fi pela opção \"Wifi Toggle\" do sistema e volte aqui."))
    G.hints({ { "b", L("Voltar") } })
    return
  end

  local items = self:items()
  if self.sel > #items then self.sel = #items end
  local cur = items[self.sel]

  -- painel superior: interruptor do Wi-Fi + conexao atual
  local on = cur and cur.kind == "switch"
  G.panel(12, 50, 640 - 24, 68, { bg = on and T.c.bg3 or T.c.bg1, border = on and T.c.accent or T.c.line, lw = on and 2 or 1 })
  Icons.draw("set_network", 26, 62, st.connected and T.c.green or T.c.dim, 1)
  G.text(T.f.bodyb, "Wi-Fi", 60, 62, T.c.text)
  local radio = st.radio
  local lbl = (radio == nil) and L("INDISPONÍVEL") or (radio and L("ATIVADO") or L("DESATIVADO"))
  -- interruptor
  local sx, sy = 640 - 24 - 60, 60
  if radio ~= nil and st.iface then
    G.rect(sx, sy, 46, 22, radio and T.c.green or T.c.bg0, 11)
    G.frame(sx, sy, 46, 22, radio and T.c.green or T.c.line, 11)
    G.color(radio and T.c.bg0 or T.c.faint)
    lg.circle("fill", radio and (sx + 35) or (sx + 11), sy + 11, 8)
    G.text(T.f.pix8, lbl, sx - 10 - T.f.pix8:getWidth(I18N.tr(lbl)), sy + 7, radio and T.c.green or T.c.dim)
  else
    G.text(T.f.pix8, lbl, sx - 30, sy + 7, T.c.red)
  end
  local line
  if not st.iface then line, lbl = L("Adaptador Wi-Fi não encontrado. Conecte o adaptador USB e ative-o pelo \"Wifi Toggle\" do sistema."), T.c.red
  elseif st.connected then
    local sig = Net.signal(st.iface)
    line = L("Conectado a ") .. (st.connection or "?") .. "  •  IP " .. st.ip
      .. (sig and ("  •  " .. L("sinal ") .. sig.quality .. "%") or "") .. "  •  " .. st.iface
    lbl = T.c.green
  else line, lbl = L("Não conectado") .. "  •  " .. st.iface, T.c.dim end
  G.text_fit(T.f.small, line, 26, 90, 640 - 60, lbl)

  -- abas
  local tabs = { L("REDES DISPONÍVEIS"), L("REDES SALVAS") }
  local tx = 12
  G.button_icon("l1", tx, 128); tx = tx + 34
  for i, t in ipairs(tabs) do
    local tw = T.f.pix8:getWidth(I18N.tr(t)) + 20
    G.rect(tx, 124, tw, 24, i == self.tab and T.c.accent2 or T.c.bg2, 6)
    G.text(T.f.pix8, t, tx + 10, 132, i == self.tab and T.c.bg0 or T.c.dim)
    tx = tx + tw + 6
  end
  G.button_icon("r1", tx + 2, 128)

  -- lista
  local list = {}
  for i = 2, #items do list[#list + 1] = { i = i, it = items[i] } end
  local selpos = self.sel - 1
  if selpos > self.top + VISIBLE then self.top = selpos - VISIBLE end
  if selpos >= 1 and selpos <= self.top then self.top = selpos - 1 end
  if self.top < 0 then self.top = 0 end
  local y = LIST_Y
  for k = self.top + 1, math.min(#list, self.top + VISIBLE) do
    local e = list[k]
    local it, sel = e.it, e.i == self.sel
    G.panel(12, y, 640 - 24, ROW_H - 4, { bg = sel and T.c.bg3 or T.c.bg1, border = sel and T.c.accent or T.c.line, lw = sel and 2 or 1 })
    if it.kind == "scan" then
      local busy = self.busy == "scan"
      G.text(T.f.bodyb, busy and L("Pesquisando redes...") or L("Pesquisar redes"), 32, y + 9, sel and T.c.text or T.c.dim)
      if busy then G.progress_busy(400, y + 15, 210, 6, App.t, T.c.accent2)
      else G.text(T.f.small, string.format(L("%d rede(s) encontrada(s)"), #(self.nets or {})), 400, y + 11, T.c.faint, "right", 210) end
    elseif it.kind == "net" then
      local n = it.net
      W.draw_bars(26, y + 9, n.signal, n.in_use and T.c.green or T.c.accent2, T.c.line)
      local right = 640 - 30
      if n.in_use then
        local tg = L("CONECTADA"); local tw = T.f.pix8:getWidth(I18N.tr(tg)) + 12
        G.tag(tg, right - tw, y + 10, T.c.green, T.c.bg0, T.f.pix8); right = right - tw - 8
      elseif saved_for(self, n.ssid) then
        local tg = L("SALVA"); local tw = T.f.pix8:getWidth(I18N.tr(tg)) + 12
        G.tag(tg, right - tw, y + 10, T.c.accent2, T.c.bg0, T.f.pix8); right = right - tw - 8
      end
      if n.security ~= "" then W.lock(right - 12, y + 9, T.c.dim); right = right - 20 end
      local sub = W.signal_label(n.signal) .. "  •  " .. W.security_label(n.security)
      local ft, fs, ty, sy = G.row_fonts(ROW_H - 4, 3, 20)
      G.text_fit(ft, n.ssid, 58, y + ty, right - 66, sel and T.c.text or T.c.dim)
      G.text_fit(fs, sub, 58, y + sy, right - 66, T.c.faint)
    elseif it.kind == "saved" then
      local s = it.saved
      Icons.draw("set_network", 24, y + 6, s.active and T.c.green or T.c.dim, 1)
      local right = 640 - 30
      if s.active then
        local tg = L("CONECTADA"); local tw = T.f.pix8:getWidth(I18N.tr(tg)) + 12
        G.tag(tg, right - tw, y + 10, T.c.green, T.c.bg0, T.f.pix8); right = right - tw - 8
      end
      local ft, fs, ty, sy = G.row_fonts(ROW_H - 4, 3, 20)
      G.text_fit(ft, s.ssid, 58, y + ty, right - 66, sel and T.c.text or T.c.dim)
      G.text_fit(fs, s.name ~= s.ssid and (L("Perfil: ") .. s.name) or L("Senha guardada pelo sistema"), 58, y + sy, right - 66, T.c.faint)
    end
    y = y + ROW_H
  end
  if #list == 0 or (self.tab == 1 and #list == 1 and self.nets and #self.nets == 0 and not self.busy) then
    local msg = self.tab == 2 and (self.saved and L("Nenhuma rede Wi-Fi salva.") or L("Carregando..."))
      or (st.radio == false and L("O Wi-Fi está desativado. Ative-o no interruptor acima.") or L("Nenhuma rede encontrada. Tente pesquisar de novo."))
    G.text(T.f.small, msg, 12, y + 14, T.c.dim, "center", 640 - 24)
  end
  if self.err then G.text_fit(T.f.small, L("Erro: ") .. self.err, 24, 418, 600, T.c.red) end
  if #list > VISIBLE then
    local track = VISIBLE * ROW_H
    local hh = track * VISIBLE / #list
    G.rect(640 - 9, LIST_Y + (track - hh) * (self.top / (#list - VISIBLE)), 3, hh, T.c.accent2, 1, 0.7)
  end
  G.hints({ { "dpad", L("Navegar") }, { "a", L("Selecionar") }, { "y", L("Pesquisar") }, { "l1", "" }, { "r1", L("Aba") }, { "b", L("Voltar") } })
end

-- ---------------------------------------------------------------------------
function S:open_saved(s)
  local st = self.status or {}
  local btns = {}
  if s.active then
    btns[#btns + 1] = { label = L("DESCONECTAR"), fn = function() W.guard(function() self:request("disconnect", { iface = st.iface }) end) end }
  else
    btns[#btns + 1] = { label = L("CONECTAR"), fn = function()
      W.guard(function()
        App.toast(L("Conectando..."), "info")
        self:request("reconnect", { uuid = s.uuid, iface = st.iface })
      end)
    end }
  end
  btns[#btns + 1] = { label = L("ESQUECER"), danger = true, fn = function()
    App.show_dialog({ title = L("Esquecer rede?"), kind = "warn",
      body = string.format(L("A rede \"%s\" e a senha guardada serão apagadas do sistema. Para usar de novo, será preciso digitar a senha."), s.ssid),
      buttons = { { label = L("ESQUECER"), danger = true, fn = function() self:request("forget", { uuid = s.uuid }) end }, { label = L("CANCELAR") } },
      sel = 2 })
  end }
  btns[#btns + 1] = { label = L("VOLTAR") }
  App.show_dialog({ title = s.ssid, kind = "info",
    body = (s.active and L("Rede conectada agora.") or L("Rede salva.")) .. "\n" .. L("A senha fica guardada pelo NetworkManager do sistema e não é exibida."),
    buttons = btns })
end

function S:action(act)
  local st = self.status
  if act == "b" then App.pop(); return end
  if not st or not st.nmcli then return end
  local items = self:items()
  local n = #items
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "l1" or act == "r1" then
    self.tab = self.tab == 1 and 2 or 1
    self.sel, self.top = math.min(self.sel, 2), 0
    if self.tab == 2 and not self.busy then self:request("saved") end
  elseif act == "y" and not self.busy then self:request(self.tab == 1 and "scan" or "saved")
  elseif act == "a" then
    local it = items[self.sel]
    if not it or self.busy == "radio" then return end
    if it.kind == "switch" then
      if st.radio == nil or not st.iface then return end
      local want = not st.radio
      local function go() self:request("radio", { on = want }) end
      if want then go() else W.guard(go) end
    elseif it.kind == "scan" then
      if not self.busy then self:request("scan") end
    elseif it.kind == "net" then
      if it.net.in_use then
        local s = saved_for(self, it.net.ssid)
        if s then self:open_saved(s) end
        return
      end
      local s = saved_for(self, it.net.ssid)
      App.push("wifi_connect", { net = it.net, iface = st.iface, saved = s })
    elseif it.kind == "saved" then
      self:open_saved(it.saved)
    end
  end
end

return S
