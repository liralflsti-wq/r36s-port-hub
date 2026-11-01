-- =============================================================================
--  Atualizacoes do hub: formatos dos pacotes e ferramentas de extracao
--  Nada e presumido: o formato vem dos primeiros bytes do arquivo e cada
--  ferramenta e testada no console (o 7-Zip que acompanha o hub, 7z/7zz/7za
--  do sistema, unzip, unrar). So os formatos com ferramenta que funciona
--  ficam disponiveis. Usado na thread principal e na thread de atualizacao.
-- =============================================================================
local M = {}

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end
M.shq = shq

local function capture(cmd)
  local h = io.popen(cmd)
  if not h then return "" end
  local s = h:read("*a") or ""
  h:close()
  return s
end
M.capture = capture

M.EXT = { zip = "zip", ["7z"] = "7z", rar = "rar" }
M.LABEL = { zip = "ZIP", ["7z"] = "7Z", rar = "RAR" }

--- formato pelos primeiros bytes ("zip" | "7z" | "rar" | nil)
function M.detect_magic(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local h = f:read(8) or ""
  f:close()
  if h:sub(1, 4) == "PK\3\4" or h:sub(1, 4) == "PK\5\6" then return "zip" end
  if h:sub(1, 6) == "7z\188\175\39\28" then return "7z" end
  if h:sub(1, 7) == "Rar!\26\7\0" or h:sub(1, 8) == "Rar!\26\7\1\0" then return "rar" end
  return nil
end

--- testa as ferramentas. opts = { bundled = caminho do 7zzs do hub, env = PORTHUB_7Z }
--- Devolve { zip = tool, ["7z"] = tool, rar = tool, list = {...} } (tool = { kind, bin, name })
function M.detect_tools(opts)
  opts = opts or {}
  local res = { list = {} }
  local function try7(bin, name)
    if not bin or bin == "" then return end
    local out = capture(shq(bin) .. " i 2>/dev/null")
    if not out:find("Formats:", 1, true) then return end
    local t = { kind = "7z", bin = bin, name = name }
    res.list[#res.list + 1] = name
    local fmt = out:match("Formats:(.-)Codecs:") or out
    if not res.zip and fmt:find("%szip%s") then res.zip = t end
    if not res["7z"] and fmt:find("%s7z%s") then res["7z"] = t end
    if not res.rar and (fmt:find("%sRar5%s") or fmt:find("%sRar%s")) then res.rar = t end
  end
  if opts.env and opts.env ~= "" then try7(opts.env, "7-Zip (PORTHUB_7Z)") end
  -- 7-Zip que acompanha o hub: o cartao pode nao permitir executar, entao roda de /tmp
  if opts.bundled and io.open(opts.bundled, "rb") then
    local tmpbin = "/tmp/r36sporthub-7zzs"
    os.execute("cp -f " .. shq(opts.bundled) .. " " .. tmpbin .. " 2>/dev/null && chmod +x " .. tmpbin .. " 2>/dev/null")
    try7(tmpbin, "7-Zip (R36S PORT HUB)")
  end
  for _, b in ipairs({ "7zz", "7z", "7za" }) do
    local p = capture("command -v " .. b .. " 2>/dev/null"):gsub("%s+$", "")
    if p ~= "" then try7(p, "7-Zip (" .. b .. ")") end
  end
  if not res.zip then
    local p = capture("command -v unzip 2>/dev/null"):gsub("%s+$", "")
    if p ~= "" then res.zip = { kind = "unzip", bin = p, name = "unzip" }; res.list[#res.list + 1] = "unzip" end
  end
  if not res.rar then
    local p = capture("command -v unrar 2>/dev/null"):gsub("%s+$", "")
    if p ~= "" then res.rar = { kind = "unrar", bin = p, name = "unrar" }; res.list[#res.list + 1] = "unrar" end
  end
  return res
end

-- ---------------------------------------------------------------------------
-- Comandos por ferramenta

--- lista o conteudo: { {path, dir, size, link}, ... } ou nil, erro
function M.list(tool, arch)
  local entries = {}
  if tool.kind == "7z" then
    local out = capture(shq(tool.bin) .. " l -slt -ba -sccUTF-8 -- " .. shq(arch) .. " 2>&1; echo \"__RC=$?\"")
    local rc = tonumber(out:match("__RC=(%d+)%s*$") or "1")
    if rc ~= 0 then return nil, (out:gsub("__RC=%d+%s*$", "")):sub(-300) end
    local cur
    for line in out:gmatch("[^\n]+") do
      local k, v = line:match("^([%w ]-) = (.*)$")
      if k == "Path" then
        cur = { path = v }
        entries[#entries + 1] = cur
      elseif cur and k == "Folder" then cur.dir = v == "+"
      elseif cur and k == "Size" then cur.size = tonumber(v)
      elseif cur and k == "Attributes" then
        if v:find("D", 1, true) and v:match("^D") then cur.dir = true end
        if v:match("[%s_]l[r-][w-][x-]") then cur.link = true end
      elseif cur and k == "Symbolic Link" and v ~= "" then cur.link = true
      end
    end
  elseif tool.kind == "unzip" then
    local out = capture(shq(tool.bin) .. " -Z1 " .. shq(arch) .. " 2>&1; echo \"__RC=$?\"")
    local rc = tonumber(out:match("__RC=(%d+)%s*$") or "1")
    if rc ~= 0 then return nil, (out:gsub("__RC=%d+%s*$", "")):sub(-300) end
    for line in out:gmatch("[^\n]+") do
      if not line:match("^__RC=") then
        entries[#entries + 1] = { path = line:gsub("/$", ""), dir = line:sub(-1) == "/" }
      end
    end
    -- tamanhos e links (zipinfo: permissao no inicio da linha)
    local info = capture(shq(tool.bin) .. " -Zl " .. shq(arch) .. " 2>/dev/null")
    local i = 0
    for line in info:gmatch("[^\n]+") do
      -- "?" no inicio: arquivo gravado sem permissoes Unix (ex.: por Python); tambem conta
      local perm, size = line:match("^([%-dl%?][rwxsStT%-]+)%s+%S+%s+%S+%s+(%d+)")
      if perm then
        i = i + 1
        local e = entries[i]
        if e then e.size = tonumber(size); if perm:sub(1, 1) == "l" then e.link = true end end
      end
    end
  elseif tool.kind == "unrar" then
    local out = capture(shq(tool.bin) .. " lb " .. shq(arch) .. " 2>&1; echo \"__RC=$?\"")
    local rc = tonumber(out:match("__RC=(%d+)%s*$") or "1")
    if rc ~= 0 then return nil, (out:gsub("__RC=%d+%s*$", "")):sub(-300) end
    for line in out:gmatch("[^\n]+") do
      if not line:match("^__RC=") then entries[#entries + 1] = { path = line } end
    end
  end
  for _, e in ipairs(entries) do
    e.path = e.path:gsub("^%./", "")
  end
  return entries
end

--- teste de integridade do arquivo (CRC de cada item). Devolve true ou false, saida
function M.test(tool, arch)
  local cmd
  if tool.kind == "7z" then cmd = shq(tool.bin) .. " t -bd -- " .. shq(arch)
  elseif tool.kind == "unzip" then cmd = shq(tool.bin) .. " -tq " .. shq(arch)
  else cmd = shq(tool.bin) .. " t -idq " .. shq(arch) end
  local out = capture(cmd .. " 2>&1; echo \"__RC=$?\"")
  local rc = tonumber(out:match("__RC=(%d+)%s*$") or "1")
  return rc == 0, (out:gsub("__RC=%d+%s*$", "")):sub(-300)
end

--- extrai tudo em `dest` (pasta vazia). Links simbolicos sao recusados depois.
function M.extract(tool, arch, dest)
  local cmd
  if tool.kind == "7z" then cmd = shq(tool.bin) .. " x -y -bd -o" .. shq(dest) .. " -- " .. shq(arch)
  elseif tool.kind == "unzip" then cmd = shq(tool.bin) .. " -q -o " .. shq(arch) .. " -d " .. shq(dest)
  else cmd = shq(tool.bin) .. " x -o+ -y -idq " .. shq(arch) .. " " .. shq(dest .. "/") end
  local out = capture(cmd .. " 2>&1; echo \"__RC=$?\"")
  local rc = tonumber(out:match("__RC=(%d+)%s*$") or "1")
  -- unzip: 1 = avisos sem erro
  local ok = rc == 0 or (tool.kind == "unzip" and rc == 1)
  return ok, (out:gsub("__RC=%d+%s*$", "")):sub(-300)
end

--- conteudo de um unico item (ex.: o manifesto), limitado a `max` bytes
function M.cat(tool, arch, member, max)
  local cmd
  if tool.kind == "7z" then cmd = shq(tool.bin) .. " e -so -- " .. shq(arch) .. " " .. shq(member)
  elseif tool.kind == "unzip" then cmd = shq(tool.bin) .. " -p " .. shq(arch) .. " " .. shq(member)
  else cmd = shq(tool.bin) .. " p -inul " .. shq(arch) .. " " .. shq(member) end
  local h = io.popen(cmd .. " 2>/dev/null")
  if not h then return nil end
  local s = h:read(max or (4 * 1024 * 1024))
  h:close()
  return s
end

return M
