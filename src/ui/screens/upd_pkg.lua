-- =============================================================================
--  Atualizacoes > pacote: analise, confirmacao, instalacao com progresso real
--  e resultado. Usado pela atualizacao local e pela via rede (pacote baixado).
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Manager = require("core.updater.manager")
local Folder = require("core.updater.folder")

local S = {}
-- painel com posicoes fixas e muita informacao: texto sempre no tamanho padrao
-- (Configuracoes > Aparencia > Tamanho do texto nao se aplica a esta tela)
S.fixed_text = true

function S:enter(p)
  self.p = p
  self.state = "wait"      -- wait | analyzing | report | installing | done | error
  self.report, self.err = nil, nil
end

function S:start_analyze()
  local ok = Manager.start("analyze", { archive = self.p.path }, function(j)
    if j.state == "done" then self.report = j.result.report; self.state = "report"
    else self.err = Manager.message(j.error_code, j.detail); self.state = "error" end
  end)
  if ok then self.state = "analyzing" end
end

function S:update()
  if self.state == "wait" and not Manager.busy() then self:start_analyze() end
end

local function mode_text(r)
  if r.mode == "manifest" then return L("Atualização com manifesto") end
  if r.mode == "full" then return L("Pacote completo sem manifesto (identificação parcial)") end
  return L("Estrutura desconhecida")
end

