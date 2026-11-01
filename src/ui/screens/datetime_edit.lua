-- =============================================================================
--  Data e hora > Ajustar manualmente
--  Seletores de dia, mes, ano, hora, minutos e segundos (cima/baixo muda o
--  valor, esquerda/direita troca de campo). SALVAR ALTERACOES pede confirmacao
--  e grava no relogio do SISTEMA (desligando a sincronizacao automatica antes).
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local J = require("core.dtjob")
local Clock = require("core.clock")

local S = {}

local NAMES = { d = L("Dia"), mo = L("Mês"), y = L("Ano"), h = L("Hora"), mi = L("Minutos"), s = L("Segundos") }
local LIMITS = { y = { 2000, 2099 }, mo = { 1, 12 }, h = { 0, 23 }, mi = { 0, 59 }, s = { 0, 59 } }

local function days_in(y, m)
  local dm = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) then return 29 end
  return dm[m]
end

function S:enter(p)
  self.ntp = p.ntp
  local now = Clock.parts()
  self.v = { y = math.max(2000, math.min(2099, now.year)), mo = now.month, d = now.day, h = now.hour, mi = now.min, s = now.sec }
  -- ordem dos campos de data segue o formato escolhido
  local f = Clock.datefmt()
  local date = (f == "mdy") and { "mo", "d", "y" } or ((f == "ymd") and { "y", "mo", "d" } or { "d", "mo", "y" })
  self.fields = { date[1], date[2], date[3], "h", "mi", "s", "save", "cancel" }
  self.sel = 1
  self.t0 = love.timer.getTime()
end

function S:limits(k)
  if k == "d" then return 1, days_in(self.v.y, self.v.mo) end
  return LIMITS[k][1], LIMITS[k][2]
end

function S:bump(k, dir)
  local lo, hi = self:limits(k)
  local v = self.v[k] + dir
  if v > hi then v = lo elseif v < lo then v = hi end
  self.v[k] = v
  -- dia que deixou de existir (ex.: 31 -> fevereiro)
  local dmax = days_in(self.v.y, self.v.mo)
  if self.v.d > dmax then self.v.d = dmax end
end

function S:text()
  local v = self.v
  return string.format("%04d-%02d-%02d %02d:%02d:%02d", v.y, v.mo, v.d, v.h, v.mi, v.s)
end

function S:save()
  local v = self.v
  local body = I18N.tr(L("Aplicar ao relógio do sistema:")) .. "\n" .. Clock.format_values(v.y, v.mo, v.d, v.h, v.mi, v.s)
  if self.ntp then body = body .. "\n\n" .. I18N.tr(L("A sincronização automática pela internet será desativada para manter este horário.")) end
  App.show_dialog({
    title = L("Salvar data e hora?"), kind = "warn", body = body,
    buttons = {
      { label = L("SALVAR"), fn = function()
        local v = self.v
        self.job = J.start("set_time", { y = v.y, mo = v.mo, d = v.d, h = v.h, mi = v.mi, s = v.s })
      end },
      { label = L("CANCELAR") },
    },
    sel = 2,
  })
end

function S:update(dt)
  local m = J.poll(self.job)
  if not m then return end
  self.job = nil
  if m.ok then
    Clock.refresh()
    App.toast(L("Data e hora do sistema alteradas: ") .. Clock.datetime(), "ok")
    App.pop()
  else
    local why = (m.why == "perm") and L("O sistema não deu permissão de administrador (sudo).")
      or ((m.why == "invalid") and L("Data ou hora inválida.") or tostring(m.why))
    App.show_dialog({ title = L("Hora não alterada"), kind = "error", body = why })
  end
end

function S:action(act)
  if self.job then return end
  local n = #self.fields
  local f = self.fields[self.sel]
  if act == "b" then App.pop(); return end
  if act == "left" then self.sel = (self.sel - 2) % n + 1
  elseif act == "right" then self.sel = self.sel % n + 1
  elseif (act == "up" or act == "down") and self.v[f] then self:bump(f, act == "up" and 1 or -1)
  elseif act == "down" and not self.v[f] then -- dos botoes volta aos campos
  elseif act == "a" then
    if f == "save" then self:save()
    elseif f == "cancel" then App.pop()
    else self.sel = self.sel % n + 1 end
  end
