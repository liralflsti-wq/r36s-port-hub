-- =============================================================================
--  Visual proprio de cada tema nas telas de Configuracoes, Categorias e
--  Biblioteca (0.5.5):
--    - Tema Padrao ......... cartoes (visual original de cada tela)
--    - Neon Grid Edition ... painel de console: destaque em cima + grade de
--                            blocos com brilho verde (ui/covergrid.lua)
--    - Pastel Pop Edition .. vitrine: coluna de bolhas a esquerda, nome grande
--                            e painel branco com informacoes (ui/coverview.lua)
--  Aqui ficam so os pedacos comuns: qual visual usar, a "capa" de icone e a
--  navegacao de cada visual. Os dados e as acoes continuam os de cada tela.
-- =============================================================================
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Icons = require("ui.icons")
local CG = require("ui.covergrid")
local CV = require("ui.coverview")

local TV = {}

--- texto centralizado numa largura (diminui/encurta se nao couber)
local function ctext(font, s, x, y, w, c)
  s = require("lib.i18n").tr(s or "")
  local f = G.fit(font, s, w)
  local t = U.ellipsize(f, s, w)
  G.text(f, t, x + math.floor((w - f:getWidth(t)) / 2), y, c)
end
TV.ctext = ctext

--- "grid" (Neon Grid), "showcase" (Pastel Pop), "bars" (Sky Warriors)
--- ou "cards" (Padrao e outros)
function TV.mode()
  local l = T.style.list
  if l == "bars" or l == "blades" then return "bars" end
  if CG.active() then return "grid" end
  if CV.active() then return "showcase" end
  return "cards"
end

--- capa feita de icone (categoria, sistema, area das configuracoes)
--- c = cor do item; label = texto curto embaixo (opcional); dim = item vazio
function TV.icon_cover(icon, c, label, dim)
  return function(_, x, y, w, h, on)
    local mode = TV.mode()
    if mode == "showcase" then
      -- bolha clara com borda na cor do item
      G.rect(x, y, w, h, T.c.bg1, 12)
      G.rect(x + 4, y + 4, w - 8, h - 8, c, 10, on and 0.16 or 0.08)
      local isz = math.min(w, h) * 0.46
      Icons.draw(icon, x + (w - isz) / 2, y + (h - isz) / 2 - (label and h * 0.06 or 0), dim and T.c.faint or c, isz / 24)
      if label and h > 70 then
        ctext(T.f.pix8, U.upper(require("lib.i18n").tr(label)), x + 6, y + h - 18, w - 12, dim and T.c.faint or c)
      end
    else
      -- bloco escuro com faixa colorida embaixo (painel de console)
      G.rect(x, y, w, h, T.c.bg2, 4)
      G.rect(x, y + h - 4, w, 4, c, 0, dim and 0.35 or 0.9)
      local isz = math.min(w, h) * (label and 0.40 or 0.5)
      Icons.draw(icon, x + (w - isz) / 2, y + (label and h * 0.18 or (h - isz) / 2), dim and T.c.faint or c, isz / 24)
      if label and h > 70 then
        -- ate 2 linhas; a fonte diminui para nao cortar palavras no meio
        -- se uma palavra nao couber, usa um texto um pouco menor (ate 10 px)
        local tr = require("lib.i18n").tr(label)
        local base = T.f.small
        for _, sz in ipairs({ 11, 10 }) do
          local fits = true
          for wd in tr:gmatch("%S+") do if base:getWidth(wd) > w - 8 then fits = false; break end end
          if fits then break end
          base = T.text_font("small", sz)
        end
        local f, lines, lh = G.fit_lines(base, label, w - 8, 36, true)
        local ly = y + h - 10 - #lines * lh
        for k = 1, #lines do
          ctext(f, lines[k], x + 4, ly + (k - 1) * lh, w - 8, dim and T.c.faint or T.c.text)
        end
      end
    end
  end
end

--- navegacao da grade (Neon Grid). Devolve o novo indice ou nil
function TV.grid_nav(sel, n, act)
  if n == 0 then return nil end
  local c = CG.COLS
  if act == "left" then return math.max(1, sel - 1)
  elseif act == "right" then return math.min(n, sel + 1)
  elseif act == "up" then return sel > c and sel - c or sel
  elseif act == "down" then return math.min(n, sel + c)
  elseif act == "l1" then return math.max(1, sel - c * 2)
  elseif act == "r1" then return math.min(n, sel + c * 2)
  end
  return nil
