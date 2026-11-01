-- =============================================================================
--  Manutencao > Analisador do cartao SD (somente leitura, so quando pedido)
--  A analisa/entra na pasta | B volta uma pasta (ou sai) | L1/R1 trocam a aba
--  Y analisa de novo
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Ftp = require("core.ftp")
local lg = love.graphics

local S = {}
local TABS = { L("PASTAS"), L("MAIORES ARQUIVOS") }
local LIST_Y, ROW_H, VISIBLE = 132, 38, 8

local function df(root)
  local out = U.capture("df -Pk " .. U.shq(root) .. " 2>/dev/null") or ""
  for line in out:gmatch("[^\n]+") do
    local total, used, avail, mount = line:match("%s(%d+)%s+(%d+)%s+(%d+)%s+%d+%%%s+(/.*)$")
    if total then
      return { total = tonumber(total) * 1024, used = tonumber(used) * 1024, free = tonumber(avail) * 1024, mount = mount }
    end
  end
end

function S:enter()
  self.root = Ftp.detect_root() or C.PORTS_DIR
  self.disk = df(self.root)
  self.state = "idle"
  self.tab = 1
  self.sel, self.scroll = 1, 0
end

function S:leave() self:cancel() end

function S:start()
  self.state = "scanning"
  self.progress = { files = 0, bytes = 0, elapsed = 0 }
  self.out = love.thread.getChannel("hub_sdscan_out")
  self.ctl = love.thread.getChannel("hub_sdscan_ctl")
  self.out:clear(); self.ctl:clear()
  self.t0 = love.timer.getTime()
  self.thread = love.thread.newThread("threads/sdscan_thread.lua")
  self.thread:start(self.root, "hub_sdscan_out", "hub_sdscan_ctl", C.TMP_DIR .. "/sdscan.pid")
  self.disk = df(self.root)
end

function S:cancel()
  if self.state == "scanning" and self.ctl then self.ctl:push("cancel") end
end

function S:update()
  if self.state ~= "scanning" then return end
  local e = self.thread:getError()
  if e then
    U.log("sdscan:", e)
    self.state, self.error = "error", L("A análise falhou: ") .. tostring(e)
    return
  end
  local m = self.out:pop()
  while m do
    if m.t == "progress" then self.progress = m
    elseif m.t == "cancelled" then
      self.state = "idle"
      App.toast(L("Análise cancelada."), "info")
    elseif m.t == "done" then
      self.result = m
      self.state = "done"
      self:open_dir(self.root)
      App.toast(string.format(L("Análise concluída: %d arquivos em %s."), m.files, U.format_time(m.elapsed)), "ok")
    end
    m = self.out:pop()
  end
end

