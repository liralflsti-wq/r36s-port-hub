-- =============================================================================
--  Vitrine de capas (Pastel Pop Edition: layout "carousel")
--  Visual das listas de jogos no estilo dos menus do 3DS/Wii U:
--    - fundo com a capa do item escolhido, esmaecida;
--    - coluna vertical de capas a esquerda: a escolhida grande, as vizinhas
--      menores (rolagem suave);
--    - no meio: nome grande e pilulas (categoria, tamanho, estado);
--    - a direita: painel branco com blocos de informacao.
--  So desenha: a tela que usa continua com os mesmos dados, botoes e acoes.
--  Usada por: Ports de Jogos / Meus Ports / Favoritos (store.lua) e pelos
--  jogos da Biblioteca (library_games.lua).
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local lg = love.graphics

local CV = {}

--- esta vitrine vale para o tema ativo?
function CV.active() return T.style.layout == "carousel" end

local BIG_W, BIG_H = 132, 176
local SM_W, SM_H = 70, 94
local STEP = 116

--- anima a posicao da coluna (chamar no update da tela)
function CV.update(st, sel, dt)
  st.cv_pos = st.cv_pos or sel
  if App.animations() then
    st.cv_pos = st.cv_pos + (sel - st.cv_pos) * math.min(1, dt * 12)
    if math.abs(st.cv_pos - sel) < 0.01 then st.cv_pos = sel end
  else
    st.cv_pos = sel
  end
end