end

--- navegacao da vitrine (Pastel Pop): cima/baixo um item, L1/R1 cinco
function TV.showcase_nav(sel, n, act)
  if n == 0 then return nil end
  if act == "up" or act == "left" then return (sel - 2) % n + 1
  elseif act == "down" or act == "right" then return sel % n + 1
  elseif act == "l1" then return math.max(1, sel - 5)
  elseif act == "r1" then return math.min(n, sel + 5)
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Barras inclinadas (Sky Warriors Edition): lista de barras azul-turquesa a
-- esquerda (a escolhida laranja, com aura) e painel de detalhes a direita.
local lg = love.graphics
TV.BAR_H, TV.BAR_STEP, TV.BAR_SKEW = 36, 42, 14

--- cores das barras/paineis: Sky Warriors (dourado/azul) ou Moonlight Blade (vermelho/preto)
local function pal()
  if T.style.list == "blades" then
    return { frame = { 0.89, 0.09, 0.17 }, inner = { 0.6, 0.6, 0.66 }, panel = { 0.04, 0.04, 0.07, 0.92 },
      shade = { 0, 0, 0, 0.5 }, ring_on = { 0.89, 0.09, 0.17 }, ring_off = { 0.55, 0.55, 0.62 },
      fill_on = { 0.08, 0.02, 0.04 }, fill_off = { 0.07, 0.07, 0.10 }, arrow = { 0.89, 0.09, 0.17 },
      outline = { 0, 0, 0 } }
  end
  return { frame = { 1.0, 0.80, 0.25 }, inner = { 0.4, 0.8, 1.0 }, panel = { 0.05, 0.18, 0.42, 0.88 },
    shade = { 0.02, 0.10, 0.28, 0.4 }, ring_on = { 1.0, 0.80, 0.25 }, ring_off = { 0.85, 0.95, 1.0 },
    fill_on = { 0.98, 0.55, 0.10 }, fill_off = { 0.10, 0.38, 0.72 }, arrow = { 1.0, 0.50, 0.08 },
    outline = { 0.04, 0.12, 0.30 } }
end
TV.pal = pal

--- texto branco com contorno escuro (legivel sobre o ceu)
function TV.outline_text(font, s, x, y, c, oc)
  s = require("lib.i18n").tr(s or "")
  oc = oc or pal().outline
  for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 1 } }) do
    G.text(font, s, x + d[1] * 1.5, y + d[2] * 1.5, oc)
  end
  G.text(font, s, x, y, c or T.c.text)
end

--- uma barra inclinada (paralelogramo) com degrade da esquerda para a direita
local function slanted(x, y, w, h, c1, c2, a1, a2)
  local k = TV.BAR_SKEW
  local steps = 24
  for i = 0, steps - 1 do
    local t0, t1 = i / steps, (i + 1) / steps
    local r = c1[1] + (c2[1] - c1[1]) * t0
    local g = c1[2] + (c2[2] - c1[2]) * t0
    local b = c1[3] + (c2[3] - c1[3]) * t0
    lg.setColor(r, g, b, a1 + (a2 - a1) * t0)
    local xa, xb = x + w * t0, x + w * t1
    lg.polygon("fill", xa + k, y, xb + k, y, xb, y + h, xa, y + h)
  end
end
TV.slanted = slanted

--- medalhao redondo com icone (dourado quando escolhido)
function TV.medal(icon, cx, cy, r, c, on)
  local P = pal()
  lg.setColor(P.shade[1], P.shade[2], P.shade[3], 0.9)
  lg.circle("fill", cx + 1, cy + 2, r + 2)
  G.color(on and P.ring_on or P.ring_off)
  lg.circle("fill", cx, cy, r + 2)
  G.color(on and P.fill_on or P.fill_off)
  lg.circle("fill", cx, cy, r - 1)
  local isz = r * 1.25
  Icons.draw(icon, cx - isz / 2, cy - isz / 2, { 1, 1, 1 }, isz / 24)
end

