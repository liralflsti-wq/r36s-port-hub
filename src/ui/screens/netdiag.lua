-- =============================================================================
--  Manutencao > Diagnostico de rede
--  Mostra o que o sistema informa e faz testes reais. Wi-Fi conectado NAO e o
--  mesmo que internet funcionando: os dois aparecem separados.
--  A/Y testam de novo | B volta
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Net = require("core.net")
local Prefs = require("core.prefs")
local I18N = require("lib.i18n")

local S = {}
local NA = L("INFORMAÇÕES INDISPONÍVEIS")

function S:enter(p)
  self.auto_speed = p and p.speed
  self:start()
end

--- Mbps a partir de bytes/s
local function mbps(bps) return string.format("%.1f Mbps", bps * 8 / 1000000) end

--- teste de velocidade (download, upload e latencia), so quando o usuario pede
function S:start_speed()
  if self.sp and self.sp.running then return end
  if S.sp_thread_any and S.sp_thread_any:isRunning() then
    App.toast(L("Aguarde o teste de velocidade anterior terminar."), "warn")
    return
  end
  local d = self.d
  if not (d.ip and d.ip.connected) then
    App.toast(L("Sem conexão de rede. Conecte o console ao Wi-Fi."), "warn")
    return
  end
  self.sp = { running = true, phase = "latency" }
  self.sp_out = love.thread.getChannel("hub_speed_out")
  self.sp_out:clear()
  self.sp_thread = love.thread.newThread("threads/speedtest_thread.lua")
  self.sp_thread:start("hub_speed_out", I18N.lang)
  S.sp_thread_any = self.sp_thread
end

function S:update_speed()
  local sp = self.sp
  if not (sp and sp.running) then return end
  local e = self.sp_thread:getError()
  if e then U.log("speedtest:", e); sp.running = false; sp.error = L("Erro interno: ") .. tostring(e); return end
  local m = self.sp_out:pop()
  while m do
    if m.t == "phase" then sp.phase = m.phase
    elseif m.t == "result" then sp[m.k] = m
    elseif m.t == "error" then sp.running = false; sp.error = m.msg
    elseif m.t == "done" then
      sp.running = false
      if sp.download then
        Prefs.set("speed_last", string.format("%d|%d|%d|%d", math.floor(sp.download.v),
          (sp.upload and sp.upload.v) and math.floor(sp.upload.v) or -1, math.floor(sp.latency and sp.latency.v or -1), os.time()))
        App.toast(L("Velocidade: download ") .. mbps(sp.download.v)
          .. ((sp.upload and sp.upload.v) and (L("  •  upload ") .. mbps(sp.upload.v)) or ""), "ok")
      end
    end
    m = self.sp_out:pop()
  end
  if not sp.running and not sp.download and sp.error then App.toast(sp.error, "error") end
end

function S:start()
  self.d = {}
  self.running = true
  self.t0 = love.timer.getTime()
  self.out = love.thread.getChannel("hub_nettest_out")
  self.out:clear()
  self.thread = love.thread.newThread("threads/nettest_thread.lua")
  self.thread:start("hub_nettest_out", C.FETCH_SH)
  Net.invalidate()
end

function S:update()
  self:update_speed()
  if not self.running then return end
  local e = self.thread:getError()
  if e then U.log("netdiag:", e); self.running = false; self.error = tostring(e) end
  local m = self.out:pop()
  while m do
    if m.t == "set" then self.d[m.k] = m.v
    elseif m.t == "done" then
      self.running = false
      if self.auto_speed then self.auto_speed = false; self:start_speed() end
    end
    m = self.out:pop()
  end
end

--- estado geral (nunca confunde Wi-Fi com internet)
function S:overall()
  local d = self.d
  if self.error then return NA, T.c.dim end
  if not d.ip then return L("VERIFICANDO CONEXÃO"), T.c.yellow end
  if not d.ip.connected then
    if not d.wifi or not d.wifi.iface then
      -- nenhuma interface de rede legivel: nao da para afirmar nada alem disso
      return d.wifi and L("DESCONECTADO") or NA, d.wifi and T.c.red or T.c.dim
    end
    return L("DESCONECTADO"), T.c.red
  end
  if not d.internet then return L("VERIFICANDO CONEXÃO"), T.c.yellow end
  if not d.internet.ok then return L("SEM ACESSO À INTERNET"), T.c.orange end
  return L("CONECTADO"), T.c.green
