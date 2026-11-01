-- =============================================================================
--  Configuracoes > Informacoes do console > Analisador de Console
--  Inicio -> analise (thread, etapas reais) -> resultado (2 abas) -> TXT
--  A: confirmar/exportar | X: nova analise | L1/R1: abas | B: voltar
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Icons = require("ui.icons")
local CID = require("core.consoleid")

local S = {}

local STEP_LABEL = {
  system = L("Identificação do sistema"), cpu = L("Processador"), memory = L("Memória RAM"),
  devicetree = L("Placa e Device Tree"), display = L("Tela"), battery = L("Bateria"), storage = L("Armazenamento"),
}
local STEP_ORDER = { "system", "cpu", "memory", "devicetree", "display", "battery", "storage" }
local VIEW_Y, VIEW_H, LINE_H = 186, 250, 18

function S:enter()
  self.state = "intro"
  self.sel = 1
  self.last = CID.load_last()
end

function S:on_language() if self.state == "result" then self:build_lines() end end

-- ---------------------------------------------------------------------------
function S:start()
  self.state = "running"
  self.step, self.nsteps = 0, #STEP_ORDER
  self.out = love.thread.getChannel("hub_consoleid_out")
  self.out:clear()
  self.thread = love.thread.newThread("threads/consoleid_thread.lua")
  self.thread:start("hub_consoleid_out", I18N.lang)
end

function S:update()
  if self.state ~= "running" then return end
  local e = self.thread:getError()
  if e then
    U.log("consoleid:", e)
    self.state = "intro"
    App.show_dialog({ title = L("Falha na análise"), kind = "error", body = L("Erro interno: ") .. tostring(e) })
    return
  end
  local m = self.out:pop()
  while m do
    if m.t == "step" then self.step, self.nsteps = m.i, m.n
    elseif m.t == "done" then
      local res = CID.classify(m.info)
      CID.save_last(m.info, res)
      self.last = { info = m.info, result = res }
      self:show_result()
      return
    end
    m = self.out:pop()
  end
end

function S:show_result()
  self.state, self.tab, self.scroll = "result", 1, 0
  self:build_lines()
end

