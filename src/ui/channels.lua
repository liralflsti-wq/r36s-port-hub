-- =============================================================================
--  Tela inicial em CANAIS (layout "channels": Wii Blue Edition e Neon Grid
--  Edition). Mesmas funcoes do menu classico, organizadas como o menu de
--  canais do Wii: grade 3x3 de cartoes com icone, nome e um resumo real.
--  A aparencia (cartao claro/escuro, halo azul ou contorno neon) vem do tema
--  (ui/gfx.lua: G.card). Nenhuma logica propria: as acoes sao as do menu.
--    cima/baixo/esquerda/direita: navegar | A: abrir | B: sair/energia
--    SELECT: atualizar o hub (quando ha versao nova) | L1/R1: trocar o destaque
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

local CH = {}

local COLS, ROWS = 3, 3
local GX, GY, CW, CHH, GAPX, GAPY = 18, 70, 192, 108, 11, 9

local function items()
  return {
    { id = "store", label = L("Central de Conteúdo"), icon = "set_store" },
    { id = "library", label = L("Biblioteca de jogos"), icon = "games" },
    { id = "categories", label = L("Categorias"), icon = "set_grid" },
    { id = "installed", label = L("Meus Ports"), icon = "set_myports" },
    { id = "favorites", label = L("Favoritos"), icon = "set_favorites" },
    { id = "downloads", label = L("Downloads"), icon = "download" },
    { id = "settings", label = L("Configurações"), icon = "settings" },
    { id = "about", label = L("Sobre o Projeto"), icon = "set_about" },
    { id = "exit", label = C.OS_MODE and L("Energia") or L("Sair"), icon = "set_exit" },
  }
end

