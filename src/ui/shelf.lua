-- =============================================================================
--  Biblioteca em PRATELEIRAS (Pastel Pop Edition: layout "carousel")
--  Duas fileiras horizontais, como nos menus do 3DS/Wii U:
--    - em cima, os consoles (Recentes, Favoritos e os sistemas com jogos);
--    - embaixo, os jogos do console escolhido, com as capas do gamelist.
--  Cima/baixo trocam de fileira; esquerda/direita andam na fileira.
--  A num console desce para os jogos; A num jogo joga. B num jogo volta para
--  os consoles; B nos consoles sai. X: emulador (do console ou do jogo);
--  SELECT: favoritar o jogo; Y: procurar de novo (consoles) ou info (jogo).
--  Os icones dos consoles sao silhuetas genericas por tipo de aparelho
--  (sem logotipos de fabricantes).
--  So desenho e navegacao: dados, jogar e emulador sao os da Biblioteca.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Lib = require("core.library")
local Icons = require("ui.icons")
local lg = love.graphics

local SH = {}

-- tipo de aparelho de cada sistema (nome do es_systems.cfg)
local KIND = {}
local function kinds(icon, list) for n in list:gmatch("%S+") do KIND[n] = icon end end
kinds("sys_handheld", "psp pspminis psvita gba gamegear gg ngp ngpc wonderswan wonderswancolor wsc lynx atarilynx supervision")
kinds("sys_vertical", "gb gbc gameboy gbh pokemini")
kinds("sys_dual", "nds 3ds")
kinds("sys_cart", "nes famicom fds snes sfc snesh sufami satellaview n64 genesis megadrive md mastersystem sms sg-1000 sg1000 "
  .. "atari2600 atari5200 atari7800 jaguar colecovision intellivision pcengine tg16 turbografx tg-16 32x sega32x vectrex "
  .. "virtualboy odyssey2 videopac channelf arduboy")
kinds("sys_disc", "psx ps1 ps2 segacd megacd saturn dreamcast gc gamecube wii pcenginecd tg-cd 3do cdi neocd pcfx")
kinds("sys_arcade", "arcade mame mame2000 mame2003 mame2003plus mame2010 mame2016 fbneo fba fbalpha neogeo cps1 cps2 cps3 naomi atomiswave daphne")
kinds("sys_computer", "dos pc amiga amigacd32 c64 c128 vic20 msx msx2 zxspectrum zx81 amstradcpc atari800 atarist x68000 pc98 pc88 apple2 scummvm bbcmicro")
kinds("games", "ports")

