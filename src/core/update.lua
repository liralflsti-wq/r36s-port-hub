-- =============================================================================
--  Atualizacao via rede: consulta a fonte oficial configurada
--  Fonte (uma das duas), definida em config.lua (C.UPDATE_URL) ou no arquivo
--  <pasta do app>/update_url.txt (uma linha):
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

--- interpreta a resposta (Release do GitHub ou JSON proprio)
local function parse_info(text, from_github)
  local d = json.decode(text or "")
  if type(d) ~= "table" then return nil, L("a resposta não é um JSON válido") end
  if from_github then
    local ver = d.tag_name or d.name
    if not ver then return nil, L("o repositório ainda não tem uma Release publicada") end
    local asset
    for _, a in ipairs(d.assets or {}) do
      if type(a) == "table" and tostring(a.name or ""):lower():match("%.zip$") then asset = a; break end
    end
    if not asset then return nil, L("a Release ") .. tostring(ver) .. L(" não tem um arquivo .zip anexado") end
    return { version = tostring(ver), url = asset.browser_download_url, size = tonumber(asset.size),
      notes = d.body or "", name = asset.name }
  end
  if not d.version or not d.url then return nil, L("o JSON precisa ter os campos \"version\" e \"url\"") end
  return { version = tostring(d.version), url = tostring(d.url), size = tonumber(d.size),
    sha256 = d.sha256 and tostring(d.sha256):lower() or nil, notes = tostring(d.notes or d.changelog or "") }
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
  local out = love.filesystem.getSaveDirectory() .. "/update_info.json"
  Fetcher.get("catalog", api or url, out, function(ok, path, reason)
    if not ok then
      M.state = "error"
      M.error = L("Não foi possível consultar a atualização (") .. tostring(reason) .. L("). Verifique o Wi-Fi.")
    else
      local info, err = parse_info(U.read_file(path), api ~= nil)
      os.remove(path)
      if not info then
        M.state, M.error = "error", L("Resposta inválida: ") .. err
      elseif not tostring(info.url or ""):match("^https?://") then
        M.state, M.error = "error", L("O link do pacote de atualização é inválido.")
      else
        M.info = info
        M.state = M.compare(info.version, C.VERSION_NUM) > 0 and "available" or "uptodate"
      end
    end
    if on_done then on_done() end
  end, true)
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
