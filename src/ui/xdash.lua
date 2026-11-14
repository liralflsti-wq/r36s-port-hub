-- =============================================================================
--  Tela inicial em PAINEL VERDE (layout "xdash": Neon Grid Edition)
--  Visual de painel de console: a esquerda o GUIA RAPIDO (capas dos ultimos
--  ports abertos/instalados e atalhos), a direita o cartao de destaque
--  (continuar o ultimo port aberto, ou o EM DESTAQUE do catalogo) e os blocos
--  grandes das areas do hub. So dados reais; as acoes sao as do menu.
--    direcionais: navegar | A: abrir | X: detalhes do port | Y: pesquisar
--    L1/R1: trocar o destaque | B: sair/energia | SELECT: atualizar o hub
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Catalog = require("core.catalog")
local Covers = require("core.covers")
local Icons = require("ui.icons")
local lg = love.graphics

local XD = {}

-- blocos da direita (3 x 2) e atalhos do Guia Rapido
local function tiles()
  return {
    { id = "store", label = L("Central de Conteúdo"), icon = "set_store" },
    { id = "library", label = L("Biblioteca"), icon = "games" },
    { id = "categories", label = L("Categorias"), icon = "set_grid" },
    { id = "settings", label = L("Configurações"), icon = "settings" },
    { id = "about", label = L("Sobre o Projeto"), icon = "set_about" },
    { id = "exit", label = C.OS_MODE and L("Energia") or L("Sair"), icon = "set_exit" },
  }
end
local LINKS = {
  { id = "installed", label = L("Meus Ports"), icon = "set_myports" },
  { id = "favorites", label = L("Favoritos"), icon = "set_favorites" },
  { id = "downloads", label = L("Downloads"), icon = "download" },
}

-- medidas (640x480)
local PX, PY, PW, PH = 14, 54, 182, 382          -- Guia Rapido
local RX, RW = 208, 418                           -- coluna da direita
local FY, FH = 92, 124                            -- cartao de destaque
local TY, TW, TH, TG = 226, 134, 98, 8            -- blocos
local CVW, CVH, CVG = 80, 98, 6                   -- capas do Guia Rapido

