-- Catalogo de ports: abas de categoria + lista + pre-visualizacao
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local Compat = require("core.compat")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Catalog = require("core.catalog")
local Covers = require("core.covers")
local Manifest = require("core.manifest")
local Cats = require("core.categories")
local PortRow = require("ui.portrow")
local Favorites = require("core.favorites")
local Tools = require("core.tools")
local Icons = require("ui.icons")

local S = {}

local ROW_H, LIST_Y, LIST_X, LIST_W = 50, 84, 12, 356
local VISIBLE = 7

local BADGE = {
  installed = { L("INSTALADO"), T.c.green },
  update = { L("ATUALIZAR"), T.c.yellow },
}

-- Modos:
--   area (params.section = "games" | "tools"): Todos + categorias da area + Instalados
--   Meus Ports (params.mine = true): abas Jogos | Utilitarios & Ferramentas (so instalados)
-- As duas areas nunca aparecem na mesma listagem.
function S:enter(params)
  self.mine = params.mine and true or false
  self.favs = params.favs and true or false
  self.section = params.section or "games"
  self.filter = params.filter or (self.mine and "installed" or (self.favs and "favs" or "all"))
  self.sel, self.scroll, self.tab_scroll = 1, 0, 0
  Manifest.rescan()
  self:build_tabs()
  self:refresh()
end

