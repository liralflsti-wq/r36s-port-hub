-- =============================================================================
--  Gerenciador de arquivos (Configuracoes)
--  Navega pelo cartao SD e extrai arquivos ZIP, RAR e 7z:
--    - EXTRAIR AQUI: descompacta na propria pasta, mantendo a estrutura
--    - INSTALAR COMO PORT: instala em /roms/ports com as verificacoes da loja
--  EXTRAIR AQUI pergunta, depois da extracao, se o arquivo compactado deve ser
--  excluido. INSTALAR COMO PORT exclui o compactado ao terminar.
--  X (ou A em arquivos): opcoes do item: recortar, excluir, extrair.
--  Y: cola o item recortado na pasta aberta (mover; nunca sobrescreve).
--  Usa o mesmo instalador da loja (pasta temporaria, confirmacao antes de
--  substituir, sem apagar nada em caso de erro).
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local lg = love.graphics

local S = {}

-- item recortado (vale enquanto o app estiver aberto)
local CLIP = nil

local ROW_H, LIST_Y, VISIBLE = 30, 82, 11
local ARCHIVE = { zip = "ZIP", rar = "RAR", ["7z"] = "7Z" }

local function parent(p) return (p:match("^(.*)/[^/]+$")) or "/" end
local function basename(p) return p:match("([^/]+)$") or p end

