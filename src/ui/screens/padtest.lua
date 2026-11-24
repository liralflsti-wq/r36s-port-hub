-- =============================================================================
--  Teste de controles AO VIVO (abre direto no desenho do controle)
--  Mostra na hora cada botao apertado no desenho do controle, os dois
--  analogicos (posicao, alcance maximo e valores), os dados brutos do SDL
--  (eixos e botoes numerados) e quantos botoes ja foram testados.
--  Saidas (SELECT + START nao e usado: no R36S essa combinacao fecha o app):
--    B segurado por 3 s: voltar (FN e um toque em B contam como teste)
--    L1 + R1 segurados (1 s): Teste completo (R36S Analog Tester, com relatorio)
--  So le o controle; nao muda nada no sistema.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Input = require("core.input")
local lg = love.graphics

local S = {}
S.fixed_text = true
S.no_shot = true        -- FN tambem e testado aqui (sem tirar print)

-- botoes do R36S (nome SDL do gamepad -> rotulo). L2/R2 podem vir como eixo.
local BUTTONS = {
  { id = "dpup", label = "↑" }, { id = "dpdown", label = "↓" }, { id = "dpleft", label = "←" }, { id = "dpright", label = "→" },
  { id = "a", label = "A" }, { id = "b", label = "B" }, { id = "x", label = "X" }, { id = "y", label = "Y" },
  { id = "leftshoulder", label = "L1" }, { id = "rightshoulder", label = "R1" },
  { id = "l2", label = "L2" }, { id = "r2", label = "R2" },
  { id = "leftstick", label = "L3" }, { id = "rightstick", label = "R3" },
  { id = "back", label = "SELECT" }, { id = "start", label = "START" }, { id = "guide", label = "FN" },
}
-- teclado (testes no PC / gptokeyb) -> mesmo id
local KEYS = {
  up = "dpup", down = "dpdown", left = "dpleft", right = "dpright",
  ["return"] = "a", a = "a", b = "b", space = "b", x = "x", y = "y",
  pageup = "leftshoulder", pagedown = "rightshoulder", home = "l2", ["end"] = "r2",
  q = "leftstick", e = "rightstick", tab = "back", escape = "start", f12 = "guide",
}

local HOLD = 1.0
local EXIT_HOLD = 3.0   -- segurar B para sair

function S:enter(p)
  self.from = (p and p.from) or "settings"
  self.tested = {}
  self.maxr = { 0, 0 }
  self.trail = { {}, {} }
  self.hold = { exit = 0, full = 0 }
  self.down = {}
  self.flash = {}
end

local function joystick()
  local js = love.joystick and love.joystick.getJoysticks() or {}
  return js[1]
end

--- estado atual: botoes apertados, eixos dos analogicos e dados brutos
function S:read()
  local down = {}
  local sticks = { { 0, 0 }, { 0, 0 } }
  local raw = { axes = {}, buttons = {} }
  local j = joystick()
  if j then
    if j:isGamepad() then
      for _, b in ipairs(BUTTONS) do
        if b.id ~= "l2" and b.id ~= "r2" then
          local ok, v = pcall(j.isGamepadDown, j, b.id)
          if ok and v then down[b.id] = true end
        end
      end
      local function ax(n) local ok, v = pcall(j.getGamepadAxis, j, n); return ok and v or 0 end
      sticks[1] = { ax("leftx"), ax("lefty") }
      sticks[2] = { ax("rightx"), ax("righty") }
      if ax("triggerleft") > 0.5 then down.l2 = true end
      if ax("triggerright") > 0.5 then down.r2 = true end
    end
    for i = 1, math.min(8, j:getAxisCount()) do raw.axes[i] = j:getAxis(i) end
    for i = 1, math.min(24, j:getButtonCount()) do raw.buttons[i] = j:isDown(i) end
    raw.name = j:getName()
  end
  -- Com controle conectado vale SO o que o controle informa. O hub transforma
  -- o analogico esquerdo em setas (para navegar nos menus) e o gptokeyb pode
  -- mandar teclas de seta: usar isso aqui faria o direcional "acender" ao
  -- mexer no analogico sem o botao ter sido apertado.
  local pad = j and j:isGamepad()
  if not pad then
    for key, id in pairs(KEYS) do
      if love.keyboard.isDown(key) then down[id] = true end
    end
  end
  return down, sticks, raw, pad
end

