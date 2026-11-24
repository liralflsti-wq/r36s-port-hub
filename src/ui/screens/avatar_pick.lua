-- =============================================================================
--  Meu perfil > Foto de perfil: escolher o avatar
--  Abas (L1/R1): "Meus" (avatares do hub, os que o usuario copiou para a pasta
--  avatares e os ja baixados) e os estilos online do DiceBear. As miniaturas
--  online vem pela internet; so o avatar aplicado e baixado e guardado no cartao.
--    direcional: escolher | L1/R1: trocar a aba | A: aplicar | X: tirar a foto
--    B: voltar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local Icons = require("ui.icons")
local P = require("core.profile")
local Covers = require("core.covers")
local lg = love.graphics

local S = {}
local COLS, SZ, GAP = 6, 84, 12
local GX = math.floor((640 - (COLS * SZ + (COLS - 1) * GAP)) / 2)
local GY = 108

function S:enter()
  self.tabs = { { id = "mine", name = L("Meus") } }
  for _, st in ipairs(P.ONLINE) do self.tabs[#self.tabs + 1] = { id = st.id, name = st.name, online = true } end
  self:load_tab(1)
  if #self.list == 0 then self:load_tab(2) end
  local cur = P.avatar()
  for i, it in ipairs(self.list) do if it.path == cur then self.sel = i end end
end

function S:load_tab(i)
  self.tab = i
  self.sel, self.top = 1, 0
  self.busy = nil
  local t = self.tabs[i]
  self.list = {}
  if t.online then
    for _, it in ipairs(P.online_list(t.id)) do self.list[#self.list + 1] = { online = it, path = it.file } end
  else
    for _, p in ipairs(P.avatars()) do self.list[#self.list + 1] = { path = p } end
  end
end

local function thumb(it)
  if it.online then
    if love.filesystem.getInfo(it.online.file) then return P.image(it.online.file) end
    return Covers.get(it.online)
  end
  return P.image(it.path)
end

function S:draw()
  G.header(L("Foto de perfil"), L("Meu perfil"))
  -- abas
  local x = 14
  for i, t in ipairs(self.tabs) do
    local name = I18N.tr(t.name)
    local w = T.f.small:getWidth(name) + 20
    local on = i == self.tab
    G.rect(x, 52, w, 24, on and T.c.accent or T.c.bg1, 12)
    G.text(T.f.small, name, x, 56, on and T.c.bg0 or T.c.dim, "center", w)
    x = x + w + 6
  end
  local t = self.tabs[self.tab]
  local note = t.online and L("Miniaturas pela internet. Só o avatar que você aplicar é baixado e guardado no cartão.")
    or L("Seus avatares: os baixados e as imagens (PNG/JPG) copiadas para a pasta avatares.")
  G.text_fit(T.f.small, I18N.tr(note), 16, 84, T.W - 32, T.c.faint)
  if #self.list == 0 then
    G.text(T.f.bodyb, I18N.tr(L("Nenhum avatar ainda. Escolha um nas outras abas (R1).")), 0, 220, T.c.text, "center", T.W)
    G.hints({ { "l1r1", L("Trocar aba") }, { "b", L("Voltar") } })
    return
  end
  local rows_vis = math.floor((T.H - 40 - GY) / (SZ + GAP))
  local row = math.floor((self.sel - 1) / COLS)
  if row < self.top then self.top = row end
  if row >= self.top + rows_vis then self.top = row - rows_vis + 1 end
  local cur = P.avatar()
  for i, it in ipairs(self.list) do
    local r = math.floor((i - 1) / COLS) - self.top
    if r >= 0 and r < rows_vis then
      local c = (i - 1) % COLS
      local ax, ay = GX + c * (SZ + GAP), GY + r * (SZ + GAP)
      G.rect(ax, ay, SZ, SZ, T.c.bg1, 8)
      local img = thumb(it)
      if img then
        local k = SZ / math.max(img:getWidth(), img:getHeight())
        G.clip(ax, ay, SZ, SZ)
        lg.setColor(1, 1, 1, 1)
        lg.draw(img, ax + (SZ - img:getWidth() * k) / 2, ay + (SZ - img:getHeight() * k) / 2, 0, k, k)
        G.unclip()
      elseif it.online and Covers.state[it.online.slug] == "failed" then
        Icons.draw("set_network", ax + SZ / 2 - 12, ay + SZ / 2 - 12, T.c.faint, 1)
      else
        G.text(T.f.pix8, "...", ax, ay + SZ / 2 - 4, T.c.faint, "center", SZ)
      end
      local on = i == self.sel
      G.frame(ax, ay, SZ, SZ, on and T.c.accent or T.c.line, 8, on and 3 or 1)
      if it.path == cur then G.tag(I18N.tr(L("EM USO")), ax + 4, ay + SZ - 18, T.c.green, T.c.bg0, T.f.pix8) end
    end
  end
  if self.busy then
    G.panel(170, 200, 300, 60, { r = 10 })
    G.text(T.f.bodyb, I18N.tr(L("Baixando avatar...")), 170, 222, T.c.text, "center", 300)
  end
  G.hints({ { "dpad", L("Escolher") }, { "l1r1", L("Trocar aba") }, { "a", L("Aplicar foto") }, { "x", L("Sem foto") }, { "b", L("Voltar") } })
end

local function done(ok)
  if ok then
    App.toast(I18N.tr(L("Foto de perfil atualizada!")), "ok")
    pcall(function() require("core.assistant").say(I18N.tr(L("Ficou ótima essa foto!")), "happy", 3) end)
  else
    App.toast(I18N.tr(L("Não consegui baixar o avatar. Confira o Wi-Fi e tente de novo.")), "error")
  end
end

function S:action(act)
  if self.busy then return end
  if act == "b" then App.pop(); return end
  if act == "l1" then self:load_tab((self.tab - 2) % #self.tabs + 1); return end
  if act == "r1" then self:load_tab(self.tab % #self.tabs + 1); return end
  if act == "x" then
    P.set_avatar(nil); App.toast(I18N.tr(L("Foto de perfil removida.")), "ok"); return
  end
  local n = #self.list
  if n == 0 then return end
  if act == "left" then self.sel = math.max(1, self.sel - 1)
  elseif act == "right" then self.sel = math.min(n, self.sel + 1)
  elseif act == "up" then if self.sel > COLS then self.sel = self.sel - COLS end
  elseif act == "down" then if self.sel + COLS <= n then self.sel = self.sel + COLS end
  elseif act == "a" then
    local it = self.list[self.sel]
    if it.online then
      self.busy = true
      P.apply_online(it.online, function(ok) self.busy = nil; done(ok) end)
    else
      P.set_avatar(it.path); done(true)
    end
  end
end

return S
