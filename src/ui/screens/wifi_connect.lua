-- =============================================================================
--  Gerenciar Wi-Fi > conectar a uma rede
--  Nome, sinal, seguranca, senha (teclado na tela), CONECTAR / CANCELAR.
--  O resultado so aparece depois que o NetworkManager confirma a conexao
--  (interface conectada e com IP). Senha errada: tenta de novo aqui mesmo.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local J = require("core.wifijob")
local Net = require("core.net")
local Wifi = require("core.wifi")

local S = {}

local function W() return App.screens.wifi.W end

function S:enter(p)
  self.net, self.iface, self.saved = p.net, p.iface, p.saved
  self.psk = ""
  self.reveal = false
  self.state = nil         -- nil | "connecting" | resultado
  local km, why = Wifi.key_mgmt(self.net.security)
  self.unsupported = not km and not self.saved and why or nil
  self.open = km == "none"
  self.need_psk = not self.open and not self.saved
  -- botoes: [senha] CONECTAR CANCELAR
  self.sel = 1
end

function S:fields()
  if self.unsupported then return { "cancel" } end
  local t = {}
  if not self.open then t[#t + 1] = "psk" end
  t[#t + 1] = "connect"
  t[#t + 1] = "cancel"
  return t
end

function S:has_psk()
  return not self.unsupported and not self.open
end

function S:edit_psk()
  App.push("textinput", {
    title = L("Senha do Wi-Fi"), label = self.net.ssid, value = self.psk, mode = "full", secret = true, max = 63,
    hint = L("8 a 63 caracteres. X: maiúsculas  •  !#1: símbolos"),
    validate = function(v)
      if #v < 8 then return false, L("A senha precisa ter pelo menos 8 caracteres.") end
      if v:find("[^\32-\126]") then return false, L("Use apenas letras sem acento, números, símbolos e espaço.") end
      return true
    end,
    on_ok = function(v) self.psk = v; self.state = nil; self.sel = #self:fields() - 1 end,
  })
end

function S:connect()
  if self.unsupported then return end
  if self.need_psk and self.psk == "" then
    self.state = { msg = L("Digite a senha da rede."), color = "yellow" }
    self.sel = 1
    return
  end
  W().guard(function()
    self.state = "connecting"
    self.t0 = love.timer.getTime()
    self.job = J.start("connect", {
      net = { ssid = self.net.ssid, security = self.net.security },
      iface = self.iface,
      psk = self.psk ~= "" and self.psk or nil,
      uuid = (self.created_uuid or (self.saved and self.saved.uuid)) or nil,
    })
  end)
end

function S:cancel_connect()
  if self.state ~= "connecting" then return end
  self.cancelling = true
  J.start("disconnect", { iface = self.iface })        -- o NetworkManager interrompe a tentativa
end

function S:update()
  if not self.job then return end
  local r = J.poll(self.job)
  if not r then return end
  self.job = nil
  local res = r.result or {}
  if res.created_uuid then self.created_uuid = res.created_uuid end
  Net.invalidate()
  if res.ok then
    self.state = { msg = L("Conectado.") .. (res.ip and ("  IP " .. res.ip) or ""), color = "green", ok = true }
    self.created_uuid = nil                          -- o perfil fica salvo pelo sistema
    App.toast(L("Conectado a ") .. self.net.ssid .. (res.ip and ("  •  IP " .. res.ip) or ""), "ok")
  else
    local st = self.cancelling and "cancelled" or (r.error and "failed" or res.state)
    self.state = { msg = W().state_text(st), color = st == "auth" and "orange" or "red", code = st }
    if st == "auth" then
      -- senha errada: o perfil ja existe; basta digitar de novo
      self.need_psk = true
      self.psk = ""
      self.sel = 1
    end
  end
  self.cancelling = false
end

function S:leave_screen()
  -- tentativa que nunca deu certo: apaga so o perfil criado aqui (nada de outras redes)
  if self.created_uuid then J.start("forget", { uuid = self.created_uuid }); self.created_uuid = nil end
  App.pop()
end

function S:draw()
  local n = self.net
  G.header(L("Conectar ao Wi-Fi"), "")
  local x, y, w = 12, 50, 640 - 24
  G.panel(x, y, w, 110, { bg = T.c.bg1 })
  W().draw_bars(x + 18, y + 22, n.signal, T.c.accent2, T.c.line)
  G.text_fit(T.f.h2, n.ssid, x + 54, y + 12, w - 70, T.c.text)
  G.text(T.f.small, L("Sinal: ") .. W().signal_label(n.signal) .. " (" .. (n.signal or 0) .. "%)", x + 54, y + 48, T.c.dim)
  G.text(T.f.small, L("Segurança: ") .. W().security_label(n.security), x + 54, y + 66, T.c.dim)
  if self.saved then G.text(T.f.small, L("Rede salva: a senha guardada pelo sistema será usada."), x + 54, y + 84, T.c.accent2) end

  local fy = y + 124
  if self.unsupported then
    G.text(T.f.bodyb, W().state_text(self.unsupported), x, fy + 6, T.c.red, "center", w)
    fy = fy + 40
  end
  local fields = self:fields()
  for i, f in ipairs(fields) do
    local on = i == self.sel
    if f == "psk" then
      G.panel(x, fy, w, 48, { bg = on and T.c.bg3 or T.c.bg0, border = on and T.c.accent or T.c.line, lw = on and 2 or 1 })
      G.text(T.f.small, L("Senha"), x + 14, fy + 6, T.c.faint)
      local shown = self.psk == "" and (self.saved and L("(usar a senha salva)") or L("Toque A para digitar")) or (self.reveal and self.psk or string.rep("•", #self.psk))
      G.text_fit(T.f.bodyb, shown, x + 14, fy + 22, w - 150, self.psk == "" and T.c.faint or T.c.text)
      G.text(T.f.small, self.reveal and L("Y: ocultar") or L("Y: mostrar"), x + w - 130, fy + 18, T.c.dim, "right", 116)
      fy = fy + 58
    else
      local bw = self.unsupported and w or (w - 10) / 2
      local bx = (f == "connect" or self.unsupported) and x or x + bw + 10
      local c = f == "connect" and T.c.accent or T.c.accent2
      local dis = f == "connect" and (self.unsupported or self.state == "connecting")
      G.rect(bx, fy, bw, 42, on and c or T.c.bg2, 8, dis and 0.4 or 1)
      if on then G.frame(bx, fy, bw, 42, T.c.text, 8, 2) end
      G.text(T.f.pix16, f == "connect" and L("CONECTAR") or L("CANCELAR"), bx, fy + 13, on and T.c.bg0 or T.c.dim, "center", bw)
      if f == "cancel" then fy = fy + 54 end
    end
  end

  -- estado da tentativa
  if self.state == "connecting" then
    local secs = math.floor(love.timer.getTime() - (self.t0 or 0))
    G.text(T.f.bodyb, L("Conectando...") .. "  (" .. secs .. " s)", x, fy + 4, T.c.yellow, "center", w)
    G.progress_busy(x + 60, fy + 30, w - 120, 6, App.t, T.c.yellow)
  elseif type(self.state) == "table" then
    G.text(T.f.bodyb, self.state.msg, x, fy + 4, T.c[self.state.color] or T.c.text, "center", w)
    if self.state.code == "auth" then G.text(T.f.small, L("Digite a senha de novo e toque em CONECTAR."), x, fy + 28, T.c.dim, "center", w) end
  end

  if self.state == "connecting" then G.hints({ { "b", L("Cancelar tentativa") } })
  else
    local h = { { "dpad", L("Navegar") }, { "a", L("Selecionar") } }
    if self:has_psk() then h[#h + 1] = { "y", self.reveal and L("Ocultar senha") or L("Mostrar senha") } end
    h[#h + 1] = { "b", L("Voltar") }
    G.hints(h)
  end
end

function S:action(act)
  if self.state == "connecting" then
    if act == "b" then self:cancel_connect() end
    return
  end
  local fields = self:fields()
  if act == "up" or act == "left" then self.sel = (self.sel - 2) % #fields + 1
  elseif act == "down" or act == "right" then self.sel = self.sel % #fields + 1
  elseif act == "y" then if self:has_psk() then self.reveal = not self.reveal end
  elseif act == "b" then self:leave_screen()
  elseif act == "a" then
    local f = fields[self.sel]
    if type(self.state) == "table" and self.state.ok and f ~= "psk" then App.pop(); return end
    if f == "psk" then self:edit_psk()
    elseif f == "connect" then self:connect()
    else self:leave_screen() end
  end
end

return S
