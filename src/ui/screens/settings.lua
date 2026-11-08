-- Configuracoes: central com as categorias em cartoes (3 colunas, 3 linhas
-- visiveis; as demais linhas aparecem rolando com o direcional).
-- Cada cartao abre a tela da categoria (ui/screens/settings_cat.lua).
-- Aqui so aparecem estados ja conhecidos em memoria (nada pesado ao abrir).
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local Icons = require("ui.icons")
local Defs = require("ui.settings_defs")
local U = require("lib.util")
local lg = love.graphics

local S = {}

local COLS, ROWS = 3, 3
local X0, Y0, CW, CH, GAP = 12, 48, 200, 124, 8

function S:enter(p)
  self.sel = self.sel or 1
  self.top = self.top or 0          -- primeira linha visivel
  if p and p.cat then
    for i, c in ipairs(Defs.LIST) do if c.id == p.cat then self.sel = i end end
  end
  self:follow()
end

--- mantem a linha do cartao escolhido dentro das 3 visiveis
function S:follow()
  local row = math.floor((self.sel - 1) / COLS)
  if row < self.top then self.top = row end
  if row > self.top + ROWS - 1 then self.top = row - ROWS + 1 end
end

local function total_rows() return math.ceil(#Defs.LIST / COLS) end

local function color(name) return T.c[name] or T.c.accent end

function S:draw()
  G.header(L("Configurações"))
  local first, last = self.top * COLS + 1, math.min(#Defs.LIST, (self.top + ROWS) * COLS)
  for i = first, last do
    local cat = Defs.LIST[i]
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS) - self.top
    local x, y = X0 + col * (CW + GAP), Y0 + row * (CH + GAP)
    local on = i == self.sel
    local c = color(cat.color)
    G.panel(x, y, CW, CH, { bg = on and T.c.bg3 or T.c.bg1, border = on and c or T.c.line, lw = on and 2 or 1 })
    if on then G.rect(x, y + 10, 4, CH - 20, c, 2) end

    -- icone num quadro com a cor da categoria
    G.rect(x + 12, y + 12, 36, 36, c, 8, on and 0.22 or 0.12)
    Icons.draw(cat.icon, x + 18, y + 18, on and c or T.c.dim, 1)

    -- nome (ate 2 linhas)
    local nl = G.wrap(T.f.bodyb, cat.name, CW - 64)
    local nstep = G.step(T.f.bodyb, 17)
    local ny = #nl > 1 and y + 12 or y + 21
    if #nl > 1 then ny = ny - (nstep - 17) end   -- texto maior: sobe um pouco
    for k = 1, math.min(2, #nl) do
      local s = nl[k]
      if k == 2 and #nl > 2 then s = U.ellipsize(T.f.bodyb, s .. " …", CW - 64) end
      G.text(T.f.bodyb, s, x + 56, ny + (k - 1) * nstep, on and T.c.text or T.c.dim)
    end

    -- descricao curta: com texto maior, diminui ate caber ou e encurtada com "…"
    local dtop = math.max(y + 56, ny + math.min(2, #nl) * nstep + 4)
    local df, dl = G.fit_lines(T.f.small, cat.desc, CW - 24, y + CH - 32 - dtop, true)
    local dstep = G.step(df, 15)
    for k = 1, #dl do
      G.text(df, dl[k], x + 12, dtop + (k - 1) * dstep, T.c.faint)
    end

    -- estado atual + indicador de acesso
    G.rect(x + 12, y + CH - 30, CW - 24, 1, T.c.line, 0, 0.8)
    local ok, st = pcall(cat.status)
    G.text_fit(T.f.small, ok and st or "", x + 12, y + CH - 22, CW - 40, on and c or T.c.dim)
    G.color(on and c or T.c.faint)
    lg.setLineWidth(2)
    local ax, ay = x + CW - 20, y + CH - 21
    lg.line(ax, ay, ax + 5, ay + 5, ax, ay + 10)
    lg.setLineWidth(1)
  end
  -- indicador de rolagem (mais categorias acima/abaixo)
  local tr = total_rows()
  if tr > ROWS then
    G.color(T.c.accent2)
    local cx = T.W - 9
    if self.top > 0 then lg.polygon("fill", cx, Y0 + 2, cx - 5, Y0 + 10, cx + 5, Y0 + 10) end
    local yb = Y0 + ROWS * (CH + GAP) - GAP
    if self.top + ROWS < tr then lg.polygon("fill", cx, yb - 2, cx - 5, yb - 10, cx + 5, yb - 10) end
  end
  G.hints({ { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "b", L("Voltar") } })
  local cnt = string.format("%d/%d", self.sel, #Defs.LIST)
  G.text(T.f.small, cnt, T.W - 14 - T.f.small:getWidth(cnt), T.H - 25, T.c.faint)
end

function S:action(act)
  local n = #Defs.LIST
  local tr = total_rows()
  local col, row = (self.sel - 1) % COLS, math.floor((self.sel - 1) / COLS)
  if act == "left" then col = (col - 1) % COLS
  elseif act == "right" then col = (col + 1) % COLS
  elseif act == "up" then row = (row - 1) % tr
  elseif act == "down" then row = (row + 1) % tr
  elseif act == "l1" then row = math.max(0, row - ROWS)
  elseif act == "r1" then row = math.min(tr - 1, row + ROWS)
  elseif act == "b" then App.pop(); return
  elseif act == "a" then App.push("settings_cat", { id = Defs.LIST[self.sel].id }); return
  else return end
  local i = row * COLS + col + 1
  if i > n then i = n end   -- ultima linha incompleta: vai para o ultimo cartao
  self.sel = i
  self:follow()
end

return S
