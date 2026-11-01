-- =============================================================================
--  Central de Conteudo > BIOS do Sistema (Gerenciador de BIOS)
--  Esquerda: acoes | Direita: pasta de BIOS, fonte, andamento e explicacao
--  Nada e baixado, instalado ou apagado sem confirmacao.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Icons = require("ui.icons")
local Bios = require("core.bios")
local Clock = require("core.clock")

local S = {}

local ITEMS = {
  { id = "console", label = L("BIOS no console"), desc = L("Sistemas do console e as BIOS de cada um: instaladas, ausentes, com atualização ou com verificação pendente. Sistemas com jogos aparecem primeiro.") },
  { id = "download", label = L("Baixar pacote de BIOS"), desc = L("Consulta a fonte, mostra o nome e o tamanho do pacote e baixa só depois da sua confirmação. O download aparece na Central de Downloads e não instala nada sozinho.") },
  { id = "analyze", label = L("Analisar e instalar"), desc = L("Extrai o pacote numa pasta temporária, identifica cada arquivo pelo hash e mostra o que pode ser instalado. Antes de trocar uma BIOS, o hub faz backup e pede confirmação.") },
  { id = "scan", label = L("Verificar BIOS do console"), desc = L("Confere de novo os arquivos da pasta de BIOS (nome, tamanho e MD5). Somente leitura.") },
  { id = "hist", label = L("Histórico e backups"), desc = L("Instalações, restaurações e limpezas feitas pelo hub. Os backups das BIOS substituídas podem ser restaurados por aqui e nunca são apagados automaticamente.") },
  { id = "clean", label = L("Limpeza de arquivos de instalação"), desc = L("Apaga o pacote baixado e as pastas temporárias da extração, para liberar espaço. Não apaga BIOS instaladas, backups nem outros arquivos.") },
}

function S:enter()
  self.sel = self.sel or 1
  self.dir = Bios.detect_dir(true)
  self:refresh()
  -- primeira visita: confere as BIOS do console (so leitura, rapido)
  if self.dir.dir and not Bios.scan() and not Bios.busy() then self:run("scan") end
end

function S:resume() self:refresh() end

function S:refresh()
  self.pkg = Bios.package()
  self.free = U.free_space(Bios.DIR) or U.free_space(require("config").APP_DIR)
  self.plan, self.plan_total = Bios.clean_plan()
end

--- inicia uma operacao e trata o fim aqui (ou com aviso, se a tela ja foi fechada)
function S:run(op, args, after)
  local ok, err = Bios.start(op, args, function(j)
    self:refresh()
    if j.state == "error" then
      App.show_dialog({ title = L("BIOS do Sistema"), kind = "error", body = Bios.message(j.error_code, j.detail) })
    elseif j.state == "cancelled" then
      App.toast(L("Operação cancelada."), "warn")
    elseif after then
      after(j)
    end
  end)
  if not ok then App.toast(err, "warn") end
  return ok
end

local function sub_of(self, id)
  if id == "console" then
    if not self.dir.dir then return L("pasta de BIOS não encontrada"), T.c.red end
    if not Bios.scan() then return L("ainda não verificado"), T.c.faint end
    local n = Bios.summary()
    return string.format(I18N.tr(L("%d com BIOS  •  %d ausentes  •  %d pendentes")), n.installed or 0, n.missing or 0,
      (n.pending or 0) + (n.update or 0) + (n.incompatible or 0) + (n.error or 0)), T.c.accent2
  elseif id == "download" then
    if self.pkg then return string.format(I18N.tr(L("baixado: %s")), U.format_bytes(self.pkg.size or 0)), T.c.green end
    return L("não baixado"), T.c.faint
  elseif id == "analyze" then
    if Bios.analysis_ready() then
      local a, n = Bios.analysis(), 0
      for _, it in ipairs(a.items or {}) do if it.kind == "bios" then n = n + 1 end end
      return string.format(I18N.tr(L("analisado: %d BIOS reconhecidas")), n), T.c.green
    end
    if self.pkg then return L("pacote pronto para análise"), T.c.accent2 end
    return L("baixe o pacote primeiro"), T.c.faint
  elseif id == "scan" then
    local sc = Bios.scan()
    if sc then return L("última verificação: ") .. Clock.datetime(sc.time, true), T.c.dim end
    return L("ainda não verificado"), T.c.faint
  elseif id == "hist" then
    local n = #Bios.history()
    return n == 0 and L("nenhum registro") or string.format(I18N.tr(L("%d registro(s)")), n), T.c.dim
  elseif id == "clean" then
    if self.plan_total and self.plan_total > 0 then return string.format(I18N.tr(L("%s para liberar")), U.format_bytes(self.plan_total)), T.c.yellow end
    return L("nada para limpar"), T.c.faint
  end
  return "", T.c.dim
end

