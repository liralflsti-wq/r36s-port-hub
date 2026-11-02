-- =============================================================================
--  Atualizacao via rede: consulta a fonte oficial configurada
--  Fonte, definida em config.lua (C.UPDATE_URL) ou no arquivo
--  <pasta do app>/update_url.txt (uma linha):
--    0) link direto do pacote .zip (ex.: .../releases/latest/download/X.zip)
--       -> baixa so o comeco do arquivo e le o update_manifest.json de dentro
--          (versao, versao minima, mudancas e correcoes). Se nao der e o link
--          for do GitHub, usa a ultima Release pela API (tag = versao).
--    a) repositorio do GitHub: https://github.com/USUARIO/REPO
--       -> le a ultima Release (tag = versao, primeiro .zip anexado = pacote)
--    b) um arquivo JSON (ex.: "raw" do GitHub) no formato:
--       { "version": "0.2", "url": "https://.../R36S-PORT-HUB.zip",
--         "size": 12345, "sha256": "...", "notes": "O que mudou" }
--  So verifica quando o usuario pede. Nada e instalado sem confirmacao.
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")
local json = require("lib.json")
local Fetcher = require("core.fetcher")

local M = { state = "idle" }   -- idle | checking | none | uptodate | available | error | working | done

function M.source_url()
  local s = U.read_file(C.APP_DIR .. "/update_url.txt")
  if s then
    s = U.trim(s:match("^[^\r\n]*") or "")
    if s:match("^https?://") then return s end
  end
  if C.UPDATE_URL and C.UPDATE_URL:match("^https?://") then return C.UPDATE_URL end
  return nil
end

--- "v0.2.1 BETA" -> {0,2,1}
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

--- endereco da API do GitHub para um link de repositorio (ou nil)
local function github_api(url)
  local owner, repo = url:match("^https?://github%.com/([%w%-%._]+)/([%w%-%._]+)")
  if owner then
    repo = repo:gsub("%.git$", "")
    return "https://api.github.com/repos/" .. owner .. "/" .. repo .. "/releases/latest"
  end
  if url:match("^https?://api%.github%.com/repos/") then return url end
  return nil
end

--- nome do arquivo no fim do link (sem ?query), ex.: "R36S-PORT-HUB-update.zip"
local function url_file(url)
  local path = tostring(url or ""):gsub("[?#].*$", "")
  return path:match("([^/]+)$")
end

--- link direto de um pacote .zip?
local function is_package_url(url)
  local name = url_file(url)
  return name ~= nil and name:lower():match("%.zip$") ~= nil
end
M.is_package_url = is_package_url

-- ---------------------------------------------------------------------------
-- Leitura do update_manifest.json no comeco de um .zip (cabecalhos locais)
local function u16(s, i) local a, b = s:byte(i, i + 1); return a + b * 256 end
local function u32(s, i) local a, b, c, d = s:byte(i, i + 3); return a + b * 256 + c * 65536 + d * 16777216 end

--- procura o update_manifest.json nos primeiros bytes de um zip -> texto ou nil, motivo
function M.manifest_from_zip_head(data)
  data = data or ""
  local i = 1
  while i + 30 <= #data and data:sub(i, i + 3) == "PK\3\4" do
    local flags, method = u16(data, i + 6), u16(data, i + 8)
    local csize = u32(data, i + 18)
    local nlen, elen = u16(data, i + 26), u16(data, i + 28)
    local name = data:sub(i + 30, i + 29 + nlen)
    local start = i + 30 + nlen + elen
    if flags % 16 >= 8 then return nil, "zip sem tamanho no cabecalho" end
    if name == "update_manifest.json" or name:match("/update_manifest%.json$") then
      if start + csize - 1 > #data then return nil, "manifesto maior que o trecho baixado" end
      local raw = data:sub(start, start + csize - 1)
      if method == 0 then return raw end
      if method == 8 then
        local ok, txt = pcall(love.data.decompress, "string", "deflate", raw)
        if ok and txt then return txt end
        return nil, "falha ao descompactar o manifesto"
      end
      return nil, "compressao nao suportada (" .. method .. ")"
    end
    i = start + csize
  end
  return nil, "manifesto nao encontrado no comeco do pacote"
end

