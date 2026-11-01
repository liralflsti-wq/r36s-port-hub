-- =============================================================================
--  Atividade FTP (tempo real) e Historico FTP (salvo, sem credenciais)
--  L1/R1 trocam a aba | X cancela a transferencia (Atividade) ou limpa (Historico)
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Ftp = require("core.ftp")

local S = {}
local TABS = { L("ATIVIDADE FTP"), L("HISTÓRICO FTP") }
local LIST_Y = 82

local ST_COLOR = {
  ["AGUARDANDO"] = T.c.dim, ["TRANSFERINDO"] = T.c.accent2, ["CONCLUÍDO"] = T.c.green,
  ["ERRO"] = T.c.red, ["CANCELADO"] = T.c.faint,
}
-- RECEBIMENTO: celular/PC -> R36S (STOR) | ENVIO: R36S -> celular/PC (RETR)
local OP = { recv = L("RECEBIMENTO"), send = L("ENVIO") }
local DIR = { recv = L("aparelho → R36S"), send = L("R36S → aparelho") }

function S:enter(p)
  self.tab = p.tab or 1
  self.sel, self.scroll = 1, 0
end

local function items(self)
  if self.tab == 1 then return Ftp.list() end
  local t = {}
  for i = #Ftp.history, 1, -1 do t[#t + 1] = Ftp.history[i] end
  return t
end

local function speed(v) return (v and v > 0) and (U.format_speed(v)) or "—" end

