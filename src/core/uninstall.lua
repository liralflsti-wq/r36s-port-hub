-- =============================================================================
--  Exclusao de um jogo instalado (Meus Ports, botao X)
--
--  Reaproveita a identificacao de ports ja existente (registro do hub + varredura
--  de /roms/ports) e so permite excluir quando os arquivos do jogo estao
--  identificados com SEGURANCA:
--    - registro do hub (o hub sabe exatamente o que instalou), ou
--    - itens declarados pelo PortMaster (port.json) ou por um arquivo .port, ou
--    - a pasta declarada no GAMEDIR= do proprio script.
--  Uma pasta reconhecida apenas pelo nome parecido NAO basta.
--  Nunca apaga: a pasta /roms/ports, PortMaster, runtimes/bibliotecas, o proprio
--  hub, pastas usadas por outro jogo ou qualquer coisa fora de /roms/ports.
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")
local Scan = require("core.scan")
local Manifest = require("core.manifest")

local X = { job = nil, seq = 0 }

-- nomes que nunca sao apagados, mesmo que algum metadado os cite
local NEVER = {
  ["portmaster"] = true, ["portmaster.sh"] = true, ["r36sporthub"] = true, ["r36s port hub.sh"] = true,
  ["gamelist.xml"] = true, ["images"] = true, ["videos"] = true, ["manuals"] = true,
  ["libs"] = true, ["runtimes"] = true, ["ports"] = true, ["bios"] = true, ["themes"] = true,
  ["tools"] = true, ["roms"] = true, ["roms2"] = true, ["."] = true, [".."] = true,
}

local function valid_name(n)
  return type(n) == "string" and n ~= "" and not n:find("/") and not n:find("%z") and not NEVER[n:lower()]
    and not C.PROTECTED_NAMES[n:lower()]
end

