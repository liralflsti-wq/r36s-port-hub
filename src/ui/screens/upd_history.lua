-- =============================================================================
--  Atualizacoes > Historico de atualizacoes (mais recentes primeiro)
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local History = require("core.updater.history")
local Clock = require("core.clock")

local S = {}
local RH, TOP, VISIBLE = 46, 50, 8

local ORIGIN = { ["local"] = L("local"), rede = L("rede"), backup = L("backup"), recuperacao = L("recuperação automática") }
local RESULT = { ok = L("CONCLUÍDA"), erro = L("FALHOU"), restaurado = L("DESFEITA") }

function S:enter()
  self.sel, self.scroll = 1, 0
  self.list = History.recent()
end

function S:draw()
  G.header(L("Histórico de atualizações"), #self.list .. L(" registro(s)"))
  if #self.list == 0 then
    G.text(T.f.h3, L("Nenhuma atualização registrada"), 0, 200, T.c.dim, "center", T.W)
  end
  for i = self.scroll + 1, math.min(#self.list, self.scroll + VISIBLE) do
    local h = self.list[i]
    local y = TOP + (i - self.scroll - 1) * RH
    local on = i == self.sel
    G.rect(12, y, T.W - 24, RH - 4, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(12, y, T.W - 24, RH - 4, T.c.accent, 5, 2) end
    local col = h.result == "ok" and T.c.green or (h.result == "restaurado" and T.c.yellow or T.c.red)
    local tw = G.tag(RESULT[h.result] or tostring(h.result), 22, y + 12, col, T.c.bg0, T.f.pix8)
    local ft, fs, ty, sy = G.row_fonts(RH - 4, 4, 23)
    G.text_fit(ft, tostring(h.from or "?") .. "  →  " .. tostring(h.to or "?"), 22 + tw + 10, y + ty, 220, T.c.text)
    local d = Clock.datetime(h.time, true)
    local df = G.fit(T.f.small, d, 150)
    local dw = df:getWidth(d)
    G.text_fit(fs, (ORIGIN[h.origin] or tostring(h.origin)) .. "  •  " .. tostring(h.package or ""), 22 + tw + 10, y + sy, math.min(T.W - 260 - tw, T.W - 40 - dw - (22 + tw + 10)), T.c.dim)
    G.text(df, d, T.W - 26 - dw, y + 14 + math.floor((T.base_font(T.f.small):getHeight() - df:getHeight()) / 2), T.c.faint)
  end
  local hints = { { "dpad", L("Navegar") } }
  if #self.list > 0 then hints[#hints + 1] = { "a", L("Detalhes") } end
  local cur = self.list[self.sel]
  if cur and require("core.updater.manager").has_notes(cur) then hints[#hints + 1] = { "y", L("Novidades") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local n = #self.list
  if act == "b" then App.pop(); return end
  if n == 0 then return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "y" then
    local h = self.list[self.sel]
    if require("core.updater.manager").has_notes(h) then
      App.push("upd_notes", { to = h.to, description = h.description, changes = h.changes, fixes = h.fixes })
    end
  elseif act == "a" then
    local h = self.list[self.sel]
    App.show_dialog({ title = L("Atualização"), kind = h.result == "ok" and "info" or "warn",
      body = L("Versão anterior: ") .. tostring(h.from or "?") .. L("\nVersão instalada: ") .. tostring(h.to or "?")
        .. L("\nData: ") .. Clock.datetime(h.time, true) .. L("\nOrigem: ") .. (ORIGIN[h.origin] or tostring(h.origin))
        .. L("\nPacote: ") .. tostring(h.package or "—") .. L("\nResultado: ") .. (RESULT[h.result] or tostring(h.result))
        .. (h.backup and (L("\nBackup: ") .. h.backup) or "")
        .. (h.error and (L("\n\nErro: ") .. h.error) or "") })
  end
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
end

return S
