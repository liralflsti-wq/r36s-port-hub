-- =============================================================================
--  Verificador de compatibilidade dos ports (somente analise).
--
--  1) Ambiente do console (detectado UMA vez por sessao, sem internet):
--     modelo (Analisador de Console, se ja foi usado; senao Device Tree),
--     SoC (Device Tree / cpuinfo), arquitetura (uname -m), arquitetura dos
--     pacotes (dpkg), sistema (core/osdetect), kernel (uname -r), glibc
--     (getconf), RAM (/proc/meminfo), resolucao (DRM do kernel), graficos
--     (/dev/dri, bibliotecas EGL/GLES), PortMaster e runtimes instalados
--     (PortMaster/libs/*.squashfs e PortMaster/runtimes/*).
--  2) Requisitos do port: so os que o catalogo informa, no objeto "compat"
--     (ou "attr", o mesmo formato do port.json do PortMaster). Nada e
--     inventado: sem requisitos -> NAO VERIFICADO.
--  3) Resultado: compatible | experimental | incompatible | unverified,
--     com a lista do que foi comparado (ok / falha / ausente / desconhecido).
--  Nunca executa ports, nunca instala nada, nunca altera arquivos.
-- =============================================================================
local I18N = require("lib.i18n")
local Lk = I18N.L                                   -- chave (traduzida ao desenhar)
local L = function(s) return I18N.tr(s) end         -- traduzida na hora (textos montados em pedacos)
local U = require("lib.util")
local C = require("config")

local M = {}

local ROOT = os.getenv("PORTHUB_ROOTFS") or ""
M.env = nil
M.cache = {}       -- id do port -> resultado (vale para o ambiente atual)

local function rd(p)
  local s = U.read_file(ROOT .. p)
  return s and U.trim((s:gsub("%z", " "))) or nil
end
local function cmd1(c)
  local s = U.trim(U.capture(c .. " 2>/dev/null") or "")
  s = s:match("^[^\n]*") or ""
  return s ~= "" and s or nil
end

--- arquitetura em nome padrao
function M.norm_arch(a)
  if not a then return nil end
  a = a:lower()
  if a == "arm64" or a == "aarch64" or a == "armv8" then return "aarch64" end
  if a == "armhf" or a:match("^armv7") or a == "arm32" or a == "arm" then return "armhf" end
  if a == "amd64" or a == "x86_64" or a == "x64" then return "x86_64" end
  if a:match("^i%d86$") or a == "x86" then return "x86" end
  return a
end

-- ---------------------------------------------------------------------------
-- Ambiente
local LIBDIRS = { "/usr/lib", "/usr/lib/aarch64-linux-gnu", "/usr/lib/arm-linux-gnueabihf", "/lib",
  "/lib/aarch64-linux-gnu", "/lib/arm-linux-gnueabihf", "/usr/lib64", "/lib64", "/usr/local/lib" }

-- arquivos das pastas de bibliotecas, lidos uma vez (um unico comando)
local LIBS = nil
local function lib_index()
  if LIBS then return LIBS end
  LIBS = {}
  local args = {}
  for _, d in ipairs(LIBDIRS) do args[#args + 1] = U.shq(ROOT .. d) end
  local out = U.capture("ls -1 " .. table.concat(args, " ") .. " 2>/dev/null") or ""
  local dir
  for line in out:gmatch("[^\n]+") do
    local h = line:match("^(.+):$")
    if h then dir = h:sub(#ROOT + 1)
    elseif dir and line ~= "" then LIBS[#LIBS + 1] = { dir = dir, name = line } end
  end
  return LIBS
end

local function find_lib(name)
  local best
  for _, f in ipairs(lib_index()) do
    if f.name == name then return f.dir .. "/" .. f.name end
    if not best and f.name:sub(1, #name + 1) == name .. "." then best = f.dir .. "/" .. f.name end
  end
  return best
end
M.find_lib = find_lib

local function resolution()
  -- modo atual informado pelo kernel (DRM): primeira linha de "modes" de um conector ligado
  local list = U.capture("ls -1d " .. U.shq(ROOT .. "/sys/class/drm") .. "/card*-* 2>/dev/null") or ""
  for d in list:gmatch("[^\n]+") do
    local st = U.trim(U.read_file(d .. "/status") or "")
    local m = U.trim(U.read_file(d .. "/modes") or ""):match("^(%d+x%d+)")
    if m and (st == "connected" or st == "") then return m, "drm" end
  end
  if ROOT == "" and love.window and love.window.getDesktopDimensions then
    local w, h = love.window.getDesktopDimensions()
    if w and w > 0 then return w .. "x" .. h, "sdl" end
  end
  return nil
end

local function runtimes(pm)
  local t, list = {}, {}
  if not pm then return t, list end
  local out = U.capture("ls -1 " .. U.shq(pm .. "/libs") .. " 2>/dev/null") or ""
  for n in out:gmatch("[^\n]+") do
    local base = n:match("^(.+)%.squashfs$")
    if base and not t[base] then t[base] = "libs/" .. n; list[#list + 1] = base end
  end
  out = U.capture("ls -1 " .. U.shq(pm .. "/runtimes") .. " 2>/dev/null") or ""
  for n in out:gmatch("[^\n]+") do
    if not t[n] then t[n] = "runtimes/" .. n; list[#list + 1] = n end
  end
  table.sort(list)
  return t, list
end

--- detecta o ambiente (uma vez; force = de novo)
function M.detect(force)
  if M.env and not force then return M.env end
  if force then LIBS = nil end
  local e = { time = os.time() }
  -- modelo: resultado do Analisador de Console (quando o usuario ja o executou)
  local okc, CID = pcall(require, "core.consoleid")
  local last = okc and CID.load_last() or nil
  if last and last.result and last.result.model and last.result.class ~= "unknown" then
    e.model, e.model_src = last.result.model, "consoleid"
  end
  local dtm = rd("/proc/device-tree/model") or rd("/sys/firmware/devicetree/base/model")
  if not e.model and dtm and dtm ~= "" then e.model, e.model_src = dtm, "devicetree" end
  e.board = dtm
  -- SoC
  local comp = rd("/proc/device-tree/compatible") or rd("/sys/firmware/devicetree/base/compatible") or ""
  e.soc = comp:match("rockchip,(rk%d+)") or comp:match("allwinner,(sun%w+)") or comp:match("amlogic,(%w+)")
  if not e.soc then
    local ci = U.read_file(ROOT .. "/proc/cpuinfo") or ""
    e.soc = ci:match("Hardware%s*:%s*([^\n]+)")
  end
  if e.soc then e.soc = U.trim(e.soc) end
  -- arquitetura do kernel e dos pacotes
  e.arch = M.norm_arch(os.getenv("PORTHUB_TEST_ARCH") or (ROOT == "" and cmd1("uname -m") or rd("/test/uname_m")))
  e.pkg_arch = M.norm_arch(ROOT == "" and cmd1("dpkg --print-architecture") or rd("/test/dpkg_arch"))
  -- sistema
  local okd, OSD = pcall(require, "core.osdetect")
  local os_ = okd and OSD.detect() or {}
  e.os_id, e.os_name, e.os_version, e.os_conf = os_.id, os_.name, os_.version, os_.confidence
  -- kernel e glibc
  e.kernel = ROOT == "" and cmd1("uname -r") or rd("/test/uname_r")
  local gl = ROOT == "" and cmd1("getconf GNU_LIBC_VERSION") or rd("/test/glibc")
  e.glibc = gl and gl:match("(%d+%.%d+)")
  -- RAM
  local mi = U.read_file(ROOT .. "/proc/meminfo") or ""
  local kb = tonumber(mi:match("MemTotal:%s*(%d+)") or "")
  e.ram_mb = kb and math.floor(kb / 1024 + 0.5) or nil
  -- tela
  e.res, e.res_src = resolution()
  -- graficos
  e.dri = U.exec_ok("test -e " .. U.shq(ROOT .. "/dev/dri/card0"))
  e.gpu_driver = nil
  local drv = U.trim(U.capture("readlink " .. U.shq(ROOT .. "/sys/class/drm/card0/device/driver") .. " 2>/dev/null") or "")
  if drv ~= "" then e.gpu_driver = drv:match("([^/]+)$") end
  e.egl = find_lib("libEGL.so") ~= nil
  e.gles = find_lib("libGLESv2.so") ~= nil
  e.mali = find_lib("libmali.so") ~= nil
  -- PortMaster e runtimes
  local okr, RT = pcall(require, "core.runtimes")
  e.pm = okr and RT.detect_pm() or nil
  e.runtimes, e.runtime_list = runtimes(e.pm)
  e.ports_dir = C.PORTS_DIR
  -- impressao digital: muda quando sistema, kernel ou runtimes mudam
  e.fingerprint = table.concat({ e.os_id or "?", e.os_version or "?", e.kernel or "?", e.arch or "?",
    table.concat(e.runtime_list, ","), e.model or "?" }, "|")
  local prev = U.read_file(love.filesystem.getSaveDirectory() .. "/compat_env.txt")
  e.changed = prev ~= nil and U.trim(prev) ~= e.fingerprint
  e.prev_fingerprint = prev and U.trim(prev) or nil
  U.write_file(love.filesystem.getSaveDirectory() .. "/compat_env.txt", e.fingerprint .. "\n")
  M.env = e
  M.cache = {}
  return e
end

--- algo mudou no console (ex.: runtimes atualizados): refaz na proxima consulta
function M.invalidate()
  M.env = nil
  LIBS = nil
  M.cache = {}
end

-- ---------------------------------------------------------------------------
-- Requisitos do port
local function as_list(v)
  if v == nil then return nil end
  if type(v) == "table" then return v end
  return { v }
end

--- junta "compat" (formato do hub) e "attr" (port.json do PortMaster)
function M.requirements(p)
  local c = type(p.compat) == "table" and p.compat or {}
  local a = type(p.attr) == "table" and p.attr or {}
  local r = {
    arch = as_list(c.arch or a.arch),
    os = as_list(c.os),
    os_exclude = as_list(c.os_exclude),
    min_os_version = type(c.min_os_version) == "table" and c.min_os_version or nil,
    min_kernel = c.min_kernel,
    min_glibc = c.min_glibc or a.min_glibc,
    min_ram_mb = tonumber(c.min_ram_mb or ""),
    resolutions = as_list(c.resolutions or c.resolution),
    min_resolution = c.min_resolution,
    runtimes = as_list(c.runtimes or c.runtime or a.runtime),
    libs = as_list(c.libs),
    gpu = as_list(c.gpu),
    soc = as_list(c.soc),
    files = as_list(c.files),
    tested = type(c.tested) == "table" and c.tested or nil,
    experimental = (c.experimental == true) or (a.exp == true) or (c.status == "experimental"),
    incompatible_note = c.incompatible,
    notes = c.notes,
    reqs = as_list(a.reqs),
  }
  -- runtime vazio do PortMaster ("" / {}) nao conta
  if r.runtimes then
    local t = {}
    for _, x in ipairs(r.runtimes) do if type(x) == "string" and x ~= "" then t[#t + 1] = x end end
    r.runtimes = #t > 0 and t or nil
  end
  local any = false
  for k, v in pairs(r) do
    if v ~= nil and v ~= false and k ~= "notes" then any = true end
  end
  r.any = any
  return r
end

-- ---------------------------------------------------------------------------
-- Comparacoes
local function vcmp(a, b)
  local ta, tb = {}, {}
  for n in tostring(a):gmatch("%d+") do ta[#ta + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do tb[#tb + 1] = tonumber(n) end
  if #ta == 0 or #tb == 0 then return nil end
  for i = 1, math.max(#ta, #tb) do
    local x, y = ta[i] or 0, tb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end
M.vcmp = vcmp

--- familia de um runtime: tudo antes do primeiro numero (ex.: "mono-6.12..." -> "mono")
local function rt_family(name)
  local f = name:match("^(.-)[%-_]?%d") or name
  return f:lower()
end

local function res_wh(s)
  local w, h = tostring(s or ""):match("(%d+)%s*[xX]%s*(%d+)")
  return tonumber(w), tonumber(h)
end

--- avalia um port; resultado guardado em cache para o ambiente atual
function M.evaluate(p)
  if not p or p.builtin then return nil end
  local e = M.detect()
  local key = tostring(p.id) .. "|" .. tostring(I18N.lang)
  local hit = M.cache[key]
  if hit and hit.port == p then return hit end
  local req = M.requirements(p)
  local items = {}
  local function add(group, status, label, detail)
    items[#items + 1] = { group = group, status = status, label = label, detail = detail }
  end
  local res = { port = p, req = req, items = items, env = e }

  if not req.any then
    res.status = "unverified"
    res.reason = L("O catálogo não informa os requisitos deste port. Não há dados suficientes para confirmar a compatibilidade.")
    M.cache[key] = res
    return res
  end

  -- arquitetura
  if req.arch then
    local want = {}
    for _, a in ipairs(req.arch) do want[#want + 1] = M.norm_arch(a) end
    local det = e.arch
    if not det then add("arch", "unknown", L("Arquitetura"), table.concat(want, ", "))
    else
      local ok = false
      for _, a in ipairs(want) do
        if a == det or (a == "armhf" and det == "aarch64" and e.pkg_arch == "armhf") then ok = true end
      end
      add("arch", ok and "ok" or "fail", L("Arquitetura"), L("exige ") .. table.concat(want, ", ") .. L("; console: ") .. det)
    end
  end

  -- sistema
  if req.os_exclude and e.os_id then
    for _, o in ipairs(req.os_exclude) do
      if o:lower() == e.os_id then add("os", "fail", L("Sistema"), L("não funciona em ") .. (e.os_name or e.os_id)) end
    end
  end
  if req.os then
    if not e.os_id then add("os", "unknown", L("Sistema"), table.concat(req.os, ", "))
    else
      local ok = false
      for _, o in ipairs(req.os) do if o:lower() == e.os_id then ok = true end end
      add("os", ok and "ok" or "warn", L("Sistema"),
        (ok and "" or L("não testado em ")) .. (e.os_name or e.os_id) .. L("; lista do port: ") .. table.concat(req.os, ", "))
    end
  end
  if req.min_os_version and e.os_id then
    local need = req.min_os_version[e.os_id]
    if need then
      local c = e.os_version and vcmp(e.os_version, need)
      if c == nil then add("os", "unknown", L("Versão do sistema"), L("mínima ") .. need .. L("; versão instalada não identificada"))
      else add("os", c >= 0 and "ok" or "fail", L("Versão do sistema"), L("mínima ") .. need .. L("; instalada ") .. e.os_version) end
    end
  end
  if req.min_kernel then
    local c = e.kernel and vcmp(e.kernel, req.min_kernel)
    if c == nil then add("os", "unknown", L("Kernel"), L("mínimo ") .. req.min_kernel)
    else add("os", c >= 0 and "ok" or "fail", L("Kernel"), L("mínimo ") .. req.min_kernel .. L("; console: ") .. e.kernel) end
  end
  if req.min_glibc then
    local c = e.glibc and vcmp(e.glibc, req.min_glibc)
    if c == nil then add("os", "unknown", "glibc", L("mínima ") .. req.min_glibc)
    else add("os", c >= 0 and "ok" or "fail", "glibc", L("mínima ") .. req.min_glibc .. L("; console: ") .. e.glibc) end
  end

  -- hardware
  if req.soc then
    if not e.soc then add("hw", "unknown", "SoC", table.concat(req.soc, ", "))
    else
      local ok = false
      for _, s in ipairs(req.soc) do if s:lower() == e.soc:lower() then ok = true end end
      add("hw", ok and "ok" or "warn", "SoC", (ok and "" or L("não listado: ")) .. e.soc .. L("; lista do port: ") .. table.concat(req.soc, ", "))
    end
  end
  if req.min_ram_mb then
    if not e.ram_mb then add("hw", "unknown", L("Memória RAM"), L("mínimo ") .. req.min_ram_mb .. " MB")
    else
      -- a RAM total informada fica um pouco abaixo da instalada (parte vai para o kernel/GPU)
      local ok = e.ram_mb >= req.min_ram_mb * 0.9
      add("hw", ok and "ok" or "fail", L("Memória RAM"), L("mínimo ") .. req.min_ram_mb .. L(" MB; console: ") .. e.ram_mb .. " MB")
    end
  end
  if req.min_resolution then
    local nw, nh = res_wh(req.min_resolution)
    local w, h = res_wh(e.res)
    if not w or not nw then add("hw", "unknown", L("Resolução"), L("mínima ") .. tostring(req.min_resolution))
    else add("hw", (w >= nw and h >= nh) and "ok" or "fail", L("Resolução"), L("mínima ") .. req.min_resolution .. L("; tela: ") .. e.res) end
  end
  if req.resolutions then
    if not e.res then add("hw", "unknown", L("Resolução"), table.concat(req.resolutions, ", "))
    else
      local ok = false
      for _, r in ipairs(req.resolutions) do if r == e.res then ok = true end end
      add("hw", ok and "ok" or "warn", L("Resolução"), (ok and "" or L("não testada em ")) .. e.res .. L("; lista do port: ") .. table.concat(req.resolutions, ", "))
    end
  end
  if req.gpu then
    for _, g in ipairs(req.gpu) do
      local gl = g:lower()
      if gl == "gles" or gl == "gles2" or gl == "gles3" then
        add("hw", e.gles and "ok" or "unknown", L("Gráficos"), "OpenGL ES" .. (e.gles and L(" (biblioteca encontrada)") or L(" (biblioteca não encontrada nas pastas padrão)")))
      elseif gl == "egl" then
        add("hw", e.egl and "ok" or "unknown", L("Gráficos"), "EGL" .. (e.egl and L(" (biblioteca encontrada)") or L(" (biblioteca não encontrada nas pastas padrão)")))
      elseif gl == "drm" or gl == "kms" then
        add("hw", e.dri and "ok" or "fail", L("Gráficos"), "DRM/KMS" .. (e.dri and " (/dev/dri/card0)" or L(" (/dev/dri ausente)")))
      else
        add("hw", "unknown", L("Gráficos"), g .. L(" (o hub não sabe verificar este requisito)"))
      end
    end
  end

  -- runtimes (PortMaster)
  if req.runtimes then
    for _, want in ipairs(req.runtimes) do
      local name, op, ver = want:match("^([%w%._%-]-)%s*(>=)%s*([%d%.]+)$")
      if not name then name = want end
      if op then
        -- "familia>=versao": confere a versao instalada
        local best
        for _, n in ipairs(e.runtime_list) do
          if rt_family(n) == name:lower() then
            local c = vcmp(n:match("(%d[%d%.]*)"), ver)
            if c and (not best or c >= 0) then best = { n = n, c = c } end
          end
        end
        if not e.pm then add("rt", "missing", want, L("PortMaster não encontrado no console"))
        elseif not best then add("rt", "missing", want, L("não instalado"))
        elseif best.c >= 0 then add("rt", "ok", want, L("instalado: ") .. best.n)
        else add("rt", "fail", want, L("versão instalada incompatível: ") .. best.n) end
      else
        if e.runtimes[name] then add("rt", "ok", name, L("instalado (") .. e.runtimes[name] .. ")")
        elseif not e.pm then add("rt", "missing", name, L("PortMaster não encontrado no console"))
        else
          local other = {}
          for _, n in ipairs(e.runtime_list) do if rt_family(n) == rt_family(name) then other[#other + 1] = n end end
          if #other > 0 then add("rt", "missing", name, L("não instalado; existe outra versão: ") .. table.concat(other, ", "))
          else add("rt", "missing", name, L("não instalado")) end
        end
      end
    end
  end

  -- bibliotecas do sistema
  if req.libs then
    for _, lib in ipairs(req.libs) do
      local f = find_lib(lib)
      add("lib", f and "ok" or "missing", lib, f and (L("encontrada: ") .. f) or L("não encontrada nas pastas padrão do sistema"))
    end
  end

  -- arquivos esperados no console (ex.: pasta de BIOS)
  if req.files then
    for _, f in ipairs(req.files) do
      local path = f:gsub("^%$PORTS", C.PORTS_DIR)
      if path:find("%.%.") then path = nil end
      local ok = path and U.exists(ROOT .. path)
      add("file", ok and "ok" or "missing", f, ok and L("encontrado") or L("não encontrado"))
    end
  end

  -- requisitos do PortMaster ("reqs"): o hub registra, mas so verifica os que conhece
  if req.reqs then
    for _, r in ipairs(req.reqs) do
      add("hw", "unknown", r, L("requisito informado pelo PortMaster; o hub não sabe verificar"))
    end
  end

  -- testes registrados pelos responsaveis/usuarios
  local tested_hit
  if req.tested then
    for _, t in ipairs(req.tested) do
      if type(t) == "table" then
        local dev = tostring(t.device or ""):lower()
        local os_ok = (not t.os) or (e.os_id and tostring(t.os):lower() == e.os_id)
          or (e.os_name and tostring(t.os):lower() == e.os_name:lower())
        local dev_ok = dev == "" or (e.model and e.model:lower():find(dev, 1, true) ~= nil)
        if os_ok and dev_ok then
          tested_hit = t
          local st = (t.result == "ok") and "ok" or ((t.result == "fail") and "fail" or "warn")
          add("test", st, L("Teste registrado"), (t.device or "?") .. " / " .. (t.os or "?") .. ": "
            .. ((t.result == "ok") and L("funcionou") or ((t.result == "fail") and L("não funcionou") or L("funcionou com problemas")))
            .. ((t.note and t.note ~= "") and (" — " .. t.note) or ""))
        end
      end
    end
  end

  -- classificacao
  local n = { ok = 0, fail = 0, warn = 0, missing = 0, unknown = 0 }
  for _, it in ipairs(items) do n[it.status] = (n[it.status] or 0) + 1 end
  res.counts = n
  if n.fail > 0 or req.incompatible_note then
    res.status = "incompatible"
    local first
    for _, it in ipairs(items) do if it.status == "fail" then first = it; break end end
    res.reason = first and (L("Incompatibilidade encontrada: ") .. first.label .. " (" .. first.detail .. ").")
      or (L("O catálogo marca este port como incompatível: ") .. tostring(req.incompatible_note))
  elseif n.ok == 0 and not req.experimental then
    res.status = "unverified"
    res.reason = L("Os requisitos informados não puderam ser comparados com o console (informações do console ausentes).")
  elseif n.missing > 0 then
    res.status = "experimental"
    res.reason = L("Este port exige uma dependência que não foi encontrada no console. Consulte os requisitos antes de instalar.")
  elseif n.warn > 0 or n.unknown > 0 or req.experimental then
    res.status = "experimental"
    if req.experimental then
      res.reason = L("O responsável pelo port o marca como experimental.")
    elseif n.warn > 0 then
      res.reason = L("O port pode funcionar, mas há condições não confirmadas para este console.")
    else
      res.reason = L("O port pode funcionar, mas alguns requisitos não puderam ser confirmados no console.")
    end
  else
    res.status = "compatible"
    res.reason = L("Este port possui requisitos conhecidos e compatíveis com o ambiente identificado.")
  end
  M.cache[key] = res
  return res
end

M.LABEL = { compatible = Lk("COMPATÍVEL"), experimental = Lk("EXPERIMENTAL"), incompatible = Lk("INCOMPATÍVEL"), unverified = Lk("NÃO VERIFICADO") }
M.COLOR = { compatible = "green", experimental = "yellow", incompatible = "red", unverified = "dim" }

return M
