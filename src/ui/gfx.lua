-- =============================================================================
--  Primitivas de desenho reutilizadas por todas as telas
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local I18N = require("lib.i18n")
local U = require("lib.util")
local lg = love.graphics

local G = { sx = 1, ox = 0, oy = 0 }

--- Recorte em coordenadas logicas (640x480), respeitando a escala da tela
-- Recortes aninhados: um recorte dentro de outro fica so na intersecao, e o
-- unclip volta ao recorte de fora (ex.: G.cover dentro da coluna de capas).
local CLIPS = {}
function G.clip(x, y, w, h)
  CLIPS[#CLIPS + 1] = { lg.getScissor() }
  local sx, sy = math.floor(G.ox + x * G.sx), math.floor(G.oy + y * G.sx)
  local sw, sh = math.ceil(w * G.sx), math.ceil(h * G.sx)
  if #CLIPS > 1 and CLIPS[#CLIPS][1] then
    lg.intersectScissor(sx, sy, math.max(0, sw), math.max(0, sh))
  else
    lg.setScissor(sx, sy, math.max(0, sw), math.max(0, sh))
  end
end
function G.unclip()
  local prev = table.remove(CLIPS)
  if prev and prev[1] then lg.setScissor(prev[1], prev[2], prev[3], prev[4]) else lg.setScissor() end
end
--- inicio de cada quadro: descarta recortes que ficaram abertos
function G.clip_reset()
  CLIPS = {}
  lg.setScissor()
end

function G.color(c, a)
  if a then lg.setColor(c[1], c[2], c[3], (c[4] or 1) * a) else lg.setColor(c) end
end

-- cantos: o tema pode deixar tudo mais reto (T.style.round < 1)
local function rr(r) return (r or 0) * (T.style.round or 1) end

function G.rect(x, y, w, h, c, r, a)
  G.color(c, a)
  r = rr(r)
  lg.rectangle("fill", x, y, w, h, r, r)
end

function G.frame(x, y, w, h, c, r, lw, a)
  G.color(c, a)
  lg.setLineWidth(lw or 1)
  r = rr(r)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
end

--- Painel com sombra e borda
function G.panel(x, y, w, h, opts)
  opts = opts or {}
  local r = opts.r or 8
  G.rect(x + 3, y + 4, w, h, T.c.shadow, r)
  G.rect(x, y, w, h, opts.bg or T.c.bg1, r)
  G.frame(x, y, w, h, opts.border or T.c.line, r, opts.lw or 1)
end

--- Texto (align: left/center/right) com limite de largura opcional
-- A fonte pixelada nao tem algumas maiusculas acentuadas (ex.: Í, Á):
-- troca so essas letras pela versao sem acento, para nao sumirem/aparecerem minusculas.
local FOLD = { ["Á"] = "A", ["À"] = "A", ["Â"] = "A", ["Ã"] = "A", ["É"] = "E", ["Ê"] = "E", ["Í"] = "I",
  ["Ó"] = "O", ["Ô"] = "O", ["Õ"] = "O", ["Ú"] = "U", ["Ç"] = "C" }
local function pixel_safe(font, s)
  if not (font == T.f.pix8 or font == T.f.pix16 or font == T.f.pix24) then return s end
  return (s:gsub("[\195][\128-\191]", function(ch)
    -- Á, Í, Ó, Ú e É existem na fonte, mas aparecem sem acento/minusculos: sempre troca
    if (ch == "Á" or ch == "Í" or ch == "Ó" or ch == "Ú" or ch == "É") or (FOLD[ch] and not font:hasGlyphs(ch)) then return FOLD[ch] end
    return ch
  end))
end

-- ---------------------------------------------------------------------------
-- Tamanho do texto maior que o padrao: quando o texto nao cabe no espaco que a
-- tela reservou, a fonte desce (ate o tamanho padrao) antes de cortar o texto.
-- No tamanho padrao nada muda: a lista de fontes menores tem so a propria fonte.

--- maior fonte da familia (do tamanho atual ao padrao) em que `s` cabe em `maxw`
function G.fit(font, s, maxw)
  local chain = T.shrink_chain(font)
  for _, f in ipairs(chain) do
    if f:getWidth(s) <= maxw then return f, true end
  end
  return chain[#chain], false
end

--- numero de linhas de `s` quebrado em `w`
local function nlines(font, s, w)
  local _, lines = font:getWrap(s, w)
  return math.max(1, #lines)
end

--- Texto quebrado em linhas dentro de uma caixa de altura `maxh`.
--- Devolve fonte, linhas, altura da linha e se precisou cortar. Desce a fonte
--- ate caber; se nem no tamanho padrao couber, corta e termina com "…".
--- plain = true: altura da linha sem o espacamento extra da fonte (getHeight).
function G.fit_lines(font, s, w, maxh, plain)
  s = U.safe_utf8(I18N.tr(s or ""))
  local chain = T.shrink_chain(font)
  local f, lines, lh
  for _, ff in ipairs(chain) do
    f = ff
    lh = plain and ff:getHeight() or ff:getHeight() * ff:getLineHeight()
    local _, ls = ff:getWrap(s, w)
    lines = ls
    if #ls * lh <= maxh + 0.5 then return f, lines, lh, false end
  end
  local maxl = math.max(1, math.floor((maxh + 0.5) / lh))
  local out = {}
  for k = 1, math.min(#lines, maxl) do out[k] = lines[k] end
  if #lines > maxl then out[maxl] = U.ellipsize(f, out[maxl] .. " …", w) end
  return f, out, lh, #lines > maxl
end

function G.text(font, s, x, y, c, align, w)
  s = U.safe_utf8(I18N.tr(s))
  if T.font_info[font] and T.base_font(font) ~= font then
    if align and w then
      -- caixa com largura: nao usa mais linhas do que o tamanho padrao usaria
      local want = nlines(T.base_font(font), s, w)
      for _, f in ipairs(T.shrink_chain(font)) do
        font = f
        if nlines(f, s, w) <= want then break end
      end
    elseif x + font:getWidth(s) > T.W - 4 then
      -- sem largura: nao deixa o texto sair da tela
      font = G.fit(font, s, T.W - 4 - x)
    end
  end
  lg.setFont(font)
  G.color(c or T.c.text)
  s = pixel_safe(font, s)
  if align and w then
    lg.printf(s, math.floor(x), math.floor(y), w, align)
  else
    lg.print(s, math.floor(x), math.floor(y))
  end
end

function G.text_fit(font, s, x, y, maxw, c)
  s = I18N.tr(s)
  font = G.fit(font, s, maxw)
  lg.setFont(font)
  G.color(c or T.c.text)
  lg.print(pixel_safe(font, U.ellipsize(font, s, maxw)), math.floor(x), math.floor(y))
end

--- Espaco entre linhas de uma tela feita para o tamanho padrao (px): cresce na
--- mesma proporcao da fonte quando o texto esta maior. No padrao devolve px.
function G.step(font, px)
  local base = T.base_font(font)
  if base == font then return px end
  return math.max(px, math.floor(px * font:getHeight() / base:getHeight() + 0.5))
end

--- Linha de lista com titulo e texto menor embaixo, feita para o tamanho padrao
--- (titulo em `ty`, texto de baixo em `sy`, dentro de `rowh` px). Devolve as
--- fontes e as posicoes que cabem: com texto maior, as fontes crescem enquanto
--- couberem (o titulo sobe um pouco se preciso); senao descem ate o padrao.
function G.row_fonts(rowh, ty, sy, tfont, sfont)
  tfont, sfont = tfont or T.f.bodyb, sfont or T.f.small
  local tb, sb = T.base_font(tfont), T.base_font(sfont)
  if tb == tfont and sb == sfont then return tfont, sfont, ty, sy end
  local gap = sy - ty - tb:getHeight()
  local limit = math.max(sy + sb:getHeight(), rowh - 1)
  local tc, sc = T.shrink_chain(tfont), T.shrink_chain(sfont)
  for i = 1, math.max(#tc, #sc) do
    local ft, fs = tc[math.min(i, #tc)], sc[math.min(i, #sc)]
    local total = ft:getHeight() + gap + fs:getHeight()
    local top = math.min(ty, limit - total)
    if top >= math.min(ty, 2) then return ft, fs, top, top + ft:getHeight() + gap end
  end
  return tb, sb, ty, sy
end

--- Quebra texto em linhas (para rolagem)
function G.wrap(font, s, w)
  local _, lines = font:getWrap(U.safe_utf8(I18N.tr(s)), w)
  return lines
end

--- Etiqueta arredondada (ex.: INSTALADO, categoria)
function G.tag(s, x, y, bg, fg, font)
  font = font or T.f.pix8
  s = I18N.tr(s)
  local w = font:getWidth(s) + 12
  local h = font:getHeight() + 8
  G.rect(x, y, w, h, bg, 4)
  G.text(font, s, x + 6, y + 4 + (font == T.f.pix8 and 0 or -1), fg or T.c.bg0)
  return w, h
end

--- Botao do controle desenhado (circulo com letra)
function G.button_icon(btn, x, y, override)
  local c = override or T.btn[btn] or T.c.dim
  if btn == "a" or btn == "b" or btn == "x" or btn == "y" then
    G.color(c)
    lg.circle("fill", x + 8, y + 8, 8)
    G.text(T.f.pix8, btn:upper(), x + 4, y + 4, T.c.bg0)
    return 16
  end
  if btn == "dpad" then
    -- direcional (cruz) com setinhas nas quatro pontas
    G.color(c)
    lg.rectangle("fill", x + 5, y, 6, 16, 1.5, 1.5)
    lg.rectangle("fill", x, y + 5, 16, 6, 1.5, 1.5)
    G.color(T.c.bg0)
    lg.polygon("fill", x + 8, y + 1.5, x + 6.5, y + 3.5, x + 9.5, y + 3.5)       -- cima
    lg.polygon("fill", x + 8, y + 14.5, x + 6.5, y + 12.5, x + 9.5, y + 12.5)    -- baixo
    lg.polygon("fill", x + 1.5, y + 8, x + 3.5, y + 6.5, x + 3.5, y + 9.5)       -- esquerda
    lg.polygon("fill", x + 14.5, y + 8, x + 12.5, y + 6.5, x + 12.5, y + 9.5)    -- direita
    lg.circle("fill", x + 8, y + 8, 1.2)
    return 16
  end
  local label = ({ l1 = "L1", r1 = "R1", l2 = "L2", r2 = "R2", start = "START", select = "SELECT" })[btn] or btn
  local f = T.f.pix8
  local w = f:getWidth(label) + 10
  G.rect(x, y + 1, w, 14, c, 7)
  G.text(f, label, x + 5, y + 4, T.c.bg0)
  return w
end

--- largura que as dicas ocupam com a fonte `font`
local HINT_LABEL = { l1 = "L1", r1 = "R1", l2 = "L2", r2 = "R2", start = "START", select = "SELECT" }
function G.hints_width(list, font)
  local tw = 14
  for _, h in ipairs(list) do
    local bw = (h[1] == "a" or h[1] == "b" or h[1] == "x" or h[1] == "y" or h[1] == "dpad") and 16
      or (T.f.pix8:getWidth(HINT_LABEL[h[1]] or h[1]) + 10)
    tw = tw + bw + 6 + font:getWidth(h[2]) + 16
  end
  return tw - 16
end

--- Barra de dicas de botoes no rodape (maxx: onde as dicas precisam terminar)
function G.hints(list, y, maxx)
  y = y or (T.H - 26)
  maxx = maxx or (T.W - 10)
  if T.style.chrome == "pill" then
    G.rect(8, y - 4, T.W - 16, 28, T.c.shadow, 14)
    G.rect(8, y - 6, T.W - 16, 28, T.c.bg1, 14)
    G.frame(8, y - 6, T.W - 16, 28, T.c.line, 14, 1)
  else
    G.rect(0, y - 6, T.W, 32, T.c.bg0, 0, 0.92)
    G.rect(0, y - 6, T.W, 1, T.c.line)
  end
  -- texto maior: se as dicas nao couberem na largura, a fonte delas desce
  local font
  for _, f in ipairs(T.shrink_chain(T.f.small)) do
    font = f
    if G.hints_width(list, f) <= maxx then break end
  end
  local x = 14
  for _, h in ipairs(list) do
    local w = G.button_icon(h[1], x, y)
    x = x + w + 6
    G.text(font, h[2], x, y + 1 + math.floor((T.f.small:getHeight() - font:getHeight()) / 2), T.c.dim)
    x = x + font:getWidth(h[2]) + 16
  end
  return x - 16
end

function G.progress(x, y, w, h, frac, c)
  frac = U.clamp(frac or 0, 0, 1)
  G.rect(x, y, w, h, T.c.bg0, h / 2)
  G.frame(x, y, w, h, T.c.line, h / 2)
  if frac > 0 then
    local fw = math.max(h, (w - 4) * frac)
    G.rect(x + 2, y + 2, fw, h - 4, c or T.c.accent2, (h - 4) / 2)
    -- brilho
    G.rect(x + 4, y + 3, math.max(0, fw - 4), math.max(1, math.floor((h - 4) / 3)), T.c.text, 1, 0.18)
  end
end

--- Barra indeterminada (quando nao se sabe o total)
function G.progress_busy(x, y, w, h, t, c)
  G.rect(x, y, w, h, T.c.bg0, h / 2)
  G.frame(x, y, w, h, T.c.line, h / 2)
  local seg = w * 0.25
  local pos = (t * 0.6 % 1) * (w + seg) - seg
  G.clip(x + 2, y + 2, w - 4, h - 4)
  G.rect(x + pos, y + 2, seg, h - 4, c or T.c.accent2, (h - 4) / 2)
  G.unclip()
end

-- Paleta para capas "genericas" (quando o port nao tem capa)
local PLACE = {
  { "#ff4f8b", "#5b2a86" }, { "#38d6ff", "#1f3a93" }, { "#ffd447", "#c0392b" },
  { "#3ddc84", "#16697a" }, { "#ff9f43", "#6d214f" }, { "#a29bfe", "#2d3436" },
}

local function initials(name)
  local out = {}
  for w in U.safe_utf8(name):gmatch("[%w]+") do
    out[#out + 1] = w:sub(1, 1):upper()
    if #out >= 2 then break end
  end
  return #out > 0 and table.concat(out) or "?"
end

--- Desenha a capa (imagem com ajuste "cover") ou uma capa gerada
function G.cover(img, p, x, y, w, h, loading, t)
  G.rect(x + 2, y + 3, w, h, T.c.shadow, 6)
  if img then
    local iw, ih = img:getDimensions()
    local s = math.max(w / iw, h / ih)
    local dw, dh = iw * s, ih * s
    G.clip(x, y, w, h)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, x + (w - dw) / 2, y + (h - dh) / 2, 0, s, s)
    G.unclip()
    G.frame(x, y, w, h, T.c.line, 4)
    return
  end
  G.clip(x, y, w, h)
  local seed = 0
  local name = p and p.name or "?"
  for i = 1, #name do seed = seed + name:byte(i) end
  local pal = PLACE[seed % #PLACE + 1]
  local c1, c2 = T.hex(pal[1]), T.hex(pal[2])
  -- gradiente simples em faixas (leve)
  local bands = 12
  for i = 0, bands - 1 do
    local k = i / (bands - 1)
    lg.setColor(c2[1] + (c1[1] - c2[1]) * k * 0.55, c2[2] + (c1[2] - c2[2]) * k * 0.55, c2[3] + (c1[3] - c2[3]) * k * 0.55, 1)
    lg.rectangle("fill", x, y + h * i / bands, w, h / bands + 1)
  end
  -- grade retro
  G.color(c1, 0.25)
  lg.setLineWidth(1)
  for gx = x + w / 6, x + w - 1, w / 6 do lg.line(gx, y + h * 0.62, x + w / 2 + (gx - x - w / 2) * 2.2, y + h) end
  for k = 0, 3 do
    local gy = y + h * 0.62 + (h * 0.38) * (k / 3) ^ 1.6
    lg.line(x, gy, x + w, gy)
  end
  -- sol
  G.color(c1, 0.9)
  lg.circle("fill", x + w / 2, y + h * 0.5, math.min(w, h) * 0.18)
  local f = w >= 120 and T.f.pix24 or (w >= 70 and T.f.pix16 or T.f.pix8)
  local s = initials(name)
  G.text(f, s, x + 1, y + h * 0.28 - f:getHeight() / 2 + 1, T.c.black, "center", w)
  G.text(f, s, x, y + h * 0.28 - f:getHeight() / 2, T.c.text, "center", w)
  if loading then
    local a = 0.5 + 0.5 * math.sin((t or 0) * 6)
    G.rect(x + w / 2 - 12, y + h - 12, 24, 4, T.c.text, 2, 0.3 + 0.5 * a)
  end
  G.unclip()
  G.frame(x, y, w, h, T.c.line, 4)
end

--- Fundo com grade e linhas de varredura (pre-renderizado uma vez)
--- Fundo "moderno": preto, brilho suave e faixas diagonais
local function background_modern(cv)
  lg.clear(T.c.bg0)
  local g = T.style.glow or T.c.accent
  -- brilho no canto superior direito (circulos concentricos bem suaves)
  for i = 30, 1, -1 do
    lg.setColor(g[1], g[2], g[3], 0.012)
    lg.circle("fill", T.W * 0.82, -40, i * 14)
  end
  -- faixa de luz na base
  for i = 0, 24 do
    lg.setColor(g[1], g[2], g[3], 0.018 * (1 - i / 24))
    lg.rectangle("fill", 0, T.H - i * 5, T.W, 5)
  end
  -- diagonais finas
  lg.setLineWidth(1)
  lg.setColor(1, 1, 1, 0.025)
  for x = -T.H, T.W, 26 do lg.line(x, T.H, x + T.H, 0) end
end

--- Fundo NEON GRID: quase preto, grade fina em perspectiva no chao, brilho
--- verde suave atras do cabecalho e uma linha de horizonte iluminada.
--- Desenhado uma vez num canvas (custo zero por quadro).
local function background_neongrid(cv)
  lg.clear(T.c.bg0)
  local g = T.style.glow or T.c.accent
  local a = T.c.accent
  -- brilho no alto, centralizado
  for i = 26, 1, -1 do
    lg.setColor(g[1], g[2], g[3], 0.010)
    lg.ellipse("fill", T.W * 0.5, -30, i * 20, i * 8)
  end
  -- grade do chao (perspectiva) abaixo do horizonte
  local hz = 300
  lg.setLineWidth(1)
  for i = -14, 14 do
    lg.setColor(a[1], a[2], a[3], 0.045)
    lg.line(T.W / 2 + i * 18, hz, T.W / 2 + i * 110, T.H)
  end
  for k = 1, 9 do
    local yy = hz + (T.H - hz) * (k / 9) ^ 1.9
    lg.setColor(a[1], a[2], a[3], 0.03 + 0.035 * (k / 9))
    lg.line(0, yy, T.W, yy)
  end
  -- horizonte iluminado
  for i = 0, 10 do
    lg.setColor(g[1], g[2], g[3], 0.05 * (1 - i / 10))
    lg.rectangle("fill", 0, hz - i, T.W, 1)
    lg.rectangle("fill", 0, hz + i, T.W, 1)
  end
  -- pontos da grade no alto (bem discretos)
  lg.setColor(1, 1, 1, 0.035)
  for y = 40, hz - 20, 24 do
    for x = 12, T.W, 24 do lg.rectangle("fill", x, y, 1, 1) end
  end
end

--- Fundo Wii Blue: azul profundo em degrade, luz suave no alto, faixas
--- horizontais bem discretas (como o menu de canais) e um arco claro na base.
--- Desenhado uma vez num canvas (custo zero por quadro).
local function background_wii(cv)
  local top, bot = T.c.bg1, T.c.bg0
  for i = 0, T.H - 1, 4 do
    local k = i / T.H
    lg.setColor(top[1] + (bot[1] - top[1]) * k, top[2] + (bot[2] - top[2]) * k, top[3] + (bot[3] - top[3]) * k, 1)
    lg.rectangle("fill", 0, i, T.W, 4)
  end
  local g = T.style.glow or T.c.accent
  -- luz suave no alto
  for i = 24, 1, -1 do
    lg.setColor(g[1], g[2], g[3], 0.014)
    lg.ellipse("fill", T.W * 0.5, -60, i * 22, i * 9)
  end
  -- faixas horizontais discretas
  lg.setColor(1, 1, 1, 0.022)
  for y = 0, T.H, 6 do lg.rectangle("fill", 0, y, T.W, 2) end
  -- arcos claros na base (lembra a barra curva do menu do Wii)
  lg.setLineWidth(2)
  for i = 0, 2 do
    lg.setColor(g[1], g[2], g[3], 0.10 - i * 0.03)
    lg.arc("line", "open", T.W / 2, T.H + 560 - i * 10, 640, -math.pi * 0.86, -math.pi * 0.14, 48)
  end
  lg.setLineWidth(1)
end

--- Fundo Pastel Pop: moldura em degrade (ciano -> azul -> roxo), area clara
--- arredondada com grade de pontos e formas pastel desfocadas nos cantos.
--- Desenhado uma vez num canvas (custo zero por quadro).
local function background_pastel(cv)
  -- moldura em degrade diagonal
  local c1, c2, c3 = { 0.33, 0.80, 0.98 }, { 0.40, 0.55, 0.98 }, { 0.68, 0.45, 0.97 }
  for y = 0, T.H - 1, 2 do
    for x = 0, T.W - 1, 16 do
      local k = (x / T.W + y / T.H) / 2
      local a, b, t
      if k < 0.5 then a, b, t = c1, c2, k * 2 else a, b, t = c2, c3, (k - 0.5) * 2 end
      lg.setColor(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1)
      lg.rectangle("fill", x, y, 16, 2)
    end
  end
  -- area clara arredondada
  G.rect(4, 4, T.W - 8, T.H - 8, T.c.bg0, 16)
  -- grade de pontos
  lg.setColor(T.c.faint[1], T.c.faint[2], T.c.faint[3], 0.16)
  for y = 14, T.H - 10, 10 do
    for x = 14, T.W - 10, 10 do lg.rectangle("fill", x, y, 1, 1) end
  end
  -- formas pastel "desfocadas" (camadas com pouca opacidade)
  local function blob(x, y, w, h, c, rot)
    lg.push(); lg.translate(x + w / 2, y + h / 2); lg.rotate(rot or 0)
    for i = 10, 1, -1 do
      lg.setColor(c[1], c[2], c[3], 0.045)
      local g = i * 2.4
      lg.rectangle("fill", -w / 2 - g, -h / 2 - g, w + 2 * g, h + 2 * g, 14 + g, 14 + g)
    end
    lg.setColor(c[1], c[2], c[3], 0.20)
    lg.rectangle("fill", -w / 2, -h / 2, w, h, 14, 14)
    lg.pop()
  end
  blob(548, 26, 62, 56, { 0.86, 0.55, 0.98 }, 0.12)    -- roxo/rosa (alto, direita)
  blob(12, 300, 52, 60, { 0.98, 0.55, 0.60 }, -0.2)    -- vermelho claro (esquerda)
  blob(500, 330, 70, 50, { 0.45, 0.90, 0.65 }, 0.05)   -- verde (direita, baixo)
  blob(200, 18, 46, 40, { 0.45, 0.85, 0.95 }, -0.1)    -- ciano (alto)
end

function G.build_background()
  if G.bg and G.bg.release then G.bg:release() end
  local cv = lg.newCanvas(T.W, T.H)
  lg.setCanvas(cv)
  if T.style.background == "pastel" then
    background_pastel(cv)
    lg.setCanvas()
    G.bg = cv
    return
  end
  if T.style.background == "wii" then
    background_wii(cv)
    lg.setCanvas()
    G.bg = cv
    return
  end
  if T.style.background == "neongrid" then
    background_neongrid(cv)
    lg.setCanvas()
    G.bg = cv
    return
  end
  if T.style.background == "modern" then
    background_modern(cv)
    lg.setCanvas()
    G.bg = cv
    return
  end
  lg.clear(T.c.bg0)
  -- brilho superior
  local g = T.style.glow or { 0.22, 0.12, 0.4 }
  for i = 0, 40 do
    local k = 1 - i / 40
    lg.setColor(g[1], g[2], g[3], 0.035 * k)
    lg.rectangle("fill", 0, 0, T.W, 8 + i * 6)
  end
  -- grade de perspectiva no rodape
  lg.setLineWidth(1)
  lg.setColor(T.c.accent[1], T.c.accent[2], T.c.accent[3], 0.06)
  for i = -12, 12 do
    lg.line(T.W / 2 + i * 22, 300, T.W / 2 + i * 120, T.H)
  end
  for k = 0, 8 do
    local yy = 300 + (T.H - 300) * (k / 8) ^ 1.8
    lg.line(0, yy, T.W, yy)
  end
  -- scanlines
  if T.style.scanlines ~= false then
    lg.setColor(0, 0, 0, 0.16)
    for yy = 0, T.H, 3 do lg.rectangle("fill", 0, yy, T.W, 1) end
  end
  lg.setCanvas()
  G.bg = cv
end

function G.background()
  lg.setColor(1, 1, 1, 1)
  lg.draw(G.bg, 0, 0)
end

--- Logo do hub (texto pixelado com sombra colorida)
-- Logo oficial (imagem). Tamanhos pre-gerados para ficar nitido em 640x480.
local LOGOS = {}
--- logo do app: o tema pode trazer a propria (themes/<id>/logo_<variante>.png);
--- sem ela, usa a logo original. So as logos do tema atual ficam na memoria.
local function logo_img(variant)
  local dir = T.style.logo_dir
  local key = (dir or "") .. "|" .. variant
  if LOGOS._dir ~= (dir or "") then
    for k, img in pairs(LOGOS) do if type(img) == "userdata" and img.release then img:release() end end
    LOGOS = { _dir = dir or "" }
  end
  if LOGOS[key] == nil then
    local img
    if dir then
      local ok, im = pcall(love.graphics.newImage, dir .. "/logo_" .. variant .. ".png")
      if ok then img = im end
    end
    if not img then
      local ok, im = pcall(love.graphics.newImage, "assets/logo/logo_" .. variant .. ".png")
      if ok then img = im end
    end
    LOGOS[key] = img or false
  end
  return LOGOS[key] or nil
end

--- Desenha o logo. variant: "menu" (padrao) | "about" | "header". Devolve largura, altura
function G.logo(x, y, variant)
  local img = logo_img(variant or "menu")
  if img then
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, math.floor(x), math.floor(y))
    return img:getWidth(), img:getHeight()
  end
  -- reserva: texto (se a imagem faltar)
  local f = variant == "header" and T.f.pix8 or T.f.pix16
  G.text(f, L("R36S PORT HUB"), x, y + 4, T.c.text)
  return f:getWidth("R36S PORT HUB"), f:getHeight() + 8
end

-- ---------------------------------------------------------------------------
-- Cartoes do tema (componente compartilhado pelos temas)
-- Canais da tela inicial, areas da Central, categorias e cartoes de
-- configuracao usam o mesmo cartao. O tema decide a aparencia:
--   style.card   = cores proprias do cartao (Wii Blue: branco com texto escuro)
--   style.effect = "soft" (halo azul e leve aumento) | "neon" (contorno luminoso
--                  e cantos de mira) | nil (moldura simples, Tema Padrao)
-- A funcao devolve a paleta que o conteudo do cartao deve usar.

local FK = {}
--- animacao do foco (0..1) de um cartao identificado por `key`
function G.focus_k(key, on)
  local target = on and 1 or 0
  if not (App and App.animations and App.animations()) then FK[key] = target; return target end
  local v = FK[key] or target
  v = v + (target - v) * math.min(1, love.timer.getDelta() * 14)
  if math.abs(v - target) < 0.01 then v = target end
  FK[key] = v
  return v
end

--- paleta do conteudo dos cartoes (sem desenhar)
function G.card_palette(on)
  local cd = T.style.card
  if cd then
    return { text = cd.text, dim = cd.dim or cd.text, faint = cd.faint or cd.dim or cd.text,
      icon = on and (T.style.focus or cd.icon or T.c.accent) or (cd.icon or T.c.accent), light = (cd.fill[1] + cd.fill[2] + cd.fill[3]) > 2 }
  end
  return { text = on and T.c.text or T.c.dim, dim = on and T.c.dim or T.c.faint, faint = T.c.faint,
    icon = on and T.c.accent or T.c.dim }
end

--- cor de status legivel dentro do cartao: em cartao claro (Wii Blue) a cor
--- fica mais escura para manter o contraste com o fundo branco
function G.ink(c, pal)
  if not (pal and pal.light) then return c end
  return { c[1] * 0.62, c[2] * 0.62, c[3] * 0.62, c[4] or 1 }
end

--- Desenha o cartao. on = selecionado; k = animacao do foco (0..1, opcional).
--- Devolve paleta, x, y, w, h (posicao final, ja com o aumento do foco).
function G.card(x, y, w, h, on, k, r, tint)
  k = k or (on and 1 or 0)
  r = r or 10
  local st, cd = T.style, T.style.card
  local fc = st.focus or T.c.accent
  if st.effect == "soft" and k > 0 then
    local g = 3 * k
    x, y, w, h = x - g, y - g, w + 2 * g, h + 2 * g
  elseif st.effect == "pop" then
    -- Pastel Pop: cartao "salta" (sobe e cresce um pouco), borda colorida
    local g = 2 * k
    x, y, w, h = x - g, y - g - 3 * k, w + 2 * g, h + 2 * g
    r = r + 4
    G.rect(x + 1, y + 5 + 3 * k, w, h, T.c.shadow, r)
    G.rect(x + 2, y + 3, w - 4, h, T.c.shadow, r)
    if k > 0 then
      local c2 = T.c.accent2
      for i = 5, 1, -1 do G.frame(x - i * 1.6, y - i * 1.6, w + i * 3.2, h + i * 3.2, i % 2 == 0 and fc or c2, r + i * 1.6, 2, 0.07 * k) end
    end
    G.rect(x, y, w, h, cd and cd.fill or T.c.bg1, r)
    local bc = tint or (cd and cd.line) or T.c.line
    G.frame(x, y, w, h, bc, r, tint and 2 or 1, tint and 0.75 or 1)
    if k > 0 then
      G.frame(x, y, w, h, fc, r, 3, k)
      G.frame(x + 3, y + 3, w - 6, h - 6, T.c.accent2, r - 3, 1, 0.5 * k)
    end
    return G.card_palette(on), x, y, w, h
  end
  -- sombra
  G.rect(x + 2, y + 4, w, h, T.c.shadow, r)
  -- halo do foco (por baixo do cartao)
  if k > 0 and st.effect == "soft" then
    for i = 4, 1, -1 do G.frame(x - i * 1.5, y - i * 1.5, w + i * 3, h + i * 3, fc, r + i, 2, 0.10 * k) end
  elseif k > 0 and st.effect == "neon" then
    for i = 3, 1, -1 do G.frame(x - i * 2, y - i * 2, w + i * 4, h + i * 4, fc, r + i * 2, 2, 0.09 * k) end
  end
  if cd then
    G.rect(x, y, w, h, cd.fill, r)
    if on and st.effect == "neon" then G.rect(x, y, w, h, fc, r, 0.07 * k) end
    G.frame(x, y, w, h, cd.line or T.c.line, r, 1)
  else
    G.rect(x, y, w, h, on and T.c.bg2 or T.c.bg1, r)
    G.frame(x, y, w, h, T.c.line, r, 1)
  end
  if k > 0 then
    G.frame(x, y, w, h, fc, r, 2, (st.effect == "neon" and App and App.pulse) and App.pulse(0.85, 0.15, 2.2) * k or k)
    if st.effect == "neon" then
      -- cantos de mira
      local c, l = 10, 2
      G.color(fc, k)
      lg.rectangle("fill", x - 3, y - 3, c, l); lg.rectangle("fill", x - 3, y - 3, l, c)
      lg.rectangle("fill", x + w + 3 - c, y - 3, c, l); lg.rectangle("fill", x + w + 1, y - 3, l, c)
      lg.rectangle("fill", x - 3, y + h + 1, c, l); lg.rectangle("fill", x - 3, y + h + 3 - c, l, c)
      lg.rectangle("fill", x + w + 3 - c, y + h + 1, c, l); lg.rectangle("fill", x + w + 1, y + h + 3 - c, l, c)
    end
  end
  return G.card_palette(on), x, y, w, h
end

--- Cabecalho padrao das telas da loja
function G.header(title, right)
  if T.style.chrome == "pill" then
    G.rect(8, 6, T.W - 16, 36, T.c.shadow, 18)
    G.rect(8, 4, T.W - 16, 36, T.c.bg1, 18)
    G.frame(8, 4, T.W - 16, 36, T.c.line, 18, 1)
  else
    G.rect(0, 0, T.W, 40, T.c.bg0, 0, 0.85)
    G.rect(0, 40, T.W, 1, T.c.line)
    G.rect(0, 40, 120, 1, T.c.accent)
    G.rect(120, 40, 80, 1, T.c.accent2)
  end
  local pill = T.style.chrome == "pill"
  local lw = G.logo(pill and 20 or 12, pill and 6 or 4, "header")
  if pill then lw = lw + 8 end
  -- relogio (hora do sistema do console) sempre no canto direito
  local clock = require("core.clock").time()
  local cf = T.base_font(T.f.bodyb)   -- a faixa tem 40 px: relogio no tamanho padrao
  local cw = cf:getWidth(clock)
  G.text(cf, clock, T.W - (pill and 24 or 14) - cw, 11, T.c.text)
  if pill then cw = cw + 10 end
  local tx = 12 + lw + 24
  local limit = T.W - 14 - cw - 12          -- onde o texto da faixa precisa parar
  local room = limit - tx
  local tw = title and T.f.h3:getWidth(I18N.tr(title)) or 0
  if right and right ~= "" then
    -- se titulo e texto da direita nao couberem juntos, a direita fica com no
    -- maximo 40% da faixa (encolhe a fonte e, se preciso, corta com "…")
    local rwf = T.f.small:getWidth(I18N.tr(right))
    local maxr = rwf
    if tw + 12 + rwf > room then maxr = math.max(math.floor(room * 0.4), room - 12 - tw) end
    local rf = G.fit(T.f.small, right, maxr)
    local rw = math.min(maxr, rf:getWidth(I18N.tr(right)))
    local rx = limit - rw
    G.text_fit(rf, right, rx, 13 + math.floor((T.f.small:getHeight() - rf:getHeight()) / 2), maxr, T.c.dim)
    G.rect(T.W - 14 - cw - 7, 13, 1, 14, T.c.line)
    limit = rx - 12
  end
  if title then
    G.rect(12 + lw + 12, 10, 1, 20, T.c.line)
    local tf = G.fit(T.f.h3, title, limit - tx)
    G.text_fit(tf, title, tx, 10 + math.floor((T.base_font(T.f.h3):getHeight() - tf:getHeight()) / 2), limit - tx, T.c.text)
  end
end

return G