local function mounts()
  local t = {}
  local s = U.read_file("/proc/mounts") or ""
  for line in s:gmatch("[^\n]+") do
    local mp = line:match("^%S+%s+(%S+)")
    if mp then t[#t + 1] = (mp:gsub("\\040", " ")) end
  end
  return t
end

--- Monta o plano de exclusao. Devolve plano ou (nil, motivo)
function X.plan(p)
  Manifest.rescan(true)
  local ports_real = U.trim(U.capture("readlink -f " .. U.shq(C.PORTS_DIR) .. " 2>/dev/null") or "")
  if ports_real == "" or ports_real == "/" or not U.is_dir(ports_real) then
    return nil, L("A pasta de ports não pôde ser verificada.")
  end

  local found, by = Manifest.found(p)
  if not found or #found == 0 then
    return nil, L("Os arquivos deste jogo não foram encontrados no cartão."), { nothing = true }
  end
  -- nada do que estava registrado existe mais (apagado por fora, ex.: pelo FTP)
  local any = false
  for _, n in ipairs(found) do if Scan.exists(n) then any = true end end
  if not any then
    return nil, L("O arquivo .sh e a pasta deste jogo não existem mais no cartão. Nada precisa ser apagado."), { nothing = true }
  end

  local targets, set, evidence = {}, {}, {}
  local function add(n)
    if n and not set[n] and Scan.exists(n) then
      set[n] = true
      targets[#targets + 1] = n
    end
  end

  local scripts = {}
  for _, n in ipairs(found) do
    if n:lower():match("%.sh$") and Scan.entries[n] == "file" then scripts[#scripts + 1] = n end
  end
  if #scripts == 0 then
    return nil, L("O arquivo de inicialização (.sh) deste jogo não existe no cartão, então os arquivos dele não podem ser identificados com segurança. Nada foi apagado."), { no_script = true }
  end

  local certain = false
  if by == "hub" then
    -- o hub instalou: o registro lista exatamente os itens
    for _, n in ipairs(found) do add(n) end
    certain = true
    evidence[#evidence + 1] = L("registro de instalação da loja")
  end
  for _, sh in ipairs(scripts) do
    add(sh)
    local lp = Scan.by_script[sh]
    if lp then
      if lp.pm_items then
        for _, n in ipairs(lp.pm_items) do add(n) end
        certain = true
        evidence[#evidence + 1] = L("port.json do PortMaster")
      elseif lp.port_items then
        for _, n in ipairs(lp.port_items) do add(n) end
        certain = true
        evidence[#evidence + 1] = L("arquivo .port")
      elseif lp.gamedir then
        add(lp.gamedir)           -- se a pasta ja nao existir, so o script e removido
        certain = true
        evidence[#evidence + 1] = L("GAMEDIR do script")
      end
    end
  end
  local note
  if not certain then
    -- sem registro/port.json/GAMEDIR: usa a pasta que o script cita (cd, gamedir=...)
    -- ou a pasta com o mesmo nome do script. O usuario ve a lista exata antes de confirmar.
    for _, sh in ipairs(scripts) do
      local lp = Scan.by_script[sh]
      if lp and lp.refdir and Scan.entries[lp.refdir] == "dir" then
        add(lp.refdir); evidence[#evidence + 1] = L("pasta citada no script")
      elseif lp and lp.dir and lp.dir_source == "nome" and Scan.entries[lp.dir] == "dir" then
        add(lp.dir); evidence[#evidence + 1] = L("pasta com o mesmo nome do script")
      end
    end
    if #targets == #scripts then
      note = L("A pasta do jogo não foi encontrada: só o script será removido.")
    end
  end

  -- validacoes de seguranca
  local mts = mounts()
  for _, n in ipairs(targets) do
    if not valid_name(n) then
      return nil, L("O item \"") .. n .. L("\" é protegido (sistema, PortMaster ou runtimes) e não pode ser apagado. Nada foi apagado.")
    end
    local abs = ports_real .. "/" .. n
    if Scan.entries[n] == "dir" then
      for _, mp in ipairs(mts) do
        if mp == abs or mp:sub(1, #abs + 1) == abs .. "/" then
          return nil, L("A pasta \"") .. n .. L("\" está em uso (há algo montado nela). Feche os jogos e tente de novo. Nada foi apagado.")
        end
      end
      -- pasta usada por outro jogo?
      for _, other in ipairs(Scan.ports) do
        if not set[other.script] then
          local uses = other.dir == n or other.gamedir == n
          for _, it in ipairs(other.pm_items or other.port_items or {}) do if it == n then uses = true end end
          if uses then
            return nil, L("A pasta \"") .. n .. L("\" também é usada por \"") .. other.script .. L("\". Para não quebrar o outro jogo, nada foi apagado.")
          end
        end
      end
    end
  end

  -- tamanho (informativo; limitado a poucos segundos)
  local sizes = {}
  for _, n in ipairs(targets) do
    local out = U.capture("timeout 4 du -sk " .. U.shq(ports_real .. "/" .. n) .. " 2>/dev/null") or ""
    local kb = tonumber(out:match("^(%d+)"))
    sizes[n] = kb and kb * 1024 or nil
  end
  -- a pasta do jogo nao foi localizada (so o .sh): a tela oferece escolher a pasta a mao
  local has_dir = false
  for _, n in ipairs(targets) do if Scan.entries[n] == "dir" then has_dir = true end end
  local expected
  for _, sh in ipairs(scripts) do
    local lp = Scan.by_script[sh]
    expected = expected or (lp and (lp.gamedir or lp.refdir)) or nil
  end
  table.sort(targets, function(a, b)
    local da, db = Scan.entries[a] == "dir", Scan.entries[b] == "dir"
    if da ~= db then return not da end
    return a:lower() < b:lower()
  end)
  return { port = p, base = ports_real, targets = targets, sizes = sizes, evidence = evidence, note = note,
    scripts = scripts, missing_dir = not has_dir, expected_dir = expected, set = set,
    is_dir = function(n) return Scan.entries[n] == "dir" end }
end

--- Pasta escolhida a mao para um port cujo .sh existe mas a pasta nao foi
--- localizada. So aceita uma pasta DIRETAMENTE dentro da pasta de ports, que
--- nao seja link, protegida, montada ou usada por outro jogo.
--- Devolve nome (relativo a pasta de ports) ou nil, motivo
function X.check_folder(plan, abs)
  if type(abs) ~= "string" or abs == "" then return nil, L("Nenhuma pasta escolhida.") end
  abs = abs:gsub("/+$", "")
  local name = abs:match("([^/]+)$")
  local parent = abs:match("^(.*)/[^/]+$") or ""
  if abs == "" or abs == "/" or not name then return nil, L("A raiz do cartão não pode ser apagada.") end
  if U.exec_ok("test -L " .. U.shq(abs)) then
    return nil, L("A pasta escolhida é um link simbólico. Por segurança, ela não é apagada.")
  end
  if not U.is_dir(abs) then return nil, L("A pasta escolhida não existe mais.") end
  local rp = U.trim(U.capture("readlink -f -- " .. U.shq(parent) .. " 2>/dev/null") or "")
  if rp ~= plan.base then
    return nil, L("Só uma pasta que esteja diretamente dentro da pasta de ports pode ser apagada: ") .. plan.base
  end
  if not valid_name(name) then
    return nil, L("A pasta \"") .. name .. L("\" é protegida (sistema, PortMaster, runtimes ou o próprio hub) e não pode ser apagada.")
  end
  local real = U.trim(U.capture("readlink -f -- " .. U.shq(abs) .. " 2>/dev/null") or "")
  if real == "" or real == plan.base or real:sub(1, #plan.base + 1) ~= plan.base .. "/" then
    return nil, L("A pasta escolhida fica fora da pasta de ports.")
  end
  for _, mp in ipairs(mounts()) do
    if mp == real or mp:sub(1, #real + 1) == real .. "/" then
      return nil, L("A pasta \"") .. name .. L("\" está em uso (há algo montado nela). Nada foi apagado.")
    end
  end
  for _, other in ipairs(Scan.ports) do
    if not plan.set[other.script] then
      local uses = other.dir == name or other.gamedir == name or other.refdir == name
      for _, it in ipairs(other.pm_items or other.port_items or {}) do if it == name then uses = true end end
      if uses then
        return nil, L("A pasta \"") .. name .. L("\" é usada por outro jogo (\"") .. other.script .. L("\"). Nada foi apagado.")
      end
    end
  end
  return name
end

--- acrescenta a pasta escolhida ao plano (depois de check_folder)
function X.add_folder(plan, name)
  if plan.set[name] then return end
  plan.set[name] = true
  plan.targets[#plan.targets + 1] = name
  plan.manual_dir = name
  plan.missing_dir = false
  plan.evidence[#plan.evidence + 1] = L("pasta escolhida manualmente")
  local out = U.capture("timeout 4 du -sk " .. U.shq(plan.base .. "/" .. name) .. " 2>/dev/null") or ""
  local kb = tonumber(out:match("^(%d+)"))
  plan.sizes[name] = kb and kb * 1024 or nil
  local is_dir = plan.is_dir
  plan.is_dir = function(n) return n == name or is_dir(n) end
end

--- limpa o registro de um jogo que nao existe mais no cartao
function X.clear_record(p)
  local had = Manifest.data[p.id] ~= nil
  if had then Manifest.data[p.id] = nil; Manifest.save() end
  Manifest.invalidate()
  Manifest.rescan(true)
  return had
end

function X.busy() return X.job ~= nil and not X.job.finished end

function X.start(plan)
  if X.busy() then return false end
  X.seq = X.seq + 1
  local j = { plan = plan, finished = false, out = "hub_del_out_" .. X.seq }
  j.ch = love.thread.getChannel(j.out)
  j.ch:clear()
  j.thread = love.thread.newThread("threads/delete_thread.lua")
  j.thread:start({ out_channel = j.out, base = plan.base, items = plan.targets })
  X.job = j
  U.log("excluindo:", plan.port.name, table.concat(plan.targets, ", "))
  return true
end

function X.update()
  local j = X.job
  if not j or j.finished then return end
  local err = j.thread:getError()
  if err then
    j.finished, j.ok, j.error = true, false, L("Erro interno: ") .. tostring(err)
    return
  end
  local m = j.ch:pop()
  while m do
    if m.t == "done" then
      j.finished, j.ok, j.failed = true, (#(m.failed or {}) == 0), m.failed or {}
      -- remove o registro do hub so se tudo foi apagado; atualiza a lista de instalados
      local p = j.plan.port
      if j.ok and Manifest.data[p.id] then
        Manifest.data[p.id] = nil
        Manifest.save()
      end
      Manifest.rescan(true)
    end
    m = j.ch:pop()
  end
end

function X.clear() if X.job and X.job.finished then X.job = nil end end

return X
