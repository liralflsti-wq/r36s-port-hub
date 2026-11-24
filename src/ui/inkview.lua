-- =============================================================================
--  Visual "tinta e papel" do Moonlight Blade Edition (arte original do hub)
--    - circulo de pincel (enso) feito em codigo
--    - fileira de talismas de papel (listas): o escolhido cresce, sobe e brilha
--    - pergaminho aberto (detalhes) com rolos nas pontas e carimbo vermelho
--  Usado por ui/themeviews.lua (listas) e ui/blademenu.lua (tela inicial).
-- =============================================================================
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Icons = require("ui.icons")
local I18N = require("lib.i18n")
local lg = love.graphics

local IV = {}

local PAPER = { 0.94, 0.90, 0.80 }
local PAPER2 = { 0.86, 0.80, 0.66 }
local INK = { 0.07, 0.06, 0.08 }
local RED = { 0.80, 0.07, 0.12 }
IV.PAPER, IV.INK, IV.RED = PAPER, INK, RED

local function anim() return App and App.animations and App.animations() end

--- circulo de pincel (enso): traco grosso que afina, com uma abertura
function IV.enso(cx, cy, r, w, c, a, rot)
  rot = rot or -0.6
  local n = 90
  for i = 0, n do
    local t = i / n
    local ang = rot + t * math.pi * 1.86
    local ww = w * (0.35 + 0.65 * math.sin(math.pi * math.min(1, t * 1.15)) ^ 0.6) * (0.9 + 0.1 * math.sin(i * 1.3))
    local rr = r + math.sin(i * 0.7) * 1.5
    lg.setColor(c[1], c[2], c[3], (a or 1) * (0.8 + 0.2 * math.sin(i * 2.1)))
    lg.circle("fill", cx + math.cos(ang) * rr, cy + math.sin(ang) * rr, ww / 2)
  end
end

--- carimbo vermelho quadrado com uma letra
function IV.stamp(x, y, s, letter, a)
  lg.setColor(RED[1], RED[2], RED[3], a or 0.9)
  lg.rectangle("fill", x, y, s, s, 3, 3)
  lg.setColor(PAPER[1], PAPER[2], PAPER[3], (a or 0.9))
  lg.setLineWidth(1.5)
  lg.rectangle("line", x + 3, y + 3, s - 6, s - 6, 2, 2)
  lg.setLineWidth(1)
  local f = T.f.h2
  local l = U.upper(letter or "")
  G.text(f, l, x + (s - f:getWidth(l)) / 2, y + (s - f:getHeight()) / 2, PAPER)
end

--- uma folha de papel com bordas levemente irregulares e sombra
function IV.paper(x, y, w, h, on)
  lg.setColor(0, 0, 0, 0.45)
  lg.rectangle("fill", x + 3, y + 4, w, h)
  for i = 0, h - 1, 4 do
    local k = i / h
    lg.setColor(PAPER[1] + (PAPER2[1] - PAPER[1]) * k * 0.6, PAPER[2] + (PAPER2[2] - PAPER[2]) * k * 0.6,
      PAPER[3] + (PAPER2[3] - PAPER[3]) * k * 0.6, 1)
    lg.rectangle("fill", x, y + i, w, math.min(4, h - i))
  end
  -- fibras do papel
  lg.setColor(0.6, 0.5, 0.35, 0.10)
  for j = 0, 5 do lg.line(x + 3, y + 10 + j * h / 6, x + w - 3, y + 14 + j * h / 6) end
  if on then
    lg.setColor(RED[1], RED[2], RED[3], 1)
    lg.setLineWidth(2)
    lg.rectangle("line", x - 1, y - 1, w + 2, h + 2)
    lg.setLineWidth(1)
  end
end

--- texto escrito na vertical (de cima para baixo, girado), cabe em `len` px
local function vtext(s, cx, y, len, c, font)
  s = I18N.tr(s or "")
  local f = G.fit(font or T.f.bodyb, s, len)
  local t = U.ellipsize(f, s, len)
  lg.push()
  lg.translate(cx + f:getHeight() / 2, y)
  lg.rotate(math.pi / 2)
  G.text(f, t, 0, 0, c)
  lg.pop()
end

-- ---------------------------------------------------------------------------
-- Fileira de talismas (listas). o = { n, sel, item(i) -> { icon, label, right, dim } }
local TW, TH, TWB, THB, GAP = 52, 168, 70, 196, 10

