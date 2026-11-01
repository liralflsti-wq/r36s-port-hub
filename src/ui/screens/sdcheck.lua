-- =============================================================================
--  Manutencao > Verificador do cartao SD
--  Identificacao (dados informados pelo cartao) + pistas + teste de velocidade
--  leve (arquivo de 64 MB, apagado no fim). Nao faz teste completo de
--  capacidade. A testa a velocidade | L1/R1 trocam de cartao | B volta
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local SD = require("core.sdcard")
local lg = love.graphics

local S = {}
local TEST_MB = 64
local HINT_COLOR = { ok = "green", warn = "yellow", info = "dim" }

function S:enter()
  self.cards = SD.list()
  self.ports_dev = SD.ports_device()
  self.idx = 1
  for i, c in ipairs(self.cards) do if c.dev == self.ports_dev then self.idx = i end end
  self.state = "idle"
end

function S:leave() end

function S:start_test()
  local free = U.free_space(C.TMP_DIR)
  if free and free < (TEST_MB + 32) * 1024 * 1024 then
    App.toast(L("Espaço livre insuficiente para o teste (precisa de ") .. (TEST_MB + 32) .. L(" MB)."), "warn")
    return
  end
  self.out = love.thread.getChannel("hub_sdspeed_out")
  self.out:clear()
  self.result, self.phase = nil, "write"
  self.thread = love.thread.newThread("threads/sdspeed_thread.lua")
  self.thread:start({ lang = require("lib.i18n").lang, out = "hub_sdspeed_out", dir = C.TMP_DIR, mb = TEST_MB })
  self.state = "testing"
end

function S:update()
  if self.state ~= "testing" then return end
  local e = self.thread:getError()
  if e then U.log("sdspeed:", e); self.state = "done"; self.result = { ok = false, error = L("Erro interno no teste.") }; return end
  local m = self.out:pop()
  while m do
    if m.t == "phase" then self.phase = m.phase
    elseif m.t == "done" then self.result = m; self.state = "done" end
    m = self.out:pop()
  end
end

local function row(k, v, x, y, w, c)
  G.text(T.f.small, k, x, y + 1, T.c.faint)
  G.text_fit(T.f.bodyb, v or L("não informado"), x + 118, y, w - 118, v and (c or T.c.text) or T.c.faint)
end

