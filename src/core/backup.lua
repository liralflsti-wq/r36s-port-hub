-- =============================================================================
--  Backup e restauracao das configuracoes do HUB (somente arquivos do app).
--  Copia os grupos escolhidos para a pasta "backup/" dos dados do app,
--  com um backup.json (data, versao, grupos). Os ports instalados, a pasta
--  de ports e os registros de instalacao NUNCA entram no backup.
-- =============================================================================
local L = require("lib.i18n").L
local json = require("lib.json")
local C = require("config")
local Prefs = require("core.prefs")

local B = {}

local DIR = "backup"
local META = DIR .. "/backup.json"

B.GROUPS = {
  { id = "prefs", label = L("Preferências"), desc = L("Idioma, tema, brilho, som, notificações e aviso aceito."),
    files = { "settings.txt", "theme.txt", "brightness.txt" } },
  { id = "favorites", label = L("Favoritos"), desc = L("Ports marcados com estrela."), files = { "favorites.json" } },
  { id = "ftp", label = L("Servidor FTP"), desc = L("Porta, usuário e senha do FTP."), files = { "ftp.json" } },
  { id = "history", label = L("Históricos"), desc = L("Histórico de downloads e do FTP."),
    files = { "downloads.json", "ftp_history.json" } },
  { id = "catalog", label = L("Catálogo local"), desc = L("Último catálogo baixado e o registro dos ports instalados pelo hub."),
    files = { "catalog_cache.json", "installed.json" } },
}
B.BY_ID = {}
for _, g in ipairs(B.GROUPS) do B.BY_ID[g.id] = g end

--- grupos marcados para o proximo backup (salvo em settings.txt)
function B.selected()
  local s = Prefs.get("backup_groups")
  local sel = {}
  if not s then
    for _, g in ipairs(B.GROUPS) do sel[g.id] = true end
    return sel
  end
  for id in s:gmatch("[%w_]+") do if B.BY_ID[id] then sel[id] = true end end
  return sel
end

