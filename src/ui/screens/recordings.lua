-- =============================================================================
--  Transmissao e gravacao > Gravacoes salvas
--  Lista os videos da pasta r36sporthub/gravacoes (mais recentes primeiro).
--  Somente consulta: nada e apagado por esta tela.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Rec = require("core.recordings")
local Clock = require("core.clock")

local S = {}
local RH = 46
local TOP = 50
local VISIBLE = 8

function S:enter()
  self.sel, self.scroll = 1, 0
  self:load()
end

function S:resume() self:load() end

function S:load()
  self.list = Rec.list()
  if self.sel > #self.list then self.sel = math.max(1, #self.list) end
end

function S:draw()
  G.header(L("Gravações salvas"), #self.list .. L(" arquivo(s)"))
  if #self.list == 0 then
    G.panel(40, 120, T.W - 80, 150, { bg = T.c.bg1 })
    G.text(T.f.h3, L("Nenhuma gravação ainda"), 40, 150, T.c.text, "center", T.W - 80)
    G.text(T.f.small, L("Use INICIAR GRAVAÇÃO na tela de transmissão e gravação. Os vídeos ficam em r36sporthub/gravacoes."),
      60, 190, T.c.dim, "center", T.W - 120)
  end
  for i = self.scroll + 1, math.min(#self.list, self.scroll + VISIBLE) do
    local r = self.list[i]
    local y = TOP + (i - self.scroll - 1) * RH
    local on = i == self.sel
    G.rect(12, y, T.W - 24, RH - 4, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(12, y, T.W - 24, RH - 4, T.c.accent, 5, 2) end
    local tag = r.kind == "mp4" and "MP4" or "R36REC"
    local tw = G.tag(tag, 22, y + 12, r.kind == "mp4" and T.c.accent2 or T.c.orange, T.c.bg0, T.f.pix8)
    local ft, fs, ty, sy = G.row_fonts(RH - 4, 4, 23)
    G.text_fit(ft, r.name, 22 + tw + 10, y + ty, T.W - 230 - tw, on and T.c.text or T.c.dim)
    G.text_fit(fs, Clock.datetime(r.mtime, true), 22 + tw + 10, y + sy, T.W - 230 - tw, T.c.faint)
    local right = Rec.format_dur(r.dur) .. "   " .. U.format_bytes(r.size)
    local rf = G.fit(T.f.bodyb, right, 180)
    G.text(rf, right, T.W - 26 - rf:getWidth(right), y + 12 + math.floor((T.base_font(T.f.bodyb):getHeight() - rf:getHeight()) / 2), T.c.text)
  end
  if #self.list > VISIBLE then
    G.text(T.f.small, (self.scroll + 1) .. "-" .. math.min(#self.list, self.scroll + VISIBLE) .. " / " .. #self.list,
      0, TOP + VISIBLE * RH + 2, T.c.faint, "center", T.W)
  end
  local hints = { { "dpad", L("Navegar") } }
  if #self.list > 0 then hints[#hints + 1] = { "a", L("Detalhes") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

local function details(r)
  local body = L("Arquivo: ") .. r.name .. L("\nPasta: ") .. Rec.DIR
    .. L("\nData: ") .. Clock.datetime(r.mtime, true)
    .. L("\nDuração: ") .. Rec.format_dur(r.dur) .. L("\nTamanho: ") .. U.format_bytes(r.size)
    .. (r.fps and (L("\nQuadros por segundo: ") .. r.fps) or "")
  if r.kind == "mp4" then
    body = body .. L("\n\nPara assistir, copie o arquivo para o computador ou celular pelo FTP do hub.")
  else
    body = body .. L("\n\nCopie o arquivo pelo FTP do hub e abra a página converter_gravacao.html (na mesma pasta) no Firefox ou Chromium do PC para assistir ou converter em vídeo WebM.")
  end
  App.show_dialog({ title = L("Detalhes da gravação"), kind = "info", body = body })
end

function S:action(act)
  local n = #self.list
  if act == "b" then App.pop(); return end
  if n == 0 then return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "a" then details(self.list[self.sel]) end
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
end

return S
