-- =============================================================================
--  Wi-Fi (thread): executa um pedido ao NetworkManager sem travar a tela.
--  job = { op = "status"|"scan"|"saved"|"connect"|"reconnect"|"disconnect"|
--          "forget"|"radio", ... }   resultado em { t = "done", op, ... }
--  A senha (job.psk) so existe na memoria desta thread e no pipe para o nmcli.
-- =============================================================================
require("love.filesystem")
require("love.timer")
local out_name, job = ...
local OUT = love.thread.getChannel(out_name)
local W = require("core.wifi")
W.SUDO = job.sudo and true or false

local r = { t = "done", op = job.op, id = job.id }
local ok, err = pcall(function()
  if job.op == "status" then
    r.status = W.status()
  elseif job.op == "scan" then
    r.status = W.status()
    if r.status.nmcli and r.status.iface and r.status.radio ~= false then
      r.list, r.error = W.scan(r.status.iface)
    end
  elseif job.op == "saved" then
    r.list, r.error = W.saved()
    r.status = W.status()
  elseif job.op == "connect" then
    r.result = W.connect(job.net, { iface = job.iface, psk = job.psk, uuid = job.uuid })
    r.status = W.status()
  elseif job.op == "reconnect" then
    r.result = W.reconnect(job.uuid, job.iface)
    r.status = W.status()
  elseif job.op == "disconnect" then
    r.ok, r.detail = W.disconnect(job.iface)
    r.status = W.status()
  elseif job.op == "forget" then
    r.ok, r.detail = W.forget(job.uuid)
    r.list = W.saved()
    r.status = W.status()
  elseif job.op == "radio" then
    r.ok, r.detail = W.radio(job.on)
    love.timer.sleep(1)
    r.status = W.status()
  end
end)
job.psk = nil
if not ok then r.error = tostring(err) end
r.sudo = W.SUDO
OUT:push(r)