end

local function ms(v) return v and (v .. L(" ms")) or "" end

function S:draw()
  local lbl, col = self:overall()
  G.header(L("Diagnóstico de rede"), (self.running or (self.sp and self.sp.running)) and L("testando...") or "")
  G.panel(12, 50, T.W - 24, 44, { bg = T.c.bg1, border = col, lw = 2 })
  G.text(T.f.pix16, lbl, 12, 64, col, "center", T.W - 24)
  if self.running then G.progress_busy(40, 84, T.W - 80, 6, App.t, col) end

  local d = self.d
  local x, y, w = 12, 102, T.W - 24
  G.panel(x, y, w, 334, { bg = T.c.bg1 })
  local cy = y + 10
  local function row(k, v, c)
    G.text_fit(T.f.small, k, x + 14, cy + 2, 130, T.c.faint)
    G.text_fit(T.f.bodyb, v, x + 150, cy, w - 164, c or T.c.text)
    cy = cy + 21
  end
  local function sep(title)
    G.text(T.f.pix8, title, x + 14, cy + 4, T.c.accent2)
    G.rect(x + 22 + T.f.pix8:getWidth(title), cy + 8, w - 40 - T.f.pix8:getWidth(title), 1, T.c.line)
    cy = cy + 20
  end
  local wait = L("verificando...")

  sep(L("REDE LOCAL"))
  if not d.wifi then row("Wi-Fi", wait, T.c.dim)
  elseif not d.wifi.iface then row("Wi-Fi", L("nenhuma interface sem fio encontrada"), T.c.red)
  else
    local up = d.wifi.oper == "up"
    local wl = d.ip and d.ip.connected and d.ip.iface == d.wifi.iface
    row("Wi-Fi", (wl and L("conectado") or (up and L("ligado, sem endereço IP") or L("desconectado")))
      .. "  (" .. d.wifi.iface .. (d.wifi.oper ~= "" and (L(", estado: ") .. d.wifi.oper) or "") .. ")",
      wl and T.c.green or T.c.red)
  end
  if not d.ssid then row(L("Nome da rede"), wait, T.c.dim)
  else row(L("Nome da rede"), d.ssid.value or L("indisponível (o sistema não informou)"), d.ssid.value and T.c.text or T.c.dim) end
  if not d.ip then row("IPv4", wait, T.c.dim); row(L("Interface"), wait, T.c.dim)
  else
    row("IPv4", d.ip.connected and d.ip.ip or L("INDISPONÍVEL"), d.ip.connected and T.c.accent2 or T.c.red)
    row(L("Interface"), d.ip.connected and (tostring(d.ip.iface) .. (d.ip.wireless and L("  (sem fio)") or "")) or "—")
  end
  if not d.gateway then row(L("Gateway"), wait, T.c.dim)
  else row(L("Gateway"), d.gateway.value or L("indisponível"), d.gateway.value and T.c.text or T.c.dim) end
  if not d.dns then row("DNS", wait, T.c.dim)
  else row("DNS", #d.dns.value > 0 and table.concat(d.dns.value, ", ") or L("indisponível"), #d.dns.value > 0 and T.c.text or T.c.dim) end
  if not d.signal then row(L("Sinal"), wait, T.c.dim)
  elseif d.signal.value then
    local s = d.signal.value
    row(L("Sinal"), s.quality .. "%" .. (s.dbm and string.format("  (%d dBm)", s.dbm) or ""),
      s.quality >= 60 and T.c.green or (s.quality >= 30 and T.c.yellow or T.c.red))
  else row(L("Sinal"), L("indisponível (o sistema não informou)"), T.c.dim) end

  cy = cy + 4
  sep(L("TESTES"))
  local it = d.internet
  if not it then row(L("Internet"), d.ip and d.ip.connected and wait or "—", T.c.dim)
  elseif it.skipped then row(L("Internet"), L("não testada: sem conexão de rede"), T.c.red)
  elseif it.ok then
    row(L("Internet"), L("OK  •  por IP ") .. (it.ip_ok and ms(it.ip_ms) or L("falhou")) .. L("  •  por nome ")
      .. (it.name_ok and ms(it.name_ms) or (it.dns_ok and L("falhou") or L("DNS falhou"))), T.c.green)
  else
    row(L("Internet"), L("SEM ACESSO") .. (it.dns_ok and "" or L("  •  DNS também falhou")), T.c.red)
  end
  local g = d.github
  if not g then row("GitHub", (it and not it.skipped) and wait or "—", T.c.dim)
  elseif g.skipped then row("GitHub", L("não testado: sem conexão de rede"), T.c.red)
  else
    local parts = { g.dns_ok and L("DNS ok") or L("DNS falhou") }
    if g.dns_ok then parts[#parts + 1] = g.tcp_ok and (L("conexão ") .. ms(g.tcp_ms)) or L("conexão falhou") end
    if g.method then
      parts[#parts + 1] = g.https and (L("HTTPS ok") .. (g.code and (" (" .. g.code .. ")") or "")) or (L("HTTPS falhou (") .. g.method .. ")")
    else
      parts[#parts + 1] = L("HTTPS não testado (curl/wget ausentes)")
    end
    row("GitHub", (g.ok and L("ACESSÍVEL  •  ") or L("INACESSÍVEL  •  ")) .. table.concat(parts, "  •  "), g.ok and T.c.green or T.c.red)
  end

  -- velocidade da internet (so quando o usuario pede: consome dados)
  cy = cy + 4
  sep(L("VELOCIDADE DA INTERNET"))
  local sp = self.sp
  if not sp then
    local last = Prefs.get("speed_last")
    local dn, up, lt, tm = (last or ""):match("^(%-?%d+)|(%-?%d+)|(%-?%d+)|(%d+)$")
    if dn then
      row(L("Último teste"), require("core.clock").datetime(tonumber(tm), true) .. "  •  " .. L("download ") .. mbps(tonumber(dn))
        .. (tonumber(up) >= 0 and (L("  •  upload ") .. mbps(tonumber(up))) or "")
        .. (tonumber(lt) >= 0 and ("  •  " .. tonumber(lt) .. L(" ms")) or ""), T.c.dim)
    end
    row(L("Velocidade"), L("Pressione X para medir (usa cerca de 33 MB de dados)."), T.c.dim)
  else
    local function phase_row(key, label, fmt)
      local r = sp[key]
      if r and r.failed then row(label, L("falhou"), T.c.red)
      elseif r then row(label, fmt(r), T.c.green)
      elseif sp.running and sp.phase == key then row(label, L("medindo..."), T.c.yellow)
      elseif sp.error then row(label, "—", T.c.dim)
      else row(label, sp.running and L("aguardando") or "—", T.c.dim) end
    end
    phase_row("latency", L("Latência"), function(r)
      return string.format("%.0f", r.v) .. L(" ms") .. (r.jitter and (L("  •  variação ") .. string.format("%.0f", r.jitter) .. L(" ms")) or "") end)
    phase_row("download", L("Download"), function(r) return mbps(r.v) .. "  (" .. U.format_bytes(r.bytes) .. L(" em ") .. string.format(L("%.1f s"), r.time) .. ")" end)
    phase_row("upload", L("Upload"), function(r) return mbps(r.v) .. "  (" .. U.format_bytes(r.bytes) .. L(" em ") .. string.format(L("%.1f s"), r.time) .. ")" end)
    if sp.running then G.progress_busy(x + 150, cy, w - 164, 4, App.t, T.c.accent2)
    elseif sp.error then G.text_fit(T.f.small, sp.error, x + 14, cy, w - 28, T.c.red) end
  end
  if self.error then G.text(T.f.small, L("Erro interno: ") .. self.error, x + 14, y + 318, T.c.red) end
  local busy = self.running or (sp and sp.running)
  local hints = {}
  if not busy then
    hints[#hints + 1] = { "a", L("Testar de novo") }
    hints[#hints + 1] = { "x", L("Testar velocidade") }
  end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local sp_busy = self.sp and self.sp.running
  if (act == "a" or act == "y") and not self.running and not sp_busy then self.sp = nil; self:start()
  elseif act == "x" and not self.running then self:start_speed()
  elseif act == "b" then App.pop() end
end

return S
