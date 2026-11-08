-- Leitor de texto (somente leitura): registros de erro, relatorios, etc.
-- params: { title, sub, path (arquivo) | text | files = { {name, path}... }, idx, empty }
-- Cima/baixo rola, L1/R1 passa a pagina, B volta. Com varios arquivos (files),
-- esquerda/direita troca de arquivo.
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")

local S = {}

local X0, Y0, W, H = 14, 50, 612, 392
local MAX_BYTES = 256 * 1024

function S:enter(p)
  self.p = p or {}
  self.idx = self.p.idx or 1
  self:open()
end

function S:open()
  self.top = 0
  local text = self.p.text
  local path = self.p.path
  if self.p.files then
    local cur = self.p.files[self.idx]
    path = cur and cur.path
    self.fname = cur and cur.name
  end
  if not text and path then
    local f = io.open(path, "rb")
    if f then
      text = f:read(MAX_BYTES) or ""
      if f:read(1) then text = text .. "\n\n" .. L("[arquivo muito grande: mostrando só o começo]") end
      f:close()
    end
  end
  self.raw = text
  self:layout()
end

function S:layout()
  if not self.raw then self.lines = {}; self.vis = 1; return end
  local f = T.f.small
  self.font = f
  self.lh = math.floor(f:getHeight() * 1.15)
  self.lines = {}
  local text = (self.raw or ""):gsub("\r", ""):gsub("\t", "    ")
  for para in (text .. "\n"):gmatch("(.-)\n") do
    if para == "" then
      self.lines[#self.lines + 1] = ""
    else
      for _, l in ipairs(G.wrap(f, para, W - 30)) do self.lines[#self.lines + 1] = l end
    end
  end
  self.vis = math.floor((H - 16) / self.lh)
  self.top = U.clamp(self.top or 0, 0, math.max(0, #self.lines - self.vis))
end

function S:on_font() self:layout() end

function S:draw()
  local sub = self.p.sub
  if self.p.files then sub = self.idx .. "/" .. #self.p.files .. "  •  " .. tostring(self.fname or "") end
  G.header(self.p.title or L("Leitor"), sub)
  if not self.raw then
    G.text(T.f.body, self.p.empty or L("Não foi possível abrir o arquivo."), 40, 210, T.c.dim, "center", T.W - 80)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  G.panel(X0, Y0, W, H, { bg = T.c.bg1 })
  G.clip(X0 + 2, Y0 + 2, W - 4, H - 4)
  local y = Y0 + 8
  for i = self.top + 1, math.min(#self.lines, self.top + self.vis) do
    G.text(self.font, self.lines[i], X0 + 12, y, T.c.text)
    y = y + self.lh
  end
  G.unclip()
  local n = #self.lines
  if n > self.vis then
    local track = H - 12
    local h = math.max(16, track * self.vis / n)
    G.rect(X0 + W - 6, Y0 + 6 + (track - h) * (self.top / (n - self.vis)), 3, h, T.c.accent, 1, 0.8)
  end
  local hs = { { "dpad", L("Rolar") }, { "l1", L("Página") } }
  if self.p.files and #self.p.files > 1 then hs[#hs + 1] = { "dpad", L("Esquerda/direita: outro arquivo") } end
  hs[#hs + 1] = { "b", L("Voltar") }
  G.hints(hs)
end

function S:action(act)
  local maxtop = math.max(0, #self.lines - (self.vis or 1))
  if act == "b" or act == "a" then App.pop()
  elseif act == "up" then self.top = math.max(0, self.top - 1)
  elseif act == "down" then self.top = math.min(maxtop, self.top + 1)
  elseif (act == "left" or act == "right") and self.p.files and #self.p.files > 1 then
    local n = #self.p.files
    self.idx = (self.idx - 1 + (act == "right" and 1 or -1)) % n + 1
    self:open()
  elseif act == "l1" or act == "left" then self.top = math.max(0, self.top - self.vis + 1)
  elseif act == "r1" or act == "right" then self.top = math.min(maxtop, self.top + self.vis - 1)
  end
end

return S
