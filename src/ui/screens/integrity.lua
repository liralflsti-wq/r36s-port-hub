-- =============================================================================
--  Manutencao > Verificador de integridade dos ports (somente leitura)
--  Reconhece ports instalados pelo hub, pelo PortMaster ou copiados a mao
--  (mesma varredura usada por Meus Ports). A verifica | Y verifica de novo
--  cima/baixo escolhem o port | esquerda/direita rolam os detalhes
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Scan = require("core.scan")
local Manifest = require("core.manifest")
local Runtimes = require("core.runtimes")
local lg = love.graphics

local S = {}
local ST_COLOR = { ["ÍNTEGRO"] = T.c.green, ["ATENÇÃO"] = T.c.yellow, ["ERRO"] = T.c.red }
local CK_COLOR = { ok = T.c.green, warn = T.c.yellow, err = T.c.red, unk = T.c.dim }
local LIST_X, LIST_Y, LIST_W, ROW_H, VISIBLE = 12, 84, 262, 44, 8

function S:enter()
  self.state = "idle"
  self.results = {}
  self.sel, self.scroll, self.dscroll = 1, 0, 0
end

function S:leave()
  if self.state == "running" and self.ctl then self.ctl:push("cancel") end
end

function S:start()
  Scan.refresh(true)
  local hub = {}
  for _, rec in pairs(Manifest.data or {}) do
    if type(rec) == "table" and type(rec.entries) == "table" then
      for _, e in ipairs(rec.entries) do if tostring(e):lower():match("%.sh$") then hub[e] = rec.entries end end
    end
  end
  local list = {}
  for _, p in ipairs(Scan.ports) do
    list[#list + 1] = { script = p.script, title = p.title, source = hub[p.script] and L("R36S PORT HUB") or p.source,
      dir = p.dir, dir_source = p.dir_source, gamedir = p.gamedir, pm_items = p.pm_items, hub_entries = hub[p.script] }
  end
  self.results = {}
  self.total = #list
  self.sel, self.scroll, self.dscroll = 1, 0, 0
  if #list == 0 then self.state = "done"; return end
  self.out = love.thread.getChannel("hub_integ_out")
  self.ctl = love.thread.getChannel("hub_integ_ctl")
  self.out:clear(); self.ctl:clear()
  self.thread = love.thread.newThread("threads/integrity_thread.lua")
  self.thread:start({ lang = require("lib.i18n").lang, out = "hub_integ_out", ctl = "hub_integ_ctl", ports_dir = C.PORTS_DIR, pm_dir = Runtimes.detect_pm(), ports = list })
  self.state = "running"
end

