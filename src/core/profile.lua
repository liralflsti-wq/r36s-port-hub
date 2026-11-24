-- =============================================================================
--  Perfil do usuario: foto (avatar) e data de aniversario
--    P.avatars()          lista de avatares: os do hub (assets/avatars) e os do
--                         usuario (pasta "avatares" dentro de r36sporthub/conf)
--    P.avatar() / P.set_avatar(path)
--    P.avatar_image()     imagem do avatar escolhido (ou nil)
--    P.birthday()         dia, mes (ou nil) | P.set_birthday(d, m)
--    P.is_birthday()      hoje e o aniversario?
--  Salvo nas preferencias: "avatar" (caminho) e "birthday" ("DD/MM").
-- =============================================================================
local Prefs = require("core.prefs")
local L = require("lib.i18n").L
local P = {}
local DIRS = { "assets/avatars", "avatares", "avatares_online" }
local cache = {}

-- Avatares online (DiceBear, https://www.dicebear.com): a tela mostra as
-- miniaturas pela internet e so baixa (copia para "avatares_online") o que o
-- usuario aplicar. Estilos sem exigencia de credito: Pixel Art, Pixel Art
-- Neutral e Lorelei (CC0 1.0); Bottts (livre para uso pessoal e comercial).
local API = os.getenv("PORTHUB_AVATAR_API") or "https://api.dicebear.com/9.x/%s/png?seed=%s&size=128&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf"
local SEEDS = { "Lira", "Nexo", "Arcade", "Pixel", "Turbo", "Combo", "Retro", "Bit", "Joy", "Boss", "Rush", "Neon",
  "Nova", "Blaze", "Kira", "Zeta", "Luna", "Max", "Rex", "Tiki", "Bolt", "Mika", "Duke", "Sora", "Echo", "Vega",
  "Flash", "Ruby", "Jade", "Onyx", "Coral", "Ember" }
P.ONLINE = {
  { id = "pixel-art", name = L("Pixel") },
  { id = "bottts", name = L("Robôs") },
  { id = "lorelei", name = L("Personagens") },
  { id = "pixel-art-neutral", name = L("Carinhas") },
}
P.ONLINE_DIR = "avatares_online"

--- lista de avatares online de um estilo: { key, url, file }
function P.online_list(style)
  local out = {}
  for _, s in ipairs(SEEDS) do
    out[#out + 1] = { slug = "av_" .. style .. "_" .. s, cover = string.format(API, style, s),
      file = P.ONLINE_DIR .. "/" .. style .. "_" .. s:lower() .. ".png" }
  end
  return out
end

--- baixa (ou pega do cache) o avatar online e passa a usa-lo. cb(ok)
function P.apply_online(item, cb)
  if love.filesystem.getInfo(item.file) then P.set_avatar(item.file); cb(true); return end
  require("core.covers").fetch_file(item, function(path)
    local data = path and require("lib.util").read_file(path)
    if not data then cb(false); return end
    love.filesystem.createDirectory(P.ONLINE_DIR)
    if not love.filesystem.write(item.file, data) then cb(false); return end
    cache[item.file] = nil
    P.set_avatar(item.file)
    cb(true)
  end)
end
local EXT = { png = true, jpg = true, jpeg = true }

function P.avatars()
  local out = {}
  for _, dir in ipairs(DIRS) do
    local ok, items = pcall(love.filesystem.getDirectoryItems, dir)
    if ok and items then
      table.sort(items)
      for _, f in ipairs(items) do
        local ext = (f:match("%.(%w+)$") or ""):lower()
        if EXT[ext] then out[#out + 1] = dir .. "/" .. f end
      end
    end
  end
  return out
end

function P.avatar()
  local v = Prefs.get("avatar")
  if v and v ~= "" and love.filesystem.getInfo(v) then return v end
  return nil
end

function P.set_avatar(path)
  Prefs.set("avatar", path or "")
end

function P.image(path)
  if not path then return nil end
  if cache[path] == nil then
    local ok, img = pcall(love.graphics.newImage, path, { mipmaps = true })
    if ok and img then pcall(function() img:setFilter("linear", "linear") end) end
    cache[path] = ok and img or false
  end
  return cache[path] or nil
end

function P.avatar_image() return P.image(P.avatar()) end

--- desenha o avatar num quadrado arredondado (com moldura); sem avatar, um icone
function P.draw(x, y, size, border)
  local G, T = require("ui.gfx"), require("ui.theme")
  local img = P.avatar_image()
  G.rect(x, y, size, size, T.c.bg0, 8)
  if img then
    local k = size / math.max(img:getWidth(), img:getHeight())
    G.clip(x, y, size, size)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x + (size - img:getWidth() * k) / 2, y + (size - img:getHeight() * k) / 2, 0, k, k)
    G.unclip()
  else
    require("ui.icons").draw("set_profile", x + size / 2 - 12, y + size / 2 - 12, T.c.faint, 1)
  end
  G.frame(x, y, size, size, border or T.c.line, 8, 2)
end

-- ---------------------------------------------------------------- aniversario
function P.birthday()
  local d, m = tostring(Prefs.get("birthday") or ""):match("^(%d+)/(%d+)$")
  d, m = tonumber(d), tonumber(m)
  if d and m and d >= 1 and d <= 31 and m >= 1 and m <= 12 then return d, m end
  return nil
end

function P.set_birthday(d, m)
  if d and m then Prefs.set("birthday", string.format("%02d/%02d", d, m)) else Prefs.set("birthday", "") end
end

function P.birthday_label()
  local d, m = P.birthday()
  return d and string.format("%02d/%02d", d, m) or nil
end

function P.is_birthday()
  local d, m = P.birthday()
  if not d then return false end
  return tonumber(os.date("%d")) == d and tonumber(os.date("%m")) == m
end

return P
