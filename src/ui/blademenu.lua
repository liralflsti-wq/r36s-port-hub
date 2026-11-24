-- =============================================================================
--  Tela inicial em RODA DE TINTA (layout "blade": Moonlight Blade Edition)
--  Arte original do hub: um circulo de pincel (enso) com as opcoes girando em
--  volta como selos; a escolhida fica no lado direito da roda, maior, com
--  brilho vermelho, e aparece grande no centro do circulo. A direita, um
--  pergaminho pendurado com o resumo real e a descricao.
--    cima/baixo (ou esquerda/direita): girar | A: abrir | B: sair/energia
--    SELECT: atualizar o hub (versao nova)
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local C = require("config")
local U = require("lib.util")
local Catalog = require("core.catalog")
local Icons = require("ui.icons")
local CH = require("ui.channels")
local IV = require("ui.inkview")
local TV = require("ui.themeviews")
local lg = love.graphics

local BM = {}

local DESC = {
  store = L("Ports de jogos, BIOS do sistema e utilitários: veja, baixe e instale."),
  library = L("Jogos dos emuladores do console, lidos do EmulationStation, com as capas do gamelist."),
  categories = L("Todos os ports organizados por gênero e por tipo de ferramenta."),
  installed = L("Os ports instalados no console: abrir, atualizar ou desinstalar."),
  favorites = L("Os ports que você marcou como favoritos (SELECT na lista)."),
  downloads = L("Fila, progresso, velocidade e histórico dos downloads. Também abre com START."),
  settings = L("Aparência, rede, FTP, armazenamento, bateria, controles e muito mais."),
  about = L("Créditos, avisos, licenças e o canal do projeto."),
}

local CX, CY, R = 196, 262, 140      -- centro e raio da roda
local RED, INK, PAPER = IV.RED, IV.INK, IV.PAPER

local function anim() return App.animations() end

function BM.update(S, self, dt)
  self.ch_sel = self.ch_sel or 1
  self.bm_pos = self.bm_pos or self.ch_sel
  if anim() then
    -- gira pelo caminho mais curto (a roda da a volta)
    local n = #(self.ch_items or CH.items())
    local d = self.ch_sel - self.bm_pos
    if d > n / 2 then self.bm_pos = self.bm_pos + n elseif d < -n / 2 then self.bm_pos = self.bm_pos - n end
    d = self.ch_sel - self.bm_pos
    self.bm_pos = self.bm_pos + d * math.min(1, dt * 10)
    if math.abs(self.ch_sel - self.bm_pos) < 0.01 then self.bm_pos = self.ch_sel end
  else
    self.bm_pos = self.ch_sel
  end
end

local function draw_top(S, self)
  local lw = G.logo(14, 8, "menu")
  -- relogio, Wi-Fi e bateria (direita)
  local Clock = require("core.clock")
  local s = Clock.time()
  local cf = T.base_font(T.f.bodyb)
  local bw = S.draw_battery(self, 15, T.W - 22)
  local wx = T.W - 22 - bw - 26
  local _, wc, off = S.wifi_state()
  S.wifi_icon(wx, 14, wc, off)
  local sw = cf:getWidth(s)
  local cx = wx - 14 - sw
  lg.setColor(0, 0, 0, 0.7)
  lg.rectangle("fill", cx - 10, 10, sw + 20, 28, 3, 3)
  lg.setColor(RED[1], RED[2], RED[3], 1)
  lg.rectangle("fill", cx - 10, 36, sw + 20, 2)
  G.text(cf, s, cx, 15, T.c.text)
  G.text(T.f.pix8, C.OS_MODE and (C.OS_NAME .. " " .. C.OS_VERSION) or C.VERSION, 14 + 4, 8 + 74 + 2, T.c.faint)
  return lw
end

