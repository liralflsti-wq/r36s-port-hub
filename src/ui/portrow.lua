-- =============================================================================
--  Linha de port reutilizada pelas listas (loja, favoritos, pesquisa, novidades)
--  Capa, nome, estrela de favorito, categoria/tipo, tamanho e selo de status.
--  O selo usa o reconhecimento de instalados ja existente (App.status).
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local Covers = require("core.covers")
local Favorites = require("core.favorites")
local Cats = require("core.categories")
local Icons = require("ui.icons")

local R = {}

R.BADGE = {
  installed = { L("INSTALADO"), T.c.green },
  update = { L("ATUALIZAR"), T.c.yellow },
}

--- texto secundario: categoria (+ tipo de teste) e tamanho
function R.subtitle(p)
  local cat = p.category
  if p.test_type and Cats.TEST_TYPE_BY_ID[p.test_type] then
    cat = cat .. " • " .. Cats.TEST_TYPE_BY_ID[p.test_type].name:gsub("^Teste d?e? ?", "")
  end
  return cat .. "  •  " .. (p.size_label or "?")
end

--- extra: { area = true } mostra JOGO/UTILITARIO; { right = "texto" } troca o selo
function R.draw(p, x, y, w, h, on, accent, extra)
  extra = extra or {}
  if on then
    G.rect(x, y, w, h, T.c.bg3, 6)
    G.frame(x, y, w, h, accent or T.c.accent, 6, 2)
  end
  local st, badge
  if p.builtin then
    G.rect(x + 8, y + 4, 29, h - 8, T.c.bg0, 4)
    G.frame(x + 8, y + 4, 29, h - 8, T.c.green, 4)
    Icons.draw(p.icon, x + 11, y + h / 2 - 11, T.c.green, 0.9)
    badge = { L("INTEGRADO"), T.c.green }
  else
    G.cover(Covers.get(p), p, x + 8, y + 4, 29, h - 8, false, App.t)
    st = App.status(p)
    badge = R.BADGE[st]
  end
  local fav = not p.builtin and Favorites.is(p)
  local rightw = 0
  if badge then
    rightw = T.f.pix8:getWidth(badge[1]) + 12
    G.tag(badge[1], x + w - 10 - rightw, y + h / 2 - 9, badge[2], T.c.bg0)
  end
  local nx = x + 46
  if fav then
    Icons.draw("generic", nx, y + 6, T.c.yellow, 0.6)
    nx = nx + 17
  end
  local tw = w - (nx - x) - 12 - (rightw > 0 and rightw + 8 or 0)
  local ft, fs, ty, sy = G.row_fonts(h, 5, h - 22)
  G.text_fit(ft, p.name, nx, y + ty, tw, on and T.c.text or T.c.dim)
  local sub = R.subtitle(p)
  if extra.area then
    sub = (p.section == "tools" and L("Utilitário") or L("Jogo")) .. "  •  " .. sub
  end
  G.text_fit(fs, sub, x + 46, y + sy, w - 58 - (rightw > 0 and rightw + 8 or 0), T.c.faint)
end

return R
