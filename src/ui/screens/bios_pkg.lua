-- =============================================================================
--  BIOS do Sistema > Analisar e instalar: resumo do pacote antes de instalar
--  Cada arquivo extraido aparece com o que o hub identificou (pelo hash) e o
--  que sera feito. So BIOS reconhecidas sao marcadas; arquivos nao reconhecidos
--  so aparecem na lista. Substituicoes so com backup e confirmacao.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local Bios = require("core.bios")
local Ref = require("core.bios_ref")

local S = {}

local LIST_Y, LIST_H = 74, 262

-- o que fazer com cada destino de um arquivo
local function dest_action(it, d)
  if d.no_folder then return "nofolder" end
  if d.special or d.inside == false then return "blocked" end
  if not d.real then return "new" end
  if d.same then return "same" end
  if it.verified and not d.verified then return "update" end
  return "pending"
end

local ACT = {
  new = { L("INSTALAR"), "green" }, update = { L("ATUALIZAR"), "accent2" }, same = { L("IDÊNTICA"), "dim" },
  pending = { L("VERIFICAÇÃO PENDENTE"), "yellow" }, nofolder = { L("SEM PASTA"), "faint" }, blocked = { L("BLOQUEADO"), "red" },
  incompatible = { L("INCOMPATÍVEL"), "orange" }, doc = { L("DOCUMENTO"), "faint" }, unknown = { L("NÃO RECONHECIDO"), "faint" },
  dup = { L("DUPLICADO"), "faint" },
}

function S:enter()
  self.a = Bios.analysis()
  self.sel, self.top = 1, 0
  self:build()
end

