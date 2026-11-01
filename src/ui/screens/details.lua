-- Pagina individual do port
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local Compat = require("core.compat")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Covers = require("core.covers")
local Manifest = require("core.manifest")
local Catalog = require("core.catalog")
local Favorites = require("core.favorites")
local Downloads = require("core.downloads")
local Cats = require("core.categories")
local Icons = require("ui.icons")

local S = {}

local DX, DY, DW, DH = 240, 152, 386, 196 -- caixa da descricao

function S:enter(params)
  Manifest.rescan()
  self.port = params.port
  self.btn = 1
  self.scroll = 0
  self:layout()
end

function S:on_catalog()
  -- o catalogo pode ter sido atualizado: pega a versao nova do mesmo port
  local p = Catalog.by_id[self.port.id]
  if p then self.port = p end
  self:layout()
end

function S:resume() self:layout() end

--- Espaco REAL ocupado pelos arquivos instalados deste port (script + pasta
--- propria). Nao entram runtimes/bibliotecas do PortMaster nem outros jogos.
function S:calc_size()
  local p = self.port
  self.disk = nil
  if App.status(p) == "none" then return end
  local found = Manifest.found(p) or {}
  local items = {}
  for _, n in ipairs(found) do
    if not n:find("/") and not n:find("%.%.") and not C.PROTECTED_NAMES[n:lower()] then
      items[#items + 1] = U.shq(n)
    end
  end
  if #items == 0 then return end
  local out = U.capture("cd " .. U.shq(C.PORTS_DIR) .. " 2>/dev/null && find " .. table.concat(items, " ")
    .. " -type f -exec stat -c '%s' {} + 2>/dev/null") or ""
  local total, files = 0, 0
  for n in out:gmatch("%d+") do total = total + tonumber(n); files = files + 1 end
  self.disk = { bytes = total, files = files }
end

function S:layout()
  local p = self.port
  self:calc_size()
  local LN = {}
  local function head(t) LN[#LN + 1] = { t = t, h = true } end
  local function para(t)
    for _, l in ipairs(G.wrap(T.f.body, t, DW - 28)) do LN[#LN + 1] = { t = l } end
  end
  local function item(k, v)
    for i, l in ipairs(G.wrap(T.f.body, k .. ": " .. v, DW - 40)) do LN[#LN + 1] = { t = l, bullet = i == 1, k = i == 1 and k or nil } end
  end
  -- compatibilidade (resumo; detalhes com Y)
  self.compat = (not p.builtin) and Compat.evaluate(p) or nil
  if self.compat then
    head(L("COMPATIBILIDADE"))
    para(I18N.tr(Compat.LABEL[self.compat.status]) .. ": " .. I18N.tr(self.compat.reason))
    para(I18N.tr(L("Y: ver detalhes da compatibilidade")))
    LN[#LN + 1] = { t = "" }
  end
  head(L("DESCRIÇÃO"))
  local desc = Catalog.text(p, "description")
  para(desc ~= "" and desc or L("Sem descrição."))
  LN[#LN + 1] = { t = "" }
  head(L("INFORMAÇÕES"))
  if (p.platform or "") ~= "" then item(L("Plataforma"), p.platform) end
  item(L("Categoria"), p.category)
  -- espaco ocupado: so numeros reais
  local st = App.status(p)
  if st ~= "none" then
    if self.disk then
      item(L("Espaço ocupado"), U.format_bytes(self.disk.bytes) .. L(" no cartão SD (") .. self.disk.files .. L(" arquivos)"))
    else
      item(L("Espaço ocupado"), L("não foi possível calcular"))
    end
  elseif p.size then
    item(L("Espaço ocupado"), L("não instalado (download de ") .. U.format_bytes(p.size) .. L("; o tamanho instalado aparece após a instalação)"))
  else
    item(L("Espaço ocupado"), L("não instalado (calculado após a instalação)"))
  end
  if (p.origin or "") ~= "" then
    item(L("Origem"), p.origin)
  end
  if (p.file_type or "") ~= "" then item(L("Formato do arquivo"), p.file_type) end
  if p.notes ~= "" then
    LN[#LN + 1] = { t = "" }
    head(L("OBSERVAÇÕES"))
    para(p.notes)
  end
  self.lines = LN
  self.lh = T.f.body:getHeight() * T.f.body:getLineHeight()
  self.max_lines = math.floor((DH - 20) / self.lh)
  self.scroll = U.clamp(self.scroll, 0, math.max(0, #self.lines - self.max_lines))
end

function S:primary()
  local p = self.port
  local st = App.status(p)
  if p.is_local then return L("INSTALADO"), false end
  local pend = Downloads.pending(p.id)
  if pend then return pend.state == "waiting" and L("NA FILA") or L("BAIXANDO"), false end
  if not p.download_url:match("^https?://") then return L("EM BREVE"), false end
  if st == "update" then return L("ATUALIZAR"), true end
  if st == "installed" then return L("REINSTALAR"), true end
  return L("BAIXAR"), true
end

function S:draw()
  local p = self.port
  G.header(L("Detalhes do port"))

  -- capa
  G.cover(Covers.get(p), p, 20, 56, 200, 267, Covers.is_loading(p), App.t)

  -- titulo
  local tl = G.wrap(T.f.h2, p.name, 386)
  local y = 52
  for i = 1, math.min(2, #tl) do
    G.text(T.f.h2, tl[i], DX, y, T.c.text)
    y = y + 24
  end
  y = y + 4
  local x = DX
  x = x + G.tag(p.section == "tools" and L("UTILITÁRIO") or L("JOGO"), x, y, p.section == "tools" and T.c.green or T.c.accent, T.c.bg0, T.f.bodyb) + 6
  x = x + G.tag(U.upper(p.category), x, y, T.c.accent2, T.c.bg0) + 6
  if p.test_type and Cats.TEST_TYPE_BY_ID[p.test_type] then
    x = x + G.tag(Cats.TEST_TYPE_BY_ID[p.test_type].short, x, y, T.c.bg3, T.c.text, T.f.bodyb) + 6
  end
  if (p.platform or "") ~= "" then x = x + G.tag(U.upper(p.platform), x, y, T.c.bg3, T.c.text) + 6 end
  if p.version ~= "" then x = x + G.tag("V" .. U.upper(p.version), x, y, T.c.bg3, T.c.text) + 6 end
  if p.size_label ~= "?" then x = x + G.tag(p.size_label, x, y, T.c.bg3, T.c.text) + 6 end
  if App.status(p) ~= "none" then G.tag(L("INSTALADO"), x, y, T.c.green, T.c.bg0) end

  -- status
  local st = App.status(p)
  local sy = y + 28
  local stc, stt
  if st == "installed" then
    stc, stt = T.c.green, L("Instalado") .. (Manifest.installed_version(p) and (" (v" .. Manifest.installed_version(p) .. ")") or "")
  elseif st == "update" then
    stc, stt = T.c.yellow, L("Atualização disponível: v") .. (Manifest.installed_version(p) or "?") .. " → v" .. p.version
  else
    stc, stt = T.c.dim, L("Não instalado")
  end
  G.color(stc); love.graphics.circle("fill", DX + 5, sy + 8, 4)
  G.text_fit(T.f.small, stt, DX + 16, sy, DW - 16, stc)
  local found, by = Manifest.found(p)
  if found then
    local where = (by == "hub" and L("Instalado pelo hub: ") or L("Encontrado no console: ")) .. table.concat(found, ", ")
    G.text_fit(T.f.small, where, DX + 16, sy + 15, DW - 16, T.c.faint)
  end

  -- descricao (rolavel)
  G.panel(DX, DY, DW, DH, { bg = T.c.bg1 })
  G.clip(DX + 2, DY + 2, DW - 4, DH - 4)
  local ty = DY + 10
  for i = self.scroll + 1, math.min(#self.lines, self.scroll + self.max_lines) do
    local l = self.lines[i]
    if l.h then
      G.text(T.f.pix8, l.t, DX + 14, ty + 5, T.c.accent2)
    elseif l.k then
      -- "Rotulo: valor" com o rotulo apagado
      G.color(T.c.accent); love.graphics.rectangle("fill", DX + 16, ty + 8, 4, 4)
      local kw = T.f.body:getWidth(l.k .. ": ")
      G.text(T.f.body, l.k .. ":", DX + 26, ty, T.c.dim)
      G.text(T.f.body, l.t:sub(#l.k + 3), DX + 26 + kw, ty, T.c.text)
    else
      G.text(T.f.body, l.t, DX + (l.bullet == false and 26 or 14), ty, T.c.text)
    end
    ty = ty + self.lh
  end
  G.unclip()
  if #self.lines > self.max_lines then
    local track = DH - 12
    local h = math.max(16, track * self.max_lines / #self.lines)
    local yy = DY + 6 + (track - h) * (self.scroll / (#self.lines - self.max_lines))
    G.rect(DX + DW - 6, yy, 3, h, T.c.accent2, 1, 0.7)
  end

  -- aviso de arquivos do jogo
  local by = DY + DH + 12
  local ry = 334
  if self.compat then
    local r = self.compat
    local col = T.c[Compat.COLOR[r.status]] or T.c.dim
    local label = Compat.LABEL[r.status]
    local tw = T.f.pix8:getWidth(I18N.tr(label)) + 12
    G.tag(label, 20 + (200 - tw) / 2, 330, col, T.c.bg0)
    ry = 356
  end
  if p.requires_files then
    G.rect(20, ry, 200, 46, T.c.yellow, 6, 0.14)
    G.frame(20, ry, 200, 46, T.c.yellow, 6)
    G.text(T.f.small, L("Requer arquivos do\njogo original"), 30, ry + 6, T.c.yellow)
  end

  -- botoes
  local label, enabled = self:primary()
  local buttons = { { label = label, enabled = enabled }, { label = "VOLTAR", enabled = true } }
  local bx = DX
  for i, b in ipairs(buttons) do
    local w = i == 1 and 230 or 146
    local on = i == self.btn
    local c = (not b.enabled) and T.c.faint or (i == 1 and T.c.accent or T.c.accent2)
    if on then
      G.rect(bx - 3, by - 3, w + 6, 46, c, 9, App.pulse(0.3, 0.15, 5))
      G.rect(bx, by, w, 40, c, 8)
      G.text(T.f.pix16, b.label, bx, by + 12, T.c.bg0, "center", w)
    else
      G.rect(bx, by, w, 40, T.c.bg2, 8)
      G.frame(bx, by, w, 40, c, 8)
      G.text(T.f.pix16, b.label, bx, by + 12, c, "center", w)
    end
    bx = bx + w + 10
  end
  local info = p.is_local and (L("Instalado em ") .. C.PORTS_DIR .. L(" (fora do catálogo)"))
    or (p.download_url:match("^https?://") and (L("Destino: ") .. C.PORTS_DIR)
    or L("O link de download deste port ainda não foi cadastrado."))
  G.text_fit(T.f.small, info, DX, by + 48, DW, T.c.faint)

  if Favorites.is(p) then
    Icons.draw("generic", 20 + 200 - 30, 62, T.c.yellow, 1)
  end
  local hs = { { "a", L("Confirmar") }, { "select", Favorites.is(p) and L("Desfavoritar") or L("Favoritar") } }
  if self.compat then hs[#hs + 1] = { "y", L("Compatibilidade") } end
  hs[#hs + 1] = { "b", L("Voltar") }
  hs[#hs + 1] = { "dpad", L("Rolar / escolher") }
  G.hints(hs)
end

function S:action(act)
  if act == "select" then
    local on = Favorites.toggle(self.port)
    App.toast(on and (self.port.name .. L(" adicionado aos favoritos")) or (self.port.name .. L(" removido dos favoritos")), "info")
    return
  end
  if act == "y" and self.compat then App.push("compat", { port = self.port }); return end
  if act == "left" then self.btn = 1
  elseif act == "right" then self.btn = 2
  elseif act == "up" then self.scroll = math.max(0, self.scroll - 1)
  elseif act == "down" then self.scroll = math.min(math.max(0, #self.lines - self.max_lines), self.scroll + 1)
  elseif act == "l1" then self.scroll = math.max(0, self.scroll - self.max_lines)
  elseif act == "r1" then self.scroll = math.min(math.max(0, #self.lines - self.max_lines), self.scroll + self.max_lines)
  elseif act == "b" then App.pop()
  elseif act == "a" then
    if self.btn == 2 then App.pop(); return end
    local _, enabled = self:primary()
    if not enabled and Downloads.pending(self.port.id) then
      App.toast(self.port.name .. L(" já está na Central de Downloads."), "info")
      return
    end
    if not enabled then
      App.toast(self.port.is_local and L("Este port foi instalado fora da loja e já está no console.")
        or L("Este port ainda não tem link de download."), "warn")
      return
    end
    local p = self.port
    App.update_free_space()
    if p.size and App.free and App.free < p.size + C.SPACE_MARGIN then
      App.show_dialog({
        title = L("Espaço insuficiente"),
        kind = "error",
        body = string.format(L("O download precisa de pelo menos %s livres (mais o espaço para extrair).\nLivre agora: %s."),
          U.format_bytes(p.size + C.SPACE_MARGIN), U.format_bytes(App.free)),
      })
      return
    end
    local st = App.status(p)
    if st ~= "none" then
      local found = Manifest.found(p) or {}
      local list = {}
      for i, n in ipairs(found) do
        if i > 3 then list[#list + 1] = string.format(L("… e mais %d"), #found - 3); break end
        list[#list + 1] = "• " .. C.PORTS_DIR .. "/" .. n
      end
      local title, intro
      if st == "update" then
        title = L("Atualização disponível")
        intro = string.format(L("%s já está no seu console (v%s). A versão do catálogo é v%s."),
          p.name, Manifest.installed_version(p) or "?", p.version)
      else
        title = L("Jogo já instalado")
        intro = p.name .. L(" já está instalado no seu console.")
      end
      App.show_dialog({
        title = title,
        kind = "warn",
        body = intro .. "\n" .. table.concat(list, "\n")
          .. L("\n\nSe clicar em OK, o port será baixado, extraído e instalado novamente. Seus saves e arquivos extras serão mantidos."),
        buttons = {
          { label = "OK", fn = function() App.install(p, { preapproved = true }) end },
          { label = L("CANCELAR") },
        },
        sel = 2,
      })
      return
    end
    App.install(p)
  end
end

return S
