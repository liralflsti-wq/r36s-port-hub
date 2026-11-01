-- =============================================================================
--  Registro dos ports instalados pelo hub (installed.json no diretorio de dados)
--  Tambem detecta ports instalados por fora (PortMaster/KMP/manual) pelo nome
--  do script .sh, do mesmo jeito que o KMP faz.
-- =============================================================================
local L = require("lib.i18n").L
local json = require("lib.json")
local U = require("lib.util")
local C = require("config")
local Scan = require("core.scan")

local M = { data = {}, cache = {} }
local FILE = "installed.json"

function M.load()
  local ok, text = pcall(love.filesystem.read, FILE)
  if ok and text then
    local d = json.decode(text)
    if type(d) == "table" then M.data = d end
  end
  M.cache = {}
end

function M.save()
  pcall(love.filesystem.write, FILE, json.encode(M.data, true))
end

function M.record(p, entries)
  M.data[p.id] = {
    name = p.name,
    version = p.version,
    entries = entries,
    date = os.date("%Y-%m-%d %H:%M"),
  }
  M.save()
  M.cache[p.id] = nil
end

--- Situacao do port no console: "none" | "installed" | "update"
--- Usa o registro do hub e, se nao houver, a varredura de /roms/ports
--- (reconhece ports instalados pelo PortMaster, KMP ou copia manual).
function M.status(p)
  if p.is_local then
    M.cache[p.id] = M.cache[p.id] or { st = "installed", found = p.local_items, by = "console" }
    return "installed"
  end
  local c = M.cache[p.id]
  if c then return c.st end
  local st, found, by = "none", nil, nil
  local rec = M.data[p.id]
  if rec and type(rec.entries) == "table" then
    local f = {}
    for _, e in ipairs(rec.entries) do
      if Scan.exists(e) then f[#f + 1] = e end
    end
    if #f > 0 then
      st, found, by = "installed", f, "hub"
      if p.version ~= "" and rec.version and rec.version ~= "" and rec.version ~= p.version then st = "update" end
    end
  end
  if st == "none" then
    local ver
    found, ver = Scan.find(p)
    if found then
      st, by = "installed", "console"
      -- so marca atualizacao quando a versao instalada e conhecida
      if ver and ver ~= "" and p.version ~= "" and ver ~= p.version then st = "update" end
      M.console_versions = M.console_versions or {}
      M.console_versions[p.id] = ver
    end
  end
  M.cache[p.id] = { st = st, found = found, by = by }
  return st
end

--- Itens encontrados no console para este port (lista de nomes) e a origem
function M.found(p)
  M.status(p)
  local c = M.cache[p.id]
  return c and c.found, c and c.by
end

function M.installed_version(p)
  local rec = M.data[p.id]
  if rec and rec.version and rec.version ~= "" then return rec.version end
  return M.console_versions and M.console_versions[p.id] or nil
end

--- Ports do cartao que NAO correspondem a nenhum port do catalogo
--- (instalados pelo PortMaster, KMP ou manualmente). Viram itens "locais".
function M.local_ports(catalog_ports)
  local used = {}
  for _, p in ipairs(catalog_ports) do
    if M.status(p) ~= "none" then
      local f = M.found(p)
      for _, n in ipairs(f or {}) do used[n] = true end
    end
  end
  local out = {}
  for _, lp in ipairs(Scan.ports) do
    if not used[lp.script] then
      local desc = L("Port encontrado no cartão SD, instalado fora da loja (") .. lp.source .. ").\n\n"
        .. L("Script: ") .. lp.script .. (lp.dir and (L("\nPasta: ") .. lp.dir) or "")
        .. L("\n\nEle não está no catálogo da loja, por isso não pode ser baixado ou atualizado por aqui.")
      out[#out + 1] = {
        id = "local:" .. lp.script,
        slug = U.slug("local_" .. lp.script),
        is_local = true,
        name = lp.title,
        short = L("Instalado no console • ") .. lp.source,
        description = desc,
        category = L("No console"),
        category_id = "_local",
        version = lp.version or "",
        size_label = "—",
        download_url = "",
        cover = lp.cover or "",
        author = "", notes = "",
        install_check = {}, local_items = lp.items,
      }
    end
  end
  return out
end

function M.invalidate() M.cache = {} end

--- Reexamina a pasta de ports (depois de instalar, ao voltar para a loja etc.)
function M.rescan(force)
  local before = Scan.time
  Scan.refresh(force)
  if Scan.time ~= before then M.cache = {} end
end

return M
