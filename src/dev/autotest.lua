-- Roteiro de teste automatico (somente desenvolvimento).
-- PORTHUB_AUTOTEST=<arquivo> com comandos, um por linha:
--   wait <seg> | press <acao> | shot <nome> | waitidle | waitconfirm | log <texto> | quit
local A = { steps = {}, i = 1, t = 0, pending_shot = nil }

function A.start(app, path)
  A.app = app
  A.dir = os.getenv("PORTHUB_SHOTDIR") or "/tmp"
  local f = io.open(path, "r")
  for line in f:lines() do
    local cmd, arg = line:match("^(%S+)%s*(.*)$")
    if cmd and cmd:sub(1, 1) ~= "#" then A.steps[#A.steps + 1] = { cmd, arg } end
  end
  f:close()
end

local Installer = require("core.installer")

function A.update(dt)
  local s = A.steps[A.i]
  if not s or A.pending_shot then return end
  local cmd, arg = s[1], s[2]
  if cmd == "wait" then
    A.t = A.t + dt
    if A.t < tonumber(arg) then return end
    A.t = 0
  elseif cmd == "press" then
    A.app_action(arg)
  elseif cmd == "shot" then
    A.pending_shot = arg
    return
  elseif cmd == "waitfile" then
    local f = io.open(arg, "r")
    if not f then return end
    f:close()
    os.remove(arg)
  elseif cmd == "touch" then
    local f = io.open(arg, "w")
    if f then f:write("1"); f:close() end
  elseif cmd == "waitdialog" then
    if not A.app.dialog then return end
  elseif cmd == "waitidle" then
    if Installer.job then return end
  elseif cmd == "waitconfirmrt" then
    local R = require("core.runtimes")
    if not (R.job and R.job.confirm) then return end
  elseif cmd == "waitidlert" then
    if require("core.runtimes").job then return end
  elseif cmd == "waitconfirm" then
    if not (Installer.job and Installer.job.confirm) then return end
  elseif cmd == "waitphase" then
    if not (Installer.job and Installer.job.phase == arg and (Installer.job.done or 0) > 0) then return end
  elseif cmd == "uninstplan" then
    -- imprime o plano de desinstalacao de um port do cartao (pelo nome do script)
    local Scan = require("core.scan")
    require("core.manifest").rescan(true)
    local lp = Scan.by_script[arg]
    local p = { id = "local:" .. arg, name = arg, is_local = true, local_items = lp and lp.items or { arg }, install_check = {} }
    local plan, why = require("core.uninstall").plan(p)
    print("[autotest] plano " .. arg .. ": " .. (plan and (table.concat(plan.targets, " | ") .. " / " .. table.concat(plan.evidence, ", ") .. " / " .. tostring(plan.note)) or ("RECUSADO: " .. tostring(why))))
  elseif cmd == "rmfile" then
    os.remove(arg)
  elseif cmd == "exists" then
    local f = io.open(arg, "rb")
    print("[autotest] existe " .. arg .. " = " .. tostring(f ~= nil)); io.stdout:flush()
    if f then f:close() end
  elseif cmd == "uninstall" then
    -- Meus Ports > X de um port do cartao (pelo nome do script)
    local Scan = require("core.scan")
    require("core.manifest").rescan(true)
    local lp = Scan.by_script[arg]
    local p = { id = "local:" .. arg, name = arg, is_local = true, local_items = lp and lp.items or { arg }, install_check = {}, version = "" }
    A.app.ask_uninstall(p)
  elseif cmd == "pickname" then
    local cur = A.app.current()
    for i, it in ipairs(cur.list or {}) do if it.name == arg then cur.sel = i end end
  elseif cmd == "dialogtext" then
    print("[autotest] dialogo: " .. tostring(A.app.dialog and A.app.dialog.title) .. " | " .. tostring(A.app.dialog and A.app.dialog.body):gsub("\n", " / "))
    io.stdout:flush()
  elseif cmd == "errdialog" then
    A.app.show_dialog({ title = "Falha de teste", kind = "error", body = "Download falhou (teste). PASS segredo123 senha=abc" })
  elseif cmd == "threadcrash" then
    local th = love.thread.newThread("-- teste\nerror('falha simulada dentro de uma tarefa')")
    th:start()
  elseif cmd == "errscreen" then
    -- desenha a tela de erro fatal (com o aviso do registro) e salva a imagem
    local loop = love.errorhandler("erro simulado pelo teste automatico")
    loop()
    local name = A.dir .. "/" .. (arg ~= "" and arg or "errscreen") .. ".png"
    love.graphics.captureScreenshot(name:match("[^/]+$"))
    loop()
    print("[autotest] shot errscreen " .. love.filesystem.getSaveDirectory()); io.stdout:flush()
    os.exit(0)
  elseif cmd == "crash" then
    error("erro simulado pelo teste automatico")
  elseif cmd == "push" then
    local name, path = tostring(arg):match("^(%S+)%s+(.+)$")
    if name then A.app.push(name, { path = path }) else A.app.push(arg) end
  elseif cmd == "pushid" then
    -- abre uma tela com { id = ... } (ex.: pushid settings_cat appearance)
    local name, id = tostring(arg):match("^(%S+)%s+(%S+)$")
    A.app.push(name, { id = id })
  elseif cmd == "fontsize" then
    A.app.set_font_level(arg)
  elseif cmd == "lang" then
    A.app.set_language(arg)
  elseif cmd == "dialog" then
    A.app.show_dialog({ title = "Teste", kind = "warn", body = "Este é um diálogo de teste com um texto longo para conferir a quebra de linhas no tamanho do texto escolhido. Nenhum arquivo foi alterado e a instalação anterior continua como estava. Confira se o texto cabe na tela.",
      buttons = { { label = "Cancelar" }, { label = "Continuar" } } })
  elseif cmd == "dialoglist" then
    A.app.show_dialog({ title = "Teste", kind = "info", list = true, body = "Escolha o que fazer com o item selecionado.",
      buttons = { { label = "Recortar", sub = "Mover para outra pasta depois" }, { label = "Excluir", sub = "Apagar do cartão SD", danger = true }, { label = "Extrair aqui", sub = "Descompactar nesta pasta" }, { label = "Cancelar" } } })
  elseif cmd == "pushport" or cmd == "uninstport" then
    local Cat = require("core.catalog")
    for _, pp in ipairs(Cat.ports) do
      if pp.id == arg then
        if cmd == "pushport" then A.app.push("details", { port = pp }) else A.app.ask_uninstall(pp) end
      end
    end
  elseif cmd == "theme" then
    require("core.themes").apply(arg, false)
  elseif cmd == "refreshcat" then
    A.app.refresh_catalog(true)
  elseif cmd == "eco" then
    A.app.eco = arg == "1"
  elseif cmd == "anim" then
    A.app.anim = arg == "1"
  elseif cmd == "cpustart" then
    A.cpu0, A.wall0, A.frames0 = os.clock(), love.timer.getTime(), A.frames or 0
  elseif cmd == "cpuend" then
    local wall = love.timer.getTime() - A.wall0
    print(string.format("[autotest] %s: %.1f quadros/s, CPU %.1f%% (eco=%s, animacoes=%s)", arg,
      ((A.frames or 0) - A.frames0) / wall, 100 * (os.clock() - A.cpu0) / wall, tostring(A.app.eco), tostring(A.app.animations())))
    io.stdout:flush()
  elseif cmd == "pushfiles" then
    A.app.push("files", { path = arg })
  elseif cmd == "selrow" then
    -- seleciona a linha de settings_cat pelo rotulo (chave pt)
    local cur = A.app.current()
    for i, r in ipairs(cur and cur.rows or {}) do
      if tostring(r.label) == arg then cur.sel = i end
    end
    local labs = {} for _, r in ipairs(cur and cur.rows or {}) do labs[#labs + 1] = tostring(r.label) end
    print("[autotest] selrow " .. arg .. " -> " .. tostring(cur and cur.sel) .. " em " .. tostring(cur and cur.name) .. " [" .. table.concat(labs, "|") .. "]"); io.stdout:flush()
  elseif cmd == "backto" then
    if A.app.dialog then A.app.close_dialog() end
    while #A.app.stack > 1 and A.app.current().name ~= arg do A.app.pop() end
  elseif cmd == "curinfo" then
    local cur = A.app.current()
    local names = {} for _, sc in ipairs(A.app.stack) do names[#names + 1] = sc.name end
    local out = { "tela=" .. tostring(cur and cur.name) .. " pilha=" .. table.concat(names, ">"), "titulo=" .. tostring(cur and cur.p and cur.p.title) }
    for i, it in ipairs(cur and cur.items or {}) do
      out[#out + 1] = string.format("[%d] %s | %s | %s", i, tostring(it.tag), tostring(it.text), tostring(it.sub))
      if i >= 12 then break end
    end
    if A.app.dialog then out[#out + 1] = "dialogo=" .. tostring(A.app.dialog.title) .. " | " .. tostring(A.app.dialog.body):gsub("\n", " / ") end
    print("[autotest] " .. table.concat(out, "\n[autotest]   ")); io.stdout:flush()
  elseif cmd == "sel" then
    local cur = A.app.current()
    if cur then cur.sel = tonumber(arg) end
  elseif cmd == "biosdir" then
    local d = require("core.bios").detect_dir(true)
    print("[autotest] biosdir=" .. tostring(d.dir) .. " origem=" .. tostring(d.source) .. " roms=" .. tostring(d.roms) .. " difere=" .. tostring(d.differs))
    io.stdout:flush()
  elseif cmd == "waitbios" then
    if require("core.bios").busy() then return end
  elseif cmd == "biosstate" then
    local B = require("core.bios")
    local j = B.job
    print("[autotest] bios op=" .. tostring(j and j.op) .. " estado=" .. tostring(j and j.state) .. " erro=" .. tostring(j and j.error_code)
      .. " det=" .. tostring(j and j.detail) .. " dialogo=" .. tostring(A.app.dialog and A.app.dialog.body))
    io.stdout:flush()
  elseif cmd == "dlstate" then
    local D = require("core.downloads")
    for _, e in ipairs(D.list) do
      local st = {}
      for k, v in pairs(e.stages or {}) do st[#st + 1] = k .. ":" .. tostring(v.state) end
      print("[autotest] download " .. tostring(e.name) .. " estado=" .. tostring(e.state) .. " op=" .. tostring(e.op) .. " etapas=" .. table.concat(st, ","))
    end
    io.stdout:flush()
  elseif cmd == "closedialog" then
    A.app.close_dialog()
  elseif cmd == "pop" then
    A.app.pop()
  elseif cmd == "waitpm" then
    if require("core.pmmanager").busy() then return end
  elseif cmd == "waitpmconfirm" then
    local PMm = require("core.pmmanager")
    if not (PMm.job and PMm.job.confirm and A.app.dialog) then return end
  elseif cmd == "music" then
    local M = require("core.music")
    local st = {}
    for n, src in pairs(M.sources) do
      st[#st + 1] = string.format("%s:%s:%.2f", n, src:isPlaying() and "play" or "stop", src:getVolume())
    end
    table.sort(st)
    print("[autotest] music cur=" .. tostring(M.current) .. " enabled=" .. tostring(M.enabled) .. " avail=" .. tostring(M.available) .. " " .. table.concat(st, " "))
    io.stdout:flush()
  elseif cmd == "screen" then
    local cur = A.app.current()
    print("[autotest] tela=" .. tostring(cur and cur.name) .. " pilha=" .. #A.app.stack .. " dialogo=" .. tostring(A.app.dialog ~= nil))
    io.stdout:flush()
  elseif cmd == "streamaddr" then
    -- grava o endereco da transmissao num arquivo (teste com cliente externo)
    local St = require("core.stream")
    local addr = St.address(require("core.net").status())
    if not addr then return end
    local f = io.open(arg, "w"); f:write(addr); f:close()
  elseif cmd == "waitrec" then
    local Rc = require("core.recorder")
    if arg == "on" and Rc.state ~= "on" then return end
    if arg == "off" and Rc.running() then return end
  elseif cmd == "streamstate" then
    local St, Rc = require("core.stream"), require("core.recorder")
    print("[autotest] stream=" .. St.state .. " viewers=" .. St.viewers .. " rec=" .. Rc.state .. " file=" .. tostring(Rc.file)
      .. " dur=" .. string.format("%.1f", Rc.dur or 0) .. " size=" .. tostring(Rc.size) .. " err=" .. tostring(Rc.last_error))
    io.stdout:flush()
  elseif cmd == "pushpkg" then
    -- abre a analise de um pacote da pasta update
    local Folder = require("core.updater.folder")
    local path = Folder.DIR .. "/" .. arg
    local f = io.open(path, "rb"); local size = f and f:seek("end") or 0; if f then f:close() end
    A.app.push("upd_pkg", { path = path, name = arg, size = size, format = require("core.updater.formats").detect_magic(path), origin = "local" })
  elseif cmd == "waitupd" then
    local M = require("core.updater.manager")
    if M.busy() then return end
    local cur = A.app.current()
    if cur and cur.name == "upd_pkg" and (cur.state == "wait" or cur.state == "analyzing") then return end
  elseif cmd == "updfail" then
    love.thread.getChannel("hub_updater_in"):push("__simulate_fail__")
  elseif cmd == "updstate" then
    local cur = A.app.current()
    local M = require("core.updater.manager")
    local r = cur and cur.report
    local probs = {}
    for _, p in ipairs(r and r.problems or {}) do probs[#probs + 1] = p.code .. ":" .. tostring(p.path) end
    print("[autotest] upd tela=" .. tostring(cur and cur.name) .. " estado=" .. tostring(cur and cur.state) .. " modo=" .. tostring(r and r.mode)
      .. " versao=" .. tostring(r and r.version) .. " troca=" .. tostring(r and r.replace) .. " novos=" .. tostring(r and r.new)
      .. " problemas=[" .. table.concat(probs, " ") .. "] erro=" .. tostring(cur and cur.err) .. " job=" .. tostring(M.job and M.job.op) .. "/" .. tostring(M.job and M.job.state))
    io.stdout:flush()
  elseif cmd == "scaninit" then
    A.scanner = require("dev.scan"); A.scanner.install(A.app)
  elseif cmd == "scanopen" then
    local name, id = tostring(arg):match("^(%S+)%s*(%S*)$")
    A.scanner.open(name, id ~= "" and { id = id } or nil)
  elseif cmd == "scanpop" then
    while #A.app.stack > 1 do pcall(A.app.pop) end
  elseif cmd == "scandump" then
    A.scanner.dump(arg)
  elseif cmd == "dumpsettings" then
    local D = require("ui.settings_defs")
    for _, c in ipairs(D.LIST) do
      print("[cat] " .. c.id .. " | " .. tostring(c.name))
      local ok, rows = pcall(function() return type(c.rows) == "function" and c.rows({}) or c.rows end)
      for _, r in ipairs(ok and rows or {}) do
        print("    - " .. tostring(r.kind) .. " | " .. tostring(r.label))
      end
      if not ok then print("    ERRO " .. tostring(rows)) end
    end
    io.stdout:flush()
  elseif cmd == "log" then
    print("[autotest] " .. arg)
  elseif cmd == "quit" then
    love.event.quit()
  end
  A.i = A.i + 1
end

function A.app_action(act)
  local Input = require("core.input")
  Input.handler(act)
end

function A.after_draw()
  A.frames = (A.frames or 0) + 1
  if A.pending_shot then
    local name = A.pending_shot
    A.pending_shot = nil
    love.graphics.captureScreenshot(function(img)
      local data = img:encode("png")
      local f = io.open(A.dir .. "/" .. name .. ".png", "wb")
      f:write(data:getString())
      f:close()
      print("[autotest] shot " .. name)
    end)
    A.i = A.i + 1
  end
end

return A
