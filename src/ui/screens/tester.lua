-- R36S Analog Tester (por LagdoLira) integrado ao hub.
-- O teste e um programa proprio (Python, tela cheia). Ao abrir, o hub fecha,
-- o launcher roda o teste e, quando o usuario sai dele, abre o hub de novo
-- nesta tela, que mostra o relatorio salvo pelo teste.
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Icons = require("ui.icons")
local utf8 = require("utf8")

local S = {}
-- painel com posicoes fixas e muita informacao: texto sempre no tamanho padrao
-- (Configuracoes > Aparencia > Tamanho do texto nao se aplica a esta tela)
S.fixed_text = true

local REPORT = "tools/r36s_analog_tester/relatorio_controles.txt"
local RX, RY, RW, RH = 324, 50, 304, 386
local LINE_H = 18

-- trecho de texto por caracteres (o relatorio alinha colunas por caractere)
local function usub(s, i, j)
  local n = utf8.len(s)
  if not n then return s:sub(i, j or -1) end
  j = math.min(j or n, n)
  if i > n then return "" end
  local a = utf8.offset(s, i)
  local b = utf8.offset(s, j + 1)
  return s:sub(a, b and b - 1 or -1)
end

-- nomes do relatorio (gerado pelo teste em portugues) no idioma do hub
local DPAD = { ["DPAD CIMA"] = true, ["DPAD BAIXO"] = true, ["DPAD ESQ"] = true, ["DPAD DIR"] = true }
local function tr_name(n)
  if DPAD[n] then return L(n) end
  local b = n:match("^BOTÃO (.+)$")
  if b then return L("BOTÃO ") .. b end
  local k = n:match("^STICK (%d) CÍRCULO$")
  if k then return string.format(L("STICK %s CÍRCULO"), k) end
  return n
end
local function tr_text(t)
  local v = t:match("^Diferença de alcance entre os analógicos: (.*)$")
  if v then return L("Diferença de alcance entre os analógicos: ") .. v end
  return t
end

local function status_color(st)
  if st == "OK" then return T.c.green end
  if st == "NÃO TESTADO" or st == "COBERTURA PARCIAL" then return T.c.yellow end
  return T.c.red
end

