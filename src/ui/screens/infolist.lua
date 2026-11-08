-- =============================================================================
--  Lista de informacoes (uso geral das Configuracoes): diagnostico, espaco dos
--  ports, historico de erros de rede, repositorios, modulos do hub, backups...
--  params = {
--    title=, sub=, empty=, items = { { tag=, tagc=, text=, sub=, detail= } },
--    load = function(scr) ... end   -- opcional: preenche scr.items (pode ser
--                                     -- assincrono: scr.loading = "texto")
--    keys = { { key = "y", label = "...", fn = function(scr, item) end } },
--  }
--  A: detalhes do item (se houver) | B: voltar | teclas extras no rodape
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")

local S = {}
local TOP, BOTTOM = 50, 436

function S:enter(p)
  self.p = p or {}
  self.sel, self.scroll = 1, 0
  self.items = self.p.items or {}
  self.loading = nil
  if self.p.load then self.p.load(self) end
end

function S:resume() if self.p.reload_on_resume and self.p.load then self.p.load(self) end end

local function row_h() return math.max(42, G.step(T.f.body, 22) + G.step(T.f.small, 16) + 8) end

function S:visible() return math.max(1, math.floor((BOTTOM - TOP) / row_h())) end

function S:draw()
  G.header(self.p.title or "", self.p.sub and (type(self.p.sub) == "function" and self.p.sub(self) or self.p.sub) or nil)
  local rh = row_h()
  if self.loading then
    G.text(T.f.h3, self.loading, 0, 190, T.c.yellow, "center", T.W)
    G.progress_busy(140, 230, T.W - 280, 8, App.t, T.c.yellow)
  elseif #self.items == 0 then
    G.text(T.f.body, self.p.empty or L("Nada para mostrar."), 40, 200, T.c.dim, "center", T.W - 80)
  end
  if not self.loading then
    local vis = self:visible()
    for i = self.scroll + 1, math.min(#self.items, self.scroll + vis) do
      local it = self.items[i]
      local y = TOP + (i - self.scroll - 1) * rh
      local on = i == self.sel
      G.rect(12, y, T.W - 24, rh - 4, on and T.c.bg3 or T.c.bg1, 5)
      if on then G.frame(12, y, T.W - 24, rh - 4, T.c.accent, 5, 2) end
      local x = 22
      if it.tag then
        x = x + G.tag(it.tag, x, y + 8, it.tagc or T.c.accent2, T.c.bg0, T.f.pix8) + 8
      end
      G.text_fit(T.f.body, it.text or "", x, y + 5, T.W - 34 - x, T.c.text)
      if it.sub and it.sub ~= "" then
        G.text_fit(T.f.small, it.sub, 22, y + 5 + G.step(T.f.body, 22), T.W - 56, T.c.dim)
      end
    end
    if #self.items > vis then
      G.text(T.f.small, string.format("%d/%d", self.sel, #self.items), T.W - 70, BOTTOM + 2, T.c.faint, "right", 50)
    end
  end
  local hints = { { "dpad", L("Navegar") } }
  local cur = self.items[self.sel]
  if cur and cur.detail and not self.loading then hints[#hints + 1] = { "a", L("Detalhes") } end
  for _, k in ipairs(self.p.keys or {}) do
    if not self.loading and (not k.enabled or k.enabled(self)) then hints[#hints + 1] = { k.key, k.label } end
  end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  if act == "b" then App.pop(); return end
  if self.loading then return end
  local n = #self.items
  for _, k in ipairs(self.p.keys or {}) do
    if act == k.key and (not k.enabled or k.enabled(self)) then k.fn(self, self.items[self.sel]); return end
  end
  if n == 0 then return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "a" then
    local it = self.items[self.sel]
    if it and it.detail then
      App.show_dialog({ title = it.text or self.p.title, kind = "info",
        body = type(it.detail) == "function" and it.detail() or it.detail })
    end
  end
  local vis = self:visible()
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + vis then self.scroll = self.sel - vis end
end

return S
