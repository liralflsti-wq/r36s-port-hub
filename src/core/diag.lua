-- =============================================================================
--  Diagnostico do aplicativo (Configuracoes > Diagnostico e suporte)
--  Verificacoes rapidas e somente leitura do proprio hub: catalogo, downloads,
--  ports instalados, FTP, atualizacoes, ferramentas e registros. Nada e
--  corrigido sozinho; o resultado pode ser exportado para o suporte.
-- =============================================================================
local L = require("lib.i18n").L
local I18N = require("lib.i18n")
local U = require("lib.util")
local C = require("config")

local D = {}

local function has(cmd) return U.exec_ok("command -v " .. cmd .. " >/dev/null 2>&1") end

--- registros do hub cujos arquivos sumiram em parte (instalacao incompleta)
function D.incomplete_ports()
  local Manifest = require("core.manifest")
  local Scan = require("core.scan")
  local out = {}
  for id, rec in pairs(Manifest.data or {}) do
    if type(rec) == "table" and type(rec.entries) == "table" and #rec.entries > 0 then
      local missing = {}
      for _, e in ipairs(rec.entries) do if not Scan.exists(e) then missing[#missing + 1] = e end end
      if #missing > 0 and #missing < #rec.entries then
        out[#out + 1] = { id = id, name = rec.name or id, missing = missing }
      end
    end
  end
  table.sort(out, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
  return out
end

--- executa as verificacoes. Devolve lista { area=, state="ok|warn|error", text= }
function D.run()
  local r = {}
  local function add(area, state, text) r[#r + 1] = { area = area, state = state, text = text } end

  -- aplicativo
  add(L("Aplicativo"), "ok", C.VERSION .. "  •  " .. L("idioma ") .. I18N.lang
    .. (App.free and ("  •  " .. U.format_bytes(App.free) .. L(" livres")) or ""))
  if App.free and App.free < 200 * 1024 * 1024 then
    add(L("Espaço livre"), "warn", L("Menos de 200 MB livres no cartão: downloads e atualizações podem falhar."))
  end

  -- rede
  local st = require("core.net").current()
  if st and st.connected then add(L("Rede"), "ok", L("Conectado") .. (st.ip and ("  •  " .. st.ip) or ""))
  else add(L("Rede"), "warn", L("Sem conexão de rede: catálogo online, downloads e atualizações via rede não funcionam.")) end

  -- catalogo
  local Catalog = require("core.catalog")
  local url = Catalog.get_remote_url()
  local last = tonumber(require("core.prefs").get("cat_last") or "")
  local ct = string.format(L("%s  •  %d ports  •  %d categorias"), Catalog.source_label(), #Catalog.ports, #Catalog.categories)
  if last then ct = ct .. "  •  " .. L("última atualização online: ") .. require("core.clock").datetime(last, true) end
  if not url then add(L("Catálogo"), "warn", L("Nenhum endereço de catálogo online configurado. ") .. ct)
  elseif Catalog.source == "online" or Catalog.source == "cache" then add(L("Catálogo"), Catalog.source == "online" and "ok" or "warn", ct)
  else add(L("Catálogo"), "error", L("O catálogo online não foi carregado. ") .. ct) end

  -- downloads
  local Downloads = require("core.downloads")
  if not Downloads.loaded then Downloads.load() end
  local nerr, ndone = 0, 0
  for _, e in ipairs(Downloads.list) do
    if e.state == "error" then nerr = nerr + 1 elseif e.state == "done" then ndone = ndone + 1 end
  end
  add(L("Downloads"), nerr > 0 and "warn" or "ok", string.format(L("%d concluído(s)  •  %d com falha  •  %d na fila"),
    ndone, nerr, Downloads.waiting_count()) .. (Downloads.active() and ("  •  " .. L("1 em andamento")) or ""))

  -- ports instalados
  local Manifest = require("core.manifest")
  Manifest.rescan(false)
  local nrec = 0
  for _ in pairs(Manifest.data or {}) do nrec = nrec + 1 end
  local inc = D.incomplete_ports()
  local sc = require("core.scan").count or 0
  local pt = string.format(L("%d script(s) .sh na pasta de ports  •  %d instalado(s) pelo hub"), sc, nrec)
  if #inc > 0 then
    local names = {}
    for k = 1, math.min(3, #inc) do names[#names + 1] = inc[k].name end
    add(L("Ports instalados"), "warn", pt .. "  •  " .. string.format(L("%d incompleto(s): "), #inc) .. table.concat(names, ", "))
  else
    add(L("Ports instalados"), "ok", pt)
  end

  -- FTP
  local Ftp = require("core.ftp")
  if Ftp.state == "on" then add(L("Servidor FTP"), "ok", L("ATIVADO") .. "  •  " .. L("porta ") .. tostring(Ftp.cfg and Ftp.cfg.port or "?"))
  elseif Ftp.last_error then add(L("Servidor FTP"), "warn", L("Desativado. Último erro: ") .. I18N.tr(tostring(Ftp.last_error)))
  else add(L("Servidor FTP"), "ok", L("Desativado")) end

  -- atualizacoes
  local M = require("core.updater.manager")
  if M.restart_needed then
    add(L("Atualizações"), "warn", L("Uma atualização foi instalada: reinicie o app."))
  elseif not M.layout_ok() then
    add(L("Atualizações"), "error", L("A pasta do hub não está em ports/r36sporthub: atualizações bloqueadas."))
  else
    add(L("Atualizações"), "ok", L("Versão ") .. C.VERSION .. "  •  " .. M.formats_text())
  end

  -- ferramentas do sistema usadas pelo hub
  local miss = {}
  if not (has("curl") or has("wget")) then miss[#miss + 1] = "curl/wget" end
  if not has("unzip") and not (M.tools().zip) then miss[#miss + 1] = "unzip" end
  if #miss > 0 then add(L("Ferramentas do sistema"), "error", L("Faltando: ") .. table.concat(miss, ", "))
  else
    add(L("Ferramentas do sistema"), "ok", (has("curl") and "curl" or "wget") .. "  •  unzip"
      .. (has("ffmpeg") and "  •  ffmpeg" or "") .. (require("core.runtimes").detect_pm() and "  •  PortMaster" or ""))
  end

  -- registros
  local ne = require("core.errlog").count()
  local nn = require("core.netlog").count()
  add(L("Registros"), (ne > 0 or nn > 0) and "warn" or "ok",
    string.format(L("%d arquivo(s) de erro  •  %d falha(s) de comunicação registradas"), ne, nn))
  return r
end

--- texto do relatorio (para exportar)
function D.text(list)
  local t = {}
  local mark = { ok = "[OK]  ", warn = "[ATENÇÃO] ", error = "[ERRO] " }
  for _, e in ipairs(list or D.run()) do
    t[#t + 1] = (mark[e.state] or "") .. I18N.tr(e.area) .. ": " .. I18N.tr(e.text)
  end
  local nl = require("core.netlog").all()
  if #nl > 0 then
    t[#t + 1] = ""
    t[#t + 1] = "FALHAS DE COMUNICACAO (mais recentes):"
    for k = 1, math.min(10, #nl) do
      local e = nl[k]
      t[#t + 1] = os.date("%Y-%m-%d %H:%M", e.time) .. "  " .. I18N.tr(e.what) .. (e.host ~= "" and (" (" .. e.host .. ")") or "")
        .. (e.reason ~= "" and (": " .. I18N.tr(e.reason)) or "")
    end
  end
  return table.concat(t, "\n")
end

return D