-- ---------------------------------------------------------------------------
-- conteudo rolavel das duas abas
function S:build_lines()
  local info, r = self.last.info, self.last.result
  local w = 640 - 56
  local lines = {}
  local function head(t) lines[#lines + 1] = { head = t } end
  local function para(t, c)
    for _, l in ipairs(G.wrap(T.f.small, t, w)) do lines[#lines + 1] = { text = l, c = c } end
  end
  local function kv(k, v, c) lines[#lines + 1] = { k = k, v = v, c = c } end
  if self.tab == 1 then
    local cls = CID.CLASSES[r.class] or CID.CLASSES.unknown
    para(cls.text, T.c.text)
    for _, e in ipairs(r.evidence or {}) do para("+  " .. e, T.c.green) end
    for _, e in ipairs(r.notes or {}) do para("•  " .. e, T.c.dim) end
    if #(r.diffs or {}) > 0 then
      lines[#lines + 1] = { gap = true }
      head(L("DIFERENÇAS EM RELAÇÃO À REFERÊNCIA"))
      for _, e in ipairs(r.diffs) do para("–  " .. e, T.c.yellow) end
    end
    lines[#lines + 1] = { gap = true }
    head(L("COMPONENTES"))
    local res = info.drm_res or info.dt_res
    local ok, no = L("identificado"), L("não identificado")
    local proc = info.soc and (info.soc:upper() .. (info.cpu and ("  •  " .. info.cpu) or "")) or info.cpu
    kv(L("Processador"), proc or no, info.soc and T.c.green or (proc and T.c.yellow or T.c.red))
    kv(L("Memória RAM"), info.mem_kb and U.format_bytes(info.mem_kb * 1024) or no, info.mem_kb and T.c.green or T.c.red)
    kv(L("Placa"), r.board and (r.board .. "  •  " .. L("na base")) or (info.model and (info.model .. "  •  " .. L("fora da base")) or no),
      r.board and T.c.green or (info.model and T.c.yellow or T.c.red))
    kv(L("Painel de tela"), info.panel_sha1 and (r.panel_known and L("assinatura conhecida") or L("assinatura fora da base")) or no,
      info.panel_sha1 and (r.panel_known and T.c.green or T.c.yellow) or T.c.red)
    kv(L("Tela"), res or no, res and T.c.green or T.c.red)
    kv(L("Bateria"), info.battery and ok or no, info.battery and T.c.green or T.c.red)
    kv(L("Armazenamento"), info.sd and ok or no, info.sd and T.c.green or T.c.red)
    kv(L("Firmware"), info.firmware or info.os or no, T.c.text)
    lines[#lines + 1] = { gap = true }
    para(L("Observação: a identificação é estimada a partir do que o sistema informa e não comprova a autenticidade nem o fabricante do aparelho."), T.c.faint)
    para(L("A placa é lida do arquivo de hardware (Device Tree) carregado pelo sistema. Se ele foi escolhido errado na instalação, o resultado também fica errado."), T.c.faint)
    para(r.firmware_note or "", T.c.faint)
  else
    for i, sec in ipairs(CID.sections(info)) do
      if i > 1 then lines[#lines + 1] = { gap = true } end
      head(sec.title)
      for _, row in ipairs(sec.rows) do
        local na = row[2] == L("Não foi possível identificar este componente.")
        kv(row[1], row[2], na and T.c.faint or T.c.text)
      end
    end
  end
  self.lines = lines
  self.scroll = 0
end

-- ---------------------------------------------------------------------------
local function big_icon(x, y, c)
  G.rect(x, y, 56, 56, c, 12, 0.18)
  Icons.draw("set_analyzer", x + 10, y + 10, c, 1.5)
end

function S:draw_intro()
  G.header(L("Analisador de Console"), L("Informações do console"))
  local x, y, w = 12, 50, 640 - 24
  G.panel(x, y, w, 386, { bg = T.c.bg1 })
  big_icon(x + 18, y + 18, T.c.accent)
  G.text(T.f.pix16, L("ANALISADOR DE CONSOLE"), x + 90, y + 24, T.c.text)
  G.text_fit(T.f.small, L("Identifique seu aparelho e consulte informações sobre o hardware."), x + 90, y + 50, w - 110, T.c.dim)

  -- botoes
  local btns = { L("INICIAR ANÁLISE") }
  if self.last then btns[2] = L("VER ÚLTIMO RESULTADO") end
  self.btns = btns
  local by = y + 96
  for i, b in ipairs(btns) do
    local on = i == self.sel
    local bx, bw, bh = x + 18, w - 36, 40
    if on then G.rect(bx - 3, by - 3, bw + 6, bh + 6, T.c.accent, 10, App.pulse(0.3, 0.15, 5)) end
    G.rect(bx, by, bw, bh, on and T.c.accent or T.c.bg3, 8)
    G.text(T.f.pix16, b, bx, by + 12, on and T.c.bg0 or T.c.dim, "center", bw)
    by = by + 50
  end
  if self.last then
    local r = self.last.result
    local cls = CID.CLASSES[r.class] or CID.CLASSES.unknown
    G.text_fit(T.f.small, L("Última análise: ") .. require("core.clock").datetime(r.time) .. "  •  " .. cls.label,
      x + 18, by, w - 36, T.c.faint)
    by = by + 22
  end
  by = by + 6
  for _, t in ipairs({
    L("A análise verifica as informações disponíveis no sistema para identificar possíveis modelos, variantes e modificações do console."),
    L("A identificação é estimada e pode não confirmar a autenticidade do aparelho."),
    L("Somente leitura: nada é alterado no console e a internet não é usada."),
  }) do
    for _, l in ipairs(G.wrap(T.f.small, t, w - 36)) do
      if by < y + 372 then G.text(T.f.small, l, x + 18, by, T.c.dim) end
      by = by + G.step(T.f.small, 15)
    end
    by = by + 5
  end
  G.hints({ { "dpad", L("Escolher") }, { "a", L("Confirmar") }, { "b", L("Voltar") } })
end

function S:draw_running()
  G.header(L("Analisador de Console"), L("Analisando..."))
  local x, y, w = 12, 50, 640 - 24
  G.panel(x, y, w, 386, { bg = T.c.bg1 })
  big_icon(x + 18, y + 18, T.c.accent2)
  G.text(T.f.pix16, L("ANALISANDO O CONSOLE"), x + 90, y + 24, T.c.text)
  G.text(T.f.small, string.format(L("Etapa %d de %d"), self.step, self.nsteps), x + 90, y + 50, T.c.dim)
  G.progress(x + 18, y + 90, w - 36, 10, math.max(0, self.step - 1) / self.nsteps, T.c.accent2)
  local ly = y + 118
  for i, id in ipairs(STEP_ORDER) do
    local done, cur = i < self.step, i == self.step
    local c = done and T.c.green or (cur and T.c.yellow or T.c.faint)
    G.color(c)
    if done then
      love.graphics.setLineWidth(2)
      love.graphics.line(x + 24, ly + 8, x + 28, ly + 12, x + 36, ly + 3)
      love.graphics.setLineWidth(1)
    elseif cur then love.graphics.circle("fill", x + 30, ly + 8, 5)
    else love.graphics.circle("line", x + 30, ly + 8, 5) end
    G.text(T.f.bodyb, STEP_LABEL[id], x + 50, ly, cur and T.c.text or (done and T.c.dim or T.c.faint))
    ly = ly + 30
  end
  G.text(T.f.small, L("Somente leitura: nada é alterado no console."), x + 18, y + 360, T.c.faint)
  G.hints({ { "b", L("Aguarde...") } })
end

function S:draw_result()
  local info, r = self.last.info, self.last.result
  local cls = CID.CLASSES[r.class] or CID.CLASSES.unknown
  local col = T.c[cls.color] or T.c.dim
  G.header(L("Analisador de Console"), require("core.clock").datetime(r.time))

  -- cartao do resultado
  local x, y, w = 12, 50, 640 - 24
  G.panel(x, y, w, 96, { bg = T.c.bg1, border = col, lw = 2 })
  big_icon(x + 14, y + 20, col)
  G.text(T.f.pix8, L("ANÁLISE CONCLUÍDA"), x + 84, y + 12, col)
  G.text_fit(T.f.h3, L("Modelo estimado: ") .. (r.model or L("não identificado")), x + 84, y + 26, w - 100, T.c.text)
  G.text_fit(T.f.bodyb, cls.label, x + 84, y + 50, w - 100, col)
  local conf = L("Confiança: ") .. (CID.CONF[r.conf] or r.conf)
  local cc = (r.conf == "alta" and T.c.green) or (r.conf == "media" and T.c.yellow) or (r.conf == "baixa" and T.c.orange) or T.c.dim
  G.tag(conf, x + 84, y + 72, cc, T.c.bg0, T.f.pix8)

  -- abas
  local tabs = { L("RESULTADO"), L("INFORMAÇÕES COLETADAS") }
  local tx = x
  G.button_icon("l1", tx, 156)
  tx = tx + 34
  for i, t in ipairs(tabs) do
    local tw = T.f.pix8:getWidth(I18N.tr(t)) + 20
    G.rect(tx, 152, tw, 24, i == self.tab and col or T.c.bg2, 6)
    G.text(T.f.pix8, t, tx + 10, 160, i == self.tab and T.c.bg0 or T.c.dim)
    tx = tx + tw + 6
  end
  G.button_icon("r1", tx + 2, 156)

  -- conteudo rolavel
  G.panel(x, VIEW_Y - 4, w, VIEW_H + 4, { bg = T.c.bg1 })
  local LINE_H = G.step(T.f.small, LINE_H)   -- texto maior: linhas mais altas
  local vis = math.floor((VIEW_H - 8) / LINE_H)
  self.vis = vis
  self.scroll = math.max(0, math.min(self.scroll, #self.lines - vis))
  G.clip(x + 2, VIEW_Y, w - 4, VIEW_H - 4)
  for i = self.scroll + 1, math.min(#self.lines, self.scroll + vis) do
    local ln = self.lines[i]
    local ly = VIEW_Y + 2 + (i - self.scroll - 1) * LINE_H
    if ln.head then
      G.text(T.f.pix8, ln.head, x + 16, ly + 4, T.c.accent2)
    elseif ln.k then
      G.text_fit(T.f.small, ln.k, x + 16, ly + 1, 196, T.c.faint)
      G.text_fit(T.f.small, ln.v, x + 220, ly + 1, w - 240, ln.c or T.c.text)
    elseif ln.text then
      G.text(T.f.small, ln.text, x + 16, ly + 1, ln.c or T.c.text)
    end
  end
  G.unclip()
  if #self.lines > vis then
    local track = VIEW_H - 8
    local hh = math.max(16, track * vis / #self.lines)
    G.rect(x + w - 7, VIEW_Y + (track - hh) * (self.scroll / (#self.lines - vis)), 3, hh, col, 1, 0.7)
  end
  G.hints({ { "dpad", L("Rolar") }, { "a", L("Exportar TXT") }, { "x", L("Nova análise") }, { "b", L("Voltar") } })
end

function S:draw()
  if self.state == "running" then self:draw_running()
  elseif self.state == "result" then self:draw_result()
  else self:draw_intro() end
end

-- ---------------------------------------------------------------------------
function S:action(act)
  if self.state == "running" then return end          -- a analise e rapida; espera terminar
  if self.state == "intro" then
    local n = #(self.btns or { 1 })
    if act == "up" then self.sel = (self.sel - 2) % n + 1
    elseif act == "down" then self.sel = self.sel % n + 1
    elseif act == "b" then App.pop()
    elseif act == "a" then
      if self.sel == 2 and self.last then self:show_result() else self:start() end
    end
    return
  end
  -- resultado
  if act == "b" then self.state = "intro"; self.sel = 1
  elseif act == "up" then self.scroll = math.max(0, self.scroll - 1)
  elseif act == "down" then self.scroll = self.scroll + 1
  elseif act == "left" then self.scroll = math.max(0, self.scroll - (self.vis or 10))
  elseif act == "right" then self.scroll = self.scroll + (self.vis or 10)
  elseif act == "l1" or act == "r1" then self.tab = self.tab == 1 and 2 or 1; self:build_lines()
  elseif act == "x" then self:start()
  elseif act == "a" then
    local path = CID.export(self.last.info, self.last.result)
    if path then
      App.show_dialog({ title = L("Relatório exportado"), kind = "ok",
        body = L("O relatório em TXT foi salvo em:\n") .. path .. L("\n\nVocê pode copiá-lo pelo Servidor FTP ou pelo Gerenciador de arquivos.") })
    else
      App.toast(L("Não foi possível salvar o relatório (cartão cheio ou somente leitura?)."), "error")
    end
  end
end

return S