function S:draw()
  G.header(L("BIOS do Sistema"), L("Central de Conteúdo"))
  -- acoes
  local lx, lw, rh = 12, 300, 62
  local gb = T.f.bodyb:getHeight() - T.base_font(T.f.bodyb):getHeight()
  for i, it in ipairs(ITEMS) do
    local y = 50 + (i - 1) * rh
    local on = i == self.sel
    G.rect(lx, y, lw, rh - 6, on and T.c.bg3 or T.c.bg1, 7)
    if on then G.frame(lx, y, lw, rh - 6, T.c.yellow, 7, 2); G.rect(lx, y + 10, 3, rh - 26, T.c.yellow, 1) end
    local ft, fs, ty, sy = G.row_fonts(rh - 6, 9, 30)
    G.text_fit(ft, it.label, lx + 14, y + ty, lw - 28, on and T.c.text or T.c.dim)
    local sub, sc = sub_of(self, it.id)
    G.text_fit(fs, sub, lx + 14, y + sy + math.max(0, gb - 2), lw - 28, sc)
  end
  -- painel da direita
  local px, py, pw, ph = 322, 50, T.W - 334, 366
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  G.rect(px, py, pw, 4, T.c.yellow, 2)
  local y = py + 14
  G.text(T.f.pix8, L("PASTA DE BIOS"), px + 14, y, T.c.yellow)
  y = y + 14
  if self.dir.dir then
    G.text_fit(T.f.bodyb, self.dir.dir, px + 14, y, pw - 28, T.c.text)
    y = y + G.step(T.f.bodyb, 20)
    G.text_fit(T.f.small, L("Origem: ") .. I18N.tr(self.dir.source or "?"), px + 14, y, pw - 28, T.c.faint)
    y = y + G.step(T.f.small, 16)
  else
    local f, ls, lh = G.fit_lines(T.f.small, L("Não foi encontrada: o RetroArch do console não informa a pasta e /roms/bios não existe. Nada será instalado."), pw - 28, 48)
    for _, l in ipairs(ls) do G.text(f, l, px + 14, y, T.c.red); y = y + lh end
  end
  y = y + 6
  G.text(T.f.pix8, L("FONTE"), px + 14, y, T.c.yellow)
  y = y + 14
  local url, from = Bios.url()
  local info = Bios.info()
  local name = info and info.name or url:match("([^/]+)$"):gsub("%%20", " ")
  G.text_fit(T.f.small, name .. (info and info.size and ("  •  " .. U.format_bytes(info.size)) or ""), px + 14, y, pw - 28, T.c.text)
  y = y + G.step(T.f.small, 16)
  G.text_fit(T.f.small, from and (L("Link de ") .. from) or url:match("^https?://([^/]+)"), px + 14, y, pw - 28, T.c.faint)
  y = y + G.step(T.f.small, 16)
  G.text_fit(T.f.small, L("Espaço livre: ") .. (self.free and U.format_bytes(self.free) or "?"), px + 14, y, pw - 28, T.c.dim)
  y = y + G.step(T.f.small, 22)
  G.rect(px + 14, y, pw - 28, 1, T.c.line)
  y = y + 10
  local j = Bios.job
  if Bios.busy() then
    G.text(T.f.pix8, L("EM ANDAMENTO"), px + 14, y, T.c.accent2)
    y = y + 16
    G.text_fit(T.f.bodyb, Bios.PHASE[j.phase or ""] or L("Preparando..."), px + 14, y, pw - 28, T.c.text)
    y = y + G.step(T.f.bodyb, 22)
    if j.total and j.total > 0 then
      G.progress(px + 14, y, pw - 28, 10, j.done / j.total, T.c.accent2)
      y = y + 16
      local t = j.phase == "download" and (U.format_bytes(j.done) .. " / " .. U.format_bytes(j.total)
        .. (j.speed and j.speed > 0 and ("  •  " .. U.format_speed(j.speed)) or "")) or (j.done .. " / " .. j.total)
      G.text_fit(T.f.small, t, px + 14, y, pw - 28, T.c.dim)
    else
      G.progress_busy(px + 14, y, pw - 28, 10, App.t, T.c.accent2)
    end
  else
    local it = ITEMS[self.sel]
    G.text_fit(T.f.bodyb, it.label, px + 14, y, pw - 28, T.c.text)
    y = y + G.step(T.f.bodyb, 22)
    local f, ls, lh = G.fit_lines(T.f.small, it.desc, pw - 28, py + ph - 10 - y, true)
    lh = G.step(f, 15)
    for _, l in ipairs(ls) do G.text(f, l, px + 14, y, T.c.dim); y = y + lh end
  end
  local hints = { { "dpad", L("Navegar") }, { "a", L("Selecionar") } }
  if Bios.busy() then hints[#hints + 1] = { "x", L("Cancelar") } end
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

-- ---------------------------------------------------------------------------
function S:ask_download()
  if Bios.busy() then App.toast(L("Aguarde a operação de BIOS em andamento."), "warn"); return end
  local D = require("core.downloads")
  if D.active() or require("core.installer").busy() then
    App.toast(L("Aguarde o download em andamento terminar (Central de Downloads)."), "warn"); return
  end
  -- 1) consulta a fonte (nome e tamanho reais)
  self:run("info", nil, function(j)
    local info = j.result.info
    local lines = {
      I18N.tr(L("Arquivo: ")) .. tostring(info.name),
      I18N.tr(L("Tamanho: ")) .. (info.size and U.format_bytes(info.size) or I18N.tr(L("não informado pela fonte"))),
      info.md5 and I18N.tr(L("A fonte informa o MD5: o arquivo será conferido depois do download.")) or I18N.tr(L("A fonte não informa um hash: só o tamanho e o formato serão conferidos.")),
    }
    if self.pkg then lines[#lines + 1] = I18N.tr(L("Já existe um pacote baixado. Baixar de novo substitui o arquivo anterior.")) end
    lines[#lines + 1] = I18N.tr(L("O download vai para a Central de Downloads. Nada é instalado sem a sua confirmação."))
    App.show_dialog({
      title = L("Baixar pacote de BIOS?"), kind = "info", body = table.concat(lines, "\n"),
      buttons = {
        { label = L("BAIXAR"), fn = function()
          self:run("download", { name = info.name, size = info.size, md5 = info.md5 }, function(j2)
            local r = j2.result
            App.toast(r.checked and L("Pacote de BIOS baixado e conferido (MD5).") or L("Pacote de BIOS baixado."), "ok")
          end)
        end },
        { label = L("CANCELAR") },
      },
      sel = 1,
    })
  end)
end

function S:start_analyze()
  if Bios.busy() then App.toast(L("Aguarde a operação de BIOS em andamento."), "warn"); return end
  if not self.pkg then App.toast(L("Baixe o pacote de BIOS primeiro."), "warn"); return end
  self:run("analyze", { pkg = self.pkg.path }, function()
    if App.current() == self then App.push("bios_pkg") else App.toast(L("Pacote de BIOS analisado."), "ok") end
  end)
end

function S:ask_clean()
  if Bios.busy() then App.toast(L("Aguarde a operação de BIOS em andamento."), "warn"); return end
  self:refresh()
  if #self.plan == 0 then App.toast(L("Não há arquivos de instalação para apagar."), "info"); return end
  local lines = {}
  for _, it in ipairs(self.plan) do
    local what = it.kind == "package" and I18N.tr(L("Pacote: ")) or (it.kind == "part" and I18N.tr(L("Download incompleto: ")) or I18N.tr(L("Pasta temporária: ")))
    lines[#lines + 1] = what .. it.path:match("([^/]+)$") .. "  (" .. U.format_bytes(it.size) .. ")"
  end
  lines[#lines + 1] = I18N.tr(L("Espaço liberado: ")) .. U.format_bytes(self.plan_total)
  lines[#lines + 1] = I18N.tr(L("BIOS instaladas, backups e outros arquivos não são apagados."))
  local paths = {}
  for _, it in ipairs(self.plan) do paths[#paths + 1] = it.path end
  App.show_dialog({
    title = L("Limpeza de arquivos de instalação"), kind = "warn", body = table.concat(lines, "\n"),
    buttons = {
      { label = L("APAGAR"), danger = true, fn = function()
        self:run("clean", { paths = paths }, function(j)
          App.toast(string.format(I18N.tr(L("Limpeza concluída: %s liberados.")), U.format_bytes(j.result.freed or 0)), "ok")
        end)
      end },
      { label = L("CANCELAR") },
    },
    sel = 2,
  })
end

function S:action(act)
  local n = #ITEMS
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "b" then App.pop()
  elseif act == "x" and Bios.busy() then
    if Bios.job.op == "download" or Bios.job.op == "analyze" then Bios.cancel()
    else App.toast(L("Esta etapa não pode ser interrompida com segurança. Aguarde."), "warn") end
  elseif act == "a" then
    local id = ITEMS[self.sel].id
    if id == "console" then
      if not self.dir.dir then App.toast(L("A pasta de BIOS do console não foi encontrada. Nada foi feito."), "warn")
      else App.push("bios_list") end
    elseif id == "download" then self:ask_download()
    elseif id == "analyze" then
      if Bios.analysis_ready() and not Bios.busy() then App.push("bios_pkg") else self:start_analyze() end
    elseif id == "scan" then
      if Bios.busy() then App.toast(L("Aguarde a operação de BIOS em andamento."), "warn")
      else self:run("scan", nil, function() App.toast(L("BIOS do console verificadas."), "ok") end) end
    elseif id == "hist" then App.push("bios_hist")
    elseif id == "clean" then self:ask_clean()
    end
  end
end

return S
