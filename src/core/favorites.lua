-- =============================================================================
--  Favoritos (salvos em favorites.json no diretorio de dados do app)
--  Nao interfere em instalacao/exclusao: guarda apenas os ids marcados.
-- =============================================================================
local json = require("lib.json")

local F = { ids = {}, loaded = false }
local FILE = "favorites.json"

function F.load()
  F.loaded = true
  local ok, text = pcall(love.filesystem.read, FILE)
  if ok and text then
    local d = json.decode(text)
    if type(d) == "table" then
      F.ids = {}
      for _, id in ipairs(d) do if type(id) == "string" then F.ids[id] = true end end
    end
  end
end

local function save()
  local list = {}
  for id in pairs(F.ids) do list[#list + 1] = id end
  table.sort(list)
  pcall(love.filesystem.write, FILE, json.encode(list))
end

function F.is(p) if not F.loaded then F.load() end return p and F.ids[p.id] == true end

--- marca/desmarca. Devolve o novo estado
function F.toggle(p)
  if not F.loaded then F.load() end
  if F.ids[p.id] then F.ids[p.id] = nil else F.ids[p.id] = true end
  save()
  return F.ids[p.id] == true
end

function F.count()
  if not F.loaded then F.load() end
  local n = 0
  for _ in pairs(F.ids) do n = n + 1 end
  return n
end

return F
