-- =============================================================================
--  R36 Control (thread): consultas e alteracoes sem travar a tela.
--  job.op = "status" | "led" | "gamma" | "path" | "volume" | "delete"
-- =============================================================================
require("love.timer")
local out_name, job = ...
local OUT = love.thread.getChannel(out_name)
local I18N = require("lib.i18n")
I18N.set(job.lang or "pt-BR")
local R = require("core.r36ctl")

local r = { t = "done", op = job.op }
local ok, err = pcall(function()
  if job.op == "led" then r.ok, r.why = R.apply_led(job.name)
  elseif job.op == "gamma" then r.ok, r.why = R.set_gamma(job.value)
  elseif job.op == "path" then r.ok, r.why = R.set_path(job.value)
  elseif job.op == "volume" then r.ok, r.why = R.set_boot_volume(job.value)
  elseif job.op == "delete" then r.ok, r.why = R.delete_config()
  end
  local s = R.status()
  -- descricoes ja no idioma (a thread tem o proprio I18N)
  s.desc = {}
  for _, n in ipairs(s.profiles) do s.desc[n] = R.describe(n) end
  if s.active then s.desc[s.active] = R.describe(s.active) end
  r.status = s
end)
if not ok then r.ok, r.why = false, tostring(err) end
OUT:push(r)