--- lamina de espada (Moonlight Blade): cabo trancado, guarda redonda (onde fica
--- o icone) e lamina de aco com fio; a escolhida brilha em vermelho com um
--- reflexo passando
local function blade(x, y, w, h, on, pulse)
  local cy = y + h / 2
  local hx = x - 20
  -- cabo trancado
  lg.setColor(0.10, 0.08, 0.12, 1)
  lg.rectangle("fill", hx - 6, cy - 6, 26, 12, 3, 3)
  if on then lg.setColor(0.80, 0.08, 0.14, 1) else lg.setColor(0.45, 0.42, 0.50, 1) end
  for k = 0, 3 do
    local px = hx - 4 + k * 6
    lg.polygon("fill", px, cy, px + 3, cy - 5, px + 6, cy, px + 3, cy + 5)
  end
  local bx0, bx1 = x + 10, x + w
  local top, bot = cy - h * 0.30, cy + h * 0.30
  local s1 = on and { 0.92, 0.92, 0.96 } or { 0.30, 0.30, 0.38 }
  local s2 = on and { 0.66, 0.66, 0.74 } or { 0.17, 0.17, 0.23 }
  if on then
    for g = 5, 1, -1 do
      lg.setColor(0.95, 0.1, 0.15, 0.07 * pulse)
      local e = g * 2.4
      lg.polygon("fill", bx0 - e, top - e, bx1 - 18, top - e, bx1 + e + 4, cy, bx1 - 18, bot + e, bx0 - e, bot + e)
    end
  end
  -- corpo em faixas (degrade de cima para baixo) com ponta em bico
  local steps = 8
  for i = 0, steps - 1 do
    local t0, t1 = i / steps, (i + 1) / steps
    lg.setColor(s1[1] + (s2[1] - s1[1]) * t0, s1[2] + (s2[2] - s1[2]) * t0, s1[3] + (s2[3] - s1[3]) * t0, 1)
    local ya, yb = top + (bot - top) * t0, top + (bot - top) * t1
    -- a ponta: as faixas convergem para (bx1 + 4, cy)
    local tipa = bx1 - 18 + 22 * (1 - math.abs((ya - cy) / (bot - top) * 2))
    local tipb = bx1 - 18 + 22 * (1 - math.abs((yb - cy) / (bot - top) * 2))
    lg.polygon("fill", bx0, ya, tipa, ya, tipb, yb, bx0, yb)
  end
  -- fio (claro embaixo) e sulco
  lg.setColor(1, 1, 1, on and 0.9 or 0.30)
  lg.setLineWidth(1.5)
  lg.line(bx0, bot - 1, bx1 - 18, bot - 1, bx1 + 4, cy)
  lg.setColor(0, 0, 0, 0.3)
  lg.setLineWidth(1)
  lg.line(bx0, top + (bot - top) * 0.32, bx1 - 34, top + (bot - top) * 0.32)
  if on then
    lg.setColor(0.95, 0.1, 0.15, 0.95)
    lg.setLineWidth(2)
    lg.line(bx0, bot + 1, bx1 - 18, bot + 1, bx1 + 4, cy)
    lg.setLineWidth(1)
    if App.animations() then
      local k = (App.t * 0.6) % 1.4
      if k < 1 then
        local sx = bx0 + (bx1 - bx0 - 24) * k
        lg.setColor(1, 1, 1, 0.6)
        lg.polygon("fill", sx, top, sx + 10, top, sx - 2, bot, sx - 12, bot)
      end
    end
  end
end

