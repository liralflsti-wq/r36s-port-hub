-- =============================================================================
--  Otimizador do microSD: executa uma operacao em segundo plano (progresso
--  real) e mostra o resultado. B cancela enquanto roda e volta depois.
--  Modo "fsck_plan": lista cada particao com o que pode (ou nao) ser
--  verificado; so particoes DESMONTADAS podem ser verificadas (somente
--  leitura, depois de confirmar). Reparos nunca sao feitos aqui.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local M = require("core.sdmaint")
local lg = love.graphics

local S = {}

local VIS = 15
local LH = 24

function S:enter(p)
  self.p = p
  self.title = p.title
  self.lines, self.top = {}, 0
  self.state = "running"
  self.t0 = love.timer.getTime()
  if p.job.op == "fsck_plan" then
    self:fsck_plan()
  else
    self:start(p.job)
  end
end

function S:start(job)
  self.seq = (self.seq or 0) + 1
  local tag = "hub_sdm_" .. tostring(os.time()) .. "_" .. self.seq
  self.out = love.thread.getChannel(tag .. "_o"); self.out:clear()
  self.ctl = love.thread.getChannel(tag .. "_c"); self.ctl:clear()
  job.pidfile = os.tmpname()
  self.pidfile = job.pidfile
  self.th = love.thread.newThread("threads/sdmaint_thread.lua")
  self.th:start(tag .. "_o", tag .. "_c", job)
  self.state, self.prog = "running", nil
  self.running_op = job.op
  self.t0 = love.timer.getTime()
end

function S:cancel()
  if self.state ~= "running" or not self.ctl then return end
  self.ctl:push("cancel")
  local pid = U.trim(U.read_file(self.pidfile or "") or "")
  if pid:match("^%d+$") then os.execute("kill " .. pid .. " 2>/dev/null") end
  self.cancelling = true
end

function S:leave()
  if self.state == "running" then self:cancel() end
end

function S:try_leave()
  if self.state == "running" then
    if self.running_op == "fsck" or self.running_op == "trim" or self.running_op == "sync" or self.running_op == "cleantmp" then
      App.toast(L("Aguarde a operação terminar."), "warn")
      return
    end
    self:cancel()
  end
  App.pop()
end

