-- =============================================================================
--  Atualizacoes > Atualizacao via rede
--  Verifica a fonte oficial configurada (update_url.txt ou C.UPDATE_URL),
--  mostra versao instalada e disponivel, baixa o pacote para a pasta update
--  (progresso real) e abre a analise/instalacao do Gerenciador de atualizacoes.
--  A: verificar / baixar | B: voltar (ou cancelar o download)
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Update = require("core.update")
local Manager = require("core.updater.manager")
local Folder = require("core.updater.folder")

local S = {}

function S:enter()
  if not Manager.busy() then Update.state = "idle" end
  self.dl = nil
end

local function downloading() return Manager.busy() and Manager.job.op == "download" end

function S:draw()
  G.header(L("Atualização via rede"), L("Versão atual: ") .. C.VERSION)
  local x, y, w, h = 12, 50, T.W - 24, 386
  G.panel(x, y, w, h, { bg = T.c.bg1 })
  local st = Update.state
  local src = Update.source_url()
  local function center(font, text, yy, c) G.text(font, text, x + 20, yy, c, "center", w - 40) end

  G.text_fit(T.f.small, L("Fonte: ") .. (src or L("nenhum link configurado ainda")), x + 16, y + 12, w - 32, src and T.c.dim or T.c.faint)
  local hints = { { "b", L("Voltar") } }

  if downloading() then
    local j = Manager.job
    center(T.f.pix16, L("BAIXANDO..."), y + 90, T.c.yellow)
    center(T.f.body, Manager.PHASE[j.phase or "download"] or "", y + 124, T.c.text)
    local frac = (j.total and j.total > 0) and math.min(1, j.done / j.total) or nil
    if frac then G.progress(x + 60, y + 154, w - 120, 12, frac, T.c.accent2)
    else G.progress_busy(x + 60, y + 154, w - 120, 12, App.t, T.c.accent2) end
    local info = U.format_bytes(j.done) .. (j.total and (L(" de ") .. U.format_bytes(j.total)) or "")
      .. (frac and string.format("  (%d%%)", math.floor(frac * 100)) or "")
      .. ((j.speed or 0) > 0 and ("  •  " .. U.format_speed(j.speed)) or "")
    center(T.f.small, info, y + 176, T.c.dim)
    center(T.f.small, L("O pacote vai para a pasta update. Nada é instalado sem a sua confirmação."), y + 220, T.c.faint)
    hints = j.phase == "download" and { { "b", L("Cancelar download") } } or {}
  elseif self.dl_error then
    center(T.f.pix16, L("FALHA NO DOWNLOAD"), y + 100, T.c.red)
    center(T.f.body, self.dl_error, y + 140, T.c.text)
    center(T.f.small, L("A versão atual continua instalada e funcionando."), y + 210, T.c.dim)
    table.insert(hints, 1, { "a", L("Tentar de novo") })
  elseif st == "idle" then
    center(T.f.pix16, L("VERSÃO ") .. C.VERSION, y + 110, T.c.accent2)
    center(T.f.body, L("Pressione A para verificar se existe uma versão mais nova do R36S PORT HUB.\nNada é baixado ou instalado sem a sua confirmação."), y + 150, T.c.dim)
    table.insert(hints, 1, { "a", L("Verificar agora") })
  elseif st == "none" then
    center(T.f.pix16, L("SEM LINK DE ATUALIZAÇÃO"), y + 90, T.c.yellow)
    center(T.f.body, L("A fonte oficial das atualizações ainda não foi configurada.\n")
      .. L("Para ativar, coloque o link do repositório do GitHub (com Releases) ou de um arquivo JSON de versão em:"), y + 126, T.c.dim)
    center(T.f.bodyb, C.APP_DIR .. "/update_url.txt", y + 190, T.c.accent2)
    center(T.f.small, L("Enquanto isso, use a Atualização local com o pacote na pasta update."), y + 222, T.c.faint)
    table.insert(hints, 1, { "a", L("Verificar de novo") })
  elseif st == "checking" then
    center(T.f.pix16, L("VERIFICANDO..."), y + 110, T.c.yellow)
    G.progress_busy(x + 80, y + 146, w - 160, 8, App.t, T.c.yellow)
  elseif st == "uptodate" then
    center(T.f.pix16, L("SISTEMA ATUALIZADO"), y + 110, T.c.green)
    center(T.f.body, L("Você já está usando a versão mais recente (") .. C.VERSION .. L(").\nÚltima versão publicada: ") .. Update.info.version .. ".", y + 150, T.c.dim)
    table.insert(hints, 1, { "a", L("Verificar de novo") })
  elseif st == "available" then
    local i = Update.info
    center(T.f.pix16, L("NOVA VERSÃO DISPONÍVEL"), y + 50, T.c.accent)
    center(T.f.h2, C.VERSION .. "  →  " .. i.version, y + 80, T.c.text)
    center(T.f.small, i.size and (L("Tamanho do download: ") .. U.format_bytes(i.size)) or L("Tamanho do download: informado ao baixar"), y + 112, T.c.dim)
    local notes = (i.notes or ""):gsub("\r", "")
    if notes ~= "" then
      G.text(T.f.pix8, L("NOVIDADES"), x + 24, y + 140, T.c.accent2)
      local lines = G.wrap(T.f.small, notes, w - 48)
      for k = 1, math.min(10, #lines) do
        G.text(T.f.small, lines[k] .. ((k == 10 and #lines > 10) and " …" or ""), x + 24, y + 156 + (k - 1) * 15, T.c.text)
      end
    end
    G.text(T.f.small, L("Depois do download o pacote é conferido e você confirma a instalação."), x + 16, y + h - 26, T.c.faint, "center", w - 32)
    table.insert(hints, 1, { "a", L("Baixar") })
  elseif st == "error" then
    center(T.f.pix16, L("NÃO FOI POSSÍVEL VERIFICAR"), y + 100, T.c.red)
    center(T.f.body, Update.error or L("Erro desconhecido."), y + 140, T.c.text)
    table.insert(hints, 1, { "a", L("Tentar de novo") })
  end
  G.hints(hints)
end

function S:download()
  if Manager.busy() then App.toast(L("Já existe uma operação de atualização em andamento."), "warn"); return end
  Folder.ensure_dir()
  local i = Update.info
  local name = Update.download_name()
  local dest = Folder.DIR .. "/" .. name
  self.dl_error = nil
  local ok, why = Manager.start("download", { url = i.url, size = i.size or 0, sha256 = i.sha256 or "", dest = dest }, function(j)
    if j.state == "done" then
      App.push("upd_pkg", { path = dest, name = name, size = U.file_size(dest), format = require("core.updater.formats").detect_magic(dest), origin = "rede" })
    elseif j.state == "error" then
      self.dl_error = Manager.message(j.error_code, j.detail)
    end
  end)
  if not ok then App.toast(why, "error") end
end

function S:action(act)
  if downloading() then
    if act == "b" then Manager.cancel() end
    return
  end
  if act == "b" then App.pop(); return end
  if act ~= "a" then return end
  local st = Update.state
  if self.dl_error then self.dl_error = nil; self:download(); return end
  if st == "idle" or st == "none" or st == "uptodate" or st == "error" then
    Update.check()
  elseif st == "available" then
    self:download()
  end
end

return S
