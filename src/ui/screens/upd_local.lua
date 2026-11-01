-- =============================================================================
--  Atualizacoes > Atualizacao local
--  Pacotes da pasta r36sporthub/update: nome, formato, tamanho e versao
--  (lida do manifesto em segundo plano). A abre a analise do pacote.
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Manager = require("core.updater.manager")
local Folder = require("core.updater.folder")
local Formats = require("core.updater.formats")
local Rules = require("core.updater.rules")
local Clock = require("core.clock")
local C = require("config")

local S = {}
local RH, TOP, VISIBLE = 50, 50, 7

function S:enter()
  self.sel, self.scroll = 1, 0
  self.probe = {}
  self:load()
end

function S:resume() self:load() end

function S:load()
  Folder.ensure_dir()
  self.list = Folder.scan()
  if self.sel > #self.list then self.sel = math.max(1, #self.list) end
  self.probing = false
  self.want_probe = #self.list > 0
end

function S:update()
  if self.want_probe and not Manager.busy() then
    self.want_probe = false
    local pk = {}
    for _, p in ipairs(self.list) do pk[#pk + 1] = { path = p.path } end
    self.probing = Manager.start("probe", { packages = pk }, function(j)
      self.probing = false
      if j.state == "done" and j.result and j.result.probe then self.probe = j.result.probe end
    end)
  end
end

local function status_of(self, p)
  local r = self.probe[p.path]
  if not r then return self.probing and L("analisando...") or "", T.c.faint end
  if r.error == "no_tool" then return L("sem ferramenta para ") .. Formats.LABEL[r.format], T.c.red end
  if r.error == "format" then return L("não é ZIP, 7Z ou RAR válido"), T.c.red end
  if r.error == "list" then return L("arquivo danificado ou incompleto"), T.c.red end
  if r.error == "manifest" then return L("manifesto inválido"), T.c.red end
  if r.error then return L("não foi possível ler"), T.c.red end
  if r.mode == "manifest" then
    local v = r.label or r.version
    local cmp = Rules.compare(r.version, C.VERSION_NUM)
    local extra = cmp > 0 and L("  (mais nova)") or (cmp == 0 and L("  (mesma versão)") or L("  (mais antiga)"))
    return L("versão ") .. tostring(v) .. extra, cmp > 0 and T.c.green or T.c.yellow
  end
  if r.mode == "full" then return L("pacote completo sem manifesto (identificação parcial)"), T.c.yellow end
  return L("estrutura desconhecida"), T.c.red
end

function S:draw()
  G.header(L("Atualização local"), #self.list .. L(" pacote(s)"))
  if #self.list == 0 then
    G.panel(40, 110, T.W - 80, 190, { bg = T.c.bg1 })
    G.text(T.f.h3, L("Nenhum pacote na pasta update"), 40, 134, T.c.text, "center", T.W - 80)
    G.text(T.f.small, L("Copie o pacote (.zip, .7z ou .rar) para a pasta abaixo pelo FTP ou pelo gerenciador de arquivos e volte aqui:"),
      60, 170, T.c.dim, "center", T.W - 120)
    G.text(T.f.bodyb, Folder.DIR, 60, 214, T.c.accent2, "center", T.W - 120)
    G.text(T.f.small, L("Nada é instalado só por estar na pasta."), 60, 250, T.c.faint, "center", T.W - 120)
  end
  for i = self.scroll + 1, math.min(#self.list, self.scroll + VISIBLE) do
    local p = self.list[i]
    local y = TOP + (i - self.scroll - 1) * RH
    local on = i == self.sel
    G.rect(12, y, T.W - 24, RH - 4, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(12, y, T.W - 24, RH - 4, T.c.accent, 5, 2) end
    local tw = G.tag(Folder.format_label(p.format), 22, y + 14, T.c.accent2, T.c.bg0, T.f.pix8)
    local nx = 22 + tw + 10
    local right = U.format_bytes(p.size)
    local ft, fs, ty, sy = G.row_fonts(RH - 4, 4, 25)
    local rw = ft:getWidth(right)
    G.text_fit(ft, p.name, nx, y + ty, T.W - 50 - nx - rw, on and T.c.text or T.c.dim)
    G.text(ft, right, T.W - 26 - rw, y + ty, T.c.text)
    local st, col = status_of(self, p)
    G.text_fit(fs, Clock.datetime(p.mtime, true) .. (st ~= "" and ("  •  " .. st) or ""), nx, y + sy, T.W - 40 - nx, col)
  end
  local hints = { { "dpad", L("Navegar") } }
  if #self.list > 0 then hints[#hints + 1] = { "a", L("Analisar") } end
  hints[#hints + 1] = { "y", L("Atualizar lista") }
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:action(act)
  local n = #self.list
  if act == "b" then App.pop(); return end
  if act == "y" then self.probe = {}; self:load(); App.toast(L("Lista atualizada."), "info"); return end
  if n == 0 then return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "a" then
    if Manager.busy() and Manager.job.op ~= "probe" then App.toast(L("Já existe uma operação de atualização em andamento."), "warn"); return end
    local p = self.list[self.sel]
    App.push("upd_pkg", { path = p.path, name = p.name, size = p.size, format = p.format, origin = "local" })
  end
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
end

return S
