-- =============================================================================
--  Configuracoes > Downloads e atualizacoes > Gerenciar PortMaster
--  Esquerda: estado real da instalacao e do console. Direita: operacoes.
--  As operacoes rodam em segundo plano (aparecem na Central de Downloads);
--  confirmacoes aparecem em qualquer tela. D-pad navega, A confirma, B volta.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local PM = require("core.pmmanager")
local Clock = require("core.clock")

local S = {}

local ITEMS = {
  { id = "install", label = L("Instalar PortMaster"), sub = L("Versão estável oficial, conferida antes de extrair") },
  { id = "update", label = L("Atualizar PortMaster"), sub = L("Com backup; preserva ports, saves e configurações") },
  { id = "verify", label = L("Verificar instalação"), sub = L("Arquivos, permissões, dependências e versão") },
  { id = "repair", label = L("Reparar PortMaster"), sub = L("Restaura só arquivos oficiais ausentes ou alterados") },
  { id = "runtimes", label = L("Verificar runtimes"), sub = L("Usa o atualizador de runtimes do hub") },
  { id = "history", label = L("Histórico de operações"), sub = L("Data, versões, fonte e resultado") },
}

local NA = L("não identificado")

function S:enter()
  self.sel = self.sel or 1
  self.view = "main"
  self:refresh()
end

function S:resume() self:refresh() end

function S:refresh()
  self.q = PM.quick_status()
  self.env = PM.env()
  self.chk = PM.last_check()
  self.rt = PM.runtimes_state()
end

-- ---------------------------------------------------------------------------
-- valores da tela principal (todos de verificacoes reais)
local function status_text(q)
  if q.state == "installed" then return L("Instalado"), T.c.green end
  if q.state == "incomplete" then return L("Instalação incompleta"), T.c.yellow end
  return L("Não instalado"), T.c.red
end

local function update_text(q, chk)
  if q.state == "missing" then return "—", T.c.faint end
  if not chk or not chk.stable or not q.version then return L("Não verificado"), T.c.faint end
  local c = require("core.pmcore").vcmp(q.version, chk.stable)
  if c == nil then return L("Não verificado"), T.c.faint end
  if c < 0 then return L("Disponível"), T.c.accent2 end
  return L("Atualizado"), T.c.green
end

local function rt_text(st)
  if st == "ok" then return L("Íntegros"), T.c.green end
  if st == "incomplete" then return L("Incompletos"), T.c.yellow end
  return L("Verificação necessária"), T.c.faint
end

-- ---------------------------------------------------------------------------
-- dialogos de confirmacao (chamados de qualquer tela pelo main.lua)
local function sz(n) return n and U.format_bytes(n) or L("não informado pelo servidor") end
local function checks(c)
  if c.sha256 and c.md5 then return "sha256 + md5" end
  return c.sha256 and "sha256" or (c.md5 and "md5" or "—")
end

