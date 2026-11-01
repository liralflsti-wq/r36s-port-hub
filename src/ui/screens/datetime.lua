-- =============================================================================
--  Configuracoes > Informacoes do console > Data e hora
--  Relogio REAL do sistema (atualizado a cada segundo), fuso, sincronizacao
--  automatica (servico do proprio sistema), ajuste manual e formatos de exibicao.
--  Consultas e alteracoes do sistema rodam em threads/datetime_thread.lua.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Prefs = require("core.prefs")
local Clock = require("core.clock")
local Net = require("core.net")
local lg = love.graphics

local S = {}

local WEEK = { L("Domingo"), L("Segunda-feira"), L("Terça-feira"), L("Quarta-feira"), L("Quinta-feira"), L("Sexta-feira"), L("Sábado") }
local DATE_LABEL = { dmy = L("DD/MM/AAAA"), mdy = L("MM/DD/AAAA"), ymd = L("AAAA-MM-DD") }
local WHY = {
  perm = L("O sistema não deu permissão de administrador (sudo)."),
  notool = L("O comando timedatectl não existe neste sistema."),
  unsupported = L("O sistema não tem um serviço de sincronização (NTP) instalado."),
  timeout = L("O servidor de horário não respondeu em 30 segundos."),
  nosync = L("Nenhum serviço ou ferramenta de sincronização foi encontrado no sistema."),
  service_only = L("O serviço de sincronização do sistema faz isso sozinho; não há como pedir agora."),
  invalid = L("Valor inválido."),
}

-- ---------------------------------------------------------------------------
-- tarefas em segundo plano
local seq = 0
function S:job(op, params, on_done)
  if self.busy then return false end
  seq = seq + 1
  local name = "hub_dt_" .. seq
  local ch = love.thread.getChannel(name)
  ch:clear()
  local job = params or {}
  job.op = op
  local th = love.thread.newThread("threads/datetime_thread.lua")
  th:start(name, job)
  self.busy = { ch = ch, th = th, op = op, cb = on_done }
  return true
end

function S:poll()
  local b = self.busy
  if not b then return end
  local m = b.ch:pop()
  while m and m.t == "progress" do self.prog = m; m = b.ch:pop() end
  local err = not m and b.th:getError()
  if not m and not err then return end
  self.busy, self.prog = nil, nil
  if err then m = { ok = false, why = tostring(err), op = b.op } end
  if m.status then self.st = m.status; self.st_t = love.timer.getTime() end
  if b.cb then b.cb(m) end
end

function S:why(w) return WHY[w] and I18N.tr(WHY[w]) or tostring(w or "?") end

-- ---------------------------------------------------------------------------
function S:enter()
  self.sel = 1
  self.t = 0
  self.err_sync = nil
  Clock.refresh()
  self:job("status")
end

function S:resume()
  Clock.refresh()
  if not self.busy then self:job("status") end
end

function S:update(dt)
  self:poll()
  self.t = self.t + dt
  -- estado do sistema a cada 5 s (consulta leve, so com a tela aberta)
  if not self.busy and self.t > 5 then
    self.t = 0
    self:job("status")
  end
end

function S:rows()
  return { "auto", "sync", "zone", "manual", "tfmt", "dfmt" }
end

--- estado da sincronizacao em texto + cor
function S:sync_state()
  local st = self.st
  if not st then return L("Verificando..."), "dim" end
  if self.busy and self.busy.op == "sync" then return L("Sincronizando..."), "yellow" end
  if not st.can_auto and not st.ntp then
    return L("Sincronização indisponível"), "dim"
  end
  if not st.ntp then return L("Modo manual"), "accent2" end
  if self.err_sync then return L("Erro ao atualizar"), "red" end
  if st.synced then return L("Sincronizado"), "green" end
  local net = Net.current()
  if not (net and net.connected) then return L("Aguardando conexão"), "yellow" end
  return L("Sincronizando..."), "yellow"
end