--- Raizes permitidas: o cartao onde esta a pasta de ports e o 2o cartao (se existir)
local function roots()
  local list, seen = {}, {}
  local function add(path, label)
    if path and not seen[path] and U.is_dir(path) then
      seen[path] = true
      list[#list + 1] = { path = path, label = label }
    end
  end
  add(parent(C.PORTS_DIR), L("Cartão SD (") .. parent(C.PORTS_DIR) .. ")")
  add("/roms", L("Cartão 1 (/roms)"))
  add("/roms2", L("Cartão 2 (/roms2)"))
  return list
end

local function is_inside_roots(path, rs)
  for _, r in ipairs(rs) do
    if path == r.path or path:sub(1, #r.path + 1) == r.path .. "/" then return true end
  end
  return false
end

local function archive_type(name)
  local ext = name:lower():match("%.([%w]+)$")
  return ext and ARCHIVE[ext] or nil
end

--- itens que o gerenciador nao recorta nem exclui (o proprio hub, PortMaster...)
local function protected(path, rs)
  for _, r in ipairs(rs) do if path == r.path then return true end end
  local dir, name = parent(path), basename(path):lower()
  if dir == C.PORTS_DIR and C.PROTECTED_NAMES[name] then return true end
  if path == C.APP_DIR or path:sub(1, #C.APP_DIR + 1) == C.APP_DIR .. "/" then return true end
  -- arquivo sendo usado por uma extracao/instalacao em andamento
  local Inst = require("core.installer")
  local j = Inst.job
  local lf = j and not j.finished and j.opts and j.opts.local_file
  if lf and (lf == path or lf:sub(1, #path + 1) == path .. "/") then return true end
  return false
end

--- pasta do primeiro nivel de um cartao (ex.: /roms/psx, /roms/bios)
local function first_level(path, rs)
  for _, r in ipairs(rs) do if parent(path) == r.path then return true end end
  return false
end

function S:enter(params)
  self.roots = roots()
  self.path = params.path or C.PORTS_DIR
  if not is_inside_roots(self.path, self.roots) then self.path = self.roots[1] and self.roots[1].path or "/" end
  self.sel, self.scroll = 1, 0
  self:load()
end

function S:resume() self:load(true) end
function S:on_catalog() self:load(true) end -- chamado apos extracoes/instalacoes

--- Lista a pasta atual (uma unica chamada ao shell)
function S:load(keep)
  local cur = keep and self.items and self.items[self.sel] and self.items[self.sel].name
  local items = {}
  if self.path == nil then
    for _, r in ipairs(self.roots) do items[#items + 1] = { name = r.label, path = r.path, dir = true, root = true } end
  else
    items[1] = { name = "..", up = true, dir = true }
    local out = U.capture("cd " .. U.shq(self.path) .. " 2>/dev/null && stat -L -c '%F|%s|%n' -- * 2>/dev/null") or ""
    for line in out:gmatch("[^\n]+") do
      local kind, size, name = line:match("^([^|]*)|(%d+)|(.*)$")
      if name and name ~= "" and name:sub(1, 1) ~= "." then
        local dir = kind == "directory"
        items[#items + 1] = { name = name, dir = dir, size = tonumber(size), arc = (not dir) and archive_type(name) or nil,
          path = self.path .. "/" .. name }
      end
    end
    table.sort(items, function(a, b)
      if a.up ~= b.up then return a.up == true end
      if a.dir ~= b.dir then return a.dir end
      -- arquivos compactados logo apos as pastas
      if (a.arc ~= nil) ~= (b.arc ~= nil) then return a.arc ~= nil end
      return a.name:lower() < b.name:lower()
    end)
  end
  self.items = items
  self.sel = 1
  if cur then for i, it in ipairs(items) do if it.name == cur then self.sel = i end end end
  self:clamp()
  self.free = self.path and U.free_space(self.path) or nil
end

function S:clamp()
  local n = #self.items
  self.sel = U.clamp(self.sel, 1, math.max(1, n))
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  self.scroll = U.clamp(self.scroll, 0, math.max(0, n - VISIBLE))
end

local function icon(it, x, y, c)
  G.color(c)
  lg.setLineWidth(2)
  if it.up then
    lg.line(x + 9, y + 15, x + 9, y + 4)
    lg.polygon("fill", x + 9, y + 1, x + 4, y + 8, x + 14, y + 8)
  elseif it.dir then
    lg.polygon("fill", x + 1, y + 4, x + 7, y + 4, x + 9, y + 6, x + 18, y + 6, x + 18, y + 16, x + 1, y + 16)
  else
    lg.rectangle("line", x + 3, y + 1, 12, 15, 1, 1)
    if it.arc then lg.rectangle("fill", x + 8, y + 3, 2, 9) end
  end
  lg.setLineWidth(1)
end

function S:draw()
  G.header(L("Gerenciador de arquivos"))
  -- caminho atual
  G.rect(12, 48, T.W - 24, 26, T.c.bg2, 6)
  local path = self.path or L("Escolha o cartão")
  G.text_fit(T.f.bodyb, path, 22, 52, T.W - 180, T.c.text)
  if self.free then
    local s = U.format_bytes(self.free) .. L(" livres")
    G.text(T.f.small, s, T.W - 22 - T.f.small:getWidth(s), 55, T.c.dim)
  end

  G.panel(12, LIST_Y, T.W - 24, VISIBLE * ROW_H + 8, { bg = T.c.bg1 })
  local n = #self.items
  if n <= 1 and self.path then
    G.text(T.f.body, L("Pasta vazia"), 12, LIST_Y + 150, T.c.faint, "center", T.W - 24)
  end
  for i = self.scroll + 1, math.min(n, self.scroll + VISIBLE) do
    local it = self.items[i]
    local y = LIST_Y + 4 + (i - self.scroll - 1) * ROW_H
    local on = i == self.sel
    if on then
      G.rect(16, y, T.W - 32, ROW_H - 2, T.c.bg3, 5)
      G.frame(16, y, T.W - 32, ROW_H - 2, T.c.accent, 5, 2)
    end
    local c = it.arc and T.c.yellow or (it.dir and T.c.accent2 or T.c.dim)
    icon(it, 26, y + 5, c)
    local label = it.up and L(".. (voltar)") or it.name
    local right = ""
    if it.arc then right = U.format_bytes(it.size)
    elseif not it.dir and it.size then right = U.format_bytes(it.size) end
    local tagw = 0
    if it.arc then
      tagw = T.f.pix8:getWidth(it.arc) + 12
      G.tag(it.arc, T.W - 28 - tagw - 76, y + 7, T.c.yellow, T.c.bg0)
    end
    G.text_fit(T.f.body, label, 54, y + 5, T.W - 54 - 120 - tagw, on and T.c.text or (it.arc and T.c.text or T.c.dim))
    if right ~= "" then G.text(T.f.small, right, T.W - 28 - T.f.small:getWidth(right), y + 7, T.c.faint) end
  end
  if n > VISIBLE then
    local track = VISIBLE * ROW_H - 4
    local h = math.max(18, track * VISIBLE / n)
    local yy = LIST_Y + 6 + (track - h) * (self.scroll / (n - VISIBLE))
    G.rect(T.W - 18, yy, 3, h, T.c.accent2, 1, 0.7)
  end
  if self.busy then
    G.text(T.f.small, self.busy, 12, LIST_Y + VISIBLE * ROW_H + 10, T.c.yellow, "center", T.W - 24)
  elseif CLIP then
    G.text_fit(T.f.small, L("Recortado: ") .. CLIP.name .. L("  •  Y: colar nesta pasta"), 18, LIST_Y + VISIBLE * ROW_H + 10, T.W - 36, T.c.accent2)
  end
  local h = { { "a", L("Abrir / opções") }, { "x", L("Opções") } }
  if CLIP and self.path then h[#h + 1] = { "y", L("Colar") } end
  h[#h + 1] = { "b", L("Voltar") }
  h[#h + 1] = { "l1", "" }
  h[#h + 1] = { "r1", L("Página") }
  G.hints(h)
end

function S:extract(it)
  local p = { id = "file:" .. it.path, slug = U.slug("file_" .. it.name), name = it.name, size = it.size,
    download_url = "", install_check = {}, version = "" }
  -- o arquivo compactado so e excluido se o usuario confirmar depois da extracao
  App.install(p, { local_file = it.path, delete_source = false, ask_delete = true, mode = "extract", dest_dir = self.path })
end

function S:install_port(it)
  local p = { id = "file:" .. it.path, slug = U.slug("file_" .. it.name), name = it.name, size = it.size,
    download_url = "", install_check = {}, version = "" }
  App.show_dialog({
    title = L("Instalar como port?"),
    kind = "info",
    body = it.name .. "  (" .. U.format_bytes(it.size) .. ")\n\n"
      .. L("INSTALAR COMO PORT: instala em ") .. C.PORTS_DIR .. L(" com as verificações da loja (script .sh, sem pastas duplicadas).\n\n")
      .. L("Após a instalação bem-sucedida, o arquivo compactado será excluído."),
    buttons = {
      { label = L("INSTALAR"), fn = function() App.install(p, { local_file = it.path, delete_source = true, mode = "port" }) end },
      { label = L("CANCELAR") },
    },
  })
end

--- a pasta tem script .sh na raiz (formato de port)?
function S:has_script(path)
  local out = U.capture("ls -1 " .. U.shq(path) .. " 2>/dev/null | grep -ciE '\\.sh$'") or ""
  return (tonumber(out:match("%d+")) or 0) > 0
end

--- instala uma pasta ja extraida como port: copia o conteudo para a pasta de ports
--- (nunca sobrescreve; itens protegidos sao recusados)
function S:install_dir(it)
  local list = {}
  local conflicts = {}
  for name in (U.capture("ls -1A " .. U.shq(it.path) .. " 2>/dev/null") or ""):gmatch("[^\n]+") do
    list[#list + 1] = name
    if C.PROTECTED_NAMES[name:lower()] then conflicts[#conflicts + 1] = name .. L(" (protegido)")
    elseif U.exists(C.PORTS_DIR .. "/" .. name) then conflicts[#conflicts + 1] = name .. L(" (já existe)") end
  end
  if #conflicts > 0 then
    App.show_dialog({ title = L("Não é possível instalar"), kind = "error",
      body = L("Estes itens já existem na pasta de ports ou são protegidos:\n") .. table.concat(conflicts, "\n")
        .. L("\n\nNada foi copiado. Desinstale a versão antiga em Meus Ports ou renomeie os itens.") })
    return
  end
  local shown = {}
  for i, n in ipairs(list) do if i > 6 then shown[#shown + 1] = string.format(L("… e mais %d itens"), #list - 6); break end shown[#shown + 1] = "• " .. n end
  App.show_dialog({ title = L("Instalar como port?"), kind = "info",
    body = it.name .. L("\n\nSerá copiado para ") .. C.PORTS_DIR .. ":\n" .. table.concat(shown, "\n")
      .. L("\n\nNada existente é sobrescrito. A pasta original continua onde está."),
    buttons = { { label = L("INSTALAR"), fn = function()
      self:run_op({ op = "install_dir", src = it.path, dest = C.PORTS_DIR, items = list }, it.name)
    end }, { label = L("CANCELAR") } }, sel = 1 })
end

function S:cut(it)
  if protected(it.path, self.roots) then
    App.toast(L("Este item é protegido e não pode ser movido."), "warn"); return
  end
  CLIP = { path = it.path, name = it.name, dir = it.dir }
  App.toast(L("Recortado. Abra a pasta de destino e aperte Y para colar."), "info")
end

function S:ask_delete(it)
  if protected(it.path, self.roots) then
    App.toast(L("Este item é protegido e não pode ser excluído."), "warn"); return
  end
  local body = it.name .. (it.dir and L("  [pasta]") or ("  (" .. U.format_bytes(it.size or 0) .. ")")) .. "\n\n"
    .. (it.dir and L("A pasta e todo o conteúdo dela serão apagados do cartão.") or L("O arquivo será apagado do cartão."))
    .. L(" Não dá para desfazer.")
  if it.dir and first_level(it.path, self.roots) then
    body = body .. "\n\n" .. L("Atenção: esta é uma pasta principal do cartão (sistema, jogos ou BIOS).")
  end
  App.show_dialog({
    title = it.dir and L("Excluir pasta?") or L("Excluir arquivo?"),
    kind = "error",
    body = body,
    buttons = {
      { label = L("EXCLUIR"), danger = true, fn = function() self:run_op({ op = "delete", path = it.path }, it.name) end },
      { label = L("CANCELAR") },
    },
    sel = 2,
  })
end

function S:paste(target)
  target = target or self.path
  if not (CLIP and target) then return end
  local src = CLIP.path
  if not (U.is_dir(src) or U.file_size(src)) then
    CLIP = nil
    App.toast(L("O item recortado não existe mais."), "warn"); return
  end
  if parent(src) == target then
    App.toast(L("O item já está nesta pasta."), "info"); return
  end
  if CLIP.dir and (target == src or target:sub(1, #src + 1) == src .. "/") then
    App.toast(L("Não dá para mover uma pasta para dentro dela mesma."), "warn"); return
  end
  if protected(src, self.roots) then
    App.toast(L("Este item é protegido e não pode ser movido."), "warn"); return
  end
  local dest = target .. "/" .. CLIP.name
  if U.is_dir(dest) or U.file_size(dest) then
    App.toast(L("Já existe um item com esse nome nesta pasta."), "warn"); return
  end
  self:run_op({ op = "move", src = src, dest = dest }, CLIP.name)
end

--- mover/excluir em segundo plano (a tela continua respondendo)
function S:run_op(job, name)
  if self.op then return end
  self.op_seq = (self.op_seq or 0) + 1
  local ch_name = "hub_fileop_" .. self.op_seq
  local ch = love.thread.getChannel(ch_name)
  ch:clear()
  local th = love.thread.newThread("threads/fileop_thread.lua")
  th:start(ch_name, job)
  self.op = { ch = ch, th = th, job = job, name = name }
  self.busy = job.op == "move" and (L("Movendo ") .. name .. "...")
    or (job.op == "install_dir" and (L("Instalando ") .. name .. "...") or (L("Excluindo ") .. name .. "..."))
end

function S:update(dt)
  local o = self.op
  if not o then return end
  local r = o.ch:pop()
  local err = not r and o.th:getError()
  if not r and not err then return end
  self.op, self.busy = nil, nil
  if err then r = { ok = false, error = tostring(err), op = o.job.op } end
  if r.op == "install_dir" then
    if r.ok then
      App.toast(o.name .. L(" instalado em ") .. C.PORTS_DIR .. ".", "ok")
      pcall(function() require("core.manifest").rescan(true); App.on_catalog_changed() end)
    else
      App.show_dialog({ title = L("Não foi possível instalar"), kind = "error", body = o.name .. "\n\n" .. tostring(r.error) })
    end
  elseif r.op == "move" then
    if r.ok then
      CLIP = nil
      App.toast(o.name .. L(" movido para esta pasta."), "ok")
    elseif r.error == "exists" then
      App.toast(L("Já existe um item com esse nome nesta pasta."), "warn")
    else
      App.show_dialog({ title = L("Não foi possível mover"), kind = "error", body = o.name .. "\n\n" .. tostring(r.error) })
    end
  else
    if CLIP and (CLIP.path == o.job.path or CLIP.path:sub(1, #o.job.path + 1) == o.job.path .. "/") then CLIP = nil end
    if r.ok then App.toast(o.name .. L(" excluído."), "ok")
    else App.show_dialog({ title = L("Não foi possível excluir"), kind = "error", body = o.name .. "\n\n" .. tostring(r.error) }) end
  end
  self:load(true)
  App.update_free_space()
end

--- menu de opcoes do item selecionado
function S:options(it)
  if not self.path then return end            -- lista de cartoes
  local btns = {}
  -- colar: nesta pasta ou dentro da pasta selecionada
  if CLIP then
    btns[#btns + 1] = { label = L("Colar nesta pasta"), sub = CLIP.name .. L("  →  ") .. self.path, fn = function() self:paste() end }
    if it and it.dir and not it.up and it.path ~= CLIP.path then
      btns[#btns + 1] = { label = L("Colar dentro de ") .. it.name, sub = CLIP.name .. L("  →  ") .. it.path, fn = function() self:paste(it.path) end }
    end
  end
  if not it or it.up or it.root then
    if #btns == 0 then App.toast(L("Nada recortado para colar."), "info"); return end
    btns[#btns + 1] = { label = L("Cancelar") }
    App.show_dialog({ title = L("Pasta"), kind = "info", list = true, body = self.path, buttons = btns })
    return
  end
  if it.dir and parent(it.path) ~= C.PORTS_DIR and not protected(it.path, self.roots) and self:has_script(it.path) then
    btns[#btns + 1] = { label = L("Instalar como port"), sub = L("Copia o conteúdo da pasta (script .sh e pasta do jogo) para ") .. C.PORTS_DIR,
      fn = function() self:install_dir(it) end }
  end
  if it.arc then
    btns[#btns + 1] = { label = L("Extrair aqui"), sub = L("Descompacta nesta pasta; depois pergunta se exclui o arquivo compactado"), fn = function() self:extract(it) end }
    btns[#btns + 1] = { label = L("Instalar como port"), sub = L("Instala em ") .. C.PORTS_DIR .. L(" com as verificações da loja"), fn = function() self:install_port(it) end }
  end
  btns[#btns + 1] = { label = L("Recortar"), sub = L("Depois abra a pasta de destino: Y ou Opções > Colar"), fn = function() self:cut(it) end }
  btns[#btns + 1] = { label = L("Excluir"), sub = it.dir and L("Apaga a pasta e todo o conteúdo") or L("Apaga o arquivo"), danger = true, fn = function() self:ask_delete(it) end }
  btns[#btns + 1] = { label = L("Cancelar") }
  App.show_dialog({
    title = it.dir and L("Pasta") or (it.arc and (L("Arquivo ") .. it.arc) or L("Arquivo")),
    kind = "info", list = true,
    body = it.name .. (it.dir and "" or ("  (" .. U.format_bytes(it.size or 0) .. ")")),
    buttons = btns,
  })
end

function S:go_up()
  if self.path == nil then App.pop(); return end
  for _, r in ipairs(self.roots) do
    if self.path == r.path then
      if #self.roots > 1 then
        self.path = nil
        self:load()
      else
        App.pop()
      end
      return
    end
  end
  local from = basename(self.path)
  self.path = parent(self.path)
  self:load()
  for i, it in ipairs(self.items) do if it.name == from then self.sel = i end end
  self:clamp()
end

function S:action(act)
  local n = #self.items
  if act == "up" and n > 0 then self.sel = (self.sel - 2) % n + 1; self:clamp()
  elseif act == "down" and n > 0 then self.sel = self.sel % n + 1; self:clamp()
  elseif act == "l1" or act == "left" then self.sel = math.max(1, self.sel - VISIBLE); self:clamp()
  elseif act == "r1" or act == "right" then self.sel = math.min(n, self.sel + VISIBLE); self:clamp()
  elseif act == "b" then self:go_up()
  elseif self.op then return       -- movendo/excluindo: espera terminar
  elseif act == "x" then self:options(self.items[self.sel])
  elseif act == "y" then self:paste()
  elseif act == "a" then
    local it = self.items[self.sel]
    if not it then return end
    if it.up then self:go_up()
    elseif it.dir then
      self.path = it.path
      self:load()
    else
      self:options(it)
    end
  end
end

return S
