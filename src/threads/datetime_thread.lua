-- =============================================================================
--  Data e hora (thread): consulta e alteracoes do relogio do sistema sem travar
--  a tela. job.op = "status" | "zones" | "set_tz" | "set_ntp" | "sync" | "set_time"
-- =============================================================================
require("love.timer")
local out_name, job = ...
local OUT = love.thread.getChannel(out_name)
local D = require("core.datetime")

local r = { t = "done", op = job.op }
local ok, err = pcall(function()
  if job.op == "status" then
    r.status = D.status()
  elseif job.op == "zones" then
    r.zones = D.zones()
  elseif job.op == "set_tz" then
    r.ok, r.why = D.set_timezone(job.zone)
    r.status = D.status()
  elseif job.op == "set_ntp" then
    r.ok, r.why = D.set_ntp(job.on)
    r.status = D.status()
  elseif job.op == "sync" then
    local okk, res = D.sync_now(function(i, n) OUT:push({ t = "progress", i = i, n = n }) end)
    r.ok = okk
    if okk then r.status = res else r.why = res; r.status = D.status() end
  elseif job.op == "set_time" then
    r.ok, r.why = D.set_time(job.y, job.mo, job.d, job.h, job.mi, job.s)
    r.status = D.status()
  end
end)
if not ok then r.ok, r.why = false, tostring(err) end
OUT:push(r)
