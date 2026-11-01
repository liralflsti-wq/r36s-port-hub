-- =============================================================================
--  Loja de Temas (EmulationStation) - Utilitarios & Ferramentas
--  Mostra so os temas compativeis com o sistema identificado (ou escolhido).
--  L1/R1 filtros | A visualizar | X baixar e instalar | Y remover
--  SELECT trocar sistema | B voltar
--  Reconhece os temas que ja existem no console (core/esthemes_scan.lua):
--  de fabrica, do usuario, do hub e do ThemeMaster; mostra o tema ATIVO.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Covers = require("core.covers")
local OS = require("core.osdetect")
local ES = require("core.esthemes")
local Gal = require("core.esgallery")
local SIZE_FILE = "es_theme_size.txt"
local lg = love.graphics

local S = {}
-- painel com posicoes fixas e muita informacao: texto sempre no tamanho padrao
-- (Configuracoes > Aparencia > Tamanho do texto nao se aplica a esta tela)
S.fixed_text = true
local FILTERS = {
  { id = "compat", label = L("Compatíveis") }, { id = "popular", label = L("Populares") },
  { id = "recent", label = L("Recentes") }, { id = "light", label = L("Leves") },
  { id = "full", label = L("Completos") }, { id = "installed", label = L("Instalados") },
  { id = "collections", label = L("Coleções") },
}
local RES_LABEL = { yes = L("FUNCIONA"), untested = L("NÃO TESTADO"), no = L("NÃO FUNCIONA") }
local RES_COLOR = { yes = "green", untested = "yellow", no = "red" }
local RES_TEXT = { yes = L("funciona"), untested = L("não testado"), no = L("não funciona") }
local ST_COLOR = { testado = "green", compativel = "accent2", experimental = "yellow" }
local LIST_X, LIST_Y, LIST_W, ROW_H, VISIBLE = 12, 112, 300, 40, 8

function S:enter()
  self.os = OS.detect()
  self.os_id = self.os.confirmed and self.os.id or nil
  self.manual = false
  self.filter, self.sel, self.scroll = 1, 1, 0
  -- tamanho de tela: o escolhido antes ou o detectado no console
  local saved = U.trim(love.filesystem.read(SIZE_FILE) or "")
  local det, sure = Gal.detect_size()
  self.size, self.size_auto = det, sure
  for _, sz in ipairs(Gal.SIZES) do if sz == saved then self.size, self.size_auto = saved, false; self.size_manual = true end end
  self.view = nil
  self.state = "loading"
  ES.load(function()
    self.state = "ready"
    ES.match()
    self:refresh()
    if ES.online == "failed" then
      App.toast(L("Atualização online do catálogo indisponível: mostrando os temas já conhecidos."), "warn")
    end
  end)
  if not ES.loading then self.state = "ready" end
  self:rescan()
  -- fontes do ThemeMaster (galeria + colecoes): no maximo a cada 6 h
  ES.refresh_gallery(false, function(st)
    self:refresh()
    if (st == "failed" or st == "partial") and not ES.has_gallery() then
      App.toast(L("Galeria do ThemeMaster indisponível (sem internet?): mostrando o catálogo do hub."), "warn")
    elseif st == "failed" or st == "partial" then
      App.toast(L("Atualização online da galeria indisponível: mostrando a última cópia salva."), "warn")
    end
  end)
  -- uma ativacao pedida antes (o EmulationStation reiniciou): confere se valeu
  local pend, folder = ES.check_pending()
  if pend == "ok" then App.toast(L("Tema ativo no EmulationStation: ") .. folder, "ok")
  elseif pend == "fail" then App.toast(L("A ativação de ") .. folder .. L(" não foi confirmada no es_settings.cfg."), "warn") end
  if not self.os_id then self:open_picker() end
end

--- varre os temas do console (abrir, instalar, remover, ativar)
function S:rescan()
  local sysinfo = ES.systems[self.os_id or ""] or {}
  ES.scan(self.os_id, sysinfo.themes_dir or "/roms/themes")
  self.local_items = {}
  self:refresh()
end

local function pretty(folder)
  local n = folder:gsub("^es%-theme%-", ""):gsub("[_%-]+", " ")
  return (n:gsub("^%l", string.upper))
end

--- item da lista para um tema que so existe no console (fora do catalogo)
function S:local_item(loc)
  self.local_items = self.local_items or {}
  local it = self.local_items[loc.folder]
  if it then return it end
  local g = ES.tm and ES.tm.gallery[loc.folder] or {}
  it = { id = "local:" .. loc.folder, name = pretty(loc.folder), folder = loc.folder, author = g.author,
    compat = {}, slug = "localtheme-" .. U.slug(loc.folder), cover = loc.preview or g.preview or "",
    is_local = true, loc = loc }
  self.local_items[loc.folder] = it
  return it
end

