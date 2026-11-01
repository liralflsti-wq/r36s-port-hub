-- Dispara pedidos de Wi-Fi em segundo plano (threads/wifi_thread.lua) e
-- guarda o ultimo estado conhecido para as outras telas (sem rodar comandos).
local J = { sudo = false, seq = 0, last = nil, last_t = -1 }

function J.start(op, params)
  J.seq = J.seq + 1
  local name = "hub_wifi_" .. J.seq
  local ch = love.thread.getChannel(name)
  ch:clear()
  local job = params or {}
  job.op, job.id, job.sudo = op, J.seq, J.sudo
  local th = love.thread.newThread("threads/wifi_thread.lua")
  th:start(name, job)
  job.psk = nil
  return { ch = ch, th = th, op = op }
end

--- resultado (tabela) quando pronto; nil enquanto roda
function J.poll(h)
  if not h then return nil end
  local r = h.ch:pop()
  if r then
    if r.sudo then J.sudo = true end
    if r.status then J.last, J.last_t = r.status, love.timer.getTime() end
    return r
  end
  local e = h.th:getError()
  if e then return { t = "done", op = h.op, error = tostring(e) } end
  return nil
end

return J
