-- =============================================================================
--  SELECT LANGUAGE (primeiro acesso) e Configuracoes > Idioma
--  cima/baixo escolhem | A confirma (aplica na hora e salva) | B volta
--  (B so existe quando ha uma tela anterior segura: nas Configuracoes)
-- =============================================================================
local T = require("ui.theme")
local G = require("ui.gfx")
local I18N = require("lib.i18n")
local U = require("lib.util")
local L = I18N.L
local lg = love.graphics

local S = {}

function S:enter(p)
  self.first = p.first and true or false
  self.sel = 1
  for i, l in ipairs(I18N.LANGS) do if l.id == I18N.lang then self.sel = i end end
end

--- bandeiras simples desenhadas (sem imagens)
local function flag(id, x, y, w, h)
  lg.setColor(1, 1, 1, 1)
  if id == "br" then
    lg.setColor(0.0, 0.61, 0.23, 1); lg.rectangle("fill", x, y, w, h)
    lg.setColor(1.0, 0.87, 0.0, 1)
    lg.polygon("fill", x + w / 2, y + 3, x + w - 4, y + h / 2, x + w / 2, y + h - 3, x + 4, y + h / 2)
    lg.setColor(0.0, 0.15, 0.46, 1); lg.circle("fill", x + w / 2, y + h / 2, h * 0.24)
  elseif id == "us" then
    for i = 0, 6 do
      if i % 2 == 0 then lg.setColor(0.70, 0.13, 0.20, 1) else lg.setColor(1, 1, 1, 1) end
      lg.rectangle("fill", x, y + i * h / 7, w, h / 7 + 0.5)
    end
    lg.setColor(0.24, 0.23, 0.43, 1); lg.rectangle("fill", x, y, w * 0.42, h * 4 / 7)
    lg.setColor(1, 1, 1, 1)
    for r = 0, 2 do for c = 0, 3 do lg.rectangle("fill", x + 2 + c * 3.5, y + 2 + r * 3.6, 1.2, 1.2) end end
  elseif id == "ru" then
    lg.setColor(1, 1, 1, 1); lg.rectangle("fill", x, y, w, h / 3)
    lg.setColor(0.0, 0.22, 0.65, 1); lg.rectangle("fill", x, y + h / 3, w, h / 3 + 0.5)
    lg.setColor(0.84, 0.17, 0.12, 1); lg.rectangle("fill", x, y + 2 * h / 3, w, h / 3 + 0.5)
  end
  G.frame(x, y, w, h, T.c.line, 0)
end

function S:draw()
  if not self.first then G.header(L("Idioma")) end
  local top = self.first and 60 or 70
  G.text(T.f.pix16, "SELECT LANGUAGE", 0, top, T.c.accent, "center", T.W)
  if not self.first then
    G.text(T.f.small, L("Escolha o idioma do R36S PORT HUB. A mudança vale na hora."), 0, top + 28, T.c.dim, "center", T.W)
  end
  local w, h = 380, 62
  local x = (T.W - w) / 2
  for i, l in ipairs(I18N.LANGS) do
    local y = top + 60 + (i - 1) * (h + 14)
    local on = i == self.sel
    G.panel(x, y, w, h, { bg = on and T.c.bg3 or T.c.bg1, border = on and T.c.accent or T.c.line, lw = on and 2 or 1 })
    if on then G.rect(x, y + 10, 4, h - 20, T.c.accent, 2) end
    flag(l.flag, x + 22, y + 17, 42, 28)
    -- nome no proprio idioma (nao traduzido de proposito)
    local maxw = w - 84 - 16
    if l.id == I18N.lang and not self.first then
      local tag = L("EM USO")
      local tw = T.f.pix8:getWidth(tag) + 12
      G.tag(tag, x + w - 16 - tw, y + 22, T.c.green, T.c.bg0, T.f.pix8)
      maxw = w - 84 - 16 - tw - 10
    end
    -- texto maior: o nome diminui (ate o padrao) para nao encostar na etiqueta
    local nf = G.fit(T.f.h2, l.short, maxw)
    lg.setFont(nf); G.color(on and T.c.text or T.c.dim)
    lg.print(U.ellipsize(nf, l.short, maxw), math.floor(x + 84), math.floor(y + 18 + (T.base_font(T.f.h2):getHeight() - nf:getHeight()) / 2))
  end
  if self.first then
    -- primeiro acesso: as dicas aparecem no idioma destacado
    local cur = I18N.lang
    I18N.set(I18N.LANGS[self.sel].id)
    G.hints({ { "dpad", L("Escolher") }, { "a", L("Confirmar") } })
    I18N.set(cur)
  else
    G.hints({ { "dpad", L("Escolher") }, { "a", L("Confirmar") }, { "b", L("Voltar") } })
  end
end

function S:action(act)
  local n = #I18N.LANGS
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "b" and not self.first then App.pop()
  elseif act == "a" then
    local id = I18N.LANGS[self.sel].id
    App.set_language(id)
    if self.first then
      App.after_language()
    else
      App.toast(L("Idioma alterado."), "ok")
    end
  end
end

return S
