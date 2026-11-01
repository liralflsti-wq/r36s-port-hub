-- =============================================================================
--  Data e hora > Fuso horario: todas as zonas da base IANA instalada no
--  sistema, em ordem alfabetica e separadas por regiao (L1/R1). Y pesquisa.
--  A mostra a hora local da zona e pede confirmacao antes de aplicar.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local D = require("core.datetime")
local J = require("core.dtjob")
local Clock = require("core.clock")

local S = {}

local ROW_H, LIST_Y, VISIBLE = 30, 84, 11
local REGION_NAME = {
  Africa = L("África"), America = L("América"), Antarctica = L("Antártida"), Arctic = L("Ártico"), Asia = L("Ásia"),
  Atlantic = L("Atlântico"), Australia = L("Austrália"), Europe = L("Europa"), Indian = L("Índico"), Pacific = L("Pacífico"),
  Other = L("Outros"),
}

function S:enter(p)
  self.current = p.current
  self.all = D.zones()
  -- regioes que existem de fato na base instalada
  local seen, regs = {}, {}
  for _, z in ipairs(self.all) do
    local r = z:match("^([^/]+)/") or "Other"
    if not REGION_NAME[r] then r = "Other" end
    if not seen[r] then seen[r] = true; regs[#regs + 1] = r end
  end
  table.sort(regs, function(a, b) if a == "Other" then return false elseif b == "Other" then return true end return a < b end)
  self.regions = regs
  self.query = nil
  -- comeca na regiao do fuso atual
  self.ri = 1
  local cr = self.current and (self.current:match("^([^/]+)/") or "Other") or nil
  for i, r in ipairs(regs) do if r == cr then self.ri = i end end
  self:filter()
  for i, z in ipairs(self.items) do if z == self.current then self.sel = i end end
  self:clamp()
end

function S:filter()
  local items = {}
  if self.query then
    local q = self.query:lower():gsub(" ", "_")
    for _, z in ipairs(self.all) do if z:lower():find(q, 1, true) then items[#items + 1] = z end end
  else
    local r = self.regions[self.ri]
    for _, z in ipairs(self.all) do
      local zr = z:match("^([^/]+)/") or "Other"
      if not REGION_NAME[zr] then zr = "Other" end
      if zr == r then items[#items + 1] = z end
    end
  end
  self.items = items
  self.sel, self.scroll = 1, 0
  self.off_for, self.off = nil, nil
end

function S:clamp()
  local n = #self.items
  if self.sel > n then self.sel = math.max(1, n) end
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  self.scroll = math.max(0, math.min(self.scroll, math.max(0, n - VISIBLE)))
  self.t_off = 0
end

function S:update(dt)
  -- deslocamento da zona em foco (um comando, so depois de parar em cima dela)
  local z = self.items[self.sel]
  if z and self.off_for ~= z then
    self.t_off = (self.t_off or 0) + dt
    if self.t_off > 0.25 then self.off_for, self.off = z, D.zone_offset(z) end
  end
  local m = J.poll(self.job)
  if m then
    self.job = nil
    if m.ok then
      Clock.refresh()
      App.toast(L("Fuso horário alterado: ") .. self.pending .. "  •  " .. Clock.time(), "ok")
      App.pop()
    else
      local why = (m.why == "perm") and L("O sistema não deu permissão de administrador (sudo).")
        or ((m.why == "invalid") and L("Fuso horário não encontrado na base do sistema.") or tostring(m.why))
      App.show_dialog({ title = L("Fuso não alterado"), kind = "error", body = why })
    end
  end
end

function S:choose(z)
  local off = D.zone_offset(z)
  local now = os.time()
  local here = off and Clock.time(now, false, off) or "?"
  App.show_dialog({
    title = L("Mudar o fuso?"), kind = "info",
    body = z .. "  (" .. Clock.offset_label(off) .. ")\n\n" .. I18N.tr(L("A hora local passa a ser ")) .. here
      .. ".\n" .. I18N.tr(L("O relógio do sistema continua no mesmo instante; só a hora local muda.")),
    buttons = {
      { label = L("APLICAR"), fn = function()
        self.pending = z
        self.job = J.start("set_tz", { zone = z })
      end },
      { label = L("CANCELAR") },
    },
  })
end

function S:action(act)
  if self.job then return end
  local n = #self.items
  if act == "b" then
    if self.query then self.query = nil; self:filter(); return end
    App.pop(); return
  end
  if act == "up" and n > 0 then self.sel = (self.sel - 2) % n + 1; self:clamp()
  elseif act == "down" and n > 0 then self.sel = self.sel % n + 1; self:clamp()
  elseif act == "left" and n > 0 then self.sel = math.max(1, self.sel - VISIBLE); self:clamp()
  elseif act == "right" and n > 0 then self.sel = math.min(n, self.sel + VISIBLE); self:clamp()
  elseif (act == "l1" or act == "r1") and not self.query then
    self.ri = (self.ri - 1 + (act == "r1" and 1 or -1)) % #self.regions + 1
    self:filter()
  elseif act == "y" then
    App.push("textinput", { title = L("Pesquisar fuso horário"), label = L("Parte do nome (ex.: Sao_Paulo, Tokyo, London)"),
      value = self.query or "", max = 30,
      on_ok = function(v)
        v = (v or ""):gsub("^%s+", ""):gsub("%s+$", "")
        self.query = v ~= "" and v or nil
        self:filter()
      end })
  elseif act == "a" and n > 0 then
    self:choose(self.items[self.sel])
  end
end

function S:draw()
  G.header(L("Fuso horário"), self.current or "")
  -- abas de regiao (ou a pesquisa)
  local y = 50
  if self.query then
    G.text_fit(T.f.bodyb, I18N.tr(L("Pesquisa: ")) .. self.query .. string.format("  (%d)", #self.items), 16, y + 6, T.W - 32, T.c.accent2)
  else
    local x = 12
    local start = math.max(1, self.ri - 2)
    for i = start, #self.regions do
      local name = REGION_NAME[self.regions[i]]
      local tw = T.f.bodyb:getWidth(I18N.tr(name)) + 20
      if x + tw > T.W - 90 then break end
      local on = i == self.ri
      G.rect(x, y, tw, 26, on and T.c.accent or T.c.bg2, 6)
      G.text(T.f.bodyb, name, x, y + 5, on and T.c.bg0 or T.c.dim, "center", tw)
      x = x + tw + 6
    end
    G.button_icon("l1", T.W - 80, y + 5)
    G.button_icon("r1", T.W - 44, y + 5)
  end
  -- lista
  G.panel(12, LIST_Y, T.W - 24, VISIBLE * ROW_H + 8, { bg = T.c.bg1 })
  if #self.items == 0 then
    G.text(T.f.body, L("Nenhum fuso horário encontrado."), 12, LIST_Y + 150, T.c.faint, "center", T.W - 24)
  end
  for i = self.scroll + 1, math.min(#self.items, self.scroll + VISIBLE) do
    local z = self.items[i]
    local ry = LIST_Y + 4 + (i - self.scroll - 1) * ROW_H
    local on = i == self.sel
    if on then
      G.rect(16, ry, T.W - 32, ROW_H - 2, T.c.bg3, 5)
      G.frame(16, ry, T.W - 32, ROW_H - 2, T.c.accent, 5, 2)
    end
    local cur = z == self.current
    G.text(T.f.body, z:gsub("_", " "), 28, ry + 5, on and T.c.text or (cur and T.c.green or T.c.dim))
    local right
    if on and self.off_for == z and self.off then
      right = Clock.offset_label(self.off) .. "  •  " .. Clock.time(nil, false, self.off)
    elseif cur then right = I18N.tr(L("ATUAL")) end
    if right then G.text(T.f.small, right, T.W - 28 - T.f.small:getWidth(right), ry + 7, cur and T.c.green or T.c.accent2) end
  end
  if self.job then G.text(T.f.small, L("Aplicando..."), 12, LIST_Y + VISIBLE * ROW_H + 12, T.c.yellow, "center", T.W - 24) end
  G.hints({ { "dpad", L("Navegar") }, { "a", L("Escolher") }, { "y", L("Pesquisar") }, { "b", L("Voltar") }, { "l1", "" }, { "r1", L("Região") } })
end

return S
