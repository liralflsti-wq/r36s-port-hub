-- Tarefas de data e hora em segundo plano (threads/datetime_thread.lua)
local J = { seq = 0 }

function J.start(op, params)
  J.seq = J.seq + 1
  local name = "hub_dtj_" .. J.seq
  local ch = love.thread.getChannel(name)
  ch:clear()
  local job = params or {}
  job.op = op
  local th = love.thread.newThread("threads/datetime_thread.lua")
  th:start(name, job)
  return { ch = ch, th = th, op = op }
end

--- resultado quando pronto (progresso e ignorado); nil enquanto roda
function J.poll(h)
  if not h then return nil end
  local m = h.ch:pop()
  while m and m.t == "progress" do m = h.ch:pop() end
  if m then return m end
  local e = h.th:getError()
  if e then return { op = h.op, ok = false, why = tostring(e) } end
  return nil
end

return J
