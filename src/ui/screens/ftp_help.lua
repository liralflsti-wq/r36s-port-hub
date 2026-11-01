-- =============================================================================
--  Como conectar pelo celular / pelo computador (dados reais do console)
--  L1/R1 trocam a aba | cima/baixo rolam | B volta
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local Ftp = require("core.ftp")
local Net = require("core.net")

local S = {}
local TABS = { L("COMO CONECTAR PELO CELULAR"), L("COMO CONECTAR PELO COMPUTADOR") }

function S:enter(p)
  self.tab = p.tab or 1
  self.scroll = 0
end

local function data()
  local net = Net.current() or Net.get(3)
  local ip = net.connected and net.ip or nil
  return ip, Ftp.cfg.port, Ftp.cfg.user
end

local function steps(tab)
  local ip, port, user = data()
  local ipt = ip or L("(sem rede: conecte o R36S ao Wi-Fi)")
  local common = {
    L("No R36S, abra Configurações > Rede e conectividade > Configurar servidor FTP e escolha INICIAR. O status precisa mostrar ATIVADO."),
  }
  local s = {}
  for _, v in ipairs(common) do s[#s + 1] = v end
  if tab == 1 then
    s[#s + 1] = L("Conecte o celular Android na MESMA rede Wi-Fi do console (dados móveis não funcionam).")
    s[#s + 1] = L("Instale um aplicativo cliente de FTP ou um gerenciador de arquivos com suporte a FTP (por exemplo: Solid Explorer, Material Files ou AndFTP).")
    s[#s + 1] = L("No aplicativo, crie uma nova conexão FTP com estes dados:")
    s[#s + 1] = { L("Servidor/Host"), ipt }
    s[#s + 1] = { L("Porta"), tostring(port) }
    s[#s + 1] = { L("Usuário"), user }
    s[#s + 1] = { L("Senha"), L("a senha mostrada na tela Servidor FTP (botão Y)") }
    s[#s + 1] = { L("Modo"), L("Passivo  •  Criptografia: nenhuma (FTP simples)") }
    s[#s + 1] = L("Atalho: leia o QR Code da tela Servidor FTP com a câmera. Ele abre o endereço ftp://; o aplicativo pede usuário e senha.")
    s[#s + 1] = L("Para enviar jogos, copie a pasta do port e o arquivo .sh para a pasta ports. Depois reinicie a lista de ports no EmulationStation.")
  else
    s[#s + 1] = L("Conecte o computador (Windows ou Linux) na MESMA rede do console, por Wi-Fi ou cabo no mesmo roteador.")
    s[#s + 1] = L("FileZilla (Windows/Linux): Arquivo > Gerenciador de Sites > Novo site, e preencha:")
    s[#s + 1] = { L("Protocolo"), L("FTP - Protocolo de Transferência de Arquivos") }
    s[#s + 1] = { "Host", ipt }
    s[#s + 1] = { L("Porta"), tostring(port) }
    s[#s + 1] = { L("Criptografia"), L("Usar apenas FTP simples (inseguro)") }
    s[#s + 1] = { L("Tipo de logon"), L("Normal") }
    s[#s + 1] = { L("Usuário"), user }
    s[#s + 1] = { L("Senha"), L("a senha mostrada na tela Servidor FTP (botão Y)") }
    s[#s + 1] = L("Em Configurações de transferência, deixe o modo Passivo. Clique em Conectar. Na direita aparecem as pastas do cartão SD do R36S.")
    s[#s + 1] = L("Sem instalar nada: no Explorador de Arquivos do Windows ou no gerenciador de arquivos do Linux, digite ftp://") .. (ip or "IP") .. ":" .. port .. L(" na barra de endereço e entre com usuário e senha.")
    s[#s + 1] = L("Se não conectar: confira IP e porta, se o servidor está ATIVADO e se o firewall do computador libera o FileZilla.")
  end
  return s
end

function S:draw()
  G.header(L("Servidor FTP"), L("Ajuda"))
  local x = 12
  G.button_icon("l1", x, 52)
  x = x + 30
  for i, t in ipairs(TABS) do
    local w = T.f.pix8:getWidth(t) + 18
    local on = i == self.tab
    G.rect(x, 48, w, 24, on and T.c.accent or T.c.bg2, 5)
    G.text(T.f.pix8, t, x, 56, on and T.c.bg0 or T.c.dim, "center", w)
    x = x + w + 6
  end
  G.button_icon("r1", x, 52)

  local px, py, pw, ph = 12, 80, T.W - 24, 362
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  G.clip(px + 2, py + 2, pw - 4, ph - 4)
  local y = py + 14 - self.scroll
  local n = 0
  local lh = T.f.body:getHeight() * T.f.body:getLineHeight()
  for _, st in ipairs(steps(self.tab)) do
    if type(st) == "table" then
      G.text(T.f.small, st[1], px + 54, y + 1, T.c.faint)
      G.text_fit(T.f.bodyb, st[2], px + 170, y, pw - 186, T.c.accent2)
      y = y + 22
    else
      n = n + 1
      G.rect(px + 14, y, 24, 22, T.c.accent, 5)
      G.text(T.f.pix8, tostring(n), px + 14, y + 7, T.c.bg0, "center", 24)
      local lines = G.wrap(T.f.body, st, pw - 70)
      for _, l in ipairs(lines) do
        G.text(T.f.body, l, px + 52, y + 2, T.c.text)
        y = y + lh
      end
      y = y + 8
    end
  end
  self.content_h = y + self.scroll - (py + 14)
  G.unclip()
  G.hints({ { "l1", L("Trocar aba") }, { "dpad", L("Rolar") }, { "b", L("Voltar") } })
end

function S:action(act)
  local max = math.max(0, (self.content_h or 0) - 340)
  if act == "l1" or act == "r1" or act == "left" or act == "right" then
    self.tab = self.tab == 1 and 2 or 1
    self.scroll = 0
  elseif act == "down" then self.scroll = math.min(max, self.scroll + 30)
  elseif act == "up" then self.scroll = math.max(0, self.scroll - 30)
  elseif act == "b" then App.pop()
  end
end

return S
