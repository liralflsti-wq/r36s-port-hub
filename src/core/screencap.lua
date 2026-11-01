-- =============================================================================
--  Captura da interface do R36S PORT HUB (somente a tela do hub)
--
--  O hub desenha tudo numa imagem interna de 640x480 (canvas). Enquanto a
--  transmissao ou a gravacao estiverem ligadas, uma copia desse canvas e lida
--  no ritmo pedido (quadros por segundo) e entregue as threads delas.
--  Jogos, EmulationStation e o resto do sistema nunca passam por aqui.
--  Se a thread estiver atrasada, o quadro e descartado (nunca acumula).
-- =============================================================================
local T = require("ui.theme")

local Cap = {
  users = {},        -- nome -> { fps = n, channel = Channel, max = n }
  last = -1,
  canvas = nil,
}

--- passa a entregar quadros para `name` (fps = quadros por segundo)
function Cap.want(name, fps, channel, max)
  Cap.users[name] = { fps = fps, channel = channel, max = max or 1 }
end

function Cap.set_fps(name, fps)
  if Cap.users[name] then Cap.users[name].fps = fps end
end

function Cap.release(name)
  local u = Cap.users[name]
  Cap.users[name] = nil
  if u and u.channel then
    -- quadros que ninguem vai ler
    local img = u.channel:pop()
    while img do pcall(img.release, img); img = u.channel:pop() end
  end
end

function Cap.active() return next(Cap.users) ~= nil end

--- canvas proprio (no console a tela ja tem 640x480 e o hub desenha direto nela)
function Cap.get_canvas()
  if not Cap.canvas then
    Cap.canvas = love.graphics.newCanvas(T.W, T.H)
    Cap.canvas:setFilter("nearest", "nearest")
  end
  return Cap.canvas
end

--- chamado logo depois do desenho do quadro no canvas (antes de ir para a tela)
function Cap.after_draw(canvas)
  if not Cap.active() then return end
  local now = love.timer.getTime()
  local fps = 0
  for _, u in pairs(Cap.users) do if u.fps > fps then fps = u.fps end end
  if fps <= 0 or now - Cap.last < 1 / fps - 0.004 then return end
  -- alguem precisa do quadro agora?
  local need = false
  for _, u in pairs(Cap.users) do
    if u.channel:getCount() < u.max and now - (u.last or -1) >= 1 / u.fps - 0.004 then need = true end
  end
  if not need then return end
  Cap.last = now
  local ok, img = pcall(canvas.newImageData, canvas)
  if not ok or not img then return end
  for _, u in pairs(Cap.users) do
    if u.channel:getCount() < u.max and now - (u.last or -1) >= 1 / u.fps - 0.004 then
      u.last = now
      u.channel:push(img)
    end
  end
  img:release()   -- os canais guardam a propria referencia
end

return Cap
