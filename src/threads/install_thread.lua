-- =============================================================================
--  R36S PORT HUB - thread de instalacao
--  Roda fora da thread principal para nao travar a interface.
--  Etapas: espaco -> download -> verificacao -> extracao (pasta temporaria)
--          -> analise da estrutura -> confirmacao de sobrescrita -> instalacao
--  Comunicacao: canal de saida (mensagens para a interface) e canal de entrada
--  (cancelar / resposta da confirmacao).
-- =============================================================================
require("love.timer")

local job = ...
require("love.filesystem")
local I18N = require("lib.i18n")
I18N.set(job.lang or "pt-BR")
local L = I18N.L
local OUT = love.thread.getChannel(job.out_channel)
local IN = love.thread.getChannel(job.in_channel)

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end
local function ok(r) return r == 0 or r == true end
local function sh(cmd) return ok(os.execute(cmd)) end
local function capture(cmd)
  local h = io.popen(cmd)
  if not h then return "" end
  local s = h:read("*a") or ""
  h:close()
  return s
end
local function log(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  print("[install] " .. table.concat(t, " "))
  io.stdout:flush()
end
local function send(msg) OUT:push(msg) end
local function fsize(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:seek("end")
  f:close()
  return s
end
local function read_all(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local WORK = job.tmp_dir .. "/job_" .. job.slug
local ZIP = WORK .. "/download.zip"
local PART = ZIP .. ".part"
local STAGE = WORK .. "/stage"
local PIDF = WORK .. "/dl.pid"
local RCF = WORK .. "/dl.rc"

local cancelled = false
local extract_7z
local function check_cancel()
  local m = IN:pop()
  while m do
    if m.t == "cancel" then cancelled = true end
    m = IN:pop()
  end
  return cancelled
end

local function cleanup()
  sh("rm -rf " .. shq(WORK) .. " 2>/dev/null")
end

local function fail(code, detail)
  log("ERRO", code, detail or "")
  cleanup()
  send({ t = "error", code = code, detail = detail or "" })
end

local function cancel_done()
  log("cancelado pelo usuario")
  cleanup()
  send({ t = "cancelled" })
end

local function free_bytes(path)
  local out = capture("df -Pk " .. shq(path) .. " 2>/dev/null | tail -n 1")
  local avail = out:match("^%S+%s+%d+%s+%d+%s+(%d+)")
  return avail and tonumber(avail) * 1024 or nil
end

local function lower(s) return (s or ""):lower() end

-- ---------------------------------------------------------------------------
-- Extrator para RAR e 7z. Prefere o 7-Zip incluso (bin/7zzs, aarch64 estatico),
-- copiado para /tmp porque o cartao pode nao permitir executar binarios.
local function find_7z()
  local cands = {}
  if job.sevenzip and job.sevenzip ~= "" then cands[#cands + 1] = job.sevenzip end
  local tmpbin = "/tmp/r36sporthub-7zzs"
  if job.bundled_7z and sh("test -f " .. shq(job.bundled_7z)) then
    sh("cp -f " .. shq(job.bundled_7z) .. " " .. shq(tmpbin) .. " 2>/dev/null && chmod 755 " .. shq(tmpbin))
    cands[#cands + 1] = tmpbin
  end
  for _, n in ipairs({ "7zz", "7zzs", "7z", "7za" }) do
    local pth = capture("command -v " .. n .. " 2>/dev/null"):match("^(%S+)")
    if pth then cands[#cands + 1] = pth end
  end
  for _, c in ipairs(cands) do
    if sh(shq(c) .. " i >/dev/null 2>&1") then return c end
  end
  return nil
end

extract_7z = function(fmt)
  local X = find_7z()
  local unrar = (not X and fmt == "rar") and capture("command -v unrar 2>/dev/null"):match("^(%S+)") or nil
  if not X and not unrar then fail("no_extractor", fmt:upper()); return false end

  local entries, unpacked = 0, 0
  if X then
    log("extrator:", X)
    -- lista tecnica: caminhos, tamanhos, pastas, criptografia
    local listing = capture(shq(X) .. " l -slt -ba -p- " .. shq(ZIP) .. " 2>&1; echo __PHX:$?")
    local lcode = tonumber(listing:match("__PHX:(%d+)")) or 2
    if listing:find("Wrong password") or listing:find("Encrypted = %+") or listing:find("Can not open encrypted") then
      fail("encrypted"); return false
    end
    if lcode > 1 then fail("bad_zip", (listing:match("ERROR: ([^\n]+)") or ""):sub(1, 80)); return false end
    for block in (listing .. "\n\n"):gmatch("(Path = .-)\n\n") do
      local path = block:match("^Path = ([^\n]*)")
      if path and path ~= "" then
        entries = entries + 1
        path = path:gsub("\\", "/")
        if path:sub(1, 1) == "/" or path:find("^%a:") or path:find("%.%./") or path:find("/%.%.$") or path == ".." then
          fail("unsafe_zip", path); return false
        end
        unpacked = unpacked + (tonumber(block:match("\nSize = (%d+)")) or 0)
      end
    end
  else
    log("extrator: unrar", unrar)
    local listing = capture(shq(unrar) .. " lb -p- " .. shq(ZIP) .. " 2>/dev/null")
    for line in listing:gmatch("[^\n]+") do
      entries = entries + 1
      if line:sub(1, 1) == "/" or line:find("%.%./") then fail("unsafe_zip", line); return false end
    end
  end
  if entries == 0 then fail("bad_zip"); return false end

  local avail = free_bytes(job.ports_dir)
  if avail and avail < unpacked + job.margin then
    fail("no_space", string.format("%d|%d", unpacked + job.margin, avail)); return false
  end

  send({ t = "phase", phase = "extract", total = entries })
  local cmd
  if X then
    -- -mmt1: um processo de descompactacao (menos memoria no R36S)
    cmd = shq(X) .. " x -y -p- -mmt1 -bb1 -bso1 -bse1 -bsp0 -o" .. shq(STAGE) .. " " .. shq(ZIP) .. " 2>&1; echo __PHX:$?"
  else
    cmd = "cd " .. shq(STAGE) .. " && " .. shq(unrar) .. " x -o+ -y -p- " .. shq(ZIP) .. " 2>&1; echo __PHX:$?"
  end
  local h = io.popen(cmd)
  local count, code, lastpct, errl = 0, nil, -1, nil
  if h then
    for line in h:lines() do
      local c = line:match("^__PHX:(%d+)")
      if c then code = tonumber(c)
      else
        if line:match("^%- ") or line:match("^Extracting%s") or line:match("^Creating%s") then
          count = count + 1
        elseif not errl and (line:find("ERROR") or line:find("Error")) then
          errl = line
        end
        local pct = math.floor(count / entries * 100)
        if pct ~= lastpct then
          send({ t = "progress", phase = "extract", done = math.min(count, entries), total = entries })
          lastpct = pct
        end
        if count % 25 == 0 and check_cancel() then break end
      end
    end
    h:close()
  end
  if cancelled then cancel_done(); return false end
  -- 7-Zip: 0 = ok, 1 = aviso; 2 = erro fatal; 8 = sem memoria. unrar: 0 = ok
  if code == nil or code > 1 then
    if errl and (errl:find("[Ww]rong password") or errl:find("encrypted")) then fail("encrypted"); return false end
    if errl and errl:lower():find("space") then fail("no_space", ""); return false end
    if code == 8 then fail("no_memory"); return false end
    fail("bad_zip", (errl or (L("codigo ") .. tostring(code))):sub(1, 80)); return false
  end
  return true
end

-- ---------------------------------------------------------------------------
local function run()
  log("iniciando:", job.name, "->", job.ports_dir)

  -- 0) preparacao -----------------------------------------------------------
  send({ t = "phase", phase = "prepare" })
  if not sh("test -d " .. shq(job.ports_dir)) then
    return fail("no_ports_dir", job.ports_dir)
  end
  if not sh("test -w " .. shq(job.ports_dir)) then
    return fail("no_write", job.ports_dir)
  end
  cleanup()
  if not sh("mkdir -p " .. shq(STAGE)) then
    return fail("no_write", job.tmp_dir)
  end

  local expected, got
  if job.local_file then
    -- arquivo que ja esta no cartao (Gerenciador de arquivos): sem download
    PART = job.local_file
    got = fsize(PART) or 0
    log("arquivo local:", PART, got, "bytes")
  else

  -- tamanho esperado: catalogo ou cabecalho do servidor
  expected = tonumber(job.expected_size)
  if not expected or expected <= 0 then
    local h = capture("sh " .. shq(job.fetch_sh) .. " head " .. shq(job.url) .. " 2>/dev/null")
    expected = tonumber(h:match("(%d+)"))
    if expected and expected <= 0 then expected = nil end
  end

  -- 1) espaco para o ZIP ----------------------------------------------------
  local avail = free_bytes(job.ports_dir)
  if expected and avail and avail < expected + job.margin then
    return fail("no_space", string.format("%d|%d", expected + job.margin, avail))
  end
  if check_cancel() then return cancel_done() end

  -- 2) download (em segundo plano, com acompanhamento) ---------------------
  send({ t = "phase", phase = "download", total = expected })
  os.remove(PART); os.remove(RCF); os.remove(PIDF)
  sh("sh " .. shq(job.fetch_sh) .. " get " .. shq(job.url) .. " " .. shq(PART) .. " "
    .. shq(PIDF) .. " " .. shq(RCF) .. " >" .. shq(WORK .. "/fetch.log") .. " 2>&1 &")

  local last_push = -1
  local rc
  while true do
    love.timer.sleep(0.25)
    local s = read_all(RCF)
    if s and s:match("%d+") then rc = tonumber(s:match("%d+")); break end
    if check_cancel() then
      local pid = (read_all(PIDF) or ""):match("%d+")
      if pid then sh("kill " .. pid .. " 2>/dev/null") end
      -- espera o script terminar
      for _ = 1, 40 do
        love.timer.sleep(0.1)
        if read_all(RCF) then break end
      end
      return cancel_done()
    end
    local done = fsize(PART) or 0
    if done ~= last_push then
      send({ t = "progress", phase = "download", done = done, total = expected })
      last_push = done
    end
  end

  got = fsize(PART) or 0
  send({ t = "progress", phase = "download", done = got, total = expected })
  if rc ~= 0 then
    local flog = read_all(WORK .. "/fetch.log") or ""
    log("fetch rc=", rc, flog)
    if rc == 22 then return fail("http_error", flog:match("error:%s*([^\n]+)") or "") end
    if rc == 127 then return fail("no_curl") end
    if rc == 23 then return fail("no_space", "") end
    return fail("net_error", tostring(rc))
  end
  end -- fim do download

  -- 3) verificacao ----------------------------------------------------------
  send({ t = "phase", phase = "verify" })
  if got <= 0 then return fail("empty_file") end
  local f = io.open(PART, "rb")
  local head = f and f:read(512) or ""
  if f then f:close() end
  -- formato pela assinatura do arquivo (nao pela extensao do link)
  local fmt
  if head:sub(1, 2) == "PK" then fmt = "zip"
  elseif head:sub(1, 7) == "Rar!\26\7\0" or head:sub(1, 8) == "Rar!\26\7\1\0" then fmt = "rar"
  elseif head:sub(1, 6) == "7z\188\175\39\28" then fmt = "7z"
  end
  if not fmt then
    local low = lower(head):gsub("^%s+", "")
    local what = "desconhecido"
    if low:find("^<!doct") or low:find("^<html") then
      what = (head:match("<[Tt][Ii][Tt][Ll][Ee]>%s*(.-)%s*</") or L("página HTML")):sub(1, 60)
    elseif low:sub(1, 1) == "{" or low:sub(1, 1) == "[" then
      what = L("resposta JSON")
    end
    return fail("not_zip", what)
  end
  log("formato do pacote:", fmt)
  if expected and got ~= expected then
    return fail("size_mismatch", string.format("%d|%d", got, expected))
  end
  if job.sha256 and job.sha256 ~= "" then
    local sum = capture("sha256sum " .. shq(PART) .. " 2>/dev/null"):match("^(%x+)")
    if not sum then
      log("sha256sum indisponivel; pulando verificacao")
    elseif lower(sum) ~= lower(job.sha256) then
      return fail("checksum")
    end
  elseif job.md5 and job.md5 ~= "" then
    local sum = capture("md5sum " .. shq(PART) .. " 2>/dev/null"):match("^(%x+)")
    if sum and lower(sum) ~= lower(job.md5) then return fail("checksum") end
  end
  if job.local_file then
    ZIP = PART      -- usa o arquivo no lugar (so e excluido apos sucesso)
  elseif not os.rename(PART, ZIP) then
    return fail("no_write", WORK)
  end
  if check_cancel() then return cancel_done() end

  if fmt == "zip" then
    if not sh("command -v unzip >/dev/null 2>&1") then return fail("no_unzip") end
    -- lista do ZIP: tamanho descompactado, quantidade de itens, caminhos perigosos
    local listing = capture("unzip -Z1 " .. shq(ZIP) .. " 2>/dev/null")
    local entries = 0
    for line in listing:gmatch("[^\n]+") do
      entries = entries + 1
      if line:sub(1, 1) == "/" or line:find("%.%./") or line:find("/%.%.$") or line == ".." then
        return fail("unsafe_zip", line)
      end
    end
    if entries == 0 then return fail("bad_zip") end
    local summary = capture("unzip -l " .. shq(ZIP) .. " 2>/dev/null | tail -n 1")
    local unpacked = tonumber(summary:match("^%s*(%d+)")) or 0

    -- 4) espaco para extrair ---------------------------------------------------
    local avail = free_bytes(job.ports_dir)
    if avail and avail < unpacked + job.margin then
      return fail("no_space", string.format("%d|%d", unpacked + job.margin, avail))
    end

    -- 5) extracao para a pasta temporaria ------------------------------------
    send({ t = "phase", phase = "extract", total = entries })
    local h = io.popen("unzip -o " .. shq(ZIP) .. " -d " .. shq(STAGE) .. " 2>&1; echo __PHX:$?")
    local count, code, lastpct = 0, nil, -1
    local errlines = {}
    if h then
      for line in h:lines() do
        local c = line:match("^__PHX:(%d+)")
        if c then
          code = tonumber(c)
        else
          if line:match("^%s+inflating:") or line:match("^%s+extracting:") or line:match("^%s+creating:")
              or line:match("^%s+linking:") then
            count = count + 1
          elseif line:lower():find("error") or line:lower():find("bad") then
            errlines[#errlines + 1] = line
          end
          local pct = math.floor(count / entries * 100)
          if pct ~= lastpct then
            send({ t = "progress", phase = "extract", done = count, total = entries })
            lastpct = pct
          end
          if count % 25 == 0 and check_cancel() then break end
        end
      end
      h:close()
    end
    if cancelled then return cancel_done() end
    -- unzip: 0 = ok, 1 = avisos (ok); >1 = erro (arquivo corrompido, disco cheio...)
    if code == nil or code > 1 then
      local detail = errlines[1] or (L("codigo ") .. tostring(code))
      if code == 50 then return fail("no_space", "") end
      return fail("bad_zip", detail)
    end
  else
    -- RAR / 7z: extrator 7-Zip (incluso no hub) ou o do sistema
    local ok7, err7 = extract_7z(fmt)
    if not ok7 then return end
  end

  -- 6) analise da estrutura ------------------------------------------------
  send({ t = "phase", phase = "analyze" })
  local JUNK = { ["__macosx"] = true, [".ds_store"] = true, ["thumbs.db"] = true, ["desktop.ini"] = true }

  local function list(dir)
    local items = {}
    local out = capture("cd " .. shq(dir) .. " && for f in * .[!.]* ..?*; do "
      .. "[ -e \"$f\" ] || [ -L \"$f\" ] || continue; "
      .. "if [ -d \"$f\" ] && [ ! -L \"$f\" ]; then echo \"D:$f\"; else echo \"F:$f\"; fi; done")
    for line in out:gmatch("[^\n]+") do
      local kind, name = line:match("^([DF]):(.+)$")
      if name and not JUNK[lower(name)] then
        items[#items + 1] = { name = name, dir = (kind == "D") }
      end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
  end
  local function has_script(items)
    for _, it in ipairs(items) do
      if not it.dir and lower(it.name):match("%.sh$") then return true end
    end
    return false
  end

  -- Remove pastas "embrulho" para nao criar diretorios duplicados:
  --   roms/ports/Jogo.sh  ->  Jogo.sh
  --   ports/Jogo.sh       ->  Jogo.sh
  --   Jogo/Jogo.sh + Jogo/jogo/  ->  Jogo.sh + jogo/   (so se nao houver .sh na raiz)
  local root = STAGE
  for _ = 1, (job.mode == "extract" and 0 or 4) do
    local items = list(root)
    if #items == 1 and items[1].dir then
      local n = lower(items[1].name)
      local inner = root .. "/" .. items[1].name
      if n == "roms" or n == "roms2" or n == "ports" then
        root = inner
      elseif not has_script(items) and has_script(list(inner)) then
        root = inner
      else
        break
      end
    else
      break
    end
  end

  local items = list(root)
  if #items == 0 then return fail("empty_pkg") end
  if job.mode ~= "extract" and not has_script(items) and not job.allow_no_script then
    return fail("no_script")
  end

  -- Itens protegidos (PortMaster, o proprio hub, gamelist.xml) sao ignorados
  local install, skipped = {}, {}
  for _, it in ipairs(items) do
    if job.mode ~= "extract" and job.protected[lower(it.name)] then
      skipped[#skipped + 1] = it.name
    else
      install[#install + 1] = it
    end
  end
  if #install == 0 then return fail("empty_pkg") end

  -- 7) conflitos com o que ja esta instalado ------------------------------
  local conflicts = {}
  for _, it in ipairs(install) do
    if sh("test -e " .. shq(job.ports_dir .. "/" .. it.name) .. " -o -L " .. shq(job.ports_dir .. "/" .. it.name)) then
      conflicts[#conflicts + 1] = it.name
      it.exists = true
    end
  end
  if #conflicts > 0 and job.preapproved then
    log("substituicao ja confirmada pelo usuario:", table.concat(conflicts, ", "))
  elseif #conflicts > 0 then
    send({ t = "confirm", items = conflicts })
    local answer
    while answer == nil do
      local m = IN:demand(0.5)
      if m then
        if m.t == "answer" then answer = m.yes and true or false
        elseif m.t == "cancel" then answer = false end
      end
    end
    if not answer then return cancel_done() end
  end

  -- 8) instalacao -------------------------------------------------------------
  send({ t = "phase", phase = "install", total = #install })
  local installed = {}
  for i, it in ipairs(install) do
    local src = root .. "/" .. it.name
    local dst = job.ports_dir .. "/" .. it.name
    local okmv
    if it.exists and it.dir and sh("test -d " .. shq(dst) .. " -a ! -L " .. shq(dst)) then
      -- Atualizacao: mescla, mantendo arquivos extras do usuario (saves, dados do jogo)
      okmv = sh("cp -a " .. shq(src) .. "/. " .. shq(dst) .. "/ 2>/dev/null || cp -rf "
        .. shq(src) .. "/. " .. shq(dst) .. "/")
    else
      if it.exists then sh("rm -rf " .. shq(dst)) end
      okmv = sh("mv -f " .. shq(src) .. " " .. shq(dst))
    end
    if not okmv then
      return fail("install_failed", it.name)
    end
    installed[#installed + 1] = it.name
    send({ t = "progress", phase = "install", done = i, total = #install })
  end

  -- scripts executaveis
  for _, name in ipairs(installed) do
    if lower(name):match("%.sh$") then
      sh("chmod +x " .. shq(job.ports_dir .. "/" .. name) .. " 2>/dev/null")
    end
  end
  -- RAR/7z feitos no Windows nao guardam a permissao de execucao:
  -- devolve +x aos scripts .sh e aos binarios ELF dentro das pastas do port
  if fmt ~= "zip" and job.mode ~= "extract" then
    for _, name in ipairs(installed) do
      local d = job.ports_dir .. "/" .. name
      if sh("test -d " .. shq(d) .. " -a ! -L " .. shq(d)) then
        -- pastas precisam de permissao de acesso (x) para o usuario do console
        sh("find " .. shq(d) .. " -type d -exec chmod u+rwx,go+rx {} + 2>/dev/null")
        sh("find " .. shq(d) .. " -type f \\( -name '*.sh' -o ! -name '*.*' -o -name '*.bin' -o -name '*.aarch64' -o -name '*.arm64' -o -name '*.elf' \\) "
          .. "-exec sh -c 'for f; do case \"$f\" in *.sh) chmod +x \"$f\";; *) [ \"$(head -c 4 \"$f\" 2>/dev/null)\" = \"$(printf \"\\177ELF\")\" ] && chmod +x \"$f\";; esac; done' sh {} + 2>/dev/null")
      end
    end
  end
  sh("sync")

  -- 9) limpeza (remove o ZIP temporario e a pasta de trabalho) ----------------
  cleanup()
  local deleted = false
  if job.local_file and job.delete_source then
    deleted = os.remove(job.local_file) and true or false
    log(deleted and L("arquivo compactado excluido:") or L("nao foi possivel excluir:"), job.local_file)
  end
  log("instalado:", table.concat(installed, ", "))
  send({ t = "done", entries = installed, skipped = skipped, deleted = deleted })
end

local okrun, err = pcall(run)
if not okrun then
  log("falha interna:", err)
  pcall(cleanup)
  send({ t = "error", code = "internal", detail = tostring(err) })
end