function BM.draw(S, self)
  self.ch_sel = self.ch_sel or 1
  self.ch_items = self.ch_items or CH.items()
  local items = self.ch_items
  local n = #items
  draw_top(S, self)
  local pos = self.bm_pos or self.ch_sel
  local step = math.pi * 2 / n
  -- circulo de pincel (sombra vermelha + tinta) girando devagar
  local spin = anim() and App.t * 0.05 or 0
  IV.enso(CX + 3, CY + 3, R - 30, 30, RED, 0.55, -0.6 + spin)
  IV.enso(CX, CY, R - 30, 26, INK, 0.95, -0.6 + spin)
  -- opcao escolhida grande no centro
  local cur = items[self.ch_sel]
  local pulse = anim() and App.pulse(0.85, 0.15, 2.4) or 1
  for g = 6, 1, -1 do
    lg.setColor(RED[1], RED[2], RED[3], 0.05 * pulse)
    lg.circle("fill", CX, CY, 50 + g * 5)
  end
  lg.setColor(0.04, 0.03, 0.05, 0.92)
  lg.circle("fill", CX, CY, 56)
  Icons.draw(cur.icon, CX - 30, CY - 40, PAPER, 60 / 24)
  local lab = U.upper(I18N.tr(cur.label))
  local lf = G.fit(T.f.pix8, lab, 104)
  G.text(lf, lab, CX - lf:getWidth(lab) / 2, CY + 26, RED)
  -- selos em volta: a escolhida fica no lado direito (angulo 0)
  local order = {}
  for i = 1, n do order[#order + 1] = i end
  local function ang(i) return (i - pos) * step end
  table.sort(order, function(a, b) return math.cos(ang(a)) < math.cos(ang(b)) end)
  for _, i in ipairs(order) do
    local it = items[i]
    local a = ang(i)
    local x, y = CX + math.cos(a) * R, CY + math.sin(a) * R
    local front = (math.cos(a) + 1) / 2          -- 1 no lado direito
    local on = i == self.ch_sel
    local r = on and 24 or (13 + 5 * front)
    if on then
      for g = 5, 1, -1 do
        lg.setColor(RED[1], RED[2], RED[3], 0.10 * pulse)
        lg.circle("fill", x, y, r + g * 3.5)
      end
    end
    lg.setColor(0, 0, 0, 0.5)
    lg.circle("fill", x + 2, y + 3, r + 2)
    if on then lg.setColor(RED[1], RED[2], RED[3], 1) else lg.setColor(PAPER[1], PAPER[2], PAPER[3], 0.55 + 0.45 * front) end
    lg.circle("fill", x, y, r + 2)
    lg.setColor(INK[1], INK[2], INK[3], 1)
    lg.circle("fill", x, y, r - 1)
    local isz = r * 1.2
    Icons.draw(it.icon, x - isz / 2, y - isz / 2, on and PAPER or { 0.85, 0.82, 0.78 }, isz / 24)
  end
  require("ui.skyfx").focus = { CX + R, CY }
  require("ui.skyfx").sparks(CX + R - 30, CY - 20, 60, 40)

  -- pergaminho pendurado (direita): resumo + descricao
  local px, py, pw, ph = 380, 52, T.W - 380 - 14, T.H - 52 - 44
  -- rolos em cima e embaixo
  local function roller(ry)
    lg.setColor(0.25, 0.12, 0.06, 1)
    lg.rectangle("fill", px - 8, ry - 6, pw + 16, 12, 5, 5)
    lg.setColor(0.45, 0.24, 0.12, 1)
    lg.rectangle("fill", px - 6, ry - 3, pw + 12, 4, 2, 2)
    lg.setColor(INK[1], INK[2], INK[3], 1)
    lg.rectangle("fill", px - 12, ry - 7, 6, 14, 2, 2)
    lg.rectangle("fill", px + pw + 6, ry - 7, 6, 14, 2, 2)
  end
  IV.paper(px, py + 4, pw, ph - 8, false)
  roller(py + 4)
  roller(py + ph - 4)
  -- faixa vermelha lateral com o nome em pe (como num pergaminho)
  lg.setColor(RED[1], RED[2], RED[3], 0.9)
  lg.rectangle("fill", px + pw - 30, py + 16, 20, ph - 32)
  lg.push()
  local vs = U.upper(I18N.tr(cur.label))
  local vf = G.fit(T.f.pix8, vs, ph - 44)
  lg.translate(px + pw - 20 + vf:getHeight() / 2, py + 22)
  lg.rotate(math.pi / 2)
  G.text(vf, vs, 0, 0, PAPER)
  lg.pop()
  local ix, iw = px + 14, pw - 52
  local name = I18N.tr(cur.label)
  IV.stamp(ix, py + 20, 30, name:match("^[%z\1-\127\194-\244][\128-\191]*") or "")
  local nf, nl, nlh = G.fit_lines(T.f.h2, name, iw - 38, 2 * T.f.h2:getHeight(), true)
  local ny = (#nl == 1) and (py + 35 - nlh / 2) or (py + 18)
  for k, l in ipairs(nl) do G.text(nf, l, ix + 38, ny + (k - 1) * nlh, INK) end
  local by = math.max(py + 60, ny + #nl * nlh + 4)
  lg.setColor(RED[1], RED[2], RED[3], 0.85)
  for i = 0, 30 do
    local t = i / 30
    lg.circle("fill", ix + t * iw, by + math.sin(t * 3) * 1.2, 2.2 * (1 - t * 0.7))
  end
  local y = by + 12
  local sum = I18N.tr(CH.summary(cur.id))
  local sf = T.f.small
  local sw = math.min(iw, sf:getWidth(sum) + 16)
  lg.setColor(INK[1], INK[2], INK[3], 0.92)
  lg.rectangle("fill", ix, y, sw, 20, 3, 3)
  G.text_fit(sf, sum, ix + 8, y + 10 - sf:getHeight() / 2, sw - 16, PAPER)
  y = y + 30
  if cur.id == "store" or cur.id == "categories" then
    G.text_fit(sf, Catalog.source_label(), ix, y, iw, Catalog.source == "online" and { 0.10, 0.45, 0.20 } or { 0.65, 0.30, 0.05 })
    y = y + 18
  end
  if App.free then
    G.text_fit(sf, U.format_bytes(App.free) .. I18N.tr(L(" livres")), ix, y, iw, { 0.35, 0.28, 0.22 })
    y = y + 18
  end
  y = y + 6
  local d = cur.id == "exit" and (C.OS_MODE and L("Desligar ou reiniciar o console.") or L("Fecha o hub e volta ao EmulationStation.")) or DESC[cur.id] or ""
  local f, ls = G.fit_lines(T.f.body, d, iw, py + ph - 56 - y, true)
  local lh = G.step(f, 18)
  for _, l in ipairs(ls) do G.text(f, l, ix, y, { 0.18, 0.14, 0.12 }); y = y + lh end
  -- "A Abrir" no pe do pergaminho
  G.button_icon("a", ix, py + ph - 44)
  G.text(T.f.bodyb, L("Abrir"), ix + 22, py + ph - 45, INK)

  local hints = { { "dpad", L("Girar") }, { "a", L("Abrir") }, { "b", C.OS_MODE and L("Energia") or L("Sair") } }
  if require("core.updnotice").pending() then hints[#hints + 1] = { "select", L("Atualizar") } end
  G.hints(hints)
end

function BM.action(S, self, act)
  self.ch_sel = self.ch_sel or 1
  local n = #(self.ch_items or CH.items())
  if act == "up" or act == "left" then self.ch_sel = (self.ch_sel - 2) % n + 1
  elseif act == "down" or act == "right" then self.ch_sel = self.ch_sel % n + 1
  elseif act == "a" then S.open(self.ch_items[self.ch_sel].id)
  elseif act == "b" then
    if require("core.prefs").get("exit_mode") == "quit" and not C.OS_MODE then App.quit() else S.exit_dialog() end
  elseif act == "select" and require("core.updnotice").pending() then App.push("update")
  end
end

return BM
