-- =============================================================================
--  Configuracoes > Informacoes do console > Otimizador e manutencao do microSD
--  Esquerda: cartao (dados do sistema) e particoes. Direita: ferramentas.
--  Nada aqui formata, reparticiona, desmonta ou apaga sem o usuario pedir.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local SD = require("core.sdcard")
local M = require("core.sdmaint")
local lg = love.graphics

local S = {}

local ITEMS = {
  { id = "analyze", label = L("Analisar armazenamento"), sub = L("Pastas e arquivos que mais ocupam espaço") },
  { id = "integrity", label = L("Verificar integridade"), sub = L("Montagem, erros do sistema e estado das partições") },
  { id = "fsck", label = L("Verificar erros do sistema de arquivos"), sub = L("fsck.exfat, fsck.vfat ou e2fsck, só leitura") },
  { id = "optimize", label = L("Otimização compatível"), sub = L("Só o que o cartão e o sistema suportam") },
  { id = "dups", label = L("Localizar arquivos duplicados"), sub = L("Compara o conteúdo (hash), não o nome") },
  { id = "defrag", label = L("Desfragmentação"), sub = L("Por que não é recomendada no microSD") },
  { id = "report", label = L("Gerar relatório"), sub = L("Salva um arquivo TXT sem sobrescrever outro") },
}

function S:enter()
  self.sel = self.sel or 1
  self.cards = SD.list()
  local want = SD.ports_device()
  self.ci = 1
  for i, c in ipairs(self.cards) do if c.dev == want then self.ci = i end end
  self:load()
end

function S:resume() self:load() end

function S:load()
  local c = self.cards[self.ci]
  self.card = c
  if c then
    self.parts, self.src = M.partitions(c.dev)
    self.sum = M.summary(c, self.parts)
  else
    self.parts, self.sum = {}, nil
  end
end

