-- =============================================================================
--  Capas: download sob demanda, cache em disco e poucas imagens na memoria
-- =============================================================================
local C = require("config")
local U = require("lib.util")
local Fetcher = require("core.fetcher")

local Covers = { mem = {}, order = {}, state = {}, dir = "covers" }

function Covers.init()
  love.filesystem.createDirectory(Covers.dir)
  Covers.abs_dir = love.filesystem.getSaveDirectory() .. "/" .. Covers.dir
end

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end

local function file_name(p) return p.slug .. "_" .. hash(p.cover) .. ".img" end
local function file_for(p) return Covers.dir .. "/" .. file_name(p) end

local function touch(key)
  for i, k in ipairs(Covers.order) do
    if k == key then table.remove(Covers.order, i); break end
  end
  table.insert(Covers.order, key)
  while #Covers.order > C.COVER_CACHE_MAX do
    local old = table.remove(Covers.order, 1)
    local img = Covers.mem[old]
    if img and img.release then img:release() end
    Covers.mem[old] = nil
    if Covers.state[old] == "ready" then Covers.state[old] = "disk" end
  end
end

local function load_image(key, path_in_save, abs)
  local ok, img = pcall(function()
    if abs then
      local data = U.read_file(abs)
      if not data then error("sem arquivo") end
      local fd = love.filesystem.newFileData(data, "cover")
      return love.graphics.newImage(love.image.newImageData(fd))
    end
    return love.graphics.newImage(path_in_save)
  end)
  if ok and img then
    img:setFilter("linear", "linear")
    Covers.mem[key] = img
    Covers.state[key] = "ready"
    touch(key)
    return img
  end
  U.log("capa invalida:", key, tostring(img))
  Covers.state[key] = "failed"
  return nil
end

--- Devolve a imagem (ou nil enquanto carrega/sem capa). Nunca bloqueia na rede.
function Covers.get(p)
  if not p or p.cover == "" then return nil end
  local key = p.slug
  local img = Covers.mem[key]
  if img then touch(key); return img end
  local st = Covers.state[key]
  if st == "failed" or st == "loading" then return nil end

  -- capa local (caminho relativo a pasta do app)
  if not p.cover:match("^https?://") then
    local abs = p.cover:sub(1, 1) == "/" and p.cover or (C.APP_DIR .. "/" .. p.cover)
    if p.cover:sub(1, 1) ~= "/" and love.filesystem.getInfo(p.cover) then return load_image(key, p.cover) end
    if U.read_file(abs) then return load_image(key, nil, abs) end
    Covers.state[key] = "failed"
    return nil
  end

  local f = file_for(p)
  if love.filesystem.getInfo(f) then return load_image(key, f) end

  Covers.state[key] = "loading"
  Fetcher.get("cover", p.cover, Covers.abs_dir .. "/" .. file_name(p), function(ok, _, reason)
    if ok then
      Covers.state[key] = "disk"
    elseif reason == "cancelado" then
      Covers.state[key] = nil
    else
      Covers.state[key] = "failed"
    end
  end)
  return nil
end

function Covers.is_loading(p)
  return p and Covers.state[p.slug] == "loading"
end

--- Ao trocar de catalogo/tela: libera pedidos pendentes
function Covers.reset_pending()
  Fetcher.drop_covers()
  for k, v in pairs(Covers.state) do
    if v == "loading" then Covers.state[k] = nil end
  end
end

--- Apaga as capas baixadas (serao baixadas de novo quando aparecerem)
function Covers.clear_disk()
  for _, f in ipairs(love.filesystem.getDirectoryItems(Covers.dir)) do
    love.filesystem.remove(Covers.dir .. "/" .. f)
  end
  for k, img in pairs(Covers.mem) do if img.release then img:release() end end
  Covers.mem, Covers.order, Covers.state = {}, {}, {}
end

--- Tentar de novo capas que falharam (ex.: depois de reconectar)
function Covers.retry_failed()
  for k, v in pairs(Covers.state) do
    if v == "failed" then Covers.state[k] = nil end
  end
end

return Covers
