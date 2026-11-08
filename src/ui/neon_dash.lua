-- =============================================================================
--  NEON GRID — dashboard da tela inicial (so quando o tema usa layout
--  "dashboard"). Mesmas funcoes do menu classico, outra apresentacao:
--    cabecalho (logo, aviso de versao, Wi-Fi, bateria, data e hora)
--    destaque grande + atalhos em cartoes
--    fileiras de cartoes: jogos recentes e novidades do catalogo
--    painel lateral de navegacao rapida (SELECT abre e fecha)
--  Dados reais apenas: catalogo, registro de instalacao, gamelist.xml do ES.
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
local Favorites = require("core.favorites")
local Compat = require("core.compat")
local lg = love.graphics

local D = {}

-- geometria (640x480)
local HEAD_H = 38
local HERO = { x = 12, y = 46, w = 372, h = 172 }
local TILES = { x = 394, y = 46, w = 234, h = 172, cols = 2, rows = 4 }
local ROW1_Y, ROW2_Y = 226, 334          -- titulo de cada fileira
local CARD_W, CARD_H, CARD_GAP = 60, 80, 9
local ROW_X, ROW_W = 12, 616
local PANEL_W = 236

local SHORTCUTS = {
  { id = "library", label = L("Biblioteca"), icon = "testes_de_controles" },
  { id = "store", label = L("Conteúdo"), icon = "set_store" },
  { id = "installed", label = L("Meus Ports"), icon = "set_myports" },
  { id = "favorites", label = L("Favoritos"), icon = "set_favorites" },
  { id = "categories", label = L("Categorias"), icon = "set_grid" },
  { id = "downloads", label = L("Downloads"), icon = "set_downloads" },
  { id = "settings", label = L("Configurações"), icon = "ferramentas_de_sistema" },
  { id = "about", label = L("Sobre"), icon = "set_about" },
}