function IV.update(st, sel, dt)
  st.iv_pos = st.iv_pos or sel
  if anim() then
    st.iv_pos = st.iv_pos + (sel - st.iv_pos) * math.min(1, dt * 12)
    if math.abs(st.iv_pos - sel) < 0.01 then st.iv_pos = sel end
  else
    st.iv_pos = sel
  end
end

function IV.talismans(st, o)
  local top = (o.top or 46) + 8
  if not st.iv_upd or st.iv_upd ~= App.t then
    IV.update(st, o.sel, App.dt or 0.016)
    st.iv_upd = App.t
  end
  local pos = st.iv_pos or o.sel
  -- corda onde os talismas ficam pendurados
  lg.setColor(0.55, 0.42, 0.30, 1)
  lg.setLineWidth(2)
  lg.line(0, top + 6, T.W, top + 10)
  lg.setLineWidth(1)
  local cx = T.W / 2
  local step = TW + GAP
  G.clip(0, top, T.W, THB + 24)
  local first = math.max(1, math.floor(pos - cx / step) - 1)
  local last = math.min(o.n, math.ceil(pos + cx / step) + 1)
  -- desenha de fora para dentro: o escolhido por ultimo
  local order = {}
  for i = first, last do order[#order + 1] = i end
  table.sort(order, function(a, b) return math.abs(a - pos) > math.abs(b - pos) end)
  local sway = anim() and math.sin(App.t * 1.6) * 0.02 or 0
  for _, i in ipairs(order) do
    local it = o.item(i)
    local d = i - pos
    local k = math.max(0, 1 - math.abs(d))
    local w, h = TW + (TWB - TW) * k, TH + (THB - TH) * k
    local x = cx + d * step + (d > 0 and 1 or -1) * (math.min(1, math.abs(d)) * (TWB - TW) / 2) - w / 2
    local y = top + 12 - k * 2
    local on = i == o.sel
    lg.push()
    lg.translate(x + w / 2, top + 8)
    lg.rotate((on and 0 or (d * 0.012)) + sway * (on and 0.5 or 1))
    lg.translate(-(x + w / 2), -(top + 8))
    -- cordinha
    lg.setColor(0.55, 0.42, 0.30, 1)
    lg.line(x + w / 2, top + 8, x + w / 2, y)
    if on then
      -- brilho vermelho atras do escolhido
      for g = 5, 1, -1 do
        lg.setColor(RED[1], RED[2], RED[3], 0.08 * (anim() and App.pulse(0.7, 0.3, 2.4) or 1))
        lg.rectangle("fill", x - g * 3, y - g * 3, w + g * 6, h + g * 6, 4, 4)
      end
    end
    IV.paper(x, y, w, h, on)
    -- faixa de tinta no topo + icone
    lg.setColor(INK[1], INK[2], INK[3], it.dim and 0.5 or 0.95)
    lg.rectangle("fill", x + 4, y + 4, w - 8, 30)
    local isz = 22
    Icons.draw(it.icon or "games", x + (w - isz) / 2, y + 8, on and RED or PAPER, isz / 24)
    -- nome na vertical
    vtext(it.label, x + w / 2 - 8, y + 42, h - 74, it.dim and { 0.45, 0.40, 0.36 } or INK, on and T.f.bodyb or T.f.body)
    -- numero (quantidade) embaixo, num circulo vermelho
    if it.right and it.right ~= "" then
      local rs = I18N.tr(it.right)
      local f = T.f.small
      local rw = math.max(18, f:getWidth(rs) + 8)
      lg.setColor(RED[1], RED[2], RED[3], 0.9)
      lg.rectangle("fill", x + (w - rw) / 2, y + h - 24, rw, 16, 8, 8)
      G.text(f, rs, x + (w - f:getWidth(rs)) / 2, y + h - 24 + 8 - f:getHeight() / 2, PAPER)
    elseif on then
      IV.stamp(x + w / 2 - 10, y + h - 28, 20, "", 0.9)
    end
    lg.pop()
  end
  G.unclip()
  -- contador
  G.text(T.f.pix8, string.format("%d / %d", o.sel, o.n), T.W - 70, top + THB + 10, T.c.faint)
  local fx = require("ui.skyfx")
  fx.focus = { cx, top + 12 + THB / 2 }
end
IV.LIST_BOTTOM = 46 + 8 + THB + 26

-- ---------------------------------------------------------------------------
-- Pergaminho aberto (detalhes). o = { x, y, w, h, icon, name, pills, rows, text, image(x,y,w,h) }
function IV.scroll(o)
  local x, y = o.x or 26, o.y or IV.LIST_BOTTOM
  local w, h = o.w or (T.W - 52), o.h or (T.H - 46 - (o.y or IV.LIST_BOTTOM))
  -- rolos de madeira nas pontas
  local function roller(rx)
    lg.setColor(0.25, 0.12, 0.06, 1)
    lg.rectangle("fill", rx - 6, y - 4, 12, h + 8, 5, 5)
    lg.setColor(0.45, 0.24, 0.12, 1)
    lg.rectangle("fill", rx - 3, y - 2, 4, h + 4, 2, 2)
    lg.setColor(INK[1], INK[2], INK[3], 1)
    lg.rectangle("fill", rx - 7, y - 8, 14, 6, 2, 2)
    lg.rectangle("fill", rx - 7, y + h + 2, 14, 6, 2, 2)
  end
  IV.paper(x, y, w, h, false)
  roller(x - 2)
  roller(x + w + 2)
  local ix = x + 18
  local iw = w - 36
  local right = 0
  if o.image then
    right = math.min(140, math.floor(w * 0.3))
    local ih = h - 20
    lg.setColor(INK[1], INK[2], INK[3], 1)
    lg.rectangle("fill", x + w - right - 14, y + 10, right, ih)
    o.image(x + w - right - 12, y + 12, right - 4, ih - 4)
    iw = iw - right - 6
  end
  -- carimbo com a inicial + nome em tinta
  local name = I18N.tr(o.name or "")
  IV.stamp(ix, y + 12, 34, name:match("^[%z\1-\127\194-\244][\128-\191]*") or "")
  local nf, nl, nlh = G.fit_lines(T.f.h2, name, iw - 46, 2 * T.f.h2:getHeight(), true)
  local ny = (#nl == 1) and (y + 29 - nlh / 2) or (y + 10)
  for k, l in ipairs(nl) do G.text(nf, l, ix + 46, ny + (k - 1) * nlh, INK) end
  -- traco de pincel vermelho embaixo do nome
  local by = math.max(y + 52, ny + #nl * nlh + 3)
  lg.setColor(RED[1], RED[2], RED[3], 0.85)
  for i = 0, 30 do
    local t = i / 30
    lg.circle("fill", ix + 46 + t * math.min(iw - 46, 200), by + math.sin(t * 3) * 1.2, 2.2 * (1 - t * 0.7))
  end
  local cy = by + 10
  local px = ix
  for _, p in ipairs(o.pills or {}) do
    local tr = I18N.tr(p[1] or "")
    if tr ~= "" then
      local pw = math.min(iw, T.f.small:getWidth(tr) + 16)
      if px + pw > ix + iw then px = ix; cy = cy + 22 end
      lg.setColor(INK[1], INK[2], INK[3], 0.9)
      lg.rectangle("fill", px, cy, pw, 18, 3, 3)
      G.text_fit(T.f.small, tr, px + 8, cy + 9 - T.f.small:getHeight() / 2, pw - 16, PAPER)
      px = px + pw + 6
    end
  end
  cy = cy + 24
  local split = #(o.rows or {}) > 0 and (o.text and o.text ~= "") and not o.image
  local colw = split and math.floor(iw * 0.48) or iw
  local ry = cy
  for _, kv in ipairs(o.rows or {}) do
    if ry > y + h - 18 then break end
    G.text_fit(T.f.small, kv[1], ix, ry, 90, { 0.45, 0.36, 0.28 })
    G.text_fit(T.f.small, kv[2], ix + 92, ry, colw - 96, INK)
    ry = ry + G.step(T.f.small, 16)
  end
  if o.text and o.text ~= "" then
    local tx, ty, tw = ix, cy, iw
    if split then tx, tw = ix + colw + 10, iw - colw - 10
    elseif #(o.rows or {}) > 0 then ty = ry + 4 end
    local f, ls = G.fit_lines(T.f.small, o.text, tw, y + h - 10 - ty, true)
    local lh = G.step(f, 15)
    for _, l in ipairs(ls) do G.text(f, l, tx, ty, { 0.20, 0.16, 0.14 }); ty = ty + lh end
  end
end

return IV
