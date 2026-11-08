-- =============================================================================
--  Comandos de verificacao em segundo plano (threads/shjob_thread.lua)
--  Sh.start(cmds, on_done) -> job; Sh.update() e chamado pelo app a cada quadro.
--  on_done(results) recebe { out=, rc=, secs= } de cada comando, na ordem.
-- =============================================================================
local U = require("lib.util")

local Sh = { jobs = {}, seq = 0 }

function Sh.start(cmds, on_done)
  Sh.seq = Sh.seq + 1
  local name = "hub_shjob_" .. Sh.seq
  local ch = love.thread.getChannel(name)
  ch:clear()
  local th = love.thread.newThread("threads/shjob_thread.lua")
  local j = { thread = th, ch = ch, on_done = on_done, done = 0, total = #cmds, running = true }
  Sh.jobs[#Sh.jobs + 1] = j
  th:start({ out = name, cmds = cmds })
  return j
end

function Sh.update()
  for i = #Sh.jobs, 1, -1 do
    local j = Sh.jobs[i]
    local err = j.thread:getError()
    if err then
      U.log("verificação em segundo plano falhou:", err)
      j.running = false
      table.remove(Sh.jobs, i)
      if j.on_done then pcall(j.on_done, nil, err) end
    else
      local m = j.ch:pop()
      while m do
        if m.t == "progress" then j.done = m.done
        elseif m.t == "done" then
          j.running = false
          table.remove(Sh.jobs, i)
          if j.on_done then
            local ok, e = pcall(j.on_done, m.results)
            if not ok then U.log("retorno da verificação falhou:", e) end
          end
          break
        end
        m = j.ch:pop()
      end
    end
  end
end

return Sh
