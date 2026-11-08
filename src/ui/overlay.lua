-- =============================================================================
--  Camadas sobre as telas: progresso da instalacao, dialogos e avisos rapidos
-- =============================================================================
local L = require("lib.i18n").L
local T = require("ui.theme")
local G = require("ui.gfx")
local U = require("lib.util")
local C = require("config")
local Installer = require("core.installer")
local Runtimes = require("core.runtimes")
local Downloads = require("core.downloads")
local lg = love.graphics

local O = {}

local STEPS = {
  { key = "download", label = L("Download") },
  { key = "verify", label = L("Verificação") },
  { key = "extract", label = L("Extração") },
  { key = "install", label = L("Instalação") },
}
local PHASE_STEP = { prepare = 1, download = 1, verify = 2, extract = 3, analyze = 4, install = 4 }

local KIND_COLOR = { info = T.c.accent2, ok = T.c.green, error = T.c.red, warn = T.c.yellow }

local function dim_screen(a)
  G.rect(0, 0, T.W, T.H, T.c.black, 0, a or 0.62)
end

local function check_mark(x, y, c)
  G.color(c)
  lg.setLineWidth(3)
  lg.line(x, y + 6, x + 4, y + 10, x + 12, y + 1)
  lg.setLineWidth(1)
end

local function buttons_row(buttons, sel, cx, y)
  local f = T.f.pix8
  local widths, total = {}, 0
  for i, b in ipairs(buttons) do
    widths[i] = math.max(96, f:getWidth(b.label) + 28)
    total = total + widths[i] + (i > 1 and 12 or 0)
  end
  local x = cx - total / 2
  for i, b in ipairs(buttons) do
    local w = widths[i]
    local on = i == sel
    if on then
      G.rect(x - 2, y - 2, w + 4, 32, T.c.accent, 7, App.pulse(0.35, 0.15, 5))
      G.rect(x, y, w, 28, b.danger and T.c.red or T.c.accent, 6)
      G.text(f, b.label, x, y + 10, T.c.bg0, "center", w)
    else
      G.rect(x, y, w, 28, T.c.bg3, 6)
      G.frame(x, y, w, 28, T.c.line, 6)
      G.text(f, b.label, x, y + 10, T.c.dim, "center", w)
    end
    x = x + w + 12
  end
end

---------------------------------------------------------------------------
-- Dialogo generico
---------------------------------------------------------------------------
--- botoes em lista vertical (d.list = true): rotulo + descricao opcional
local LIST_RH = 40
--- altura de cada botao da lista: cresce com o tamanho do texto (rotulo + descricao)
local function list_rh(buttons)
  local any_sub = false
  for _, b in ipairs(buttons) do if b.sub then any_sub = true end end
  local grow = T.f.bodyb:getHeight() - T.base_font(T.f.bodyb):getHeight()
  local need = LIST_RH + grow + (any_sub and (T.f.small:getHeight() - T.base_font(T.f.small):getHeight()) or 0)
  return math.max(LIST_RH, need)
end
local function buttons_list(buttons, sel, x, y, w, rh)
  rh = rh or LIST_RH
  local LIST_RH = rh
  -- sem espaco para crescer (rh = 40): rotulo e descricao no tamanho padrao
  local fl, fs = T.f.bodyb, T.f.small
  if rh <= 40 then fl, fs = T.base_font(fl), T.base_font(fs) end
  local hb = T.base_font(T.f.bodyb):getHeight()
  local grow = fl:getHeight() - hb
  for i, b in ipairs(buttons) do
    local on = i == sel
    local by = y + (i - 1) * (LIST_RH + 6)
    if on then
      G.rect(x - 2, by - 2, w + 4, LIST_RH + 4, b.danger and T.c.red or T.c.accent, 8, App.pulse(0.35, 0.15, 5))
      G.rect(x, by, w, LIST_RH, T.c.bg3, 7)
      G.frame(x, by, w, LIST_RH, b.danger and T.c.red or T.c.accent, 7, 2)
    else
      G.rect(x, by, w, LIST_RH, T.c.bg2, 7)
      G.frame(x, by, w, LIST_RH, T.c.line, 7)
    end
    local lc = on and (b.danger and T.c.red or T.c.text) or T.c.dim
    if b.sub then
      G.text_fit(fl, b.label, x + 16, by + 4, w - 32, lc)
      G.text_fit(fs, b.sub, x + 16, by + 23 + grow, w - 32, on and T.c.dim or T.c.faint)
    else
      G.text_fit(fl, b.label, x + 16, by + 11 + math.floor((LIST_RH - 40 - grow) / 2), w - 32, lc)
    end
  end
