-- =============================================================================
--  Detalhes do port > Y: VER DETALHES DA COMPATIBILIDADE
--  Painel compacto (port, classificacao, motivo) + explicacao completa:
--  o que foi detectado, o que foi comparado, o que foi atendido ou nao, o que
--  falta saber e por que o port recebeu a classificacao. Somente leitura.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Compat = require("core.compat")

local S = {}
-- painel com posicoes fixas e muita informacao: texto sempre no tamanho padrao
-- (Configuracoes > Aparencia > Tamanho do texto nao se aplica a esta tela)
S.fixed_text = true

local VIS, LH = 13, 22
local LIST_Y = 150

-- niveis de confianca do core/osdetect (para a traducao)
local _CONF = { L("alta"), L("media"), L("baixa") }

local MARK = {
  ok = { L("ATENDIDO"), "green" }, fail = { L("NÃO ATENDIDO"), "red" }, missing = { L("AUSENTE"), "yellow" },
  warn = { L("NÃO CONFIRMADO"), "yellow" }, unknown = { L("DESCONHECIDO"), "dim" },
}
-- prefixo so onde o rotulo e um nome tecnico (runtime, biblioteca, arquivo)
local GROUP = { rt = L("Runtime"), lib = L("Biblioteca"), file = L("Arquivo") }

function S:enter(p)
  self.port = p.port
  self:build()
end

function S:on_language() self:build() end

