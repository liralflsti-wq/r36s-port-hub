-- Biblioteca de jogos: sistemas do console (es_systems.cfg) com a quantidade
-- de jogos encontrados. A abre o sistema; X escolhe o emulador/core padrao.
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Lib = require("core.library")
local Icons = require("ui.icons")
local CV = require("ui.coverview")
local SH = require("ui.shelf")

local S = {}

local function njogos(n) return string.format(I18N.tr(n == 1 and L("%d jogo") or L("%d jogos")), n) end

local COLS, CW, CH, GAP = 3, 196, 88, 10
local X0, Y0 = 16, 52
local VIS_ROWS = 4

function S:enter(p)
  self.sel, self.top = 1, 0
  self.focus, self.gsel, self.gsels, self.games = "sys", 1, {}, nil   -- prateleiras (Pastel Pop)
  self.want = p and p.system
  if not Lib.scanned and Lib.state ~= "scanning" then Lib.scan(function() self:rebuild() end) end
  self:rebuild()
end

function S:resume() self:rebuild() end

function S:rebuild()
  local items = {}
  if Lib.scanned then
    local favn, recn = 0, #Lib.recent()
    for _, s in ipairs(Lib.systems) do for _, g in ipairs(s.games) do if Lib.is_fav(g) then favn = favn + 1 end end end
    items[#items + 1] = { special = "recent", label = L("Recentes"), count = recn }
    items[#items + 1] = { special = "favs", label = L("Favoritos"), count = favn }
    for _, s in ipairs(Lib.with_games()) do items[#items + 1] = { sys = s } end
  end
  self.items = items
  -- volta de um jogo: abre direto o sistema de onde ele saiu
  if self.want and Lib.scanned then
    for i, it in ipairs(items) do
      if it.sys and it.sys.name == self.want then
        self.sel = i
        local want = self.want
        self.want = nil
        if CV.active() then
          -- prateleiras: fica no console, com o jogo que acabou de fechar escolhido
          self:load_games()
          local last = Lib.recent()[1]
          for gi, git in ipairs(self.games or {}) do if last and git.g.file == last.file then self.gsel = gi end end
          self.focus = "game"
          App.toast(L("Bem-vindo de volta!"), "info")
          return
        end
        App.push("library_games", { system = it.sys, from_return = want })
        return
      end
    end
    self.want = nil
  end
  self.sel = U.clamp(self.sel, 1, math.max(1, #items))
  if CV.active() then self:load_games() end
end

-- prateleiras: jogos do console escolhido (lembra o jogo escolhido de cada um)
local function item_key(it) return it and (it.special or it.sys.name) or "" end
function S:load_games()
  local it = self.items[self.sel]
  if not it then self.games = {}; return end
  self.games = SH.games_for(it)
  self.gsel = U.clamp((self.gsels or {})[item_key(it)] or 1, 1, math.max(1, #self.games))
end

function S:leave() SH.release() end

function S:update(dt)
  if Lib.scanned and not self.items[1] then self:rebuild() end
  if CV.active() and self.items[1] then
    if not self.games then self:load_games() end
    SH.update(self, dt or 0)
  end
end

function S:draw()
  local total = Lib.scanned and njogos(Lib.total_games()) or ""
  G.header(L("Biblioteca de jogos"), total)
  if Lib.state == "error" then
    G.text(T.f.body, Lib.error or L("Não foi possível ler os sistemas."), 40, 200, T.c.dim, "center", T.W - 80)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  if not Lib.scanned then
    G.text(T.f.body, L("Procurando jogos nas pastas de ROMs..."), 0, 210, T.c.dim, "center", T.W)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  if CV.active() and #self.items > 0 and Lib.total_games() > 0 then
    SH.draw(self)
    local hs
    if (self.focus or "sys") == "sys" then
      hs = { { "dpad", L("Navegar") }, { "a", L("Jogos") } }
      local it = self.items[self.sel]
      if it and it.sys and #it.sys.emulators > 0 then hs[#hs + 1] = { "x", L("Emulador padrão") } end
      hs[#hs + 1] = { "y", L("Procurar de novo") }
      hs[#hs + 1] = { "b", L("Voltar") }
    else
      local git = self.games and self.games[self.gsel]
      hs = { { "a", L("Jogar") } }
      if git and #git.sys.emulators > 0 then hs[#hs + 1] = { "x", L("Emulador") } end
      if git then hs[#hs + 1] = { "select", Lib.is_fav(git.g) and L("Desfavoritar") or L("Favoritar") } end
      hs[#hs + 1] = { "y", L("Info") }
      hs[#hs + 1] = { "b", L("Consoles") }
    end
    G.hints(hs)
    return
  end
  if #self.items <= 2 and Lib.total_games() == 0 then
    G.text(T.f.body, L("Nenhum jogo encontrado nas pastas de ROMs (/roms/<sistema>). Copie as ROMs pelo FTP e aperte Y para procurar de novo."),
      40, 190, T.c.dim, "center", T.W - 80)
  end
  local row = math.floor((self.sel - 1) / COLS)
  if row < self.top then self.top = row end
  if row >= self.top + VIS_ROWS then self.top = row - VIS_ROWS + 1 end
  for i, it in ipairs(self.items) do
    local r = math.floor((i - 1) / COLS) - self.top
    if r >= 0 and r < VIS_ROWS then
      local c = (i - 1) % COLS
      local x, y = X0 + c * (CW + GAP), Y0 + r * (CH + GAP)
      local on = i == self.sel
      G.rect(x, y, CW, CH, on and T.c.bg2 or T.c.bg1, 8)
      G.frame(x, y, CW, CH, on and T.c.accent or T.c.line, 8, on and 2 or 1)
      local title, sub, count, icon
      if it.special == "recent" then
        title, sub, count, icon = it.label, L("Últimos jogos abertos pelo hub"), it.count, "set_clock"
      elseif it.special == "favs" then
        title, sub, count, icon = it.label, L("Jogos marcados com SELECT"), it.count, "set_favorites"
      else
        local s = it.sys
        title = s.fullname
        local parts = {}
        if s.manufacturer and s.manufacturer ~= "" then parts[#parts + 1] = s.manufacturer end
        if s.release and s.release ~= "" and s.release ~= "unknown" then parts[#parts + 1] = s.release end
        sub = table.concat(parts, "  •  ")
        count, icon = #s.games, "testes_de_controles"
      end
      Icons.draw(icon, x + 12, y + 12, on and T.c.accent or T.c.dim, 0.9)
      G.text_fit(T.f.bodyb, title, x + 44, y + 12, CW - 54, on and T.c.text or T.c.dim)
      G.text_fit(T.f.small, sub, x + 12, y + 44, CW - 24, T.c.faint)
      local cs = njogos(count)
      G.text(T.f.small, cs, x + CW - 12 - T.f.small:getWidth(cs), y + CH - 22, on and T.c.accent or T.c.dim)
    end
  end
  local rows = math.ceil(#self.items / COLS)
  if rows > VIS_ROWS then
    G.text(T.f.small, self.sel .. "/" .. #self.items, T.W - 80, T.H - 46, T.c.faint, "right", 64)
  end
  local hs = { { "dpad", L("Navegar") }, { "a", L("Abrir") } }
  local it = self.items[self.sel]
  if it and it.sys and #it.sys.emulators > 0 then hs[#hs + 1] = { "x", L("Emulador padrão") } end
  hs[#hs + 1] = { "y", L("Procurar de novo") }
  hs[#hs + 1] = { "b", L("Voltar") }
  G.hints(hs)
end

--- lista de emulador/core para o sistema (ou para um jogo), numa tela propria
--- (alguns sistemas tem muitas opcoes)
function S.choose_emulator(sys, game)
  local cur_e, cur_c = Lib.choice(sys, game)
  local items = { { tag = L("PADRÃO"), tagc = T.c.accent2,
    text = game and L("Padrão do sistema") or L("Padrão (primeiro da lista)"),
    sub = L("Usa a escolha do sistema ou o primeiro emulador do es_systems.cfg") } }
  for _, o in ipairs(Lib.options(sys)) do
    local on = o.emulator == cur_e and o.core == cur_c
    items[#items + 1] = { tag = on and L("EM USO") or nil, tagc = T.c.green, text = o.emulator .. (o.core and (" / " .. o.core) or ""),
      sub = o.core and (L("Core: ") .. o.core) or L("Emulador próprio"), opt = o }
  end
  App.push("infolist", { title = game and L("Emulador deste jogo") or L("Emulador padrão"),
    sub = game and game.name or sys.fullname, items = items,
    keys = { { key = "a", label = L("Usar"), fn = function(scr, it)
      if not it then return end
      if it.opt then
        Lib.set_choice(sys, game, it.opt.emulator, it.opt.core)
        App.toast(L("Emulador: ") .. it.text, "ok")
      else
        Lib.set_choice(sys, game, nil)
        App.toast(L("Emulador: padrão."), "info")
      end
      App.pop()
    end } } })
end

--- informacoes do jogo (mesmo conteudo da tela de jogos)
function S.game_info(it)
  local emu, core = Lib.choice(it.sys, it.g)
  local body = {}
  if it.g.desc and it.g.desc ~= "" then body[#body + 1] = it.g.desc; body[#body + 1] = "" end
  body[#body + 1] = L("Arquivo: ") .. it.g.file
  if it.g.size then body[#body + 1] = L("Tamanho: ") .. U.format_bytes(it.g.size) end
  if it.g.releasedate and it.g.releasedate:match("^%d%d%d%d") then body[#body + 1] = L("Lançamento: ") .. it.g.releasedate:sub(1, 4) end
  if it.g.players and it.g.players ~= "" then body[#body + 1] = L("Jogadores: ") .. it.g.players end
  body[#body + 1] = L("Emulador: ") .. tostring(emu or "-") .. (core and (" / " .. core) or "")
  App.show_dialog({ title = it.g.name, kind = "info", body = table.concat(body, "\n") })
end

-- prateleiras (Pastel Pop): cima = consoles, baixo = jogos
function S:shelf_action(act)
  local n = #self.items
  if (self.focus or "sys") == "sys" then
    if act == "b" then App.pop()
    elseif act == "left" or act == "right" then
      local d = act == "left" and -1 or 1
      self.gsels[item_key(self.items[self.sel])] = self.gsel
      self.sel = U.clamp(self.sel + d, 1, n)
      self:load_games()
    elseif act == "l1" or act == "r1" then
      self.gsels[item_key(self.items[self.sel])] = self.gsel
      self.sel = U.clamp(self.sel + (act == "l1" and -4 or 4), 1, n)
      self:load_games()
    elseif (act == "down" or act == "a") then
      if #(self.games or {}) > 0 then self.focus = "game" end
    elseif act == "x" then
      local it = self.items[self.sel]
      if it.sys and #it.sys.emulators > 0 then S.choose_emulator(it.sys, nil) end
    elseif act == "y" then
      Lib.scanned = false
      Lib.systems = {}
      Lib.scan(function() self:rebuild() end)
      self.items, self.games = {}, nil
    end
    return
  end
  local list = self.games or {}
  local m = #list
  local it = list[self.gsel]
  if act == "b" or act == "up" then self.focus = "sys"; return end
  if m == 0 then self.focus = "sys"; return end
  if act == "left" then self.gsel = math.max(1, self.gsel - 1)
  elseif act == "right" then self.gsel = math.min(m, self.gsel + 1)
  elseif act == "l1" then self.gsel = math.max(1, self.gsel - 5)
  elseif act == "r1" then self.gsel = math.min(m, self.gsel + 5)
  elseif act == "a" then App.launch_game(it.sys, it.g)
  elseif act == "x" then if #it.sys.emulators > 0 then S.choose_emulator(it.sys, it.g) end
  elseif act == "select" then
    local on = Lib.toggle_fav(it.g)
    App.toast(on and (it.g.name .. L(" adicionado aos favoritos")) or (it.g.name .. L(" removido dos favoritos")), "info")
    if self.items[self.sel].special == "favs" then
      self:load_games()
      if #self.games == 0 then self.focus = "sys" end
    end
  elseif act == "y" then S.game_info(it)
  end
  self.gsels[item_key(self.items[self.sel])] = self.gsel
end

function S:action(act)
  local n = #self.items
  if CV.active() and n > 0 and Lib.scanned and Lib.total_games() > 0 then return self:shelf_action(act) end
  if act == "b" then App.pop(); return end
  if act == "y" then
    Lib.scanned = false
    Lib.systems = {}
    Lib.scan(function() self:rebuild() end)
    self.items = {}
    return
  end
  if n == 0 then return end
  if act == "left" then self.sel = math.max(1, self.sel - 1)
  elseif act == "right" then self.sel = math.min(n, self.sel + 1)
  elseif act == "up" then self.sel = math.max(1, self.sel - COLS)
  elseif act == "down" then self.sel = math.min(n, self.sel + COLS)
  elseif act == "l1" then self.sel = math.max(1, self.sel - COLS * VIS_ROWS)
  elseif act == "r1" then self.sel = math.min(n, self.sel + COLS * VIS_ROWS)
  elseif act == "x" then
    local it = self.items[self.sel]
    if it.sys and #it.sys.emulators > 0 then S.choose_emulator(it.sys, nil) end
  elseif act == "a" then
    local it = self.items[self.sel]
    if it.sys then App.push("library_games", { system = it.sys })
    else App.push("library_games", { special = it.special }) end
  end
end

return S
