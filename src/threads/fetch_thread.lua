-- =============================================================================
--  R36S PORT HUB - thread de downloads pequenos (catalogo e capas)
--  Recebe pedidos pelo canal "hub_fetch_req" e responde em "hub_fetch_res".
--  Pedido: { id=, url=, out=, kind="catalog"|"cover", part=BYTES (opcional) }
-- =============================================================================
require("love.timer")

local fetch_sh = ...
local REQ = love.thread.getChannel("hub_fetch_req")
local RES = love.thread.getChannel("hub_fetch_res")

local function shq(s) return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'" end

local function fsize(p)
  local f = io.open(p, "rb")
  if not f then return 0 end
  local s = f:seek("end")
  f:close()
  return s or 0
end

local function read_head(p, n)
  local f = io.open(p, "rb")
  if not f then return "" end
  local s = f:read(n) or ""
  f:close()
  return s
end

while true do
  local req = REQ:demand()
  if type(req) == "table" and req.t == "quit" then break end
  if type(req) == "table" and req.url and req.out then
    local tmp = req.out .. ".tmp"
    local rcf = req.out .. ".rc"
    local pidf = req.out .. ".pid"
    os.remove(tmp); os.remove(rcf)
    local maxt = req.kind == "catalog" and 25 or 30
    local rc
    if req.part then
      -- so o comeco do arquivo (manifesto de um pacote .zip)
      local ok = os.execute("sh " .. shq(fetch_sh) .. " part " .. shq(req.url) .. " " .. shq(tmp) .. " "
        .. math.floor(tonumber(req.part) or 262144) .. " >/dev/null 2>&1")
      rc = (ok == 0 or ok == true) and 0 or 1
    else
      os.execute("sh " .. shq(fetch_sh) .. " get " .. shq(req.url) .. " " .. shq(tmp) .. " "
        .. shq(pidf) .. " " .. shq(rcf) .. " " .. maxt .. " >/dev/null 2>&1")
      local rcs = read_head(rcf, 16)
      rc = tonumber(rcs:match("%d+") or "1")
    end
    os.remove(rcf); os.remove(pidf)
    local size = fsize(tmp)
    local okres = (rc == 0 and size > 0)
    local reason = okres and "" or ("rc=" .. tostring(rc))
    if okres and (req.kind == "cover" or req.kind == "cover_all") then
      local h = read_head(tmp, 12)
      local is_png = h:sub(1, 8) == "\137PNG\r\n\26\n"
      local is_jpg = h:sub(1, 3) == "\255\216\255"
      if not (is_png or is_jpg) then okres = false; reason = "nao e imagem" end
    end
    if okres then
      os.remove(req.out)
      if not os.rename(tmp, req.out) then okres = false; reason = "falha ao salvar" end
    else
      os.remove(tmp)
    end
    RES:push({ id = req.id, kind = req.kind, ok = okres, out = req.out, reason = reason })
  end
end
