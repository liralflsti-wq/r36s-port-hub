-- Teste automatico do instalador (somente desenvolvimento)
-- PORTHUB_INSTALLTEST="id:answer,id:answer,..."  answer = yes|no|cancel|- ; resultado em stdout
local Installer = require("core.installer")
local Catalog = require("core.catalog")
local X = { queue = {}, cur = nil }
local _print = print
local function print(s) _print(s); io.stdout:flush() end

function X.start(spec)
  for item in spec:gmatch("[^,]+") do
    local id, ans = item:match("^([^:]+):?(.*)$")
    X.queue[#X.queue + 1] = { id = id, ans = ans ~= "" and ans or "-" }
  end
end

local Runtimes = require("core.runtimes")
function X.update(dt)
  if X.del then
    X.del.update()
    local j = X.del.job
    if j and j.finished then
      print("[itest] DEL RESULT ok=" .. tostring(j.ok) .. " falhas=" .. table.concat(j.failed or {}, ","))
      X.del.clear(); X.del = nil
    end
    return
  end
  local rj = Runtimes.job
  if X.cur and X.cur.rt then
    if rj and rj.confirm then
      local c = rj.confirm
      print(string.format("[itest] RT CONFIRM new=%d upd=%d ok=%d dl=%d libs=%s items=%s", c.new, c.update, c.ok, c.download, c.libs, table.concat(c.items, "|")))
      Runtimes.answer(X.cur.ans == "yes")
    end
    if rj and rj.finished then
      local sm = rj.summary or {}
      print(string.format("[itest] RT RESULT %s %s %s new=%s upd=%s ok=%s uptodate=%s", tostring(rj.result), tostring(rj.error_code or ""),
        (rj.error or ""):gsub("\n", " / "), tostring(sm.new), tostring(sm.update), tostring(sm.ok), tostring(sm.uptodate)))
      Runtimes.clear()
      X.cur = nil
    end
    return
  end
  local j = Installer.job
  if X.cur and j then
    if j.confirm then
      print("[itest] " .. X.cur.id .. " CONFIRM " .. table.concat(j.confirm, "|"))
      Installer.answer(X.cur.ans == "yes")
    end
    if X.cur.ans == "cancel" and j.phase == "download" and (j.done or 0) > 0 and not j.cancelling then
      print("[itest] " .. X.cur.id .. " cancel at " .. j.done)
      Installer.cancel()
    end
    if j.finished then
      print(string.format("[itest] %s RESULT %s %s %s", X.cur.id, tostring(j.result), tostring(j.error_code or ""),
        (j.error or ""):gsub("\n", " / ")))
      if j.entries then print("[itest] " .. X.cur.id .. " ENTRIES " .. table.concat(j.entries, "|")) end
      if not (j.opts and j.opts.local_file) then print("[itest] " .. X.cur.id .. " STATUS " .. App.status(j.port)) end
      if j.opts and j.opts.local_file then print("[itest] " .. X.cur.id .. " DELETED " .. tostring(j.deleted)) end
      Installer.clear()
      X.cur = nil
    end
    return
  end
  if not X.cur then
    local nxt = table.remove(X.queue, 1)
    if not nxt then print("[itest] ALLDONE"); love.event.quit(); return end
    local dname = nxt.id:match("^del=(.+)$")
    if dname then
      local Un = require("core.uninstall")
      local target
      for _, q in ipairs(Catalog.filter("installed", App.status)) do if q.name == dname then target = q end end
      if not target then print("[itest] DEL " .. dname .. " NAO LISTADO"); return end
      local plan, why = Un.plan(target)
      if not plan then print("[itest] DEL " .. dname .. " RECUSADO: " .. why:gsub("\n", " / ")); return end
      print("[itest] DEL " .. dname .. " PLANO: " .. table.concat(plan.targets, " | ") .. "  [" .. table.concat(plan.evidence, ", ") .. "]")
      Un.start(plan)
      X.del = Un
      return
    end
    local mode, fpath = nxt.id:match("^(%a+)=(.+)$")
    if mode then
      local name = fpath:match("([^/]+)$")
      local p = { id = "file:" .. fpath, slug = "file_" .. name:gsub("%W", "_"), name = name, download_url = "", install_check = {}, version = "" }
      X.cur = { id = name, ans = nxt.ans }
      local ok, err = Installer.start(p, { local_file = fpath, delete_source = true,
        mode = mode == "extract" and "extract" or "port", dest_dir = mode == "extract" and fpath:match("^(.*)/[^/]+$") or nil })
      if not ok then print("[itest] STARTFAIL " .. tostring(err)); X.cur = nil end
      return
    end
    if nxt.id == "rt" then
      X.cur = { rt = true, ans = nxt.ans }
      Runtimes.start()
      return
    end
    if nxt.id:sub(1, 1) == "?" then
      local q = Catalog.by_id[nxt.id:sub(2)]
      local M = require("core.manifest")
      local f, by = M.found(q)
      print(string.format("[itest] %s STATUS %s by=%s found=%s", q.id, M.status(q), tostring(by), f and table.concat(f, "|") or "-"))
      return
    end
    local p = Catalog.by_id[nxt.id]
    if not p then print("[itest] missing " .. nxt.id); return end
    X.cur = nxt
    local ok, err = Installer.start(p)
    if not ok then print("[itest] " .. nxt.id .. " STARTFAIL " .. tostring(err)); X.cur = nil end
  end
end

return X