function S:build_tabs()
  local tabs = {}
  if self.mine or self.favs then
    for _, sec in ipairs(Cats.SECTIONS) do
      tabs[#tabs + 1] = { id = self.mine and "installed" or "favs", section = sec.id, label = sec.name }
    end
  else
    tabs[1] = { id = "all", section = self.section, label = L("Todos") }
    for _, c in ipairs(Catalog.categories) do
      if c.section == self.section then
        tabs[#tabs + 1] = { id = "cat:" .. c.id, section = self.section, label = c.name }
      end
    end
    tabs[#tabs + 1] = { id = "installed", section = self.section, label = L("Instalados") }
  end
  self.tabs = tabs
  self.tab = 1
  for i, t in ipairs(tabs) do
    if t.id == self.filter and t.section == self.section then self.tab = i end
  end
  self.filter = tabs[self.tab].id
  self.section = tabs[self.tab].section
end

function S:refresh()
  local cur = self.items and self.items[self.sel]
  self.items = {}
  -- ferramentas integradas (Manutencao) primeiro; depois os ports do catalogo
  if not self.mine and not self.favs then
    for _, t in ipairs(Tools.for_filter(self.section, self.filter)) do self.items[#self.items + 1] = t end
  end
  for _, p in ipairs(Catalog.filter(self.filter, App.status, self.section)) do self.items[#self.items + 1] = p end
  self.sel = 1
  if cur then
    for i, p in ipairs(self.items) do if p.id == cur.id then self.sel = i end end
  end
  self:clamp()
end

function S:on_catalog()
  self:build_tabs()
  self:refresh()
end

function S:resume() self:refresh() end

function S:leave() Covers.reset_pending() end

function S:clamp()
  local n = #self.items
  self.sel = U.clamp(self.sel, 1, math.max(1, n))
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  self.scroll = U.clamp(self.scroll, 0, math.max(0, n - VISIBLE))
end

function S:title()
  if self.mine then return L("Meus Ports") end
  if self.favs then return L("Favoritos") end
  return Cats.SECTION_BY_ID[self.section].name
end

function S:color()
  return self.section == "tools" and T.c.green or T.c.accent
end

function S:draw_tabs()
  local f = T.f.bodyb
  local x0, y = 12, 48
  local xs, x = {}, 0
  for i, t in ipairs(self.tabs) do
    local w = f:getWidth(t.label) + 24
    xs[i] = { x, w }
    x = x + w + 6
  end
  -- rolagem horizontal das abas
  local cur = xs[self.tab]
  local view = T.W - 24 - 96
  if cur[1] - self.tab_scroll < 0 then self.tab_scroll = cur[1] end
  if cur[1] + cur[2] - self.tab_scroll > view then self.tab_scroll = cur[1] + cur[2] - view end
  G.clip(x0, y - 2, view + 2, 32)
  for i, t in ipairs(self.tabs) do
    local tx = x0 + xs[i][1] - self.tab_scroll
    local w = xs[i][2]
    local on = i == self.tab
    if on then
      G.rect(tx, y, w, 26, self:color(), 13)
      G.text(f, t.label, tx, y + 4, T.c.bg0, "center", w)
    else
      G.rect(tx, y, w, 26, T.c.bg2, 13)
      G.text(f, t.label, tx, y + 4, T.c.dim, "center", w)
    end
  end
  G.unclip()
  G.button_icon("l1", T.W - 80, y + 5)
  G.button_icon("r1", T.W - 44, y + 5)
end

function S:draw_list()
  local n = #self.items
  if n == 0 then
    G.panel(LIST_X, LIST_Y, T.W - 24, 346, { bg = T.c.bg1 })
    local msg, sub
    local area = Cats.SECTION_BY_ID[self.section].name
    if self.filter == "favs" then
      msg, sub = L("Lista vazia"), L("Nenhum favorito em ") .. area .. L(".\nNa loja, pressione SELECT sobre um port para marcar com a estrela.")
    elseif self.filter == "installed" then
      msg, sub = L("Nada instalado"), L("Nenhum port de ") .. area .. L(" instalado no console.")
    elseif self.filter:sub(1, 4) == "cat:" then
      msg, sub = L("Categoria vazia"), L("Não existem ports disponíveis nesta categoria.")
    else
      msg, sub = L("Nenhum port ainda"), L("Não existem ports disponíveis em ") .. area .. L(".\nEles aparecem aqui quando o catálogo for atualizado (Configurações).")
    end
    G.text(T.f.pix16, U.upper(msg), LIST_X, LIST_Y + 130, T.c.dim, "center", T.W - 24)
    G.text(T.f.body, sub, LIST_X + 20, LIST_Y + 162, T.c.faint, "center", T.W - 64)
    return
  end
  G.panel(LIST_X, LIST_Y, LIST_W, VISIBLE * ROW_H + 8, { bg = T.c.bg1 })
  for i = self.scroll + 1, math.min(n, self.scroll + VISIBLE) do
    local p = self.items[i]
    local y = LIST_Y + 4 + (i - self.scroll - 1) * ROW_H
    PortRow.draw(p, LIST_X + 4, y, LIST_W - 8, ROW_H - 4, i == self.sel, T.c.accent)
  end
  -- barra de rolagem
  if n > VISIBLE then
    local track = VISIBLE * ROW_H - 4
    local h = math.max(20, track * VISIBLE / n)
    local yy = LIST_Y + 6 + (track - h) * (self.scroll / (n - VISIBLE))
    G.rect(LIST_X + LIST_W - 4, yy, 3, h, T.c.accent2, 1, 0.7)
  end
end

function S:draw_preview()
  local p = self.items[self.sel]
  if not p then return end
  local px, py, pw, ph = 380, LIST_Y, 248, VISIBLE * ROW_H + 8
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  local cw, ch = 150, 200
  if p.builtin then
    G.rect(px + (pw - cw) / 2, py + 12, cw, ch, T.c.bg0, 10)
    G.frame(px + (pw - cw) / 2, py + 12, cw, ch, T.c.green, 10, 2)
    Icons.draw(p.icon, px + pw / 2 - 36, py + 70, T.c.green, 3)
    G.text(T.f.pix8, L("INTEGRADO"), px, py + ch - 14, T.c.green, "center", pw)
  else
    G.cover(Covers.get(p), p, px + (pw - cw) / 2, py + 12, cw, ch, Covers.is_loading(p), App.t)
  end
  local y = py + ch + 22
  G.text_fit(T.f.h3, p.name, px + 14, y, pw - 28, T.c.text)
  y = y + 24
  local tw = G.tag(U.upper(p.category), px + 14, y, T.c.accent2, T.c.bg0)
  if p.version ~= "" then G.tag("v" .. p.version, px + 20 + tw, y, T.c.bg3, T.c.dim) end
  y = y + 26
  local short = Catalog.text(p, "short")
  local lines = G.wrap(T.f.small, short ~= "" and short or L("Sem descrição."), pw - 28)
  for i = 1, math.min(3, #lines) do
    G.text(T.f.small, lines[i] .. ((i == 3 and #lines > 3) and "…" or ""), px + 14, y, T.c.dim)
    y = y + 15
  end
  -- compatibilidade do port em foco (resultado em cache; nada pesado aqui)
  if not p.builtin then
    local r = Compat.evaluate(p)
    if r then
      local col = T.c[Compat.COLOR[r.status]] or T.c.dim
      local label = Compat.LABEL[r.status]
      local tw = T.f.pix8:getWidth(I18N.tr(label)) + 12
      G.tag(label, px + (pw - tw) / 2, py + ph - 26, col, T.c.bg0)
    end
  end
end

function S:draw()
  local right = string.format(L("%d de %d"), #self.items > 0 and self.sel or 0, #self.items)
  G.header(self:title(), right)
  self:draw_tabs()
  self:draw_list()
  self:draw_preview()
  local tabword = (self.mine or self.favs) and L("Área") or L("Categoria")
  if self.filter == "installed" then
    G.hints({ { "a", L("Detalhes") }, { "x", L("Desinstalar") }, { "select", L("Favorito") }, { "b", L("Voltar") }, { "l1", "" }, { "r1", tabword } })
  else
    local cur = self.items[self.sel]
    G.hints({ { "a", (cur and cur.builtin) and L("Abrir") or L("Ver detalhes") }, { "select", L("Favorito") }, { "b", L("Voltar") }, { "l1", "" }, { "r1", tabword }, { "y", L("Atualizar") } })
  end
end

function S:switch_tab(d)
  self.tab = (self.tab - 1 + d) % #self.tabs + 1
  self.filter = self.tabs[self.tab].id
  self.section = self.tabs[self.tab].section
  self.sel, self.scroll = 1, 0
  Covers.reset_pending()
  self:refresh()
end

function S:action(act)
  local n = #self.items
  if act == "up" and n > 0 then self.sel = (self.sel - 2) % n + 1; self:clamp()
  elseif act == "down" and n > 0 then self.sel = self.sel % n + 1; self:clamp()
  elseif act == "right" and n > 0 then self.sel = math.min(n, self.sel + VISIBLE); self:clamp()
  elseif act == "left" and n > 0 then self.sel = math.max(1, self.sel - VISIBLE); self:clamp()
  elseif act == "l1" then self:switch_tab(-1)
  elseif act == "r1" then self:switch_tab(1)
  elseif act == "a" and n > 0 and self.items[self.sel].builtin then App.push(self.items[self.sel].screen, { from = "store" })
  elseif act == "a" and n > 0 then App.push("details", { port = self.items[self.sel] })
  elseif act == "b" then App.pop()
  elseif act == "select" and n > 0 and self.items[self.sel].builtin then
    App.toast(L("Ferramentas integradas já ficam sempre aqui, em Manutenção."), "info")
  elseif act == "select" and n > 0 then
    local p = self.items[self.sel]
    local on = Favorites.toggle(p)
    App.toast(on and (p.name .. L(" adicionado aos favoritos")) or (p.name .. L(" removido dos favoritos")), "info")
    if self.favs then self:refresh() end
  elseif act == "x" and self.filter == "installed" and n > 0 then
    App.ask_uninstall(self.items[self.sel])
  elseif act == "y" then
    App.toast(L("Atualizando catálogo..."), "info")
    App.refresh_catalog(true)
  end
end

return S