function S:update(dt)
  local down, sticks, raw, pad = self:read()
  for id, t in pairs(self.flash) do
    if t > 0 and not pad then down[id] = true end
    self.flash[id] = (t > 0) and (t - dt) or nil
  end
  self.down, self.sticks, self.raw = down, sticks, raw
  for id in pairs(down) do self.tested[id] = true end
  -- conquista "Dedos de aco": todos os botoes testados
  if not self.achv_done then
    local all = true
    for _, b in ipairs(BUTTONS) do if not self.tested[b.id] then all = false; break end end
    if all then self.achv_done = true; pcall(function() require("core.achievements").unlock("padtest") end) end
  end
  for k = 1, 2 do
    local x, y = sticks[k][1], sticks[k][2]
    local r = math.sqrt(x * x + y * y)
    if r > self.maxr[k] then self.maxr[k] = math.min(1.5, r) end
    -- rastro do alcance (angulo -> maior raio visto)
    if r > 0.2 then
      local a = math.floor(((math.atan2(y, x) + math.pi) / (2 * math.pi)) * 36) % 36 + 1
      if r > (self.trail[k][a] or 0) then self.trail[k][a] = math.min(1.2, r) end
    end
  end
  -- B segurado por 3 s volta (um toque em B conta so como teste)
  if down.b then self.hold.exit = self.hold.exit + dt else self.hold.exit = 0 end
  if self.hold.exit >= EXIT_HOLD then
    self.hold.exit = -99
    Input.reset()
    App.pop()
    return
  end
  -- combinacao segurada
  if down.leftshoulder and down.rightshoulder then self.hold.full = self.hold.full + dt else self.hold.full = 0 end
  if self.hold.full >= HOLD then
    self.hold.full = -99
    Input.reset()
    App.push("tester", { from = self.from })
  end
end

-- START, FN e o resto: tudo vira teste (sem acao). Sem controle detectado
-- (teste no PC), as acoes do hub acendem o botao por um instante.
local ACT = { up = "dpup", down = "dpdown", left = "dpleft", right = "dpright", a = "a", b = "b", x = "x", y = "y",
  l1 = "leftshoulder", r1 = "rightshoulder", l2 = "l2", r2 = "r2", select = "back", start = "start", shot = "guide" }
function S:on_start() self:action("start") end
function S:action(act)
  local id = ACT[act]
  if id then self.flash[id] = 0.25 end
end

-- ---------------------------------------------------------------------------
-- desenho
-- ---------------------------------------------------------------------------
local function key_color(self, id)
  if self.down[id] then return T.c.accent, true end
  if self.tested[id] then return T.c.green, false end
  return nil, false
end

--- botao redondo do desenho
local function rbtn(self, id, x, y, r, label)
  local c, on = key_color(self, id)
  G.color(on and c or T.c.bg3)
  lg.circle("fill", x, y, r)
  G.color(c or T.c.line, c and 1 or 0.9)
  lg.setLineWidth(2)
  lg.circle("line", x, y, r)
  lg.setLineWidth(1)
  if label then
    local f = T.f.pix8
    G.text(f, label, x - 20, y - f:getHeight() / 2, on and T.c.bg0 or (c or T.c.text), "center", 40)
  end
end

--- botao retangular (ombros, select/start)
local function qbtn(self, id, x, y, w, h, label)
  local c, on = key_color(self, id)
  G.rect(x, y, w, h, on and c or T.c.bg3, math.min(8, h / 2))
  G.frame(x, y, w, h, c or T.c.line, math.min(8, h / 2), 2)
  G.text(T.f.pix8, label, x, y + h / 2 - T.f.pix8:getHeight() / 2, on and T.c.bg0 or (c or T.c.dim), "center", w)
end

