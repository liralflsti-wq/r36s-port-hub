-- =============================================================================
--  Sobre o projeto
--  Topo fixo: logo do app + versao | botao "Canal do YouTube" | logo do desenvolvedor
--  Abaixo: texto de apresentacao rolavel (cima/baixo, L1/R1), dados do catalogo
--  e o aviso de direitos autorais no final.
--  A = Canal do YouTube (navegador, se existir; senao QR Code + endereco) | B = voltar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Catalog = require("core.catalog")
local lg = love.graphics

local S = {}

local CHANNEL_NAME = L("Lag do Lira")
local CHANNEL_URL = "https://youtube.com/@lagdolira"
local CHANNEL_SHORT = "youtube.com/@lagdolira"

-- Apoio ao projeto (START): Pix "copia e cola" do projeto (BR Code com CRC conferido)
local PIX_PAYLOAD = L("00020126580014BR.GOV.BCB.PIX01364bcb070b-3155-41a6-b03d-2f24e30d05e15204000053039865802BR5922Lucas Ferreira de Lira6009SAO PAULO62140510hIyqlorhu563044638")
local PIX_TEXT = L("O R36S PORT HUB é gratuito e feito por fãs, nas horas vagas. ")
  .. L("Se ele te ajudou, considere apoiar com qualquer valor: cada contribuição ajuda a trazer novos ports, ")
  .. L("ferramentas e atualizações para a comunidade.")
local PIX_HOW = L("Abra o app do seu banco, escolha Pix > Pagar com QR Code e aponte a câmera para a tela. Você escolhe o valor.")

local TITLE = L("Sobre o R36S PORT HUB")
local PARAGRAPHS = {
  L("O R36S PORT HUB é um projeto independente desenvolvido para ampliar as possibilidades do console portátil R36S."),
  L("Mais do que uma plataforma para descobrir e baixar ports de jogos, o projeto busca reunir em um único ambiente recursos que facilitem o uso, o gerenciamento, a manutenção, a personalização e o aproveitamento do console."),
  L("A proposta é oferecer uma experiência prática e organizada, disponibilizando ferramentas para diagnóstico do sistema, testes de controles, gerenciamento de arquivos, conectividade, transferência de dados, informações do dispositivo e muito mais."),
  L("O R36S PORT HUB está em constante evolução, com a intenção de incorporar novos recursos e funcionalidades que tornem o console ainda mais versátil."),
}
local MOTTO = L("FEITO PELA COMUNIDADE, PARA A COMUNIDADE!")
local DISCLAIMER = {
  L("Este projeto é uma iniciativa independente, criada por fãs e para fãs do console R36S. Não possui vínculo oficial com os fabricantes do dispositivo, com o PortMaster ou com os desenvolvedores dos jogos e ports disponibilizados por terceiros."),
  L("Não somos proprietários dos jogos, ports ou demais conteúdos de terceiros. Seus direitos pertencem aos respectivos desenvolvedores e detentores de propriedade intelectual."),
  L("Não nos responsabilizamos pela criação, funcionamento, conteúdo ou distribuição de projetos de terceiros. Respeite as licenças e os direitos autorais aplicáveis a cada projeto."),
}

local VIEW_X, VIEW_Y, VIEW_W, VIEW_H = 20, 152, T.W - 40, 286
local TEXT_W = VIEW_W - 44

-- logo do desenvolvedor (imagem fornecida, proporcoes originais)
local dev_logo
local function get_dev_logo()
  if dev_logo == nil then
    local ok, img = pcall(lg.newImage, "assets/logo/dev_logo.png")
    dev_logo = ok and img or false
    if dev_logo then dev_logo:setFilter("linear", "linear") end
  end
  return dev_logo or nil
end

function S:enter()
  self.scroll = 0
  self.qr = nil          -- matriz do QR Code (gerada so quando o usuario pede)
  self.show_qr = false
  self:layout()
end