local function loc_of(th) return th.is_local and th.loc or ES.local_for(th) end
local function state_of(th)
  if th.is_local then return ES.state_loc(th.loc), th.loc end
  return ES.state(th)
end

function S:leave() Covers.reset_pending() end

--- lista do filtro atual (so temas do sistema escolhido)
--- res do tema no tamanho de tela escolhido: "yes" | "untested" | "no"
function S:res_of(th) return (th.res or {})[self.size] or "untested" end

function S:refresh()
  local f = FILTERS[self.filter].id
  -- tela escolhida: some o que a galeria marca como "nao funciona"; os que
  -- funcionam vem antes dos nao testados. Colecoes do GitHub ficam no filtro proprio.
  local base, rank = {}, { yes = 1, untested = 2 }
  for i, th in ipairs(ES.for_os(self.os_id)) do
    local r = self:res_of(th)
    if r ~= "no" and not th.collection then base[#base + 1] = th; th._ord = rank[r] * 10000 + i end
  end
  table.sort(base, function(a, b) return a._ord < b._ord end)
  self.base_n = #base
  local list, msg = {}, nil
  if f == "compat" then
    list = base
  elseif f == "collections" then
    for _, th in ipairs(ES.for_os(self.os_id)) do if th.collection then list[#list + 1] = th end end
    if #list == 0 then
      msg = ES.gallery_time() and L("Nenhum repositório de coleção para este sistema.")
        or L("As coleções do GitHub ainda não foram baixadas (precisa de internet).")
    end
  elseif f == "popular" then
    for _, t in ipairs(base) do if tonumber(t.popularity) then list[#list + 1] = t end end
    table.sort(list, function(a, b) return tonumber(a.popularity) > tonumber(b.popularity) end)
    if #list == 0 then msg = L("O catálogo ainda não informa a popularidade dos temas.") end
  elseif f == "recent" then
    for _, t in ipairs(base) do if type(t.updated) == "string" and t.updated ~= "" then list[#list + 1] = t end end
    table.sort(list, function(a, b) return a.updated > b.updated end)
  elseif f == "light" or f == "full" then
    local w = f == "light" and "leve" or "completo"
    for _, t in ipairs(base) do if t.weight == w then list[#list + 1] = t end end
    if #list == 0 then msg = L("Nenhum tema classificado como ") .. w .. L(" para este sistema.") end
  elseif f == "installed" then
    -- todos os temas que existem no console (catalogo + os que so existem aqui)
    for _, t in ipairs(ES.themes) do if ES.local_for(t) then list[#list + 1] = t end end
    for _, loc in ipairs(ES.local_only or {}) do list[#list + 1] = self:local_item(loc) end
    table.sort(list, function(a, b)
      local aa, ba = state_of(a) == "active", state_of(b) == "active"
      if aa ~= ba then return aa end
      return a.name:lower() < b.name:lower()
    end)
    if #list == 0 then
      msg = (ES.loc and #ES.loc.unreadable > 0) and L("Não foi possível ler a pasta de temas do console.")
        or L("Nenhum tema encontrado nas pastas de temas do console.")
    end
  end
  self.items, self.msg = list, msg
  self.sel = U.clamp(self.sel, 1, math.max(1, #list))
end

-- ---------------------------------------------------------------------------
-- escolha manual do sistema
--- so aparecem os sistemas que tem temas no catalogo
function S:picker_ids()
  local ids = {}
  for _, id in ipairs(OS.ORDER) do
    if #ES.for_os(id) > 0 then ids[#ids + 1] = id end
  end
  return ids
end

function S:open_picker(tab)
  self.picker = { sel = 1, ids = self:picker_ids(), tab = tab or 1, ssel = 1 }
  for i, id in ipairs(self.picker.ids) do if id == (self.os_id or self.os.id) then self.picker.sel = i end end
  for i, sz in ipairs(Gal.SIZES) do if sz == self.size then self.picker.ssel = i end end
end

--- aba "Tela": tamanhos da galeria com quantos temas funcionam / nao testados
function S:draw_size_tab(x, y, w)
  local det = Gal.detect_size()
  local msg = self.size_auto and (L("Tela detectada: ") .. det .. L(". Você pode escolher outro tamanho."))
    or L("Escolha o tamanho da tela. Temas de outro tamanho costumam ficar cortados ou esticados.")
  local yy = y
  for _, l in ipairs(G.wrap(T.f.small, msg, w - 40)) do G.text(T.f.small, l, x + 20, yy, T.c.dim); yy = yy + 15 end
  yy = yy + 6
  for i, sz in ipairs(Gal.SIZES) do
    local on = i == self.picker.ssel
    if on then G.rect(x + 16, yy - 2, w - 32, 28, T.c.bg3, 5); G.frame(x + 16, yy - 2, w - 32, 28, T.c.accent, 5, 2) end
    G.text(T.f.bodyb, sz .. (sz == det and L("  (este console)") or ""), x + 28, yy + 3, on and T.c.text or T.c.dim)
    local ok, un = 0, 0
    for _, th in ipairs(ES.for_os(self.os_id)) do
      if not th.collection then
        local r = (th.res or {})[sz] or "untested"
        if r == "yes" then ok = ok + 1 elseif r == "untested" then un = un + 1 end
      end
    end
    local info = ok .. L(" funcionam  •  ") .. un .. L(" não testados")
    G.text(T.f.small, info, x + w - 28 - T.f.small:getWidth(info), yy + 5, T.c.faint)
    yy = yy + 31
  end
end

function S:draw_picker()
  G.rect(0, 0, T.W, T.H, T.c.black, 0, 0.7)
  local w, h = 460, 380
  local x, y = (T.W - w) / 2, (T.H - h) / 2
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.accent, lw = 2, r = 10 })
  -- abas: sistema | tela (esquerda/direita)
  local tabs = { L("SISTEMA DO CONSOLE"), L("TAMANHO DA TELA") }
  local tx = x + 20
  for i, t in ipairs(tabs) do
    local on = i == self.picker.tab
    local tw = T.f.pix8:getWidth(require("lib.i18n").tr(t)) + 20
    G.rect(tx, y + 14, tw, 22, on and T.c.accent or T.c.bg2, 11)
    G.text(T.f.pix8, t, tx, y + 21, on and T.c.bg0 or T.c.dim, "center", tw)
    tx = tx + tw + 8
  end
  if self.picker.tab == 2 then
    self:draw_size_tab(x, y + 46, w)
    return
  end
  local msg = self.os.confirmed and (L("Detectado: ") .. self.os.name .. L(". Você pode escolher outro sistema."))
    or L("Sistema operacional não identificado. Selecione manualmente seu sistema para visualizar os temas compatíveis.")
  if not self.os.confirmed and self.os.id then
    msg = L("Possível sistema: ") .. self.os.name .. L(" (confiança ") .. require("lib.i18n").tr(self.os.confidence) .. L("). Confirme ou escolha outro.")
  end
  local yy = y + 46
  for _, l in ipairs(G.wrap(T.f.small, msg, w - 40)) do G.text(T.f.small, l, x + 20, yy, T.c.dim); yy = yy + 15 end
  yy = yy + 6
  if #self.picker.ids == 0 then
    G.text(T.f.body, L("O catálogo ainda não tem temas para nenhum sistema."), x + 20, yy + 10, T.c.faint, "left", w - 40)
  end
  for i, id in ipairs(self.picker.ids) do
    local on = i == self.picker.sel
    if on then G.rect(x + 16, yy - 2, w - 32, 28, T.c.bg3, 5); G.frame(x + 16, yy - 2, w - 32, 28, T.c.accent, 5, 2) end
    G.text(T.f.bodyb, OS.NAMES[id], x + 28, yy + 3, on and T.c.text or T.c.dim)
    -- quantos temas e como estao classificados para este sistema
    local n, comp = 0, 0
    for _, th in ipairs(ES.for_os(id)) do
      n = n + 1
      if th.compat[id] == "compativel" or th.compat[id] == "testado" then comp = comp + 1 end
    end
    local ex = n - comp
    local info = n .. L(" temas  •  ") .. comp .. (comp == 1 and L(" compatível, ") or L(" compatíveis, "))
      .. ex .. (ex == 1 and L(" experimental") or L(" experimentais"))
    G.text(T.f.small, info, x + w - 28 - T.f.small:getWidth(info), yy + 5, T.c.faint)
    yy = yy + 31
  end
end

-- ---------------------------------------------------------------------------
local function status_tag(st, x, y)
  local c = T.c[ST_COLOR[st] or "dim"]
  return G.tag(ES.status_label(st), x, y, c, T.c.bg0, T.f.pix8)
end

function S:sys_dir()
  local sysinfo = ES.systems[self.os_id or ""] or {}
  return OS.themes_dir(self.os_id, sysinfo.themes_dir)
end

function S:draw_preview(th, x, y, w, h)
  G.rect(x, y, w, h, T.c.bg0, 4)
  local img = Covers.get(th)
  if img then
    local iw, ih = img:getDimensions()
    local s = math.min(w / iw, h / ih)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, x + (w - iw * s) / 2, y + (h - ih * s) / 2, 0, s, s)
  else
    G.text(T.f.small, Covers.is_loading(th) and L("Carregando imagem...") or L("Sem pré-visualização"), x, y + h / 2 - 6, T.c.faint, "center", w)
  end
  G.frame(x, y, w, h, T.c.line, 4)
end

function S:draw()
  G.header(L("Loja de Temas"))
  -- sistema
  G.panel(12, 46, T.W - 24, 30, { bg = T.c.bg1 })
  local sys
  if self.os_id then
    sys = L("Sistema: ") .. OS.NAMES[self.os_id]
    if not self.manual and self.os.version then sys = sys .. " (" .. self.os.version .. ")" end
    sys = sys .. (self.manual and L("  •  escolhido manualmente") or (L("  •  confiança ") .. require("lib.i18n").tr(self.os.confidence or "?")))
  else
    sys = L("Sistema operacional não identificado")
  end
  G.text_fit(T.f.small, sys, 24, 54, 330, self.os_id and T.c.text or T.c.yellow)
  local nloc = ES.loc and #ES.loc.list or 0
  local cnt = L("Tela ") .. self.size .. "  •  " .. (self.base_n or 0) .. L(" temas  •  ") .. nloc .. L(" no console")
  G.text(T.f.small, cnt, T.W - 24 - T.f.small:getWidth(cnt), 54, T.c.dim)

  -- filtros (letra menor se nao couberem na largura da tela, ex.: russo)
  local I18N = require("lib.i18n")
  local ff, pad = T.f.bodyb, 18
  local total = 0
  for _, f in ipairs(FILTERS) do total = total + ff:getWidth(I18N.tr(f.label)) + pad + 5 end
  if total > T.W - 24 then ff, pad = T.f.small, 12 end
  local fx = 12
  for i, f in ipairs(FILTERS) do
    local tw = ff:getWidth(I18N.tr(f.label)) + pad
    local on = i == self.filter
    G.rect(fx, 82, tw, 24, on and T.c.accent or T.c.bg2, 12)
    G.text(ff, f.label, fx, ff == T.f.small and 88 or 85, on and T.c.bg0 or T.c.dim, "center", tw)
    fx = fx + tw + 5
  end

  -- lista
  G.panel(LIST_X, LIST_Y, LIST_W, VISIBLE * ROW_H + 8, { bg = T.c.bg1 })
  local list = self.items or {}
  if self.state == "loading" and #list == 0 then
    G.text(T.f.body, L("Carregando catálogo..."), LIST_X, LIST_Y + 150, T.c.dim, "center", LIST_W)
  elseif #list == 0 then
    local m = self.msg or (self.os_id and L("Nenhum tema do catálogo é compatível com este sistema ainda.") or L("Escolha o sistema (SELECT)."))
    G.text(T.f.small, m, LIST_X + 16, LIST_Y + 140, T.c.faint, "center", LIST_W - 32)
  end
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  for i = self.scroll + 1, math.min(#list, self.scroll + VISIBLE) do
    local th = list[i]
    local y = LIST_Y + 4 + (i - self.scroll - 1) * ROW_H
    local on = i == self.sel
    if on then G.rect(LIST_X + 4, y, LIST_W - 8, ROW_H - 4, T.c.bg3, 5); G.frame(LIST_X + 4, y, LIST_W - 8, ROW_H - 4, T.c.accent, 5, 2) end
    local ft, fs, ty, sy = G.row_fonts(ROW_H - 4, 2, 19)
    G.text_fit(ft, th.name, LIST_X + 14, y + ty, LIST_W - 120, on and T.c.text or T.c.dim)
    G.text_fit(fs, th.author or "", LIST_X + 14, y + sy, LIST_W - 120, T.c.faint)
    if th.is_local then
      local o = ES.ORIGIN[th.loc.origin] or "?"
      local ot = I18N.upper(I18N.tr(o))
      local ow = T.f.pix8:getWidth(ot) + 12
      G.tag(ot, LIST_X + LIST_W - 12 - ow, y + 4, T.c.bg3, T.c.text, T.f.pix8)
    else
      local st = th.compat[self.os_id or ""] or "experimental"
      local tw = T.f.pix8:getWidth(ES.status_label(st)) + 12
      status_tag(st, LIST_X + LIST_W - 12 - tw, y + 4)
    end
    local es = state_of(th)
    if es ~= "available" then
      local lb = require("lib.i18n").tr(ES.STATE_SHORT[es])
      G.tag(lb, LIST_X + LIST_W - 12 - T.f.pix8:getWidth(lb) - 12, y + 20, T.c[ES.STATE_COLOR[es]], T.c.bg0, T.f.pix8)
    end
  end

  -- pre-visualizacao do selecionado
  local px, py, pw, ph = LIST_X + LIST_W + 10, LIST_Y, T.W - (LIST_X + LIST_W + 10) - 12, VISIBLE * ROW_H + 8
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  local th = list[self.sel]
  if th then
    self:draw_preview(th, px + 10, py + 10, pw - 20, math.floor((pw - 20) * 3 / 4))
    local y = py + 18 + math.floor((pw - 20) * 3 / 4)
    G.text_fit(T.f.h3, th.name, px + 12, y, pw - 24, T.c.text)
    y = y + 22
    local es, loc = state_of(th)
    local tw = 0
    if not th.is_local then
      local st = th.compat[self.os_id or ""] or "experimental"
      tw = status_tag(st, px + 12, y) + 6
    end
    G.tag(require("lib.i18n").tr(ES.STATE_LABEL[es]), px + 12 + tw, y, T.c[ES.STATE_COLOR[es]], T.c.bg0, T.f.pix8)
    y = y + 20
    local info
    if loc then
      info = L("Origem: ") .. require("lib.i18n").tr(ES.ORIGIN[loc.origin] or "?")
        .. ((not th.is_local and ES.update_available(th, loc)) and ("  •  " .. require("lib.i18n").tr(L("atualização disponível"))) or "")
    else
      info = (th.updated and (L("Atualizado ") .. th.updated) or "") .. (th.weight and ("  •  " .. require("lib.i18n").tr(th.weight)) or "")
    end
    if not th.is_local then
      local r = self:res_of(th)
      G.tag(self.size .. " " .. require("lib.i18n").tr(RES_LABEL[r]), px + 12, y, T.c[RES_COLOR[r]], T.c.bg0, T.f.pix8)
      y = y + 18
    end
    G.text_fit(T.f.small, info, px + 12, y, pw - 24, T.c.dim)
  end

  local hints = { { "l1", L("Filtro") } }
  if th then hints[#hints + 1] = { "a", L("Visualizar") } end
  if th and not th.is_local and not loc_of(th) then hints[#hints + 1] = { "x", L("Instalar") } end
  if th and loc_of(th) and ES.can_remove(loc_of(th)) then hints[#hints + 1] = { "y", L("Remover") } end
  hints[#hints + 1] = { "select", L("Sistema / tela") }
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)

  if self.view then self:draw_view() end
  if self.picker then self:draw_picker() end
  if ES.job then self:draw_job() end
end

-- ---------------------------------------------------------------------------
-- VISUALIZAR
function S:draw_view()
  local th = self.view.theme
  G.rect(0, 0, T.W, T.H, T.c.black, 0, 0.75)
  local x, y, w, h = 14, 40, T.W - 28, 404
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.accent, lw = 2, r = 10 })
  self:draw_preview(th, x + 14, y + 14, 300, 225)
  local tx, tw = x + 330, w - 344
  G.text_fit(T.f.h2, th.name, tx, y + 12, tw, T.c.text)
  local st = th.compat[self.os_id or ""] or "experimental"
  local es, loc = state_of(th)
  local tgw = th.is_local and 0 or (status_tag(st, tx, y + 42) + 6)
  G.tag(require("lib.i18n").tr(ES.STATE_LABEL[es]), tx + tgw, y + 42, T.c[ES.STATE_COLOR[es]], T.c.bg0, T.f.pix8)
  local yy = y + 64
  local upd, have = false, nil
  if loc and not th.is_local then upd, have = ES.update_available(th, loc) end
  local rows = {
    { L("Origem"), loc and (require("lib.i18n").tr(ES.ORIGIN[loc.origin] or "?") .. (loc.evidence and ("  (" .. require("lib.i18n").tr(loc.evidence) .. ")") or "")) or nil },
    { L("Pasta"), loc and loc.path or nil },
    { L("Instalado"), have or (loc and loc.tm_version) or nil },
    { L("Autor"), th.author }, { L("Atualizado"), th.updated and (th.updated .. (upd and ("  •  " .. require("lib.i18n").tr(L("mais novo que o instalado"))) or "")) or nil },
    { L("Tela"), (not th.is_local) and (self.size .. ": " .. require("lib.i18n").tr(RES_TEXT[self:res_of(th)])) or nil },
    { L("Funciona em"), (function()
        if th.is_local or not th.res then return nil end
        local t = {}
        for _, sz in ipairs(Gal.SIZES) do if th.res[sz] == "yes" then t[#t + 1] = sz end end
        return #t > 0 and table.concat(t, ", ") or nil
      end)() },
    { L("Fonte"), (not th.is_local) and ({ catalog = L("catálogo do R36S PORT HUB"), ["catalog+gallery"] = L("catálogo do hub + galeria OGA"),
        gallery = L("galeria OGA (ThemeMaster)"), collection = L("coleção do GitHub: ") .. tostring(th.collection) })[th.src or "catalog"] or nil },
    { L("Tamanho"), (not th.is_local) and (th.size and U.format_bytes(th.size) or L("informado no download")) or nil },
    { L("Tipo"), th.weight and (require("lib.i18n").tr(th.weight) .. (th.files and (" (" .. th.files .. L(" arquivos)")) or "")) or nil },
    { "EmulationStation", (not th.is_local) and ((th.es_min or th.es_max) and ((th.es_min or "?") .. " a " .. (th.es_max or "?")) or L("versão não informada")) or nil },
  }
  if loc and loc.missing and #loc.missing > 0 then
    rows[#rows + 1] = { L("Ausentes"), table.concat(loc.missing, ", ") }
  elseif loc and not loc.xml_ok and loc.readable then
    rows[#rows + 1] = { L("Estrutura"), L("sem theme.xml") }
  end
  for _, r in ipairs(rows) do
    if r[2] then
      G.text(T.f.small, r[1], tx, yy + 1, T.c.faint)
      G.text_fit(T.f.small, tostring(r[2]), tx + 108, yy, tw - 108, T.c.text)
      yy = yy + 17
    end
  end
  yy = y + 248
  for _, l in ipairs(G.wrap(T.f.small, th["description_" .. require("lib.i18n").lang] or th.description or "", w - 28)) do
    G.text(T.f.small, l, x + 14, yy, T.c.dim); yy = yy + 15
  end
  if th.is_local then
    G.text(T.f.small, L("Tema encontrado no console (não está no catálogo da loja)."), x + 14, yy + 2, T.c.dim)
    yy = yy + 17
  elseif st == "experimental" then
    G.text(T.f.small, L("Experimental: deve funcionar neste sistema, mas ainda não foi confirmado."), x + 14, yy + 2, T.c.yellow)
    yy = yy + 17
  end
  G.text_fit(T.f.small, L("Projeto: ") .. (th.project_url or (loc and loc.git_url) or "?"), x + 14, yy + 2, w - 28, T.c.faint)
  -- botoes (conforme o estado real do tema no console)
  local btns = self:view_buttons(th)
  self.view.buttons = btns
  local bx = x + 14
  for i, b in ipairs(btns) do
    local lb = require("lib.i18n").tr(b.label)
    local bw = T.f.pix8:getWidth(lb) + 30
    local on = i == self.view.btn
    G.rect(bx, y + h - 44, bw, 30, on and T.c.accent or T.c.bg2, 6)
    if not on then G.frame(bx, y + h - 44, bw, 30, T.c.line, 6) end
    G.text(T.f.pix8, lb, bx, y + h - 33, on and T.c.bg0 or T.c.text, "center", bw)
    bx = bx + bw + 10
  end
end

-- ---------------------------------------------------------------------------
-- instalacao
function S:ask_install(th, force)
  local es, loc = state_of(th)
  if loc and not force then
    -- ja existe no console: nada de segunda instalacao
    local upd = (not th.is_local) and ES.update_available(th, loc)
    local btns = {}
    if es ~= "active" and loc.xml_ok and not loc.incomplete then btns[#btns + 1] = { label = L("ATIVAR TEMA"), fn = function() self:ask_activate(th) end } end
    if upd or loc.incomplete then btns[#btns + 1] = { label = loc.incomplete and L("REINSTALAR") or L("ATUALIZAR"), fn = function() self:ask_install(th, true) end } end
    btns[#btns + 1] = { label = "OK" }
    App.show_dialog({ title = L("Tema já instalado"), kind = "info",
      body = th.name .. L(" já está no console em:\n") .. loc.path .. L("\nOrigem: ") .. require("lib.i18n").tr(ES.ORIGIN[loc.origin] or "?")
        .. (upd and L("\n\nO catálogo tem uma versão mais nova.") or "") .. (loc.incomplete and L("\n\nA instalação está incompleta.") or "")
        .. L("\n\nNada foi baixado."),
      buttons = btns, sel = #btns })
    return
  end
  if th.is_local then return end
  if not self.os_id then App.toast(L("Escolha o sistema do console antes (SELECT)."), "warn"); return end
  local st = th.compat[self.os_id]
  if not st then App.toast(L("Este tema não é compatível com o sistema escolhido."), "error"); return end
  local dir, why = self:sys_dir()
  if not dir then
    App.show_dialog({ title = L("Não é possível instalar"), kind = "error",
      body = L("A pasta de temas deste sistema não foi encontrada (") .. tostring(why) .. L(").\nNada foi alterado.") })
    return
  end
  -- reinstalar/atualizar vai para a MESMA pasta (nunca duplica o tema)
  local folder = (loc and loc.folder) or th.folder
  if loc then dir = loc.root end
  local free = U.free_space(dir)
  local body = th.name .. L("\n\nDestino: ") .. dir .. "/" .. folder .. (free and (L("\nEspaço livre: ") .. U.format_bytes(free)) or "")
  if loc then
    body = body .. L("\n\nO tema já existe: a versão atual vira backup e é substituída.")
  elseif U.exec_ok("test -e " .. U.shq(dir .. "/" .. folder)) then
    body = body .. L("\n\nJá existe uma pasta com esse nome. Ela será guardada como backup antes da troca.")
  end
  if st == "experimental" then body = body .. L("\n\nAtenção: tema EXPERIMENTAL neste sistema (ainda não confirmado).") end
  local r = self:res_of(th)
  if r ~= "yes" then body = body .. string.format(L("\n\nA galeria não confirma este tema em %s: pode ficar cortado ou esticado."), self.size) end
  body = body .. L("\n\nO tema não será aplicado automaticamente.")
  App.show_dialog({ title = L("Baixar e instalar tema?"), kind = st == "experimental" and "warn" or "info", body = body,
    buttons = { { label = L("INSTALAR"), fn = function()
      local ok, e = ES.start_install(th, dir, self.os_id, folder)
      if not ok then App.toast(e, "error") end
    end }, { label = L("CANCELAR") } }, sel = 2 })
end

function S:view_buttons(th)
  local b = {}
  local es, loc = state_of(th)
  if not loc then
    if not th.is_local and es ~= "unverified" then b[#b + 1] = { id = "install", label = L("BAIXAR E INSTALAR") } end
  else
    if es ~= "active" and loc.xml_ok and not loc.incomplete then b[#b + 1] = { id = "activate", label = L("ATIVAR TEMA") } end
    if not th.is_local and (loc.incomplete or ES.update_available(th, loc)) then
      b[#b + 1] = { id = "reinstall", label = loc.incomplete and L("REINSTALAR") or L("ATUALIZAR") }
    end
    if ES.can_remove(loc) then b[#b + 1] = { id = "remove", label = L("REMOVER") } end
  end
  b[#b + 1] = { id = "back", label = L("VOLTAR") }
  return b
end

function S:ask_uninstall(th)
  local loc = loc_of(th)
  local okr, why = ES.can_remove(loc)
  if not okr then
    if why == "active" then
      App.show_dialog({ title = L("Tema em uso"), kind = "warn",
        body = th.name .. L(" é o tema ativo do EmulationStation. Para removê-lo com segurança, ative outro tema antes."),
        buttons = { { label = L("ESCOLHER OUTRO TEMA"), fn = function()
          for i, f in ipairs(FILTERS) do if f.id == "installed" then self.filter = i end end
          self.sel, self.scroll = 1, 0
          self:refresh()
        end }, { label = L("VOLTAR") } }, sel = 1 })
    else
      App.show_dialog({ title = L("Não removido"), kind = "error", body = why })
    end
    return
  end
  App.show_dialog({ title = L("Remover tema?"), kind = "warn",
    body = th.name .. L("\n\nPasta: ") .. loc.path .. L("\nOrigem: ") .. require("lib.i18n").tr(ES.ORIGIN[loc.origin] or "?")
      .. L("\n\nA pasta inteira do tema será apagada. Ela fica dentro da pasta de temas, não tem links para outros arquivos e não é o tema ativo."),
    buttons = { { label = L("REMOVER"), fn = function()
      local ok, e = ES.remove(loc)
      if ok then App.toast(th.name .. L(" removido."), "ok"); self:rescan()
      else App.show_dialog({ title = L("Não removido"), kind = "error", body = e }) end
    end }, { label = L("CANCELAR") } }, sel = 2 })
end

function S:ask_activate(th)
  local loc = loc_of(th)
  if not loc then return end
  App.show_dialog({ title = L("Ativar tema?"), kind = "info",
    body = th.name .. L("\n\nO tema é ativado pelo próprio EmulationStation (opção ThemeSet do es_settings.cfg, a mesma do menu Configurações da interface > Tema).")
      .. L("\n\nPara isso o R36S PORT HUB fecha e o EmulationStation reinicia. Uma cópia do es_settings.cfg é guardada antes da troca.")
      .. (ES.active and (L("\n\nTema atual: ") .. ES.active) or ""),
    buttons = { { label = L("ATIVAR E REINICIAR"), fn = function()
      local ok, e = ES.request_activate(loc)
      if not ok then App.show_dialog({ title = L("Não ativado"), kind = "error", body = e }); return end
      App.request_es_restart()
    end }, { label = L("CANCELAR") } }, sel = 2 })
end

local PHASE = { download = L("Baixando"), verify = L("Conferindo o arquivo"), extract = L("Extraindo"), install = L("Instalando") }

function S:draw_job()
  local j = ES.job
  G.rect(0, 0, T.W, T.H, T.c.black, 0, 0.7)
  local w, h = 500, 170
  local x, y = (T.W - w) / 2, (T.H - h) / 2
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.accent2, lw = 2, r = 10 })
  G.text(T.f.pix16, L("INSTALANDO TEMA"), x + 20, y + 18, T.c.accent2)
  G.text_fit(T.f.bodyb, j.theme.name, x + 20, y + 46, w - 40, T.c.text)
  G.text(T.f.small, PHASE[j.phase] or L("Preparando"), x + 20, y + 72, T.c.dim)
  local frac = (j.phase == "download" and j.total and j.total > 0) and math.min(1, j.done / j.total) or nil
  if frac then G.progress(x + 20, y + 92, w - 40, 10, frac, T.c.accent2)
  else G.progress_busy(x + 20, y + 92, w - 40, 10, App.t, T.c.accent2) end
  if j.phase == "download" then
    local s = U.format_bytes(j.done) .. (j.total and (L(" de ") .. U.format_bytes(j.total)) or "")
      .. ((j.speed or 0) > 0 and ("  •  " .. U.format_speed(j.speed)) or "")
    G.text(T.f.small, s, x + 20, y + 110, T.c.text)
    G.button_icon("b", x + w - 110, y + h - 30)
    G.text(T.f.small, L("Cancelar"), x + w - 88, y + h - 29, T.c.dim)
  end
end

function S:update()
  local j = ES.job
  if not j then return end
  ES.update()
  if j.finished and not j.reported then
    j.reported = true
    ES.job = nil
    self:rescan()
    if j.ok then
      local loc = ES.local_for(j.theme)
      App.show_dialog({ title = L("Tema instalado!"), kind = "ok",
        body = j.theme.name .. L(" foi instalado em:\n") .. j.dir .. "/" .. j.folder
          .. (j.backup and (L("\n\nA versão anterior foi guardada em:\n") .. j.backup) or "")
          .. (loc and "" or L("\n\nATENÇÃO: a nova varredura não encontrou o tema."))
          .. L("\n\nPara usar: ative agora (o EmulationStation reinicia) ou escolha depois em\nStart > Configurações da interface > Tema."),
        buttons = { { label = "OK" }, loc and { label = L("ATIVAR TEMA"), fn = function() self:ask_activate(j.theme) end } or nil } })
    elseif j.cancelled then
      App.toast(L("Instalação do tema cancelada."), "warn")
    else
      App.show_dialog({ title = L("Falha na instalação"), kind = "error", body = (j.error or L("Erro.")) .. L("\n\nO tema anterior (se havia) foi mantido.") })
    end
  end
end

function S:action(act)
  if ES.job then
    if act == "b" then ES.cancel() end
    return
  end
  if self.picker and (act == "left" or act == "right") then
    self.picker.tab = self.picker.tab == 1 and 2 or 1
    return
  end
  if self.picker and self.picker.tab == 2 then
    local p = self.picker
    local n = #Gal.SIZES
    if act == "up" then p.ssel = (p.ssel - 2) % n + 1
    elseif act == "down" then p.ssel = p.ssel % n + 1
    elseif act == "a" then
      self.size = Gal.SIZES[p.ssel]
      self.size_auto = false
      pcall(love.filesystem.write, SIZE_FILE, self.size)
      self.picker = nil
      self.sel, self.scroll = 1, 0
      self:refresh()
    elseif act == "b" then self.picker = nil end
    return
  end
  if self.picker then
    local p = self.picker
    local n = #p.ids
    if act == "up" and n > 0 then p.sel = (p.sel - 2) % n + 1
    elseif act == "down" and n > 0 then p.sel = p.sel % n + 1
    elseif act == "a" and n > 0 then
      local id = p.ids[p.sel]
      self.manual = not (self.os.confirmed and id == self.os.id)
      self.os_id = id
      self.picker = nil
      self.sel, self.scroll = 1, 0
      self:refresh()
    elseif act == "b" then
      self.picker = nil
      if not self.os_id then App.pop() end
    end
    return
  end
  if self.view then
    local v = self.view
    local n = #(v.buttons or { 1, 2 })
    if act == "left" then v.btn = math.max(1, v.btn - 1)
    elseif act == "right" then v.btn = math.min(n, v.btn + 1)
    elseif act == "b" then self.view = nil
    elseif act == "a" then
      local b = v.buttons and v.buttons[v.btn]
      local th = v.theme
      self.view = nil
      if not b or b.id == "back" then return
      elseif b.id == "remove" then self:ask_uninstall(th)
      elseif b.id == "activate" then self:ask_activate(th)
      elseif b.id == "reinstall" then self:ask_install(th, true)
      else self:ask_install(th) end
    end
    return
  end
  local list = self.items or {}
  local th = list[self.sel]
  if act == "up" and #list > 0 then self.sel = (self.sel - 2) % #list + 1
  elseif act == "down" and #list > 0 then self.sel = self.sel % #list + 1
  elseif act == "left" then self.sel = math.max(1, self.sel - VISIBLE)
  elseif act == "right" then self.sel = math.min(math.max(1, #list), self.sel + VISIBLE)
  elseif act == "l1" or act == "r1" then
    self.filter = (self.filter - 1 + (act == "l1" and -1 or 1)) % #FILTERS + 1
    self.sel, self.scroll = 1, 0
    Covers.reset_pending()
    self:refresh()
  elseif act == "select" then self:open_picker()
  elseif act == "a" and th then self.view = { theme = th, btn = 1 }
  elseif act == "x" and th then self:ask_install(th)
  elseif act == "y" and th and loc_of(th) then self:ask_uninstall(th)
  elseif act == "b" then App.pop()
  end
end

return S
