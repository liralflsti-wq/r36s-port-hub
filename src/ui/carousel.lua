-- =============================================================================
--  Tela inicial em CARROSSEL (layout "carousel": Pastel Pop Edition)
--  Inspirada nos menus do 3DS/Wii U: uma fileira horizontal de cartoes com
--  borda colorida; o selecionado "salta" e fica maior. Embaixo, um balao com
--  o nome, o resumo real e a descricao do canal (na Central, a capa do
--  destaque). Mesmos canais e acoes da grade de canais (ui/channels.lua).
--    esquerda/direita: navegar | A: abrir | B: sair/energia
--    SELECT: atualizar o hub (versao nova). Sem EM DESTAQUE nesta tela.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Catalog = require("core.catalog")
local Icons = require("ui.icons")
local CH = require("ui.channels")
local lg = love.graphics

local CR = {}

-- cor de cada canal (borda e icone), em tons pastel
local TINT = {
  store = "#8b5cf6", library = "#f97316", categories = "#ec4899", installed = "#06b6d4",
  favorites = "#eab308", downloads = "#22c55e", settings = "#6366f1", about = "#0ea5e9", exit = "#f43f5e",
}
local tint_cache = {}
local function tint(id)
  local c = tint_cache[id]
  if not c then c = T.parse_hex(TINT[id] or "#8b5cf6") or T.c.accent; tint_cache[id] = c end
  return c
end

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

local TS, TB = 104, 140          -- tamanho do cartao normal e do selecionado
local GAP = 14
local ROW_Y = 64                  -- topo da fileira (o selecionado comeca aqui)
local X0 = 30                     -- onde o cartao selecionado tende a ficar

local ENTER = 0.35
function CR.update(S, self, dt)
  if self.ch_t then
    self.ch_t = self.ch_t + dt
    if self.ch_t > ENTER + 0.3 then self.ch_t = nil end
  end
  -- rolagem suave da fileira
  local target = self.cr_target or 0
  self.cr_scroll = self.cr_scroll or target
  if App.animations() then
    self.cr_scroll = self.cr_scroll + (target - self.cr_scroll) * math.min(1, dt * 12)
    if math.abs(self.cr_scroll - target) < 0.5 then self.cr_scroll = target end
  else
    self.cr_scroll = target
  end
end

-- x de cada cartao (sem rolagem): o selecionado ocupa TB, os outros TS
local function layout(self, n)
  local xs, x = {}, 0
  for i = 1, n do
    xs[i] = x
    x = x + (i == self.ch_sel and TB or TS) + GAP
  end
  return xs, x - GAP
end

local function draw_top(S, self)
  -- pilula do topo: logo, tema e versao | data, hora, Wi-Fi e bateria
  G.rect(8, 6, T.W - 16, 40, T.c.shadow, 20)
  G.rect(8, 4, T.W - 16, 40, T.c.bg1, 20)
  G.frame(8, 4, T.W - 16, 40, T.c.line, 20, 1)
  local lw = G.logo(20, 8, "header")
  local Themes = require("core.themes")
  local th = Themes.by_id and Themes.by_id[Themes.current]
  local name = th and U.upper(th.name) or ""
  local tx = 20 + lw + 12
  G.text(T.f.pix8, name, tx, 12, T.c.accent)
  G.text(T.f.pix8, C.OS_MODE and (C.OS_NAME .. " " .. C.OS_VERSION) or C.VERSION, tx, 26, T.c.faint)
  -- relogio | data
  local Clock = require("core.clock")
  local clock = Clock.time()
  local wd = ({ L("dom"), L("seg"), L("ter"), L("qua"), L("qui"), L("sex"), L("sáb") })[Clock.wday()]
  local datestr = I18N.tr(wd) .. ", " .. Clock.date(nil, true)
  local cf = T.base_font(T.f.bodyb)
  local s = clock .. "  |  " .. datestr
  local sw = cf:getWidth(s)
  -- bateria e Wi-Fi dentro da pilula (direita)
  local bw = S.draw_battery(self, 15, T.W - 22)
  local wx = T.W - 22 - bw - 26
  local _, wc, off = S.wifi_state()
  S.wifi_icon(wx, 14, wc, off)
  local cx = wx - 12 - sw
  G.rect(cx - 10, 10, sw + 20, 28, T.c.bg0, 14)
  G.text(cf, s, cx, 15, T.c.text)
  -- aviso de versao nova
  S.draw_update_notice(self, cx - 18, tx + math.max(T.f.pix8:getWidth(I18N.tr(name)), 80) + 12, 14)
end

local function draw_tile(self, i, it, x, y, size)
  local on = i == self.ch_sel
  local k = G.focus_k("cr" .. i, on)
  local tc = tint(it.id)
  local pal, cx, cy, cw, chh = G.card(x, y, size, size, on, k, 14, tc)
  -- fundo levemente tingido com a cor do canal
  G.rect(cx + 4, cy + 4, cw - 8, chh - 8, tc, 11, on and 0.10 or 0.06)
  local isz = size * 0.46
  Icons.draw(it.icon, cx + (cw - isz) / 2, cy + (chh - isz) / 2 - 2, tc, isz / 24)
  -- selo de downloads em andamento
  if it.id == "downloads" then
    local D = require("core.downloads")
    local n = (D.active() and 1 or 0) + D.waiting_count()
    if n > 0 then
      local s = tostring(n)
      local bw = T.f.pix8:getWidth(s) + 12
      G.rect(cx + cw - bw - 6, cy + 6, bw, 16, tc, 8)
      G.text(T.f.pix8, s, cx + cw - bw, cy + 10, T.c.bg1)
    end
  end