function S:draw_pad(px, py, pw, ph)
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  G.text(T.f.h3, L("Tela de teste"), px + 14, py + 10, T.c.text)
  G.text(T.f.small, L("Aperte qualquer botão ou mexa os analógicos"), px + 14, py + 34, T.c.dim)
  local cx = px + pw / 2
  local oy = py + 64
  -- ombros
  qbtn(self, "l2", cx - 132, oy, 54, 16, "L2")
  qbtn(self, "leftshoulder", cx - 132, oy + 20, 54, 16, "L1")
  qbtn(self, "r2", cx + 78, oy, 54, 16, "R2")
  qbtn(self, "rightshoulder", cx + 78, oy + 20, 54, 16, "R1")
  -- corpo do controle (formato de gamepad)
  local by = oy + 44
  G.color(T.c.bg2)
  lg.rectangle("fill", cx - 140, by, 280, 118, 36, 36)
  lg.ellipse("fill", cx - 104, by + 112, 50, 66)
  lg.ellipse("fill", cx + 104, by + 112, 50, 66)
  G.color(T.c.line)
  lg.setLineWidth(2)
  lg.rectangle("line", cx - 140, by, 280, 118, 36, 36)
  lg.setLineWidth(1)
  -- direcional
  local dx, dy = cx - 98, by + 50
  for _, d in ipairs({ { "dpup", 0, -1 }, { "dpdown", 0, 1 }, { "dpleft", -1, 0 }, { "dpright", 1, 0 } }) do
    local c, on = key_color(self, d[1])
    local bx, byy = dx + d[2] * 18 - 9, dy + d[3] * 18 - 9
    G.rect(bx, byy, 18, 18, on and c or T.c.bg3, 3)
    G.frame(bx, byy, 18, 18, c or T.c.line, 3, 2)
  end
  G.rect(dx - 9, dy - 9, 18, 18, T.c.bg3, 2)
  -- A B X Y no padrao do R36S (estilo Nintendo): X em cima, A a direita,
  -- B embaixo e Y a esquerda. Os nomes do SDL no dArkOS seguem as letras
  -- impressas no aparelho (o mesmo A que confirma no hub).
  local ax, ay = cx + 98, by + 50
  rbtn(self, "x", ax, ay - 22, 12, "X")
  rbtn(self, "a", ax + 22, ay, 12, "A")
  rbtn(self, "b", ax, ay + 22, 12, "B")
  rbtn(self, "y", ax - 22, ay, 12, "Y")
  -- select / FN / start
  qbtn(self, "back", cx - 54, by + 22, 40, 14, "SEL")
  qbtn(self, "guide", cx - 14, by + 22, 28, 14, "FN")
  qbtn(self, "start", cx + 18, by + 22, 40, 14, "START")
  -- analogicos (L3 / R3 ao clicar)
  for k, st in ipairs({ { "leftstick", cx - 44 }, { "rightstick", cx + 44 } }) do
    local sx, sy = st[2], by + 96
    local c, on = key_color(self, st[1])
    G.color(T.c.bg0)
    lg.circle("fill", sx, sy, 24)
    G.color(c or T.c.line)
    lg.setLineWidth(2)
    lg.circle("line", sx, sy, 24)
    lg.setLineWidth(1)
    local v = self.sticks and self.sticks[k] or { 0, 0 }
    G.color(on and c or T.c.bg3)
    lg.circle("fill", sx + U.clamp(v[1], -1, 1) * 10, sy + U.clamp(v[2], -1, 1) * 10, 15)
    G.color(T.c.dim)
    lg.circle("line", sx + U.clamp(v[1], -1, 1) * 10, sy + U.clamp(v[2], -1, 1) * 10, 15)
    G.text(T.f.pix8, k == 1 and "L3" or "R3", sx - 20, sy + 30, c or T.c.faint, "center", 40)
  end
  -- legenda
  local ly = py + ph - 22
  G.color(T.c.accent); lg.circle("fill", px + 20, ly + 6, 4)
  G.text(T.f.small, L("apertado agora"), px + 30, ly, T.c.dim)
  G.color(T.c.green); lg.circle("fill", px + 150, ly + 6, 4)
  G.text(T.f.small, L("já testado"), px + 160, ly, T.c.dim)
end

