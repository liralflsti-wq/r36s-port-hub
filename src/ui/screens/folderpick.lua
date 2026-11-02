-- =============================================================================
--  Navegador de pastas (escolher uma pasta): usado em Meus Ports > Desinstalar,
--  quando o .sh existe mas a pasta do jogo nao foi localizada.
--  A abre a pasta | Y escolhe a pasta destacada | B sobe (ou fecha na raiz)
--  So navega dentro da raiz recebida (o cartao); quem chama valida a escolha.
--  Somente leitura: esta tela nao apaga nada.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")

local S = {}

local LIST_Y = 76

local function parent(p) return (p:match("^(.*)/[^/]+$")) or p end

function S:enter(p)
  self.p = p or {}
  self.root = (self.p.root or "/roms"):gsub("/+$", "")
  self:open(self.p.start or self.root)
end

function S:open(dir)
  dir = dir:gsub("/+$", "")
  if dir ~= self.root and dir:sub(1, #self.root + 1) ~= self.root .. "/" then dir = self.root end
  self.dir = dir
  self.sel, self.top = 1, 0
  local list = {}
  local out = U.capture("find " .. U.shq(dir) .. " -mindepth 1 -maxdepth 1 \\( -type d -o -type l \\) 2>/dev/null") or ""
  for line in out:gmatch("[^\n]+") do
    local name = line:match("([^/]+)$")
    if name then
      local link = U.exec_ok("test -L " .. U.shq(line))
      if not link or U.is_dir(line) then
        list[#list + 1] = { name = name, path = line, link = link }
      end
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  self.list = list
end

function S:rh() return 30 + (T.f.bodyb:getHeight() - T.base_font(T.f.bodyb):getHeight()) end

function S:draw()
  G.header(self.p.title or L("Escolher pasta"))
  G.panel(12, 46, T.W - 24, 26, { bg = T.c.bg1 })
  G.text_fit(T.f.small, self.dir .. "/", 22, 51, T.W - 44, T.c.accent2)
  local rh = self:rh()
  local vis = math.max(4, math.floor((390 - LIST_Y) / rh))
  self.vis = vis
  if #self.list == 0 then
    G.text(T.f.body, L("Nenhuma pasta aqui."), 0, 200, T.c.dim, "center", T.W)
  end
  if self.sel > self.top + vis then self.top = self.sel - vis end
  if self.sel <= self.top then self.top = self.sel - 1 end
  for i = self.top + 1, math.min(#self.list, self.top + vis) do
    local it = self.list[i]
    local y = LIST_Y + 4 + (i - self.top - 1) * rh
    local on = i == self.sel
    G.rect(12, y, T.W - 24, rh - 3, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(12, y, T.W - 24, rh - 3, T.c.yellow, 5, 2) end
    -- icone de pasta
    local fy = y + (rh - 3) / 2 - 7
    G.color(on and T.c.yellow or T.c.dim)
    love.graphics.rectangle("fill", 24, fy + 3, 20, 12, 2, 2)
    love.graphics.rectangle("fill", 24, fy, 9, 4, 1, 1)
    local tw = 0
    if it.link then
      tw = T.f.pix8:getWidth(I18N.tr(L("LINK"))) + 12
      G.tag(L("LINK"), T.W - 22 - tw, y + (rh - 3) / 2 - 8, T.c.orange, T.c.bg0, T.f.pix8)
    end
    G.text_fit(T.f.bodyb, it.name .. "/", 54, y + (rh - 3 - T.f.bodyb:getHeight()) / 2, T.W - 80 - tw, on and T.c.text or T.c.dim)
  end
  -- pasta destacada e para que ela sera usada
  local it = self.list[self.sel]
  T.with_base_fonts(function()
    G.panel(12, 394, T.W - 24, 38, { bg = T.c.bg1 })
    G.text_fit(T.f.small, it and (L("Destacada: ") .. it.path) or "", 22, 398, T.W - 44, T.c.text)
    if self.p.info then
      G.text_fit(T.f.small, L("Para o jogo: ") .. self.p.info, 22, 414, T.W - 44, T.c.faint)
    end
  end)
  local hints = { { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "y", L("Escolher esta pasta") },
    { "b", self.dir == self.root and L("Cancelar") or L("Pasta acima") } }
  G.hints(hints)
end

function S:action(act)
  local n = #self.list
  if act == "up" and n > 0 then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" and n > 0 then self.sel = self.sel % n + 1
  elseif act == "left" and n > 0 then self.sel = math.max(1, self.sel - (self.vis or 8))
  elseif act == "right" and n > 0 then self.sel = math.min(n, self.sel + (self.vis or 8))
  elseif act == "a" and n > 0 then
    local it = self.list[self.sel]
    if it.link then App.toast(L("Links simbólicos não são abertos por segurança."), "warn") else self:open(it.path) end
  elseif act == "y" and n > 0 then
    local it = self.list[self.sel]
    if self.p.on_pick then self.p.on_pick(it.path) end
  elseif act == "b" then
    if self.dir == self.root then
      App.pop()
      if self.p.on_cancel then self.p.on_cancel() end
    else
      local prev = self.dir
      self:open(parent(self.dir))
      for i, it in ipairs(self.list) do if it.path == prev then self.sel = i end end
    end
  end
end

return S