function B.set_selected(sel)
  local ids = {}
  for _, g in ipairs(B.GROUPS) do if sel[g.id] then ids[#ids + 1] = g.id end end
  Prefs.set("backup_groups", #ids > 0 and table.concat(ids, ",") or "none")
end

--- dados do ultimo backup ou nil
function B.info()
  local ok, s = pcall(love.filesystem.read, META)
  local d = ok and s and json.decode(s) or nil
  if type(d) ~= "table" or type(d.groups) ~= "table" or type(d.time) ~= "number" then return nil end
  return d
end

local function chmod_private(name)
  local p = love.filesystem.getSaveDirectory() .. "/" .. name
  os.execute("chmod 600 '" .. p:gsub("'", "'\\''") .. "' 2>/dev/null")
end

--- cria o backup dos grupos marcados. Devolve true, n_arquivos ou false, motivo
function B.create(sel)
  local groups, n = {}, 0
  if not love.filesystem.getInfo(DIR) and not love.filesystem.createDirectory(DIR) then
    return false, L("Não foi possível criar a pasta do backup.")
  end
  -- limpa o backup anterior (so arquivos conhecidos)
  for _, g in ipairs(B.GROUPS) do
    for _, f in ipairs(g.files) do love.filesystem.remove(DIR .. "/" .. f) end
  end
  for _, g in ipairs(B.GROUPS) do
    if sel[g.id] then
      local files = {}
      for _, f in ipairs(g.files) do
        local data = love.filesystem.getInfo(f) and love.filesystem.read(f)
        if data then
          if not love.filesystem.write(DIR .. "/" .. f, data) then
            return false, L("Falha ao gravar o backup (cartão cheio ou somente leitura?).")
          end
          if f == "ftp.json" then chmod_private(DIR .. "/" .. f) end
          files[#files + 1] = f
          n = n + 1
        end
      end
      groups[#groups + 1] = { id = g.id, files = files }
    end
  end
  if #groups == 0 then return false, L("Escolha pelo menos um item para o backup.") end
  local meta = { time = os.time(), version = C.VERSION, groups = groups }
  if not love.filesystem.write(META, json.encode(meta)) then
    return false, L("Falha ao gravar o backup (cartão cheio ou somente leitura?).")
  end
  return true, n
end

--- restaura os arquivos do backup. Devolve true, {grupos restaurados} ou false, motivo
function B.restore()
  local d = B.info()
  if not d then return false, L("Nenhum backup encontrado.") end
  local done = {}
  for _, g in ipairs(d.groups) do
    if B.BY_ID[g.id] and type(g.files) == "table" then
      for _, f in ipairs(g.files) do
        -- so nomes conhecidos do grupo (nada fora da pasta de dados do app)
        local known = false
        for _, kf in ipairs(B.BY_ID[g.id].files) do if kf == f then known = true end end
        local data = known and love.filesystem.read(DIR .. "/" .. f)
        if data then
          if not love.filesystem.write(f, data) then
            return false, L("Falha ao restaurar ") .. f .. "."
          end
          if f == "ftp.json" then chmod_private(f) end
        end
      end
      done[g.id] = true
    end
  end
  return true, done
end

-- ---------------------------------------------------------------------------
-- Exportar / importar (pasta visivel no cartao: da para copiar pelo FTP)
-- A senha do FTP nunca e exportada (o cartao nao protege arquivos).
B.EXPORT_DIR = C.APP_DIR .. "/configuracoes"
local NO_EXPORT = { ftp = true }

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function read_abs(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function write_abs(path, data)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then return false end
  local ok = f:write(data)
  f:close()
  if not ok or not os.rename(tmp, path) then os.remove(tmp); return false end
  return true
end

--- grava os itens marcados numa pasta nova em configuracoes/. Devolve true, nome ou false, motivo
function B.export(sel)
  local stamp = os.date("%Y-%m-%d_%H-%M-%S")
  local dir = B.EXPORT_DIR .. "/" .. stamp
  os.execute("mkdir -p " .. shq(dir) .. " 2>/dev/null")
  local test = io.open(dir .. "/.teste", "wb")
  if not test then return false, L("Não foi possível criar a pasta ") .. dir .. "." end
  test:close(); os.remove(dir .. "/.teste")
  local groups, n = {}, 0
  for _, g in ipairs(B.GROUPS) do
    if sel[g.id] and not NO_EXPORT[g.id] then
      local files = {}
      for _, f in ipairs(g.files) do
        local data = love.filesystem.getInfo(f) and love.filesystem.read(f)
        if data then
          if not write_abs(dir .. "/" .. f, data) then
            return false, L("Falha ao gravar a exportação (cartão cheio ou somente leitura?).")
          end
          files[#files + 1] = f
          n = n + 1
        end
      end
      groups[#groups + 1] = { id = g.id, files = files }
    end
  end
  if #groups == 0 then
    os.execute("rmdir " .. shq(dir) .. " 2>/dev/null")
    return false, L("Escolha pelo menos um item (a senha do FTP não é exportada).")
  end
  if not write_abs(dir .. "/backup.json", json.encode({ time = os.time(), version = C.VERSION, groups = groups })) then
    return false, L("Falha ao gravar a exportação (cartão cheio ou somente leitura?).")
  end
  return true, stamp, n
end

--- exportacoes encontradas (mais recentes primeiro): { name=, time=, version=, groups= }
function B.exports()
  local out = {}
  local p = io.popen("ls -1 " .. shq(B.EXPORT_DIR) .. " 2>/dev/null")
  if p then
    for name in p:lines() do
      if name:match("^[%w%-_]+$") then
        local d = json.decode(read_abs(B.EXPORT_DIR .. "/" .. name .. "/backup.json") or "")
        if type(d) == "table" and type(d.groups) == "table" and type(d.time) == "number" then
          d.name = name
          out[#out + 1] = d
        end
      end
    end
    p:close()
  end
  table.sort(out, function(a, b) return a.time > b.time end)
  return out
end

--- restaura uma exportacao (so nomes de arquivo conhecidos). Devolve true, {grupos} ou false, motivo
function B.import(name)
  if not tostring(name):match("^[%w%-_]+$") then return false, L("Exportação inválida.") end
  local dir = B.EXPORT_DIR .. "/" .. name
  local d = json.decode(read_abs(dir .. "/backup.json") or "")
  if type(d) ~= "table" or type(d.groups) ~= "table" then return false, L("Exportação inválida.") end
  local done = {}
  for _, g in ipairs(d.groups) do
    local def = B.BY_ID[g.id]
    if def and not NO_EXPORT[g.id] and type(g.files) == "table" then
      for _, f in ipairs(g.files) do
        local known = false
        for _, kf in ipairs(def.files) do if kf == f then known = true end end
        local data = known and read_abs(dir .. "/" .. f)
        if data then
          if not love.filesystem.write(f, data) then return false, L("Falha ao restaurar ") .. f .. "." end
        end
      end
      done[g.id] = true
    end
  end
  return true, done
end

return B
