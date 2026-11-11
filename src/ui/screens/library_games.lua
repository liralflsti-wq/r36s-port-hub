-- Jogos de um sistema (ou favoritos / recentes): lista, capa do gamelist.xml,
-- emulador/core em uso. A joga, X troca o emulador do jogo, SELECT favorita.
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Lib = require("core.library")
local Icons = require("ui.icons")
local lg = love.graphics
local CV = require("ui.coverview")

local S = {}

local LIST_X, LIST_Y, LIST_W = 12, 50, 330
local ROW_H = 32
local VIS = 12
local PX, PY, PW, PH = 352, 50, 276, 396

function S:enter(p)
  self.p = p or {}
  self.sel, self.top = 1, 0
  self.img, self.img_for, self.img_wait = nil, nil, 0
  self:rebuild()
  if self.p.from_return then
    App.toast(L("Bem-vindo de volta!"), "info")
  end
end

function S:rebuild()
  local list = {}
  local p = self.p
  if p.system then
    for _, g in ipairs(p.system.games) do list[#list + 1] = { sys = p.system, g = g } end
    self.title = p.system.fullname
  elseif p.special == "favs" then
    for _, s in ipairs(Lib.systems) do
      for _, g in ipairs(s.games) do if Lib.is_fav(g) then list[#list + 1] = { sys = s, g = g } end end
    end
    table.sort(list, function(a, b) return a.g.name:lower() < b.g.name:lower() end)
    self.title = L("Favoritos")
  elseif p.special == "recent" then
    for _, r in ipairs(Lib.recent()) do
      local s, g = Lib.find_game(r.file)
      if s then list[#list + 1] = { sys = s, g = g } end
    end
    self.title = L("Recentes")
  end
  self.list = list
  self.sel = U.clamp(self.sel, 1, math.max(1, #list))
end

function S:resume() self:rebuild() end

function S:leave()
  if self.img and self.img.release then self.img:release() end
  self.img = nil
end

-- capa: carrega a imagem do gamelist.xml (fora da pasta do app) so do item
-- escolhido, depois de um instante parado (rolar a lista fica leve)
function S:update(dt)
  if CV.active() then CV.update(self, self.sel, dt) end
  local it = self.list[self.sel]
  local want = it and it.g.image or nil
  if want ~= self.img_for then
    self.img_wait = (self.img_wait or 0) + dt
    if self.img_wait < 0.18 then return end
    self.img_wait = 0
    if self.img and self.img.release then self.img:release() end
    self.img, self.img_for = nil, want
    if want then
      local ok, img = pcall(function()
        local f = io.open(want, "rb")
        if not f then error("sem arquivo") end
        local size = f:seek("end")
        if size > 3 * 1024 * 1024 then f:close(); error("grande demais") end
        f:seek("set", 0)
        local data = f:read("*a")
        f:close()
        return lg.newImage(love.image.newImageData(love.filesystem.newFileData(data, "capa")))
      end)
      if ok then img:setFilter("linear", "linear"); self.img = img end
    end
  else
    self.img_wait = 0
  end
end

function S:draw()
  G.header(L("Biblioteca de jogos"), self.title)
  local n = #self.list
  if n == 0 then
    G.text(T.f.body, self.p.special == "favs" and L("Nenhum favorito ainda. Aperte SELECT num jogo para marcar.")
      or (self.p.special == "recent" and L("Nenhum jogo aberto pelo hub ainda.") or L("Nenhum jogo neste sistema.")),
      40, 210, T.c.dim, "center", T.W - 80)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  if CV.active() then self:draw_showcase(); return end
  if self.sel > self.top + VIS then self.top = self.sel - VIS end
  if self.sel <= self.top then self.top = self.sel - 1 end
  -- lista
  for i = self.top + 1, math.min(n, self.top + VIS) do
    local it = self.list[i]
    local y = LIST_Y + (i - self.top - 1) * ROW_H
    local on = i == self.sel
    if on then
      G.rect(LIST_X, y, LIST_W, ROW_H - 3, T.c.bg2, 6)
      G.frame(LIST_X, y, LIST_W, ROW_H - 3, T.c.accent, 6, 2)
    end
    local x = LIST_X + 10
    if Lib.is_fav(it.g) then Icons.draw("set_favorites", x - 2, y + 5, T.c.yellow, 0.7); x = x + 20 end
    local sub = self.p.system and "" or ("  " .. it.sys.fullname)
    G.text_fit(T.f.body, it.g.name, x, y + 6, LIST_W - (x - LIST_X) - 10 - (sub ~= "" and 90 or 0), on and T.c.text or T.c.dim)
    if sub ~= "" then G.text_fit(T.f.small, it.sys.fullname, LIST_X + LIST_W - 96, y + 8, 88, T.c.faint) end
  end
  if n > VIS then
    local track = VIS * ROW_H - 6
    local h = math.max(16, track * VIS / n)
    G.rect(LIST_X + LIST_W + 2, LIST_Y + (track - h) * (self.top / math.max(1, n - VIS)), 3, h, T.c.accent2, 1, 0.7)
  end
  -- painel do jogo escolhido
  local it = self.list[self.sel]
  local g, sys = it.g, it.sys
  G.panel(PX, PY, PW, PH, { bg = T.c.bg1 })
  local cw, ch = PW - 24, 170
  local cx, cy = PX + 12, PY + 12
  if self.img then
    local iw, ih = self.img:getDimensions()
    local s = math.min(cw / iw, ch / ih)
    lg.setColor(1, 1, 1, 1)
    lg.draw(self.img, cx + (cw - iw * s) / 2, cy + (ch - ih * s) / 2, 0, s, s)
  else
    G.rect(cx, cy, cw, ch, T.c.bg2, 6)
    Icons.draw("testes_de_controles", cx + cw / 2 - 24, cy + ch / 2 - 30, T.c.faint, 2)
    G.text(T.f.small, g.image and L("Carregando capa...") or L("Sem capa no gamelist.xml"), cx, cy + ch - 24, T.c.faint, "center", cw)
  end
  local ty = cy + ch + 10
  local lines = G.wrap(T.f.bodyb, g.name, PW - 24)
  for i = 1, math.min(2, #lines) do G.text(T.f.bodyb, lines[i], PX + 12, ty, T.c.text); ty = ty + 18 end
  ty = ty + 4
  local emu, core = Lib.choice(sys, g)
  local info = {
    { L("Sistema"), sys.fullname },
    { L("Emulador"), emu and (emu .. (core and (" / " .. core) or "")) .. (Lib.has_game_choice(g) and L(" (deste jogo)") or "") or L("comando do sistema") },
  }
  if g.developer and g.developer ~= "" then info[#info + 1] = { L("Desenvolvedor"), g.developer } end
  if g.genre and g.genre ~= "" then info[#info + 1] = { L("Gênero"), g.genre } end
  if g.size then info[#info + 1] = { L("Tamanho"), U.format_bytes(g.size) } end
  for _, kv in ipairs(info) do
    if ty > PY + PH - 34 then break end
    G.text(T.f.small, kv[1], PX + 12, ty, T.c.faint)
    G.text_fit(T.f.small, kv[2], PX + 110, ty, PW - 122, T.c.dim)
    ty = ty + 17
  end
  G.text_fit(T.f.small, g.rel or g.file, PX + 12, PY + PH - 22, PW - 24, T.c.faint)
  local hs = { { "a", L("Jogar") } }
  if #sys.emulators > 0 then hs[#hs + 1] = { "x", L("Emulador") } end
  hs[#hs + 1] = { "select", Lib.is_fav(g) and L("Desfavoritar") or L("Favoritar") }
  hs[#hs + 1] = { "y", L("Info") }
  hs[#hs + 1] = { "b", L("Voltar") }
  G.hints(hs)
end

-- Pastel Pop: vitrine de capas (ui/coverview.lua). So a capa do jogo escolhido
-- e carregada (as outras aparecem como cartoes com o nome do sistema).
local function fit_image(img, x, y, w, h, cover)
  local iw, ih = img:getDimensions()
  local s = cover and math.max(w / iw, h / ih) or math.min(w / iw, h / ih)
  G.clip(x, y, w, h)
  lg.setColor(1, 1, 1, 1)
  lg.draw(img, x + (w - iw * s) / 2, y + (h - ih * s) / 2, 0, s, s)
  G.unclip()
end

function S:draw_showcase()
  local list = self.list
  local it = list[self.sel]
  local g, sys = it.g, it.sys
  local function cover(i, x, y, w, h, on)
    G.rect(x, y, w, h, T.c.bg1, 10)
    if on and self.img then
      fit_image(self.img, x + 3, y + 3, w - 6, h - 6, false)
      return
    end
    G.rect(x + 4, y + 4, w - 8, h - 8, T.c.accent, 8, 0.08)
    local isz = math.min(w, h) * 0.42
    Icons.draw("games", x + (w - isz) / 2, y + h * 0.28, T.c.accent, isz / 24)
    G.text_fit(T.f.pix8, U.upper(list[i].sys.name or ""), x + 6, y + h - 18, w - 12, T.c.faint)
  end
  local emu, core = Lib.choice(sys, g)
  local rows = {
    { L("Sistema"), sys.fullname },
    { L("Emulador"), emu and (emu .. (core and (" / " .. core) or "")) or L("comando do sistema") },
  }
  if g.developer and g.developer ~= "" then rows[#rows + 1] = { L("Desenvolvedor"), g.developer } end
  if g.genre and g.genre ~= "" then rows[#rows + 1] = { L("Gênero"), g.genre } end
  if g.releasedate and g.releasedate:match("^%d%d%d%d") then rows[#rows + 1] = { L("Lançamento"), g.releasedate:sub(1, 4) } end
  if g.players and g.players ~= "" then rows[#rows + 1] = { L("Jogadores"), g.players } end
  if g.size then rows[#rows + 1] = { L("Tamanho"), U.format_bytes(g.size) } end
  local sections = { { title = L("Detalhes"), rows = rows } }
  sections[#sections + 1] = { title = L("Descrição"), text = (g.desc and g.desc ~= "") and g.desc or L("Sem descrição no gamelist.xml.") }
  local tags = {}
  if Lib.is_fav(g) then tags[#tags + 1] = { L("FAVORITO"), T.c.yellow } end
  if Lib.has_game_choice(g) then tags[#tags + 1] = { L("EMULADOR PRÓPRIO"), T.c.accent2 } end
  CV.draw(self, {
    top = 48, n = #list, sel = self.sel, draw_cover = cover,
    bg_cover = self.img and function(x, y, w, h) fit_image(self.img, x, y, w, h, true) end or nil,
    name = g.name, pills = { { sys.fullname, T.c.accent2 }, { g.rel or g.file, T.c.line } }, tags = tags, sections = sections,
  })
  local hs = { { "a", L("Jogar") } }
  if #sys.emulators > 0 then hs[#hs + 1] = { "x", L("Emulador") } end
  hs[#hs + 1] = { "select", Lib.is_fav(g) and L("Desfavoritar") or L("Favoritar") }
  hs[#hs + 1] = { "y", L("Info") }
  hs[#hs + 1] = { "b", L("Voltar") }
  G.hints(hs)
end

function S:action(act)
  local n = #self.list
  if act == "b" then App.pop(); return end
  if n == 0 then return end
  local it = self.list[self.sel]
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "l1" or act == "left" then self.sel = math.max(1, self.sel - VIS)
  elseif act == "r1" or act == "right" then self.sel = math.min(n, self.sel + VIS)
  elseif act == "select" then
    local on = Lib.toggle_fav(it.g)
    App.toast(on and (it.g.name .. L(" adicionado aos favoritos")) or (it.g.name .. L(" removido dos favoritos")), "info")
    if self.p.special == "favs" then self:rebuild() end
  elseif act == "x" then
    if #it.sys.emulators > 0 then App.screens.library.choose_emulator(it.sys, it.g) end
  elseif act == "y" then
    local emu, core = Lib.choice(it.sys, it.g)
    local body = {}
    if it.g.desc and it.g.desc ~= "" then body[#body + 1] = it.g.desc; body[#body + 1] = "" end
    body[#body + 1] = L("Arquivo: ") .. it.g.file
    if it.g.size then body[#body + 1] = L("Tamanho: ") .. U.format_bytes(it.g.size) end
    if it.g.releasedate and it.g.releasedate:match("^%d%d%d%d") then body[#body + 1] = L("Lançamento: ") .. it.g.releasedate:sub(1, 4) end
    if it.g.players and it.g.players ~= "" then body[#body + 1] = L("Jogadores: ") .. it.g.players end
    body[#body + 1] = L("Emulador: ") .. tostring(emu or "-") .. (core and (" / " .. core) or "")
    App.show_dialog({ title = it.g.name, kind = "info", body = table.concat(body, "\n") })
  elseif act == "a" then
    App.launch_game(it.sys, it.g)
  end
end

return S