--- Desenha a vitrine.
--- o = {
---   n, sel, top (y do topo da area, padrao 48),
---   draw_cover = function(i, x, y, w, h, on)  -- capa do item i
---   name, pills = { {texto, cor}, ... }, tags = { {texto, cor}, ... },
---   sections = { { title=, badge=, rows={ {k,v}, ... } } | { title=, text= } },
---   bg_cover = function(x, y, w, h)          -- capa grande do fundo (opcional)
--- }
function CV.draw(st, o)
  local top = o.top or 48
  local pos = st.cv_pos or o.sel
  -- fundo: capa do item escolhido, esmaecida
  if o.bg_cover then
    local bh = T.H - top - 34
    o.bg_cover(4, top, T.W - 8, bh)
    G.rect(4, top, T.W - 8, bh, T.c.bg0, 0, 0.82)
    -- clareia mais a esquerda (coluna de capas e nome)
    for i = 0, 9 do G.rect(4 + i * 36, top, 36, bh, T.c.bg0, 0, 0.10 * (1 - i / 10)) end
  end
  -- coluna de capas
  local cx, cy = 92, top + (T.H - 34 - top) / 2 + 6
  G.clip(4, top + 2, 176, T.H - top - 38)
  local first = math.max(1, math.floor(pos) - 3)
  local last = math.min(o.n, math.ceil(pos) + 3)
  -- desenha de fora para dentro: a escolhida por ultimo (por cima)
  local order = {}
  for i = first, last do order[#order + 1] = i end
  table.sort(order, function(a, b) return math.abs(a - pos) > math.abs(b - pos) end)
  for _, i in ipairs(order) do
    local d = i - pos
    local s = math.max(0, 1 - math.abs(d))
    local w = SM_W + (BIG_W - SM_W) * s
    local h = SM_H + (BIG_H - SM_H) * s
    local off = d * STEP
    if math.abs(d) > 1 then off = off + (d > 0 and 1 or -1) * ((BIG_H - SM_H) / 2 - 8) end
    if math.abs(d) <= 1 then off = d * (STEP + (BIG_H - SM_H) / 2 - 8) end
    local x, y = cx - w / 2, cy + off - h / 2
    local on = i == o.sel
    if on then
      for g = 4, 1, -1 do G.frame(x - g * 1.6, y - g * 1.6, w + g * 3.2, h + g * 3.2, g % 2 == 0 and T.c.accent or T.c.accent2, 14 + g, 2, 0.08) end
      G.rect(x - 4, y - 4, w + 8, h + 8, T.c.bg1, 14)
    end
    o.draw_cover(i, x, y, w, h, on)
    G.frame(x - (on and 4 or 0), y - (on and 4 or 0), w + (on and 8 or 0), h + (on and 8 or 0), on and T.c.accent or T.c.line, on and 14 or 8, on and 3 or 1)
  end
  G.unclip()
  -- setas da coluna
  G.color(T.c.faint)
  local ax = cx + BIG_W / 2 + 14
  if o.sel > 1 then lg.polygon("fill", ax - 6, top + 14, ax + 6, top + 14, ax, top + 7) end
  if o.sel < o.n then lg.polygon("fill", ax - 6, T.H - 50, ax + 6, T.H - 50, ax, T.H - 43) end

  -- meio: nome grande + pilulas + selos
  local mx, mw = 180, 172
  local y = top + 22
  local nf, nl, nlh = G.fit_lines(T.f.h1, o.name or "", mw, 3 * T.base_font(T.f.h1):getHeight())
  for _, l in ipairs(nl) do G.text(nf, l, mx, y, T.c.text); y = y + nlh end
  y = y + 8
  for _, p in ipairs(o.pills or {}) do
    local f = T.f.small
    local w = math.min(mw, f:getWidth(I18N.tr(p[1])) + 22)
    G.rect(mx, y, w, 22, T.c.bg1, 11, 0.95)
    G.frame(mx, y, w, 22, p[2] or T.c.line, 11, 1)
    G.text_fit(f, p[1], mx + 11, y + 11 - f:getHeight() / 2, w - 22, T.c.dim)
    y = y + 28
  end
  for _, tg in ipairs(o.tags or {}) do
    G.tag(tg[1], mx, y, tg[2], T.c.bg1)
    y = y + 24
  end
  -- contador
  G.text(T.f.pix8, string.format("%d / %d", o.sel, o.n), mx, T.H - 52, T.c.faint)

  -- painel da direita (blocos de informacao)
  local px, py, pw, ph = 362, top + 6, T.W - 362 - 14, T.H - top - 48
  G.rect(px + 2, py + 5, pw, ph, T.c.shadow, 18)
  G.rect(px, py, pw, ph, T.c.bg1, 18)
  G.frame(px, py, pw, ph, T.c.line, 18, 1)
  local by = py + 10
  for si, sec in ipairs(o.sections or {}) do
    if by > py + ph - 40 then break end
    local bx, bw = px + 10, pw - 20
    local room = py + ph - 10 - by
    -- altura do bloco
    local f = T.f.small
    local lh = G.step(f, 16)
    local bh
    local lines
    if sec.text then
      local tf
      tf, lines = G.fit_lines(f, sec.text, bw - 20, math.max(lh, room - 34), true)
      f = tf
      bh = 30 + #lines * G.step(f, 16) + 6
    else
      bh = 30 + #sec.rows * lh + 6
    end
    local btw = sec.badge and (T.f.pix8:getWidth(I18N.tr(sec.badge[1])) + 12) or 0
    local below = sec.badge and (T.f.bodyb:getWidth(I18N.tr(sec.title)) + 18 + btw > bw - 8)
    if below then bh = bh + 20 end
    bh = math.min(bh, room)
    G.rect(bx, by, bw, bh, T.c.bg0, 12)
    G.frame(bx, by, bw, bh, T.c.line, 12, 1)
    G.text(T.f.bodyb, sec.title, bx + 10, by + 6, T.c.text)
    local ly = by + 30
    if sec.badge then
      if not below then
        G.tag(sec.badge[1], bx + bw - btw - 8, by + 7, sec.badge[2] or T.c.accent, T.c.bg1)
      else
        -- sem espaco ao lado do titulo: o selo desce para a linha de baixo
        G.tag(sec.badge[1], bx + 10, ly - 2, sec.badge[2] or T.c.accent, T.c.bg1)
        ly = ly + 20
      end
    end
    if sec.text then
      for _, l in ipairs(lines) do
        if ly > by + bh - 14 then break end
        G.text(f, l, bx + 10, ly, T.c.dim); ly = ly + G.step(f, 16)
      end
    else
      for _, kv in ipairs(sec.rows) do
        if ly > by + bh - 14 then break end
        G.text_fit(f, kv[1], bx + 10, ly, 84, T.c.faint)
        G.text_fit(f, kv[2], bx + 98, ly, bw - 108, kv[3] or T.c.dim)
        ly = ly + lh
      end
    end
    by = by + bh + 8
  end
end

return CV
