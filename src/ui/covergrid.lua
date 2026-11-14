-- =============================================================================
--  Grade de capas (Neon Grid Edition: style.list = "grid")
--  Listas de ports como um painel de console: em cima, o port escolhido em
--  destaque (capa, nome, categoria, tamanho, estado e descricao curta) com
--  brilho verde; embaixo, a grade de capas. So desenha: a tela que usa
--  continua com os mesmos dados, botoes e acoes.
--  Usada por: Ports de Jogos / Utilitarios / Meus Ports / Favoritos (store.lua).
-- =============================================================================
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local lg = love.graphics

local CG = {}

CG.COLS = 6
local CW, CH = 88, 114
local HERO_H = 112

--- esta grade vale para o tema ativo?
function CG.active() return T.style.list == "grid" end

local function glow(x, y, w, h, r)
  local fc = T.style.focus or T.c.accent
  local k = (App.pulse and App.animations()) and App.pulse(0.85, 0.15, 2.0) or 1
  for i = 6, 1, -1 do G.frame(x - i * 1.5, y - i * 1.5, w + i * 3, h + i * 3, fc, r + i * 1.5, 2, 0.07 * k) end
  G.frame(x, y, w, h, fc, r, 3, k)
end

--- o = { top, n, sel, draw_cover(i, x, y, w, h), name, pills = { {txt, cor} },
---       tags = { {txt, cor} }, desc, badge(i) -> cor|nil }
function CG.draw(st, o)
  local top = o.top or 82
  -- destaque do item escolhido
  local x, y, w, h = 14, top + 2, T.W - 28, HERO_H
  G.rect(x + 2, y + 4, w, h, T.c.shadow, 8)
  G.rect(x, y, w, h, T.c.bg1, 8, 0.96)
  glow(x, y, w, h, 8)
  local cw = 76
  o.draw_cover(o.sel, x + 10, y + 7, cw, h - 14)
  local tx, tw = x + cw + 24, w - cw - 36
  -- etiquetas a direita do nome
  local right = x + w - 12
  for i = #(o.tags or {}), 1, -1 do
    local t = o.tags[i]
    local tw2 = T.f.pix8:getWidth(I18N.tr(t[1])) + 12
    right = right - tw2
    G.tag(t[1], right, y + 12, t[2], T.c.bg0, T.f.pix8)
    right = right - 6
  end
  local nf = G.fit(T.f.h2, o.name or "", right - tx - 8)
  G.text_fit(nf, o.name or "", tx, y + 8, right - tx - 8, T.c.text)
  -- pilulas (categoria, tamanho, versao)
  local px = tx
  for _, p in ipairs(o.pills or {}) do
    local s = I18N.tr(p[1] or "")
    if s ~= "" then
      local pw = T.f.small:getWidth(s) + 16
      if px + pw > x + w - 12 then break end
      G.rect(px, y + 40, pw, 20, T.c.bg2, 10)
      G.frame(px, y + 40, pw, 20, p[2] or T.c.line, 10, 1)
      G.text(T.f.small, s, px + 8, y + 50 - T.f.small:getHeight() / 2, T.c.dim)
      px = px + pw + 6
    end
  end
  local lines = G.wrap(T.f.small, o.desc or "", tw)
  for i = 1, math.min(2, #lines) do
    G.text(T.f.small, lines[i] .. ((i == 2 and #lines > 2) and "…" or ""), tx, y + 68 + (i - 1) * 16, T.c.dim)
  end
  -- grade de capas
  local gy = y + h + 12
  local rows = math.max(1, math.floor((T.H - 40 - gy + 8) / (CH + 8)))
  local cols = CG.COLS
  local gap = math.floor((T.W - 28 - cols * CW) / (cols - 1))
  local x0 = math.floor((T.W - (cols * CW + (cols - 1) * gap)) / 2)
  local row = math.floor((o.sel - 1) / cols)
  local sc = st.cg_scroll or 0
  if row < sc then sc = row elseif row >= sc + rows then sc = row - rows + 1 end
  st.cg_scroll = sc
  for i = sc * cols + 1, math.min(o.n, (sc + rows) * cols) do
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols) - sc
    local cx, cy = x0 + c * (CW + gap), gy + r * (CH + 8)
    G.rect(cx + 2, cy + 3, CW, CH, T.c.shadow, 4)
    o.draw_cover(i, cx, cy, CW, CH)
    local b = o.badge and o.badge(i)
    if b then
      G.rect(cx + CW - 18, cy + CH - 18, 14, 14, T.c.bg0, 7, 0.85)
      G.color(b); lg.circle("fill", cx + CW - 11, cy + CH - 11, 4)
    end
    if i == o.sel then glow(cx, cy, CW, CH, 4) end
  end
  -- barra de rolagem
  local total = math.ceil(o.n / cols)
  if total > rows then
    local bh = (T.H - 40 - gy) * rows / total
    local by = gy + (T.H - 40 - gy - bh) * sc / math.max(1, total - rows)
    G.rect(T.W - 7, gy, 3, T.H - 40 - gy, T.c.line, 2)
    G.rect(T.W - 7, by, 3, bh, T.style.focus or T.c.accent, 2)
  end
end

return CG