function S:draw()
  G.header(L("Pacote de atualização"), L("Versão atual: ") .. C.VERSION)
  local x, y, w, h = 12, 50, T.W - 24, 386
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  local p = self.p
  G.text_fit(T.f.bodyb, p.name, x + 16, y + 10, w - 32, T.c.text)
  G.text(T.f.small, Folder.format_label(p.format) .. "  •  " .. U.format_bytes(p.size)
    .. (self.report and self.report.tool and ("  •  " .. self.report.tool) or ""), x + 16, y + 30, T.c.dim)
  local cy = y + 54
  local function row(k, v, c)
    G.text(T.f.small, k, x + 16, cy, T.c.faint)
    G.text_fit(T.f.bodyb, v, x + 170, cy - 2, w - 186, c or T.c.text)
    cy = cy + 20
  end
  local hints = { { "b", L("Voltar") } }
  local st = self.state
  if st == "wait" or st == "analyzing" then
    G.text(T.f.pix16, L("ANALISANDO..."), x, y + 150, T.c.yellow, "center", w)
    G.progress_busy(x + 80, y + 186, w - 160, 8, App.t, T.c.yellow)
    G.text(T.f.small, L("Lendo o conteúdo do pacote sem extrair nada."), x, y + 206, T.c.dim, "center", w)
  elseif st == "report" then
    local r = self.report
    row(L("Tipo"), mode_text(r), r.mode == "manifest" and T.c.green or (r.mode == "full" and T.c.yellow or T.c.red))
    local vtxt = r.version and (tostring(r.label or r.version_label or r.version)) or L("não identificada")
    local cmpc = (r.cmp or 0) > 0 and T.c.green or T.c.yellow
    row(L("Versão do pacote"), vtxt .. ((r.cmp == 0) and L("  (mesma versão)") or ((r.cmp or 1) < 0 and L("  (mais antiga)") or "")), r.version and cmpc or T.c.orange)
    if r.name then row(L("Nome"), r.name) end
    if r.date then row(L("Lançamento"), tostring(r.date)) end
    if r.min_version or r.max_version then
      row(L("Compatível com"), (r.min_version and (">= " .. r.min_version) or "") .. (r.max_version and ("  <= " .. r.max_version) or ""))
    end
    row(L("Arquivos"), r.files .. "  (" .. U.format_bytes(r.total) .. ")")
    if r.replace then row(L("Serão substituídos"), r.replace .. L(" arquivo(s)  •  novos: ") .. r.new) end
    if r.backup_bytes then row(L("Backup"), U.format_bytes(r.backup_bytes)) end
    if Manager.has_notes(r) then
      row(L("Novidades"), (r.changes and #r.changes or 0) .. L(" mudança(s)  •  ") .. (r.fixes and #r.fixes or 0)
        .. L(" correção(ões)  —  Y para ver"), T.c.accent2)
    end
    if r.description and r.description ~= "" then
      cy = cy + 2
      local lines = G.wrap(T.f.small, tostring(r.description), w - 32)
      for k = 1, math.min(3, #lines) do G.text(T.f.small, lines[k], x + 16, cy, T.c.text); cy = cy + 15 end
    end
    if #r.problems > 0 then
      cy = cy + 10
      G.text(T.f.pix8, L("PROBLEMAS — NÃO É POSSÍVEL INSTALAR"), x + 16, cy, T.c.red)
      cy = cy + 16
      for k = 1, math.min(5, #r.problems) do
        G.text_fit(T.f.small, "• " .. Manager.problem_text(r.problems[k]), x + 16, cy, w - 32, T.c.orange)
        cy = cy + 15
      end
      if #r.problems > 5 then G.text(T.f.small, "… +" .. (#r.problems - 5), x + 16, cy, T.c.orange) end
    else
      G.text(T.f.small, L("Os arquivos atuais são guardados num backup antes da troca. Configurações, ports e gravações não são alterados."),
        x + 16, y + h - 40, T.c.faint, "left", w - 32)
      table.insert(hints, 1, { "a", L("Instalar") })
    end
    if Manager.has_notes(r) then table.insert(hints, #hints, { "y", L("Novidades") }) end
  elseif st == "installing" then
    local j = Manager.job
    G.text(T.f.pix16, L("ATUALIZANDO..."), x, y + 110, T.c.yellow, "center", w)
    G.text(T.f.body, Manager.PHASE[j.phase or "verify"] or "", x, y + 144, T.c.text, "center", w)
    local frac = (j.total and j.total > 0) and math.min(1, j.done / j.total) or nil
    if frac then G.progress(x + 60, y + 174, w - 120, 12, frac, T.c.accent2)
    else G.progress_busy(x + 60, y + 174, w - 120, 12, App.t, T.c.accent2) end
    local info = ""
    if frac then
      info = (j.phase == "hash") and (U.format_bytes(j.done) .. L(" de ") .. U.format_bytes(j.total))
        or string.format(L("%d de %d arquivos"), j.done, j.total)
      info = info .. string.format("  (%d%%)", math.floor(frac * 100))
    end
    G.text(T.f.small, info, x, y + 196, T.c.dim, "center", w)
    G.text(T.f.small, L("Não desligue o console. Se algo falhar, a versão atual é restaurada."), x, y + 240, T.c.orange, "center", w)
    hints = {}
  elseif st == "done" then
    local res = Manager.job and Manager.job.result or {}
    G.text(T.f.pix16, L("ATUALIZAÇÃO INSTALADA"), x, y + 110, T.c.green, "center", w)
    G.text(T.f.body, tostring(res.from_label or Manager.job.from_version) .. "  →  " .. tostring(res.to_label or res.to), x, y + 146, T.c.text, "center", w)
    G.text(T.f.small, L("Backup da versão anterior: ") .. tostring(res.backup), x, y + 176, T.c.dim, "center", w)
    G.text(T.f.body, L("Reinicie o app para usar a nova versão. Se ela não abrir, a anterior volta sozinha."), x + 30, y + 206, T.c.text, "center", w - 60)
    hints = { { "a", L("Reiniciar o app agora") } }
    if Manager.has_notes(res) then table.insert(hints, 2, { "y", L("Novidades") }) end
    if self.left then table.insert(hints, #hints, { "x", L("Excluir arquivo") }) end
  elseif st == "error" then
    G.text(T.f.pix16, L("NÃO FOI POSSÍVEL ATUALIZAR"), x, y + 90, T.c.red, "center", w)
    G.text(T.f.body, self.err or L("Erro desconhecido."), x + 30, y + 126, T.c.text, "center", w - 60)
    local r = self.report
    if r and r.problems and #r.problems > 0 then
      local yy = y + 200
      for k = 1, math.min(5, #r.problems) do
        G.text_fit(T.f.small, "• " .. Manager.problem_text(r.problems[k]), x + 30, yy, w - 60, T.c.orange)
        yy = yy + 15
      end
    end
    G.text(T.f.small, L("Configurações, ports e gravações não foram alterados."), x, y + h - 40, T.c.dim, "center", w)
    if self.p.origin == "local" then
      G.text(T.f.small, L("O arquivo de atualização foi mantido na pasta update para uma nova tentativa."), x, y + h - 24, T.c.dim, "center", w)
    end
  end
  G.hints(hints)
end

function S:install()
  local r = self.report
  local p = self.p
  local ok, why = Manager.start("install", { archive = p.path, origin = p.origin, package = p.name, version = r.version },
    function(j)
      if j.state == "done" then
        self.state = "done"
        self.left = Folder.package_left(self.p.path)   -- conferido uma vez (nao a cada quadro)
        -- instalacao conferida: oferece apagar o pacote (so ele; falhas nunca chegam aqui)
        self:ask_delete()
      else
        self.err = Manager.message(j.error_code, j.detail)
        if j.report then self.report = j.report end
        self.state = "error"
      end
    end)
  if ok then self.state = "installing" else App.toast(why, "error") end
end

--- pergunta se apaga o arquivo do pacote instalado; se ele ja nao existe, nada muda
function S:ask_delete()
  if self.pkg_handled or not self.left then return end
  App.show_dialog({
    title = L("Arquivo de atualização"), kind = "info",
    body = L("A atualização foi instalada e conferida. O arquivo de atualização ainda está na pasta update:") .. "\n"
      .. self.p.name .. "  (" .. U.format_bytes(U.file_size(self.p.path) or 0) .. ")\n\n"
      .. L("Excluir só este arquivo? Os outros arquivos da pasta, os backups e os registros não são tocados."),
    buttons = {
      { label = L("EXCLUIR"), fn = function() self:delete_package() end },
      { label = L("MANTER"), fn = function()
        self.pkg_handled = true
        App.toast(L("Arquivo de atualização mantido na pasta update."), "info")
      end },
    },
    sel = 2,
  })
end

function S:delete_package()
  self.pkg_handled = true
  local ok, why = Folder.remove_package(self.p.path)
  self.left = Folder.package_left(self.p.path)
  if ok then App.toast(L("Arquivo de atualização excluído."), "ok")
  elseif why == "missing" then App.toast(L("O arquivo de atualização já não existe. Nada foi alterado."), "info")
  else App.toast(L("Não foi possível excluir o arquivo de atualização: ") .. tostring(why), "error") end
end

function S:confirm()
  local r = self.report
  local Installer, Runtimes = require("core.installer"), require("core.runtimes")
  if Installer.busy() or Runtimes.busy() or require("core.pmmanager").busy() then
    App.toast(L("Aguarde os downloads e instalações em andamento terminarem."), "warn")
    return
  end
  local warn = ""
  if r.mode == "full" then warn = warn .. L("\n\nEste pacote não tem manifesto: a versão e os arquivos não podem ser conferidos um a um (só o teste de integridade do arquivo compactado).") end
  if not r.version then warn = warn .. L("\n\nA versão do pacote não foi identificada.")
  elseif (r.cmp or 1) == 0 then warn = warn .. L("\n\nO pacote tem a MESMA versão da instalada (reinstalação).")
  elseif (r.cmp or 1) < 0 then warn = warn .. L("\n\nO pacote é MAIS ANTIGO que a versão instalada.") end
  App.show_dialog({
    title = L("Instalar a atualização?"), kind = warn ~= "" and "warn" or "info",
    body = select(2, Manager.disk_version()) .. "  →  " .. tostring(r.label or r.version_label or r.version or "?") .. "\n"
      .. r.files .. L(" arquivo(s): ") .. (r.replace or 0) .. L(" substituído(s), ") .. (r.new or 0) .. L(" novo(s).")
      .. L("\n\nOs arquivos atuais vão para um backup antes da troca. Se algo falhar, tudo volta como estava.") .. warn,
    buttons = { { label = L("INSTALAR"), fn = function() self:install() end }, { label = "VOLTAR" } },
    sel = warn ~= "" and 2 or 1,
  })
end

function S:action(act)
  local st = self.state
  if st == "installing" then return end
  if st == "analyzing" or st == "wait" then
    if act == "b" then App.pop() end
    return
  end
  local notes = (st == "done" and Manager.job and Manager.job.result) or (st == "report" and self.report) or nil
  if act == "y" and notes and Manager.has_notes(notes) then
    App.push("upd_notes", { to = notes.version or notes.to, to_label = notes.label or notes.version_label or notes.to_label,
      description = notes.description, changes = notes.changes, fixes = notes.fixes })
    return
  end
  if st == "done" then
    if act == "x" and self.left then
      self.pkg_handled = false
      self:ask_delete()
      return
    end
    -- os arquivos do hub foram trocados: continuar usando o app sem reiniciar
    -- faz ele fechar com erro ao abrir uma tela ou tarefa nova
    if act == "a" or act == "b" then require("ui.screens.updmgr").restart_app() end
    return
  end
  if act == "b" then App.pop()
  elseif act == "a" and st == "report" and #self.report.problems == 0 then self:confirm() end
end

return S
