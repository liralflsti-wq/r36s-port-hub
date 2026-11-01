-- =============================================================================
--  Configuracoes > Downloads e atualizacoes > Atualizacoes
--  Atualizacao local (pasta update), via rede, versao atual, historico e backups.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Manager = require("core.updater.manager")
local Folder = require("core.updater.folder")
local Backup = require("core.updater.backup")
local History = require("core.updater.history")
local Update = require("core.update")
local Clock = require("core.clock")

local S = {}

local ITEMS = {
  { id = "local", label = L("Atualização local") },
  { id = "net", label = L("Atualização via rede") },
  { id = "version", label = L("Versão atual") },
  { id = "history", label = L("Histórico de atualizações") },
  { id = "backups", label = L("Gerenciar backups") },
}

local DESC = {
  ["local"] = L("Instala um pacote .zip, .7z ou .rar colocado na pasta update do R36S PORT HUB (pelo FTP ou pelo gerenciador de arquivos). Nada é instalado sem confirmação."),
  net = L("Verifica a fonte oficial configurada, mostra a versão disponível, baixa o pacote para a pasta update e instala depois da sua confirmação."),
  version = L("Versão instalada do R36S PORT HUB e detalhes da última atualização."),
  history = L("Versão anterior e nova, data, origem, pacote e resultado de cada atualização."),
  backups = L("Cópias dos arquivos trocados em cada atualização (as 3 mais recentes). Restaure ou apague, sempre com confirmação."),
}

function S:enter()
  self.sel = 1
  self:refresh()
  self.wait = 2   -- testa as ferramentas depois do primeiro quadro
end

function S:resume() self:refresh() end

function S:refresh()
  Folder.ensure_dir()
  self.pkgs = Folder.scan()
  self.backups = Backup.list(C.APP_DIR)
  self.hist = History.recent()
end

function S:update()
  if self.wait then
    self.wait = self.wait - 1
    if self.wait <= 0 then self.wait = nil; Manager.tools(); self.fmt_ok, self.fmt_no = Manager.formats_text() end
  end
end

local function value_of(self, id)
  if id == "local" then return #self.pkgs .. L(" pacote(s)") end
  if id == "net" then return Update.source_url() and L("configurada") or L("sem link") end
  if id == "version" then return C.VERSION end
  if id == "history" then return tostring(#self.hist) end
  if id == "backups" then return #self.backups .. " / " .. Backup.KEEP end
end

function S:draw()
  G.header(L("Atualizações"), L("Versão atual: ") .. C.VERSION)
  -- texto maior: os itens crescem junto (ha espaco livre abaixo da lista)
  local gb = T.f.bodyb:getHeight() - T.base_font(T.f.bodyb):getHeight()
  local gs = T.f.small:getHeight() - T.base_font(T.f.small):getHeight()
  local x, y, w, rh = 12, 50, 260, 40 + gb + gs
  for i, it in ipairs(ITEMS) do
    local on = i == self.sel
    G.rect(x, y, w, rh - 4, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(x, y, w, rh - 4, T.c.accent, 5, 2); G.rect(x, y + 8, 3, rh - 20, T.c.accent, 1) end
    G.text_fit(T.f.bodyb, it.label, x + 12, y + 3, w - 24, on and T.c.text or T.c.dim)
    G.text_fit(T.f.small, value_of(self, it.id) or "", x + 12, y + 20 + gb, w - 24, T.c.accent2)
    y = y + rh
  end

  local px, py, pw, ph = 284, 50, T.W - 296, 390
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  local it = ITEMS[self.sel]
  G.text(T.f.pix8, U.upper(it.label), px + 14, py + 14, T.c.accent2)
  local d = DESC[it.id]
  G.text(T.f.small, d, px + 14, py + 34, T.c.dim, "left", pw - 28)
  local cy = py + 40 + #G.wrap(T.f.small, d, pw - 28) * T.f.small:getHeight() + 10
  G.rect(px + 12, cy, pw - 24, 1, T.c.line)
  cy = cy + 10
  local function row(k, v, c)
    G.text_fit(T.f.small, k, px + 14, cy, 110, T.c.faint)
    G.text_fit(T.f.bodyb, v, px + 130, cy - 2, pw - 144, c or T.c.text)
    cy = cy + 20
  end
  row(L("Instalada"), select(2, Manager.disk_version()), T.c.accent2)
  row(L("Pasta update"), "r36sporthub/update")
  row(L("Formatos"), self.fmt_ok and (self.fmt_ok ~= "" and self.fmt_ok or L("nenhum")) or L("Verificando..."),
    self.fmt_ok == "" and T.c.red or nil)
  if self.fmt_no and self.fmt_no ~= "" then row(L("Indisponíveis"), self.fmt_no, T.c.orange) end
  row(L("Backups"), #self.backups .. " / " .. Backup.KEEP)
  local last = self.hist[1]
  if last then
    row(L("Última"), (last.to or "?") .. "  •  " .. Clock.datetime(last.time, true),
      last.result == "ok" and T.c.green or T.c.orange)
  end
  if Manager.restart_needed then
    cy = cy + 6
    local msg = L("Atualização instalada. Reinicie o app para usar a versão ") .. tostring(Manager.restart_needed.to_label or Manager.restart_needed.to) .. "."
    G.text(T.f.small, msg, px + 14, cy, T.c.yellow, "left", pw - 28)
  end
  if not Manager.layout_ok() then
    G.text(T.f.small, L("Atualizações bloqueadas: a pasta do hub não está em ports/r36sporthub."), px + 14, py + ph - 40, T.c.red, "left", pw - 28)
  end
  local hints = { { "dpad", L("Navegar") }, { "a", L("Abrir") }, { "b", L("Voltar") } }
  if Manager.restart_needed then table.insert(hints, 3, { "x", L("Reiniciar o app") }) end
  G.hints(hints)
end

--- fecha e abre o hub de novo (o lancador abre a versao nova)
function S.restart_app()
  os.execute("mkdir -p " .. U.shq(C.APP_DIR .. "/conf") .. " 2>/dev/null")
  U.write_file(C.APP_DIR .. "/conf/.restart_app", "1\n")
  App.quit(true)
end

local function show_version(self)
  local last
  for _, h in ipairs(self.hist) do if h.result == "ok" then last = h; break end end
  local body = L("Versão instalada: ") .. C.VERSION .. L("\nNúmero da versão: ") .. C.VERSION_NUM
    .. L("\nPasta do hub: ") .. C.APP_DIR
  if last then
    body = body .. L("\n\nÚltima atualização: ") .. tostring(last.from) .. " → " .. tostring(last.to)
      .. "\n" .. Clock.datetime(last.time, true) .. "  •  " .. (last.package or "")
  end
  App.show_dialog({ title = L("Versão atual"), kind = "info", body = body })
end

function S:action(act)
  local id = ITEMS[self.sel].id
  if act == "up" then self.sel = (self.sel - 2) % #ITEMS + 1
  elseif act == "down" then self.sel = self.sel % #ITEMS + 1
  elseif act == "b" then App.pop()
  elseif act == "x" and Manager.restart_needed then S.restart_app()
  elseif act == "a" then
    if id == "local" then App.push("upd_local")
    elseif id == "net" then App.push("update")
    elseif id == "version" then show_version(self)
    elseif id == "history" then App.push("upd_history")
    elseif id == "backups" then App.push("upd_backups")
    end
  end
end

return S