local function panel_items()
  local list = {}
  if require("core.updnotice").pending() then
    list[#list + 1] = { id = "update", label = L("Atualizar o hub agora"), icon = "set_updates", hot = true }
  end
  local base = {
    { id = "library", label = L("Biblioteca de jogos"), icon = "testes_de_controles" },
    { id = "store", label = L("Central de Conteúdo"), icon = "set_store" },
    { id = "categories", label = L("Categorias"), icon = "set_grid" },
    { id = "installed", label = L("Meus Ports"), icon = "set_myports" },
    { id = "favorites", label = L("Favoritos"), icon = "set_favorites" },
    { id = "downloads", label = L("Central de Downloads"), icon = "set_downloads" },
    { id = "news", label = L("Novidades"), icon = "news" },
    { id = "themes", label = L("Temas"), icon = "set_appearance" },
    { id = "settings", label = L("Configurações"), icon = "ferramentas_de_sistema" },
    { id = "about", label = L("Sobre o Projeto"), icon = "set_about" },
    { id = "exit", label = C.OS_MODE and L("Energia") or L("Sair"), icon = "set_exit" },
  }
  for _, it in ipairs(base) do list[#list + 1] = it end
  return list
end

-- ---------------------------------------------------------------------------
-- dados das fileiras
-- ---------------------------------------------------------------------------
--- jogos recentes: abertos pela lista de Ports do ES (lastplayed) e
--- instalados pelo hub (data do registro), sem repetir, mais novos primeiro
local function recent_ports()
  local Manifest = require("core.manifest")
  local by_script = {}
  for id, rec in pairs(Manifest.data or {}) do
    if type(rec) == "table" and type(rec.entries) == "table" then
      for _, e in ipairs(rec.entries) do
        if tostring(e):lower():match("%.sh$") then by_script[tostring(e)] = id end
      end
    end
  end
  local seen, list = {}, {}
  local function add(p, key)
    if p and not seen[p.id] then seen[p.id] = true; list[#list + 1] = { p = p, key = key } end
  end
  -- 1) jogados (gamelist.xml da pasta de ports)
  local text = U.read_file(C.PORTS_DIR .. "/gamelist.xml") or ""
  for block in text:gmatch("<game[%s>].-</game>") do
    local lp = block:match("<lastplayed>%s*(%d%d%d%d%d%d%d%dT%d%d%d%d)")
    local path = block:match("<path>%s*%./(.-)%s*</path>")
    if lp and path then
      local id = by_script[path]
      add(id and Catalog.by_id[id], "2" .. lp)
    end
  end
  -- 2) instalados pelo hub (data do registro "AAAA-MM-DD HH:MM")
  for id, rec in pairs(Manifest.data or {}) do
    if type(rec) == "table" and rec.date then
      local k = tostring(rec.date):gsub("[^%d]", "")
      add(Catalog.by_id[id], "1" .. k)
    end
  end
  table.sort(list, function(a, b) return a.key > b.key end)
  local out = {}
  for i = 1, math.min(12, #list) do out[i] = list[i].p end
  return out
end

local function news_ports()
  local out, seen = {}, {}
  local ok, items = pcall(function() return require("core.news").build(App.status) end)
  for _, n in ipairs(ok and items or {}) do
    if not seen[n.port.id] then seen[n.port.id] = true; out[#out + 1] = n.port end
    if #out >= 12 then break end
  end
  return out
end

local function refresh(self)
  self.dash_dirty = false
  self.d_recent = recent_ports()
  self.d_news = news_ports()
  self.d_rsel = U.clamp(self.d_rsel or 1, 1, math.max(1, #self.d_recent))
  self.d_nsel = U.clamp(self.d_nsel or 1, 1, math.max(1, #self.d_news))
  self.d_rtop = self.d_rtop or 0
  self.d_ntop = self.d_ntop or 0
end

local function ensure(self)
  if self.d_zone == nil then
    self.d_zone, self.d_tile = "hero", 1
    self.d_pan, self.d_pan_open, self.d_psel = 0, false, 1
    self.dash_dirty = true
  end
  if self.dash_dirty or not self.d_recent then refresh(self) end
  -- biblioteca: procura os jogos uma vez em segundo plano (contador do atalho)
  local Lib = require("core.library")
  if not Lib.scanned and Lib.state == "idle" and Lib.cfg_path() then Lib.scan() end
end

--- item mostrado na area de destaque: o cartao escolhido nas fileiras,
--- senao o destaque do catalogo
local function hero_item(self)
  local p
  if self.d_zone == "recent" then p = self.d_recent[self.d_rsel]
  elseif self.d_zone == "news" then p = self.d_news[self.d_nsel] end
  if p then return p, "card" end
  return self.featured and self.featured[self.feat_i], "featured"
end

-- ---------------------------------------------------------------------------
-- desenho
-- ---------------------------------------------------------------------------
local function glow_frame(x, y, w, h, c, r)
  local a = App.animations() and App.pulse(0.55, 0.3, 2.4) or 0.8
  G.frame(x - 3, y - 3, w + 6, h + 6, c, (r or 6) + 2, 1, a * 0.45)
  G.frame(x - 1, y - 1, w + 2, h + 2, c, (r or 6) + 1, 2, a)
end

local function state_of(p)
  if p.builtin then return L("Ferramenta do hub"), T.c.accent2 end
  local st = App.status(p)
  if st == "installed" then return L("Instalado"), T.c.green end
  if st == "update" then return L("Atualização disponível"), T.c.yellow end
  return L("Não instalado"), T.c.dim
end

local function draw_header(S, self)
  G.rect(0, 0, T.W, HEAD_H, T.c.bg0, 0, 0.88)
  G.rect(0, HEAD_H, T.W, 1, T.c.line)
  G.rect(0, HEAD_H, 180, 1, T.c.accent, 0, 0.9)
  G.rect(180, HEAD_H, 90, 1, T.c.accent2, 0, 0.6)
  local lw = G.logo(12, 3, "header")
  G.text(T.f.pix8, C.OS_MODE and "R36 HUB OS" or "NEON GRID", 12 + lw + 10, 9, T.c.accent)
  G.text(T.f.pix8, C.VERSION, 12 + lw + 10, 22, T.c.faint)
  -- direita: hora, data, bateria, Wi-Fi
  local Clock = require("core.clock")
  local clock = Clock.time()
  local cf = T.base_font(T.f.bodyb)
  local cw = cf:getWidth(clock)
  G.text(cf, clock, T.W - 12 - cw, 10, T.c.text)
  local wd = ({ L("dom"), L("seg"), L("ter"), L("qua"), L("qui"), L("sex"), L("sáb") })[Clock.wday()]
  local datestr = I18N.tr(wd) .. ", " .. Clock.date(nil, true)
  local dw = T.f.small:getWidth(datestr)
  local dx = T.W - 12 - cw - 10 - dw
  G.text(T.f.small, datestr, dx, 12, T.c.dim)
  local bw = self:draw_battery(11, dx - 12)
  local _, wc, off = S.wifi_state()
  local wx = dx - 12 - bw - 26
  S.wifi_icon(wx, 10, wc, off)
  -- aviso de versao nova (faixa deslizante), entre o nome e o Wi-Fi
  self:draw_update_notice(wx - 10, 12 + lw + 10 + T.f.pix8:getWidth(C.VERSION) + 14, 9)
end

local function draw_hero(S, self)
  local x, y, w, h = HERO.x, HERO.y, HERO.w, HERO.h
  local on = self.d_zone == "hero" and not self.d_pan_open
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  if on then glow_frame(x, y, w, h, T.c.accent, 8) end
  local p, kind = hero_item(self)
  local label = kind == "card" and L("SELECIONADO") or L("EM DESTAQUE")
  G.text(T.f.pix8, label, x + 14, y + 10, kind == "card" and T.c.accent2 or T.c.accent)
  local n = self.featured and #self.featured or 0
  if kind == "featured" and n > 1 then
    local s = self.feat_i .. "/" .. n
    G.text(T.f.pix8, s, x + w - 14 - T.f.pix8:getWidth(s), y + 10, T.c.faint)
  end
  if not p then
    G.text(T.f.body, L("Nenhum destaque no catálogo."), x, y + h / 2 - 8, T.c.dim, "center", w)
    return
  end
  -- troca de destaque: entra com fade curto (leve)
  local a = 1
  if kind == "featured" and self.trans then a = math.min(1, self.trans.t / 0.35) end
  local cw, ch = 105, 140
  local cx, cy = x + 14, y + 24
  G.cover(Covers.get(p), p, cx, cy, cw, ch, Covers.is_loading(p), App.t)
  if a < 1 then G.rect(cx - 1, cy - 1, cw + 4, ch + 5, T.c.bg1, 6, 1 - a) end
  G.frame(cx - 1, cy - 1, cw + 2, ch + 2, S.type_color(p), 6, 1, 0.8)
  -- textos
  local tx, tw = cx + cw + 14, w - cw - 42
  local lines = G.wrap(T.f.h3, p.name, tw)
  local ty = cy - 2
  for i = 1, math.min(2, #lines) do
    G.text(T.f.h3, lines[i], tx, ty, T.c.text); ty = ty + 21
  end
  ty = ty + 4
  local xx = tx
  xx = xx + G.tag(S.is_tool(p) and L("UTILITÁRIO") or L("JOGO"), xx, ty, S.type_color(p), T.c.bg0) + 6
  if (p.platform or "") ~= "" then G.tag(U.upper(p.platform), xx, ty, T.c.bg3, T.c.text) end
  ty = ty + 24
  local info = I18N.tr(p.category) .. ((p.size_label and p.size_label ~= "?") and ("  •  " .. p.size_label) or "")
  G.text_fit(T.f.small, info, tx, ty, tw, T.c.dim)
  ty = ty + 18
  local st, sc = state_of(p)
  G.color(sc); lg.circle("fill", tx + 4, ty + 7, 3.5)
  G.text_fit(T.f.small, st, tx + 13, ty, tw - 13, sc)
  ty = ty + 18
  if not p.builtin then
    local r = Compat.evaluate(p)
    if r then
      local col = T.c[Compat.COLOR[r.status]] or T.c.dim
      G.tag(Compat.LABEL[r.status], tx, ty, col, T.c.bg0)
    end
  end
  if Favorites.is(p) then Icons.draw("set_favorites", cx + cw - 22, cy + 4, T.c.yellow, 0.75) end
  -- L1 / R1 e indicadores (so com mais de um destaque)
  if n > 1 then
    local by = y + h - 18
    G.button_icon("l1", tx, by - 6)
    local rw = T.f.pix8:getWidth("R1") + 10
    G.button_icon("r1", x + w - 14 - rw, by - 6)
    local total = n * 8 + (n - 1) * 4
    local dx = tx + 34 + ((x + w - 14 - rw - 8) - (tx + 34) - total) / 2
    for i = 1, n do
      local c = i == self.feat_i and T.c.accent or T.c.line
      G.rect(dx, by, 8, 4, c, 2)
      dx = dx + 12
    end
  end
end

local function draw_tiles(self)
  local cols, rows = TILES.cols, TILES.rows
  local gap = 8
  local tw = (TILES.w - gap * (cols - 1)) / cols
  local th = (TILES.h - gap * (rows - 1)) / rows
  for i, it in ipairs(SHORTCUTS) do
    local cx = TILES.x + ((i - 1) % cols) * (tw + gap)
    local cy = TILES.y + math.floor((i - 1) / cols) * (th + gap)
    local on = self.d_zone == "tiles" and self.d_tile == i and not self.d_pan_open
    G.rect(cx, cy, tw, th, on and T.c.bg3 or T.c.bg1, 6)
    G.frame(cx, cy, tw, th, on and T.c.accent or T.c.line, 6, 1)
    if on then glow_frame(cx, cy, tw, th, T.c.accent, 6) end
    G.rect(cx, cy + 7, 3, th - 14, on and T.c.accent or T.c.bg3, 1)
    Icons.draw(it.icon, cx + 8, cy + (th - 17) / 2, on and T.c.accent or T.c.dim, 0.7)
    local extra
    if it.id == "favorites" then extra = tostring(Favorites.count())
    elseif it.id == "installed" then extra = tostring(require("core.scan").count)
    elseif it.id == "library" then
      local Lib = require("core.library")
      extra = Lib.scanned and tostring(Lib.total_games()) or nil
    elseif it.id == "downloads" then
      local n = require("core.downloads").waiting_count()
      extra = n > 0 and tostring(n) or nil
    end
    -- contador no canto (nao toma espaco do nome)
    if extra then
      local ew = T.f.pix8:getWidth(extra) + 8
      G.rect(cx + tw - ew - 3, cy + 3, ew, 11, on and T.c.accent or T.c.bg2, 5)
      G.text(T.f.pix8, extra, cx + tw - ew + 1, cy + 5, on and T.c.bg0 or T.c.dim)
    end
    G.text_fit(T.f.small, it.label, cx + 28, cy + (th - T.f.small:getHeight()) / 2 + 2, tw - 32, on and T.c.text or T.c.dim)
  end
end

local function draw_row(self, title, list, ysel, top_key, zone, y, empty)
  local on_zone = self.d_zone == zone and not self.d_pan_open
  G.text(T.f.pix8, title, ROW_X + 2, y, on_zone and T.c.accent or T.c.dim)
  G.rect(ROW_X + T.f.pix8:getWidth(I18N.tr(title)) + 10, y + 4, ROW_W - T.f.pix8:getWidth(I18N.tr(title)) - 12, 1, T.c.line)
  local cy = y + 16
  if #list == 0 then
    G.rect(ROW_X, cy, ROW_W, CARD_H, T.c.bg1, 6, 0.8)
    G.frame(ROW_X, cy, ROW_W, CARD_H, on_zone and T.c.accent or T.c.line, 6, 1)
    G.text(T.f.small, empty, ROW_X, cy + CARD_H / 2 - 7, T.c.dim, "center", ROW_W)
    return
  end
  local vis = math.floor((ROW_W + CARD_GAP) / (CARD_W + CARD_GAP))
  local top = self[top_key] or 0
  if ysel > top + vis then top = ysel - vis end
  if ysel <= top then top = ysel - 1 end
  self[top_key] = top
  for i = top + 1, math.min(#list, top + vis) do
    local p = list[i]
    local cx = ROW_X + (i - top - 1) * (CARD_W + CARD_GAP)
    local on = on_zone and i == ysel
    G.cover(Covers.get(p), p, cx, cy, CARD_W, CARD_H, Covers.is_loading(p), App.t)
    if on then glow_frame(cx, cy, CARD_W, CARD_H, T.c.accent, 6)
    else G.frame(cx, cy, CARD_W, CARD_H, T.c.line, 6, 1) end
    -- selos: instalado (ponto verde) e favorito (estrela)
    local st = App.status(p)
    if st ~= "none" then
      G.rect(cx + 4, cy + CARD_H - 12, 8, 8, T.c.bg0, 4)
      G.color(st == "update" and T.c.yellow or T.c.green); lg.circle("fill", cx + 8, cy + CARD_H - 8, 3)
    end
    if Favorites.is(p) then Icons.draw("set_favorites", cx + CARD_W - 17, cy + 3, T.c.yellow, 0.6) end
  end
  -- setas quando ha mais cartoes
  if top > 0 then G.text(T.f.pix8, "<", ROW_X - 9, cy + CARD_H / 2 - 4, T.c.accent) end
  if top + vis < #list then G.text(T.f.pix8, ">", ROW_X + ROW_W + 1, cy + CARD_H / 2 - 4, T.c.accent) end
end

local function draw_panel(self)
  local k = self.d_pan
  if k <= 0.01 then return end
  G.rect(0, 0, T.W, T.H, T.c.black, 0, 0.55 * k)
  local x = -PANEL_W + PANEL_W * k
  G.rect(x, 0, PANEL_W, T.H, T.c.bg1, 0, 0.97)
  G.rect(x + PANEL_W - 2, 0, 2, T.H, T.c.accent, 0, 0.8)
  G.text(T.f.pix8, L("NAVEGAÇÃO RÁPIDA"), x + 16, 16, T.c.accent)
  local items = panel_items()
  self.d_pitems = items
  self.d_psel = U.clamp(self.d_psel or 1, 1, #items)
  local y = 40
  local rh = math.min(38, math.floor((T.H - 40 - 44) / #items))
  for i, it in ipairs(items) do
    local on = i == self.d_psel
    if on then
      G.rect(x + 8, y, PANEL_W - 18, rh - 4, T.c.bg3, 6)
      G.frame(x + 8, y, PANEL_W - 18, rh - 4, T.c.accent, 6, 1)
    end
    local c = it.hot and T.c.yellow or (on and T.c.accent or T.c.dim)
    Icons.draw(it.icon, x + 16, y + (rh - 4 - 20) / 2, c, 0.83)
    G.text_fit(T.f.body, it.label, x + 46, y + (rh - 4 - T.f.body:getHeight()) / 2, PANEL_W - 64, on and T.c.text or (it.hot and T.c.yellow or T.c.dim))
    y = y + rh
  end
  G.hints({ { "a", L("Abrir") }, { "select", L("Fechar") }, { "b", L("Voltar") } })
end

function D.draw(S, self)
  ensure(self)
  draw_header(S, self)
  draw_hero(S, self)
  draw_tiles(self)
  draw_row(self, L("JOGOS RECENTES"), self.d_recent, self.d_rsel, "d_rtop", "recent", ROW1_Y,
    L("Nenhum jogo recente ainda. Os ports que você instalar ou jogar aparecem aqui."))
  draw_row(self, L("NOVIDADES DO CATÁLOGO"), self.d_news, self.d_nsel, "d_ntop", "news", ROW2_Y,
    L("O catálogo ainda não informa novidades."))
  if self.d_pan > 0.01 then
    draw_panel(self)
    return
  end
  local hints = { { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "select", L("Menu") } }
  if self.d_zone ~= "tiles" then
    hints[#hints + 1] = { "x", L("Favorito") }
    hints[#hints + 1] = { "y", L("Info") }
  end
  hints[#hints + 1] = { "b", C.OS_MODE and L("Energia") or L("Sair") }
  G.hints(hints)
end

function D.update(S, self, dt)
  ensure(self)
  local target = self.d_pan_open and 1 or 0
  if App.animations() then
    self.d_pan = self.d_pan + (target - self.d_pan) * math.min(1, dt * 14)
    if math.abs(self.d_pan - target) < 0.01 then self.d_pan = target end
  else
    self.d_pan = target
  end
end

-- ---------------------------------------------------------------------------
-- controles
-- ---------------------------------------------------------------------------
local function type_name(p) return p.section == "tools" and L("Utilitário") or L("Jogo") end

local function info_dialog(p)
  if not p then return end
  local st = state_of(p)
  local lines = { L("Tipo: ") .. I18N.tr(type_name(p)), L("Categoria: ") .. I18N.tr(p.category) }
  if (p.platform or "") ~= "" then lines[#lines + 1] = L("Plataforma: ") .. p.platform end
  if (p.author or "") ~= "" then lines[#lines + 1] = L("Desenvolvedor: ") .. p.author end
  if p.size_label and p.size_label ~= "?" then lines[#lines + 1] = L("Tamanho: ") .. p.size_label end
  lines[#lines + 1] = L("Estado: ") .. I18N.tr(st)
  if not p.builtin then
    local r = Compat.evaluate(p)
    if r then lines[#lines + 1] = L("Compatibilidade: ") .. I18N.tr(Compat.LABEL[r.status]) end
  end
  App.show_dialog({ title = p.name, kind = "info", body = table.concat(lines, "\n"),
    buttons = { { label = L("DETALHES"), fn = function() App.push("details", { port = p }) end }, { label = L("FECHAR") } } })
end

local function toggle_fav(p)
  if not p or p.builtin then return end
  local on = Favorites.toggle(p)
  App.toast(on and (p.name .. L(" adicionado aos favoritos")) or (p.name .. L(" removido dos favoritos")), "info")
end

local function open_port(p)
  if p then App.push("details", { port = p }) end
end

function D.action(S, self, act)
  ensure(self)
  -- painel lateral
  if self.d_pan_open then
    local items = self.d_pitems or panel_items()
    if act == "select" or act == "b" then self.d_pan_open = false
    elseif act == "up" then self.d_psel = (self.d_psel - 2) % #items + 1
    elseif act == "down" then self.d_psel = self.d_psel % #items + 1
    elseif act == "a" then
      local it = items[self.d_psel]
      self.d_pan_open = false
      if it then S.open(it.id) end
    end
    return
  end
  if act == "select" then
    self.d_pan_open, self.d_psel = true, 1
    return
  end
  if act == "l1" then self:feat_go(-1, true); return end
  if act == "r1" then self:feat_go(1, true); return end
  if act == "b" then
    if require("core.prefs").get("exit_mode") == "quit" and not C.OS_MODE then App.quit() else S.exit_dialog() end
    return
  end
  local z = self.d_zone
  local cols = TILES.cols
  if z == "hero" then
    if act == "right" then self.d_zone, self.d_tile = "tiles", 1
    elseif act == "down" then self.d_zone = #self.d_recent > 0 and "recent" or "news"
    elseif act == "a" then open_port((hero_item(self)))
    elseif act == "x" then toggle_fav((hero_item(self)))
    elseif act == "y" then info_dialog((hero_item(self)))
    end
  elseif z == "tiles" then
    local t = self.d_tile
    local col, row = (t - 1) % cols, math.floor((t - 1) / cols)
    if act == "left" then
      if col == 0 then self.d_zone = "hero" else self.d_tile = t - 1 end
    elseif act == "right" then
      if col < cols - 1 then self.d_tile = t + 1 end
    elseif act == "up" then
      if row > 0 then self.d_tile = t - cols end
    elseif act == "down" then
      if row < TILES.rows - 1 then self.d_tile = t + cols
      else self.d_zone = #self.d_recent > 0 and "recent" or "news" end
    elseif act == "a" then S.open(SHORTCUTS[t].id)
    end
  elseif z == "recent" or z == "news" then
    local list = z == "recent" and self.d_recent or self.d_news
    local key = z == "recent" and "d_rsel" or "d_nsel"
    if act == "left" then self[key] = math.max(1, self[key] - 1)
    elseif act == "right" then self[key] = math.min(math.max(1, #list), self[key] + 1)
    elseif act == "up" then
      if z == "news" then self.d_zone = "recent" else self.d_zone = "hero" end
    elseif act == "down" then
      if z == "recent" then self.d_zone = "news" end
    elseif act == "a" then open_port(list[self[key]])
    elseif act == "x" then toggle_fav(list[self[key]])
    elseif act == "y" then info_dialog(list[self[key]])
    end
  end
end

return D