--- monta a lista de blocos do conteudo rolavel (texto quebrado para a largura)
function S:layout()
  local blocks = {}
  local function add(kind, font, text, color, gap)
    local lines = G.wrap(font, text, TEXT_W)
    blocks[#blocks + 1] = { kind = kind, font = font, lines = lines, color = color, gap = gap or 0 }
  end
  add("text", T.f.h3, TITLE, T.c.accent2, 6)
  for _, p in ipairs(PARAGRAPHS) do add("text", T.f.body, p, T.c.text, 10) end
  add("text", T.f.pix8, MOTTO, T.c.accent, 16)
  blocks[#blocks + 1] = { kind = "info", gap = 16 }
  add("text", T.f.pix8, L("AVISO"), T.c.yellow, 6)
  for i, p in ipairs(DISCLAIMER) do add("text", T.f.small, p, T.c.dim, i < #DISCLAIMER and 6 or 0) end
  -- altura total
  local h = 10
  for _, b in ipairs(blocks) do
    if b.kind == "info" then
      b.h = 4 * G.step(T.f.small, 17)
    else
      local lh = b.font:getHeight() * b.font:getLineHeight()
      if b.font == T.f.pix8 then lh = 14 end
      b.lh = lh
      b.h = #b.lines * lh
    end
    h = h + b.h + b.gap
  end
  self.blocks = blocks
  self.content_h = h + 6
  self.max_scroll = math.max(0, self.content_h - VIEW_H)
end

local function youtube_icon(x, y, w, h)
  G.rect(x, y, w, h, T.hex("#ff0033"), h * 0.28)
  lg.setColor(1, 1, 1, 1)
  lg.polygon("fill", x + w * 0.40, y + h * 0.28, x + w * 0.40, y + h * 0.72, x + w * 0.68, y + h * 0.5)
end

function S:draw()
  G.header(L("Sobre o projeto"))

  -- topo fixo: logo do app, botao do canal, logo do desenvolvedor
  G.panel(20, 50, T.W - 40, 96, { bg = T.c.bg1 })
  G.logo(30, 56, "about")
  G.text(T.f.pix8, L("VERSÃO ") .. C.VERSION, 34, 126, T.c.yellow)

  local img = get_dev_logo()
  if img then
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, T.W - 32 - img:getWidth(), 61)
  end

  -- botao Canal do YouTube (selecionavel com A): cartao pequeno, sempre no tamanho padrao
  T.with_base_fonts(self.draw_channel, self)

  -- conteudo rolavel
  self:draw_content()
end

function S:draw_channel()
  local bx, by, bw, bh = 168, 64, 300, 68
  local pulse = App.pulse(0.25, 0.15, 4)
  G.rect(bx - 3, by - 3, bw + 6, bh + 6, T.c.accent, 12, pulse)
  G.rect(bx, by, bw, bh, T.c.bg3, 10)
  G.frame(bx, by, bw, bh, T.c.accent, 10, 2)
  youtube_icon(bx + 14, by + 18, 46, 32)
  G.text(T.f.bodyb, L("Canal do YouTube"), bx + 72, by + 9, T.c.text)
  G.text(T.f.small, CHANNEL_NAME .. "  •  " .. CHANNEL_SHORT, bx + 72, by + 30, T.c.dim)
  G.button_icon("a", bx + 72, by + 47)
  G.text(T.f.small, L("Abrir canal"), bx + 94, by + 48, T.c.faint)
  -- START: apoio ao projeto (em destaque)
  local sx = math.max(bx + 168, bx + 94 + T.f.small:getWidth(L("Abrir canal")) + 12)
  local sw = G.button_icon("start", sx, by + 47, T.c.yellow)
  -- textos longos (ex.: russo) nao passam da borda do cartao
  local ax, aw = sx + sw + 5, bx + bw - 10 - (sx + sw + 5)
  local af = (T.f.bodyb:getWidth(I18N.tr(L("Apoiar"))) <= aw) and T.f.bodyb or T.f.small
  G.text_fit(af, L("Apoiar"), ax, by + (af == T.f.bodyb and 45 or 48), aw, T.c.yellow)
end

function S:draw_content()
  G.panel(VIEW_X, VIEW_Y, VIEW_W, VIEW_H, { bg = T.c.bg1 })
  G.clip(VIEW_X + 2, VIEW_Y + 2, VIEW_W - 4, VIEW_H - 4)
  local y = VIEW_Y + 10 - self.scroll
  local x = VIEW_X + 20
  for _, b in ipairs(self.blocks) do
    if y + b.h >= VIEW_Y and y <= VIEW_Y + VIEW_H then
      if b.kind == "info" then
        G.rect(x, y - 8, TEXT_W, 1, T.c.line)
        local info = {
          { L("Pasta de ports"), C.PORTS_DIR },
          { L("Catálogo"), Catalog.source_label() .. string.format(" (%d ports)", #Catalog.ports) },
          { L("Fonte online"), Catalog.remote_url or L("não configurada") },
          { L("Atualizado em"), Catalog.updated ~= "" and Catalog.updated or "—" },
        }
        local st = G.step(T.f.small, 17)
        for i, row in ipairs(info) do
          G.text_fit(T.f.small, row[1], x, y + (i - 1) * st, 114, T.c.faint)
          G.text_fit(T.f.small, row[2], x + 120, y + (i - 1) * st, TEXT_W - 120, T.c.dim)
        end
      else
        for i, l in ipairs(b.lines) do
          G.text(b.font, l, x, y + (i - 1) * b.lh, b.color)
        end
      end
    end
    y = y + b.h + b.gap
  end
  G.unclip()
  -- barra de rolagem
  if self.max_scroll > 0 then
    local track = VIEW_H - 12
    local hh = math.max(24, track * VIEW_H / self.content_h)
    local yy = VIEW_Y + 6 + (track - hh) * (self.scroll / self.max_scroll)
    G.rect(VIEW_X + VIEW_W - 8, yy, 3, hh, T.c.accent2, 1, 0.7)
  end

  G.hints({ { "a", L("Canal do YouTube") }, { "start", L("Apoiar o projeto") }, { "dpad", L("Rolar") }, { "b", L("Voltar") } })

  if self.show_qr then self:draw_qr() end
  if self.show_pix then self:draw_pix() end
end

--- QR Code centralizado com zona de silencio (modulos inteiros)
local function draw_qr_matrix(qr, x, y, max)
  local n = #qr
  local m = math.max(1, math.floor(max / (n + 8)))
  local size = (n + 8) * m
  lg.setColor(1, 1, 1, 1)
  lg.rectangle("fill", x, y, size, size)
  lg.setColor(0, 0, 0, 1)
  for cx = 1, n do
    for cy = 1, n do
      if qr[cx][cy] > 0 then lg.rectangle("fill", x + (cx + 3) * m, y + (cy + 3) * m, m, m) end
    end
  end
  return size
end

--- Janela de apoio (Pix)
function S:draw_pix()
  G.rect(0, 0, T.W, T.H, T.c.black, 0, 0.75)
  local w, h = 600, 330
  local x, y = (T.W - w) / 2, (T.H - h) / 2 - 6
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.yellow, lw = 2, r = 10 })
  G.rect(x, y, w, 6, T.c.yellow, 3)
  G.text(T.f.pix16, L("APOIE O PROJETO"), x + 22, y + 22, T.c.yellow)
  local size = 0
  if self.pix_qr then
    size = draw_qr_matrix(self.pix_qr, x + 22, y + 54, 236)
  else
    G.text(T.f.body, L("Não foi possível gerar o QR Code."), x + 22, y + 120, T.c.red, "left", 230)
  end
  local tx = x + 22 + math.max(size, 236) + 20
  local tw = x + w - 22 - tx
  local ty = y + 56
  for _, l in ipairs(G.wrap(T.f.body, PIX_TEXT, tw)) do
    G.text(T.f.body, l, tx, ty, T.c.text)
    ty = ty + 18
  end
  ty = ty + 10
  G.tag("PIX", tx, ty, T.c.accent2, T.c.bg0, T.f.pix8)
  ty = ty + 24
  for _, l in ipairs(G.wrap(T.f.small, PIX_HOW, tw)) do
    G.text(T.f.small, l, tx, ty, T.c.dim)
    ty = ty + 15
  end
  G.text(T.f.bodyb, L("Obrigado pelo apoio!"), tx, y + h - 64, T.c.accent)
  G.button_icon("b", x + w - 110, y + h - 30)
  G.text(T.f.small, L("Fechar"), x + w - 88, y + h - 29, T.c.dim)
end

--- START nesta tela: abre a janela de apoio (em vez da Central de Downloads)
function S:on_start()
  self.show_qr = false
  if not self.pix_qr then
    local ok, qrlib = pcall(require, "lib.qrencode")
    if ok then
      local okq, tab = qrlib.qrcode(PIX_PAYLOAD)
      if okq and type(tab) == "table" then self.pix_qr = tab end
    end
  end
  self.show_pix = not self.show_pix
end

--- Janela com QR Code e endereco (console sem navegador)
function S:draw_qr()
  G.rect(0, 0, T.W, T.H, T.c.black, 0, 0.7)
  local w, h = 520, 330
  local x, y = (T.W - w) / 2, (T.H - h) / 2
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.accent, lw = 2, r = 10 })
  G.rect(x, y, w, 6, T.c.accent, 3)
  youtube_icon(x + 22, y + 22, 34, 24)
  G.text(T.f.pix16, L("CANAL DO YOUTUBE"), x + 66, y + 26, T.c.text)
  -- QR Code: modulos inteiros, com margem branca (zona de silencio)
  local qr = self.qr
  if qr then
    local n = #qr
    local m = math.floor(200 / (n + 8))
    local size = (n + 8) * m
    local qx, qy = x + 24, y + 66
    lg.setColor(1, 1, 1, 1)
    lg.rectangle("fill", qx, qy, size, size)
    lg.setColor(0, 0, 0, 1)
    for cx = 1, n do
      for cy = 1, n do
        if qr[cx][cy] > 0 then
          lg.rectangle("fill", qx + (cx + 3) * m, qy + (cy + 3) * m, m, m)
        end
      end
    end
    local tx = qx + size + 20
    local tw = x + w - 24 - tx
    G.text(T.f.bodyb, CHANNEL_NAME, tx, qy, T.c.text)
    G.text(T.f.body, CHANNEL_SHORT, tx, qy + 22, T.c.accent2)
    G.text(T.f.small, self.qr_msg or "", tx, qy + 52, T.c.dim, "left", tw)
  else
    G.text(T.f.body, L("Acesse pelo celular ou computador:\n") .. CHANNEL_URL, x + 24, y + 80, T.c.text, "left", w - 48)
    G.text(T.f.small, self.qr_msg or "", x + 24, y + 140, T.c.dim, "left", w - 48)
  end
  G.button_icon("a", x + w - 120, y + h - 34)
  G.text(T.f.small, L("Fechar"), x + w - 98, y + h - 33, T.c.dim)
