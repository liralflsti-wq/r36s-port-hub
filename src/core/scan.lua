-- =============================================================================
--  Varredura da pasta de ports do console (/roms/ports)
--  Reconhece ports instalados por QUALQUER meio (hub, PortMaster, KMP, copia
--  manual) usando, numa unica chamada ao shell:
--    1) scripts .sh da raiz (e a linha GAMEDIR= de cada script)
--    2) port.json do PortMaster dentro de cada pasta (nome do zip, titulo, itens)
--    3) arquivos .port (metadados de instalacao, ate 2 niveis)
--    4) gamelist.xml do EmulationStation (nome exibido -> script)
--  O nome da pasta sozinho NUNCA identifica um jogo: e preciso o script .sh.
-- =============================================================================
local C = require("config")
local U = require("lib.util")

local S = {
  entries = {},     -- nome exato -> "file" | "dir"
  scripts = {},     -- chave normalizada -> nome do .sh
  dirs = {},        -- chave normalizada -> nome da pasta
  meta = {},        -- chave normalizada (zip/titulo/nome) -> { itens }
  versions = {},    -- chave normalizada -> versao informada nos metadados
  ports = {},       -- lista de ports encontrados no cartao (um por script .sh)
  by_script = {},   -- nome do .sh -> port encontrado
  count = 0,
  time = -1,
}

-- scripts da raiz que nao sao jogos
local NOT_GAMES = { ["portmaster.sh"] = true, ["r36s port hub.sh"] = true }

--- Normaliza nomes para comparar: sem acentos, minusculo, so letras e numeros
function S.key(s)
  s = U.slug(s or "")
  s = s:gsub("%.zip$", ""):gsub("%.rar$", ""):gsub("%.7z$", ""):gsub("%.sh$", ""):gsub("%.port$", "")
  s = s:gsub("[^%w]", "")
  return s
end

