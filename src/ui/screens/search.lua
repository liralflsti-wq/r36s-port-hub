-- =============================================================================
--  Pesquisa de ports (jogos e utilitarios) com teclado virtual
--  Busca pelo nome nos dados reais do catalogo; resultados atualizam a cada
--  letra, agrupados por area (Ports de Jogos primeiro, depois Utilitarios).
--  Controles: direcional = teclado | A = digitar | B = apagar letra (vazio: voltar)
--             X = limpar | R1 = ir para os resultados | L1 = voltar ao teclado
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Catalog = require("core.catalog")
local Cats = require("core.categories")
local PortRow = require("ui.portrow")
local Favorites = require("core.favorites")

local S = {}

local KEYS = {
  { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" },
  { "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T" },
  { "U", "V", "W", "X", "Y", "Z", "1", "2", "3", "4" },
  { "5", "6", "7", "8", "9", "0", "ESPAÇO", "APAGAR", "LIMPAR", "VER" },
}
local KW, KH, KX, KY = 60, 30, 20, 318
local RES_Y, ROW_H, VISIBLE = 92, 46, 4

--- texto normalizado: minusculo, sem acentos, so letras/numeros/espaco
local function norm(s)
  s = U.slug(s or ""):gsub("[^%w]", " ")
  return (s:gsub("%s+", " "))
end

function S:enter()
  self.query = ""
  self.kr, self.kc = 1, 1
  self.focus = "keys"
  self.sel, self.scroll = 1, 0
  self:search()
end

function S:resume() self:search(true) end
function S:on_catalog() self:search(true) end

--- Busca real no catalogo (nome). Comeca-com aparece antes de contem.
function S:search(keep)
  local q = norm(self.query):gsub("^%s+", ""):gsub("%s+$", "")
  local res = {}
  if q ~= "" then
    for _, p in ipairs(Catalog.ports) do
      local n = norm(p.name)
      local pos = n:find(q, 1, true)
      if pos then
        res[#res + 1] = { p = p, rank = (pos == 1 or n:sub(pos - 1, pos - 1) == " ") and 0 or 1 }
      end
    end
    local order = { games = 1, tools = 2 }
    table.sort(res, function(a, b)
      local sa, sb = order[a.p.section] or 1, order[b.p.section] or 1
      if sa ~= sb then return sa < sb end
      if a.rank ~= b.rank then return a.rank < b.rank end
      return a.p.name:lower() < b.p.name:lower()
    end)
  end
  self.results = {}
  for _, r in ipairs(res) do self.results[#self.results + 1] = r.p end
  if not keep then self.sel, self.scroll = 1, 0 end
  self:clamp()
end

function S:clamp()
  local n = #self.results
  self.sel = U.clamp(self.sel, 1, math.max(1, n))
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  self.scroll = U.clamp(self.scroll, 0, math.max(0, n - VISIBLE))
  if n == 0 and self.focus == "results" then self.focus = "keys" end
end

function S:draw()
  local games, tools = 0, 0
  for _, p in ipairs(self.results) do if p.section == "tools" then tools = tools + 1 else games = games + 1 end end
  G.header(L("Pesquisar"), self.query ~= "" and string.format(L("%d jogos  •  %d utilitários"), games, tools) or nil)

  -- campo de pesquisa
  local fx, fy, fw = 20, 50, T.W - 40
  G.rect(fx, fy, fw, 34, T.c.bg0, 8)
  G.frame(fx, fy, fw, 34, self.focus == "keys" and T.c.accent2 or T.c.line, 8, 2)
  local shown = self.query ~= "" and self.query or L("Digite o nome do jogo ou utilitário...")
  G.text_fit(T.f.h3, shown, fx + 14, fy + 7, fw - 40, self.query ~= "" and T.c.text or T.c.faint)
  if self.query ~= "" and self.focus == "keys" and math.floor(App.t * 2) % 2 == 0 then
    local cx = fx + 14 + math.min(fw - 40, T.f.h3:getWidth(self.query)) + 2
    G.rect(cx, fy + 8, 2, 18, T.c.accent2)
  end

  -- resultados
  local rh = VISIBLE * ROW_H + 8
  G.panel(12, RES_Y, T.W - 24, rh, { bg = T.c.bg1, border = self.focus == "results" and T.c.accent or T.c.line })
  if self.query == "" then
    G.text(T.f.body, L("Os resultados aparecem aqui enquanto você digita."), 12, RES_Y + rh / 2 - 9, T.c.faint, "center", T.W - 24)
  elseif #self.results == 0 then
    G.text(T.f.pix16, L("NENHUM RESULTADO"), 12, RES_Y + rh / 2 - 22, T.c.dim, "center", T.W - 24)
    G.text(T.f.small, L("Nenhum port com \"") .. self.query .. L("\" no nome."), 12, RES_Y + rh / 2 + 4, T.c.faint, "center", T.W - 24)
  else
    for i = self.scroll + 1, math.min(#self.results, self.scroll + VISIBLE) do
      local p = self.results[i]
      local y = RES_Y + 4 + (i - self.scroll - 1) * ROW_H
      PortRow.draw(p, 16, y, T.W - 32, ROW_H - 4, self.focus == "results" and i == self.sel,
        p.section == "tools" and T.c.green or T.c.accent, { area = true })
    end
    if #self.results > VISIBLE then
      local track = VISIBLE * ROW_H - 4
      local h = math.max(16, track * VISIBLE / #self.results)
      local yy = RES_Y + 6 + (track - h) * (self.scroll / (#self.results - VISIBLE))
      G.rect(T.W - 18, yy, 3, h, T.c.accent2, 1, 0.7)
    end
  end

  -- teclado virtual
  for r, row in ipairs(KEYS) do
    for c, k in ipairs(row) do
      local x, y = KX + (c - 1) * KW, KY + (r - 1) * (KH + 4)
      local on = self.focus == "keys" and r == self.kr and c == self.kc
      local special = #k > 1
      G.rect(x + 2, y, KW - 4, KH, on and T.c.accent2 or (special and T.c.bg3 or T.c.bg2), 6)
      if not on then G.frame(x + 2, y, KW - 4, KH, T.c.line, 6) end
      local f = special and T.f.small or T.f.pix8
      local lbl = require("lib.i18n").tr(k)
      local lw = f:getWidth(lbl)
      if special and lw > KW - 10 then
        -- rotulo traduzido mais longo que a tecla: reduz so a escala horizontal
        local sx = (KW - 10) / lw
        love.graphics.setFont(f)
        G.color(on and T.c.bg0 or T.c.text)
        love.graphics.print(lbl, math.floor(x + KW / 2 - lw * sx / 2), y + 8, 0, sx, 1)
      else
        G.text(f, lbl, x + 2, y + (special and 8 or 11), on and T.c.bg0 or T.c.text, "center", KW - 4)
      end
    end
  end

  if self.focus == "keys" then
    G.hints({ { "a", L("Digitar") }, { "b", L("Apagar") }, { "x", L("Limpar") }, { "r1", L("Resultados") } })
  else
    G.hints({ { "a", L("Detalhes") }, { "select", L("Favorito") }, { "l1", L("Teclado") }, { "b", L("Teclado") } })
  end
end

function S:press_key(k)
  if k == "ESPAÇO" then
    if self.query ~= "" and self.query:sub(-1) ~= " " then self.query = self.query .. " " end
  elseif k == "APAGAR" then
    self.query = self.query:sub(1, -2)
  elseif k == "LIMPAR" then
    self.query = ""
  elseif k == "VER" then
    if #self.results > 0 then self.focus = "results" end
    return
  elseif #self.query < 24 then
    self.query = self.query .. k
  end
  self:search()
end

function S:action(act)
  if self.focus == "keys" then
    if act == "up" then self.kr = (self.kr - 2) % #KEYS + 1
    elseif act == "down" then self.kr = self.kr % #KEYS + 1
    elseif act == "left" then self.kc = (self.kc - 2) % 10 + 1
    elseif act == "right" then self.kc = self.kc % 10 + 1
    elseif act == "a" then self:press_key(KEYS[self.kr][self.kc])
    elseif act == "b" then
      if self.query == "" then App.pop() else self.query = self.query:sub(1, -2); self:search() end
    elseif act == "x" then self.query = ""; self:search()
    elseif act == "y" then self:press_key("ESPAÇO")
    elseif act == "r1" and #self.results > 0 then self.focus = "results"
    end
  else
    local n = #self.results
    if act == "up" then self.sel = math.max(1, self.sel - 1)
    elseif act == "down" then self.sel = math.min(n, self.sel + 1)
    elseif act == "a" and n > 0 then App.push("details", { port = self.results[self.sel] })
    elseif act == "select" and n > 0 then
      local p = self.results[self.sel]
      local on = Favorites.toggle(p)
      App.toast(on and (p.name .. L(" adicionado aos favoritos")) or (p.name .. L(" removido dos favoritos")), "info")
    elseif act == "l1" or act == "b" then self.focus = "keys"
    end
    self:clamp()
  end
end

return S