end

--- Tenta abrir o canal em um navegador grafico. Devolve true se conseguiu iniciar.
local function try_browser()
  -- so faz sentido com uma sessao grafica (o R36S/dArkOS normalmente nao tem)
  if os.getenv("PORTHUB_NO_BROWSER") then return false end -- (testes)
  if not (os.getenv("DISPLAY") or os.getenv("WAYLAND_DISPLAY")) then return false end
  for _, b in ipairs({ "xdg-open", "firefox", "chromium", "chromium-browser", "epiphany", "falkon", "surf", "netsurf-gtk" }) do
    if U.exec_ok("command -v " .. b .. " >/dev/null 2>&1") then
      return U.exec_ok(b .. " " .. U.shq(CHANNEL_URL) .. " >/dev/null 2>&1 &")
    end
  end
  return false
end

function S:open_channel()
  local launched = try_browser()
  -- sempre mostra endereco + QR Code (o R36S/dArkOS normalmente nao tem navegador)
  if not self.qr then
    local ok, qrlib = pcall(require, "lib.qrencode")
    if ok then
      local okq, tab = qrlib.qrcode(CHANNEL_URL)
      if okq and type(tab) == "table" then self.qr = tab end
    end
  end
  if launched then
    self.qr_msg = L("Tentando abrir o canal no navegador do sistema. Se ele não aparecer, aponte a câmera do celular para o QR Code ou digite o endereço.")
  else
    self.qr_msg = L("Não há navegador disponível neste console. Aponte a câmera do celular para o QR Code ou digite o endereço no navegador do celular ou computador.")
  end
  self.show_qr = true
end

function S:action(act)
  if self.show_pix then
    if act == "a" or act == "b" then self.show_pix = false end
    return
  end
  if self.show_qr then
    if act == "a" or act == "b" then self.show_qr = false end
    return
  end
  if act == "b" then App.pop()
  elseif act == "a" then self:open_channel()
  elseif act == "up" then self.scroll = math.max(0, self.scroll - 24)
  elseif act == "down" then self.scroll = math.min(self.max_scroll, self.scroll + 24)
  elseif act == "l1" or act == "left" then self.scroll = math.max(0, self.scroll - (VIEW_H - 40))
  elseif act == "r1" or act == "right" then self.scroll = math.min(self.max_scroll, self.scroll + (VIEW_H - 40))
  end
end

return S