function S:draw()
  local right = Ftp.state == "on" and (Ftp.clients .. L(" cliente(s) conectado(s)")) or L("servidor desativado")
  G.header(L("Servidor FTP"), right)
  -- abas
  local x = 12
  G.button_icon("l1", x, 52)
  x = x + 30
  for i, t in ipairs(TABS) do
    local w = T.f.pix8:getWidth(t) + 24
    local on = i == self.tab
    G.rect(x, 48, w, 24, on and T.c.accent or T.c.bg2, 5)
    G.text(T.f.pix8, t, x, 56, on and T.c.bg0 or T.c.dim, "center", w)
    x = x + w + 8
  end
  G.button_icon("r1", x, 52)

  local list = items(self)
  local hints = { { "l1", L("Trocar aba") } }
  if #list == 0 then
    G.panel(12, LIST_Y, T.W - 24, 360, { bg = T.c.bg1 })
    if self.tab == 1 then
      G.text(T.f.pix16, L("NENHUMA TRANSFERÊNCIA"), 12, LIST_Y + 140, T.c.dim, "center", T.W - 24)
      G.text(T.f.body, Ftp.state == "on" and L("Envie ou baixe arquivos pelo celular/computador: o progresso aparece aqui.")
        or L("Ligue o servidor em Servidor FTP > INICIAR."), 40, LIST_Y + 172, T.c.faint, "center", T.W - 80)
    else
      G.text(T.f.pix16, L("HISTÓRICO VAZIO"), 12, LIST_Y + 150, T.c.dim, "center", T.W - 24)
    end
    hints[#hints + 1] = { "b", L("Voltar") }
    G.hints(hints)
    return
  end

  self.sel = U.clamp(self.sel, 1, #list)
  local rh = self.tab == 1 and 88 or 52
  local visible = math.floor(360 / (rh + 6))
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + visible then self.scroll = self.sel - visible end
  for i = self.scroll + 1, math.min(#list, self.scroll + visible) do
    local e = list[i]
    local y = LIST_Y + (i - self.scroll - 1) * (rh + 6)
    local on = i == self.sel
    local c = ST_COLOR[e.status] or T.c.dim
    G.panel(12, y, T.W - 24, rh, { bg = on and T.c.bg3 or T.c.bg1, border = on and T.c.accent or T.c.line, lw = on and 2 or 1 })
    G.rect(12, y + 8, 4, rh - 16, c, 2)
    local ow = G.tag(OP[e.op] or "?", 26, y + 8, e.op == "recv" and T.c.green or T.c.accent2, T.c.bg0, T.f.small)
    G.text_fit(T.f.bodyb, e.name or "?", 34 + ow, y + 7, T.W - 200 - ow, T.c.text)
    G.text(T.f.pix8, e.status, T.W - 28 - T.f.pix8:getWidth(e.status), y + 12, c)
    if self.tab == 1 then
      local pct = (e.total and e.total > 0) and math.min(100, math.floor(e.done * 100 / e.total)) or nil
      if e.status == "CONCLUÍDO" then pct = 100 end
      if pct then G.progress(26, y + 30, T.W - 52, 10, pct / 100, c)
      elseif e.status == "TRANSFERINDO" then G.progress_busy(26, y + 30, T.W - 52, 10, App.t, c)
      else G.progress(26, y + 30, T.W - 52, 10, 0, c) end
      local size
      if e.total then
        size = U.format_bytes(e.done) .. L(" de ") .. U.format_bytes(e.total) .. (pct and ("  (" .. pct .. "%)") or "")
      else
        size = U.format_bytes(e.done) .. L(" recebidos  •  total informado só no fim (o FTP não envia o tamanho antes)")
      end
      local has_reason = e.reason and e.reason ~= "" and e.status ~= "CONCLUÍDO"
      G.text_fit(T.f.small, size, 26, y + 46, has_reason and (T.W - 260) or (T.W - 52), T.c.text)
      local line = DIR[e.op] .. L("  •  atual ") .. speed(e.status == "TRANSFERINDO" and e.speed or 0) .. L("  •  média ") .. speed(e.avg)
        .. L("  •  tempo ") .. U.format_time(e.elapsed or 0)
      G.text_fit(T.f.small, line, 26, y + 62, T.W - 52, T.c.dim)
      if has_reason then
        G.text_fit(T.f.small, e.reason, T.W - 220, y + 46, 194, T.c.red)
      end
    else
      local when = require("core.clock").datetime(e.time or 0)
      local line = when .. "  •  " .. DIR[e.op or "send"] .. "  •  " .. U.format_bytes(e.size or 0)
        .. L("  •  média ") .. speed(e.avg) .. "  •  " .. U.format_time(e.elapsed or 0)
      if e.status ~= "CONCLUÍDO" and e.reason and e.reason ~= "" then line = line .. "  •  " .. require("lib.i18n").tr(e.reason) end
      G.text_fit(T.f.small, line, 26, y + 30, T.W - 52, e.status == "ERRO" and T.c.red or T.c.dim)
    end
  end
  local sel = list[self.sel]
  if self.tab == 1 and sel and (sel.status == "TRANSFERINDO" or sel.status == "AGUARDANDO") then
    hints[#hints + 1] = { "x", L("Cancelar transferência") }
  elseif self.tab == 2 then
    hints[#hints + 1] = { "x", L("Limpar histórico") }
  end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local list = items(self)
  local e = list[self.sel]
  if act == "l1" or act == "r1" or act == "left" or act == "right" then
    self.tab = self.tab == 1 and 2 or 1
    self.sel, self.scroll = 1, 0
  elseif act == "up" then self.sel = math.max(1, self.sel - 1)
  elseif act == "down" then self.sel = math.min(math.max(1, #list), self.sel + 1)
  elseif act == "b" then App.pop()
  elseif act == "x" and self.tab == 1 and e and (e.status == "TRANSFERINDO" or e.status == "AGUARDANDO") then
    App.show_dialog({ title = L("Cancelar transferência?"), kind = "warn",
      body = e.name .. L("\n\nSe for um recebimento, o arquivo incompleto é descartado."),
      buttons = { { label = L("CANCELAR"), fn = function() Ftp.cancel_xfer(e.id) end }, { label = "VOLTAR" } }, sel = 2 })
  elseif act == "x" and self.tab == 2 and #list > 0 then
    App.show_dialog({ title = L("Limpar histórico?"), kind = "warn",
      body = L("Todas as ") .. #list .. L(" entradas do histórico FTP serão apagadas. Os arquivos não são afetados."),
      buttons = { { label = "LIMPAR", fn = function() Ftp.clear_history(); App.toast(L("Histórico FTP limpo."), "ok") end },
        { label = "VOLTAR" } }, sel = 2 })
  end
end

return S