--- resumo real de cada canal (texto pequeno embaixo do nome)
local function summary(id)
  if id == "store" then
    if Catalog.remote_state == "loading" then return L("Sincronizando catálogo...") end
    return string.format(L("%d ports  •  %d categorias"), #Catalog.ports, #Catalog.categories)
  elseif id == "library" then
    return L("Jogos dos emuladores")
  elseif id == "categories" then
    return L("Navegue por gênero")
  elseif id == "installed" then
    return string.format(L("%d no console"), require("core.scan").count or 0)
  elseif id == "favorites" then
    local n = require("core.favorites").count()
    return n == 1 and L("1 favorito") or string.format(L("%d favoritos"), n)
  elseif id == "downloads" then
    local D = require("core.downloads")
    local n = (D.active() and 1 or 0) + D.waiting_count()
    if n > 0 then return string.format(L("%d em andamento"), n) end
    return L("Atalho: START")
  elseif id == "settings" then
    return L("Aparência, rede, sistema")
  elseif id == "about" then
    return L("Créditos e avisos")
  elseif id == "exit" then
    return C.OS_MODE and L("Desligar ou reiniciar") or L("Voltar ao EmulationStation")
  end
  return ""
end

-- entrada dos canais: cada cartao sobe alguns pixels, um apos o outro (0,4 s)
local ENTER, STAGGER, RISE = 0.22, 0.025, 14
function CH.update(S, self, dt)
  if self.ch_t then
    self.ch_t = self.ch_t + dt
    if self.ch_t > ENTER + STAGGER * 9 then self.ch_t = nil end
  end
end

local function rise(self, i)
  if not self.ch_t or not App.animations() then return 0 end
  local k = math.max(0, math.min(1, (self.ch_t - (i - 1) * STAGGER) / ENTER))
  return RISE * (1 - k) ^ 3
end

-- ---------------------------------------------------------------------------
local function draw_top(S, self)
  -- logo + tema + versao
  G.logo(14, 8, "header")
  local Themes = require("core.themes")
  local th = Themes.by_id and Themes.by_id[Themes.current]
  local name = th and U.upper(th.name) or ""
  G.text(T.f.pix8, name, 70, 14, T.c.accent)
  G.text(T.f.pix8, C.OS_MODE and (C.OS_NAME .. " " .. C.OS_VERSION) or C.VERSION, 70, 28, T.c.faint)
  -- data e hora
  local Clock = require("core.clock")
  local clock = Clock.time()
  local wd = ({ L("dom"), L("seg"), L("ter"), L("qua"), L("qui"), L("sex"), L("sáb") })[Clock.wday()]
  local datestr = wd .. ", " .. Clock.date(nil, true)
  local cf = T.base_font(T.f.h2)
  local cw = cf:getWidth(clock)
  G.text(cf, clock, T.W - 16 - cw, 8, T.c.text)
  G.text(T.f.small, datestr, T.W - 16 - T.f.small:getWidth(datestr), 36, T.c.dim)
  -- aviso de versao nova (faixa deslizante entre o tema e o relogio)
  local nx = 70 + math.max(T.f.pix8:getWidth(I18N.tr(name)), 90) + 14
  S.draw_update_notice(self, T.W - 16 - math.max(cw, T.f.small:getWidth(datestr)) - 12, nx, 14)
end

local function draw_card(self, i, it)
  local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
  local x, y = GX + c * (CW + GAPX), GY + r * (CHH + GAPY) + rise(self, i)
  local on = i == self.ch_sel
  local k = G.focus_k("ch" .. i, on)
  local pal, cx, cy, cw, chh = G.card(x, y, CW, CHH, on, k, 12)
  -- icone (o do canal da Central mostra a capa do destaque, quando houver)
  local feat = it.id == "store" and self.featured and self.featured[self.feat_i]
  if feat then
    local img = Covers.get(feat)
    local iw, ih = 44, 58
    G.cover(img, feat, cx + 14, cy + 10, iw, ih, Covers.is_loading(feat), App.t)
    G.text_fit(T.f.pix8, L("EM DESTAQUE"), cx + 68, cy + 16, cw - 80, pal.icon)
    local f, ls = G.fit_lines(T.f.small, feat.name, cw - 80, 32, true)
    for li, l in ipairs(ls) do G.text(f, l, cx + 68, cy + 30 + (li - 1) * 15, pal.dim) end
  else
    local isz = 44 + 4 * k
    Icons.draw(it.icon, cx + (cw - isz) / 2, cy + 12 - 2 * k, pal.icon, isz / 24)
  end
  local ty = cy + chh - 44
  G.text(T.f.h3, it.label, cx + 8, ty, pal.text, "center", cw - 16)
  local f = T.f.small
  local sub = summary(it.id)
  local sw = f:getWidth(I18N.tr(sub))
  if sw > cw - 16 then
    G.text_fit(f, sub, cx + 8, ty + 21, cw - 16, pal.dim)
  else
    G.text(f, sub, cx + (cw - sw) / 2, ty + 21, pal.dim)
  end
  -- selo de downloads em andamento
  if it.id == "downloads" then
    local D = require("core.downloads")
    local n = (D.active() and 1 or 0) + D.waiting_count()
    if n > 0 then
      local s = tostring(n)
      local bw = T.f.pix8:getWidth(s) + 12
      G.rect(cx + cw - bw - 8, cy + 8, bw, 16, T.c.accent, 8)
      G.text(T.f.pix8, s, cx + cw - bw - 2, cy + 12, T.c.bg0)
    end
  end
end

local function draw_bottom(S, self)
  -- linha de estado do catalogo e do armazenamento (dados reais)
  local y = GY + ROWS * (CHH + GAPY) + 2
  local online = Catalog.source == "online"
  local dot = Catalog.remote_state == "loading" and T.c.yellow or (online and T.c.green or T.c.orange)
  local st = Catalog.remote_state == "loading" and L("Sincronizando catálogo...") or Catalog.source_label()
  local free = App.free and (U.format_bytes(App.free) .. L(" livres")) or L("Espaço livre: desconhecido")
  local line = I18N.tr(st) .. "   •   " .. I18N.tr(free)
  local f = T.f.small
  local w = f:getWidth(line) + 14
  local x = (T.W - w) / 2
  G.color(dot); lg.circle("fill", x + 4, y + f:getHeight() / 2 + 1, 3.5)
  G.text_fit(f, line, x + 14, y, T.W - 40, T.c.dim)
end

function CH.draw(S, self)
  self.ch_sel = self.ch_sel or 1
  self.ch_items = self.ch_items or items()
  draw_top(S, self)
  for i, it in ipairs(self.ch_items) do draw_card(self, i, it) end
  draw_bottom(S, self)
  -- deixa a capa do proximo destaque pronta
  local n = self.featured and #self.featured or 0
  if n > 1 then Covers.get(self.featured[self.feat_i % n + 1]) end
  local hints = { { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "b", C.OS_MODE and L("Energia") or L("Sair") } }
  if n > 1 then hints[#hints + 1] = { "l1", L("Destaque") } end
  if require("core.updnotice").pending() then hints[#hints + 1] = { "select", L("Atualizar") } end
  if G.hints_width(hints, T.f.small) + 24 > S.wifi_left(self) then
    T.with_base_fonts(function() G.hints(hints); S.draw_wifi(self) end)
  else
    G.hints(hints)
    S.draw_wifi(self)
  end
end

function CH.action(S, self, act)
  self.ch_sel = self.ch_sel or 1
  local n = #(self.ch_items or items())
  local i = self.ch_sel
  local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
  if act == "left" then c = (c - 1) % COLS
  elseif act == "right" then c = (c + 1) % COLS
  elseif act == "up" then r = (r - 1) % ROWS
  elseif act == "down" then r = (r + 1) % ROWS
  elseif act == "a" then
    S.open(self.ch_items[i].id)
    return
  elseif act == "b" then
    if require("core.prefs").get("exit_mode") == "quit" and not C.OS_MODE then App.quit() else S.exit_dialog() end
    return
  elseif act == "select" and require("core.updnotice").pending() then App.push("update"); return
  elseif act == "l1" then self:feat_go(-1, true); return
  elseif act == "r1" then self:feat_go(1, true); return
  else return end
  self.ch_sel = math.min(n, r * COLS + c + 1)
end

-- usados tambem pelo carrossel (ui/carousel.lua)
CH.items, CH.summary = items, summary

--- troca de idioma: refaz os nomes dos canais
function CH.reset(self) self.ch_items = nil end

return CH