function S.confirm_dialog(app, c)
  local d = { kind = "warn", sel = 2, cancel = function() PM.answer(false) end }
  local yes = function() PM.answer(true) end
  if c.kind == "install" then
    d.title = L("Instalar o PortMaster?")
    d.body = L("Versão estável: ") .. c.version .. "\n" .. L("Download: ") .. sz(c.size) .. "   •   " .. L("Conferência: ") .. checks(c)
      .. "\n" .. L("Destino: ") .. c.dest .. "\n" .. L("Iniciador: ") .. c.launcher
      .. "\n\n" .. L("O pacote é baixado, conferido e extraído; nenhum script dele é executado. Depois, reinicie a lista (Sair > Reiniciar lista) para o PortMaster aparecer em Ferramentas.")
    d.buttons = { { label = L("INSTALAR"), fn = yes }, { label = L("CANCELAR"), fn = d.cancel } }
  elseif c.kind == "update" then
    d.title = L("Atualizar o PortMaster?")
    d.body = (c.from or L("versão desconhecida")) .. "  →  " .. c.to .. L("  (estável)") .. "\n"
      .. L("Download: ") .. sz(c.size) .. "   •   " .. L("Conferência: ") .. checks(c) .. "\n" .. L("Pasta: ") .. c.dest
      .. "\n\n" .. string.format(L("Preservados: ports, saves, configurações (config/), temas, autoinstall e %d runtime(s) em libs/. Os arquivos que mudarem ganham backup antes; se algo falhar, o backup é restaurado e conferido."), c.libs or 0)
    d.buttons = { { label = L("ATUALIZAR"), fn = yes }, { label = L("CANCELAR"), fn = d.cancel } }
  elseif c.kind == "repair_download" then
    d.title = L("Baixar o pacote de referência?")
    d.kind = "info"
    d.body = string.format(L("Para reparar, o hub baixa o pacote oficial da versão instalada (%s, %s, conferência: %s) e compara arquivo por arquivo (md5).\n\nNada é alterado antes de você ver a lista do que será restaurado."),
      c.version, sz(c.size), checks(c))
    d.buttons = { { label = L("BAIXAR E COMPARAR"), fn = yes }, { label = L("CANCELAR"), fn = d.cancel } }
  elseif c.kind == "repair" then
    d.title = L("Reparar o PortMaster?")
    local items = {}
    for i, n in ipairs(c.items or {}) do
      if i > 5 then items[#items + 1] = string.format(L("… e mais %d"), #c.items - 5); break end
      items[#items + 1] = n
    end
    d.body = string.format(L("Ausentes: %d   •   Diferentes do oficial: %d"), c.missing or 0, c.changed or 0)
      .. (c.perms and ("\n" .. L("As permissões também serão corrigidas.")) or "")
      .. (#items > 0 and ("\n" .. table.concat(items, "\n")) or "")
      .. "\n\n" .. L("Os arquivos diferentes ganham backup antes. Configurações, ports e runtimes não são tocados.")
    d.buttons = { { label = L("REPARAR"), fn = yes }, { label = L("CANCELAR"), fn = d.cancel } }
  else
    return
  end
  app.show_dialog(d)
end

-- ---------------------------------------------------------------------------
-- resultado (main.lua chama quando a operacao termina)
local function add(t, text, color, ind) t[#t + 1] = { text = text, color = color, ind = ind or 0 } end

local function short(dir, p)
  local base = (dir or ""):match("^(.*)/[^/]+$") or ""
  if base ~= "" and p:sub(1, #base + 1) == base .. "/" then return p:sub(#base + 2) end
  return p
end

function S.verify_lines(s)
  local t = {}
  if s.installed == false then
    add(t, L("O PortMaster não foi encontrado neste console."), "red")
    add(t, L("Pastas verificadas: /opt/system/Tools/PortMaster, /roms/ports/PortMaster, /opt/tools/PortMaster e a pasta informada pelo PortMaster."), "dim")
    return t
  end
  local ins, r = s.inspect or {}, s.result or {}
  local cl = {}
  for _, c in ipairs(s.classes or {}) do cl[#cl + 1] = PM.CLASS[c] and PM.CLASS[c] or { c, "text" } end
  for _, c in ipairs(cl) do add(t, c[1], c[2]) end
  add(t, "")
  add(t, L("Pasta: ") .. tostring(s.dir), "text")
  add(t, L("Versão instalada: ") .. (s.version or L("desconhecida")), "text")
  add(t, L("Iniciador: ") .. tostring(s.launcher or "—"), "text")
  add(t, L("Sistema de arquivos: ") .. (ins.fs and ins.fs ~= "" and ins.fs or NA)
    .. (ins.posix and L("  (com permissões Unix)") or L("  (sem permissões Unix: permissões não se aplicam)")), "dim")
  add(t, string.format(L("Runtimes em libs/: %d"), ins.libs or 0), "dim")
  if r.method == "manifest" then
    add(t, string.format(L("Método: md5 de %d arquivos, gravados pelo hub a partir do pacote oficial desta versão."), r.files or 0), "dim")
  elseif r.method == "download" then
    add(t, string.format(L("Método: md5 de %d arquivos comparados com o pacote oficial desta versão (baixado e conferido)."), r.files or 0), "dim")
  else
    add(t, L("Método: arquivos essenciais. Sem referência completa desta versão, arquivos alterados não são detectados (use X: verificação completa)."), "yellow")
  end
  if r.update == "available" then add(t, L("Nova versão estável: ") .. tostring(r.stable), "accent2")
  elseif r.update == "current" then add(t, L("Versão estável mais recente: ") .. tostring(r.stable) .. L(" (instalada)"), "green")
  else add(t, L("Atualização: não verificada (sem conexão com a fonte oficial)."), "faint") end
  local function list(title, items, color)
    if not items or #items == 0 then return end
    add(t, "")
    add(t, title .. " (" .. #items .. ")", color)
    for i, f in ipairs(items) do
      if i > 30 then add(t, string.format(L("… e mais %d"), #items - 30), "faint", 1); break end
      add(t, short(s.dir, f), "text", 1)
    end
  end
  list(L("Arquivos essenciais ausentes"), ins.missing, "red")
  list(L("Arquivos oficiais ausentes"), r.missing, "red")
  list(L("Diferentes do pacote oficial (não significa corrompido)"), r.changed, "yellow")
  list(L("Sem permissão de execução"), ins.noexec, "yellow")
  list(L("Programas do sistema ausentes"), ins.deps, "yellow")
  add(t, "")
  add(t, L("Somente leitura: nada foi alterado."), "dim")
  return t
end

function S.on_finished(app, j)
  local s = j.summary or {}
  local cur = app.current()
  local here = cur and cur.name == "pmmanager"
  if here then cur:refresh() end
  local rtbtn = { label = L("VERIFICAR RUNTIMES"), fn = function() app.update_runtimes() end }
  if j.result == "error" then
    local body = j.error or L("Erro desconhecido.")
    if j.recovered == true then body = body .. "\n\n" .. L("O backup foi restaurado e conferido (md5): a instalação anterior continua como estava.")
    elseif j.recovered == false then body = body .. "\n\n" .. L("ATENÇÃO: não foi possível confirmar a restauração do backup. Use Verificar instalação.")
    elseif j.op == "install" or j.op == "update" or j.op == "repair" then
      if j.error_code ~= "validate_failed" and j.error_code ~= "preserve_failed" and j.error_code ~= "pending_recovery" then body = body .. "\n\n" .. L("Nenhum arquivo do PortMaster foi alterado.") end
    end
    app.show_dialog({ title = L("Falha: ") .. (PM.OP_LABEL[j.op] or j.op), kind = "error", body = body })
  elseif j.result == "cancelled" then
    app.toast(L("Operação do PortMaster cancelada. Nada foi alterado."), "warn")
  elseif s.op == "install" then
    app.show_dialog({ title = L("PortMaster instalado!"), kind = "ok",
      body = L("Versão ") .. s.version .. L(" em ") .. s.dir .. "\n" .. string.format(L("%d arquivos conferidos (md5) depois da instalação."), s.files or 0)
        .. "\n" .. (s.perms == "ok" and L("Permissões ajustadas como no instalador oficial.") or L("Sistema de arquivos sem permissões Unix: nada a ajustar."))
        .. "\n\n" .. L("Reinicie a lista (Sair > Reiniciar lista) ou o console para o PortMaster aparecer em Ferramentas. O pacote base não traz os runtimes dos ports: use Verificar runtimes."),
      buttons = { { label = "OK" }, rtbtn } })
  elseif s.op == "update" then
    if s.uptodate then
      app.show_dialog({ title = L("O PortMaster já está atualizado"), kind = "ok",
        body = L("Instalada: ") .. tostring(s.version) .. "   •   " .. L("Estável: ") .. tostring(s.stable)
          .. (s.newer_installed and ("\n\n" .. L("A versão instalada é mais nova que a estável (canal beta ou alfa). Nada foi alterado.")) or "") })
    else
      app.show_dialog({ title = L("PortMaster atualizado!"), kind = "ok",
        body = (s.from or "?") .. "  →  " .. s.version .. "\n" .. string.format(L("%d arquivo(s) substituído(s) e %d novo(s), conferidos por md5."), s.replaced or 0, s.added or 0)
          .. "\n" .. L("Conferido: ports, saves, configurações e runtimes continuam iguais.")
          .. (s.gcd and ("\n" .. L("Modo de controle do PortMaster mantido: ") .. s.gcd) or "")
          .. "\n" .. L("Backup dos arquivos antigos: ") .. tostring(s.backup) })
    end
  elseif s.op == "repair" then
    if s.nothing then
      app.show_dialog({ title = L("Nada para reparar"), kind = "ok",
        body = string.format(L("Os %d arquivos do pacote oficial %s conferem com a instalação (md5). Nenhum arquivo foi alterado."), s.files or 0, s.version or "") })
    else
      app.show_dialog({ title = L("PortMaster reparado!"), kind = "ok",
        body = string.format(L("%d arquivo(s) restaurado(s) e %d substituído(s), conferidos por md5."), s.restored or 0, s.replaced or 0)
          .. (s.backup and ("\n" .. L("Backup dos arquivos substituídos: ") .. s.backup) or "") })
    end
  elseif s.op == "verify" then
    if here then cur:show_report(L("Verificar instalação"), S.verify_lines(s), s)
    else app.toast(L("Verificação do PortMaster concluída (veja em Gerenciar PortMaster)."), "info") end
  elseif s.op == "check" then
    if here then cur:refresh() end
  end
end

-- ---------------------------------------------------------------------------
function S:show_report(title, lines, data)
  self.view = "report"
  self.rtitle = title
  self.rdata = data
  local w = T.W - 56
  local out = {}
  for _, l in ipairs(lines) do
    local ind = (l.ind or 0) * 18
    local parts = (l.text == "") and { "" } or G.wrap(T.f.small, I18N.tr(l.text), w - ind)
    for _, s in ipairs(parts) do out[#out + 1] = { text = s, color = l.color, ind = ind } end
  end
  self.wrapped, self.top = out, 0
end

local function hist_lines()
  local t = {}
  local h = PM.history()
  if #h == 0 then add(t, L("Nenhuma operação registrada ainda."), "dim"); return t end
  local RES = { ok = { L("OK"), "green" }, error = { L("FALHOU"), "red" }, cancelled = { L("CANCELADA"), "faint" },
    warn = { L("ATENÇÃO"), "yellow" }, info = { L("INFO"), "accent2" } }
  for _, e in ipairs(h) do
    local r = RES[e.result] or { tostring(e.result), "text" }
    add(t, Clock.datetime(e.time or 0, true) .. "   " .. (PM.OP_LABEL[e.op] or tostring(e.op)) .. "   [" .. r[1] .. "]", r[2])
    if e.from or e.to then
      add(t, L("Versão: ") .. (e.from or "—") .. ((e.to and e.to ~= e.from) and ("  →  " .. e.to) or ""), "text", 1)
    end
    if e.url then add(t, L("Fonte: ") .. e.url, "dim", 1) end
    if e.method then add(t, L("Conferência: ") .. e.method, "dim", 1) end
    if e.note then add(t, e.note, "dim", 1) end
    if e.error then add(t, e.error, "red", 1) end
    add(t, "")
  end
  return t
end

-- ---------------------------------------------------------------------------
function S:open(id)
  if id == "history" then self:show_report(L("Histórico de operações"), hist_lines(), { history = true }); return end
  if id == "runtimes" then self:runtimes(); return end
  if PM.busy() then App.toast(L("Já existe uma operação do PortMaster em andamento."), "warn"); return end
  local q = self.q
  if id == "install" and q.state ~= "missing" then
    App.show_dialog({ title = L("PortMaster já instalado"), kind = "info",
      body = L("Foi encontrada uma instalação em:\n") .. q.dir .. "\n\n" .. L("Ela não será sobrescrita. Use Atualizar para a versão estável mais nova, ou Reparar para restaurar arquivos oficiais.") })
    return
  end
  if (id == "update" or id == "repair") and q.state == "missing" then
    App.show_dialog({ title = L("PortMaster não encontrado"), kind = "info",
      body = L("O PortMaster não foi encontrado neste console. Use Instalar.") })
    return
  end
  local okk, err = PM.start(id)
  if not okk then App.show_dialog({ title = L("Gerenciar PortMaster"), kind = "warn", body = err }) end
end

function S:runtimes()
  if self.q.state == "missing" then
    App.show_dialog({ title = L("Verificar runtimes"), kind = "info", body = L("Instale o PortMaster antes de verificar os runtimes.") })
    return
  end
  local txt = rt_text(self.rt)
  App.show_dialog({
    title = L("Verificar runtimes"), kind = "info",
    body = L("Estado: ") .. txt .. "   •   " .. string.format(L("%d runtime(s) em libs/"), self.env.libs or 0) .. "\n\n"
      .. L("Os runtimes são dos ports (libs/*.squashfs), separados dos arquivos do PortMaster. A verificação usa o atualizador de runtimes do hub: ele confere cada arquivo (md5), mostra o que falta e só baixa depois de você confirmar. Nenhum runtime é removido."),
    buttons = { { label = L("VERIFICAR AGORA"), fn = function() App.update_runtimes() end }, { label = L("VOLTAR") } },
  })
end

function S:action(act)
  if self.view == "report" then
    local n = #(self.wrapped or {})
    local vis = 16
    if act == "b" then self.view = "main"; self:refresh()
    elseif act == "up" then self.top = math.max(0, self.top - 1)
    elseif act == "down" then self.top = math.max(0, math.min(n - vis, self.top + 1))
    elseif act == "left" or act == "l1" then self.top = math.max(0, self.top - vis)
    elseif act == "right" or act == "r1" then self.top = math.max(0, math.min(n - vis, self.top + vis))
    elseif act == "x" and self.rdata and self.rdata.history then
      App.show_dialog({ title = L("Limpar histórico?"), kind = "warn", sel = 2,
        body = L("Os registros das operações do PortMaster serão apagados desta lista. Nenhum arquivo do console é alterado."),
        buttons = { { label = L("LIMPAR"), fn = function()
          PM.clear_history(); self:show_report(L("Histórico de operações"), hist_lines(), { history = true })
        end }, { label = L("VOLTAR") } } })
    elseif act == "x" and self.rdata and self.rdata.result and self.rdata.result.method == "essentials" and self.rdata.version then
      if PM.busy() then return end
      App.show_dialog({ title = L("Verificação completa?"), kind = "info", sel = 1,
        body = string.format(L("Baixa o pacote oficial da versão %s (cerca de 24 MB), confere o md5 e compara cada arquivo instalado. Nada é alterado."), self.rdata.version),
        buttons = { { label = L("VERIFICAR"), fn = function()
          self.view = "main"
          local okk, err = PM.start("verify", { deep = true })
          if not okk then App.toast(err, "warn") end
        end }, { label = L("CANCELAR") } } })
    end
    return
  end
  if act == "b" then
    if PM.busy() and PM.can_cancel() then
      App.show_dialog({ title = L("Cancelar a operação?"), kind = "warn", sel = 2,
        body = L("A operação do PortMaster está em andamento. Ela continua em segundo plano se você só sair (veja a Central de Downloads)."),
        buttons = { { label = L("CANCELAR OPERAÇÃO"), fn = function() PM.cancel() end },
          { label = L("SAIR E CONTINUAR"), fn = function() App.pop() end }, { label = L("VOLTAR") } } })
      return
    end
    App.pop()
    return
  end
  local n = #ITEMS
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "y" and not PM.busy() then
    local okk = PM.start("check")
    if okk then App.toast(L("Consultando a versão estável nas fontes oficiais..."), "info") end
  elseif act == "a" then self:open(ITEMS[self.sel].id) end
end

function S:update()
  -- o atualizador de runtimes terminou: mostra o resultado real dele
  if require("core.runtimes").job then self.rt_wait = true
  elseif self.rt_wait then self.rt_wait = false; self:refresh() end
end

-- ---------------------------------------------------------------------------
local PHASE = {
  check = L("Verificando"), discover = L("Consultando a fonte oficial"), download = L("Baixando"),
  verify = L("Validando o pacote"), extract = L("Extraindo (pasta temporária)"), backup = L("Backup"),
  apply = L("Gravando os arquivos"), validate = L("Conferindo"),
}

function S:draw_report()
  G.header(self.rtitle)
  G.panel(12, 50, T.W - 24, 386, { bg = T.c.bg1 })
  local vis = 16
  for i = 1, vis do
    local l = self.wrapped[self.top + i]
    if not l then break end
    G.text(T.f.small, l.text, 26 + l.ind, 58 + (i - 1) * 23, T.c[l.color or "text"] or T.c.text)
  end
  local n = #self.wrapped
  if n > vis then
    local track = 370
    local h = math.max(20, track * vis / n)
    G.rect(T.W - 18, 58 + (track - h) * (self.top / (n - vis)), 3, h, T.c.accent2, 1, 0.7)
  end
  local h = { { "dpad", L("Rolar") } }
  if self.rdata and self.rdata.history then h[#h + 1] = { "x", L("Limpar histórico") } end
  if self.rdata and self.rdata.result and self.rdata.result.method == "essentials" and self.rdata.version then
    h[#h + 1] = { "x", L("Verificação completa") }
  end
  h[#h + 1] = { "b", L("Voltar") }
  G.hints(h)
end

function S:draw()
  if self.view == "report" then return self:draw_report() end
  G.header(L("Gerenciar PortMaster"))
  local lx, lw = 12, 300
  local q, chk = self.q, self.chk
  -- estado
  G.panel(lx, 50, lw, 152, { bg = T.c.bg1 })
  local function kv(k, v, y, col)
    local tv = I18N.tr(v)
    local vw = math.min(G.fit(T.f.bodyb, tv, 170):getWidth(tv), 170)
    G.text_fit(T.f.small, k, lx + 12, y, lw - 24 - vw - 8, T.c.dim)
    G.text_fit(T.f.bodyb, tv, lx + lw - 12 - vw, y - 2, 170, col or T.c.text)
  end
  local st, sc = status_text(q)
  kv(L("Situação"), st, 60, sc)
  kv(L("Versão instalada"), q.version or (q.state == "missing" and "—" or L("desconhecida")), 84)
  kv(L("Última versão estável"), chk and chk.stable or L("Não verificada"), 108, chk and T.c.text or T.c.faint)
  local ut, uc = update_text(q, chk)
  kv(L("Atualização"), ut, 132, uc)
  local rt, rc = rt_text(self.rt)
  kv(L("Runtimes"), q.state == "missing" and "—" or rt, 156, q.state == "missing" and T.c.faint or rc)
  G.text_fit(T.f.pix8, chk and (L("CONSULTA: ") .. Clock.datetime(chk.time or 0, true)) or L("Y: CONSULTAR VERSÃO ESTÁVEL"), lx + 12, 182, lw - 24, T.c.faint)
  -- console
  local e = self.env
  G.panel(lx, 208, lw, 228, { bg = T.c.bg1 })
  G.text(T.f.pix8, L("CONSOLE"), lx + 12, 216, T.c.accent2)
  local rows = {
    { L("Modelo"), e.model or NA },
    { L("CPU / sistema"), (e.arch or NA) .. " / " .. (e.pkg_arch or NA) },
    { L("Sistema"), e.os_name and (e.os_name .. (e.os_version and (" " .. e.os_version) or "")) or NA },
    { L("Variante (R36)"), e.variant or NA },
    { L("Kernel"), e.kernel or NA },
    { L("PortMaster"), e.pm_dir or L("não encontrado") },
    { L("Iniciador"), e.launcher or "—" },
    { L("Espaço livre"), e.free and U.format_bytes(e.free) or NA },
    { L("Gravação"), (e.writable == nil and NA) or (e.writable and L("permitida") or L("sem permissão")) .. (e.fs and ("  •  " .. e.fs) or "") },
  }
  for i, r in ipairs(rows) do
    local y = 232 + (i - 1) * 22
    G.text_fit(T.f.small, r[1], lx + 12, y, 94, T.c.dim)
    G.text_fit(T.f.small, r[2], lx + 112, y, lw - 124, (r[2] == NA) and T.c.faint or T.c.text)
  end
  -- operacoes
  local rx, rw = 322, T.W - 334
  local j = PM.job
  local busy = PM.busy()
  for i, it in ipairs(ITEMS) do
    local iy = 50 + (i - 1) * 55
    local on = i == self.sel
    G.rect(rx, iy, rw, 49, on and T.c.bg3 or T.c.bg1, 8)
    if on then G.frame(rx, iy, rw, 49, T.c.accent, 8, 2) end
    G.text_fit(T.f.bodyb, it.label, rx + 14, iy + 6, rw - 28, on and T.c.text or T.c.dim)
    G.text_fit(T.f.small, it.sub, rx + 14, iy + 27, rw - 28, on and T.c.dim or T.c.faint)
  end
  -- operacao em andamento
  if busy then
    local py = 384
    G.panel(rx, py, rw, 52, { bg = T.c.bg2, border = T.c.accent2 })
    local label = (PM.OP_LABEL[j.op] or "") .. " — " .. (PHASE[j.phase] or j.phase or "")
    G.text_fit(T.f.small, label, rx + 10, py + 5, rw - 20, T.c.text)
    local frac = (j.total and j.total > 0) and U.clamp(j.done / j.total, 0, 1) or nil
    if frac then G.progress(rx + 10, py + 24, rw - 20, 8, frac, T.c.accent2)
    else G.progress_busy(rx + 10, py + 24, rw - 20, 8, App.t, T.c.accent2) end
    local det
    if j.phase == "download" then
      det = U.format_bytes(j.done or 0) .. (j.total and (" / " .. U.format_bytes(j.total)) or "")
        .. ((j.speed and j.speed > 0) and ("  •  " .. U.format_speed(j.speed)) or "")
        .. (j.eta and ("  •  " .. L("faltam ") .. U.format_time(j.eta)) or "")
    elseif frac then det = string.format("%d / %d", j.done or 0, j.total)
    else det = j.label ~= "" and j.label or "" end
    G.text_fit(T.f.small, det, rx + 10, py + 34, rw - 20, T.c.dim)
  end
  local h = { { "dpad", L("Navegar") }, { "a", L("Selecionar") } }
  if not busy then h[#h + 1] = { "y", L("Consultar versão") } end
  h[#h + 1] = { "b", busy and PM.can_cancel() and L("Voltar / cancelar") or L("Voltar") }
  G.hints(h)
end

return S