function S:draw()
  G.header(L("Verificador do cartão SD"), #self.cards > 1 and (self.idx .. L(" de ") .. #self.cards .. L(" cartões")) or "")
  local c = self.cards[self.idx]
  local x, w = 12, T.W - 24

  -- identificacao
  G.panel(x, 50, w, 168, { bg = T.c.bg1 })
  G.text(T.f.pix8, L("IDENTIFICAÇÃO"), x + 14, 60, T.c.accent2)
  if not c then
    G.text(T.f.body, L("Nenhum cartão SD (mmcblk) foi encontrado pelo sistema."), x + 14, 90, T.c.faint)
  else
    local is_ports = c.dev == self.ports_dev
    G.text(T.f.small, c.dev .. (is_ports and L("  •  cartão dos ports") or ""), x + w - 14 - T.f.small:getWidth(c.dev .. (is_ports and L("  •  cartão dos ports") or "")), 58, T.c.dim)
    local hw = (w - 28) / 2
    local lx, rx, y = x + 14, x + 14 + hw + 10, 80
    row(L("Fabricante"), c.maker or (c.manfid and string.format(L("desconhecido (0x%02X)"), c.manfid)) or nil, lx, y, hw, c.maker and T.c.text or T.c.yellow)
    row(L("Modelo"), c.name, lx, y + 22, hw)
    row(L("Capacidade"), c.bytes and (U.format_bytes(c.bytes) .. L("  (informada)")) or nil, lx, y + 44, hw)
    row(L("Tipo"), c.type, lx, y + 66, hw)
    row(L("Classe"), c.class and (c.class.none and L("nenhuma declarada") or c.class.text)
      or (c.ssr == nil and L("não informada pelo sistema") or nil), lx, y + 88, hw,
      c.class and c.class.none and T.c.yellow or nil)
    row(L("Fabricação"), c.date, rx, y, hw)
    row("OEM", c.oem_txt and (c.oem_txt .. string.format("  (0x%04X)", c.oemid)) or (c.oemid and string.format("0x%04X", c.oemid)) or nil, rx, y + 22, hw)
    row(L("Nº de série"), c.serial, rx, y + 44, hw)
    row(L("Revisão"), (c.hwrev or c.fwrev) and (L("hw ") .. (c.hwrev or "?") .. L("  •  fw ") .. (c.fwrev or "?")) or nil, rx, y + 66, hw)
    G.text_fit(T.f.small, L("A capacidade informada não prova a capacidade real: cartões falsos mentem justamente nesse dado."), x + 14, 196, w - 28, T.c.faint)
  end

  -- pistas
  G.panel(x, 224, w, 100, { bg = T.c.bg1 })
  G.text(T.f.pix8, L("PISTAS"), x + 14, 234, T.c.accent2)
  local y = 250
  if c then
    for i, h in ipairs(c.hints) do
      if i > 4 then break end
      local col = T.c[HINT_COLOR[h.level]]
      G.color(col); lg.circle("fill", x + 20, y + 7, 3)
      G.text_fit(T.f.small, h.text, x + 30, y, w - 44, h.level == "info" and T.c.dim or T.c.text)
      y = y + 17
    end
  end

  -- velocidade
  G.panel(x, 330, w, 106, { bg = T.c.bg1 })
  G.text(T.f.pix8, L("VELOCIDADE (CARTÃO DOS PORTS)"), x + 14, 340, T.c.accent2)
  if self.state == "idle" then
    G.text(T.f.body, L("Pressione A para medir: grava e lê um arquivo de ") .. TEST_MB .. L(" MB (alguns segundos)\ne apaga no fim. Seus arquivos não são tocados."), x + 14, 360, T.c.dim, "left", w - 28)
  elseif self.state == "testing" then
    G.text(T.f.body, self.phase == "read" and L("Medindo a leitura...") or L("Medindo a gravação..."), x + 14, 362, T.c.yellow)
    G.progress_busy(x + 14, 392, w - 28, 8, App.t, T.c.yellow)
  else
    local r = self.result or {}
    if not r.ok then
      G.text(T.f.body, r.error or L("Falha no teste."), x + 14, 362, T.c.red)
    else
      G.text(T.f.small, L("Gravação"), x + 14, 362, T.c.faint)
      G.text(T.f.h2, U.format_speed(r.write), x + 100, 356, T.c.text)
      G.text(T.f.small, L("Leitura"), x + 320, 362, T.c.faint)
      if r.read then
        G.text(T.f.h2, U.format_speed(r.read), x + 390, 356, T.c.text)
      else
        G.text(T.f.small, L("indisponível (sem como evitar o cache do sistema)"), x + 390, 362, T.c.faint, "left", w - 400)
      end
      G.text(T.f.small, L("Arquivo de ") .. r.mb .. L(" MB") .. (r.read_method and (L("  •  leitura: ") .. r.read_method) or "")
        .. L(". O resultado inclui o limite do leitor de cartão do console."), x + 14, 392, T.c.faint, "left", w - 28)
      -- gravacao abaixo do minimo da classe declarada: pista de cartao falso
      local cls = c and c.class
      if cls and cls.min_mb and cls.min_mb > 0 and r.write and r.write < cls.min_mb * 1000 * 1000 then
        G.text_fit(T.f.small, string.format(L("Gravação abaixo do mínimo da classe declarada (%s exige %d MB/s): pode ser cartão falso ou limite do leitor."),
          cls.text, cls.min_mb), x + 14, 414, w - 28, T.c.yellow)
      end
    end
  end
  local hints = {}
  if self.state ~= "testing" then hints[#hints + 1] = { "a", self.state == "done" and L("Testar de novo") or L("Testar velocidade") } end
  if #self.cards > 1 then hints[#hints + 1] = { "l1", L("Cartão") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  if self.state == "testing" then return end   -- o teste dura poucos segundos
  if act == "b" then App.pop()
  elseif act == "a" then self:start_test()
  elseif (act == "l1" or act == "r1") and #self.cards > 1 then
    self.idx = (self.idx % #self.cards) + 1
  end
end

return S