local PAL = { "#8b5cf6", "#f97316", "#ec4899", "#06b6d4", "#eab308", "#22c55e", "#6366f1", "#0ea5e9", "#f43f5e", "#14b8a6" }
local pal_cache = {}
local function color_for(key)
  local c = pal_cache[key]
  if not c then
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 1000003 end
    c = T.parse_hex(PAL[h % #PAL + 1])
    pal_cache[key] = c
  end
  return c
end

-- ---------------------------------------------------------------------------
-- Icones de console, nesta ordem:
--   1. do usuario: <pasta do hub>/icones/sistemas/<sistema>.png
--   2. do projeto: assets/systems/<sistema>.png (arte original do hub)
--   3. silhueta da familia de linha
-- (nome do sistema no es_systems.cfg, em minusculas)
local C = require("config")
local USER_DIR = C.APP_DIR .. "/icones/sistemas/"
local SYS_PX = 160
local sys_imgs, sys_wait = {}, 0     -- [nome] = canvas | false (sem arquivo/erro)

local function load_sys_icon(name)
  local path = USER_DIR .. name .. ".png"
  local f = io.open(path, "rb")
  if not f then
    -- icones do proprio projeto (arte original: tools/make_system_icons.py)
    local ap = "assets/systems/" .. name .. ".png"
    if love.filesystem.getInfo(ap) then
      local ok, img = pcall(lg.newImage, ap, { mipmaps = true })
      if ok and img then
        img:setFilter("linear", "linear")
        pcall(img.setMipmapFilter, img, "linear")
        return img
      end
    end
    return false
  end
  local size = f:seek("end")
  if size > 4 * 1024 * 1024 then f:close(); return false end
  f:seek("set", 0)
  local data = f:read("*a")
  f:close()
  local ok, cv = pcall(function()
    local img = lg.newImage(love.image.newImageData(love.filesystem.newFileData(data, "icone")))
    img:setFilter("linear", "linear")
    local iw, ih = img:getDimensions()
    local c = lg.newCanvas(SYS_PX, SYS_PX)
    local prev = lg.getCanvas()
    local sc = { lg.getScissor() }
    lg.setScissor()
    lg.push("all")
    lg.setCanvas(c)
    lg.clear(0, 0, 0, 0)
    lg.origin()
    local s = math.min(SYS_PX / iw, SYS_PX / ih)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, (SYS_PX - iw * s) / 2, (SYS_PX - ih * s) / 2, 0, s, s)
    lg.pop()
    lg.setCanvas(prev)
    if sc[1] then lg.setScissor(sc[1], sc[2], sc[3], sc[4]) end
    img:release()
    c:setFilter("linear", "linear")
    return c
  end)
  return ok and cv or false
end

local function sys_key(it) return it.sys and (it.sys.name or ""):lower() or nil end

--- icone do usuario ja carregado (ou nil)
local function user_icon(it)
  local k = sys_key(it)
  local v = k and sys_imgs[k]
  return v or nil
end

local function sys_icon(it)
  if it.special == "recent" then return "set_clock" end
  if it.special == "favs" then return "set_favorites" end
  return KIND[(it.sys.name or ""):lower()] or "sys_console"
end
local function sys_color(it)
  if it.special == "recent" then return T.c.accent2 end
  if it.special == "favs" then return T.parse_hex("#eab308") end
  return color_for(it.sys.name or "?")
end
local function sys_title(it)
  if it.special then return it.label end
  return it.sys.fullname
end

--- jogos de um item da fileira de cima ({ sys, g } como na tela de jogos)
function SH.games_for(it)
  local list = {}
  if it.sys then
    for _, g in ipairs(it.sys.games) do list[#list + 1] = { sys = it.sys, g = g } end
  elseif it.special == "favs" then
    for _, s in ipairs(Lib.systems) do
      for _, g in ipairs(s.games) do if Lib.is_fav(g) then list[#list + 1] = { sys = s, g = g } end end
    end
    table.sort(list, function(a, b) return a.g.name:lower() < b.g.name:lower() end)
  elseif it.special == "recent" then
    for _, r in ipairs(Lib.recent()) do
      local s, g = Lib.find_game(r.file)
      if s then list[#list + 1] = { sys = s, g = g } end
    end
  end
  return list
end

-- ---------------------------------------------------------------------------
-- Miniaturas das capas (gamelist.xml): carregadas uma por vez, reduzidas para
-- 120x160 (pouca memoria) e guardadas num cache pequeno.
local THUMB_W, THUMB_H, THUMB_MAX = 120, 160, 14
local thumbs, thumb_order = {}, {}

local function thumb_drop_old()
  while #thumb_order > THUMB_MAX do
    local k = table.remove(thumb_order, 1)
    local t = thumbs[k]
    if t and t ~= false and t.release then t:release() end
    thumbs[k] = nil
  end
end

local function load_thumb(path)
  local ok, cv = pcall(function()
    local f = io.open(path, "rb")
    if not f then error("sem arquivo") end
    local size = f:seek("end")
    if size > 3 * 1024 * 1024 then f:close(); error("grande demais") end
    f:seek("set", 0)
    local data = f:read("*a")
    f:close()
    local img = lg.newImage(love.image.newImageData(love.filesystem.newFileData(data, "capa")))
    img:setFilter("linear", "linear")
    local iw, ih = img:getDimensions()
    local c = lg.newCanvas(THUMB_W, THUMB_H)
    local prev = lg.getCanvas()
    local sc = { lg.getScissor() }
    lg.setScissor()
    lg.push("all")
    lg.setCanvas(c)
    lg.clear(0, 0, 0, 0)
    lg.origin()
    local s = math.max(THUMB_W / iw, THUMB_H / ih)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, (THUMB_W - iw * s) / 2, (THUMB_H - ih * s) / 2, 0, s, s)
    lg.pop()
    lg.setCanvas(prev)
    if sc[1] then lg.setScissor(sc[1], sc[2], sc[3], sc[4]) end
    img:release()
    c:setFilter("linear", "linear")
    return c
  end)
  return ok and cv or false
end

local function thumb(path)
  local t = thumbs[path]
  if t then return t end
  return nil
end

function SH.release()
  for _, t in pairs(thumbs) do if t and t.release then t:release() end end
  thumbs, thumb_order = {}, {}
  for _, t in pairs(sys_imgs) do if t and t.release then t:release() end end
  sys_imgs = {}
end

-- ---------------------------------------------------------------------------
local function anim(v, target, dt)
  if not App.animations() then return target end
  v = v or target
  v = v + (target - v) * math.min(1, dt * 12)
  if math.abs(v - target) < 0.01 then v = target end
  return v
end

function SH.update(self, dt)
  self.sh_spos = anim(self.sh_spos, self.sel, dt)
  self.sh_gpos = anim(self.sh_gpos, self.gsel or 1, dt)
  -- icones de console do usuario: um por vez, primeiro os visiveis
  sys_wait = sys_wait + dt
  if sys_wait >= 0.05 then
    local function next_sys()
      for d = 0, 8 do
        for _, i in ipairs(d == 0 and { self.sel } or { self.sel + d, self.sel - d }) do
          local it = self.items[i]
          local k = it and sys_key(it)
          if k and sys_imgs[k] == nil then return k end
        end
      end
    end
    local k = next_sys()
    if k then sys_wait = 0; sys_imgs[k] = load_sys_icon(k) end
  end
  -- carrega uma capa por vez (as do jogo escolhido e das vizinhas)
  self.sh_wait = (self.sh_wait or 0) + dt
  if self.sh_wait < 0.08 then return end
  local list = self.games or {}
  local g0 = self.gsel or 1
  for d = 0, 5 do
    for _, i in ipairs(d == 0 and { g0 } or { g0 + d, g0 - d }) do
      local it = list[i]
      local p = it and it.g.image
      if p and thumbs[p] == nil then
        self.sh_wait = 0
        thumbs[p] = load_thumb(p)
        thumb_order[#thumb_order + 1] = p
        thumb_drop_old()
        return
      end
    end
  end
end

-- posicao x de um item numa fileira com o escolhido em x0
local function row_x(d, x0, big, small, gap)
  local x = x0 + d * (small + gap)
  if d > 0 then x = x + (big - small) * math.min(1, d) end
  return x
end

local function draw_row(n, pos, sel, x0, y, bw, bh, sw, shh, gap, focus, draw)
  local first = math.max(1, math.floor(pos) - 2)
  local last = math.min(n, math.ceil(pos) + 7)
  for i = first, last do
    local d = i - pos
    local s = math.max(0, 1 - math.abs(d))
    local w = sw + (bw - sw) * s
    local h = shh + (bh - shh) * s
    local x = row_x(d, x0, bw, sw, gap)
    if x < T.W + 10 and x + w > -10 then draw(i, x, y, w, h, i == sel, focus and i == sel) end
  end
end

-- pilula de texto
local function pill(text, x, y, c, maxw)
  local f = T.f.small
  local w = math.min(maxw or 300, f:getWidth(I18N.tr(text)) + 22)
  G.rect(x, y, w, 22, T.c.bg1, 11)
  G.frame(x, y, w, 22, c or T.c.line, 11, 1)
  G.text_fit(f, text, x + 11, y + 11 - f:getHeight() / 2, w - 22, T.c.dim)
  return w
end

local function njogos(n) return string.format(I18N.tr(n == 1 and L("%d jogo") or L("%d jogos")), n) end

local SROW_Y, GROW_Y = 54, 236
local SB, SS = 108, 80              -- consoles: escolhido / outros
local GBW, GBH, GSW, GSH = 120, 160, 82, 110   -- jogos: escolhido / outros
local X0 = 36

function SH.draw(self)
  local items = self.items
  local n = #items
  local sfocus = (self.focus or "sys") == "sys"
  -- ---------------- consoles
  draw_row(n, self.sh_spos or self.sel, self.sel, X0, SROW_Y, SB, SB, SS, SS, 14, sfocus, function(i, x, y, w, h, on, foc)
    local it = items[i]
    local c = sys_color(it)
    local k = G.focus_k("shs" .. i, foc)
    local ui = user_icon(it)
    -- com icone proprio, o cartao fica sem borda colorida (o icone ja tem a dele)
    local pal, cx, cy, cw, chh = G.card(x, y, w, h, foc, k, 12, (not ui) and c or nil)
    if ui then
      -- icone do usuario ocupa o cartao (ele ja traz moldura e arte proprias)
      lg.setColor(1, 1, 1, 1)
      lg.draw(ui, cx, cy, 0, cw / ui:getWidth(), chh / ui:getHeight())
    else
      G.rect(cx + 4, cy + 4, cw - 8, chh - 8, c, 10, on and 0.12 or 0.06)
      local isz = w * 0.46
      Icons.draw(sys_icon(it), cx + (cw - isz) / 2, cy + (chh - isz) / 2 - 8, c, isz / 24)
      local lab = it.special and U.upper(it.label) or U.upper(it.sys.name or "")
      G.text_fit(T.f.pix8, lab, cx + 8 + math.max(0, (cw - 16 - T.f.pix8:getWidth(I18N.tr(lab))) / 2), cy + chh - 20, cw - 16, on and c or T.c.faint)
    end
    if on and not foc then G.frame(cx, cy, cw, chh, c, 16, 2) end
  end)
  local cur = items[self.sel]
  local cc = sys_color(cur)
  -- nome do console + quantidade de jogos (ao lado do escolhido, embaixo das outras)
  local nx = X0 + SB + 18
  local nf = G.fit(T.f.h1, sys_title(cur), T.W - nx - 20)
  G.text(nf, sys_title(cur), nx, SROW_Y + SS + 12, T.c.text)
  local py = SROW_Y + SS + 14 + nf:getHeight() + 4
  local pw = pill(njogos(#(self.games or {})), nx, py, cc)
  if cur.sys and cur.sys.manufacturer and cur.sys.manufacturer ~= "" then
    pill(cur.sys.manufacturer .. ((cur.sys.release and cur.sys.release ~= "" and cur.sys.release ~= "unknown") and ("  •  " .. cur.sys.release) or ""), nx + pw + 8, py, T.c.line, T.W - nx - pw - 30)
  end
  -- seta: indica a fileira de jogos embaixo
  G.color(sfocus and cc or T.c.line)
  local ax = X0 + SB / 2
  lg.polygon("fill", ax - 9, SROW_Y + SB + 12, ax + 9, SROW_Y + SB + 12, ax, SROW_Y + SB + 22)
  -- ---------------- jogos
  local list = self.games or {}
  if #list == 0 then
    local msg = cur.special == "favs" and L("Nenhum favorito ainda. Aperte SELECT num jogo para marcar.")
      or (cur.special == "recent" and L("Nenhum jogo aberto pelo hub ainda.") or L("Nenhum jogo neste sistema."))
    G.rect(X0, GROW_Y + 20, T.W - 2 * X0, 90, T.c.bg1, 18)
    G.frame(X0, GROW_Y + 20, T.W - 2 * X0, 90, T.c.line, 18, 1)
    G.text(T.f.body, msg, X0 + 20, GROW_Y + 56, T.c.dim, "center", T.W - 2 * X0 - 40)
    return
  end
  local gsel = self.gsel or 1
  draw_row(#list, self.sh_gpos or gsel, gsel, X0, GROW_Y, GBW, GBH, GSW, GSH, 12, not sfocus, function(i, x, y, w, h, on, foc)
    local it = list[i]
    local k = G.focus_k("shg" .. i, foc)
    -- moldura branca com borda (cor do console do jogo)
    local c = color_for(it.sys.name or "?")
    local g = foc and (3 * k) or 0
    G.rect(x - g + 2, y - g - 3 * k + 5, w + 2 * g, h + 2 * g, T.c.shadow, 12)
    if foc then
      for gg = 4, 1, -1 do G.frame(x - g - gg * 1.6, y - g - 3 * k - gg * 1.6, w + 2 * g + gg * 3.2, h + 2 * g + gg * 3.2, gg % 2 == 0 and T.c.accent or T.c.accent2, 12 + gg, 2, 0.08 * k) end
    end
    local fx, fy, fw, fh = x - g, y - g - 3 * k, w + 2 * g, h + 2 * g
    G.rect(fx, fy, fw, fh, T.c.bg1, 12)
    local tb = it.g.image and thumb(it.g.image)
    if tb then
      G.clip(fx + 4, fy + 4, fw - 8, fh - 8)
      lg.setColor(1, 1, 1, 1)
      lg.draw(tb, fx + 4, fy + 4, 0, (fw - 8) / THUMB_W, (fh - 8) / THUMB_H)
      G.unclip()
    else
      G.cover(nil, { name = it.g.name }, fx + 4, fy + 4, fw - 8, fh - 8, false, App.t)
    end
    G.frame(fx, fy, fw, fh, foc and T.c.accent or c, 12, foc and 3 or 2, foc and 1 or 0.7)
    if Lib.is_fav(it.g) then
      G.rect(fx + fw - 24, fy + 6, 18, 18, T.c.bg1, 9)
      Icons.draw("set_favorites", fx + fw - 22, fy + 8, T.parse_hex("#eab308"), 14 / 24)
    end
  end)
  -- nome do jogo escolhido + pilulas (embaixo dos outros jogos)
  local it = list[gsel]
  local gx = X0 + GBW + 18
  local gy = GROW_Y + GSH + 12
  local gf = G.fit(T.f.h2, it.g.name, T.W - gx - 20)
  G.text_fit(gf, it.g.name, gx, gy, T.W - gx - 20, T.c.text)
  local qy = gy + gf:getHeight() + 6
  local qx = gx
  local emu, core = Lib.choice(it.sys, it.g)
  if cur.special then qx = qx + pill(it.sys.fullname, qx, qy, color_for(it.sys.name or "?"), 180) + 8 end
  qx = qx + pill(emu and (emu .. (core and (" / " .. core) or "")) or L("comando do sistema"), qx, qy, T.c.line, 200) + 8
  if it.g.size and qx < T.W - 120 then pill(U.format_bytes(it.g.size), qx, qy, T.c.line, 100) end
  -- contador
  G.text(T.f.pix8, string.format("%d / %d", gsel, #list), T.W - 70, GROW_Y - 14, T.c.faint)
end

return SH