function S:draw_sticks(x, y, w, h)
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  G.text(T.f.bodyb, L("Analógicos"), x + 12, y + 8, T.c.green)
  G.text(T.f.small, L("posição, alcance e deriva"), x + 12, y + 28, T.c.faint)
  for k = 1, 2 do
    local cx = x + w * (k == 1 and 0.27 or 0.73)
    local cy = y + 86
    local R = 36
    G.color(T.c.bg0); lg.circle("fill", cx, cy, R)
    G.color(T.c.line); lg.circle("line", cx, cy, R)
    lg.line(cx - R, cy, cx + R, cy); lg.line(cx, cy - R, cx, cy + R)
    -- zona morta (10%)
    G.color(T.c.line, 0.6); lg.circle("line", cx, cy, R * 0.1)
    -- alcance ja visto
    local pts = {}
    for a = 1, 36 do
      local r = self.trail[k][a]
      if r then
        local ang = (a - 0.5) / 36 * 2 * math.pi - math.pi
        pts[#pts + 1] = cx + math.cos(ang) * r * R
        pts[#pts + 1] = cy + math.sin(ang) * r * R
      end
    end
    if #pts >= 6 then G.color(T.c.accent2, 0.7); lg.polygon("line", pts) end
    local v = self.sticks and self.sticks[k] or { 0, 0 }
    local mag = math.sqrt(v[1] * v[1] + v[2] * v[2])
    -- fora do centro sem mexer = possivel deriva: ponto amarelo quando passa de 0.15 e < 0.5
    local col = (mag > 0.15 and mag < 0.5) and T.c.yellow or T.c.green
    G.color(col)
    lg.circle("fill", cx + U.clamp(v[1], -1.2, 1.2) * R, cy + U.clamp(v[2], -1.2, 1.2) * R, 4)
    G.text(T.f.pix8, k == 1 and L("ESQUERDO") or L("DIREITO"), cx - 50, cy + R + 6, T.c.dim, "center", 100)
    G.text(T.f.small, string.format("%+.2f, %+.2f", v[1], v[2]), cx - 50, cy + R + 20, T.c.text, "center", 100)
    G.text(T.f.small, string.format(I18N.tr(L("máx %d%%")), math.floor(self.maxr[k] * 100 + 0.5)), cx - 50, cy + R + 36, T.c.faint, "center", 100)
  end
end

function S:draw_raw(x, y, w, h)
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  G.text(T.f.bodyb, L("Dados brutos"), x + 12, y + 8, T.c.accent)
  local raw = self.raw or { axes = {}, buttons = {} }
  G.text_fit(T.f.small, raw.name or L("Nenhum controle detectado"), x + 12, y + 28, w - 24, raw.name and T.c.faint or T.c.red)
  local yy = y + 48
  local bw = (w - 24 - 8) / 2
  for i, v in ipairs(raw.axes) do
    if i > 6 then break end
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local bx, byy = x + 12 + col * (bw + 8), yy + row * 15
    G.text(T.f.pix8, tostring(i - 1), bx, byy, T.c.faint)
    G.rect(bx + 12, byy + 3, bw - 52, 5, T.c.bg3, 2)
    local m = bx + 12 + (bw - 52) / 2
    G.rect(math.min(m, m + v * (bw - 52) / 2), byy + 3, math.abs(v) * (bw - 52) / 2, 5, T.c.accent2, 2)
    G.text(T.f.pix8, string.format("%+.2f", v), bx + bw - 36, byy, T.c.dim)
  end
  yy = yy + 48
  local n = #raw.buttons
  local cw = 26
  for i = 1, n do
    local col, row = (i - 1) % 9, math.floor((i - 1) / 9)
    local bx, byy = x + 12 + col * (cw + 3), yy + row * 18
    local on = raw.buttons[i]
    G.rect(bx, byy, cw, 15, on and T.c.accent or T.c.bg3, 3)
    G.text(T.f.pix8, tostring(i - 1), bx, byy + 3, on and T.c.bg0 or T.c.faint, "center", cw)
  end
end

function S:draw()
  G.header(L("Teste de controles"), L("ao vivo"))
  self:draw_pad(12, 50, 330, 300)
  self:draw_sticks(350, 50, 278, 196)
  self:draw_raw(350, 252, 278, 98)
  -- progresso e saidas
  local x, y, w, h = 12, 358, 616, 80
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  local n, tot = 0, 0
  for _, b in ipairs(BUTTONS) do
    tot = tot + 1
    if self.tested[b.id] then n = n + 1 end
  end
  G.text(T.f.bodyb, string.format(I18N.tr(L("Botões testados: %d de %d")), n, tot), x + 14, y + 10, n == tot and T.c.green or T.c.text)
  G.rect(x + 14, y + 34, 280, 8, T.c.bg3, 4)
  G.rect(x + 14, y + 34, 280 * n / tot, 8, n == tot and T.c.green or T.c.accent, 4)
  local miss = {}
  for _, b in ipairs(BUTTONS) do if not self.tested[b.id] then miss[#miss + 1] = b.label end end
  G.text_fit(T.f.small, #miss == 0 and L("Todos os botões responderam.") or (L("Falta: ") .. table.concat(miss, " ")), x + 14, y + 50, 290, T.c.dim)
  -- combinacoes
  local function hold_bar(label, t, yy, max)
    G.text_fit(T.f.small, label, x + 320, yy, 210, T.c.text)
    G.rect(x + 536, yy + 5, 66, 6, T.c.bg3, 3)
    if t > 0 then G.rect(x + 536, yy + 5, 66 * math.min(1, t / (max or HOLD)), 6, T.c.yellow, 3) end
  end
  hold_bar(L("Segure B (3 s): voltar"), self.hold.exit, y + 14, EXIT_HOLD)
  hold_bar(L("Segure L1 + R1: teste completo"), self.hold.full, y + 40)
end

return S
