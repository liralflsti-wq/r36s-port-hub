-- =============================================================================
--  Configuracoes > Ajustes do console (R36 Control do dArkOSRE)
--  LED de aviso da bateria, correcao de gama, saida de audio, volume ao ligar
--  e a configuracao /etc/r36_config.ini. Mesmos arquivos e comandos do
--  "R36 Control.sh" do sistema (core/r36ctl.lua), em segundo plano.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local lg = love.graphics
local R = require("core.r36ctl")

local S = {}

local PATH_NAME = { SPK_HP = L("Alto-falante + fone (detecta o fone)"), SPK = L("Somente alto-falante") }
local WHY = {
  perm = L("O sistema não deu permissão de administrador (sudo)."),
  invalid = L("Valor inválido."),
  service = L("O serviço do LED (batt_led.service) não iniciou."),
}

local seq = 0
function S:job(op, params, cb)
  if self.busy then return end
  seq = seq + 1
  local name = "hub_r36_" .. seq
  local ch = love.thread.getChannel(name)
  ch:clear()
  local job = params or {}
  job.op, job.lang = op, I18N.lang
  local th = love.thread.newThread("threads/r36ctl_thread.lua")
  th:start(name, job)
  self.busy = { ch = ch, th = th, op = op, cb = cb }
end

function S:enter(p)
  self.sel = (p and p.section == "led") and 1 or 1
  self.view = nil
  self:job("status")
end

function S:update()
  local b = self.busy
  if not b then return end
  local m = b.ch:pop()
  local e = not m and b.th:getError()
  if not m and not e then return end
  self.busy = nil
  if e then m = { ok = false, why = tostring(e) } end
  if m.status then
    self.st = m.status
    self.gamma = self.st.gamma
    self.vol = self.st.alsa_volume
  end
  if b.cb then b.cb(m) end
end

function S:result(m, okmsg)
  if m.ok then App.toast(okmsg, "ok")
  else
    App.show_dialog({ title = L("Não aplicado"), kind = "error",
      body = WHY[m.why] and I18N.tr(WHY[m.why]) or tostring(m.why) })
  end
end

local ROWS = { "led", "gamma", "path", "volume", "view", "delete" }