-- ---------------------------------------------------------------------------
function S:toggle_auto()
  local st = self.st
  if not st then return end
  if not st.timedatectl then App.toast(self:why("notool"), "warn"); return end
  if not st.can_auto and not st.ntp then App.toast(self:why("unsupported"), "warn"); return end
  local on = not st.ntp
  App.show_dialog({
    title = on and L("Ativar sincronização?") or L("Desativar sincronização?"),
    kind = "info",
    body = on and L("O serviço de horário do próprio sistema passa a acertar a data e a hora pela internet (NTP) sempre que houver conexão. Sem internet, o horário atual é mantido.")
      or L("O sistema para de acertar o relógio pela internet. A data e a hora atuais são mantidas, e você pode ajustá-las manualmente."),
    buttons = {
      { label = on and L("ATIVAR") or L("DESATIVAR"), fn = function()
        self:job("set_ntp", { on = on }, function(m)
          if m.ok then
            self.err_sync = nil
            Prefs.set("dt_auto", on and "1" or "0")
            App.toast(on and L("Sincronização automática ativada.") or L("Sincronização automática desativada."), "ok")
          else
            App.show_dialog({ title = L("Não alterado"), kind = "error", body = self:why(m.why) })
          end
        end)
      end },
      { label = L("CANCELAR") },
    },
  })
end

function S:sync_now()
  local st = self.st
  if not st then return end
  if not st.ntp then App.toast(L("Ative a sincronização automática para sincronizar pela internet."), "info"); return end
  local net = Net.current()
  if not (net and net.connected) then
    App.toast(L("Sem conexão com a internet. A data e a hora atuais foram mantidas."), "warn")
    return
  end
  self.err_sync = nil
  self:job("sync", {}, function(m)
    Clock.refresh()
    if m.ok then
      Prefs.set("dt_last_sync", tostring(os.time()))
      App.toast(L("Data e hora sincronizadas: ") .. Clock.datetime(), "ok")
    else
      self.err_sync = m.why
      App.show_dialog({ title = L("Não sincronizado"), kind = "error",
        body = self:why(m.why) .. "\n\n" .. I18N.tr(L("A data e a hora atuais foram mantidas.")) })
    end
  end)
end

