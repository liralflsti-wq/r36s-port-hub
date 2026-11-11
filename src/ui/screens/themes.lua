-- =============================================================================
--  Configuracoes > Temas
--  cima/baixo escolhem | A aplica (na hora, sem reiniciar) | B volta
--  So a pre-visualizacao do item selecionado fica carregada na memoria.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Themes = require("core.themes")
local lg = love.graphics

local S = {}
local ROW_H = 58

function S:enter()
  Themes.scan()
  self.items = {}
  for _, th in ipairs(Themes.list) do self.items[#self.items + 1] = { theme = th } end
  self.items[#self.items + 1] = { download = true }
  self.sel = 1
  for i, it in ipairs(self.items) do
    if it.theme and it.theme.id == Themes.current then self.sel = i end
  end
  self.preview, self.preview_for = nil, nil
end

function S:leave() self:release_preview() end

function S:release_preview()
  if self.preview and self.preview.release then self.preview:release() end
  self.preview, self.preview_for = nil, nil
end

--- carrega so a imagem do item selecionado
function S:get_preview(th)
  if not th or not th.preview then return nil end
  if self.preview_for ~= th.id then
    self:release_preview()
    self.preview_for = th.id
    local ok, img = pcall(lg.newImage, th.preview)
    if ok then self.preview = img; img:setFilter("linear", "linear") end
  end
  return self.preview
end

function S:draw()
  local cur = Themes.by_id and Themes.by_id[Themes.current]
  G.header(L("Temas"), L("Atual: ") .. (cur and L(cur.name) or L("Tema Padrão")))
  -- lista
  local lx, ly, lw = 12, 50, 250
  for i, it in ipairs(self.items) do
    local y = ly + (i - 1) * (ROW_H + 6)
    local on = i == self.sel
    G.panel(lx, y, lw, ROW_H, { bg = on and T.c.bg3 or T.c.bg1, border = on and T.c.accent or T.c.line, lw = on and 2 or 1 })
    if on then G.rect(lx, y + 8, 4, ROW_H - 16, T.c.accent, 2) end
    if it.theme then
      local th = it.theme
      -- amostra das cores do proprio tema
      local sx = lx + 14
      for k, key in ipairs({ "bg0", "bg1", "accent", "accent2" }) do
        local c = th.colors[key]
        lg.setColor(c[1], c[2], c[3], 1)
        lg.rectangle("fill", sx + (k - 1) * 9, y + 14, 8, 30)
      end
      G.text_fit(T.f.bodyb, U.upper(th.name), lx + 56, y + 9, lw - 70, on and T.c.text or T.c.dim)
      local sub = th.builtin and L("Incluso no app") or L("Instalado")
      if th.version ~= "" then sub = sub .. "  •  v" .. th.version end
      local tagw = th.id == Themes.current and (T.f.pix8:getWidth(L("EM USO")) + 12) or 0
      G.text_fit(T.f.small, sub, lx + 56, y + 31, lw - 66 - (tagw > 0 and tagw + 8 or 0), T.c.faint)
      if tagw > 0 then G.tag(L("EM USO"), lx + lw - tagw - 6, y + 32, T.c.green, T.c.bg0, T.f.pix8) end
    else
      G.text_fit(T.f.bodyb, L("BAIXAR NOVOS TEMAS"), lx + 16, y + 9, lw - 28, on and T.c.text or T.c.dim)
      G.text_fit(T.f.small, Themes.catalog_url() and L("Catálogo configurado") or L("Catálogo remoto ainda não configurado"), lx + 16, y + 31, lw - 28, T.c.faint)
    end
  end

  -- pre-visualizacao e descricao
  local px, py, pw, ph = 274, 50, T.W - 286, 390
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  local it = self.items[self.sel]
  if it and it.theme then
    local th = it.theme
    local img = self:get_preview(th)
    local iw, ih = pw - 24, math.floor((pw - 24) * 3 / 4)
    if img then
      lg.setColor(1, 1, 1, 1)
      lg.draw(img, px + 12, py + 12, 0, iw / img:getWidth(), ih / img:getHeight())
      G.frame(px + 12, py + 12, iw, ih, T.c.line, 0)
    else
      G.rect(px + 12, py + 12, iw, ih, T.c.bg0, 4)
      G.text(T.f.small, L("Sem pré-visualização"), px + 12, py + 12 + ih / 2 - 6, T.c.faint, "center", iw)
    end
    local y = py + 24 + ih
    G.text_fit(T.f.h3, L(th.name), px + 14, y, pw - 28, T.c.text)
    y = y + 24
    -- descricao: com texto maior, diminui ou e encurtada para nao invadir "TEMA EM USO"
    local df, dl, dlh = G.fit_lines(T.f.small, L(th.description), pw - 28, py + ph - 28 - y, true)
    dlh = G.step(df, 15)
    for _, l in ipairs(dl) do
      G.text(df, l, px + 14, y, T.c.dim)
      y = y + dlh
    end
    if th.id == Themes.current then
      G.text(T.f.pix8, L("TEMA EM USO"), px + 14, py + ph - 22, T.c.green)
    end
  elseif it then
    G.text(T.f.pix16, L("NOVOS TEMAS"), px, py + 110, T.c.accent2, "center", pw)
    local msg = Themes.catalog_url()
      and L("O endereço do catálogo de temas já está configurado, mas o download de temas será liberado em uma próxima atualização do R36S PORT HUB.")
      or L("O catálogo remoto de temas ainda será configurado.\nQuando ele for publicado no GitHub, esta opção vai listar os temas disponíveis para baixar e instalar.")
    G.text(T.f.body, msg, px + 20, py + 150, T.c.dim, "center", pw - 40)
  end
  local hints = { { "dpad", L("Escolher") } }
  if it and it.theme and it.theme.id ~= Themes.current then hints[#hints + 1] = { "a", L("Aplicar tema") }
  elseif it and it.download then hints[#hints + 1] = { "a", L("Ver catálogo") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local n = #self.items
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "b" then App.pop()
  elseif act == "a" then
    local it = self.items[self.sel]
    if it.theme then
      if it.theme.id == Themes.current then App.toast(L("Este tema já está em uso."), "info"); return end
      local ok, why = Themes.apply(it.theme.id, true)
      if ok then App.toast(it.theme.name .. L(" aplicado."), "ok")
      else App.toast(L("Não foi possível aplicar o tema: ") .. tostring(why), "error") end
    else
      App.show_dialog({
        title = L("Baixar novos temas"), kind = "info",
        body = Themes.catalog_url()
          and L("O download de temas pelo catálogo ainda não está disponível nesta versão. Ele será liberado em uma próxima atualização.")
          or L("O catálogo remoto de temas ainda não foi configurado.\n\nPor enquanto estão disponíveis o Pastel Pop Edition, o Wii Blue Edition, o Neon Grid Edition e o Tema Padrão."),
      })
    end
  end
end

return S