--- particoes montadas do cartao (para analise)
function S:mounted()
  local t = {}
  for _, p in ipairs(self.parts or {}) do if p.mp then t[#t + 1] = { name = p.name, mp = p.mp, fs = p.fs, dev = p.dev } end end
  return t
end

--- pastas de dados (sem o sistema "/" e a /boot) para procurar duplicados
function S:data_roots()
  local t = {}
  for _, p in ipairs(self.parts or {}) do
    if p.mp and p.mp ~= "/" and not p.mp:match("^/boot") then t[#t + 1] = p.mp end
  end
  if #t == 0 then
    for _, p in ipairs(self.parts or {}) do
      if p.mp and (C.PORTS_DIR == p.mp or C.PORTS_DIR:sub(1, #p.mp + 1) == p.mp .. "/") and p.mp ~= "/" then t[#t + 1] = p.mp end
    end
  end
  if #t == 0 then t[1] = C.PORTS_DIR end
  return t
end

function S:job_parts()
  local t = {}
  for _, p in ipairs(self.parts or {}) do
    t[#t + 1] = { name = p.name, dev = p.dev, fs = p.fs, mp = p.mp, ro = p.ro }
  end
  return t
end

-- ---------------------------------------------------------------------------
function S:optimize()
  local c = self.card
  local disc = c and M.discard(c.dev)
  local fstrim = M.has("fstrim")
  local trim_mps = {}
  for _, p in ipairs(self.parts or {}) do
    if p.mp and not p.ro and (p.fs == "ext4" or p.fs == "vfat" or p.fs == "exfat" or p.fs == "ext3" or p.fs == "ext2") then
      trim_mps[#trim_mps + 1] = p.mp
    end
  end
  local trim_ok = disc and fstrim and #trim_mps > 0
  local trim_why = (not disc) and L("O cartão/leitor não informa suporte a descarte (discard).")
    or ((not fstrim) and L("A ferramenta fstrim não está instalada no sistema."))
    or ((#trim_mps == 0) and L("Nenhuma partição montada para gravação com sistema de arquivos compatível."))
    or nil
  local busy = require("core.installer").busy()
  App.show_dialog({
    title = L("Otimização compatível"), kind = "info", list = true,
    body = L("Escolha uma operação. Antes de executar, ela é explicada."),
    buttons = {
      { label = L("Gravar dados pendentes (sync)"), sub = L("Disponível: grava no cartão o que o sistema ainda guarda na memória"),
        fn = function()
          self:confirm(L("Gravar dados pendentes?"),
            L("O comando sync grava no cartão os dados que o sistema ainda mantém na memória. Não apaga nem altera arquivos. Útil antes de desligar ou remover o cartão."),
            { op = "sync" }, L("Gravar dados pendentes"))
        end },
      { label = L("TRIM (fstrim)"), sub = trim_ok and (L("Disponível em: ") .. table.concat(trim_mps, ", ")) or (L("Indisponível: ") .. trim_why),
        fn = function()
          if not trim_ok then App.toast(trim_why, "warn"); return end
          self:confirm(L("Executar TRIM?"),
            L("O fstrim informa ao cartão quais blocos estão livres, o que pode ajudar a manter a velocidade de gravação. Não apaga arquivos. Pode levar alguns minutos e precisa de permissão de administrador. Partições: ") .. table.concat(trim_mps, ", "),
            { op = "trim", mps = trim_mps }, L("TRIM (fstrim)"))
        end },
      { label = L("Limpar temporários do R36S PORT HUB"),
        sub = busy and L("Indisponível: há uma instalação em andamento") or L("Disponível: restos de instalações interrompidas do próprio hub"),
        fn = function()
          if busy then App.toast(L("Aguarde a operação atual terminar."), "warn"); return end
          self:confirm(L("Limpar temporários?"),
            L("Apaga somente as pastas temporárias de instalações interrompidas do R36S PORT HUB (em ") .. C.TMP_DIR .. L("). Jogos, ports e arquivos do sistema não são tocados."),
            { op = "cleantmp", tmp = C.TMP_DIR }, L("Limpar temporários"))
        end },
      { label = L("Cancelar") },
    },
  })
end

function S:confirm(title, body, job, run_title)
  App.show_dialog({
    title = title, kind = "warn", body = body,
    buttons = {
      { label = L("EXECUTAR"), fn = function() App.push("sdmaint_run", { job = job, title = run_title, card = self.card, parts = self.parts, sum = self.sum }) end },
      { label = L("CANCELAR") },
    },
    sel = 2,
  })
end

function S:open(id)
  local c = self.card
  if not c then App.toast(L("Nenhum cartão encontrado."), "warn"); return end
  local base = { card = c, parts = self.parts, sum = self.sum, src = self.src }
  local function push(job, title)
    local p = {}
    for k, v in pairs(base) do p[k] = v end
    p.job, p.title = job, title
    App.push("sdmaint_run", p)
  end
  if id == "analyze" then
    local m = self:mounted()
    if #m == 0 then App.toast(L("Nenhuma partição deste cartão está montada."), "warn"); return end
    push({ op = "analyze", parts = m }, L("Analisar armazenamento"))
  elseif id == "integrity" then
    push({ op = "integrity", card = c.dev, parts = self:job_parts() }, L("Verificar integridade"))
  elseif id == "fsck" then
    push({ op = "fsck_plan", parts = self:job_parts() }, L("Verificar erros do sistema de arquivos"))
  elseif id == "optimize" then
    self:optimize()
  elseif id == "dups" then
    local roots = self:data_roots()
    App.show_dialog({
      title = L("Localizar arquivos duplicados?"), kind = "info",
      body = L("Procura arquivos com o mesmo conteúdo (comparação por hash) em: ") .. table.concat(roots, ", ")
        .. L(". Arquivos menores que 1 MB são ignorados. Somente leitura: nada é apagado. Em cartões cheios pode levar vários minutos."),
      buttons = {
        { label = L("PROCURAR"), fn = function() push({ op = "dups", roots = roots, min_kb = 1024 }, L("Localizar arquivos duplicados")) end },
        { label = L("CANCELAR") },
      },
    })
  elseif id == "defrag" then
    App.show_dialog({
      title = L("Desfragmentação"), kind = "info",
      body = L("A desfragmentação não é recomendada para o microSD do R36S. O cartão usa memória flash: ler um arquivo em pedaços espalhados é tão rápido quanto em sequência, e reorganizar os arquivos só gastaria ciclos de gravação do cartão.")
        .. "\n\n" .. L("Para cuidar do cartão, use as outras ferramentas desta tela: verificar integridade, verificar erros, TRIM (quando suportado) e localizar duplicados."),
    })
  elseif id == "report" then
    push({ op = "integrity", card = c.dev, parts = self:job_parts(), report = true }, L("Gerar relatório"))
  end
end

function S:action(act)
  if act == "b" then App.pop(); return end
  local n = #ITEMS
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif (act == "l1" or act == "r1") and #self.cards > 1 then
    self.ci = (self.ci - 1 + (act == "r1" and 1 or -1)) % #self.cards + 1
    self:load()
  elseif act == "a" then self:open(ITEMS[self.sel].id) end
end

-- ---------------------------------------------------------------------------
local function bar(x, y, w, h, frac, col)
  G.rect(x, y, w, h, T.c.bg0, h / 2)
  if frac and frac > 0 then G.rect(x, y, math.max(h, w * math.min(1, frac)), h, col, h / 2) end
end

function S:draw()
  G.header(L("Otimizador e manutenção do microSD"))
  local lx, lw = 12, 300
  local c, s = self.card, self.sum
  -- cartao
  G.panel(lx, 50, lw, 132, { bg = T.c.bg1 })
  if not c then
    G.text(T.f.body, L("Nenhum cartão encontrado."), lx, 100, T.c.dim, "center", lw)
  else
    local id = (c.maker or (c.name and L("Cartão SD")) or L("Cartão SD")) .. (c.name and ("  " .. c.name) or "")
    G.text_fit(T.f.bodyb, id, lx + 12, 58, lw - 24, T.c.text)
    G.text_fit(T.f.small, "/dev/" .. c.dev .. ((#self.cards > 1) and ("   " .. L("L1/R1: outro cartão")) or ""), lx + 12, 78, lw - 24, T.c.faint)
    local function kv(k, v, y, col)
      G.text(T.f.small, k, lx + 12, y, T.c.dim)
      G.text(T.f.bodyb, v, lx + lw - 12 - T.f.bodyb:getWidth(I18N.tr(v)), y - 2, col or T.c.text)
    end
    kv(L("Capacidade total"), c.bytes and U.format_bytes(c.bytes) or "—", 98)
    kv(L("Usado"), s and s.used and U.format_bytes(s.used) or "—", 116)
    kv(L("Livre"), s and s.free and U.format_bytes(s.free) or "—", 134, T.c.green)
    local frac = s and s.frac
    bar(lx + 12, 158, lw - 70, 10, frac, (frac or 0) > 0.9 and T.c.red or T.c.accent2)
    G.text(T.f.bodyb, frac and string.format("%d%%", math.floor(frac * 100 + 0.5)) or "—", lx + lw - 50, 153, T.c.text, "right", 38)
  end
  -- particoes
  G.panel(lx, 188, lw, 248, { bg = T.c.bg1 })
  G.text(T.f.pix8, L("PARTIÇÕES"), lx + 12, 198, T.c.accent2)
  local y = 214
  if c and #self.parts == 0 then
    G.text_fit(T.f.small, L("O sistema não informou partições deste cartão."), lx + 12, y, lw - 24, T.c.dim)
  end
  for i, p in ipairs(self.parts or {}) do
    if y > 400 then
      G.text(T.f.small, string.format(L("… e mais %d"), #self.parts - i + 1), lx + 12, y, T.c.faint)
      break
    end
    local fs = M.fs_label(p.fs) or L("desconhecido")
    G.text(T.f.bodyb, p.name:match("(p%d+)$") or p.name, lx + 12, y, T.c.text)
    G.text_fit(T.f.small, fs .. (p.label and ("  •  " .. p.label) or ""), lx + 52, y + 2, 150, T.c.accent2)
    local sz = p.size and U.format_bytes(p.size) or "—"
    G.text(T.f.small, sz, lx + lw - 12 - T.f.small:getWidth(sz), y + 2, T.c.dim)
    local line2 = p.mp and (p.mp .. "  •  " .. (p.ro and L("somente leitura") or L("leitura e gravação"))) or L("não montada")
    G.text_fit(T.f.small, line2, lx + 52, y + 19, lw - 120, p.mp and T.c.dim or T.c.faint)
    if p.use then
      local f = p.use.used / math.max(1, p.use.used + p.use.free)
      bar(lx + lw - 62, y + 23, 50, 6, f, f > 0.9 and T.c.red or T.c.accent2)
    end
    y = y + 44
  end

  -- ferramentas
  local rx, rw = 322, T.W - 334
  for i, it in ipairs(ITEMS) do
    local iy = 50 + (i - 1) * 55
    local on = i == self.sel
    G.rect(rx, iy, rw, 49, on and T.c.bg3 or T.c.bg1, 8)
    if on then G.frame(rx, iy, rw, 49, T.c.accent, 8, 2) end
    G.text_fit(T.f.bodyb, it.label, rx + 14, iy + 6, rw - 28, on and T.c.text or T.c.dim)
    G.text_fit(T.f.small, it.sub, rx + 14, iy + 27, rw - 28, on and T.c.dim or T.c.faint)
  end

  local h = { { "dpad", L("Navegar") }, { "a", L("Selecionar") } }
  if #self.cards > 1 then h[#h + 1] = { "l1", "" }; h[#h + 1] = { "r1", L("Cartão") } end
  h[#h + 1] = { "b", L("Voltar") }
  G.hints(h)
end

return S
