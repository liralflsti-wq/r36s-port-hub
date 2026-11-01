-- Menu principal da loja
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Catalog = require("core.catalog")
local Covers = require("core.covers")
local Net = require("core.net")
local Battery = require("core.battery")
local lg = love.graphics

local S = {}

local ITEMS = {
  { id = "store", label = L("Central de Conteúdo"), sub = L("Jogos, BIOS, utilitários e ferramentas"), icon = "store" },
  { id = "categories", label = L("Categorias"), sub = L("Navegue por gênero"), icon = "cats" },
  { id = "installed", label = L("Meus Ports"), sub = L("Ports instalados no console"), icon = "mine" },
  { id = "downloads", label = L("Downloads em segundo plano"), sub = L("Progresso e histórico (atalho: START)"), icon = "download" },
  { id = "settings", label = L("Configurações"), sub = L("Música, catálogo e runtimes"), icon = "settings" },
  { id = "about", label = L("Sobre o Projeto"), sub = L("Informações e créditos"), icon = "about" },
  { id = "exit", label = L("Sair"), sub = L("Fechar o R36S PORT HUB"), icon = "exit" },
}

function S:enter()
  self.sel = self.sel or 1
  self.feat_i = 1
  self.feat_t = 0
  self:on_catalog()
end

function S:on_catalog()
  local f = {}
  for _, p in ipairs(Catalog.ports) do if p.featured then f[#f + 1] = p end end
  if #f == 0 then
    for i = 1, math.min(6, #Catalog.ports) do f[#f + 1] = Catalog.ports[i] end
  end
  self.featured = f
  if self.feat_i > #f then self.feat_i = 1 end
end

function S:resume() self:on_catalog() end

function S:update(dt)
  self.feat_t = self.feat_t + dt
  if self.feat_t > 4.5 and #self.featured > 1 and App.animations() then
    self.feat_t = 0
    self.feat_i = self.feat_i % #self.featured + 1
  end
end

local function icon(kind, x, y, c)
  G.color(c)
  lg.setLineWidth(2)
  if kind == "store" then
    lg.rectangle("line", x + 2, y + 6, 16, 12, 2, 2)
    lg.line(x + 6, y + 6, x + 6, y + 3, x + 14, y + 3, x + 14, y + 6)
  elseif kind == "cats" then
    for i = 0, 1 do for j = 0, 1 do lg.rectangle("fill", x + 2 + i * 9, y + 2 + j * 9, 7, 7, 1, 1) end end
  elseif kind == "mine" then
    lg.rectangle("line", x + 2, y + 4, 16, 12, 3, 3)
    lg.circle("fill", x + 7, y + 10, 2)
    lg.rectangle("fill", x + 11, y + 8, 4, 4)
  elseif kind == "refresh" then
    lg.arc("line", "open", x + 10, y + 10, 7, -0.3, 4.6)
    lg.polygon("fill", x + 15, y + 2, x + 18, y + 8, x + 12, y + 8)
  elseif kind == "about" then
    lg.circle("line", x + 10, y + 10, 8)
    lg.rectangle("fill", x + 9, y + 9, 2, 6)
    lg.rectangle("fill", x + 9, y + 5, 2, 2)
  elseif kind == "music" then
    lg.circle("fill", x + 6, y + 15, 3)
    lg.circle("fill", x + 15, y + 13, 3)
    lg.line(x + 9, y + 15, x + 9, y + 3, x + 18, y + 1, x + 18, y + 13)
  elseif kind == "settings" then
    lg.circle("line", x + 10, y + 10, 4)
    for i = 0, 7 do
      local a = i * math.pi / 4
      lg.line(x + 10 + math.cos(a) * 6, y + 10 + math.sin(a) * 6, x + 10 + math.cos(a) * 9, y + 10 + math.sin(a) * 9)
    end
  elseif kind == "download" then
    lg.line(x + 10, y + 2, x + 10, y + 12)
    lg.polygon("fill", x + 5, y + 10, x + 15, y + 10, x + 10, y + 15)
    lg.line(x + 3, y + 14, x + 3, y + 18, x + 17, y + 18, x + 17, y + 14)
  elseif kind == "exit" then
    lg.rectangle("line", x + 2, y + 3, 10, 14, 1, 1)
    lg.line(x + 8, y + 10, x + 18, y + 10)
    lg.polygon("fill", x + 18, y + 10, x + 14, y + 6, x + 14, y + 14)
  end
  lg.setLineWidth(1)
end

function S:draw()
  -- coluna esquerda: logo + menu
  G.logo(24, 6, "menu")
  G.text(T.f.pix8, C.VERSION, 28, 86, T.c.faint)

  local y0 = 100
  for i, it in ipairs(ITEMS) do
    local y = y0 + (i - 1) * 49
    local on = i == self.sel
    if on then
      G.rect(20, y, 300, 44, T.c.bg2, 8)
      G.frame(20, y, 300, 44, T.c.accent, 8, 2)
      G.rect(20, y + 8, 4, 28, T.c.accent, 2)
    end
    icon(it.icon, 36, y + 12, on and T.c.accent or T.c.dim)
    -- largura do destaque (x 20..320): texto maior diminui ou e encurtado
    G.text_fit(T.f.h3, it.label, 68, y + 5, 246, on and T.c.text or T.c.dim)
    G.text_fit(T.f.small, it.sub, 68, y + 25, 246, on and T.c.dim or T.c.faint)
  end

  -- relogio (hora do sistema), acima do destaque
  local Clock = require("core.clock")
  local clock = Clock.time()
  local wd = ({ L("dom"), L("seg"), L("ter"), L("qua"), L("qui"), L("sex"), L("sáb") })[Clock.wday()]
  local datestr = wd .. ", " .. Clock.date(nil, true)
  G.text(T.f.small, datestr, 620 - T.f.bodyb:getWidth(clock) - 8 - T.f.small:getWidth(datestr), 6, T.c.dim)
  G.text(T.f.bodyb, clock, 620 - T.f.bodyb:getWidth(clock), 4, T.c.text)

  -- coluna direita: destaque + status
  local px, py, pw, ph = 340, 24, 280, 330
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  G.text(T.f.pix8, L("EM DESTAQUE"), px + 16, py + 14, T.c.yellow)
  local p = self.featured[self.feat_i]
  if p then
    local cw, ch = 150, 200
    local cx, cy = px + (pw - cw) / 2, py + 34
    G.cover(Covers.get(p), p, cx, cy, cw, ch, Covers.is_loading(p), App.t)
    G.text_fit(T.f.h3, p.name, px + 16, cy + ch + 10, pw - 32, T.c.text)
    G.text_fit(T.f.small, p.category .. "  •  " .. p.size_label, px + 16, cy + ch + 32, pw - 32, T.c.dim)
    -- indicadores
    local n = #self.featured
    local dx = px + pw / 2 - (n * 12) / 2
    for i = 1, n do
      G.rect(dx + (i - 1) * 12, py + ph - 18, 8, 4, i == self.feat_i and T.c.accent or T.c.line, 2)
    end
  else
    G.text(T.f.body, L("Nenhum port no catálogo ainda."), px + 16, py + 140, T.c.dim, "center", pw - 32)
  end

  -- status
  local sy = py + ph + 12
  G.panel(px, sy, pw, 76, { bg = T.c.bg1 })
  local online = Catalog.source == "online"
  local dot = Catalog.remote_state == "loading" and T.c.yellow or (online and T.c.green or T.c.orange)
  G.color(dot); lg.circle("fill", px + 20, sy + 19, 4)
  local st = Catalog.remote_state == "loading" and L("Sincronizando catálogo...") or Catalog.source_label()
  G.text_fit(T.f.bodyb, st, px + 32, sy + 10, pw - 48, T.c.text)
  G.text(T.f.small, string.format(L("%d ports  •  %d categorias"), #Catalog.ports, #Catalog.categories), px + 16, sy + 32, T.c.dim)
  local free = App.free and (U.format_bytes(App.free) .. L(" livres")) or L("Espaço livre: desconhecido")
  free = string.format(L("%d no console  •  "), require("core.scan").count) .. free
  G.text(T.f.small, free, px + 16, sy + 50, T.c.dim)

  local hints = { { "dpad", L("Navegar") }, { "a", L("Selecionar") }, { "b", L("Sair") } }
  -- texto maior: se dicas + rede + bateria nao couberem no rodape, ele usa o tamanho padrao
  if G.hints_width(hints, T.f.small) + 24 > self:wifi_left() then
    T.with_base_fonts(function() G.hints(hints); self:draw_wifi() end)
  else
    G.hints(hints)
    self:draw_wifi()
  end
end

--- icone de Wi-Fi (arcos); off = riscado
local function wifi_icon(x, y, c, off)
  G.color(c)
  lg.setLineWidth(2)
  for i = 1, 3 do
    lg.arc("line", "open", x + 9, y + 14, i * 4, -math.pi * 0.75, -math.pi * 0.25)
  end
  lg.circle("fill", x + 9, y + 13, 2)
  if off then
    G.color(T.c.red)
    lg.line(x + 1, y + 1, x + 17, y + 15)
  end
  lg.setLineWidth(1)
end

--- texto da rede no rodape
local function wifi_text()
  local st = Net.current()
  if not st then
    return L("VERIFICANDO CONEXÃO"), T.c.yellow, false
  elseif st.connected then
    return L("CONECTADO / IP: ") .. st.ip, T.c.green, false
  end
  return L("DESCONECTADO / IP: INDISPONÍVEL"), T.c.red, true
end

local function battery_text()
  local b = Battery.get()
  if not b.ok then return L("INDISPONÍVEL") end
  return b.pct .. "%"
end

--- onde comeca (x) o bloco rede + bateria do rodape, com a fonte atual
function S:wifi_left()
  local text = wifi_text()
  local bw = T.f.small:getWidth(battery_text()) + 28
  return T.W - 14 - bw - 18 - T.f.small:getWidth(text) - 24
end

--- rodape: estado real da rede (lido em segundo plano, sem travar o menu)
function S:draw_wifi()
  local y = T.H - 26
  local text, c, off = wifi_text()
  local tw = T.f.small:getWidth(text)
  local bw = self:draw_battery(y)          -- bateria no canto direito
  local x = T.W - 14 - bw - 18 - tw        -- Wi-Fi logo a esquerda dela
  G.text(T.f.small, text, x, y + 1, c)
  wifi_icon(x - 24, y - 1, c, off)
end

--- icone de bateria: contorno, carga proporcional e raio quando carregando
local function battery_icon(x, y, frac, c, charging, unknown)
  G.color(c)
  lg.setLineWidth(1)
  lg.rectangle("line", x + 0.5, y + 3.5, 20, 10)
  lg.rectangle("fill", x + 21, y + 6, 2, 5)
  if unknown then
    G.text(T.f.pix8, "?", x + 6, y + 5, c)
    return
  end
  -- 4 segmentos (alta, media, baixa, critica)
  local segs = frac >= 0.75 and 4 or (frac >= 0.40 and 3 or (frac >= 0.15 and 2 or 1))
  for i = 1, segs do lg.rectangle("fill", x + 2 + (i - 1) * 4.5, y + 5, 3.5, 7) end
  if charging then
    G.color(T.c.bg0)
    lg.polygon("fill", x + 11, y + 1, x + 6, y + 9, x + 10, y + 9, x + 8, y + 16, x + 15, y + 7, x + 11, y + 7, x + 13, y + 1)
    G.color(T.c.yellow)
    lg.polygon("fill", x + 11, y + 2, x + 7, y + 9, x + 10.5, y + 9, x + 9, y + 14, x + 14, y + 7.5, x + 10.5, y + 7.5, x + 12.5, y + 2)
  end
end

--- desenha a bateria no rodape e devolve a largura usada
function S:draw_battery(y)
  local b = Battery.get()
  local text, c, frac, charging, unknown
  if not b.ok then
    text, c, unknown = L("INDISPONÍVEL"), T.c.faint, true
  else
    frac = b.pct / 100
    charging = b.charging
    local lv = Battery.level(b.pct)
    c = (lv == "high" and T.c.green) or (lv == "medium" and T.c.accent2) or (lv == "low" and T.c.yellow) or T.c.red
    text = b.pct .. "%"
    if charging then c = T.c.green end
    -- bateria critica: pisca devagar (sem custo extra)
    if lv == "critical" and not charging and math.floor(App.t * 2) % 2 == 0 then c = T.c.orange end
  end
  local tw = T.f.small:getWidth(text)
  local x = T.W - 14 - tw
  G.text(T.f.small, text, x, y + 1, c)
  battery_icon(x - 28, y - 1, frac or 0, c, charging, unknown)
  return tw + 28
end

local function power_confirm(kind)
  local off = kind == "poweroff"
  App.show_dialog({
    title = off and L("Desligar o console?") or L("Reiniciar o console?"),
    kind = "warn",
    body = (off and L("O R36S PORT HUB será fechado e o console será desligado.")
      or L("O R36S PORT HUB será fechado e o console será reiniciado."))
      .. "\n" .. L("Jogos e arquivos abertos em outros apps não são salvos."),
    buttons = {
      { label = off and L("DESLIGAR") or L("REINICIAR"), danger = true, fn = function() App.power_request(kind) end },
      { label = L("CANCELAR") },
    },
    sel = 2,
  })
end

local function exit_dialog()
  App.show_dialog({
    title = L("Sair do R36S PORT HUB"),
    kind = "info",
    list = true,
    body = L("O que você quer fazer?"),
    buttons = {
      { label = L("Sair"), sub = L("Fechar o R36S PORT HUB e voltar ao EmulationStation"), fn = App.quit },
      { label = L("Reiniciar lista"), sub = L("Use se instalou ports nesta sessão: reinicia o EmulationStation"), fn = App.request_es_restart },
      { label = L("Reiniciar console"), sub = L("Fecha o hub e reinicia o R36S"), danger = true, fn = function() power_confirm("reboot") end },
      { label = L("Desligar console"), sub = L("Fecha o hub e desliga o R36S"), danger = true, fn = function() power_confirm("poweroff") end },
      { label = L("Voltar") },
    },
  })
end

function S:action(act)
  if act == "up" then self.sel = (self.sel - 2) % #ITEMS + 1
  elseif act == "down" then self.sel = self.sel % #ITEMS + 1
  elseif act == "b" then exit_dialog()
  elseif act == "a" then
    local id = ITEMS[self.sel].id
    if id == "store" then App.push("sections")
    elseif id == "categories" then App.push("categories")
    elseif id == "installed" then App.push("store", { mine = true })
    elseif id == "downloads" then App.open_downloads(false)
    elseif id == "settings" then App.push("settings")
    elseif id == "about" then App.push("about")
    elseif id == "exit" then exit_dialog()
    end
  end
end

return S
