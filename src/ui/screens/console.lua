-- Informacoes do console (somente leitura). Y atualiza os dados.
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local SysInfo = require("core.sysinfo")

local S = {}

function S:enter() self:refresh() end
function S:refresh() self.info = SysInfo.collect() end

local function section(title, x, y, w, h, c)
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  G.rect(x, y, w, 4, c, 2)
  G.text(T.f.pix8, U.upper(title), x + 12, y + 12, c)
end

local function row(label, value, x, y, w)
  G.text_fit(T.f.small, label, x, y, 86, T.c.faint)
  G.text_fit(T.f.small, value, x + 92, y, w - 92, T.c.text)
end

function S:draw()
  local r = self.info
  G.header(L("Informações do Console"), L("Atualizado ") .. r.time)
  local NA = SysInfo.NA

  -- Armazenamento
  section(L("Armazenamento"), 12, 50, 302, 190, T.c.accent2)
  local y = 72
  for i, s in ipairs(r.storage) do
    if i == 2 then
      row(L("Cartão 2"), s.ok and (U.format_bytes(s.free) .. L(" livres de ") .. U.format_bytes(s.total)) or NA, 24, y, 278)
      break
    end
    G.text_fit(T.f.bodyb, s.label, 24, y, 278, T.c.text)
    if s.ok then
      G.progress(24, y + 22, 278, 12, s.frac, s.frac > 0.9 and T.c.red or T.c.accent2)
      row(L("Total"), U.format_bytes(s.total), 24, y + 40, 278)
      row(L("Utilizado"), U.format_bytes(s.used) .. string.format(" (%d%%)", math.floor(s.frac * 100 + 0.5)), 24, y + 56, 278)
      row(L("Livre"), U.format_bytes(s.free), 24, y + 72, 278)
      y = y + 94
    else
      row(L("Situação"), NA, 24, y + 22, 278)
      y = y + 46
    end
  end

  -- Memoria
  section(L("Memória RAM"), 326, 50, 302, 110, T.c.yellow)
  if r.mem.ok then
    G.progress(338, 72, 278, 12, r.mem.frac, T.c.yellow)
    row(L("Total"), U.format_bytes(r.mem.total), 338, 92, 278)
    row(L("Utilizada"), U.format_bytes(r.mem.used) .. string.format(" (%d%%)", math.floor(r.mem.frac * 100 + 0.5)), 338, 108, 278)
    row(L("Disponível"), U.format_bytes(r.mem.avail), 338, 124, 278)
  else
    row(L("Memória"), NA, 338, 76, 278)
  end

  -- PortMaster
  section("PortMaster", 326, 168, 302, 72, T.c.green)
  if r.pm.installed then
    row(L("Instalado"), L("Sim") .. (r.pm.version and ("  (" .. r.pm.version .. ")") or ""), 338, 188, 278)
    row(L("Local"), r.pm.path, 338, 204, 278)
    local n = #(r.pm.runtimes or {})
    row(L("Runtimes"), n > 0 and (n .. L(" em libs/")) or L("Nenhum encontrado em libs/"), 338, 220, 278)
  else
    row(L("Instalado"), L("Não encontrado"), 338, 188, 278)
  end

  -- Sistema
  section(L("Sistema"), 12, 248, T.W - 24, 188, T.c.accent)
  local sx, sy = 24, 270
  row(L("Sistema"), r.os, sx, sy, T.W - 48)
  row(L("Dispositivo"), r.model, sx, sy + 20, T.W - 48)
  row(L("Arquitetura"), r.arch, sx, sy + 40, T.W - 48)
  row(L("Kernel"), r.kernel, sx, sy + 60, 296)
  row(L("Núcleos CPU"), r.cores, sx, sy + 80, 296)
  row(L("Ligado há"), r.uptime, sx, sy + 100, 296)
  -- coluna da direita: bateria, rede e versao do hub (leituras reais)
  local rx, rw = 330, T.W - 24 - 330
  local b = require("core.battery").get()
  row(L("Bateria"), b.ok and (b.pct .. "%" .. (b.charging and L("  •  carregando") or "")) or NA, rx, sy + 60, rw)
  local st = require("core.net").current()
  local net = (not st) and L("Verificando...") or (st.connected and (L("Conectado  •  ") .. tostring(st.ip)) or L("Desconectado"))
  row(L("Rede"), net, rx, sy + 80, rw)
  row(L("PORT HUB"), require("config").VERSION, rx, sy + 100, rw)
  local rts = r.pm.runtimes or {}
  if #rts > 0 then
    local shown = {}
    for i = 1, math.min(4, #rts) do shown[#shown + 1] = rts[i]:gsub("%.squashfs$", "") end
    row(L("Runtimes"), table.concat(shown, ", ") .. (#rts > 4 and string.format(L(" … e mais %d"), #rts - 4) or ""), sx, sy + 124, T.W - 48)
  end
  G.hints({ { "y", L("Atualizar dados") }, { "b", L("Voltar") } })
end

function S:action(act)
  if act == "y" then
    self:refresh()
    App.toast(L("Informações atualizadas."), "info")
  elseif act == "b" then App.pop()
  end
end

return S