--- le e organiza o relatorio salvo pelo teste
function S:load_report()
  self.rep = nil
  local path = C.APP_DIR .. "/" .. REPORT
  local text = U.read_file(path)
  if not text or text == "" then return end
  local lines = {}
  for l in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  local rep = { date = lines[2] or "", rows = {}, problems = 0, ok = false }
  for i = 3, #lines do
    local l = lines[i]
    local n = l:match("^PROBLEMAS / PENDÊNCIAS: (%d+)")
    if n then rep.problems = tonumber(n)
    elseif l == "Nenhuma falha detectada." then rep.ok = true
    elseif l:match("^Dispositivos: ") then rep.device = l:sub(15)
    elseif l:match("^[A-ZÁ-Ú][^:]*:$") then
      rep.rows[#rep.rows + 1] = { head = l:sub(1, -2) }
    elseif l:match("^  %[!%] ") then
      -- linhas repetidas na lista de problemas: o detalhe ja aparece nas secoes
    elseif l:match("^  ") and utf8.len(l) and utf8.len(l) > 22 then
      local name = U.trim(usub(l, 3, 20))
      local st = U.trim(usub(l, 22, 41))
      rep.rows[#rep.rows + 1] = { name = name, status = st }
    elseif U.trim(l) ~= "" then
      rep.rows[#rep.rows + 1] = { text = l }
    end
  end
  self.rep = rep
end

function S:enter(p)
  self.from = p.from or "settings"
  self.returned = p.returned
  self.scroll = 0
  self.available = U.exists(App.tool_path("analog_tester") or "")
  self:load_report()
  if self.returned and self.rep then
    App.toast(self.rep.ok and L("Teste concluído: nenhuma falha detectada.")
      or string.format(L("Teste concluído: %d problema(s) ou pendência(s)."), self.rep.problems), self.rep.ok and "ok" or "warn")
  end
end

function S:resume() self:load_report() end

function S:draw()
  G.header("R36S Analog Tester", L("Testes de controles"))

  -- coluna esquerda: o que o teste faz + abrir
  local x, y, w = 12, 50, 304
  G.panel(x, y, w, 386, { bg = T.c.bg1 })
  G.rect(x + 14, y + 14, 52, 52, T.c.orange, 10, 0.18)
  Icons.draw("set_controls", x + 22, y + 22, T.c.orange, 1.5)
  G.text(T.f.h3, "R36S Analog Tester", x + 78, y + 16, T.c.text)
  G.text(T.f.small, L("por LagdoLira  •  versão 1.2"), x + 78, y + 40, T.c.dim)
  G.tag(L("INTEGRADO"), x + 78, y + 58, T.c.green, T.c.bg0, T.f.pix8)

  local body = L("Testa os dois analógicos (alcance, zona morta, deriva e movimento sozinho) e todos os botões, com a ilustração do R36S.")
  local yy = y + 88
  for _, l in ipairs(G.wrap(T.f.small, body, w - 28)) do
    G.text(T.f.small, l, x + 14, yy, T.c.text); yy = yy + 15
  end
  yy = yy + 8
  G.text(T.f.pix8, L("PARA SAIR DO TESTE"), x + 14, yy, T.c.accent2); yy = yy + 16
  for _, l in ipairs(G.wrap(T.f.small, L("START + SELECT (segure 0,3 s) ou L1 + R1 (1 s) voltam ao menu do teste. No menu, escolha Sair."), w - 28)) do
    G.text(T.f.small, l, x + 14, yy, T.c.dim); yy = yy + 15
  end
  yy = yy + 6
  for _, l in ipairs(G.wrap(T.f.small, L("O R36S PORT HUB fecha durante o teste e abre de novo sozinho, nesta tela, quando você sair."), w - 28)) do
    G.text(T.f.small, l, x + 14, yy, T.c.faint); yy = yy + 15
  end

  -- botao
  local bx, by, bw, bh = x + 14, y + 386 - 58, w - 28, 42
  if self.available then
    G.rect(bx - 3, by - 3, bw + 6, bh + 6, T.c.accent, 10, App.pulse(0.3, 0.15, 5))
    G.rect(bx, by, bw, bh, T.c.accent, 8)
    G.text(T.f.pix16, L("ABRIR TESTE"), bx, by + 13, T.c.bg0, "center", bw)
  else
    G.rect(bx, by, bw, bh, T.c.bg3, 8)
    G.text(T.f.small, L("Arquivos do teste não encontrados"), bx, by + 13, T.c.red, "center", bw)
  end

  -- coluna direita: ultimo relatorio
  G.panel(RX, RY, RW, RH, { bg = T.c.bg1 })
  G.rect(RX, RY, RW, 4, T.c.accent2, 2)
  G.text(T.f.pix8, L("ÚLTIMO RELATÓRIO"), RX + 12, RY + 14, T.c.accent2)
  local rep = self.rep
  if not rep then
    local ly = RY + 40
    for _, l in ipairs(G.wrap(T.f.small, L("Nenhum relatório ainda. O teste salva o relatório quando você volta ao menu dele."), RW - 24)) do
      G.text(T.f.small, l, RX + 12, ly, T.c.dim); ly = ly + 15
    end
  else
    G.text_fit(T.f.small, rep.date, RX + 12, RY + 32, RW - 24, T.c.dim)
    local summary = rep.ok and L("Nenhuma falha detectada.") or string.format(L("%d problema(s) ou pendência(s)"), rep.problems)
    G.text_fit(T.f.bodyb, summary, RX + 12, RY + 50, RW - 24, rep.ok and T.c.green or T.c.yellow)
    local top = RY + 76
    local vis = math.floor((RY + RH - 10 - top) / LINE_H)
    self.vis = vis
    self.scroll = math.max(0, math.min(self.scroll, #rep.rows - vis))
    G.clip(RX + 4, top, RW - 8, vis * LINE_H)
    for i = self.scroll + 1, math.min(#rep.rows, self.scroll + vis) do
      local r = rep.rows[i]
      local ly = top + (i - self.scroll - 1) * LINE_H
      if r.head then
        G.text(T.f.pix8, U.upper(r.head), RX + 12, ly + 4, T.c.accent)
      elseif r.name then
        local st = L(r.status)
        local sw = math.min(130, T.f.small:getWidth(st))
        G.text_fit(T.f.small, tr_name(r.name), RX + 12, ly + 2, RW - 40 - sw, T.c.text)
        G.text_fit(T.f.small, st, RX + RW - 14 - sw, ly + 2, 130, status_color(r.status))
      else
        G.text_fit(T.f.small, tr_text(r.text), RX + 12, ly + 2, RW - 24, T.c.dim)
      end
    end
    G.unclip()
    if #rep.rows > vis then
      local track = vis * LINE_H
      local hh = math.max(16, track * vis / #rep.rows)
      G.rect(RX + RW - 6, top + (track - hh) * (self.scroll / (#rep.rows - vis)), 3, hh, T.c.accent2, 1, 0.7)
    end
  end

  local hints = {}
  if self.available then hints[#hints + 1] = { "a", L("Abrir teste") } end
  if rep and #rep.rows > (self.vis or 99) then hints[#hints + 1] = { "dpad", L("Rolar relatório") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  if act == "b" then App.pop()
  elseif act == "a" and self.available then App.launch_tool("analog_tester", self.from)
  elseif act == "up" then self.scroll = math.max(0, self.scroll - 1)
  elseif act == "down" then self.scroll = self.scroll + 1
  elseif act == "l1" or act == "left" then self.scroll = math.max(0, self.scroll - (self.vis or 10))
  elseif act == "r1" or act == "right" then self.scroll = self.scroll + (self.vis or 10)
  end
end

return S
