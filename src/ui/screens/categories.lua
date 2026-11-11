-- Categorias: dois grupos (Ports de Jogos | Utilitarios & Ferramentas) com icones.
-- Cada bloco e um filtro real do catalogo (abre a loja da area naquela categoria).
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Catalog = require("core.catalog")
local Cats = require("core.categories")
local Icons = require("ui.icons")
local Tools = require("core.tools")

local S = {}
local COLS, TW, TH, GAP, X0 = 3, 196, 50, 8, 15
local HEADER_H = 26
local VIEW_Y, VIEW_H = 48, 392   -- area rolavel (entre o cabecalho e o rodape)

local COLOR = { games = T.c.accent, tools = T.c.green }

function S:enter()
  self.sel, self.scroll = 1, 0
  self:on_catalog()
end

--- monta a grade: cabecalho de cada area + blocos (posicao y no conteudo)
function S:on_catalog()
  local tiles, heads = {}, {}
  local y = 0
  for _, sec in ipairs(Cats.SECTIONS) do
    heads[#heads + 1] = { y = y, section = sec }
    y = y + HEADER_H
    local i = 0
    for _, c in ipairs(Catalog.categories) do
      if c.section == sec.id then
        local col = i % COLS
        local row = math.floor(i / COLS)
        tiles[#tiles + 1] = { cat = c, section = sec.id, col = col, y = y + row * (TH + GAP) }
        i = i + 1
      end
    end
    y = y + math.ceil(i / COLS) * (TH + GAP) + 10
  end
  self.tiles, self.heads, self.content_h = tiles, heads, y
  self.sel = U.clamp(self.sel or 1, 1, math.max(1, #tiles))
  self:follow()
end

function S:follow()
  local t = self.tiles[self.sel]
  if not t then return end
  -- limites da area do bloco selecionado (titulo + todos os blocos)
  local sec_top, sec_bot = nil, 0
  for _, h in ipairs(self.heads) do if h.section.id == t.section then sec_top = h.y end end
  for _, o in ipairs(self.tiles) do if o.section == t.section then sec_bot = math.max(sec_bot, o.y + TH) end end
  if sec_top and sec_bot - sec_top <= VIEW_H then
    -- a area inteira cabe: mostra ela toda
    if sec_bot > self.scroll + VIEW_H then self.scroll = sec_bot - VIEW_H end
    if sec_top < self.scroll then self.scroll = sec_top end
  else
    local top = t.y
    for _, h in ipairs(self.heads) do if h.y + HEADER_H == t.y then top = h.y end end
    if top < self.scroll then self.scroll = top end
    if t.y + TH > self.scroll + VIEW_H then self.scroll = t.y + TH - VIEW_H end
  end
  self.scroll = U.clamp(self.scroll, 0, math.max(0, self.content_h - VIEW_H))
end

function S:draw()
  local total = 0
  for _, c in ipairs(Catalog.categories) do if c.count > 0 then total = total + 1 end end
  G.header(L("Categorias"), string.format(L("%d com ports"), total))
  G.clip(0, VIEW_Y, T.W, VIEW_H)
  local oy = VIEW_Y - self.scroll
  for _, h in ipairs(self.heads) do
    local c = COLOR[h.section.id]
    local yy = oy + h.y + 4
    Icons.draw(h.section.id, X0, yy - 2, c, 0.75)
    G.text(T.f.pix8, U.upper(h.section.name), X0 + 24, yy + 3, c)
    G.rect(X0 + 30 + T.f.pix8:getWidth(U.upper(h.section.name)), yy + 7, T.W - 2 * X0 - 30 - T.f.pix8:getWidth(U.upper(h.section.name)), 1, c, 0, 0.5)
  end
  for i, t in ipairs(self.tiles) do
    local x = X0 + t.col * (TW + GAP)
    local y = oy + t.y
    if y + TH >= VIEW_Y and y <= VIEW_Y + VIEW_H then
      local on = i == self.sel
      local c = COLOR[t.section]
      local tools = #Tools.for_filter(t.section, "cat:" .. t.cat.id)
      local empty = t.cat.count == 0 and tools == 0
      local pal, cx, cy, cw, ch = G.card(x, y, TW, TH, on, G.focus_k("cat" .. i, on), 8)
      local cc = G.ink(c, pal)
      -- utilitarios: borda tracejada a esquerda para diferenciar dos jogos
      if t.section == "tools" then
        for k = 0, ch - 8, 6 do G.rect(cx, cy + 4 + k, 4, 3, cc, 0, on and 1 or 0.6) end
      else
        G.rect(cx, cy + 4, 4, ch - 8, cc, 2, on and 1 or 0.6)
      end
      Icons.draw(t.cat.icon, cx + 12, cy + 9, (empty and not on) and pal.faint or (on and pal.icon or cc), 32 / 24)
      local nf = T.f.bodyb:getWidth(t.cat.name) <= cw - 58 and T.f.bodyb or T.f.small
      G.text_fit(nf, t.cat.name, cx + 52, cy + (nf == T.f.bodyb and 8 or 10), cw - 60, (empty and not on) and pal.faint or pal.text)
      local label = empty and L("VAZIA") or string.format(t.cat.count == 1 and L("%d PORT") or L("%d PORTS"), t.cat.count)
      if tools > 0 then label = (t.cat.count > 0 and (label .. " + ") or "") .. tools .. L(" FERRAM.") end
      G.text(T.f.pix8, label, cx + 52, cy + 31, empty and pal.faint or cc)
    end
  end
  G.unclip()
  if self.content_h > VIEW_H then
    local h = math.max(20, VIEW_H * VIEW_H / self.content_h)
    local yy = VIEW_Y + (VIEW_H - h) * (self.scroll / (self.content_h - VIEW_H))
    G.rect(T.W - 6, yy, 3, h, T.c.accent2, 1, 0.7)
  end
  G.hints({ { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "b", L("Voltar") } })
end

--- move para o bloco mais proximo na direcao vertical (atravessa as areas)
function S:vertical(dir)
  local cur = self.tiles[self.sel]
  local best, bestd
  for i, t in ipairs(self.tiles) do
    local dy = (t.y - cur.y) * dir
    if dy > 0 then
      local d = dy * 10 + math.abs(t.col - cur.col)
      if not bestd or d < bestd then best, bestd = i, d end
    end
  end
  if best then self.sel = best end
end

function S:action(act)
  local n = #self.tiles
  if n == 0 then if act == "b" then App.pop() end return end
  if act == "left" then self.sel = math.max(1, self.sel - 1)
  elseif act == "right" then self.sel = math.min(n, self.sel + 1)
  elseif act == "up" then self:vertical(-1)
  elseif act == "down" then self:vertical(1)
  elseif act == "a" then
    local t = self.tiles[self.sel]
    App.push("store", { section = t.section, filter = "cat:" .. t.cat.id })
  elseif act == "b" then App.pop()
  end
  self:follow()
end

return S