function S:action(act)
  if act == "b" then if not (self.busy and self.busy.op == "set_time") then App.pop() end; return end
  local rows = self:rows()
  local n = #rows
  local r = rows[self.sel]
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "left" or act == "right" or act == "a" then
    local dir = act == "left" and -1 or 1
    if self.busy and act == "a" and (r == "auto" or r == "sync" or r == "manual" or r == "zone") then
      App.toast(L("Aguarde a operação atual terminar."), "info"); return
    end
    if r == "tfmt" then
      Prefs.set("time_format", Clock.fmt24() and "12" or "24")
    elseif r == "dfmt" then
      local list, cur = Clock.DATE_FORMATS, Clock.datefmt()
      local i = 1
      for k, v in ipairs(list) do if v == cur then i = k end end
      Prefs.set("date_format", list[(i - 1 + dir) % #list + 1])
    elseif act == "a" then
      if r == "auto" then self:toggle_auto()
      elseif r == "sync" then self:sync_now()
      elseif r == "zone" then
        if not (self.st and self.st.can_set_tz) then App.toast(L("A base de fusos horários não foi encontrada no sistema."), "warn"); return end
        App.push("tzpicker", { current = self.st.zone })
      elseif r == "manual" then
        App.push("datetime_edit", { ntp = self.st and self.st.ntp })
      end
    end
  end
end

-- ---------------------------------------------------------------------------
function S:draw()
  G.header(L("Data e hora"))
  local x, w = 12, T.W - 24
  local st = self.st or {}
  -- relogio grande
  G.panel(x, 50, w, 104, { bg = T.c.bg1 })
  local p = Clock.parts()
  G.text(T.f.h1, Clock.time(nil, true), x + 18, 58, T.c.text)
  G.text(T.f.bodyb, I18N.tr(WEEK[p.wday]) .. ", " .. Clock.date(), x + 18, 92, T.c.dim)
  local zline = (st.zone or I18N.tr(L("fuso não identificado"))) .. "  •  " .. Clock.offset_label() .. (Clock.abbr and ("  (" .. Clock.abbr .. ")") or "")
  G.text_fit(T.f.small, zline, x + 18, 116, w / 2 + 40, T.c.faint)
  -- estados
  local txt, col = self:sync_state()
  local tw = T.f.pix8:getWidth(I18N.tr(txt)) + 12
  G.tag(txt, x + w - 14 - tw, 62, T.c[col] or T.c.dim, T.c.bg0)
  local net = Net.current()
  local on = net and net.connected
  local nt = on and L("Internet: conectado") or L("Internet: sem conexão")
  G.text(T.f.small, nt, x + w - 14 - T.f.small:getWidth(I18N.tr(nt)), 88, on and T.c.green or T.c.yellow)
  if self.busy and self.busy.op == "sync" and self.prog then
    G.rect(x + w - 174, 112, 160, 6, T.c.bg0, 3)
    G.rect(x + w - 174, 112, 160 * self.prog.i / self.prog.n, 6, T.c.yellow, 3)
  end
  local ls = st.last_sync or tonumber(Prefs.get("dt_last_sync") or "")
  local lsl = I18N.tr(L("Última sincronização: ")) .. (ls and Clock.datetime(ls) or I18N.tr(L("nenhuma registrada")))
  G.text_fit(T.f.small, lsl, x + w / 2 + 70, 128, w / 2 - 84, T.c.faint, "right")

  -- opcoes
  local rows = self:rows()
  local y = 162
  local RH = 36
  for i, r in ipairs(rows) do
    local selected = i == self.sel
    local dim = false
    local label, value, vcol = "", "", T.c.text
    if r == "auto" then
      label = L("Sincronização automática (internet)")
      if not st.timedatectl and self.st then value, vcol = L("INDISPONÍVEL"), T.c.dim
      elseif self.st and not st.can_auto and not st.ntp then value, vcol = L("INDISPONÍVEL"), T.c.dim
      else value, vcol = st.ntp and L("ATIVADA") or L("DESATIVADA"), st.ntp and T.c.green or T.c.dim end
    elseif r == "sync" then
      label = L("Sincronizar agora"); dim = not st.ntp
      value = (self.busy and self.busy.op == "sync") and L("sincronizando...") or ""
    elseif r == "zone" then
      label, value = L("Fuso horário"), st.zone or "—"
    elseif r == "manual" then
      label = L("Ajustar data e hora manualmente")
      value = st.ntp and L("desativa a sincronização") or ""
      vcol = T.c.faint
    elseif r == "tfmt" then
      label, value = L("Formato da hora"), Clock.fmt24() and L("24 horas (14:30)") or L("12 horas (02:30 PM)")
    elseif r == "dfmt" then
      label, value = L("Formato da data"), DATE_LABEL[Clock.datefmt()]
    end
    G.rect(x, y, w, RH - 4, selected and T.c.bg3 or T.c.bg1, 7)
    if selected then G.frame(x, y, w, RH - 4, T.c.accent, 7, 2) end
    G.text(T.f.bodyb, label, x + 16, y + 8, dim and T.c.faint or (selected and T.c.text or T.c.dim))
    local arrows = selected and (r == "tfmt" or r == "dfmt")
    local chev = (r == "zone" or r == "manual" or r == "sync")
    local vw = T.f.bodyb:getWidth(I18N.tr(value))
    local vx = x + w - 16 - vw - ((arrows or chev) and 18 or 0)
    if value ~= "" then G.text(r == "manual" and T.f.small or T.f.bodyb, value, r == "manual" and (x + w - 34 - T.f.small:getWidth(I18N.tr(value))) or vx, y + (r == "manual" and 10 or 8), vcol) end
    if arrows or chev then
      G.color(selected and T.c.accent or T.c.faint)
      local ax, ay = x + w - 26, y + 16
      lg.polygon("fill", ax, ay - 5, ax, ay + 5, ax + 6, ay)
    end
    y = y + RH
  end
  -- detalhes do sistema
  local svc = st.service or (self.st and I18N.tr(L("nenhum serviço ativo")) or "")
  local info = I18N.tr(L("Serviço: ")) .. svc .. "  •  RTC: " .. (st.rtc or (self.st and I18N.tr(L("não encontrado")) or ""))
    .. (st.server and ("  •  " .. st.server) or "")
  G.text_fit(T.f.small, info, x + 4, 382, w - 8, T.c.faint)
  -- comportamento observado no dArkOSRE: ao ligar com internet, o sistema acerta a hora sozinho
  G.text_fit(T.f.small, L("Com a sincronização ligada, o console acerta a data e a hora sozinho ao ligar com internet."), x + 4, 420, w - 8, T.c.accent2)
  local desc = ({
    auto = L("Usa o serviço de horário do próprio sistema (NTP). Sem internet, a hora atual é mantida e ele tenta de novo sozinho."),
    sync = L("Pede uma sincronização agora (precisa de internet e da sincronização automática ligada)."),
    zone = L("Todos os fusos da base IANA instalada no sistema, com horário de verão quando houver."),
    manual = L("Dia, mês, ano, hora, minutos e segundos. Altera o relógio do sistema."),
    tfmt = L("Só muda a exibição no R36S PORT HUB."),
    dfmt = L("Só muda a exibição no R36S PORT HUB."),
  })[rows[self.sel]] or ""
  G.text_fit(T.f.small, desc, x + 4, 401, w - 8, T.c.dim)
  G.hints({ { "dpad", L("Navegar") }, { "a", L("Selecionar") }, { "b", L("Voltar") } })
end

return S