function S:build()
  local rows = {}
  local order = { bios = 1, name = 2, wrong = 3, dup = 4, unknown = 5, doc = 6 }
  for _, it in ipairs(self.a and self.a.items or {}) do
    local r = { it = it, acts = {} }
    if it.kind == "wrong" then r.act = "incompatible"
    elseif it.kind == "doc" then r.act = "doc"
    elseif it.kind == "unknown" then r.act = "unknown"
    elseif it.kind == "dup" then r.act = "dup"
    else
      local best
      local rank = { update = 1, new = 2, pending = 3, same = 4, nofolder = 5, blocked = 6 }
      for _, d in ipairs(it.dests or {}) do
        local a = dest_action(it, d)
        r.acts[#r.acts + 1] = { d = d, a = a }
        if not best or rank[a] < rank[best] then best = a end
      end
      r.act = best or "unknown"
      -- novas ou atualizacoes; arquivo so pelo nome (nao confirmado) nunca substitui
      for _, x in ipairs(r.acts) do
        if x.a == "new" or (x.a == "update" and it.verified) then r.selectable = true end
      end
      r.on = r.selectable and it.verified or false
    end
    rows[#rows + 1] = r
  end
  table.sort(rows, function(a, b)
    local oa, ob = order[a.it.kind] or 9, order[b.it.kind] or 9
    if oa ~= ob then return oa < ob end
    return a.it.rel:lower() < b.it.rel:lower()
  end)
  self.rows = rows
end

function S:counts()
  local n = { total = #self.rows, bios = 0, sel = 0, same = 0, other = 0, new = 0, upd = 0 }
  for _, r in ipairs(self.rows) do
    if r.it.kind == "bios" then n.bios = n.bios + 1 end
    if r.act == "same" then n.same = n.same + 1 end
    if r.it.kind == "doc" or r.it.kind == "unknown" or r.it.kind == "dup" then n.other = n.other + 1 end
    if r.on then
      n.sel = n.sel + 1
      for _, x in ipairs(r.acts) do
        if x.a == "new" then n.new = n.new + 1 elseif x.a == "update" then n.upd = n.upd + 1 end
      end
    end
  end
  return n
end

local function label_of(path)
  if path:sub(1, 1) == "@" then return I18N.tr(L("ROMs/")) .. path:sub(2) end
  return path
end

function S:draw()
  G.header(L("Pacote de BIOS"), self.a and self.a.pkg_name or "")
  if not self.a then
    G.text(T.f.body, L("Nenhuma análise disponível."), 0, 200, T.c.dim, "center", T.W)
    G.hints({ { "b", L("Voltar") } })
    return
  end
  local n = self:counts()
  G.panel(12, 46, T.W - 24, 24, { bg = T.c.bg1 })
  G.text_fit(T.f.small, string.format(I18N.tr(L("%d arquivos  •  %d BIOS reconhecidas  •  %d marcadas  •  %d idênticas  •  %d outros")),
    n.total, n.bios, n.sel, n.same, n.other), 22, 50, T.W - 44, T.c.dim)
  -- lista
  local rh = 44 + (T.f.bodyb:getHeight() - T.base_font(T.f.bodyb):getHeight()) + (T.f.small:getHeight() - T.base_font(T.f.small):getHeight())
  local vis = math.max(3, math.floor(LIST_H / rh))
  self.vis = vis
  if self.sel > self.top + vis then self.top = self.sel - vis end
  if self.sel <= self.top then self.top = self.sel - 1 end
  for i = self.top + 1, math.min(#self.rows, self.top + vis) do
    local r = self.rows[i]
    local y = LIST_Y + 4 + (i - self.top - 1) * rh
    local on = i == self.sel
    G.rect(12, y, T.W - 24, rh - 4, on and T.c.bg3 or T.c.bg1, 5)
    if on then G.frame(12, y, T.W - 24, rh - 4, T.c.yellow, 5, 2) end
    -- caixa de marcar
    if r.selectable then
      G.frame(22, y + (rh - 4) / 2 - 8, 16, 16, r.on and T.c.green or T.c.line, 3, 2)
      if r.on then G.rect(26, y + (rh - 4) / 2 - 4, 8, 8, T.c.green, 2) end
    end
    local a = ACT[r.act] or ACT.unknown
    local tw = T.f.pix8:getWidth(I18N.tr(a[1])) + 12
    G.tag(a[1], T.W - 22 - tw, y + (rh - 4) / 2 - 8, T.c[a[2]] or T.c.dim, T.c.bg0, T.f.pix8)
    local ft, fs, ty, sy = G.row_fonts(rh - 4, 4, 22)
    G.text_fit(ft, Ref.basename(r.it.rel), 46, y + ty, T.W - 80 - tw, on and T.c.text or T.c.dim)
    local sub
    if r.it.target then
      sub = "→ " .. label_of(r.it.target) .. "  •  " .. I18N.tr(r.it.verified and L("confirmada pelo MD5") or L("nome conhecido, versão não confirmada"))
    elseif r.it.kind == "dup" then sub = I18N.tr(L("mesmo conteúdo de ")) .. Ref.basename(r.it.dup_of or "")
    else sub = r.it.rel end
    G.text_fit(fs, sub, 46, y + sy, T.W - 80 - tw, T.c.faint)
  end
  if #self.rows > vis then
    local track = vis * rh - 4
    local hh = math.max(16, track * vis / #self.rows)
    G.rect(T.W - 8, LIST_Y + 4 + (track - hh) * (self.top / (#self.rows - vis)), 3, hh, T.c.yellow, 1, 0.7)
  end
  -- detalhes do arquivo selecionado (texto padrao: painel de posicoes fixas)
  T.with_base_fonts(self.draw_detail, self)
  local hints = { { "dpad", L("Navegar") } }
  local r = self.rows[self.sel]
  if r and r.selectable then hints[#hints + 1] = { "a", r.on and L("Desmarcar") or L("Marcar") } end
  hints[#hints + 1] = { "y", L("Instalar marcadas") }
  hints[#hints + 1] = { "b", L("Voltar") }
  G.hints(hints)
end

function S:draw_detail()
  local r = self.rows[self.sel]
  local px, py, pw, ph = 12, 340, T.W - 24, 96
  G.panel(px, py, pw, ph, { bg = T.c.bg1 })
  if not r then return end
  local it = r.it
  local y = py + 8
  G.text_fit(T.f.small, I18N.tr(L("No pacote: ")) .. it.rel .. "  (" .. U.format_bytes(it.size or 0) .. ")", px + 12, y, pw - 24, T.c.text)
  y = y + 16
  G.text_fit(T.f.small, "MD5 " .. tostring(it.md5) .. (it.sha256 and ("   SHA-256 " .. it.sha256:sub(1, 16) .. "…") or ""), px + 12, y, pw - 24, T.c.dim)
  y = y + 16
  local lines = {}
  for _, x in ipairs(r.acts) do
    local d = x.d
    local base = d.target:sub(1, 1) == "@" and (self.a.roms_dir .. "/" .. d.target:sub(2)) or (self.a.bios_dir .. "/" .. d.target)
    lines[#lines + 1] = I18N.tr(L("Destino: ")) .. (d.real or base) .. "  —  " .. I18N.tr((ACT[x.a] or ACT.unknown)[1])
  end
  local expl = {
    update = L("A BIOS atual não confere com nenhuma versão conhecida; a do pacote confere. A atual vai para o backup antes da troca."),
    pending = L("O arquivo atual é diferente e não dá para saber qual versão é a correta: o hub não substitui."),
    same = L("O arquivo instalado é idêntico (mesmo MD5): não precisa substituir."),
    nofolder = L("A pasta de ROMs deste sistema não existe no console: o hub não cria."),
    blocked = L("O destino é um link ou uma pasta, ou fica fora da pasta permitida: bloqueado."),
    incompatible = L("O nome é de uma BIOS conhecida, mas o tamanho não bate com nenhuma versão: não é instalado."),
    doc = L("Documentação ou imagem que acompanha o pacote: não é instalada."),
    unknown = L("Não é uma BIOS conhecida pelo banco do libretro nem pela wiki do ArkOS: só listado (COMPATIBILIDADE NÃO VERIFICADA)."),
    dup = L("Mesmo conteúdo de outro arquivo do pacote: instalado uma vez só."),
    new = it.verified and L("BIOS ausente no console: será instalada.") or L("Nome conhecido, mas a versão não foi confirmada pelo hash. Só é instalada se você marcar."),
  }
  if expl[r.act] then lines[#lines + 1] = I18N.tr(expl[r.act]) end
  for _, l in ipairs(lines) do
    for _, w in ipairs(G.wrap(T.f.small, l, pw - 24)) do
      if y < py + ph - 14 then G.text(T.f.small, w, px + 12, y, T.c.faint) end
      y = y + 15
    end
  end
end

function S:install()
  local items, news, upds = {}, {}, {}
  for _, r in ipairs(self.rows) do
    if r.on then
      for _, x in ipairs(r.acts) do
        if x.a == "new" or x.a == "update" then
          items[#items + 1] = { src = self.a.tmp .. "/" .. r.it.rel, rel = r.it.rel, md5 = r.it.md5, target = x.d.target,
            replace = x.a == "update" }
          if x.a == "new" then news[#news + 1] = label_of(x.d.target) else upds[#upds + 1] = label_of(x.d.target) end
        end
      end
    end
  end
  if #items == 0 then App.toast(L("Nenhuma BIOS marcada para instalar."), "info"); return end
  local body = { string.format(I18N.tr(L("Novas: %d  •  Substituídas (com backup): %d")), #news, #upds) }
  local function add(list, title)
    if #list == 0 then return end
    local shown = {}
    for i = 1, math.min(5, #list) do shown[#shown + 1] = list[i] end
    body[#body + 1] = I18N.tr(title) .. table.concat(shown, ", ") .. (#list > 5 and (" … +" .. (#list - 5)) or "")
  end
  add(upds, L("Serão substituídas: "))
  add(news, L("Serão instaladas: "))
  body[#body + 1] = I18N.tr(L("Pasta: ")) .. tostring(self.a.bios_dir)
  App.show_dialog({
    title = L("Instalar BIOS?"), kind = #upds > 0 and "warn" or "info", body = table.concat(body, "\n"),
    buttons = {
      { label = L("INSTALAR"), fn = function()
        local ok, err = Bios.start("install", { items = items, pkg_name = self.a.pkg_name }, function(j)
          if j.state == "done" then
            local r = j.result.results or {}
            local nn, nu, ns = 0, 0, 0
            for _, x in ipairs(r) do
              if x.action == "new" then nn = nn + 1 elseif x.action == "replace" then nu = nu + 1 else ns = ns + 1 end
            end
            App.show_dialog({ title = L("Instalação concluída"), kind = "ok",
              body = string.format(I18N.tr(L("%d instaladas, %d substituídas, %d já idênticas. Cada arquivo foi conferido pelo MD5 depois de copiado.")), nn, nu, ns)
                .. (j.result.backup and ("\n" .. I18N.tr(L("Backup das BIOS anteriores: ")) .. "backups/bios/" .. j.result.backup) or "")
                .. "\n" .. I18N.tr(L("Para liberar espaço, use Limpeza de arquivos de instalação.")) })
            -- confere o console de novo e atualiza a lista
            Bios.start("scan", nil, function() if App.current() == self then self:build() end end)
            self:build()
          elseif j.state == "error" then
            App.show_dialog({ title = L("BIOS do Sistema"), kind = "error", body = Bios.message(j.error_code, j.detail) })
            Bios.start("scan")
          end
        end)
        if not ok then App.toast(err, "warn") end
      end },
      { label = L("CANCELAR") },
    },
    sel = #upds > 0 and 2 or 1,
  })
end

function S:action(act)
  local n = #self.rows
  if act == "b" then App.pop(); return end
  if n == 0 then return end
  if act == "up" then self.sel = (self.sel - 2) % n + 1
  elseif act == "down" then self.sel = self.sel % n + 1
  elseif act == "left" then self.sel = math.max(1, self.sel - (self.vis or 5))
  elseif act == "right" then self.sel = math.min(n, self.sel + (self.vis or 5))
  elseif act == "a" then
    local r = self.rows[self.sel]
    if r.selectable then r.on = not r.on end
  elseif act == "y" then
    if Bios.busy() then App.toast(L("Aguarde a operação de BIOS em andamento."), "warn") else self:install() end
  end
end

return S
