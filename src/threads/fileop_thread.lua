-- =============================================================================
--  Gerenciador de arquivos: mover (colar) e excluir sem travar a tela.
--  job = { op = "move", src, dest } | { op = "copy", src, dest } | { op = "delete", path }
--        | { op = "install_dir", src, dest, items }  (copia uma pasta de port ja extraida)
--  Resultado: { ok, error }
-- =============================================================================
local out_name, job = ...
local OUT = love.thread.getChannel(out_name)

local function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function exists(p)
  return os.execute("test -e " .. shq(p) .. " -o -L " .. shq(p)) == 0
end

local function run(cmd)
  local f = io.popen("{ " .. cmd .. "; } 2>&1; echo \"__EXIT:$?\"")
  local out = f and f:read("*a") or ""
  if f then f:close() end
  local code = tonumber(out:match("__EXIT:(%d+)%s*$"))
  return code == 0, (out:gsub("__EXIT:%d+%s*$", ""):gsub("%s+$", ""))
end

local r = { t = "done", op = job.op }
if job.op == "move" then
  if exists(job.dest) then
    r.ok, r.error = false, "exists"
  else
    -- -n: nunca sobrescreve; entre cartoes diferentes o mv copia e depois apaga a origem
    local ok, out = run("mv -n -- " .. shq(job.src) .. " " .. shq(job.dest))
    if ok and exists(job.dest) and not exists(job.src) then
      r.ok = true
    else
      r.ok, r.error = false, out ~= "" and out or "mv"
    end
    os.execute("sync")
  end
elseif job.op == "copy" then
  -- copia (arquivo ou pasta inteira); nunca sobrescreve. Se falhar no meio
  -- (ex.: cartao cheio), apaga so a copia incompleta; a origem nao e tocada.
  if exists(job.dest) then
    r.ok, r.error = false, "exists"
  else
    local ok, out = run("cp -a -n -- " .. shq(job.src) .. " " .. shq(job.dest))
    if ok and exists(job.dest) then
      r.ok = true
    else
      run("rm -rf -- " .. shq(job.dest))
      r.ok, r.error = false, out ~= "" and out or "cp"
    end
    os.execute("sync")
  end
elseif job.op == "install_dir" then
  -- confere de novo: nada pode existir no destino (nunca sobrescreve)
  for _, n in ipairs(job.items or {}) do
    if exists(job.dest .. "/" .. n) then r.ok, r.error = false, n .. ": exists"; break end
  end
  if r.ok == nil then
    local copied, failed = {}, nil
    for _, n in ipairs(job.items or {}) do
      local ok, out = run("cp -a -n -- " .. shq(job.src .. "/" .. n) .. " " .. shq(job.dest .. "/" .. n))
      if not ok or not exists(job.dest .. "/" .. n) then failed = n .. ": " .. (out ~= "" and out or "cp"); break end
      copied[#copied + 1] = n
    end
    if failed then
      -- desfaz so o que esta operacao copiou
      for _, n in ipairs(copied) do run("rm -rf -- " .. shq(job.dest .. "/" .. n)) end
      r.ok, r.error = false, failed
    else
      for _, n in ipairs(job.items or {}) do
        if n:lower():match("%.sh$") then run("chmod +x -- " .. shq(job.dest .. "/" .. n)) end
      end
      r.ok = true
    end
    os.execute("sync")
  end
elseif job.op == "delete" then
  local ok, out = run("rm -rf -- " .. shq(job.path))
  r.ok = ok and not exists(job.path)
  if not r.ok then r.error = out ~= "" and out or "rm" end
  os.execute("sync")
end
OUT:push(r)