local function add_meta(k, items, version)
  k = S.key(k)
  if k == "" then return end
  S.meta[k] = S.meta[k] or {}
  for _, it in ipairs(items) do S.meta[k][#S.meta[k] + 1] = it end
  if version and version ~= "" then S.versions[k] = version end
end

-- por script: informacoes reunidas
local info = {}
local function script_info(sh)
  info[sh] = info[sh] or { items = {} }
  return info[sh]
end

local function json_str(text, field)
  return text:match('"' .. field .. '"%s*:%s*"([^"]*)"')
end

local function parse_port_json(dir, text)
  -- leitura tolerante (sem depender de JSON perfeito)
  local items = {}
  local block = text:match('"items"%s*:%s*(%b[])')
  if block then
    for it in block:gmatch('"([^"]+)"') do items[#items + 1] = it end
  end
  if #items == 0 then items = { dir } end
  local zip = json_str(text, "name")
  local title = json_str(text, "title")
  local shot = text:match('"screenshot"%s*:%s*"([^"]+)"')
  local cover = text:match('"covers"%s*:%s*%[%s*"([^"]+)"')
  if zip then add_meta(zip, items) end
  if title then add_meta(title, items) end
  for _, it in ipairs(items) do
    if it:lower():match("%.sh$") then
      local si = script_info(it)
      si.title = si.title or title
      si.zip = si.zip or zip
      si.source = "PortMaster"
      si.dir = si.dir or dir
      si.items = items
      local img = cover or shot
      if img and not img:find("%.%.") then si.cover = si.cover or (dir .. "/" .. img) end
    end
  end
end

--- arquivos .port: JSON ou linhas chave=valor (name/title/zip/version/items/script)
local function parse_dot_port(path, text)
  local base = path:gsub("^%./", "")
  local dir = base:match("^(.-)/[^/]+$")
  local name = (base:match("([^/]+)%.port$") or "")
  local function field(k)
    return json_str(text, k) or text:match("%f[%w]" .. k .. "%s*=%s*([^\r\n;]+)")
  end
  local title = field("title") or field("name") or name
  local zip = field("zip") or field("package")
  local version = field("version")
  local script = field("script") or field("launcher")
  local items = {}
  local block = text:match('"items"%s*:%s*(%b[])')
  if block then for it in block:gmatch('"([^"]+)"') do items[#items + 1] = it end end
  if script then items[#items + 1] = U.trim(script) end
  if dir then items[#items + 1] = dir end
  if #items == 0 then items[1] = name .. ".sh" end
  add_meta(title, items, version)
  add_meta(name, items, version)
  if zip then add_meta(zip, items, version) end
  for _, it in ipairs(items) do
    if it:lower():match("%.sh$") then
      local si = script_info(it)
      si.title = si.title or title
      si.version = si.version or version
      si.source = si.source or "arquivo .port"
      si.port_items = items      -- itens declarados no .port (evidencia para exclusao)
    end
  end
end

local function xml_unescape(s)
  return (s:gsub("&amp;", "&"):gsub("&apos;", "'"):gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"))
end

local function parse_gamelist(text)
  for game in text:gmatch("<game[%s>].-</game>") do
    local path = game:match("<path>%s*(.-)%s*</path>")
    local name = game:match("<name>%s*(.-)%s*</name>")
    if path and name then
      local file = path:gsub("^%./", "")
      if not file:find("/") then
        name = xml_unescape(name)
        add_meta(name, { file })
        local si = script_info(file)
        si.es_name = name
      end
    end
  end
end

--- Reexamina a pasta (force=false respeita um intervalo minimo de 3 s)
function S.refresh(force)
  local now = love and love.timer and love.timer.getTime() or os.time()
  if not force and S.time >= 0 and now - S.time < 3 then return end
  local dir = C.PORTS_DIR
  local cmd = "cd " .. U.shq(dir) .. " 2>/dev/null && { "
    .. "for f in * .[!.]*; do [ -e \"$f\" ] || continue; "
    .. "if [ -d \"$f\" ]; then echo \"D:$f\"; else echo \"F:$f\"; "
    .. "case \"$f\" in *.sh|*.SH) g=$(head -c 6000 \"$f\" 2>/dev/null | grep -m1 -E '^[[:space:]]*(export[[:space:]]+)?GAMEDIR=' | tr -d '\\r'); "
    .. "[ -n \"$g\" ] && echo \"S:$f|$g\"; "
    -- outras formas de o script apontar a pasta (gamedir=, PORTDIR=, cd /roms/ports/...)
    .. "r=$(head -c 8000 \"$f\" 2>/dev/null | grep -m1 -E '(gamedir|GAME_DIR|PORTDIR|PORT_DIR|portdir)=|cd[[:space:]].*ports/' | tr -d '\\r'); "
    .. "[ -n \"$r\" ] && echo \"R:$f|$r\";; esac; fi; done; "
    .. "for j in */port.json; do [ -f \"$j\" ] || continue; echo \"J:$j\"; head -c 8192 \"$j\" | tr '\\n\\r' '  '; echo; done; "
    .. "for p in *.port */*.port; do [ -f \"$p\" ] || continue; echo \"P:$p\"; head -c 4096 \"$p\" | tr '\\n\\r' ';;'; echo; done; "
    .. "if [ -f gamelist.xml ]; then echo 'G:'; head -c 400000 gamelist.xml | tr '\\n\\r' '  '; echo; fi; }"
  local out = U.capture(cmd) or ""

  S.entries, S.scripts, S.dirs, S.meta, S.versions, S.count, S.ports = {}, {}, {}, {}, {}, 0, {}
  S.by_script = {}
  info = {}
  local mode, arg = nil, nil
  local gamedirs, refdirs = {}, {}
  for line in out:gmatch("[^\n]+") do
    if mode == "json" then parse_port_json(arg, line); mode = nil
    elseif mode == "port" then parse_dot_port(arg, line); mode = nil
    elseif mode == "gamelist" then parse_gamelist(line); mode = nil
    else
      local kind, rest = line:match("^([DFJPGSR]):(.*)$")
      if kind == "D" then
        S.entries[rest] = "dir"
        local k = S.key(rest)
        S.dirs[k] = S.dirs[k] or rest
      elseif kind == "F" then
        S.entries[rest] = "file"
        if rest:lower():match("%.sh$") then
          local k = S.key(rest)
          S.scripts[k] = S.scripts[k] or rest
        end
      elseif kind == "S" then
        local f, g = rest:match("^(.-)|(.*)$")
        if f and g then
          -- GAMEDIR="/$directory/ports/jogo" ou GAMEDIR=/roms/ports/jogo/
          local d = g:match("ports/([^\"'/%s%$]+)")
          if d then gamedirs[f] = d end
        end
      elseif kind == "R" then
        local f, g = rest:match("^(.-)|(.*)$")
        local d = g and g:match("ports/([^\"'/%s%$]+)")
        if f and d then refdirs[f] = d end
      elseif kind == "J" then mode, arg = "json", rest:match("^(.-)/port%.json$")
      elseif kind == "P" then mode, arg = "port", rest
      elseif kind == "G" then mode = "gamelist"
      end
    end
  end

  -- monta a lista de ports do cartao (um por script .sh)
  for name, kind in pairs(S.entries) do
    if kind == "file" and name:lower():match("%.sh$") and not NOT_GAMES[name:lower()] then
      local si = info[name] or { items = {} }
      local p = {
        script = name,
        title = si.title or si.es_name or name:gsub("%.[sS][hH]$", ""),
        zip = si.zip,
        version = si.version,
        source = si.source or (si.es_name and "EmulationStation" or "script .sh"),
      }
      -- pasta de dados: port.json > GAMEDIR do script > mesmo nome do script
      local d = si.dir or gamedirs[name]
      if d and S.entries[d] ~= "dir" then d = nil end
      if not d then
        local k = S.key(name)
        d = S.dirs[k]
      end
      p.dir = d
      -- evidencias de quais arquivos pertencem ao port (usadas pela exclusao segura)
      p.pm_items = (si.source == "PortMaster" and si.items and #si.items > 0) and si.items or nil
      p.port_items = si.port_items
      p.gamedir = gamedirs[name]           -- pasta declarada no GAMEDIR= (pode nao existir)
      p.refdir = refdirs[name]             -- pasta citada no script de outra forma (cd, gamedir=...)
      if si.dir and S.entries[si.dir] == "dir" then p.dir_source = "port.json"
      elseif gamedirs[name] and S.entries[gamedirs[name]] == "dir" then p.dir_source = "GAMEDIR"
      elseif d then p.dir_source = "nome" end
      p.items = { name }
      if d then p.items[2] = d end
      if si.cover and S.entries[(si.cover:match("^([^/]+)/"))] == "dir" then
        p.cover = dir .. "/" .. si.cover
      end
      S.ports[#S.ports + 1] = p
      S.by_script[name] = p
      S.count = S.count + 1
      -- o titulo e o nome do zip do PortMaster tambem servem de chave
      add_meta(p.title, p.items, p.version)
      if p.zip then add_meta(p.zip, p.items, p.version) end
      add_meta(name, p.items, p.version)
    end
  end
  table.sort(S.ports, function(a, b) return a.title:lower() < b.title:lower() end)
  S.time = now
  U.log(string.format("varredura de %s: %d ports (.sh) encontrados", dir, S.count))
end

function S.exists(name) return S.entries[name] ~= nil end

--- Procura um port do catalogo no console.
--- Devolve (lista de itens encontrados, versao instalada se conhecida) ou nil
function S.find(p)
  -- 1) lista explicita do catalogo (nome exato)
  if p.install_check and #p.install_check > 0 then
    local found = {}
    for _, n in ipairs(p.install_check) do
      if S.exists(n) then found[#found + 1] = n end
    end
    return #found > 0 and found or nil
  end

  local keys = {}
  local function addk(v)
    local k = S.key(v)
    if k ~= "" then keys[#keys + 1] = k end
  end
  addk(p.pm_name)          -- nome do pacote no PortMaster (ex.: "sprout.zip")
  addk(p.id)
  addk(p.name)
  local file = (p.download_url or ""):match("([^/%?]+)%.[zZ][iI][pP]")
    or (p.download_url or ""):match("([^/%?]+)%.[rR][aA][rR]")
    or (p.download_url or ""):match("([^/%?]+)%.7[zZ]")
  if file then
    addk((file:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)))
  end

  -- 2) metadados (PortMaster, .port, EmulationStation, titulo do script)
  for _, k in ipairs(keys) do
    local m = S.meta[k]
    if m then
      local found, seen, has_script = {}, {}, false
      for _, it in ipairs(m) do
        if S.exists(it) and not seen[it] then
          seen[it] = true
          found[#found + 1] = it
          if it:lower():match("%.sh$") then has_script = true end
        end
      end
      -- exige um script .sh existente: pasta sozinha nao identifica o jogo
      if has_script then return found, S.versions[k] end
    end
  end
  -- 3) script .sh com o mesmo nome
  for _, k in ipairs(keys) do
    local sh = S.scripts[k]
    if sh then
      local found = { sh }
      if S.dirs[k] then found[2] = S.dirs[k] end
      return found, S.versions[k]
    end
  end
  return nil
end

return S
