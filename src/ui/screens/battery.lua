-- =============================================================================
--  Configuracoes > Informacoes do console > Analise da bateria
--  So o que o kernel informa em /sys/class/power_supply (nada e estimado sem
--  dado real; nada e escrito no sistema). Le arquivos pequenos a cada 5 s e
--  so enquanto esta tela esta aberta (nenhum processo em segundo plano).
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Battery = require("core.battery")

local S = {}
local INTERVAL = 5

function S:enter()
  self.samples = {}
  self.t = 0
  self:read()
end

function S:read()
  local ok, snap = pcall(Battery.snapshot)
  if not ok then
    U.log("Bateria: falha na leitura:", tostring(snap))
    pcall(function() require("core.errlog").problem(I18N.tr(L("Análise da bateria")), tostring(snap)) end)
    snap = { ok = false, raw = {}, avail = {}, chargers = {} }
  end
  self.snap = snap
  self.v = snap.ok and Battery.values(snap) or nil
  if self.v then
    local charging = self.v.status == "charging" or (self.v.status ~= "discharging" and self.v.charger == true)
    if charging and self.v.pct then
      local now = love.timer.getTime()
      -- um ponto por mudanca de percentual (e o primeiro) basta para a taxa observada
      local last = self.samples[#self.samples]
      if not last or last.pct ~= self.v.pct then self.samples[#self.samples + 1] = { t = now, pct = self.v.pct } end
      if #self.samples > 120 then table.remove(self.samples, 1) end
    else
      self.samples = {}      -- carregador desligado: a medicao recomeca
    end
    self.est = Battery.estimate(self.v, self.samples)
  else
    self.est = { kind = "none" }
  end
end

function S:update(dt)
  self.t = self.t + dt
  if self.t >= INTERVAL then self.t = 0; self:read() end
end

local function fmt_time(secs)
  secs = math.max(60, math.floor(secs + 0.5))
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60 + 0.5)
  if m == 60 then h, m = h + 1, 0 end
  if I18N.lang == "ru" then
    if h > 0 then return string.format("%d ч %02d мин", h, m) end
    return string.format("%d мин", m)
  end
  if h > 0 then return string.format("%dh%02dmin", h, m) end
  return string.format("%dmin", m)
end

local STATUS = { charging = L("Carregando"), discharging = L("Descarregando"), full = L("Completa"),
  ["not charging"] = L("Não está carregando"), unknown = L("Desconhecido") }

local function battery_shape(x, y, w, h, pct, col, charging)
  G.frame(x, y, w, h, T.c.text, 6, 3)
  G.rect(x + w, y + h / 2 - 12, 8, 24, T.c.text, 2)
  local fw = math.max(0, (w - 12) * (pct or 0) / 100)
  if fw > 0 then G.rect(x + 6, y + 6, fw, h - 12, col, 3) end
  if charging then
    G.color(T.c.yellow)
    local cx, cy = x + w / 2, y + h / 2
    love.graphics.polygon("fill", cx + 6, cy - 22, cx - 12, cy + 4, cx - 1, cy + 4, cx - 6, cy + 22, cx + 12, cy - 4, cx + 1, cy - 4)
  end
end

function S:draw()
  G.header(L("Análise da bateria"), L("Somente leitura"))
  local v, snap = self.v, self.snap
  if not v then
    G.panel(12, 50, T.W - 24, 386, { bg = T.c.bg1 })
    G.text(T.f.pix16, L("BATERIA NÃO IDENTIFICADA"), 12, 150, T.c.orange, "center", T.W - 24)
    G.text(T.f.body, L("O sistema não informa a bateria em /sys/class/power_supply (sem um \"capacity\" legível). Nenhum valor é inventado."),
      40, 190, T.c.dim, "center", T.W - 80)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  local charging = v.status == "charging"
  local col = v.pct >= 40 and T.c.green or (v.pct >= 15 and T.c.yellow or T.c.red)
  -- esquerda: desenho da bateria
  G.panel(12, 50, 236, 230, { bg = T.c.bg1 })
  battery_shape(36, 80, 170, 90, v.pct, col, charging)
  G.text(T.f.pix24, string.format("%d%%", v.pct), 12, 190, col, "center", 236)
  G.text_fit(T.f.bodyb, I18N.tr(STATUS[v.status] or STATUS.unknown), 24, 228, 212, T.c.text)
  local ch = v.charger == true and L("Carregador conectado") or (v.charger == false and L("Carregador desconectado") or L("Carregador: não informado"))
  G.text_fit(T.f.small, ch, 24, 228 + G.step(T.f.bodyb, 22), 212, v.charger and T.c.green or T.c.dim)
  -- direita: valores reais (o que nao existe aparece como "não informado")
  local px, pw = 258, T.W - 270
  G.panel(px, 50, pw, 230, { bg = T.c.bg1 })
  local y = 60
  local NA = I18N.tr(L("não informado"))
  local function row(k, val, c)
    G.text_fit(T.f.small, k, px + 12, y + 1, 146, T.c.faint)
    G.text_fit(T.f.bodyb, val or NA, px + 162, y - 1, pw - 174, val and (c or T.c.text) or T.c.faint)
    y = y + G.step(T.f.bodyb, 21)
  end
  row(L("Nível atual"), string.format("%d%%", v.pct))
  row(L("Estado"), I18N.tr(STATUS[v.status] or STATUS.unknown))
  row(L("Tensão atual"), v.voltage and ((string.format("%.2f V", v.voltage):gsub("%.", I18N.lang == "en" and "." or ","))) or nil)
  row(L("Corrente"), v.current and string.format("%d mA", math.floor(v.current + 0.5)) or nil)
  local cap
  if v.charge_full then cap = string.format("%d mAh", math.floor(v.charge_full + 0.5))
  elseif v.energy_full then cap = string.format("%d mWh", math.floor(v.energy_full + 0.5)) end
  row(L("Capacidade identificada"), cap)
  local design
  if v.charge_design then design = string.format("%d mAh", math.floor(v.charge_design + 0.5))
  elseif v.energy_design then design = string.format("%d mWh", math.floor(v.energy_design + 0.5)) end
  row(L("Capacidade nominal"), design)
  row(L("Carregador"), v.charger == true and L("Conectado") or (v.charger == false and L("Desconectado") or nil))
  G.text_fit(T.f.small, L("Fonte: ") .. tostring(snap.dir), px + 12, 262, pw - 24, T.c.faint)
  -- estimativa
  T.with_base_fonts(self.draw_estimate, self)
  G.hints({ { "b", L("Voltar") } })
end

function S:draw_estimate()
  local v, e = self.v, self.est or {}
  local x, y, w, h = 12, 290, T.W - 24, 146
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  G.rect(x, y, w, 4, T.c.yellow, 2)
  G.text(T.f.pix8, L("TEMPO ESTIMADO PARA CARGA COMPLETA"), x + 14, y + 14, T.c.yellow)
  local cy = y + 32
  local function line(s, c, font)
    font = font or T.f.small
    for _, l in ipairs(G.wrap(font, s, w - 28)) do
      if cy < y + h - 14 then G.text(font, l, x + 14, cy, c or T.c.dim) end
      cy = cy + font:getHeight()
    end
  end
  if e.kind == "full" then
    line(I18N.tr(L("A bateria está completa (100%).")), T.c.green, T.f.bodyb)
  elseif e.kind == "not_charging" then
    line(I18N.tr(L("Não há carga em andamento: conecte o carregador para ver a estimativa.")), T.c.text, T.f.bodyb)
  elseif e.kind == "kernel" or e.kind == "current" or e.kind == "observed" then
    line(I18N.tr(L("Tempo estimado restante: ")) .. fmt_time(e.secs), T.c.text, T.f.h3)
    line(string.format(I18N.tr(L("Bateria atual: %d%%  •  Carregamento: ativo")), v.pct), T.c.text)
    if e.kind == "kernel" then
      line(I18N.tr(L("Valor informado pelo próprio sistema (time_to_full).")))
    elseif e.kind == "current" then
      line(string.format(I18N.tr(L("Calculado com a corrente real (%d mA) e a capacidade real (%d mAh, %s). Acima de 80%% a corrente cai e a carga fica mais lenta: isso já está considerado.")),
        math.floor(e.current + 0.5), math.floor(e.cap + 0.5), e.cap_src))
    else
      line(string.format(I18N.tr(L("ESTIMATIVA APROXIMADA: o sistema não informa corrente e capacidade, então o cálculo usa a velocidade observada (%.1f%% por hora em %d min). A fase final mais lenta já está considerada.")),
        e.rate_h, math.floor(e.minutes + 0.5)), T.c.yellow)
    end
  elseif e.kind == "measuring" then
    line(I18N.tr(L("Medindo a velocidade de carga...")), T.c.text, T.f.bodyb)
    line(string.format(I18N.tr(L("O sistema não informa corrente e capacidade. Deixe esta tela aberta com o carregador conectado: a estimativa aproximada aparece depois que a carga subir pelo menos 2%% (mínimo 2 min). Observado até agora: +%d%% em %d min.")),
      e.delta or 0, math.floor((e.minutes or 0) + 0.5)))
  else
    line(I18N.tr(L("Não foi possível calcular o tempo de carregamento com precisão. Verifique se o carregador está conectado e tente novamente.")), T.c.orange)
  end
end

function S:action(act)
  if act == "b" then App.pop()
  elseif act == "y" then self:read() end
end

return S