end

function O.draw_dialog(app, d)
  dim_screen(0.66)
  if d.list then
    local w = 520
    -- texto maior: os botoes crescem; se a janela passar da tela, eles voltam a
    -- 40 px e o texto do corpo diminui (ou e encurtado) para caber
    local rh = list_rh(d.buttons)
    if 74 + 10 + #d.buttons * (rh + 6) > T.H - 60 then rh = LIST_RH end
    local maxb = T.H - 16 - 74 - 10 - #d.buttons * (rh + 6)
    local bf, lines, lh = G.fit_lines(T.f.body, d.body or "", w - 48, math.max(maxb, 20))
    local h = 74 + #lines * lh + #d.buttons * (rh + 6) + 10
    local x, y = (T.W - w) / 2, (T.H - h) / 2
    local kc = KIND_COLOR[d.kind or "info"] or T.c.accent2
    G.panel(x, y, w, h, { bg = T.c.bg1, border = kc, lw = 2, r = 10 })
    G.rect(x, y, w, 6, kc, 3)
    G.text(T.f.pix16, U.upper(d.title or ""), x + 24, y + 22, kc)
    local ty = y + 54
    for _, l in ipairs(lines) do
      G.text(bf, l, x + 24, ty, T.c.text)
      ty = ty + lh
    end
    buttons_list(d.buttons, d.sel, x + 24, ty + 8, w - 48, rh)
    return
  end
  local w = 500
  -- texto maior: se a janela passar da tela, o corpo diminui ou e encurtado
  local bf, lines, lh = G.fit_lines(T.f.body, d.body or "", w - 48, T.H - 16 - 126)
  local h = 126 + #lines * lh
  local x, y = (T.W - w) / 2, (T.H - h) / 2
  local kc = KIND_COLOR[d.kind or "info"] or T.c.accent2
  G.panel(x, y, w, h, { bg = T.c.bg1, border = kc, lw = 2, r = 10 })
  G.rect(x, y, w, 6, kc, 3)
  G.text(T.f.pix16, U.upper(d.title or ""), x + 24, y + 22, kc)
  local ty = y + 54
  for _, l in ipairs(lines) do
    G.text(bf, l, x + 24, ty, T.c.text)
    ty = ty + lh
  end
  buttons_row(d.buttons, d.sel, T.W / 2, y + h - 44)
end

