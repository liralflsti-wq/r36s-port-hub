-- =============================================================================
--  Tela inicial em BARRAS (layout "sky": Sky Warriors; layout "blade": Moonlight
--  Blade, com as opcoes em laminas de espada)
--  Clima de menu de jogo de luta de anime (arte original do hub): logo no alto,
--  opcoes em barras inclinadas azul-turquesa a esquerda (a escolhida fica
--  laranja com aura de energia) e um painel com moldura dourada a direita
--  com o resumo real e a descricao da opcao. Mesmos itens e acoes da grade
--  de canais (ui/channels.lua).
--    cima/baixo: navegar | A: abrir | B: sair/energia | SELECT: atualizar o hub
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local C = require("config")
local Catalog = require("core.catalog")
local CH = require("ui.channels")
local TV = require("ui.themeviews")
local lg = love.graphics

local SK = {}

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

local COLORS = {
  store = "#ff9a1f", library = "#36d3ea", categories = "#ff6fae", installed = "#4be38a",
  favorites = "#ffd23f", downloads = "#7fb2ff", settings = "#b48cff", about = "#5ee0ff", exit = "#ff4d6a",
}
local cache = {}
local function tint(id)
  local c = cache[id]
  if not c then c = T.parse_hex(COLORS[id] or "#36d3ea") or T.c.accent2; cache[id] = c end
  return c
end

function SK.update(S, self, dt) end

--- nome curto do tema ativo (sem "Edition")
local function theme_label()
  local Th = require("core.themes")
  local th = Th.by_id and Th.by_id[Th.current]
  local n = th and th.name or ""
  return (n:gsub("%s*[Ee]dition$", "")):upper()
end

local function draw_top(S, self)
  -- logo do hub num selo com a cor do tema + nome do tema e versao
  local P = TV.pal()
  local gold = P.frame
  lg.setColor(P.panel[1], P.panel[2], P.panel[3], 0.9)
  lg.rectangle("fill", 10, 6, 210, 40, 20, 20)
  G.frame(10, 6, 210, 40, gold, 20, 2)
  local lw = G.logo(18, 9, "header")
  TV.outline_text(T.f.pix8, theme_label(), 18 + lw + 10, 13, gold)
  G.text(T.f.pix8, C.OS_MODE and (C.OS_NAME .. " " .. C.OS_VERSION) or C.VERSION, 18 + lw + 10, 27, { 0.85, 0.93, 1 })
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
  local P2 = TV.pal()
  lg.setColor(P2.panel[1], P2.panel[2], P2.panel[3], 0.85)
  lg.rectangle("fill", cx - 10, 10, sw + 20, 28, 14, 14)
  TV.outline_text(cf, s, cx, 15, { 1, 1, 1 })
end

function SK.draw(S, self)
  self.ch_sel = self.ch_sel or 1
  self.ch_items = self.ch_items or CH.items()
  local items = self.ch_items
  draw_top(S, self)
  TV.draw_bars(self, { top = 46, n = #items, sel = self.ch_sel, w = 300,
    item = function(i) local it = items[i]; return { icon = it.icon, color = tint(it.id), label = it.label } end })
  local it = items[self.ch_sel]
  local d = it.id == "exit" and (C.OS_MODE and L("Desligar ou reiniciar o console.") or L("Fecha o hub e volta ao EmulationStation.")) or DESC[it.id] or ""
  local rows = {}
  if it.id == "store" or it.id == "categories" then
    local online = Catalog.source == "online"
    rows[#rows + 1] = { L("Catálogo"), Catalog.source_label(), online and T.c.green or T.c.orange }
  end
  if App.free then rows[#rows + 1] = { L("Espaço livre"), require("lib.util").format_bytes(App.free) } end
  TV.draw_detail({ x = 330, w = T.W - 330 - 12, icon = it.icon, color = tint(it.id), name = it.label,
    pills = { { CH.summary(it.id), tint(it.id) } }, rows = rows, text = I18N.tr(d) })
  local hints = { { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "b", C.OS_MODE and L("Energia") or L("Sair") } }
  if require("core.updnotice").pending() then hints[#hints + 1] = { "select", L("Atualizar") } end
  G.hints(hints)
end

function SK.action(S, self, act)
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

return SK
