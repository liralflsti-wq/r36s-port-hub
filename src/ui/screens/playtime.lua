-- =============================================================================
--  Meu perfil > Tempo de jogo
--  Resumo no topo (total, jogos, sessoes, favorito) e o ranking dos jogos e
--  ports abertos pelo hub, com barra proporcional ao mais jogado.
--    cima/baixo: escolher | L1/R1: pagina | A: abrir o port (se estiver no
--    catalogo) | B: voltar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local Icons = require("ui.icons")
local PT = require("core.playtime")
local lg = love.graphics

local S = {}
local LX, LY, LW = 14, 150, 612
local RH = 46                     -- altura de cada linha do ranking
local VIS = 6                     -- linhas visiveis

function S:enter()
  self.list = PT.top()
  self.total = PT.total()
  self.sessions = 0
  for _, g in ipairs(self.list) do self.sessions = self.sessions + (g.sessions or 0) end
  self.sel, self.top = 1, 0
end

local function card(x, y, w, h, icon, label, value, color)
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.line, r = 10 })
  Icons.draw(icon, x + 10, y + 12, color or T.c.accent, 1)
  G.text_fit(T.f.pix8, I18N.tr(label), x + 42, y + 10, w - 50, T.c.faint)
  G.text_fit(T.f.bodyb, value, x + 42, y + 24, w - 50, color or T.c.text)
end

function S:draw()
  G.header(L("Tempo de jogo"), L("Meu perfil"))
  -- resumo
  local fav = self.list[1]
  local cw = math.floor((LW - 3 * 8) / 4)
  card(LX, 52, cw, 50, "set_clock", L("TOTAL JOGADO"), self.total > 0 and PT.format(self.total) or "—", T.c.accent)
  card(LX + (cw + 8), 52, cw, 50, "games", L("JOGOS"), tostring(#self.list), T.c.text)
  card(LX + 2 * (cw + 8), 52, cw, 50, "set_downloads", L("SESSÕES"), tostring(self.sessions), T.c.text)
  card(LX + 3 * (cw + 8), 52, cw, 50, "generic", L("FAVORITO"), fav and fav.name or "—", T.c.yellow)
  G.text(T.f.small, I18N.tr(L("Conta só os jogos da Biblioteca e os ports abertos pelo hub.")), LX, 112, T.c.faint)
  G.text(T.f.pix8, I18N.tr(L("RANKING")), LX, 134, T.c.accent2)

  if #self.list == 0 then
    G.panel(LX, LY, LW, 120, { bg = T.c.bg1, r = 10 })
    Icons.draw("set_clock", T.W / 2 - 12, LY + 20, T.c.faint, 1)
    local s1 = I18N.tr(L("Nenhum jogo aberto pelo hub ainda."))
    local s2 = I18N.tr(L("Abra um jogo pela Biblioteca ou um port em Meus Ports e o tempo aparece aqui."))
    G.text(G.fit(T.f.bodyb, s1, LW - 20), s1, LX, LY + 56, T.c.text, "center", LW)
    G.text(G.fit(T.f.small, s2, LW - 20), s2, LX, LY + 80, T.c.dim, "center", LW)
    G.hints({ { "b", L("Voltar") } })
    return
  end

  if self.sel <= self.top then self.top = self.sel - 1 end
  if self.sel > self.top + VIS then self.top = self.sel - VIS end
  local max = math.max(1, self.list[1].secs)
  for r = 1, VIS do
    local i = self.top + r
    local g = self.list[i]
    if not g then break end
    local y = LY + (r - 1) * RH
    local on = i == self.sel
    G.rect(LX, y, LW, RH - 6, on and T.c.bg3 or T.c.bg1, 8)
    if on then G.frame(LX, y, LW, RH - 6, T.c.accent, 8, 2) end
    -- posicao
    local medal = (i == 1 and T.c.yellow) or (i == 2 and { 0.78, 0.80, 0.86 }) or (i == 3 and { 0.85, 0.55, 0.30 }) or T.c.faint
    G.text(T.f.bodyb, "#" .. i, LX + 10, y + 11, medal)
    -- nome e detalhes
    local nx, nw = LX + 52, 300
    G.text_fit(T.f.bodyb, g.name or "?", nx, y + 4, nw, T.c.text)
    local sub = ((g.sessions or 0) == 1 and I18N.tr(L("1 sessão")) or string.format(I18N.tr(L("%d sessões")), g.sessions or 0))
    if g.last then sub = sub .. "  ·  " .. I18N.tr(L("última vez: ")) .. os.date("%d/%m", g.last) end
    G.text_fit(T.f.small, sub, nx, y + 22, nw, T.c.faint)
    -- barra e tempo
    local bx, bw = LX + 364, 150
    G.rect(bx, y + 16, bw, 8, T.c.bg0, 4)
    G.rect(bx, y + 16, math.max(6, bw * g.secs / max), 8, i == 1 and T.c.yellow or T.c.accent, 4)
    G.text_fit(T.f.bodyb, PT.format(g.secs), bx + bw + 8, y + 11, LX + LW - (bx + bw + 8) - 8, T.c.text)
  end
  if #self.list > VIS then
    G.text(T.f.pix8, string.format("%d / %d", self.sel, #self.list), LX, LY + VIS * RH, T.c.faint, "right", LW)
  end
  local hs = { { "dpad", L("Escolher") } }
  local g = self.list[self.sel]
  if g and g.key:match("^port:") then hs[#hs + 1] = { "a", L("Abrir port") } end
  hs[#hs + 1] = { "b", L("Voltar") }
  G.hints(hs)
end

function S:action(act)
  local n = #self.list
  if act == "b" then App.pop(); return end
  if n == 0 then return end
  if act == "up" then self.sel = math.max(1, self.sel - 1)
  elseif act == "down" then self.sel = math.min(n, self.sel + 1)
  elseif act == "l1" then self.sel = math.max(1, self.sel - VIS)
  elseif act == "r1" then self.sel = math.min(n, self.sel + VIS)
  elseif act == "a" then
    local g = self.list[self.sel]
    local id = g and g.key:match("^port:(.+)$")
    if id then
      local ok, C = pcall(require, "core.catalog")
      local port
      for _, p in ipairs(ok and C.ports or {}) do if tostring(p.id) == id then port = p end end
      if port then App.push("details", { port = port })
      else App.toast(I18N.tr(L("Este port não está no catálogo atual.")), "info") end
    end
  end
end

return S
