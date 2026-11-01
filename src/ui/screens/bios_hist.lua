-- =============================================================================
--  BIOS do Sistema > Historico e backups
--  Instalacoes, restauracoes, recuperacoes e limpezas. A em uma instalacao com
--  backup restaura as BIOS que ela substituiu (com confirmacao).
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Bios = require("core.bios")
local Clock = require("core.clock")

local S = {}

local OPS = { install = L("Instalação"), restore = L("Restauração de backup"), recover = L("Recuperação automática"), clean = L("Limpeza") }

function S:enter() self.sel, self.top = 1, 0; self.list = Bios.history() end
function S:resume() self.list = Bios.history() end

local function summary(h)
  if h.op == "clean" then return string.format(I18N.tr(L("%d item(ns) apagado(s)  •  %s liberados")), h.count or 0, U.format_bytes(h.freed or 0)) end
  if h.op == "recover" then return I18N.tr(L("instalação interrompida desfeita na abertura do app")) end
  if h.result == "error" then return I18N.tr(L("falhou em ")) .. tostring(h.failed or "?") .. I18N.tr(L("; arquivos anteriores restaurados")) end
  local n, u, s, r = 0, 0, 0, 0
  for _, x in ipairs(h.items or {}) do
    if x.action == "new" then n = n + 1 elseif x.action == "replace" then u = u + 1 elseif x.action == "restored" then r = r + 1 else s = s + 1 end
  end
  if h.op == "restore" then return string.format(I18N.tr(L("%d arquivo(s) restaurado(s)")), r) end
  return string.format(I18N.tr(L("%d novas  •  %d substituídas  •  %d idênticas")), n, u, s)
end

function S:draw()
  G.header(L("Histórico e backups"), string.format(I18N.tr(L("%d registro(s)")), #self.list))
  if #self.list == 0 then
    G.text(T.f.bodyb, L("Nenhuma operação de BIOS registrada"), 0, 200, T.c.dim, "center", T.W)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  local rh = 50 + (T.f.bodyb:getHeight() - T.base_font(T.f.bodyb):getHeight()) + (T.f.small:getHeight() - T.base_font(T.f.small):getHeight())
  local vis = math.floor((436 - 50) / rh)
  self.vis = vis
  if self.sel > self.top + vis then self.top = self.sel - vis end
  if self.sel <= self.top then self.top = self.sel - 1 end
  for i = self.top + 1, math.min(#self.list, self.top + vis) do
    local h = self.list[i]
    local y = 50 + (i - self.top - 1) * rh
    local on = i == self.sel
    G.rect(12, y, T.W - 24, rh - 4, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(12, y, T.W - 24, rh - 4, T.c.yellow, 5, 2) end
    local ok = h.result == "ok"
    local tw = G.tag(ok and L("OK") or L("FALHOU"), 22, y + (rh - 4) / 2 - 8, ok and T.c.green or T.c.red, T.c.bg0, T.f.pix8)
    local ft, fs, ty, sy = G.row_fonts(rh - 4, 5, 26)
    local d = Clock.datetime(h.time or 0, true)
    local df = G.fit(T.f.small, d, 150)
    G.text_fit(ft, I18N.tr(OPS[h.op] or h.op) .. (h.backup and h.op == "install" and ("  •  " .. I18N.tr(L("com backup"))) or ""),
      32 + tw, y + ty, T.W - 80 - tw - df:getWidth(d), on and T.c.text or T.c.dim)
    G.text(df, d, T.W - 26 - df:getWidth(d), y + ty + 2, T.c.faint)
    G.text_fit(fs, summary(h), 32 + tw, y + sy, T.W - 60 - tw, T.c.faint)
  end
  local h = self.list[self.sel]
  local hints = { { "dpad", L("Navegar") } }
  if h and h.backup and h.op == "install" then hints[#hints + 1] = { "a", L("Restaurar backup") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local n = #self.list
  if act == "b" then App.pop(); return end
  if n == 0 then return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "a" then
    local h = self.list[self.sel]
    if not (h.backup and h.op == "install") then return end
    if Bios.busy() then App.toast(L("Aguarde a operação de BIOS em andamento."), "warn"); return end
    local names = {}
    for _, x in ipairs(h.items or {}) do if x.action == "replace" then names[#names + 1] = x.target end end
    App.show_dialog({
      title = L("Restaurar backup?"), kind = "warn",
      body = I18N.tr(L("As BIOS que esta instalação substituiu voltam para a versão anterior (conferidas pelo MD5 do backup). BIOS novas que ela instalou não são apagadas.")) ..
        (#names > 0 and ("\n" .. table.concat(names, ", ")) or ""),
      buttons = {
        { label = L("RESTAURAR"), danger = true, fn = function()
          local ok, err = Bios.start("restore", { backup = h.backup }, function(j)
            if j.state == "done" then
              App.toast(L("Backup restaurado e conferido."), "ok")
              Bios.start("scan")
            else
              App.show_dialog({ title = L("BIOS do Sistema"), kind = "error", body = Bios.message(j.error_code, j.detail) })
            end
            self.list = Bios.history()
          end)
          if not ok then App.toast(err, "warn") end
        end },
        { label = L("CANCELAR") },
      },
      sel = 2,
    })
  end
end

return S