-- ---------------------------------------------------------------------------
local function add(t, text, color, ind) t[#t + 1] = { text = text, color = color, ind = ind or 0 } end

local function fmt_analyze(r)
  local t = {}
  add(t, L("Somente leitura: nada foi alterado."), "dim")
  for _, p in ipairs(r.parts or {}) do
    add(t, "")
    local use = M.usage(p.mp)
    add(t, p.mp .. "  (" .. p.name .. ")", "accent2")
    if use then
      add(t, L("Ocupado: ") .. U.format_bytes(use.used) .. L("  •  Livre: ") .. U.format_bytes(use.free)
        .. string.format("  •  %d%%", math.floor(use.used / math.max(1, use.used + use.free) * 100 + 0.5)), "text", 1)
    end
    if p.du_failed then add(t, L("Não foi possível somar as pastas (du indisponível ou sem permissão)."), "yellow", 1)
    elseif #p.dirs > 0 then
      add(t, L("Pastas que mais ocupam:"), "dim", 1)
      for _, d in ipairs(p.dirs) do add(t, U.format_bytes(d.size) .. "   " .. d.path, "text", 2) end
    end
    if #p.files > 0 then
      add(t, L("Maiores arquivos (acima de 10 MB):"), "dim", 1)
      for _, f in ipairs(p.files) do add(t, U.format_bytes(f.size) .. "   " .. f.path, "text", 2) end
    elseif not p.du_failed then
      add(t, L("Nenhum arquivo acima de 10 MB."), "faint", 1)
    end
  end
  if r.cancelled then add(t, ""); add(t, L("Análise cancelada: o resultado acima está incompleto."), "yellow") end
  return t
end

local function fmt_dups(r)
  local t = {}
  if r.error == "nohash" then
    add(t, L("Não foi possível comparar: o sistema não tem md5sum nem sha1sum."), "red")
    return t
  end
  if r.cancelled then add(t, L("Busca cancelada antes de terminar."), "yellow"); return t end
  add(t, string.format(L("%d arquivo(s) de 1 MB ou mais analisado(s)  •  comparação: %s"), r.scanned or 0, r.hasher or "?"), "dim")
  add(t, L("Somente leitura: nenhum arquivo foi apagado."), "dim")
  add(t, "")
  if not r.groups or #r.groups == 0 then
    add(t, L("Nenhum arquivo duplicado encontrado."), "green")
    return t
  end
  add(t, string.format(L("%d grupo(s) de arquivos idênticos  •  espaço repetido: %s"), #r.groups, U.format_bytes(r.wasted or 0)), "yellow")
  for i, g in ipairs(r.groups) do
    add(t, "")
    add(t, string.format(L("Grupo %d  •  %d cópias de %s"), i, #g.files, U.format_bytes(g.size)), "accent2")
    for _, f in ipairs(g.files) do
      local name, dir = f.path:match("^(.*)/([^/]+)$")
      add(t, (dir or f.path) .. "   " .. L("em ") .. (name or ""), "text", 1)
    end
  end
  return t
end

local INTEG_TEXT = {
  ro = function(d) return string.format(L("%s (%s) está montada como somente leitura. O sistema costuma fazer isso quando encontra erros."), d.name, d.mp) end,
  mount = function(d) return string.format(L("%s montada em %s (%s)."), d.name, d.mp, d.ro and L("somente leitura") or L("leitura e gravação")) end,
  unmounted = function(d) return string.format(L("%s não está montada."), d.name) end,
  dmesg = function() return L("Registro do sistema (dmesg) não pôde ser lido (sem permissão).") end,
  dmesg_ok = function() return L("Registro do sistema: nenhum erro de leitura/gravação ou do sistema de arquivos deste cartão.") end,
  dmesg_err = function(d) return string.format(L("Registro do sistema: %d mensagem(ns) de erro ligadas ao cartão ou ao sistema de arquivos."), d.count) end,
  notool = function(d) return string.format(L("%s: não verificada, ferramenta ausente (%s)."), d.name, d.tool) end,
  ext_noread = function(d) return string.format(L("%s: estado do ext4 não pôde ser lido (sem permissão)."), d.name) end,
  ext_err = function(d) return string.format(L("%s: o ext4 registrou erros (estado: %s%s)."), d.name, d.state, d.errors and (", " .. d.errors .. L(" erro(s)")) or "") end,
  ext_notclean = function(d)
    if d.mounted then return string.format(L("%s: ext4 marcado como \"não limpo\" (normal enquanto está em uso)."), d.name) end
    return string.format(L("%s: ext4 desmontado marcado como \"não limpo\": foi desligado sem desmontar."), d.name)
  end,
  ext_clean = function(d) return string.format(L("%s: ext4 sem erros registrados (estado: %s)."), d.name, d.state) end,
  exfat_noread = function(d) return string.format(L("%s: indicadores do exFAT não puderam ser lidos (sem permissão)."), d.name) end,
  exfat_media = function(d) return string.format(L("%s: o exFAT registrou FALHA DE MÍDIA (problema físico ou de leitura do cartão)."), d.name) end,
  exfat_dirty = function(d) return string.format(L("%s: exFAT marcado como não desmontado corretamente."), d.name) end,
  exfat_ok = function(d) return string.format(L("%s: exFAT sem registro de falha de mídia."), d.name) end,
  fat_mounted = function(d) return string.format(L("%s: FAT montada; o indicador de erro não é confiável enquanto está em uso."), d.name) end,
  fat_unmounted = function(d) return string.format(L("%s: FAT desmontada; use \"Verificar erros do sistema de arquivos\"."), d.name) end,
}
local LEVEL = { ok = { "OK", "green" }, problem = { L("PROBLEMA"), "red" }, skipped = { L("NÃO VERIFICADO"), "yellow" }, info = { L("INFO"), "accent2" } }

local function fmt_integrity(r)
  local t = {}
  local counts = { ok = 0, problem = 0, skipped = 0, info = 0 }
  for _, it in ipairs(r.items or {}) do counts[it.level] = (counts[it.level] or 0) + 1 end
  if counts.problem > 0 then add(t, string.format(L("%d possível(is) problema(s) encontrado(s)."), counts.problem), "red")
  else add(t, L("Nenhum problema encontrado nas verificações feitas."), "green") end
  if counts.skipped > 0 then add(t, string.format(L("%d verificação(ões) não puderam ser feitas (veja abaixo)."), counts.skipped), "yellow") end
  add(t, L("Somente leitura: nada foi alterado."), "dim")
  add(t, "")
  for _, it in ipairs(r.items or {}) do
    local lv = LEVEL[it.level] or LEVEL.info
    local f = INTEG_TEXT[it.text]
    add(t, "[" .. lv[1] .. "]  " .. (f and f(it.detail or {}) or it.text), lv[2])
    if it.text == "dmesg_err" then
      for _, l in ipairs(it.detail.lines or {}) do add(t, l, "faint", 2) end
    end
  end
  return t
end

local function fmt_trim(r)
  local t = {}
  if r.error == "notool" then add(t, L("A ferramenta fstrim não está instalada no sistema."), "red"); return t end
  for _, p in ipairs(r.parts or {}) do
    if p.ok then add(t, p.mp .. ": " .. (p.bytes and (U.format_bytes(p.bytes) .. L(" informados ao cartão como livres.")) or L("concluído.")), "green")
    elseif p.unsupported then add(t, p.mp .. ": " .. L("o cartão ou o sistema de arquivos não aceita TRIM."), "yellow")
    elseif p.noperm then add(t, p.mp .. ": " .. L("sem permissão de administrador (sudo)."), "yellow")
    else add(t, p.mp .. ": " .. L("falhou.") .. " " .. (p.out or ""), "red") end
  end
  add(t, ""); add(t, L("Nenhum arquivo foi apagado ou alterado."), "dim")
  return t
end

function S:fmt(r)
  if r.error and r.op ~= "dups" and r.op ~= "trim" then
    return { { text = L("A operação falhou: ") .. tostring(r.error), color = "red", ind = 0 } }
  end
  if r.op == "analyze" then return fmt_analyze(r)
  elseif r.op == "dups" then return fmt_dups(r)
  elseif r.op == "integrity" then return fmt_integrity(r)
  elseif r.op == "trim" then return fmt_trim(r)
  elseif r.op == "sync" then
    return { { text = r.ok and L("Dados pendentes gravados no cartão.") or L("O comando sync falhou."), color = r.ok and "green" or "red", ind = 0 } }
  elseif r.op == "cleantmp" then
    if (r.removed or 0) == 0 then return { { text = L("Não havia temporários do hub para limpar."), color = "green", ind = 0 } } end
    return { { text = string.format(L("%d pasta(s) temporária(s) apagada(s)  •  %s liberados."), r.removed, U.format_bytes(r.bytes or 0)), color = "green", ind = 0 } }
  elseif r.op == "fsck" then return self:fmt_fsck(r)
  end
  return {}
end

-- ---------------------------------------------------------------------------
-- fsck: plano por particao
local function pc_help()
  return L("Para corrigir erros, desligue o console, faça backup do cartão e use um computador: no Windows, \"Verificar erros\" nas propriedades da unidade (FAT/exFAT); no Linux, fsck.exfat, fsck.vfat ou e2fsck com a partição desmontada.")
end

function S:fsck_plan()
  self.state = "plan"
  local t = {}
  self.choices = {}
  add(t, L("Verificar exige a partição desmontada. As partições em uso pelo console não são desmontadas por segurança."), "dim")
  add(t, "")
  for _, p in ipairs(self.p.job.parts) do
    local tool, tname = M.fsck_tool(p.fs)
    local fs = M.fs_label(p.fs) or L("desconhecido")
    add(t, p.name .. "  •  " .. fs .. "  •  " .. p.dev, "accent2")
    if not M.FSCK[p.fs or ""] then
      add(t, L("Sem verificação disponível para este sistema de arquivos."), "faint", 1)
    elseif p.mp then
      add(t, L("Não verificada: está montada em ") .. p.mp .. L(". Verificar ou reparar exige o cartão fora do console."), "yellow", 1)
    elseif not tool then
      add(t, L("Não verificada: ferramenta ausente no sistema (") .. tostring(tname) .. ").", "yellow", 1)
    else
      add(t, L("Pode ser verificada agora em modo somente leitura com ") .. tname .. L(". Toque A para escolher."), "green", 1)
      self.choices[#self.choices + 1] = { line = #t, part = p, tool = tool, tname = tname }
    end
  end
  add(t, "")
  add(t, pc_help(), "dim")
  self.lines = t
  self.csel = (#self.choices > 0) and 1 or nil
  self:wrap()
end

function S:fmt_fsck(r)
  local t = {}
  local p = self.fsck_part
  if r.refused == "mounted" then add(t, L("Não executado: a partição foi montada em ") .. tostring(r.mp) .. ".", "yellow")
  elseif r.refused == "notool" then add(t, L("Não executado: ferramenta ausente."), "yellow")
  elseif r.result == "clean" then add(t, L("Nenhum erro encontrado em ") .. p.name .. ".", "green")
  elseif r.result == "errors" then add(t, L("Foram encontrados erros em ") .. p.name .. L(". Nada foi corrigido (modo somente leitura)."), "red")
  elseif r.result == "noperm" then add(t, L("Não executado: sem permissão de administrador (sudo)."), "yellow")
  else add(t, L("A verificação não pôde ser concluída."), "yellow") end
  if r.out and r.out ~= "" then
    add(t, ""); add(t, L("Saída da ferramenta:"), "dim")
    local lines = {}
    for l in r.out:gmatch("[^\n]+") do lines[#lines + 1] = l end
    for i = math.max(1, #lines - 12), #lines do add(t, lines[i], "faint", 1) end
  end
  if r.result == "errors" then add(t, ""); add(t, pc_help(), "dim") end
  return t
end

-- quebra de linhas para a largura da tela
function S:wrap()
  local w = T.W - 56
  local out = {}
  for i, l in ipairs(self.lines) do
    local ind = (l.ind or 0) * 18
    local parts = (l.text == "") and { "" } or G.wrap(T.f.small, I18N.tr(l.text), w - ind)
    for j, s in ipairs(parts) do out[#out + 1] = { text = s, color = l.color, ind = ind, src = i, first = j == 1 } end
  end
  self.wrapped = out
  self.top = 0
end

-- ---------------------------------------------------------------------------
-- relatorio
function S:report(integ)
  local p = self.p
  local c, s = p.card, p.sum
  local R = {}
  local function w(x) R[#R + 1] = x or "" end
  w("R36S PORT HUB " .. C.VERSION .. " - " .. L("Relatório do microSD"))
  w(os.date("%d/%m/%Y %H:%M:%S"))
  w(string.rep("=", 60))
  w(L("CARTÃO"))
  w("  " .. L("Dispositivo: ") .. "/dev/" .. c.dev)
  w("  " .. L("Fabricante: ") .. (c.maker or (c.manfid and string.format("0x%02X", c.manfid)) or L("não informado")))
  w("  " .. L("Modelo: ") .. (c.name or L("não informado")))
  if c.date then w("  " .. L("Data de fabricação informada: ") .. c.date) end
  w("  " .. L("Capacidade total: ") .. (c.bytes and U.format_bytes(c.bytes) or L("não informada")))
  if s and s.used then
    w("  " .. L("Usado: ") .. U.format_bytes(s.used) .. "   " .. L("Livre: ") .. U.format_bytes(s.free)
      .. string.format("   (%d%%)", math.floor((s.frac or 0) * 100 + 0.5)))
    if s.uncounted > 0 then w("  " .. L("(soma das partições montadas; partições desmontadas não entram)")) end
  end
  w("")
  w(L("PARTIÇÕES") .. "  (" .. L("fonte: ") .. tostring(p.src or "?") .. ")")
  for _, x in ipairs(p.parts or {}) do
    w(string.format("  %-14s %-12s %10s   %s", x.name, M.fs_label(x.fs) or "?", x.size and U.format_bytes(x.size) or "?",
      x.mp and (x.mp .. (x.ro and " (ro)" or " (rw)") .. (x.use and string.format("  %s / %s", U.format_bytes(x.use.used), U.format_bytes(x.use.used + x.use.free)) or ""))
      or L("não montada")))
  end
  w("")
  w(L("VERIFICAÇÕES REALIZADAS"))
  local problems, skipped = {}, {}
  for _, it in ipairs(integ.items or {}) do
    local lv = LEVEL[it.level] or LEVEL.info
    local f = INTEG_TEXT[it.text]
    local txt = f and f(it.detail or {}) or it.text
    w("  [" .. lv[1] .. "] " .. txt)
    if it.text == "dmesg_err" then for _, l in ipairs(it.detail.lines or {}) do w("      " .. l) end end
    if it.level == "problem" then problems[#problems + 1] = txt end
    if it.level == "skipped" then skipped[#skipped + 1] = txt end
  end
  local last = M.last
  if last.fsck then w("  " .. L("Verificação de sistema de arquivos (somente leitura): ") .. tostring(last.fsck)) end
  if last.dups then w("  " .. last.dups) end
  if last.trim then w("  " .. last.trim) end
  if last.fsck_problem then problems[#problems + 1] = L("Verificação de sistema de arquivos: ") .. last.fsck_problem end
  w("")
  w(L("PROBLEMAS ENCONTRADOS"))
  if #problems == 0 then w("  " .. L("Nenhum.")) end
  for _, x in ipairs(problems) do w("  - " .. x) end
  w("")
  w(L("OPERAÇÕES INDISPONÍVEIS"))
  local un = {}
  for _, x in ipairs(skipped) do un[#un + 1] = x end
  local disc = M.discard(c.dev)
  if not disc then un[#un + 1] = L("TRIM: o cartão/leitor não informa suporte a descarte.") elseif not M.has("fstrim") then un[#un + 1] = L("TRIM: fstrim não instalado.") end
  for _, x in ipairs(p.parts or {}) do
    if M.FSCK[x.fs or ""] then
      local tool, tname = M.fsck_tool(x.fs)
      if x.mp then un[#un + 1] = string.format(L("Verificação de %s: partição montada (exige o cartão fora do console)."), x.name)
      elseif not tool then un[#un + 1] = string.format(L("Verificação de %s: %s ausente."), x.name, tostring(tname)) end
    end
  end
  if #un == 0 then w("  " .. L("Nenhuma.")) end
  for _, x in ipairs(un) do w("  - " .. x) end
  w("")
  w(L("RECOMENDAÇÕES"))
  if #problems > 0 then w("  - " .. L("Faça backup do cartão o quanto antes.")); w("  - " .. pc_help()) end
  if s and s.frac and s.frac > 0.9 then w("  - " .. L("O cartão está com mais de 90% ocupado: libere espaço para evitar falhas de gravação.")) end
  w("  - " .. L("Desligue o console pelo menu do sistema (ou pelo R36S PORT HUB) antes de remover o cartão ou tirar a bateria."))
  w("  - " .. L("Desfragmentação não é recomendada no microSD (memória flash)."))
  w("")
  w(L("Somente leitura: este relatório não alterou nada no cartão."))
  local text = table.concat(R, "\n") .. "\n"
  -- salva sem sobrescrever
  local dir = C.APP_DIR .. "/relatorios"
  os.execute("mkdir -p " .. U.shq(dir) .. " 2>/dev/null")
  local base = dir .. "/microsd_" .. os.date("%Y%m%d_%H%M%S")
  local path = base .. ".txt"
  local n = 1
  while U.exists(path) do n = n + 1; path = base .. "_" .. n .. ".txt" end
  local ok = U.write_file(path, text)
  return ok and path or nil, text
end

-- ---------------------------------------------------------------------------
function S:update(dt)
  if self.state ~= "running" or not self.out then return end
  while true do
    local m = self.out:pop()
    if not m then break end
    if m.t == "progress" then self.prog = m
    elseif m.t == "done" then
      self.state = "done"
      os.remove(self.pidfile or "")
      local job = self.p.job
      if m.op == "fsck" then
        self.lines = self:fmt(m)
        local words = { clean = L("nenhum erro encontrado"), errors = L("erros encontrados (nada foi corrigido)"),
          noperm = L("não executada (sem permissão)"), failed = L("não concluída"), mounted = L("não executada (partição montada)"),
          notool = L("não executada (ferramenta ausente)") }
        local key = m.result or m.refused
        M.last.fsck = (self.fsck_part and self.fsck_part.name or "?") .. ": " .. (words[key] or tostring(key))
        M.last.fsck_problem = (m.result == "errors") and M.last.fsck or nil
      elseif m.op == "integrity" and job.report then
        local path = self:report(m)
        local t = {}
        if path then
          add(t, L("Relatório salvo em:"), "green"); add(t, path, "text", 1)
          add(t, L("Abra pelo Gerenciador de arquivos ou pelo FTP. Nenhum arquivo existente foi sobrescrito."), "dim")
        else
          add(t, L("Não foi possível salvar o relatório (pasta somente leitura?)."), "red")
        end
        add(t, "")
        for _, l in ipairs(fmt_integrity(m)) do t[#t + 1] = l end
        self.lines = t
      else
        self.lines = self:fmt(m)
        if m.op == "dups" and not m.cancelled and not m.error then
          M.last.dups = string.format(L("Duplicados: %d grupo(s), %s repetidos."), #(m.groups or {}), U.format_bytes(m.wasted or 0))
        elseif m.op == "trim" then
          M.last.trim = L("TRIM executado nesta sessão.")
        end
      end
      self:wrap()
    end
  end
  local e = self.th and self.th:getError()
  if e and self.state == "running" then
    self.state = "done"
    self.lines = { { text = L("A operação falhou: ") .. tostring(e), color = "red", ind = 0 } }
    self:wrap()
  end
end

function S:action(act)
  if self.state == "running" then
    if act == "b" then self:try_leave() end
    return
  end
  local n = #(self.wrapped or {})
  local maxtop = math.max(0, n - VIS)
  if act == "b" then
    if self.state == "done" and self.p.job.op == "fsck_plan" then self:fsck_plan(); return end
    App.pop(); return
  end
  if self.state == "plan" and self.csel then
    if act == "up" then self.csel = (self.csel - 2) % #self.choices + 1; self:scroll_to_choice(); return
    elseif act == "down" then self.csel = self.csel % #self.choices + 1; self:scroll_to_choice(); return
    elseif act == "a" then
      local ch = self.choices[self.csel]
      App.show_dialog({
        title = L("Verificar ") .. ch.part.name .. "?", kind = "warn",
        body = string.format(L("Executa %s em modo somente leitura (-n) na partição %s (%s), que não está montada. Nada é corrigido nem alterado. Pode levar alguns minutos e precisa de permissão de administrador."),
          ch.tname, ch.part.name, ch.part.dev),
        buttons = {
          { label = L("VERIFICAR"), fn = function()
            self.fsck_part = ch.part
            self:start({ op = "fsck", dev = ch.part.dev, fs = ch.part.fs, tool = ch.tool })
          end },
          { label = L("CANCELAR") },
        },
        sel = 2,
      })
      return
    end
  end
  if act == "up" then self.top = math.max(0, self.top - 1)
  elseif act == "down" then self.top = math.min(maxtop, self.top + 1)
  elseif act == "l1" or act == "left" then self.top = math.max(0, self.top - VIS)
  elseif act == "r1" or act == "right" then self.top = math.min(maxtop, self.top + VIS) end
end

function S:scroll_to_choice()
  local ch = self.choices[self.csel]
  for i, w in ipairs(self.wrapped) do
    if w.src == ch.line and w.first then
      if i <= self.top then self.top = math.max(0, i - 2) end
      if i > self.top + VIS then self.top = i - VIS + 1 end
    end
  end
end

function S:draw()
  G.header(self.title or "")
  local x, w = 12, T.W - 24
  if self.state == "running" then
    G.panel(x, 140, w, 170, { bg = T.c.bg1 })
    local secs = math.floor(love.timer.getTime() - self.t0)
    G.text(T.f.pix16, self.cancelling and L("CANCELANDO...") or L("EM ANDAMENTO..."), x, 162, T.c.yellow, "center", w)
    local pr = self.prog
    local txt = pr and pr.text or ""
    if txt == "hash" then txt = L("Comparando o conteúdo dos arquivos (hash)...") end
    if txt ~= "" then G.text_fit(T.f.small, txt, x + 24, 196, w - 48, T.c.dim) end
    if pr and pr.total and pr.total > 0 and pr.done then
      local f = math.min(1, pr.done / pr.total)
      G.rect(x + 40, 226, w - 80, 10, T.c.bg0, 5)
      G.rect(x + 40, 226, math.max(10, (w - 80) * f), 10, T.c.accent2, 5)
      local lbl = (self.running_op == "dups") and (U.format_bytes(pr.done) .. " / " .. U.format_bytes(pr.total))
        or string.format("%d%%", math.floor(f * 100))
      G.text(T.f.small, lbl, x, 244, T.c.text, "center", w)
    else
      G.progress_busy(x + 40, 226, w - 80, 6, App.t, T.c.accent2)
      if pr and pr.done and pr.done > 0 then G.text(T.f.small, string.format(L("%d arquivo(s) encontrado(s)"), pr.done), x, 244, T.c.text, "center", w) end
    end
    G.text(T.f.small, string.format(L("Tempo: %d s"), secs), x, 270, T.c.faint, "center", w)
    local canb = not (self.running_op == "fsck" or self.running_op == "trim" or self.running_op == "sync" or self.running_op == "cleantmp")
    G.hints(canb and { { "b", L("Cancelar") } } or {})
    return
  end

  G.panel(x, 50, w, 384, { bg = T.c.bg1 })
  local wr = self.wrapped or {}
  local cur_line = self.state == "plan" and self.csel and self.choices[self.csel].line
  for i = self.top + 1, math.min(#wr, self.top + VIS) do
    local l = wr[i]
    local y = 58 + (i - self.top - 1) * LH
    if cur_line and l.src == cur_line then
      G.rect(x + 6, y - 2, w - 12, LH, T.c.bg3, 5)
      G.frame(x + 6, y - 2, w - 12, LH, T.c.accent, 5, 2)
    end
    G.text(T.f.small, l.text, x + 16 + l.ind, y + 3, T.c[l.color or "text"] or T.c.text)
  end
  if #wr > VIS then
    local track = 370
    local h = math.max(18, track * VIS / #wr)
    local yy = 56 + (track - h) * (self.top / math.max(1, #wr - VIS))
    G.rect(T.W - 18, yy, 3, h, T.c.accent2, 1, 0.7)
  end
  local h = { { "dpad", L("Rolar") } }
  if self.state == "plan" and self.csel then h = { { "dpad", L("Escolher") }, { "a", L("Verificar") } } end
  h[#h + 1] = { "b", L("Voltar") }
  G.hints(h)
end

return S
