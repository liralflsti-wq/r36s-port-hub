-- =============================================================================
--  Novidades de uma versao: descricao, o que mudou e o que foi corrigido
--  (vem do update_manifest.json). Aparece sozinha na primeira abertura depois
--  de uma atualizacao e tambem pela analise do pacote e pelo historico.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local C = require("config")

local S = {}
local TOP, BOTTOM = 92, 436

function S:enter(p)
  self.p = p or {}
  self.scroll = 0
  self:layout()
end

function S:layout()
  local p = self.p
  local w = T.W - 60
  local lines = {}
  local function add(font, text, color, indent)
    for _, l in ipairs(G.wrap(font, text, w - (indent or 0))) do
      lines[#lines + 1] = { font = font, text = l, color = color, x = indent or 0 }
    end
  end
  local function gap(n) lines[#lines + 1] = { gap = n or 8 } end
  if p.description and tostring(p.description):find("%S") then
    add(T.f.body, tostring(p.description), T.c.text)
    gap(12)
  end
  local function section(title, list, color)
    if type(list) ~= "table" or #list == 0 then return end
    lines[#lines + 1] = { font = T.f.pix8, text = title, color = color, x = 0 }
    gap(6)
    for _, item in ipairs(list) do
      local wrapped = G.wrap(T.f.body, tostring(item), w - 22)
      for i, l in ipairs(wrapped) do
        lines[#lines + 1] = { font = T.f.body, text = l, color = T.c.text, x = 22, bullet = i == 1 and color or nil }
      end
      gap(4)
    end
    gap(10)
  end
  section(L("O QUE MUDOU"), p.changes, T.c.accent2)
  section(L("CORREÇÕES"), p.fixes, T.c.green)
  if #lines == 0 then add(T.f.body, L("Esta atualização não trouxe a lista do que mudou."), T.c.dim) end
  self.lines = lines
  local hgt = 0
  for _, l in ipairs(lines) do hgt = hgt + (l.gap or l.font:getHeight() + 2) end
  self.total = hgt
end

S.on_language = S.layout

function S:max_scroll() return math.max(0, self.total - (BOTTOM - TOP)) end

function S:draw()
  local p = self.p
  G.header(L("Novidades"), L("Versão atual: ") .. C.VERSION)
  local title = (p.first and L("Atualizado para a versão ") or L("Versão ")) .. tostring(p.to_label or p.to or "?")
  G.text(T.f.h3, title, 30, 54, p.first and T.c.green or T.c.accent2)
  G.rect(30, 84, T.W - 60, 1, T.c.line)
  love.graphics.setScissor(0, TOP, T.W, BOTTOM - TOP)
  local y = TOP + 6 - self.scroll
  for _, l in ipairs(self.lines) do
    if l.gap then y = y + l.gap
    else
      local h = l.font:getHeight() + 2
      if y + h > TOP and y < BOTTOM then
        if l.bullet then G.rect(36, y + math.floor(h / 2) - 3, 6, 6, l.bullet, 3) end
        G.text(l.font, l.text, 30 + l.x, y, l.color)
      end
      y = y + h
    end
  end
  love.graphics.setScissor()
  local hints = {}
  if self:max_scroll() > 0 then hints[#hints + 1] = { "dpad", L("Rolar") } end
  hints[#hints + 1] = { "b", p.first and L("Continuar") or L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  if act == "up" then self.scroll = math.max(0, self.scroll - 40)
  elseif act == "down" then self.scroll = math.min(self:max_scroll(), self.scroll + 40)
  elseif act == "b" or act == "a" then App.pop() end
end

return S