function O.dialog_action(app, act)
  local d = app.dialog
  if act == (d.list and "up" or "left") then d.sel = math.max(1, d.sel - 1)
  elseif act == (d.list and "down" or "right") then d.sel = math.min(#d.buttons, d.sel + 1)
  elseif act == "a" then
    local b = d.buttons[d.sel]
    app.close_dialog()
    if b and b.fn then b.fn() end
  elseif act == "b" then
    local cancel = d.cancel
    app.close_dialog()
    if cancel then cancel() end
  else
    -- botao com tecla propria (ex.: key = "y"), alem da navegacao normal
    for _, b in ipairs(d.buttons or {}) do
      if b.key and b.key == act then
        app.close_dialog()
        if b.fn then b.fn() end
        return
      end
    end
  end
end

---------------------------------------------------------------------------
-- Aviso rapido
---------------------------------------------------------------------------
-- posicao escolhida em Configuracoes > Preferencias > Posicao das notificacoes
O.TOAST_POS = { "bottom", "top", "top_right", "bottom_right" }
function O.draw_toast(app, t)
  local f = T.f.body
  local pos = require("core.prefs").get("notif_pos") or "bottom"
  local corner = pos == "top_right" or pos == "bottom_right"
  local maxw = corner and 330 or 520
  local lines = G.wrap(f, t.text, maxw - 36)
  local lh = f:getHeight()
  local w = 0
  for _, l in ipairs(lines) do w = math.max(w, f:getWidth(l)) end
  w = w + 40
  local h = #lines * lh + 18
  local x, y = (T.W - w) / 2, T.H - 44 - h
  if pos == "top" then y = 44
  elseif pos == "top_right" then x, y = T.W - 12 - w, 44
  elseif pos == "bottom_right" then x = T.W - 12 - w end
  local a = math.min(1, t.t * 3)
  local kc = KIND_COLOR[t.kind] or T.c.accent2
  G.rect(x + 2, y + 3, w, h, T.c.shadow, 8, a)
  G.rect(x, y, w, h, T.c.bg2, 8, a)
  G.rect(x, y, 5, h, kc, 3, a)
  for i, l in ipairs(lines) do
    G.text(f, l, x + 20, y + 9 + (i - 1) * lh, T.c.text)
  end
end

---------------------------------------------------------------------------
-- Progresso da instalacao
---------------------------------------------------------------------------
function O.draw_install(app, j)
  if j.finished or j.background then return end
  dim_screen(0.7)
  local w, h = 540, 268
  local x, y = (T.W - w) / 2, (T.H - h) / 2 - 10
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.accent2, lw = 2, r = 10 })
  G.rect(x, y, w, 6, T.c.accent2, 3)
  local jopts = j.opts or {}
  G.text(T.f.pix16, jopts.mode == "extract" and L("EXTRAINDO") or L("INSTALANDO"), x + 24, y + 22, T.c.accent2)
  G.text_fit(T.f.h2, j.port.name, x + 24, y + 40, w - 48, T.c.text)

  -- etapas
  local cur = PHASE_STEP[j.phase] or 1
  local sw = (w - 48) / #STEPS
  for i, s in ipairs(STEPS) do
    local sx = x + 24 + (i - 1) * sw
    local sy = y + 84
    local c
    if i < cur then c = T.c.green
    elseif i == cur then c = T.c.yellow
    else c = T.c.faint end
    G.rect(sx, sy, sw - 8, 34, T.c.bg2, 6)
    if i == cur then G.frame(sx, sy, sw - 8, 34, c, 6, 1, App.pulse(0.6, 0.4, 6)) end
    if i < cur then
      check_mark(sx + 10, sy + 11, c)
    else
      G.text(T.f.pix8, tostring(i), sx + 12, sy + 13, c)
    end
    local lbl = (i == 1 and jopts.local_file) and L("Arquivo") or s.label
    G.text(T.f.bodyb, lbl, sx + 30, sy + 8, i <= cur and T.c.text or T.c.faint)
  end

  -- barra + detalhes
  local by = y + 140
  local label, detail, frac = "", "", nil
  if j.phase == "prepare" then
    label = L("Preparando...")
    detail = L("Verificando pasta de ports e espaço livre")
  elseif j.phase == "download" then
    label = L("Baixando arquivo")
    if j.total and j.total > 0 then
      frac = j.done / j.total
      detail = string.format(L("%s de %s"), U.format_bytes(j.done), U.format_bytes(j.total))
    else
      detail = U.format_bytes(j.done) .. L(" recebidos")
    end
    if j.speed and j.speed > 0 then
      detail = detail .. "  •  " .. U.format_speed(j.speed)
      if j.eta then detail = detail .. L("  •  faltam ") .. U.format_time(j.eta) end
    end
  elseif j.phase == "verify" then
    label = L("Verificando o download")
    detail = L("Conferindo se o arquivo chegou completo e íntegro")
  elseif j.phase == "extract" then
    label = L("Extraindo arquivos")
    if j.total and j.total > 0 then
      frac = j.done / j.total
      detail = string.format(L("%d de %d itens"), j.done, j.total)
    end
  elseif j.phase == "analyze" then
    label = L("Analisando estrutura do port")
    detail = L("Evitando pastas duplicadas e locais incorretos")
  elseif j.phase == "install" then
    label = (jopts.mode == "extract" and L("Movendo para ") or L("Instalando em ")) .. (jopts.dest_dir or C.PORTS_DIR)
    if j.total and j.total > 0 then frac = j.done / j.total end
  end
  G.text(T.f.bodyb, label, x + 24, by, T.c.text)
  if frac then
    local pct = string.format("%d%%", math.floor(U.clamp(frac, 0, 1) * 100))
    G.text(T.f.pix16, pct, x + w - 24 - T.f.pix16:getWidth(pct), by, T.c.yellow)
    G.progress(x + 24, by + 24, w - 48, 18, frac, j.phase == "download" and T.c.accent2 or T.c.green)
  else
    G.progress_busy(x + 24, by + 24, w - 48, 18, app.t, T.c.accent)
  end
  G.text(T.f.small, detail, x + 24, by + 50, T.c.dim)

  -- rodape
  local hint = j.cancelling and L("Cancelando...") or L("Não desligue o console durante a instalação.")
  G.text(T.f.small, hint, x + 24, y + h - 30, j.cancelling and T.c.yellow or T.c.faint)
  if not j.cancelling then
    local bx = x + w - 24
    if j.phase ~= "install" then
      local lw = T.f.small:getWidth("Cancelar")
      bx = bx - lw - 22
      G.button_icon("b", bx, y + h - 32)
      G.text(T.f.small, L("Cancelar"), bx + 22, y + h - 30, T.c.dim)
    end
    local lw2 = T.f.small:getWidth("Segundo plano")
    bx = bx - lw2 - 36
    G.button_icon("y", bx, y + h - 32)
    G.text(T.f.small, L("Segundo plano"), bx + 22, y + h - 30, T.c.dim)
  end

  -- confirmacao de sobrescrita (vinda da thread)
  if j.confirm then
    local names = {}
    for i, n in ipairs(j.confirm) do
      if i > 4 then names[#names + 1] = string.format(L("… e mais %d"), #j.confirm - 4); break end
      names[#names + 1] = "• " .. n
    end
    O._confirm = O._confirm or { sel = 2 }
    O._confirm_job = j
    local d = {
      title = L("Port já instalado"),
      kind = "warn",
      body = L("Estes itens já existem em ") .. ((j.opts and j.opts.dest_dir) or C.PORTS_DIR) .. ":\n" .. table.concat(names, "\n")
        .. ((j.opts and j.opts.mode == "extract")
          and L("\n\nDeseja substituir? Arquivos com o mesmo nome serão sobrescritos; os demais arquivos dessas pastas serão mantidos.")
          or L("\n\nDeseja substituir? Os arquivos do port serão atualizados e os arquivos extras que você adicionou (saves, dados do jogo) serão mantidos.")),
      buttons = { { label = L("SUBSTITUIR"), danger = true }, { label = L("CANCELAR") } },
      sel = O._confirm.sel,
    }
    O.draw_dialog(app, d)
  elseif j.ask_cancel then
    O.draw_dialog(app, {
      title = L("Cancelar instalação?"),
      kind = "warn",
      body = L("O download será interrompido e os arquivos temporários serão apagados."),
      buttons = { { label = L("SIM, CANCELAR"), danger = true }, { label = L("CONTINUAR") } },
      sel = j.ask_cancel_sel or 2,
    })
  end
end

function O.install_action(app, act)
  local j = Installer.job
  if not j or j.finished then return end
  if j.confirm then
    O._confirm = O._confirm or { sel = 2 }
    if act == "left" then O._confirm.sel = 1
    elseif act == "right" then O._confirm.sel = 2
    elseif act == "a" then
      local yes = O._confirm.sel == 1
      O._confirm = nil
      Installer.answer(yes)
    elseif act == "b" then
      O._confirm = nil
      Installer.answer(false)
    end
    return
  end
  if j.ask_cancel then
    if act == "left" then j.ask_cancel_sel = 1
    elseif act == "right" then j.ask_cancel_sel = 2
    elseif act == "a" then
      if (j.ask_cancel_sel or 2) == 1 then Installer.cancel() end
      j.ask_cancel = nil
    elseif act == "b" then
      j.ask_cancel = nil
    end
    return
  end
  if act == "b" and not j.cancelling and j.phase ~= "install" then
    j.ask_cancel = true
    j.ask_cancel_sel = 2
  elseif act == "y" and not j.cancelling then
    -- continua baixando enquanto o usuario navega; progresso na Central de Downloads
    j.background = true
    Downloads.background = true
    app.toast(L("Download em segundo plano. Pressione START para acompanhar."), "info")
  end
end

--- Gerenciador de arquivos > Extrair aqui: depois da extracao, pergunta se o
--- arquivo compactado deve ser excluido (nada e apagado sem a resposta).
local function ask_delete_archive(app, path, name, extracted_body)
  local function refresh()
    app.update_free_space()
    local cur = app.current()
    if cur and cur.name == "files" and cur.load then cur:load(true) end
  end
  app.show_dialog({
    title = L("Arquivo extraído!"), kind = "ok",
    body = (extracted_body or (name .. L(" foi extraído."))) .. "\n\n" .. L("Deseja excluir o arquivo compactado?"),
    buttons = {
      { label = L("EXCLUIR"), danger = true, fn = function()
        local ok = os.remove(path)
        app.toast(ok and (name .. L(" excluído.")) or L("Não foi possível excluir o arquivo compactado."), ok and "ok" or "error")
        refresh()
      end },
      { label = L("MANTER"), fn = function() app.toast(L("Arquivo compactado mantido."), "info") end },
    },
    sel = 2,
  })
end

function O.on_install_finished(app, j)
  O._confirm = nil
  pcall(function() require("core.compat").invalidate() end)
  local p = j.port
  app.update_free_space()
  app.on_catalog_changed()
  local jo0 = j.opts or {}
  if j.background and j.result == "done" and jo0.ask_delete and jo0.local_file then
    -- extracao em segundo plano: a pergunta aparece assim que nao houver outra janela
    if not app.dialog then
      ask_delete_archive(app, jo0.local_file, p.name, p.name .. L(" foi extraído em:\n") .. (jo0.dest_dir or ""))
    else
      app.toast(p.name .. L(" extraído. O arquivo compactado foi mantido."), "ok")
    end
    Installer.clear()
    return
  end
  if j.background then
    -- em segundo plano: aviso rapido (os detalhes ficam na Central de Downloads)
    -- Configuracoes > Downloads > Avisos de downloads em segundo plano
    if require("core.prefs").get("notif_downloads") == "0" then
      Installer.clear()
      return
    end
    if j.result == "done" then
      app.toast(p.name .. (require("config").OS_MODE and L(" instalado. Ele já está em Meus Ports.")
        or L(" instalado. Reinicie a lista de Ports para ver o jogo.")), "ok")
    elseif j.result == "error" then
      app.toast(L("Falha ao instalar ") .. p.name .. L(". Veja a Central de Downloads."), "error")
    else
      app.toast(L("Download de ") .. p.name .. L(" cancelado."), "warn")
    end
    Installer.clear()
    return
  end
  local jo = j.opts or {}
  local del_txt = ""
  if jo.local_file and jo.delete_source then
    del_txt = j.deleted and L("\nO arquivo compactado foi excluído.") or L("\nNão foi possível excluir o arquivo compactado.")
  end
  if j.result == "done" and jo.mode == "extract" then
    local shown = {}
    for i, n in ipairs(j.entries or {}) do
      if i > 4 then shown[#shown + 1] = string.format(L("… e mais %d"), #j.entries - 4); break end
      shown[#shown + 1] = "• " .. n
    end
    local body = p.name .. L(" foi extraído em:\n") .. (jo.dest_dir or "") .. "\n" .. table.concat(shown, "\n")
    if jo.ask_delete and jo.local_file then
      ask_delete_archive(app, jo.local_file, p.name, body)
    else
      app.show_dialog({ title = L("Arquivo extraído!"), kind = "ok", body = body .. "\n" .. del_txt })
    end
    Installer.clear()
    return
  end
  if j.result == "done" then
    local body = p.name .. L(" foi instalado em ") .. C.PORTS_DIR .. "." .. del_txt .. "\n\n"
      .. (j.es_cover and L("Reinicie o EmulationStation para o jogo aparecer na lista de Ports com a capa.")
        or L("Reinicie o EmulationStation para o jogo aparecer na lista de Ports."))
    if p.requires_files then
      body = body .. L("\n\nAtenção: este port precisa dos arquivos do jogo original. Consulte as instruções do port.")
    end
    app.show_dialog({
      title = L("Port instalado!"),
      kind = "ok",
      body = body,
      buttons = {
        { label = "OK" },
        { label = L("REINICIAR LISTA"), fn = function()
          app.show_dialog({
            title = L("Reiniciar EmulationStation?"),
            kind = "info",
            body = L("O R36S PORT HUB será fechado e o EmulationStation será reiniciado para atualizar a lista de Ports."),
            buttons = { { label = L("REINICIAR"), fn = app.request_es_restart }, { label = "VOLTAR" } },
          })
        end },
      },
    })
  elseif j.result == "error" then
    app.show_dialog({
      title = L("Falha na instalação"),
      kind = "error",
      body = (j.error or L("Erro desconhecido.")) .. (jo.local_file
        and L("\n\nNada foi alterado e o arquivo compactado foi mantido.") or L("\n\nNenhum arquivo do port foi alterado.")),
      buttons = {
        { label = "OK" },
        { label = L("TENTAR DE NOVO"), fn = function() app.install(p, j.opts) end },
      },
    })
    if j.error_code == "install_failed" then
      app.dialog.body = j.error .. L("\n\nA cópia foi interrompida; reinstale o port para corrigir.")
    end
  elseif j.result == "cancelled" then
    app.toast(jo.local_file and L("Extração cancelada. O arquivo compactado foi mantido.")
      or L("Instalação cancelada. Arquivos temporários removidos."), "warn")
  end
  Installer.clear()
end

---------------------------------------------------------------------------
-- Atualizacao dos runtimes do PortMaster
---------------------------------------------------------------------------
local RT_STEPS = { L("Verificação"), L("Download"), L("Validação"), L("Instalação") }
local RT_PHASE = { check = 1, download = 2, validate = 3, extract = 3, install = 4 }

function O.draw_runtimes(app, j)
  if j.finished then return end
  dim_screen(0.7)
  local w, h = 540, 268
  local x, y = (T.W - w) / 2, (T.H - h) / 2 - 10
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.accent2, lw = 2, r = 10 })
  G.rect(x, y, w, 6, T.c.accent2, 3)
  G.text(T.f.pix16, L("RUNTIMES"), x + 24, y + 22, T.c.accent2)
  G.text_fit(T.f.h2, L("PortMaster ") .. C.RUNTIMES_ARCH, x + 24, y + 44, w - 48, T.c.text)

  local cur = RT_PHASE[j.phase] or 1
  local sw = (w - 48) / #RT_STEPS
  for i, label in ipairs(RT_STEPS) do
    local sx, sy = x + 24 + (i - 1) * sw, y + 84
    local c = i < cur and T.c.green or (i == cur and T.c.yellow or T.c.faint)
    G.rect(sx, sy, sw - 8, 34, T.c.bg2, 6)
    if i == cur then G.frame(sx, sy, sw - 8, 34, c, 6, 1, App.pulse(0.6, 0.4, 6)) end
    if i < cur then check_mark(sx + 10, sy + 11, c) else G.text(T.f.pix8, tostring(i), sx + 12, sy + 13, c) end
    G.text(T.f.bodyb, label, sx + 30, sy + 8, i <= cur and T.c.text or T.c.faint)
  end

  local by = y + 140
  local label, detail, frac = j.label or "", "", nil
  if j.phase == "check" then
    if label == "" then label = L("Verificando") end
    if j.total and j.total > 0 then
      frac = j.done / j.total
      detail = string.format(L("%d de %d runtimes conferidos"), j.done, j.total)
    else
      detail = j.libs and (L("Destino: ") .. j.libs) or L("Conferindo internet, PortMaster e espaço livre")
    end
  elseif j.phase == "download" then
    label = L("Baixando ") .. C.RUNTIMES_ZIP_NAME
    if j.total and j.total > 0 then
      frac = j.done / j.total
      detail = string.format(L("%s de %s"), U.format_bytes(j.done), U.format_bytes(j.total))
    else
      detail = U.format_bytes(j.done) .. L(" recebidos")
    end
    if j.speed and j.speed > 0 then
      detail = detail .. "  •  " .. U.format_speed(j.speed)
      if j.eta then detail = detail .. L("  •  faltam ") .. U.format_time(j.eta) end
    end
  elseif j.phase == "validate" then
    label, detail = L("Verificando o pacote"), L("Tamanho, assinatura ZIP e estrutura interna")
  elseif j.phase == "extract" then
    label = L("Validando runtimes (md5)")
    if j.total and j.total > 0 then frac = j.done / j.total end
    detail = j.label or ""
  elseif j.phase == "install" then
    label = L("Instalando em ") .. (j.libs or "libs")
    if j.total and j.total > 0 then frac = j.done / j.total end
    detail = L("Backup dos arquivos antigos e troca pelos novos")
  end
  G.text_fit(T.f.bodyb, label, x + 24, by, w - 110, T.c.text)
  if frac then
    local pct = string.format("%d%%", math.floor(U.clamp(frac, 0, 1) * 100))
    G.text(T.f.pix16, pct, x + w - 24 - T.f.pix16:getWidth(pct), by, T.c.yellow)
    G.progress(x + 24, by + 24, w - 48, 18, frac, j.phase == "download" and T.c.accent2 or T.c.green)
  else
    G.progress_busy(x + 24, by + 24, w - 48, 18, app.t, T.c.accent)
  end
  G.text_fit(T.f.small, detail, x + 24, by + 50, w - 48, T.c.dim)

  local hint = j.cancelling and L("Cancelando...") or L("Não desligue o console durante a atualização.")
  G.text(T.f.small, hint, x + 24, y + h - 30, j.cancelling and T.c.yellow or T.c.faint)
  if not j.cancelling and j.phase ~= "install" then
    local lw = T.f.small:getWidth("Cancelar")
    local bx = x + w - 24 - lw - 22
    G.button_icon("b", bx, y + h - 32)
    G.text(T.f.small, L("Cancelar"), bx + 22, y + h - 30, T.c.dim)
  end

  if j.confirm then
    local c = j.confirm
    local items = {}
    for i, n in ipairs(c.items or {}) do
      if i > 4 then items[#items + 1] = string.format(L("… e mais %d"), #c.items - 4); break end
      items[#items + 1] = n
    end
    O.draw_dialog(app, {
      title = L("Atualizar runtimes?"),
      kind = "warn",
      body = string.format(L("Novos: %d   •   Atualizações: %d   •   Já atualizados: %d\nDownload: %s   •   Destino: %s\n%s\n\nOs runtimes atuais só serão substituídos depois que os novos forem baixados e validados (md5). Se algo falhar, o backup é restaurado."),
        c.new, c.update, c.ok, U.format_bytes(c.download), c.libs or "", table.concat(items, "\n")),
      buttons = { { label = L("ATUALIZAR"), danger = true }, { label = L("CANCELAR") } },
      sel = j.confirm_sel or 2,
    })
  elseif j.ask_cancel then
    O.draw_dialog(app, {
      title = L("Cancelar atualização?"),
      kind = "warn",
      body = L("O download será interrompido e os arquivos temporários serão apagados. Os runtimes atuais não serão alterados."),
      buttons = { { label = L("SIM, CANCELAR"), danger = true }, { label = L("CONTINUAR") } },
      sel = j.ask_cancel_sel or 2,
    })
  end
end

function O.runtimes_action(app, act)
  local j = Runtimes.job
  if not j or j.finished then return end
  if j.confirm then
    if act == "left" then j.confirm_sel = 1
    elseif act == "right" then j.confirm_sel = 2
    elseif act == "a" then
      local yes = (j.confirm_sel or 2) == 1
      j.confirm_sel = nil
      Runtimes.answer(yes)
    elseif act == "b" then j.confirm_sel = nil; Runtimes.answer(false) end
    return
  end
  if j.ask_cancel then
    if act == "left" then j.ask_cancel_sel = 1
    elseif act == "right" then j.ask_cancel_sel = 2
    elseif act == "a" then
      if (j.ask_cancel_sel or 2) == 1 then Runtimes.cancel() end
      j.ask_cancel = nil
    elseif act == "b" then j.ask_cancel = nil end
    return
  end
  if act == "b" and not j.cancelling and j.phase ~= "install" then
    j.ask_cancel, j.ask_cancel_sel = true, 2
  end
end

function O.on_runtimes_finished(app, j)
  app.update_free_space()
  -- runtimes mudaram: a compatibilidade dos ports e refeita na proxima consulta
  pcall(function() require("core.compat").invalidate() end)
  -- estado dos runtimes para o Gerenciador do PortMaster (resultado real desta verificacao)
  pcall(function()
    local PMm = require("core.pmmanager")
    local s = j.summary or {}
    if j.result == "done" then
      PMm.set_runtimes_state((s.missing and #s.missing > 0) and "incomplete" or "ok",
        s.uptodate and string.format(L("%d runtimes conferidos (md5), todos atualizados"), s.total or 0)
        or string.format(L("Novos: %d, atualizados: %d, já estavam ok: %d"), s.new or 0, s.update or 0, s.ok or 0))
    elseif j.result == "cancelled" and j.asked and ((j.asked.new or 0) + (j.asked.update or 0)) > 0 then
      PMm.set_runtimes_state("incomplete", string.format(L("Faltando ou desatualizados: %d"), (j.asked.new or 0) + (j.asked.update or 0)))
    end
  end)
  if j.result == "done" then
    local s = j.summary or {}
    if s.uptodate then
      app.show_dialog({ title = L("Runtimes atualizados"), kind = "ok",
        body = string.format(L("Todos os %d runtimes já estão na versão mais recente.\nNenhum download foi necessário.\n\nPasta: %s"), s.total or 0, s.libs or "") })
    else
      local body = string.format(L("Atualização concluída!\nNovos: %d   •   Atualizados: %d   •   Já estavam ok: %d\n\nPasta: %s\nArquivos temporários removidos. Configurações e dados dos jogos foram preservados."),
        s.new or 0, s.update or 0, s.ok or 0, s.libs or "")
      if s.missing and #s.missing > 0 then
        body = body .. L("\n\nNão estavam no pacote: ") .. table.concat(s.missing, ", ")
      end
      app.show_dialog({ title = L("Runtimes atualizados!"), kind = "ok", body = body })
    end
  elseif j.result == "error" then
    app.show_dialog({
      title = L("Falha nos runtimes"), kind = "error",
      body = (j.error or L("Erro desconhecido.")) .. (j.error_code ~= "install_failed" and L("\n\nNenhum runtime instalado foi alterado.") or ""),
      buttons = { { label = "OK" }, { label = L("TENTAR DE NOVO"), fn = function() app.update_runtimes() end } },
    })
  elseif j.result == "cancelled" then
    app.toast(L("Atualização dos runtimes cancelada. Nada foi alterado."), "warn")
  end
  Runtimes.clear()
end

---------------------------------------------------------------------------
-- Exclusao de jogo em andamento
---------------------------------------------------------------------------
function O.draw_uninstall(app, j)
  if j.finished then return end
  dim_screen(0.7)
  local w, h = 440, 120
  local x, y = (T.W - w) / 2, (T.H - h) / 2
  G.panel(x, y, w, h, { bg = T.c.bg1, border = T.c.red, lw = 2, r = 10 })
  G.rect(x, y, w, 6, T.c.red, 3)
  G.text(T.f.pix16, L("DESINSTALANDO"), x + 24, y + 22, T.c.red)
  G.text_fit(T.f.bodyb, j.plan.port.name, x + 24, y + 46, w - 48, T.c.text)
  G.progress_busy(x + 24, y + 78, w - 48, 14, app.t, T.c.red)
end

return O