function S:build()
  local p = self.port
  local r = Compat.evaluate(p)
  self.r = r
  local e = r and r.env or Compat.detect()
  local t = {}
  local function add(text, color, ind) t[#t + 1] = { text = text, color = color or "text", ind = ind or 0 } end
  local function kv(k, v, color) add(I18N.tr(k) .. ": " .. I18N.tr(v or L("desconhecido")), color or (v and "text" or "faint"), 1) end
  local unk = L("desconhecido")

  if e.changed then
    add(L("O sistema ou os runtimes do console mudaram desde a última análise; os resultados foram refeitos."), "yellow")
    add("")
  end

  add(L("DETECTADO NO CONSOLE"), "accent2")
  local msrc = e.model_src == "consoleid" and L(" (Analisador de Console)") or (e.model_src == "devicetree" and L(" (Device Tree)") or "")
  kv(L("Console"), e.model and (e.model .. I18N.tr(msrc)) or nil)
  kv("SoC", e.soc)
  kv(L("Arquitetura"), e.arch and (e.arch .. (e.pkg_arch and e.pkg_arch ~= e.arch and (L("  (pacotes: ") .. e.pkg_arch .. ")") or "")) or nil)
  local osn = e.os_name and (e.os_name .. (e.os_version and (" " .. e.os_version) or "")
    .. (e.os_conf and (I18N.tr(L("  •  confiança: ")) .. I18N.tr(e.os_conf)) or "")) or nil
  kv(L("Sistema"), osn)
  kv(L("Kernel"), e.kernel)
  kv("glibc", e.glibc)
  kv(L("Memória RAM"), e.ram_mb and (e.ram_mb .. " MB") or nil)
  kv(L("Tela"), e.res)
  local gfx = {}
  if e.dri then gfx[#gfx + 1] = "DRM" .. (e.gpu_driver and (" (" .. e.gpu_driver .. ")") or "") end
  if e.egl then gfx[#gfx + 1] = "EGL" end
  if e.gles then gfx[#gfx + 1] = "OpenGL ES" end
  if e.mali then gfx[#gfx + 1] = "libmali" end
  kv(L("Gráficos"), #gfx > 0 and table.concat(gfx, ", ") or nil)
  kv("PortMaster", e.pm or L("não encontrado"), e.pm and "text" or "yellow")
  kv(L("Runtimes instalados"), #e.runtime_list > 0 and (#e.runtime_list .. ": " .. table.concat(e.runtime_list, ", ")) or L("nenhum"))
  kv(L("Pasta de ports"), e.ports_dir)
  add("")

  if not r then
    add(L("Ferramenta integrada ao hub: não depende de requisitos externos."), "dim")
    self.lines = t; self:wrap(); return
  end

  -- requisitos e comparacao
  add(L("REQUISITOS INFORMADOS PELO PORT E COMPARAÇÃO"), "accent2")
  if #r.items == 0 then
    add(L("O catálogo não informa nenhum requisito verificável para este port."), "faint", 1)
  end
  for _, it in ipairs(r.items) do
    local m = MARK[it.status] or MARK.unknown
    local g = GROUP[it.group] and (I18N.tr(GROUP[it.group]) .. " ") or ""
    add("[" .. I18N.tr(m[1]) .. "]  " .. g .. I18N.tr(it.label) .. ": " .. I18N.tr(it.detail or ""), m[2], 1)
  end
  add("")

  -- runtimes e dependencias
  local need, have, miss = {}, {}, {}
  for _, it in ipairs(r.items) do
    if it.group == "rt" or it.group == "lib" or it.group == "file" then
      need[#need + 1] = it.label
      if it.status == "ok" then have[#have + 1] = it.label else miss[#miss + 1] = it.label end
    end
  end
  add(L("DEPENDÊNCIAS E RUNTIMES"), "accent2")
  kv(L("Necessários"), #need > 0 and table.concat(need, ", ") or L("nenhum informado"))
  kv(L("Já instalados"), #have > 0 and table.concat(have, ", ") or L("nenhum"))
  kv(L("Ausentes"), #miss > 0 and table.concat(miss, ", ") or L("nenhum"), #miss > 0 and "yellow" or "text")
  if #miss > 0 then add(L("O hub não instala dependências automaticamente. Runtimes do PortMaster podem ser atualizados em Configurações → Downloads e atualizações → Atualizar runtimes."), "dim", 1) end
  if p.requires_files then add(L("Este port precisa dos arquivos do jogo original (não verificados pelo hub)."), "yellow", 1) end
  add("")

  -- espaco
  add(L("ARMAZENAMENTO"), "accent2")
  local free = App.free
  if p.size then
    kv(L("Download"), U.format_bytes(p.size) .. (free and (I18N.tr(L("  •  livre no cartão: ")) .. U.format_bytes(free)) or ""),
      (free and free < p.size) and "red" or "text")
    add(L("O espaço depois de extraído só é conhecido após a instalação."), "faint", 1)
  else
    kv(L("Download"), L("tamanho não informado pelo catálogo"))
  end
  add("")

  -- o que falta saber
  local req = r.req
  local absent = {}
  local function chk(v, name) if v == nil then absent[#absent + 1] = name end end
  chk(req.arch, L("arquitetura")); chk(req.os, L("sistemas testados")); chk(req.runtimes, L("runtimes"))
  chk(req.min_ram_mb, L("memória mínima")); chk(req.resolutions or req.min_resolution, L("resolução"))
  chk(req.tested, L("testes registrados"))
  local unknown_items = 0
  for _, it in ipairs(r.items) do if it.status == "unknown" then unknown_items = unknown_items + 1 end end
  add(L("INFORMAÇÕES AUSENTES"), "accent2")
  if #absent > 0 then
    local tr = {}
    for _, a in ipairs(absent) do tr[#tr + 1] = I18N.tr(a) end
    add(I18N.tr(L("O catálogo não informa: ")) .. table.concat(tr, ", ") .. ".", "faint", 1)
  end
  if unknown_items > 0 then add(string.format(I18N.tr(L("%d requisito(s) não puderam ser confirmados no console.")), unknown_items), "faint", 1) end
  if #absent == 0 and unknown_items == 0 then add(L("Nenhuma."), "faint", 1) end
  add("")

  -- motivo
  add(L("POR QUE ESTA CLASSIFICAÇÃO"), "accent2")
  add(r.reason, Compat.COLOR[r.status], 1)
  local rule = ({
    compatible = L("Todos os requisitos informados foram comparados e atendidos."),
    experimental = L("Nenhuma incompatibilidade concreta foi encontrada, mas algo ainda não está confirmado."),
    incompatible = L("Pelo menos um requisito informado não é atendido por este console."),
    unverified = L("Sem dados suficientes, o hub não afirma nada: o port não é marcado como incompatível."),
  })[r.status]
  add(rule, "dim", 1)
  if req.notes and req.notes ~= "" then add(""); add(L("OBSERVAÇÕES DO PORT"), "accent2"); add(req.notes, "text", 1) end
  add("")
  add(L("Somente análise: nada foi executado, instalado ou alterado. A decisão de instalar é sua."), "faint")
  self.lines = t
  self:wrap()
end

function S:wrap()
  local w = T.W - 56
  local out = {}
  for _, l in ipairs(self.lines) do
    local ind = (l.ind or 0) * 16
    local parts = (l.text == "") and { "" } or G.wrap(T.f.small, I18N.tr(l.text), w - ind)
    for _, s in ipairs(parts) do out[#out + 1] = { text = s, color = l.color, ind = ind } end
  end
  self.wrapped = out
  self.top = 0
end

function S:action(act)
  local maxtop = math.max(0, #self.wrapped - VIS)
  if act == "b" then App.pop()
  elseif act == "up" then self.top = math.max(0, self.top - 1)
  elseif act == "down" then self.top = math.min(maxtop, self.top + 1)
  elseif act == "l1" or act == "left" then self.top = math.max(0, self.top - VIS)
  elseif act == "r1" or act == "right" then self.top = math.min(maxtop, self.top + VIS) end
end

function S:draw()
  G.header(L("Compatibilidade"))
  local x, w = 12, T.W - 24
  local p, r = self.port, self.r
  -- painel compacto
  G.panel(x, 50, w, 92, { bg = T.c.bg1 })
  G.text(T.f.pix8, L("PORT ANALISADO"), x + 14, 60, T.c.faint)
  G.text_fit(T.f.h3, p.name, x + 14, 72, w - 200, T.c.text)
  if r then
    local col = T.c[Compat.COLOR[r.status]] or T.c.dim
    local label = Compat.LABEL[r.status]
    local tw = T.f.pix16:getWidth(I18N.tr(label)) + 12
    G.tag(label, x + w - 14 - tw, 64, col, T.c.bg0, T.f.pix16)
    local lines = G.wrap(T.f.small, I18N.tr(r.reason), w - 28)
    for i = 1, math.min(2, #lines) do G.text(T.f.small, lines[i], x + 14, 98 + (i - 1) * 16, T.c.dim) end
  end
  -- detalhes rolaveis
  G.panel(x, LIST_Y - 4, w, VIS * LH + 12, { bg = T.c.bg1 })
  local wr = self.wrapped or {}
  for i = self.top + 1, math.min(#wr, self.top + VIS) do
    local l = wr[i]
    local y = LIST_Y + 2 + (i - self.top - 1) * LH
    G.text(T.f.small, l.text, x + 14 + l.ind, y, T.c[l.color or "text"] or T.c.text)
  end
  if #wr > VIS then
    local track = VIS * LH
    local h = math.max(18, track * VIS / #wr)
    local yy = LIST_Y + (track - h) * (self.top / math.max(1, #wr - VIS))
    G.rect(T.W - 18, yy, 3, h, T.c.accent2, 1, 0.7)
  end
  G.hints({ { "dpad", L("Rolar") }, { "b", L("Voltar") } })
end

return S