--- desenha a lista de barras. o = { top, bottom, n, sel, item(i) -> { icon, color, label, right, dim },
---   x, w, aura (opcional, 0..1) }
function TV.draw_bars(st, o)
  -- Moonlight Blade: fileira de talismas de papel (ui/inkview.lua)
  if T.style.list == "blades" then return require("ui.inkview").talismans(st, o) end
  local top = o.top or 50
  local bottom = o.bottom or (T.H - 46)
  local x0, w = o.x or 14, o.w or 312
  local vis = math.max(1, math.floor((bottom - top - 24) / TV.BAR_STEP))
  local scroll = st.tvb_scroll or 0
  if o.sel - 1 < scroll then scroll = o.sel - 1 end
  if o.sel > scroll + vis then scroll = o.sel - vis end
  scroll = math.max(0, math.min(scroll, math.max(0, o.n - vis)))
  st.tvb_scroll = scroll
  local y0 = top + 14
  local orange, yellow = { 1.0, 0.50, 0.08 }, { 1.0, 0.86, 0.25 }
  local teal, sky = { 0.12, 0.70, 0.86 }, { 0.40, 0.85, 0.98 }
  local pulse = (App.pulse and App.animations()) and App.pulse(0.6, 0.4, 2.2) or 1
  local blades = T.style.list == "blades"
  local P = pal()
  for i = scroll + 1, math.min(o.n, scroll + vis) do
    local it = o.item(i)
    local y = y0 + (i - scroll - 1) * TV.BAR_STEP
    local on = i == o.sel
    local bx = x0 + 22 + (on and 6 or 0)
    local bw = w - 22 + (on and 10 or -10)
    -- sombra
    lg.setColor(0.02, 0.10, 0.28, blades and 0 or 0.35)
    lg.polygon("fill", bx + TV.BAR_SKEW + 3, y + 4, bx + bw + TV.BAR_SKEW + 3, y + 4, bx + bw + 3, y + TV.BAR_H + 4, bx + 3, y + TV.BAR_H + 4)
    if on then
      -- centro da opcao escolhida (para o efeito do A) e faiscas subindo
      require("ui.skyfx").focus = { bx + bw / 2, y + TV.BAR_H / 2 }
    end
    if blades then
      blade(bx, y, bw, TV.BAR_H, on, pulse)
    elseif on then
      -- aura de energia em volta da barra escolhida
      for g = 5, 1, -1 do
        lg.setColor(1.0, 0.75, 0.2, 0.06 * pulse)
        local e = g * 2.5
        lg.polygon("fill", bx + TV.BAR_SKEW - e, y - e, bx + bw + TV.BAR_SKEW + e, y - e, bx + bw + e, y + TV.BAR_H + e, bx - e, y + TV.BAR_H + e)
      end
      slanted(bx, y, bw, TV.BAR_H, orange, yellow, 1, 0.92)
    else
      slanted(bx, y, bw, TV.BAR_H, teal, sky, it.dim and 0.55 or 0.88, 0.15)
    end
    if not blades then
      -- brilho no alto da barra
      lg.setColor(1, 1, 1, on and 0.35 or 0.22)
      lg.polygon("fill", bx + TV.BAR_SKEW, y, bx + bw + TV.BAR_SKEW, y, bx + bw + TV.BAR_SKEW - 2, y + 4, bx + TV.BAR_SKEW - 2, y + 4)
    end
    if on then require("ui.skyfx").sparks(bx, y, bw, TV.BAR_H) end
    TV.medal(it.icon or "games", bx + 6, y + TV.BAR_H / 2, 15, it.color, on)
    local tx = bx + 30
    local rw = 0
    if it.right and it.right ~= "" then
      local rf = T.f.small
      local rs = require("lib.i18n").tr(it.right)
      rw = rf:getWidth(rs) + 10
      TV.outline_text(rf, rs, bx + bw - rw - 2, y + TV.BAR_H / 2 - rf:getHeight() / 2, on and { 1, 1, 1 } or { 0.85, 0.95, 1 })
    end
    local f = G.fit(T.f.bodyb, require("lib.i18n").tr(it.label or ""), bw - (tx - bx) - rw - 8)
    local lab = U.ellipsize(f, require("lib.i18n").tr(it.label or ""), bw - (tx - bx) - rw - 8)
    local tc = it.dim and not on and { 0.80, 0.88, 0.98 } or { 1, 1, 1 }
    local oc = nil
    if blades and on then tc, oc = { 0.08, 0.02, 0.04 }, { 1, 1, 1 } end
    TV.outline_text(f, lab, tx, y + TV.BAR_H / 2 - f:getHeight() / 2, tc, oc)
  end
  -- setas de rolagem (laranja, como no menu)
  local ax = x0 + w / 2
  if scroll > 0 then
    G.color(P.arrow); lg.polygon("fill", ax - 12, y0 - 2, ax + 12, y0 - 2, ax, y0 - 13)
  end
  if scroll + vis < o.n then
    local yb = y0 + vis * TV.BAR_STEP + 2
    G.color(P.arrow); lg.polygon("fill", ax - 12, yb, ax + 12, yb, ax, yb + 11)
  end
