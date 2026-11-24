-- =============================================================================
--  Meu perfil > Aniversário: escolher dia e mês
--    esquerda/direita: dia ou mês | cima/baixo: mudar o número
--    A: salvar | X: apagar a data | B: voltar sem salvar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local P = require("core.profile")
local lg = love.graphics

local S = {}
local MONTHS = { L("Janeiro"), L("Fevereiro"), L("Março"), L("Abril"), L("Maio"), L("Junho"), L("Julho"),
  L("Agosto"), L("Setembro"), L("Outubro"), L("Novembro"), L("Dezembro") }
local DAYS = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function S:enter(p)
  self.p = p or {}
  local d, m = P.birthday()
  self.d, self.m = d or 1, m or 1
  self.field = 1
end

local function box(x, y, w, h, label, value, on)
  G.panel(x, y, w, h, { bg = on and T.c.bg3 or T.c.bg1, border = on and T.c.accent or T.c.line, lw = on and 2 or 1, r = 10 })
  G.text(T.f.pix8, label, x, y + 12, T.c.faint, "center", w)
  G.text(T.f.h1 or T.f.h2, value, x, y + 40, T.c.text, "center", w)
  if on then
    G.color(T.c.accent)
    local cx = x + w / 2
    lg.polygon("fill", cx, y - 14, cx - 8, y - 4, cx + 8, y - 4)
    lg.polygon("fill", cx, y + h + 14, cx - 8, y + h + 4, cx + 8, y + h + 4)
  end
end

function S:draw()
  G.header(L("Aniversário"), self.p.first and L("Primeiro acesso") or L("Meu perfil"))
  G.text(T.f.bodyb, I18N.tr(L("Quando é o seu aniversário?")), 0, 80, T.c.text, "center", T.W)
  G.text(T.f.small, I18N.tr(L("No dia, o hub comemora com você e libera uma carta especial.")), 0, 104, T.c.dim, "center", T.W)
  box(150, 170, 120, 110, I18N.tr(L("DIA")), string.format("%02d", self.d), self.field == 1)
  box(290, 170, 200, 110, I18N.tr(L("MÊS")), I18N.tr(MONTHS[self.m]), self.field == 2)
  local cur = P.birthday_label()
  if cur then G.text(T.f.small, I18N.tr(L("Data salva: ")) .. cur, 0, 320, T.c.faint, "center", T.W) end
  if self.p.first then
    G.text(T.f.small, I18N.tr(L("Você pode mudar depois em Configurações > Meu perfil.")), 0, 344, T.c.faint, "center", T.W)
    G.hints({ { "dpad", L("Ajustar") }, { "a", L("Salvar") }, { "b", L("Pular") } })
    return
  end
  G.hints({ { "dpad", L("Ajustar") }, { "a", L("Salvar") }, { "x", L("Apagar") }, { "b", L("Voltar") } })
end

function S:finish()
  if self.p.done then self.p.done() else App.pop() end
end

function S:action(act)
  if act == "b" then self:finish(); return end
  if self.p.first and act == "x" then return end
  if act == "left" then self.field = 1
  elseif act == "right" then self.field = 2
  elseif act == "up" or act == "down" then
    local dir = act == "up" and 1 or -1
    if self.field == 1 then self.d = (self.d - 1 + dir) % DAYS[self.m] + 1
    else self.m = (self.m - 1 + dir) % 12 + 1 end
    self.d = math.min(self.d, DAYS[self.m])
  elseif act == "x" then
    P.set_birthday(nil); App.toast(I18N.tr(L("Data de aniversário apagada.")), "ok"); App.pop()
  elseif act == "a" then
    P.set_birthday(self.d, self.m)
    App.toast(I18N.tr(L("Aniversário salvo!")), "ok")
    if not self.p.first then pcall(function() require("core.achievements").check_birthday() end) end
    self:finish()
  end
end

return S
