-- Observador de rede: le o estado (IP/interface) periodicamente fora da tela
require("love.filesystem")
require("love.timer")
local interval = ...
local Net = require("core.net")
local out = love.thread.getChannel("hub_net_out")
local ctl = love.thread.getChannel("hub_net_ctl")
while true do
  local ok, st = pcall(Net.status)
  if ok and st then out:clear(); out:push(st) end
  local m = ctl:demand(interval or 4)
  if m == "stop" then break end
  while ctl:pop() do end
end
