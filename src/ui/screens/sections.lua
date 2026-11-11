-- Central de Conteudo (antiga Loja de Ports): Ports de Jogos | BIOS do Sistema |
-- Ports Utilitarios e Ferramentas, mais os atalhos (pesquisa, favoritos, novidades, downloads).
-- Os ids internos continuam os mesmos ("store", "games", "tools").
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Catalog = require("core.catalog")
local Cats = require("core.categories")
local Icons = require("ui.icons")
local Favorites = require("core.favorites")
local Downloads = require("core.downloads")
local News = require("core.news")
local Tools = require("core.tools")

local S = {}

local INFO = {
  games = { color = T.c.accent, desc = L("Jogos portados para o R36S. Detalhes, download e instalação.") },
  bios = { color = T.c.yellow, desc = L("Downloads, verificação e instalação de BIOS para emuladores.") },
  tools = { color = T.c.green, desc = L("Ports utilitários, manutenção, diagnóstico, testes de controles e ferramentas do sistema.") },
}

-- cartoes da Central (BIOS nao e uma secao do catalogo: tem tela propria)
local function cards()
  local out = {}
  for _, sec in ipairs(Cats.SECTIONS) do
    out[#out + 1] = { id = sec.id, name = sec.name }
    if sec.id == "games" then out[#out + 1] = { id = "bios", name = L("BIOS do Sistema") } end
  end
  return out
end

-- atalhos (linha de baixo)
local SHORTCUTS = {
  { id = "search", label = L("Pesquisar"), icon = "search" },
  { id = "favs", label = L("Favoritos"), icon = "set_favorites" },
  { id = "news", label = L("Novidades"), icon = "news" },
  { id = "downloads", label = L("Downloads"), icon = "download" },
}
local function shortcuts() return SHORTCUTS end

function S:enter()
  self.row = self.row or 1   -- 1 = areas, 2 = atalhos
  self.sel = self.sel or 1
  self.sc = self.sc or 1
end

local function count(section)
  local n = 0
  for _, p in ipairs(Catalog.ports) do if p.section == section then n = n + 1 end end
  return n
end

function S:shortcut_info(id)
  if id == "search" then return string.format(L("%d ports"), #Catalog.ports) end
  if id == "favs" then local n = Favorites.count(); return n == 0 and "nenhum" or (n .. L(" marcado") .. (n == 1 and "" or "s")) end
  if id == "news" then local n = News.count(App.status); return n == 0 and L("nenhuma") or tostring(n) end
  if id == "downloads" then
    local a = Downloads.active()
    if a then
      local p = Downloads.percent(a)
      return p and (L("baixando ") .. p .. "%") or L("em andamento")
    end
    local w = Downloads.waiting_count()
    return w > 0 and (w .. L(" na fila")) or L("nada em andamento")
  end
  return ""
end

--- resumo das BIOS para o cartao (estado real; sem verificar, diz isso)
function S:bios_label()
  local Bios = require("core.bios")
  if not Bios.scan() then return L("NÃO VERIFICADO"), T.c.faint end
  local n = Bios.summary()
  local miss = (n.missing or 0)
  if miss == 0 and (n.error or 0) == 0 and (n.incompatible or 0) == 0 then
    return string.format(L("%d COM BIOS"), n.installed or 0), T.c.green
  end
  return string.format(L("%d OK  •  %d AUSENTES"), n.installed or 0, miss), T.c.yellow
end

function S:draw()
  G.header(L("Central de Conteúdo"))
  G.text_fit(T.f.small, L("Ports de Jogos, BIOS, Ports Utilitários e Ferramentas"),
    math.max(14, (T.W - T.f.small:getWidth(require("lib.i18n").tr(L("Ports de Jogos, BIOS, Ports Utilitários e Ferramentas")))) / 2), 47, T.W - 28, T.c.dim)
  local list = cards()
  local gap = 12
  local w = math.floor((T.W - 28 - gap * (#list - 1)) / #list)
  local h = 236
  local x0 = 14
  if self.sel > #list then self.sel = #list end
  for i, card in ipairs(list) do
    local x, y = x0 + (i - 1) * (w + gap), 68
    local on = self.row == 1 and i == self.sel
    local pal, cx, cy, cw, chh = G.card(x, y, w, h, on, G.focus_k("sec" .. i, on), 12)
    local c = G.ink(INFO[card.id].color, pal)
    G.rect(cx, cy, cw, 6, c, 3, on and 1 or 0.5)
    Icons.draw(card.id, cx + cw / 2 - 28, cy + 16, on and pal.icon or c, 56 / 24)
    -- nome (ate 2 linhas) e descricao: diminuem ou sao encurtados para caber no cartao
    local nf, nl, nlh = G.fit_lines(T.f.h3, card.name, cw - 20, 2 * T.base_font(T.f.h3):getHeight() + 6)
    local ny = cy + 80
    for k, l in ipairs(nl) do G.text(nf, l, cx + 10, ny + (k - 1) * nlh, pal.text, "center", cw - 20) end
    local dy = ny + #nl * nlh + 6
    local df, dl, dlh = G.fit_lines(T.f.small, INFO[card.id].desc, cw - 20, cy + chh - 47 - dy, true)
    for k, l in ipairs(dl) do G.text(df, l, cx + 10, dy + (k - 1) * dlh, pal.dim, "center", cw - 20) end
    local label, lc
    if card.id == "bios" then
      label, lc = self:bios_label()
      lc = G.ink(lc or c, pal)
    else
      local n = count(card.id)
      label = n == 0 and L("NENHUM PORT AINDA") or string.format(n == 1 and L("%d PORT") or L("%d PORTS"), n)
      lc = n == 0 and pal.faint or c
    end
    local lf = T.f.pix8:getWidth(require("lib.i18n").tr(label)) <= cw - 12 and T.f.pix8 or T.f.small
    G.text_fit(lf, label, cx + math.max(6, (cw - lf:getWidth(require("lib.i18n").tr(label))) / 2), cy + chh - 42, cw - 12, lc)
    if on then
      G.button_icon("a", cx + cw / 2 - 34, cy + chh - 26)
      G.text(T.f.small, L("Entrar"), cx + cw / 2 - 12, cy + chh - 25, pal.text)
    end
  end
  -- atalhos
  local list = shortcuts()
  local sgap, sh = 10, 92
  local sw = math.floor((145 * 4 + sgap * 3 - sgap * (#list - 1)) / #list)
  local sx0 = (T.W - (sw * #list + sgap * (#list - 1))) / 2
  if self.sc > #list then self.sc = #list end
  for i, sc in ipairs(list) do
    local x, y = sx0 + (i - 1) * (sw + sgap), 314
    local on = self.row == 2 and i == self.sc
    local pal
    pal, x, y, sw, sh = G.card(x, y, sw, sh, on, G.focus_k("secs" .. i, on), 10)
    Icons.draw(sc.icon, x + sw / 2 - 14, y + 10, pal.icon, 28 / 24)
    G.text(T.f.bodyb, sc.label, x, y + 42, pal.text, "center", sw)
    G.text_fit(T.f.small, self:shortcut_info(sc.id), x + 8 + math.max(0, (sw - 16 - T.f.small:getWidth(self:shortcut_info(sc.id))) / 2), y + 64, sw - 16, pal.dim)
  end
  G.hints({ { "dpad", L("Navegar") }, { "a", L("Entrar") }, { "b", L("Voltar") } })
end

function S:action(act)
  if act == "up" then self.row = 1
  elseif act == "down" then self.row = 2
  elseif act == "left" then
    if self.row == 1 then self.sel = math.max(1, self.sel - 1) else self.sc = math.max(1, self.sc - 1) end
  elseif act == "right" then
    if self.row == 1 then self.sel = math.min(#cards(), self.sel + 1) else self.sc = math.min(#shortcuts(), self.sc + 1) end
  elseif act == "a" then
    if self.row == 1 then
      local card = cards()[self.sel]
      if card.id == "bios" then App.push("bios")
      else App.push("store", { section = card.id, filter = "all" }) end
    else
      local id = shortcuts()[self.sc].id
      if id == "search" then App.push("search")
      elseif id == "favs" then App.push("store", { favs = true })
      elseif id == "news" then App.push("news")
      elseif id == "downloads" then App.open_downloads(false)
      end
    end
  elseif act == "b" then App.pop()
  end
end

return S