end

function S:draw()
  G.header(L("Ajustar data e hora"))
  local x, w = 12, T.W - 24
  G.panel(x, 50, w, 300, { bg = T.c.bg1 })
  G.text(T.f.small, L("Cima/baixo muda o valor  •  esquerda/direita troca de campo"), x, 62, T.c.dim, "center", w)
  -- campos: [data] [hora]
  local fw, fh, gap = 74, 64, 8
  local function field(i, k, fx, fy, wide)
    local on = self.fields[self.sel] == k
    local ww = wide and (fw + 20) or fw
    G.rect(fx, fy, ww, fh, on and T.c.bg3 or T.c.bg0, 8)
    G.frame(fx, fy, ww, fh, on and T.c.accent or T.c.line, 8, on and 2 or 1)
    G.text(T.f.small, NAMES[k], fx, fy - 18, on and T.c.accent or T.c.faint, "center", ww)
    G.text(T.f.h1, string.format(k == "y" and "%04d" or "%02d", self.v[k]), fx, fy + 16, on and T.c.text or T.c.dim, "center", ww)
    if on then
      G.color(T.c.accent)
      love.graphics.polygon("fill", fx + ww / 2 - 6, fy - 2 + 0, fx + ww / 2 + 6, fy - 2, fx + ww / 2, fy - 8)
      love.graphics.polygon("fill", fx + ww / 2 - 6, fy + fh + 2, fx + ww / 2 + 6, fy + fh + 2, fx + ww / 2, fy + fh + 8)
    end
    return ww
  end
  local total = 3 * fw + 20 + 2 * gap + 30 + 3 * fw + 2 * gap
  local fx = x + (w - total) / 2
  local fy = 120
  for i = 1, 3 do
    local k = self.fields[i]
    fx = fx + field(i, k, fx, fy, k == "y") + gap
  end
  fx = fx + 30 - gap
  for i = 4, 6 do fx = fx + field(i, self.fields[i], fx, fy) + gap end
  -- previsao no formato da interface
  local v = self.v
  G.text(T.f.body, I18N.tr(L("Como vai ficar: ")) .. Clock.format_values(v.y, v.mo, v.d, v.h, v.mi, v.s), x, 214, T.c.dim, "center", w)
  G.text(T.f.small, I18N.tr(L("Hora local do fuso atual  •  agora: ")) .. Clock.date() .. " " .. Clock.time(nil, true), x, 236, T.c.faint, "center", w)
  if self.ntp then
    G.text(T.f.small, L("A sincronização automática está ligada e será desativada ao salvar."), x, 258, T.c.yellow, "center", w)
  end
  -- botoes
  local bw, bh = 236, 42
  local bx = x + (w - (bw * 2 + 14)) / 2
  for i, k in ipairs({ "save", "cancel" }) do
    local on = self.fields[self.sel] == k
    local c = k == "save" and T.c.accent or T.c.accent2
    local label = k == "save" and L("SALVAR ALTERAÇÕES") or L("CANCELAR")
    if on then
      G.rect(bx - 3, 290 - 3, bw + 6, bh + 6, c, 9, App.pulse(0.3, 0.15, 5))
      G.rect(bx, 290, bw, bh, c, 8)
      G.text(T.f.pix8, label, bx, 290 + 17, T.c.bg0, "center", bw)
    else
      G.rect(bx, 290, bw, bh, T.c.bg2, 8)
      G.frame(bx, 290, bw, bh, c, 8)
      G.text(T.f.pix8, label, bx, 290 + 17, c, "center", bw)
    end
    bx = bx + bw + 14
  end
  if self.job then G.text(T.f.small, L("Aplicando..."), x, 360, T.c.yellow, "center", w) end
  G.hints({ { "dpad", L("Mudar / trocar campo") }, { "a", L("Confirmar") }, { "b", L("Voltar") } })
end

return S
