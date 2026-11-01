-- =============================================================================
--  Preferencias do usuario em settings.txt (pasta de dados do app), formato
--  chave=valor, uma por linha. Mesmo arquivo ja usado pela musica.
--  Chaves: music (1/0), language (pt-BR|en|ru), disclaimer_ok (1)
-- =============================================================================
local P = { data = nil }
local FILE = "settings.txt"

function P.load()
  P.data = {}
  local ok, s = pcall(love.filesystem.read, FILE)
  if ok and type(s) == "string" then
    for line in s:gmatch("[^\r\n]+") do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then P.data[k] = v end
    end
  end
  return P.data
end

function P.get(k)
  if not P.data then P.load() end
  return P.data[k]
end

function P.set(k, v)
  if not P.data then P.load() end
  P.data[k] = v ~= nil and tostring(v) or nil
  local keys = {}
  for key in pairs(P.data) do keys[#keys + 1] = key end
  table.sort(keys)
  local out = {}
  for _, key in ipairs(keys) do out[#out + 1] = key .. "=" .. P.data[key] end
  -- grava em arquivo temporario e troca (nao perde as outras chaves se faltar energia)
  local okw = pcall(love.filesystem.write, FILE .. ".tmp", table.concat(out, "\n") .. "\n")
  if okw then
    local dir = love.filesystem.getSaveDirectory()
    if not os.rename(dir .. "/" .. FILE .. ".tmp", dir .. "/" .. FILE) then
      pcall(love.filesystem.write, FILE, table.concat(out, "\n") .. "\n")
    end
  end
end

return P