--- ultimos ports: abertos pelo hub (mais recente primeiro), completando com os
--- instalados mais novos. So ports que estao no catalogo.
local function recent_ports()
  local out, seen = {}, {}
  local function add(id)
    local p = Catalog.by_id[id]
    if p and not seen[id] and not p.builtin then seen[id] = true; out[#out + 1] = p end
  end
  for id in (require("core.prefs").get("recent_ports") or ""):gmatch("[^,]+") do add(id) end
  if #out < 4 then
    local M = require("core.manifest")
    local inst = {}
    for id, rec in pairs(M.data or {}) do inst[#inst + 1] = { id = id, date = rec.date or "" } end
    table.sort(inst, function(a, b) return a.date > b.date end)
    for _, e in ipairs(inst) do add(e.id) end
  end
  return out
end

--- o que o cartao de destaque mostra: continuar o ultimo port aberto (se ainda
--- instalado) ou o destaque do catalogo
local function hero(S, self)
  local last = (require("core.prefs").get("recent_ports") or ""):match("^[^,]+")
  local p = last and Catalog.by_id[last]
  if p and App.status(p) ~= "none" and not self.xd_feat then return p, "continue" end
  local f = self.featured and self.featured[self.feat_i]
  if f then return f, "featured" end
  if p then return p, "continue" end
  return nil
end

function XD.update(S, self, dt)
  if self.ch_t then
    self.ch_t = self.ch_t + dt
    if self.ch_t > 0.5 then self.ch_t = nil end
  end
  if self.dash_dirty or not self.xd_recent then
    self.xd_recent = recent_ports()
    self.dash_dirty = false
  end
end

local function draw_top(S, self)
  local lw = G.logo(14, 6, "header")
  local Themes = require("core.themes")
  local th = Themes.by_id and Themes.by_id[Themes.current]
  G.text(T.f.bodyb, th and th.name or "", 14 + lw + 12, 9, T.c.text)
  G.text(T.f.pix8, C.OS_MODE and (C.OS_NAME .. " " .. C.OS_VERSION) or C.VERSION, 14 + lw + 12, 27, T.c.faint)
  -- direita: hora, Wi-Fi e bateria
  local bw = S.draw_battery(self, 13, T.W - 16)
  local wx = T.W - 16 - bw - 26
  local _, wc, off = S.wifi_state()
  S.wifi_icon(wx, 12, wc, off)
  local clock = require("core.clock").time()
  local cf = T.base_font(T.f.bodyb)
  local cx = wx - 12 - cf:getWidth(clock)
  G.text(cf, clock, cx, 11, T.c.text)
  S.draw_update_notice(self, cx - 16, 14 + lw + 12 + 120, 12)
end

local function focus_glow(x, y, w, h, r)
  local fc = T.style.focus or T.c.accent
  local k = (App.pulse and App.animations()) and App.pulse(0.85, 0.15, 2.0) or 1
  for i = 6, 1, -1 do G.frame(x - i * 1.6, y - i * 1.6, w + i * 3.2, h + i * 3.2, fc, r + i * 1.6, 2, 0.07 * k) end
  G.frame(x, y, w, h, fc, r, 3, k)
end

local function cover(p, x, y, w, h)
  G.cover(Covers.get(p), p, x, y, w, h, Covers.is_loading(p), App.t)
end

local function draw_guide(S, self)
  local on_zone = self.xd_zone == "left"
  G.rect(PX + 2, PY + 4, PW, PH, T.c.shadow, 8)
  G.rect(PX, PY, PW, PH, T.c.bg1, 8, 0.94)
  local x, y = PX + 10, PY + 10
  G.text_fit(T.f.bodyb, U.upper(I18N.tr(L("Guia rápido"))), x, y, PW - 40, T.c.text)
  G.text(T.f.bodyb, "›", PX + PW - 22, y - 1, T.c.dim)
  y = y + 26
  G.text_fit(T.f.small, U.upper(I18N.tr(L("Ports recentes"))), x, y, PW - 20, T.c.dim)
  y = y + 20
  local rec = self.xd_recent or {}
  for i = 1, 4 do
    local cx = x + ((i - 1) % 2) * (CVW + CVG)
    local cy = y + math.floor((i - 1) / 2) * (CVH + CVG)
    local p = rec[i]
    if p then
      cover(p, cx, cy, CVW, CVH)
    else
      G.rect(cx, cy, CVW, CVH, T.c.bg2, 4)
      G.frame(cx, cy, CVW, CVH, T.c.line, 4, 1)
      Icons.draw("games", cx + CVW / 2 - 14, cy + CVH / 2 - 14, T.c.faint, 28 / 24)
    end
    if on_zone and self.xd_left == i then focus_glow(cx, cy, CVW, CVH, 4) end
  end
  if #rec == 0 then
    G.text(T.f.small, L("Nenhum port ainda"), x, y + 2 * CVH + CVG - 18, T.c.faint, "center", 2 * CVW + CVG)
  end
  y = y + 2 * (CVH + CVG) + 4
  G.text_fit(T.f.bodyb, L("Atalhos"), x, y, PW - 20, T.c.text)
  y = y + 24
  for j, it in ipairs(LINKS) do
    local on = on_zone and self.xd_left == 4 + j
    local ly = y + (j - 1) * 25
    if on then G.rect(PX + 4, ly - 3, PW - 8, 23, T.style.focus or T.c.accent, 4) end
    local c = on and T.c.bg0 or T.c.dim
    Icons.draw(it.icon, x, ly, c, 18 / 24)
    local lab = I18N.tr(it.label)
    if it.id == "downloads" then
      local D = require("core.downloads")
      local n = (D.active() and 1 or 0) + D.waiting_count()
      if n > 0 then lab = lab .. "  (" .. n .. ")" end
    end
    G.text_fit(T.f.body, lab, x + 26, ly, PW - 44, on and T.c.bg0 or T.c.text)
  end
end

local function draw_hero(S, self)
  local p, kind = hero(S, self)
  local on = self.xd_zone == "right" and self.xd_right == 0
  local x, y, w, h = RX, FY, RW, FH
  G.rect(x + 2, y + 4, w, h, T.c.shadow, 8)
  G.rect(x, y, w, h, T.c.bg1, 8, 0.96)
  G.frame(x, y, w, h, T.c.line, 8, 1)
  if on then focus_glow(x, y, w, h, 8) end
  if not p then
    G.text(T.f.bodyb, L("Nenhum destaque no momento"), x + 18, y + 26, T.c.text)
    G.text_fit(T.f.small, L("Abra a Central de Conteúdo para ver os ports."), x + 18, y + 52, w - 36, T.c.dim)
    return
  end
  local cw = 136
  G.clip(x + 8, y + 8, cw, h - 16)
  cover(p, x + 8, y + 8 - (cw * 4 / 3 - (h - 16)) / 2, cw, cw * 4 / 3)
  G.unclip()
  local tx, tw = x + cw + 22, w - cw - 34
  local green = T.c.green
  local label = kind == "continue" and L("Continuar jogo") or L("Em destaque")
  G.text_fit(T.f.bodyb, U.upper(I18N.tr(label)), tx, y + 12, tw, green)
  local nf = G.fit(T.f.h2, p.name, tw)
  G.text_fit(nf, p.name, tx, y + 34, tw, T.c.text)
  local info = {}
  local sub = require("ui.portrow").subtitle(p)
  local cat = sub:match("^(.-)%s+•") or sub
  if (cat or "") ~= "" then info[#info + 1] = I18N.tr(cat) end
  if p.size_label and p.size_label ~= "?" then info[#info + 1] = p.size_label end
  local st = App.status(p)
  info[#info + 1] = I18N.tr(st == "installed" and L("Instalado") or (st == "update" and L("Atualização disponível") or L("Não instalado")))
  G.text_fit(T.f.small, table.concat(info, "  •  "), tx, y + 66, tw, T.c.dim)
  local act = (kind == "continue" and st ~= "none") and L("Jogar agora") or L("Ver detalhes")
  G.text_fit(T.f.body, act, tx, y + h - 30, tw - 60, T.c.text)
  -- pontos do destaque (L1/R1)
  local n = self.featured and #self.featured or 0
  if kind == "featured" and n > 1 then
    for i = 1, math.min(n, 8) do
      G.color(i == self.feat_i and green or T.c.line)
      lg.circle("fill", x + w - 16 - (math.min(n, 8) - i) * 10, y + h - 20, 3)
    end
  end
end

local function draw_tiles(S, self)
  local list = self.xd_tiles
  for i, it in ipairs(list) do
    local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
    local x = RX + c * (TW + TG)
    local y = TY + r * (TH + TG)
    local on = self.xd_zone == "right" and self.xd_right == i
    local fc = T.style.focus or T.c.accent
    G.rect(x + 2, y + 4, TW, TH, T.c.shadow, 6)
    if on then
      for g = 4, 1, -1 do G.frame(x - g * 1.5, y - g * 1.5, TW + g * 3, TH + g * 3, fc, 6 + g * 1.5, 2, 0.08) end
      G.rect(x, y, TW, TH, T.c.green, 6)
    else
      G.rect(x, y, TW, TH, T.c.bg2, 6, 0.95)
      G.frame(x, y, TW, TH, T.c.line, 6, 1)
    end
    local ic = on and T.c.bg0 or T.c.text
    Icons.draw(it.icon, x + TW / 2 - 17, y + 14, ic, 34 / 24)
    local lab = U.upper(I18N.tr(it.label))
    local f, ls, lh = G.fit_lines(T.f.bodyb, lab, TW - 16, 2 * T.base_font(T.f.bodyb):getHeight())
    local ly = y + TH - 10 - #ls * lh
    for k, l in ipairs(ls) do G.text(f, l, x + 10, ly + (k - 1) * lh, ic) end
  end
end

function XD.draw(S, self)
  self.xd_zone = self.xd_zone or "right"
  self.xd_right = self.xd_right or 0
  self.xd_left = self.xd_left or 1
  self.xd_tiles = self.xd_tiles or tiles()
  if not self.xd_recent then self.xd_recent = recent_ports() end
  draw_top(S, self)
  draw_guide(S, self)
  G.text(T.f.h1, U.upper(I18N.tr(L("Início"))), RX, 50, T.c.text)
  draw_hero(S, self)
  draw_tiles(S, self)
  local hints = { { "b", C.OS_MODE and L("Energia") or L("Sair") }, { "a", L("Selecionar") }, { "y", L("Pesquisar") } }
  if require("core.updnotice").pending() then hints[#hints + 1] = { "select", L("Atualizar") } end
  G.hints(hints)
end

--- port focado (destaque ou capa do Guia Rapido)
local function focused_port(S, self)
  if self.xd_zone == "right" and self.xd_right == 0 then return (hero(S, self)) end
  if self.xd_zone == "left" and self.xd_left <= 4 then return (self.xd_recent or {})[self.xd_left] end
  return nil
end

function XD.action(S, self, act)
  self.xd_zone = self.xd_zone or "right"
  self.xd_right = self.xd_right or 0
  self.xd_left = self.xd_left or 1
  local z = self.xd_zone
  if act == "b" then
    if require("core.prefs").get("exit_mode") == "quit" and not C.OS_MODE then App.quit() else S.exit_dialog() end
    return
  elseif act == "select" and require("core.updnotice").pending() then App.push("update"); return
  elseif act == "y" then App.push("search"); return
  elseif act == "l1" or act == "r1" then
    -- troca o destaque do catalogo (sai do "continuar" ate o proximo retorno)
    self.xd_feat = true
    S.feat_go(self, act == "r1" and 1 or -1, true)
    return
  end
  if z == "right" then
    local i = self.xd_right
    if i == 0 then
      if act == "down" then self.xd_right = 1
      elseif act == "left" then self.xd_zone = "left"
      end
    else
      local c, r = (i - 1) % 3, math.floor((i - 1) / 3)
      if act == "up" then self.xd_right = r == 0 and 0 or i - 3
      elseif act == "down" and r == 0 then self.xd_right = i + 3
      elseif act == "left" then
        if c == 0 then self.xd_zone = "left"; self.xd_left = r == 0 and 2 or 5 else self.xd_right = i - 1 end
      elseif act == "right" and c < 2 then self.xd_right = i + 1
      end
    end
  else
    local i = self.xd_left
    if i <= 4 then
      local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
      if act == "left" and c == 1 then self.xd_left = i - 1
      elseif act == "right" then
        if c == 0 then self.xd_left = i + 1 else self.xd_zone = "right"; self.xd_right = r == 0 and 0 or 1 end
      elseif act == "up" and r == 1 then self.xd_left = i - 2
      elseif act == "down" then self.xd_left = r == 0 and i + 2 or 5
      end
    else
      if act == "up" then self.xd_left = i == 5 and 3 or i - 1
      elseif act == "down" and i < 7 then self.xd_left = i + 1
      elseif act == "right" then self.xd_zone = "right"; self.xd_right = 4
      end
    end
  end
  if act == "a" then
    if z == "right" and self.xd_right == 0 then
      local p, kind = hero(S, self)
      if not p then S.open("store")
      elseif kind == "continue" and App.status(p) ~= "none" and not p.builtin then App.launch_port(p)
      else App.push("details", { port = p }) end
    elseif z == "right" then
      S.open(self.xd_tiles[self.xd_right].id)
    elseif self.xd_left <= 4 then
      local p = (self.xd_recent or {})[self.xd_left]
      if p then App.push("details", { port = p }) else S.open("store") end
    else
      S.open(LINKS[self.xd_left - 4].id)
    end
  elseif act == "x" then
    local p = focused_port(S, self)
    if p then App.push("details", { port = p }) end
  end
end

return XD
