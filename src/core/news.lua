-- =============================================================================
--  Novidades e Atualizacoes: monta a lista a partir dos dados REAIS do catalogo
--  (nada e inventado). Fontes, nesta ordem:
--    1) "news" no topo do catalogo (id do port, tipo, data, texto)
--    2) campos "added" / "updated_at" de cada port
--    3) ports instalados com versao mais nova no catalogo (atualizacao disponivel)
--  Preparado para um catalogo remoto: basta o JSON trazer esses campos.
-- =============================================================================
local L = require("lib.i18n").L
local Catalog = require("core.catalog")

local N = {}

function N.build(status_fn)
  local items, seen = {}, {}
  local function add(p, kind, date, text)
    local key = p.id .. "|" .. kind
    if seen[key] then return end
    seen[key] = true
    items[#items + 1] = { port = p, kind = kind, date = date or "", text = text or "" }
  end
  for _, n in ipairs(Catalog.news or {}) do
    local p = Catalog.by_id[n.id]
    if p then add(p, n.type, n.date, n.text ~= "" and n.text or (n.type == "update" and p.changelog or p.short)) end
  end
  for _, p in ipairs(Catalog.ports) do
    if p.updated_at ~= "" then add(p, "update", p.updated_at, p.changelog ~= "" and p.changelog or p.short) end
    if p.added ~= "" then add(p, "new", p.added, p.short) end
  end
  -- atualizacoes disponiveis para o que esta instalado (reconhecimento existente)
  if status_fn then
    for _, p in ipairs(Catalog.ports) do
      if status_fn(p) == "update" then add(p, "available", "", L("Nova versão v") .. p.version .. L(" disponível para o port instalado.")) end
    end
  end
  table.sort(items, function(a, b)
    if (a.kind == "available") ~= (b.kind == "available") then return a.kind == "available" end
    if a.date ~= b.date then return a.date > b.date end
    return a.port.name:lower() < b.port.name:lower()
  end)
  return items
end

function N.count(status_fn) return #N.build(status_fn) end

return N
