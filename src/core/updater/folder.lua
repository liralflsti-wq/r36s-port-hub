-- =============================================================================
--  Atualizacoes do hub: pasta "update" (r36sporthub/update)
--  Lista os pacotes .zip/.7z/.rar colocados ali (pelo FTP ou pelo gerenciador
--  de arquivos). Nada e instalado so por estar na pasta.
-- =============================================================================
local L = require("lib.i18n").L
local C = require("config")
local U = require("lib.util")
local Formats = require("core.updater.formats")

local M = {}
M.DIR = C.APP_DIR .. "/update"

local README = [[
R36S PORT HUB - pasta de atualizações / updates folder

PT: Coloque aqui o pacote de atualização (.zip, .7z ou .rar) e abra
    Configurações > Downloads e atualizações > Atualizações >
    Atualização local.
    Nada é instalado sem a sua confirmação.
EN: Put the update package (.zip, .7z or .rar) here and open
    Settings > Downloads and updates > Updates > Local update.
    Nothing is installed without your confirmation.
]]

function M.ensure_dir()
  os.execute("mkdir -p " .. U.shq(M.DIR) .. " 2>/dev/null")
  if U.is_dir(M.DIR) and not U.exists(M.DIR .. "/LEIA-ME.txt") then
    U.write_file(M.DIR .. "/LEIA-ME.txt", README)
  end
  return U.is_dir(M.DIR)
end

--- pacotes na pasta (mais recentes primeiro): { name, path, size, mtime, format, by }
function M.scan()
  local out = U.capture("cd " .. U.shq(M.DIR) .. " 2>/dev/null && for f in *; do [ -f \"$f\" ] && stat -c '%s|%Y|%n' -- \"$f\"; done 2>/dev/null") or ""
  local t = {}
  for line in out:gmatch("[^\n]+") do
    local size, mtime, name = line:match("^(%d+)|(%d+)|(.+)$")
    if name and not name:match("%.part$") and name ~= "LEIA-ME.txt" then
      local path = M.DIR .. "/" .. name
      local ext = (name:match("%.([%w]+)$") or ""):lower()
      local fmt = Formats.detect_magic(path)
      if fmt or Formats.EXT[ext] then
        t[#t + 1] = { name = name, path = path, size = tonumber(size), mtime = tonumber(mtime),
          format = fmt or Formats.EXT[ext], magic_ok = fmt ~= nil and (Formats.EXT[ext] == nil or Formats.EXT[ext] == fmt) }
      end
    end
  end
  table.sort(t, function(a, b) return a.mtime > b.mtime end)
  return t
end

--- O pacote instalado ainda esta na pasta update? (so arquivo comum, direto na
--- pasta, sem link). Devolve o caminho real ou nil.
function M.package_left(path)
  if type(path) ~= "string" or path == "" then return nil end
  local dir, name = path:match("^(.*)/([^/]+)$")
  if not dir or not name or name == "LEIA-ME.txt" or name:find("^%.") then return nil end
  local rd = U.trim(U.capture("readlink -f -- " .. U.shq(M.DIR) .. " 2>/dev/null") or "")
  local rp = U.trim(U.capture("readlink -f -- " .. U.shq(dir) .. " 2>/dev/null") or "")
  if rd == "" or rp ~= rd then return nil end
  if U.exec_ok("test -L " .. U.shq(path)) or not U.exec_ok("test -f " .. U.shq(path)) then return nil end
  return path
end

--- Apaga SO o arquivo do pacote instalado (nunca a pasta). Devolve ok, motivo
function M.remove_package(path)
  local p = M.package_left(path)
  if not p then return false, "missing" end
  local ok, err = os.remove(p)
  if not ok then
    U.log("Atualizações: não foi possível apagar o pacote", p, tostring(err))
    return false, tostring(err)
  end
  U.log("Atualizações: pacote apagado depois da instalação:", p)
  return true
end

function M.format_label(fmt) return Formats.LABEL[fmt] or L("desconhecido") end

return M