end

--- painel de detalhes do item escolhido (direita). o = { x, y, w, h, icon, color,
---   name, pills = { {txt, cor} }, text, rows = { {k, v} } }
function TV.draw_detail(o)
  -- Moonlight Blade: pergaminho aberto embaixo dos talismas
  if T.style.list == "blades" then
    local IV = require("ui.inkview")
    return IV.scroll({ icon = o.icon, name = o.name, pills = o.pills, rows = o.rows, text = o.text, image = o.image })
  end
  local x, y, w, h = o.x or 342, o.y or 54, o.w or (T.W - 342 - 12), o.h or (T.H - 54 - 48)
  local P = pal()
  local gold = P.frame
  lg.setColor(P.shade[1], P.shade[2], P.shade[3], 0.4)
  lg.rectangle("fill", x + 3, y + 5, w, h, 14, 14)
  lg.setColor(P.panel[1], P.panel[2], P.panel[3], P.panel[4])
  lg.rectangle("fill", x, y, w, h, 14, 14)
  G.frame(x, y, w, h, gold, 14, 2)
  G.frame(x + 4, y + 4, w - 8, h - 8, P.inner, 11, 1, 0.5)
  TV.medal(o.icon or "games", x + 34, y + 36, 22, o.color, true)
  local nf, nl, nlh = G.fit_lines(T.f.h2, o.name or "", w - 80, 2 * T.f.h2:getHeight(), true)
  local ny = y + 14
  if #nl == 1 then ny = y + 36 - nlh / 2 end
  for k, l in ipairs(nl) do TV.outline_text(nf, l, x + 66, ny + (k - 1) * nlh, { 1, 1, 1 }) end
  local cy = y + 72
  local px = x + 14
  for _, p in ipairs(o.pills or {}) do
    local tr = require("lib.i18n").tr(p[1] or "")
    if tr ~= "" then
      local pw = math.min(w - 28, T.f.small:getWidth(tr) + 18)
      if px + pw > x + w - 14 then px = x + 14; cy = cy + 26 end
      G.rect(px, cy, pw, 20, T.c.bg0, 10, 0.9)
      G.frame(px, cy, pw, 20, p[2] or gold, 10, 1)
      G.text_fit(T.f.small, tr, px + 9, cy + 10 - T.f.small:getHeight() / 2, pw - 18, T.c.dim)
      px = px + pw + 6
    end
  end
  cy = cy + 30
  for _, kv in ipairs(o.rows or {}) do
    if cy > y + h - 30 then break end
    G.text_fit(T.f.small, kv[1], x + 14, cy, 96, T.c.faint)
    G.text_fit(T.f.small, kv[2], x + 112, cy, w - 126, kv[3] or T.c.text)
    cy = cy + G.step(T.f.small, 17)
  end
  if o.rows and #o.rows > 0 then cy = cy + 6 end
  if o.text and o.text ~= "" then
    G.rect(x + 14, cy, w - 28, 1, gold, 0, 0.6)
    cy = cy + 8
    local f, ls = G.fit_lines(T.f.small, o.text, w - 28, y + h - 12 - cy, true)
    local lh = G.step(f, 16)
    for _, l in ipairs(ls) do G.text(f, l, x + 14, cy, T.c.dim); cy = cy + lh end
  end
end

--- navegacao das barras: cima/baixo um item, L1/R1 e esquerda/direita uma pagina
function TV.bars_nav(sel, n, act)
  if n == 0 then return nil end
  if T.style.list == "blades" then
    -- talismas: esquerda/direita (ou cima/baixo) um, L1/R1 seis
    if act == "left" or act == "up" then return math.max(1, sel - 1)
    elseif act == "right" or act == "down" then return math.min(n, sel + 1)
    elseif act == "l1" then return math.max(1, sel - 6)
    elseif act == "r1" then return math.min(n, sel + 6)
    end
    return nil
  end
  if act == "up" then return (sel - 2) % n + 1
  elseif act == "down" then return sel % n + 1
  elseif act == "l1" or act == "left" then return math.max(1, sel - 8)
  elseif act == "r1" or act == "right" then return math.min(n, sel + 8)
  end
  return nil
end

return TV