end

local function draw_info(S, self, it)
  -- balao de informacoes do canal selecionado
  local x, y, w, h = 18, 238, T.W - 36, 186
  G.rect(x + 2, y + 5, w, h, T.c.shadow, 20)
  G.rect(x, y, w, h, T.c.bg1, 20)
  G.frame(x, y, w, h, T.c.line, 20, 1)
  local tc = tint(it.id)
  local rw = 0   -- Pastel Pop: a tela inicial nao mostra o EM DESTAQUE
  local ix, iw = x + 22, w - 44 - rw
  -- nome + pilula com o resumo real
  local nf = G.fit(T.f.h1, it.label, iw)
  G.text(nf, it.label, ix, y + 16, T.c.text)
  local sub = I18N.tr(CH.summary(it.id))
  local sf = T.f.small
  local pw = math.min(iw, sf:getWidth(sub) + 24)
  local py = y + 16 + nf:getHeight() + 8
  G.rect(ix, py, pw, 22, T.c.bg0, 11)
  G.frame(ix, py, pw, 22, tc, 11, 1, 0.6)
  G.text_fit(sf, sub, ix + 12, py + 11 - sf:getHeight() / 2, pw - 24, T.c.dim)
  -- descricao
  local d = it.id == "exit" and (C.OS_MODE and L("Desligar ou reiniciar o console.") or L("Fecha o hub e volta ao EmulationStation.")) or DESC[it.id] or ""
  local dy = py + 32
  local f, ls = G.fit_lines(T.f.body, d, iw, y + h - 44 - dy, true)
  local lh = G.step(f, 18)
  for _, l in ipairs(ls) do G.text(f, l, ix, dy, T.c.dim); dy = dy + lh end
  -- botao "A Abrir" em pilula
  local bl = I18N.tr(L("Abrir"))
  local bx, by = ix, y + h - 36
  local bwid = T.f.bodyb:getWidth(bl) + 44
  G.rect(bx, by, bwid, 26, tc, 13, 0.14)
  G.frame(bx, by, bwid, 26, tc, 13, 1)
  G.button_icon("a", bx + 8, by + 5)
  G.text(T.f.bodyb, bl, bx + 30, by + 13 - T.f.bodyb:getHeight() / 2, T.c.text)
  -- estado do catalogo (dados reais) ao lado do botao
  local online = Catalog.source == "online"
  local dot = Catalog.remote_state == "loading" and T.c.yellow or (online and T.c.green or T.c.orange)
  local st = Catalog.remote_state == "loading" and L("Sincronizando catálogo...") or Catalog.source_label()
  local free = App.free and (U.format_bytes(App.free) .. I18N.tr(L(" livres"))) or ""
  local line = I18N.tr(st) .. (free ~= "" and ("  •  " .. free) or "")
  G.color(dot); lg.circle("fill", bx + bwid + 18, by + 13, 4)
  G.text_fit(T.f.small, line, bx + bwid + 28, by + 13 - T.f.small:getHeight() / 2, x + w - 22 - rw - (bx + bwid + 28), T.c.faint)
end

function CR.draw(S, self)
  self.ch_sel = self.ch_sel or 1
  self.ch_items = self.ch_items or CH.items()
  local items = self.ch_items
  local n = #items
  draw_top(S, self)
  local xs, total = layout(self, n)
  -- rolagem: o cartao anterior ao selecionado fica parcialmente visivel
  local want = xs[self.ch_sel] - X0 - (self.ch_sel > 1 and (TS * 0.35 + GAP) or 0)
  want = math.max(-X0 + 18, math.min(want, total - (T.W - 36)))
  if self.ch_sel == 1 then want = -X0 + 18 end
  self.cr_target = want
  local scroll = self.cr_scroll or want
  local enter = (self.ch_t and App.animations()) and (1 - math.min(1, self.ch_t / ENTER)) ^ 3 or 0
  G.clip(4, 48, T.W - 8, 186)
  for i, it in ipairs(items) do
    local size = i == self.ch_sel and TB or TS
    local x = xs[i] - scroll
    local y = ROW_Y + (TB - size) / 2 + 8 + enter * (24 + i * 6)
    if x + size > -10 and x < T.W + 10 then draw_tile(self, i, it, x, y, size) end
  end
  G.unclip()
  -- pontos de pagina
  local dw = n * 12
  for i = 1, n do
    local on = i == self.ch_sel
    G.color(on and tint(items[i].id) or T.c.line)
    lg.circle("fill", T.W / 2 - dw / 2 + (i - 1) * 12 + 6, 228, on and 4 or 3)
  end
  draw_info(S, self, items[self.ch_sel])
  local hints = { { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "b", C.OS_MODE and L("Energia") or L("Sair") } }
  if require("core.updnotice").pending() then hints[#hints + 1] = { "select", L("Atualizar") } end
  G.hints(hints)
end

function CR.action(S, self, act)
  self.ch_sel = self.ch_sel or 1
  local n = #(self.ch_items or CH.items())
  if act == "left" or act == "up" then self.ch_sel = (self.ch_sel - 2) % n + 1
  elseif act == "right" or act == "down" then self.ch_sel = self.ch_sel % n + 1
  elseif act == "a" then S.open(self.ch_items[self.ch_sel].id)
  elseif act == "b" then
    if require("core.prefs").get("exit_mode") == "quit" and not C.OS_MODE then App.quit() else S.exit_dialog() end
  elseif act == "select" and require("core.updnotice").pending() then App.push("update")
  end
end

return CR
