-- =============================================================================
--  Atualizacoes do hub: regras de validacao (Lua puro: thread principal e threads)
--  - Quais caminhos um pacote pode trocar (so arquivos do R36S PORT HUB)
--  - Leitura e conferencia do update_manifest.json
--  - Comparacao de versoes e compatibilidade
-- =============================================================================
local json = require("lib.json")

local M = {}

M.MANIFEST = "update_manifest.json"
M.LAUNCHER = "R36S PORT HUB.sh"
M.APP = "r36sporthub"
--- itens do hub que guardam dados do usuario: nunca vem de um pacote
M.PROTECTED = { conf = true, tmp = true, logs = true, gravacoes = true, update = true, backups = true,
  bios = true, ["bios_url.txt"] = true,
  ["catalog.json"] = true, ["catalog_url.txt"] = true, ["update_url.txt"] = true, ["log.txt"] = true }
--- arquivos na raiz do pacote que sao lidos mas nunca instalados
M.IGNORED_ROOT = { [M.MANIFEST] = true, ["LEIA-ME.txt"] = true, ["README.txt"] = true, ["LEIAME.txt"] = true }
M.MAX_FILES = 5000
M.MAX_TOTAL = 512 * 1024 * 1024

--- confere um caminho relativo do pacote. Devolve true ou false, motivo
function M.check_path(p)
  if type(p) ~= "string" or p == "" then return false, "vazio" end
  if #p > 400 then return false, "longo" end
  if p:find("[%z\1-\31\127]") or p:find("\\", 1, true) then return false, "caracteres" end
  if p:sub(1, 1) == "/" or p:match("^%a:") then return false, "absoluto" end
  for part in (p .. "/"):gmatch("([^/]*)/") do
    if part == "" or part == "." or part == ".." then return false, "componente" end
  end
  if p == M.LAUNCHER then return true end
  local rel = p:match("^" .. M.APP .. "/(.+)$")
  if not rel then return false, "fora" end
  local top = rel:match("^([^/]+)")
  if M.PROTECTED[top] then return false, "protegido" end
  if top:match("^libs%.") then return false, "protegido" end
  return true
end

--- "v0.3.1 BETA" -> {0,3,1}
local function parse_version(s)
  local t = {}
  for n in tostring(s or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end

--- 1 se a > b, -1 se a < b, 0 se iguais
function M.compare(a, b)
  local x, y = parse_version(a), parse_version(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p > q and 1 or -1 end
  end
  return 0
end

function M.valid_version(v) return type(v) == "string" and v:match("^%d+[%.%d]*$") ~= nil end

--- le e confere o manifesto. Devolve a tabela ou nil, motivo (codigo curto)
function M.parse_manifest(text)
  local d = json.decode(text or "")
  if type(d) ~= "table" then return nil, "manifest_json" end
  if d.format ~= nil and tonumber(d.format) ~= 1 then return nil, "manifest_format" end
  d.version = d.version ~= nil and tostring(d.version) or nil
  if not M.valid_version(d.version) then return nil, "manifest_version" end
  if d.min_version ~= nil and not M.valid_version(tostring(d.min_version)) then return nil, "manifest_version" end
  if d.max_version ~= nil and not M.valid_version(tostring(d.max_version)) then return nil, "manifest_version" end
  if type(d.files) ~= "table" or #d.files == 0 then return nil, "manifest_files" end
  if #d.files > M.MAX_FILES then return nil, "too_many" end
  local seen = {}
  for _, f in ipairs(d.files) do
    if type(f) ~= "table" or type(f.path) ~= "string" then return nil, "manifest_files" end
    local ok = M.check_path(f.path)
    if not ok then return nil, "manifest_path:" .. f.path end
    if seen[f.path] then return nil, "manifest_dup:" .. f.path end
    seen[f.path] = true
    if type(f.sha256) ~= "string" or not f.sha256:lower():match("^" .. ("%x"):rep(64) .. "$") then
      return nil, "manifest_hash:" .. f.path
    end
    f.sha256 = f.sha256:lower()
    f.size = tonumber(f.size)
  end
  d.by_path = seen
  -- notas da versao (opcionais): o que mudou e o que foi corrigido
  for _, k in ipairs({ "changes", "fixes" }) do
    local list = d[k]
    if list ~= nil then
      if type(list) ~= "table" then return nil, "manifest_notes" end
      local clean = {}
      for i, v in ipairs(list) do
        if i > 60 then break end
        if type(v) ~= "string" then return nil, "manifest_notes" end
        v = v:gsub("[%z\1-\31\127]", " "):sub(1, 400)
        if v:find("%S") then clean[#clean + 1] = v end
      end
      d[k] = clean
    end
  end
  if d.description ~= nil then d.description = tostring(d.description):sub(1, 2000) end
  return d
end

--- a versao instalada aceita este pacote? Devolve true ou false, codigo
function M.compat(m, current)
  if m.min_version and M.compare(current, m.min_version) < 0 then return false, "too_old" end
  if m.max_version and M.compare(current, m.max_version) > 0 then return false, "too_new" end
  return true
end

return M
