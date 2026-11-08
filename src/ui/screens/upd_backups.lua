-- =============================================================================
--  Atualizacoes > Gerenciar backups
--  Cada backup guarda os arquivos que uma atualizacao trocou. Restaurar volta
--  a versao anterior (com um backup do estado atual antes); apagar pede
--  confirmacao. Ficam os 3 mais recentes.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Backup = require("core.updater.backup")
local Manager = require("core.updater.manager")
local Clock = require("core.clock")

local S = {}
local RH, TOP, VISIBLE = 50, 50, 7

function S:enter()
  self.sel, self.scroll = 1, 0
  self:load()
end

function S:load()
  self.list = Backup.list(C.APP_DIR)
  if self.sel > #self.list then self.sel = math.max(1, #self.list) end
end

function S:draw()
  G.header(L("Gerenciar backups"), #self.list .. " / " .. Backup.KEEP)
  if #self.list == 0 then
    G.text(T.f.h3, L("Nenhum backup ainda"), 0, 180, T.c.dim, "center", T.W)
    G.text(T.f.small, L("Cada atualização instalada cria um backup dos arquivos que trocou."), 40, 214, T.c.faint, "center", T.W - 80)
  end
  for i = self.scroll + 1, math.min(#self.list, self.scroll + VISIBLE) do
    local b = self.list[i]
    local y = TOP + (i - self.scroll - 1) * RH
    local on = i == self.sel
    G.rect(12, y, T.W - 24, RH - 4, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(12, y, T.W - 24, RH - 4, T.c.accent, 5, 2) end
    local ok = b.state == "complete"
    local ft, fs, ty, sy = G.row_fonts(RH - 4, 4, 25)
    G.text_fit(ft, L("Versão ") .. tostring(b.from_label or b.from or "?") .. "  (" .. L("antes de ") .. tostring(b.to or "?") .. ")",
      24, y + ty, T.W - 180, on and T.c.text or T.c.dim)
    G.text_fit(fs, Clock.datetime(b.created, true) .. "  •  " .. #(b.files or {}) .. L(" arquivo(s)") .. "  •  " .. tostring(b.package or ""),
      24, y + sy, T.W - 180, ok and T.c.faint or T.c.orange)
    local s = U.format_bytes(b.size or 0)
    G.text(ft, s, T.W - 26 - ft:getWidth(s), y + ty, T.c.text)
    if not ok then G.text(fs, L("incompleto"), T.W - 26 - fs:getWidth(L("incompleto")), y + sy, T.c.orange) end
  end
  if Manager.busy() and Manager.job.op == "restore" then
    local j = Manager.job
    G.rect(60, 180, T.W - 120, 90, T.c.bg0, 8, 0.95)
    G.frame(60, 180, T.W - 120, 90, T.c.yellow, 8, 2)
    G.text(T.f.pix8, L("RESTAURANDO..."), 60, 196, T.c.yellow, "center", T.W - 120)
    G.text(T.f.small, Manager.PHASE[j.phase or "verify"] or "", 60, 216, T.c.text, "center", T.W - 120)
    G.progress_busy(90, 244, T.W - 180, 8, App.t, T.c.yellow)
  end
  local hints = { { "dpad", L("Navegar") } }
  if #self.list > 0 then hints[#hints + 1] = { "a", L("Opções") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

local function restore(self, b)
  App.show_dialog({ title = L("Restaurar este backup?"), kind = "warn",
    body = L("O R36S PORT HUB volta para a versão ") .. tostring(b.from_label or b.from) .. L(" (") .. #(b.files or {})
      .. L(" arquivo(s) devolvidos, ") .. #(b.added or {}) .. L(" arquivo(s) novos removidos).")
      .. L("\n\nAntes, o estado atual também vai para um backup. Configurações, ports e gravações não são alterados."),
    buttons = { { label = L("RESTAURAR"), fn = function()
      local ok, why = Manager.start("restore", { backup = b.id, origin = "backup", package = b.id, version = b.from }, function(j)
        self:load()
        if j.state == "done" then
          App.show_dialog({ title = L("Backup restaurado"), kind = "ok",
            body = L("A versão ") .. tostring(b.from_label or b.from) .. L(" foi restaurada. Reinicie o app para usá-la."),
            buttons = { { label = L("REINICIAR O APP"), fn = function() require("ui.screens.updmgr").restart_app() end } },
            cancel = function() require("ui.screens.updmgr").restart_app() end })
        else
          App.show_dialog({ title = L("Não foi possível restaurar"), kind = "error", body = Manager.message(j.error_code, j.detail) })
        end
      end)
      if not ok then App.toast(why, "error") end
    end }, { label = "VOLTAR" } }, sel = 2 })
end

local function delete(self, b)
  App.show_dialog({ title = L("Apagar este backup?"), kind = "warn",
    body = L("O backup de ") .. Clock.datetime(b.created, true) .. L(" será apagado do cartão SD. Depois disso não será possível voltar para a versão ")
      .. tostring(b.from_label or b.from) .. L(" por ele."),
    buttons = { { label = L("APAGAR"), fn = function()
      if Backup.delete(C.APP_DIR, b.id) then App.toast(L("Backup apagado."), "info") else App.toast(L("Não foi possível apagar o backup."), "error") end
      self:load()
    end }, { label = "VOLTAR" } }, sel = 2 })
end

function S:action(act)
  if Manager.busy() and Manager.job.op == "restore" then return end
  local n = #self.list
  if act == "b" then App.pop(); return end
  if n == 0 then return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "a" then
    local b = self.list[self.sel]
    local btns = {}
    if b.state == "complete" then btns[#btns + 1] = { label = L("RESTAURAR"), fn = function() restore(self, b) end } end
    btns[#btns + 1] = { label = L("APAGAR"), fn = function() delete(self, b) end }
    btns[#btns + 1] = { label = "VOLTAR" }
    App.show_dialog({ title = L("Backup"), kind = "info",
      body = L("Criado: ") .. Clock.datetime(b.created, true) .. L("\nVersão guardada: ") .. tostring(b.from_label or b.from)
        .. L("\nAtualização: ") .. tostring(b.to) .. "  •  " .. tostring(b.package or "")
        .. L("\nArquivos guardados: ") .. #(b.files or {}) .. "  (" .. U.format_bytes(b.size or 0) .. ")"
        .. L("\nArquivos criados pela atualização: ") .. #(b.added or {})
        .. L("\nPasta: ") .. Backup.dir(C.APP_DIR) .. "/" .. b.id
        .. (b.state ~= "complete" and L("\n\nEste backup está incompleto e não pode ser restaurado.") or ""),
      buttons = btns, sel = #btns })
  end
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
end

return S
