-- Novidades e Atualizacoes: novos ports, ports atualizados e atualizacoes disponiveis
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local News = require("core.news")
local Covers = require("core.covers")

local S = {}
local ROW_H, LIST_Y, VISIBLE = 74, 50, 5

local KIND = {
  new = { L("NOVO"), T.c.green },
  update = { L("ATUALIZADO"), T.c.accent2 },
  available = { L("ATUALIZAÇÃO DISPONÍVEL"), T.c.yellow },
}

local function fmt_date(d)
  local y, m, dd = (d or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if y then return dd .. "/" .. m .. "/" .. y end
  return d or ""
end

function S:enter()
  self.sel, self.scroll = 1, 0
  self:load()
end
function S:resume() self:load() end
function S:on_catalog() self:load() end

function S:load()
  self.items = News.build(App.status)
  self:clamp()
end

function S:clamp()
  local n = #self.items
  self.sel = U.clamp(self.sel, 1, math.max(1, n))
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  self.scroll = U.clamp(self.scroll, 0, math.max(0, n - VISIBLE))
end

function S:draw()
  G.header(L("Novidades e Atualizações"), #self.items > 0 and (#self.items .. L(" itens")) or nil)
  if #self.items == 0 then
    G.panel(12, LIST_Y + 4, T.W - 24, 380, { bg = T.c.bg1 })
    G.text(T.f.pix16, L("SEM NOVIDADES"), 12, LIST_Y + 150, T.c.dim, "center", T.W - 24)
    G.text(T.f.body, L("Não existem novidades no momento.\nNovos ports e atualizações do catálogo aparecem aqui."),
      12, LIST_Y + 180, T.c.faint, "center", T.W - 24)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  for i = self.scroll + 1, math.min(#self.items, self.scroll + VISIBLE) do
    local it = self.items[i]
    local p = it.port
    local y = LIST_Y + 4 + (i - self.scroll - 1) * (ROW_H + 4)
    local on = i == self.sel
    local k = KIND[it.kind]
    G.panel(12, y, T.W - 24, ROW_H, { bg = on and T.c.bg3 or T.c.bg1, border = on and k[2] or T.c.line, lw = on and 2 or 1 })
    G.cover(Covers.get(p), p, 20, y + 6, 46, ROW_H - 12, false, App.t)
    local x = 76
    x = x + G.tag(k[1], x, y + 7, k[2], T.c.bg0) + 6
    x = x + G.tag(p.section == "tools" and L("UTILITÁRIO") or L("JOGO"), x, y + 6, p.section == "tools" and T.c.green or T.c.accent, T.c.bg0, T.f.small) + 8
    if it.date ~= "" then
      local d = fmt_date(it.date)
      G.text(T.f.small, d, T.W - 28 - T.f.small:getWidth(d), y + 8, T.c.dim)
    end
    G.text_fit(T.f.bodyb, p.name .. (p.version ~= "" and ("  v" .. p.version) or ""), 76, y + 28, T.W - 110, T.c.text)
    G.text_fit(T.f.small, it.text ~= "" and it.text:gsub("\n", " ") or p.category, 76, y + 50, T.W - 110, T.c.dim)
  end
  G.hints({ { "a", L("Ver detalhes") }, { "b", L("Voltar") } })
end

function S:action(act)
  local n = #self.items
  if act == "up" then self.sel = math.max(1, self.sel - 1)
  elseif act == "down" then self.sel = math.min(n, self.sel + 1)
  elseif act == "a" and n > 0 then App.push("details", { port = self.items[self.sel].port })
  elseif act == "b" then App.pop()
  end
  self:clamp()
end

return S