--- texto de novidades a partir das listas do manifesto
local function notes_from_manifest(d)
  local out = {}
  local function add(title, list)
    if type(list) ~= "table" or #list == 0 then return end
    out[#out + 1] = title
    for _, t in ipairs(list) do out[#out + 1] = "• " .. tostring(t) end
  end
  add(L("O que mudou:"), d.changes)
  add(L("Correções:"), d.fixes)
  if #out == 0 and d.description then out[1] = tostring(d.description) end
  return table.concat(out, "\n")
end

--- informacoes da versao a partir do manifesto lido de um link direto
local function info_from_manifest(text, url)
  local d = json.decode(text or "")
  if type(d) ~= "table" or not d.version then return nil, L("o manifesto do pacote não tem a versão") end
  return { version = tostring(d.version), label = d.version_label and tostring(d.version_label) or nil,
    url = url, name = url_file(url), notes = notes_from_manifest(d),
    description = d.description and tostring(d.description) or nil,
    changes = type(d.changes) == "table" and d.changes or nil, fixes = type(d.fixes) == "table" and d.fixes or nil,
    min_version = d.min_version and tostring(d.min_version) or nil }
end

--- interpreta a resposta (Release do GitHub ou JSON proprio)
local function parse_info(text, from_github, want_name)
  local d = json.decode(text or "")
  if type(d) ~= "table" then return nil, L("a resposta não é um JSON válido") end
  if from_github then
    local ver = d.tag_name or d.name
    if not ver then return nil, L("o repositório ainda não tem uma Release publicada") end
    local asset
    for _, a in ipairs(d.assets or {}) do
      if type(a) == "table" and want_name and a.name == want_name then asset = a; break end
    end
    if not asset then
      for _, a in ipairs(d.assets or {}) do
        if type(a) == "table" and tostring(a.name or ""):lower():match("%.zip$") then asset = a; break end
      end
    end
    if not asset then return nil, L("a Release ") .. tostring(ver) .. L(" não tem um arquivo .zip anexado") end
    return { version = tostring(ver), url = asset.browser_download_url, size = tonumber(asset.size),
      notes = d.body or "", name = asset.name }
  end
  if not d.version or not d.url then return nil, L("o JSON precisa ter os campos \"version\" e \"url\"") end
  return { version = tostring(d.version), url = tostring(d.url), size = tonumber(d.size),
    sha256 = d.sha256 and tostring(d.sha256):lower() or nil, notes = tostring(d.notes or d.changelog or "") }
end

--- conclui a verificacao com as informacoes obtidas
local function finish(info, err)
  if not info then
    M.state, M.error = "error", err
  elseif not tostring(info.url or ""):match("^https?://") then
    M.state, M.error = "error", L("O link do pacote de atualização é inválido.")
  else
    M.info = info
    M.state = M.compare(info.version, C.VERSION_NUM) > 0 and "available" or "uptodate"
  end
end

--- consulta a ultima Release pela API do GitHub (ou um JSON proprio)
local function check_api(url, api, want_name, on_done)
  local out = love.filesystem.getSaveDirectory() .. "/update_info.json"
  Fetcher.get("catalog", api or url, out, function(ok, path, reason)
    if not ok then
      finish(nil, L("Não foi possível consultar a atualização (") .. tostring(reason) .. L("). Verifique o Wi-Fi."))
    else
      local info, err = parse_info(U.read_file(path), api ~= nil, want_name)
      os.remove(path)
      if info and want_name and is_package_url(url) and info.name ~= want_name then
        -- a Release nao tem o arquivo do link: baixa pelo proprio link
        info.url, info.name, info.size = url, want_name, nil
      end
      finish(info, info and nil or (L("Resposta inválida: ") .. tostring(err)))
    end
    if on_done then on_done() end
  end, true)
end

--- Verifica se existe versao nova. on_done() e chamado ao terminar
function M.check(on_done)
  local url = M.source_url()
  if not url then
    M.state = "none"
    if on_done then on_done() end
    return
  end
  M.state, M.error, M.info = "checking", nil, nil
  local api = github_api(url)
  if not is_package_url(url) then
    check_api(url, api, nil, on_done)
    return
  end
  -- link direto do pacote: le o manifesto no comeco do .zip
  local want = url_file(url)
  local out = love.filesystem.getSaveDirectory() .. "/update_head.bin"
  Fetcher.get_part("catalog", url, out, 262144, function(ok, path, reason)
    local info, err
    if ok then
      local text
      text, err = M.manifest_from_zip_head(U.read_file(path))
      if text then info, err = info_from_manifest(text, url) end
    else
      err = "rc " .. tostring(reason)
    end
    if path then os.remove(path) end
    if info then
      finish(info)
      if on_done then on_done() end
    elseif api then
      U.log("atualizacao: manifesto do pacote nao lido (" .. tostring(err) .. "); usando a Release do GitHub")
      check_api(url, api, want, on_done)
    else
      if ok then finish(nil, L("Resposta inválida: ") .. tostring(err))
      else finish(nil, L("Não foi possível consultar a atualização (") .. tostring(reason) .. L("). Verifique o Wi-Fi.")) end
      if on_done then on_done() end
    end
  end)
end

-- ---------------------------------------------------------------------------
-- O download e a instalacao passam pelo Gerenciador de atualizacoes
-- (core/updater): o pacote baixado vai para a pasta update e e validado,
-- instalado e registrado do mesmo jeito que um pacote local.
local Manager = require("core.updater.manager")

--- nome do arquivo na pasta update para o pacote da versao disponivel
function M.download_name()
  local i = M.info or {}
  local ext = (tostring(i.name or i.url or ""):lower():match("%.(%w+)$")) or "zip"
  if ext ~= "zip" and ext ~= "7z" and ext ~= "rar" then ext = "zip" end
  local v = tostring(i.version or "x"):gsub("[^%w%.]", "")
  return "rede_R36S-PORT-HUB_v" .. v .. "." .. ext
end

function M.busy() return Manager.busy() end
function M.update() end

return M