--- lista da pasta: subpastas (tamanhos da analise) + arquivos (lidos agora)
function S:open_dir(path, keep_sel)
  self.cwd = path
  local items = {}
  local dirs = self.result.dirs
  local prefix = path .. "/"
  for p, e in pairs(dirs) do
    if p:sub(1, #prefix) == prefix and not p:sub(#prefix + 1):find("/") then
      items[#items + 1] = { name = p:sub(#prefix + 1), path = p, dir = true, size = e.size }
    end
  end
  local out = U.capture("cd " .. U.shq(path) .. " 2>/dev/null && find . -maxdepth 1 -type f -exec stat -c '%s|%n' {} + 2>/dev/null") or ""
  for line in out:gmatch("[^\n]+") do
    local size, name = line:match("^(%d+)|%./(.*)$")
    if size then items[#items + 1] = { name = name, path = path .. "/" .. name, size = tonumber(size) } end
  end
  table.sort(items, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    return a.name:lower() < b.name:lower()
  end)
  self.items = items
  self.dir_total = (dirs[path] and dirs[path].size) or 0
  if not keep_sel then self.sel, self.scroll = 1, 0 end
end

local function vpath(self, p)
  if p == self.root then return "/" end
  return p:sub(#self.root + 1)
end

function S:draw_disk()
  local d = self.disk
  local x, y, w = 12, 48, T.W - 24
  G.panel(x, y, w, 48, { bg = T.c.bg1 })
  if not d then
    G.text(T.f.body, L("Não foi possível ler o espaço do cartão (") .. self.root .. ").", x + 12, y + 14, T.c.red)
    return
  end
  local frac = d.total > 0 and d.used / d.total or 0
  G.text(T.f.bodyb, L("Cartão: ") .. self.root, x + 12, y + 6, T.c.text)
  local info = string.format(L("Total %s  •  Usado %s (%d%%)  •  Livre %s"), U.format_bytes(d.total), U.format_bytes(d.used),
    math.floor(frac * 100 + 0.5), U.format_bytes(d.free))
  G.text(T.f.small, info, x + w - 12 - T.f.small:getWidth(info), y + 8, T.c.dim)
  G.progress(x + 12, y + 30, w - 24, 10, frac, frac > 0.9 and T.c.red or (frac > 0.75 and T.c.yellow or T.c.accent2))
end

function S:draw()
  G.header(L("Analisador do cartão SD"), L("Somente leitura"))
  T.with_base_fonts(self.draw_disk, self)   -- faixa de 48 px: tamanho padrao
  local px, py, pw = 12, 104, T.W - 24
  if self.state == "idle" or self.state == "error" then
    G.panel(px, py, pw, 330, { bg = T.c.bg1 })
    G.text(T.f.pix16, L("ANALISAR O CARTÃO"), px, py + 100, T.c.accent2, "center", pw)
    G.text(T.f.body, L("Mostra o tamanho de cada pasta e os maiores arquivos.\nA análise só lê o cartão: nada é movido, alterado ou apagado.\nCartões cheios podem levar alguns minutos."),
      px + 30, py + 140, T.c.dim, "center", pw - 60)
    if self.error then G.text(T.f.small, self.error, px + 20, py + 230, T.c.red, "center", pw - 40) end
    G.hints({ { "a", L("Analisar agora") }, { "b", L("Voltar") } })
    return
  end
  if self.state == "scanning" then
    G.panel(px, py, pw, 330, { bg = T.c.bg1 })
    G.text(T.f.pix16, L("ANALISANDO..."), px, py + 100, T.c.yellow, "center", pw)
    G.progress_busy(px + 60, py + 136, pw - 120, 10, App.t, T.c.yellow)
    local p = self.progress
    G.text(T.f.body, string.format(L("%d arquivos lidos  •  %s  •  %s"), p.files or 0, U.format_bytes(p.bytes or 0),
      U.format_time(love.timer.getTime() - self.t0)), px, py + 160, T.c.text, "center", pw)
    G.hints({ { "b", L("Cancelar") } })
    return
  end

  -- resultado
  local r = self.result
  local x = 12
  G.button_icon("l1", x, 106)
  x = x + 30
  for i, t in ipairs(TABS) do
    local w = T.f.pix8:getWidth(t) + 24
    local on = i == self.tab
    G.rect(x, 102, w, 24, on and T.c.accent or T.c.bg2, 5)
    G.text(T.f.pix8, t, x, 110, on and T.c.bg0 or T.c.dim, "center", w)
    x = x + w + 8
  end
  G.button_icon("r1", x, 106)
  local summary
  if self.tab == 1 then
    summary = vpath(self, self.cwd) .. "  •  " .. U.format_bytes(self.dir_total)
  else
    summary = string.format(L("%d arquivos  •  %s  •  análise em %s"), r.files, U.format_bytes(r.bytes), U.format_time(r.elapsed))
  end
  local sw = math.min(T.f.small:getWidth(summary), T.W - 14 - x - 30)
  G.text_fit(T.f.small, summary, T.W - 14 - sw, 106, sw, self.tab == 1 and T.c.accent2 or T.c.faint)

  local list = self.tab == 1 and self.items or r.top
  G.panel(12, LIST_Y, T.W - 24, VISIBLE * ROW_H + 8, { bg = T.c.bg1 })
  if #list == 0 then
    G.text(T.f.body, self.tab == 1 and L("Pasta vazia.") or L("Nenhum arquivo encontrado."), 12, LIST_Y + 140, T.c.faint, "center", T.W - 24)
  end
  self.sel = U.clamp(self.sel, 1, math.max(1, #list))
  if self.sel <= self.scroll then self.scroll = self.sel - 1 end
  if self.sel > self.scroll + VISIBLE then self.scroll = self.sel - VISIBLE end
  for i = self.scroll + 1, math.min(#list, self.scroll + VISIBLE) do
    local e = list[i]
    local y = LIST_Y + 4 + (i - self.scroll - 1) * ROW_H
    local on = i == self.sel
    if on then G.rect(16, y, T.W - 32, ROW_H - 2, T.c.bg3, 5); G.frame(16, y, T.W - 32, ROW_H - 2, T.c.accent, 5, 2) end
    local name, sub
    if self.tab == 1 then
      name = e.name
      local frac = self.dir_total > 0 and e.size / self.dir_total or 0
      sub = string.format(L("%s  •  %d%% desta pasta"), e.dir and L("Pasta") or L("Arquivo"), math.floor(frac * 100 + 0.5))
      if frac >= 0.005 then G.rect(48, y + ROW_H - 6, (T.W - 200) * frac, 2, e.dir and T.c.accent2 or T.c.yellow, 1) end
      -- icone
      G.color(e.dir and T.c.accent2 or T.c.dim)
      if e.dir then
        lg.rectangle("fill", 24, y + 10, 16, 12, 2, 2); lg.rectangle("fill", 24, y + 7, 7, 4, 1, 1)
      else
        lg.rectangle("line", 26, y + 7, 12, 16, 2, 2)
      end
    else
      name = e.path:match("([^/]+)$")
      sub = vpath(self, e.path:match("^(.*)/[^/]+$") or self.root)
      G.text(T.f.pix8, tostring(i), 20, y + 14, T.c.faint, "center", 22)
    end
    local ft, fs, ty, sy = G.row_fonts(ROW_H - 2, 3, 19)
    G.text_fit(ft, name, 48, y + ty, T.W - 200, on and T.c.text or T.c.dim)
    G.text_fit(fs, sub, 48, y + sy, T.W - 200, T.c.faint)
    local sz = U.format_bytes(e.size)
    G.text(ft, sz, T.W - 28 - ft:getWidth(sz), y + 9 + math.floor((T.base_font(T.f.bodyb):getHeight() - ft:getHeight()) / 2), on and T.c.text or T.c.dim)
  end
  local hints = { { "l1", L("Aba") } }
  local cur = list[self.sel]
  if self.tab == 1 and cur and cur.dir then hints[#hints + 1] = { "a", L("Abrir pasta") } end
  hints[#hints + 1] = { "b", (self.tab == 1 and self.cwd ~= self.root) and L("Pasta acima") or L("Voltar") }
  hints[#hints + 1] = { "y", L("Analisar de novo") }
  G.hints(hints)
end

function S:action(act)
  if self.state == "scanning" then
    if act == "b" then self:cancel() end
    return
  end
  if self.state ~= "done" then
    if act == "a" then self:start()
    elseif act == "b" then App.pop() end
    return
  end
  local list = self.tab == 1 and self.items or self.result.top
  if act == "up" then self.sel = math.max(1, self.sel - 1)
  elseif act == "down" then self.sel = math.min(math.max(1, #list), self.sel + 1)
  elseif act == "left" then self.sel = math.max(1, self.sel - VISIBLE)
  elseif act == "right" then self.sel = math.min(math.max(1, #list), self.sel + VISIBLE)
  elseif act == "l1" or act == "r1" then
    self.tab = self.tab == 1 and 2 or 1
    self.sel, self.scroll = 1, 0
    if self.tab == 1 then self:open_dir(self.cwd) end
  elseif act == "y" then self:start()
  elseif act == "a" and self.tab == 1 then
    local e = list[self.sel]
    if e and e.dir then
      self.back = self.back or {}
      self.back[#self.back + 1] = { sel = self.sel, scroll = self.scroll }
      self:open_dir(e.path)
    end
  elseif act == "b" then
    if self.tab == 1 and self.cwd ~= self.root then
      self:open_dir(self.cwd:match("^(.*)/[^/]+$") or self.root)
      local b = self.back and table.remove(self.back)
      if b then self.sel, self.scroll = b.sel, b.scroll end
    else
      App.pop()
    end
  end
end

return S