function S:update()
  if self.state ~= "running" then return end
  local e = self.thread:getError()
  if e then U.log("integridade:", e); self.state = "done"; App.toast(L("A verificação parou por um erro interno."), "error"); return end
  local m = self.out:pop()
  while m do
    if m.t == "port" then self.results[#self.results + 1] = m.result
    elseif m.t == "done" then
      self.state = "done"
      local c = self:counts()
      App.toast(string.format(L("Verificação concluída: %d íntegro(s), %d atenção, %d erro(s)."), c["ÍNTEGRO"], c["ATENÇÃO"], c["ERRO"]),
        c["ERRO"] > 0 and "error" or (c["ATENÇÃO"] > 0 and "warn" or "ok"))
    elseif m.t == "cancelled" then self.state = "done" end
    m = self.out:pop()
  end
end

function S:counts()
  local c = { ["ÍNTEGRO"] = 0, ["ATENÇÃO"] = 0, ["ERRO"] = 0 }
  for _, r in ipairs(self.results) do c[r.state] = c[r.state] + 1 end
  return c
end

local function mark(x, y, state)
  local c = CK_COLOR[state]
  G.color(c)
  if state == "ok" then
    lg.setLineWidth(2); lg.line(x, y + 6, x + 4, y + 10, x + 11, y + 2); lg.setLineWidth(1)
  elseif state == "err" then
    lg.setLineWidth(2); lg.line(x + 1, y + 2, x + 10, y + 11); lg.line(x + 10, y + 2, x + 1, y + 11); lg.setLineWidth(1)
  elseif state == "warn" then
    lg.polygon("fill", x + 6, y + 1, x + 12, y + 12, x, y + 12)
  else
    lg.circle("line", x + 6, y + 7, 5)
  end
end

function S:draw()
  local right = ""
  if self.state ~= "idle" then
    local c = self:counts()
    right = string.format(L("%d íntegro  •  %d atenção  •  %d erro"), c["ÍNTEGRO"], c["ATENÇÃO"], c["ERRO"])
  end
  G.header(L("Integridade dos ports"), right)
  if self.state == "idle" then
    G.panel(12, 52, T.W - 24, 384, { bg = T.c.bg1 })
    G.text(T.f.pix16, L("VERIFICAR OS PORTS"), 12, 160, T.c.accent2, "center", T.W - 24)
    G.text(T.f.body, L("Confere o script, a pasta de dados, os itens do PortMaster, os runtimes e\nos arquivos instalados pelo hub de cada port do console.\nSomente leitura: nada é corrigido, movido ou apagado."),
      40, 196, T.c.dim, "center", T.W - 80)
    G.hints({ { "a", L("Verificar agora") }, { "b", L("Voltar") } })
    return
  end

  -- barra de progresso
  local frac = (self.total or 0) > 0 and #self.results / self.total or 1
  G.text(T.f.small, self.state == "running" and string.format(L("Verificando %d de %d..."), #self.results, self.total)
    or string.format(L("%d port(s) verificados  •  pasta %s"), #self.results, C.PORTS_DIR), 14, 50, T.c.dim)
  G.progress(14, 68, T.W - 28, 8, frac, self.state == "running" and T.c.yellow or T.c.green)

  if #self.results == 0 then
    G.panel(12, LIST_Y, T.W - 24, 352, { bg = T.c.bg1 })
    G.text(T.f.body, self.state == "running" and L("Aguarde...") or L("Nenhum port (.sh) encontrado em ") .. C.PORTS_DIR .. ".",
      12, LIST_Y + 160, T.c.faint, "center", T.W - 24)
    G.hints({ { "b", L("Voltar") } })
    return
  end

  -- lista
  self.sel = U.clamp(self.sel, 1, #self.results)
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  G.panel(LIST_X, LIST_Y, LIST_W, VISIBLE * ROW_H + 8, { bg = T.c.bg1 })
  for i = self.scroll + 1, math.min(#self.results, self.scroll + VISIBLE) do
    local r = self.results[i]
    local y = LIST_Y + 4 + (i - self.scroll - 1) * ROW_H
    local on = i == self.sel
    local c = ST_COLOR[r.state]
    if on then G.rect(LIST_X + 4, y, LIST_W - 8, ROW_H - 4, T.c.bg3, 5); G.frame(LIST_X + 4, y, LIST_W - 8, ROW_H - 4, T.c.accent, 5, 2) end
    G.rect(LIST_X + 8, y + 6, 4, ROW_H - 16, c, 2)
    local ft, fs, ty, sy = G.row_fonts(ROW_H - 4, 3, 21)
    G.text_fit(ft, r.title, LIST_X + 18, y + ty, LIST_W - 30, on and T.c.text or T.c.dim)
    G.text(T.f.pix8, r.state, LIST_X + 18, y + sy + 4, c)
    G.text_fit(fs, r.source or "", LIST_X + 30 + T.f.pix8:getWidth(r.state), y + sy, LIST_W - 50 - T.f.pix8:getWidth(r.state), T.c.faint)
  end

  -- detalhes do port selecionado
  local r = self.results[self.sel]
  local px, py, pw, ph = LIST_X + LIST_W + 10, LIST_Y, T.W - (LIST_X + LIST_W + 10) - 12, VISIBLE * ROW_H + 8
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  G.rect(px, py, pw, 4, ST_COLOR[r.state], 2)
  G.clip(px + 2, py + 6, pw - 4, ph - 8)
  local y = py + 12 - self.dscroll
  G.text_fit(T.f.h3, r.title, px + 12, y, pw - 24, T.c.text)
  y = y + G.step(T.f.h3, 24)
  G.tag(r.state, px + 12, y, ST_COLOR[r.state], T.c.bg0, T.f.pix8)
  G.text_fit(T.f.small, L("Instalado por: ") .. (r.source or "?"), px + 100, y + 2, pw - 112, T.c.dim)
  y = y + 26
  local function group(title, filter)
    local any = false
    for _, ck in ipairs(r.checks) do
      if filter(ck.state) then
        if not any then
          G.text(T.f.pix8, title, px + 12, y + 2, T.c.faint)
          y = y + 16
          any = true
        end
        mark(px + 12, y + 2, ck.state)
        G.text(T.f.bodyb, ck.label, px + 30, y, CK_COLOR[ck.state] == T.c.dim and T.c.dim or T.c.text)
        y = y + G.step(T.f.bodyb, 18)
        for _, l in ipairs(G.wrap(T.f.small, ck.detail, pw - 44)) do
          G.text(T.f.small, l, px + 30, y, T.c.dim)
          y = y + G.step(T.f.small, 14)
        end
        y = y + 4
      end
    end
    if any then y = y + 6 end
  end
  group(L("CONFIRMADO"), function(s) return s ~= "unk" end)
  group(L("NÃO FOI POSSÍVEL CONFIRMAR"), function(s) return s == "unk" end)
  self.detail_h = y + self.dscroll - (py + 12)
  G.unclip()

  local hints = { { "dpad", L("Port / detalhes") } }
  if self.state == "done" then hints[#hints + 1] = { "y", L("Verificar de novo") } end
  hints[#hints + 1] = { "b", self.state == "running" and L("Parar") or L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  if self.state == "idle" then
    if act == "a" then self:start() elseif act == "b" then App.pop() end
    return
  end
  local n = #self.results
  local maxd = math.max(0, (self.detail_h or 0) - (VISIBLE * ROW_H - 20))
  if act == "up" and n > 0 then self.sel = math.max(1, self.sel - 1); self.dscroll = 0
  elseif act == "down" and n > 0 then self.sel = math.min(n, self.sel + 1); self.dscroll = 0
  elseif act == "right" then self.dscroll = math.min(maxd, self.dscroll + 60)
  elseif act == "left" then self.dscroll = math.max(0, self.dscroll - 60)
  elseif act == "y" and self.state == "done" then self:start()
  elseif act == "b" then
    if self.state == "running" then self.ctl:push("cancel"); self.state = "done"
    else App.pop() end
  end
end

return S