function S:pick_led()
  local st = self.st
  if #st.profiles == 0 then
    App.toast(L("Nenhum perfil de LED encontrado para esta variante."), "warn"); return
  end
  local btns = {}
  for _, n in ipairs(st.profiles) do
    btns[#btns + 1] = { label = (st.desc and st.desc[n]) or n, sub = n .. ((n == st.active) and ("  •  " .. I18N.tr(L("ATUAL"))) or ""),
      fn = function()
        self:job("led", { name = n }, function(m) self:result(m, L("LED de aviso da bateria aplicado.")) end)
      end }
  end
  btns[#btns + 1] = { label = L("Voltar") }
  local sel = 1
  for i, n in ipairs(st.profiles) do if n == st.active then sel = i end end
  App.show_dialog({ title = L("LED de aviso da bateria"), kind = "info", list = true,
    body = L("Com o carregador ligado, o LED volta ao controle do hardware."), buttons = btns, sel = sel })
end

function S:pick_path()
  local btns = {}
  for _, pth in ipairs(R.PATHS) do
    btns[#btns + 1] = { label = PATH_NAME[pth], sub = pth .. ((pth == self.st.alsa_path) and ("  •  " .. I18N.tr(L("ATUAL"))) or ""),
      fn = function()
        self:job("path", { value = pth }, function(m) self:result(m, L("Saída de áudio alterada.")) end)
      end }
  end
  btns[#btns + 1] = { label = L("Voltar") }
  App.show_dialog({ title = L("Saída de áudio"), kind = "info", list = true,
    body = L("Aplica na hora e reinicia o serviço de teclas de volume (ogage)."), buttons = btns,
    sel = self.st.alsa_path == "SPK" and 2 or 1 })
end

local function vol_list()
  local t = { false }
  for _, v in ipairs(R.VOLUMES) do t[#t + 1] = v end
  return t
end

function S:action(act)
  if self.view then
    local maxtop = math.max(0, #self.view - 14)
    if act == "b" or act == "a" then self.view = nil
    elseif act == "up" then self.vtop = math.max(0, self.vtop - 1)
    elseif act == "down" then self.vtop = math.min(maxtop, self.vtop + 1) end
    return
  end
  if act == "b" then App.pop(); return end
  local st = self.st
  if not st or not st.available then return end
  local n = #ROWS
  local r = ROWS[self.sel]
  if act == "up" then self.sel = (self.sel - 2) % n + 1; return end
  if act == "down" then self.sel = self.sel % n + 1; return end
  if self.busy then if act == "a" then App.toast(L("Aguarde a operação atual terminar."), "info") end return end
  if act == "left" or act == "right" then
    local d = act == "left" and -1 or 1
    if r == "gamma" then
      local i = 1
      for k, v in ipairs(R.GAMMAS) do if v == self.gamma then i = k end end
      self.gamma = R.GAMMAS[math.max(1, math.min(#R.GAMMAS, i + d))]
    elseif r == "volume" then
      local list, i = vol_list(), 1
      for k, v in ipairs(list) do if v == (self.vol or false) then i = k end end
      local nv = list[math.max(1, math.min(#list, i + d))]
      self.vol = nv or nil
    end
    return
  end
  if act ~= "a" then return end
  if r == "led" then self:pick_led()
  elseif r == "path" then self:pick_path()
  elseif r == "gamma" then
    if self.gamma == st.gamma then App.toast(L("Use esquerda/direita para escolher outro valor."), "info"); return end
    App.show_dialog({ title = L("Salvar gama?"), kind = "info",
      body = string.format(I18N.tr(L("Gama %s. Vale a partir do próximo boot. Para testar agora, segure R3 e use esquerda/direita no direcional.")), self.gamma),
      buttons = { { label = L("SALVAR"), fn = function()
        self:job("gamma", { value = self.gamma }, function(m) self:result(m, L("Gama salva. Reinicie o console para aplicar.")) end)
      end }, { label = L("CANCELAR") } } })
  elseif r == "volume" then
    local v = self.vol
    self:job("volume", { value = v }, function(m)
      self:result(m, v and string.format(I18N.tr(L("Volume ao ligar: %d%% (aplicado a cada boot).")), v)
        or L("Volume ao ligar desativado: vale o volume normal."))
    end)
  elseif r == "view" then
    local lines = {}
    for l in (st.config_text or I18N.tr(L("Arquivo de configuração não encontrado."))):gmatch("[^\n]+") do lines[#lines + 1] = l end
    self.view, self.vtop = lines, 0
  elseif r == "delete" then
    App.show_dialog({ title = L("Apagar configuração?"), kind = "error",
      body = L("Apaga /etc/r36_config.ini. O sistema cria de novo com os valores padrão no próximo boot."),
      buttons = { { label = L("APAGAR"), danger = true, fn = function()
        self:job("delete", {}, function(m) self:result(m, L("Configuração apagada. Reinicie o console para restaurar o padrão.")) end)
      end }, { label = L("CANCELAR") } }, sel = 2 })
  end
end

function S:draw()
  G.header(L("Ajustes do console (R36 Control)"))
  local x, w = 12, T.W - 24
  local st = self.st
  if not st then
    G.text(T.f.body, L("Lendo a configuração do sistema..."), x, 200, T.c.dim, "center", w)
    return
  end
  if not st.available then
    G.panel(x, 50, w, 380, { bg = T.c.bg1 })
    G.text(T.f.pix16, L("NÃO DISPONÍVEL"), x, 100, T.c.yellow, "center", w)
    local lines = G.wrap(T.f.body, I18N.tr(L("Estes ajustes são do dArkOSRE (R36 Control) e não foram encontrados neste sistema: falta a pasta /usr/local/bin/r36_config e o arquivo /etc/r36_config.ini.")), w - 60)
    for i, l in ipairs(lines) do G.text(T.f.body, l, x + 30, 140 + (i - 1) * 22, T.c.dim) end
    G.hints({ { "b", L("Voltar") } })
    return
  end
  if self.view then
    G.panel(x, 50, w, 384, { bg = T.c.bg1 })
    G.text(T.f.pix8, "/etc/r36_config.ini", x + 14, 60, T.c.accent2)
    for i = self.vtop + 1, math.min(#self.view, self.vtop + 14) do
      G.text_fit(T.f.small, self.view[i], x + 14, 80 + (i - self.vtop - 1) * 24, w - 28, T.c.text)
    end
    G.hints({ { "dpad", L("Rolar") }, { "b", L("Voltar") } })
    return
  end
  -- topo
  G.panel(x, 50, w, 58, { bg = T.c.bg1 })
  G.text_fit(T.f.bodyb, (st.hardware or I18N.tr(L("modelo não informado"))), x + 14, 58, w - 28, T.c.text)
  local info = I18N.tr(L("Variante: ")) .. tostring(st.variant) .. "  •  " .. I18N.tr(L("Serviço do LED: "))
    .. I18N.tr(st.led_service and L("ativo") or L("parado"))
  G.text_fit(T.f.small, info, x + 14, 82, w - 28, T.c.dim)
  -- linhas
  local y, RH = 116, 44
  for i, r in ipairs(ROWS) do
    local on = i == self.sel
    G.rect(x, y, w, RH - 4, on and T.c.bg3 or T.c.bg1, 7)
    if on then G.frame(x, y, w, RH - 4, r == "delete" and T.c.red or T.c.accent, 7, 2) end
    local label, value, sub
    if r == "led" then
      label = L("LED de aviso da bateria")
      value = st.active and ((st.desc and st.desc[st.active]) or st.active) or I18N.tr(L("nenhum perfil escolhido"))
    elseif r == "gamma" then
      label = L("Correção de gama")
      value = self.gamma .. ((self.gamma ~= st.gamma) and ("  (" .. I18N.tr(L("atual: ")) .. st.gamma .. ")") or "")
    elseif r == "path" then label, value = L("Saída de áudio"), PATH_NAME[st.alsa_path] or st.alsa_path
    elseif r == "volume" then
      label = L("Volume ao ligar")
      value = self.vol and (self.vol .. "%") or I18N.tr(L("Manual (volume normal)"))
      if (self.vol or false) ~= (st.alsa_volume or false) then value = value .. "  •  " .. I18N.tr(L("A salva")) end
    elseif r == "view" then label, value = L("Ver configuração atual"), ""
    elseif r == "delete" then label, value = L("Apagar configuração (vale no próximo boot)"), "" end
    G.text(T.f.bodyb, label, x + 16, y + 4, on and (r == "delete" and T.c.red or T.c.text) or T.c.dim)
    G.text_fit(T.f.small, value, x + 16, y + 22, w - 60, on and T.c.accent2 or T.c.faint)
    local arrows = on and (r == "gamma" or r == "volume")
    G.color(on and T.c.accent or T.c.faint)
    local ax, ay = x + w - 22, y + 20
    if arrows then
      lg.polygon("fill", ax - 14, ay, ax - 8, ay - 5, ax - 8, ay + 5)
      lg.polygon("fill", ax + 6, ay, ax, ay - 5, ax, ay + 5)
    else
      lg.polygon("fill", ax, ay - 5, ax, ay + 5, ax + 6, ay)
    end
    y = y + RH
  end
  local desc = ({
    led = L("Perfis do próprio sistema: o LED muda de cor conforme a carga da bateria."),
    gamma = L("Esquerda/direita escolhe (0.4 a 1.8), A salva. Vale no próximo boot."),
    path = L("Como o som sai: alto-falante com detecção do fone, ou só alto-falante."),
    volume = L("Esquerda/direita escolhe, A salva. Manual = o sistema não força volume ao ligar."),
    view = L("Mostra o arquivo /etc/r36_config.ini."),
    delete = L("O sistema recria o arquivo com os valores padrão ao ligar."),
  })[ROWS[self.sel]]
  if self.busy and self.busy.op ~= "status" then desc = L("Aplicando...") end
  G.text_fit(T.f.small, desc, x + 4, 384, w - 8, self.busy and T.c.yellow or T.c.dim)
  G.hints({ { "dpad", L("Navegar") }, { "a", L("Selecionar") }, { "b", L("Voltar") } })
end

return S
