-- =============================================================================
--  Capa do R36S PORT HUB na lista de Ports do EmulationStation.
--
--  O EmulationStation mostra imagens a partir de /roms/ports/gamelist.xml.
--  Quem instala pelo PortMaster ja ganha a entrada (via gameinfo.xml); quem so
--  extrai o ZIP na pasta ports nao. Aqui o hub cuida SO da propria entrada:
--   * sem entrada: acrescenta uma, antes de </gameList>;
--   * com entrada: so completa as tags de imagem que faltam (nunca troca o que
--     o usuario ou um scraper ja colocou);
--   * nao mexe em nenhum outro jogo; copia de seguranca na 1a alteracao;
--     grava num arquivo temporario e troca de uma vez.
--  A imagem aparece depois que o EmulationStation recarrega a lista.
-- =============================================================================
local U = require("lib.util")
local C = require("config")

local E = {}

local SCRIPT = "R36S PORT HUB.sh"
local TAGS = {
  { "image", "./r36sporthub/cover.png" },
  { "thumbnail", "./r36sporthub/cover.png" },
  { "marquee", "./r36sporthub/logo.png" },
  { "fanart", "./r36sporthub/fanart.png" },
}

local DESC = "Central de ports e ferramentas para o R36S: instale jogos e utilitários, transfira arquivos por FTP, gerencie o Wi-Fi, personalize temas e verifique o console."
-- descricao antiga escrita pelo proprio hub (versoes anteriores): e trocada pela nova
local OLD_DESC = "Loja de ports para o R36S: baixe e instale jogos e utilitários, acompanhe downloads, use o servidor FTP e gerencie o Wi-Fi."

local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function entry(nl)
  local t = {
    "\t<game>",
    "\t\t<path>./" .. esc(SCRIPT) .. "</path>",
    "\t\t<name>R36S PORT HUB</name>",
    "\t\t<desc>" .. esc(DESC) .. "</desc>",
  }
  for _, tg in ipairs(TAGS) do t[#t + 1] = "\t\t<" .. tg[1] .. ">" .. tg[2] .. "</" .. tg[1] .. ">" end
  t[#t + 1] = "\t\t<developer>Comunidade R36S</developer>"
  t[#t + 1] = "\t\t<genre>Other</genre>"
  t[#t + 1] = "\t</game>"
  return table.concat(t, nl) .. nl
end

--- devolve "added" | "updated" | nil (nada a fazer) e uma mensagem de erro se falhar
function E.ensure()
  local dir = C.PORTS_DIR
  -- so faz sentido se as imagens estiverem mesmo no console
  if not U.file_size(C.APP_DIR .. "/cover.png") then return nil end
  local path = dir .. "/gamelist.xml"
  local text = U.read_file(path)
  local out, what
  if not text or not text:find("%S") then
    out = '<?xml version="1.0"?>\n<gameList>\n' .. entry("\n") .. "</gameList>\n"
    what = "added"
  else
    local nl = text:find("\r\n", 1, true) and "\r\n" or "\n"
    -- localiza o bloco <game> cujo <path> e o lancador do hub
    local s, e, block
    local pos = 1
    while true do
      local a, b = text:find("<game[%s>].-</game>", pos)
      if not a then break end
      local blk = text:sub(a, b)
      local p = blk:match("<path>%s*(.-)%s*</path>")
      if p and (p == "./" .. SCRIPT or p:sub(-#SCRIPT - 1) == "/" .. SCRIPT or p == SCRIPT) then
        s, e, block = a, b, blk
        break
      end
      pos = b + 1
    end
    if block then
      -- segue o recuo que o arquivo ja usa
      local child = block:match("\n([ \t]*)<") or "\t\t"
      local before = text:sub(1, s - 1)
      local gind = before:match("\n([ \t]*)$") or "\t"
      local add = {}
      for _, tg in ipairs(TAGS) do
        if not block:find("<" .. tg[1] .. "[%s>]") and not block:find("<" .. tg[1] .. "/>") then
          add[#add + 1] = child .. "<" .. tg[1] .. ">" .. tg[2] .. "</" .. tg[1] .. ">" .. nl
        end
      end
      local nblock = block
      local od = "<desc>" .. esc(OLD_DESC) .. "</desc>"
      local i = nblock:find(od, 1, true)
      if i then nblock = nblock:sub(1, i - 1) .. "<desc>" .. esc(DESC) .. "</desc>" .. nblock:sub(i + #od) end
      if #add == 0 and nblock == block then return nil end
      block = nblock
      local close = block:find("</game>%s*$")
      local indent_fix = block:sub(1, close - 1):gsub("[ \t]*$", "")
      local nb = indent_fix .. (indent_fix:sub(-1) == "\n" and "" or nl) .. table.concat(add) .. gind .. "</game>"
      out = text:sub(1, s - 1) .. nb .. text:sub(e + 1)
      what = #add > 0 and "updated" or "desc"
    else
      local a = nil
      local p0 = 1
      while true do   -- ultimo </gameList>
        local x = text:find("</gameList>", p0, true)
        if not x then break end
        a, p0 = x, x + 1
      end
      if not a then return nil, "gamelist.xml sem </gameList>" end
      out = text:sub(1, a - 1):gsub("[ \t]*$", "") .. entry(nl) .. text:sub(a)
      what = "added"
    end
    -- copia de seguranca (so uma vez)
    local bak = path .. ".porthub.bak"
    if not U.file_size(bak) then U.write_file(bak, text) end
  end
  local tmp = path .. ".porthub.tmp"
  if not U.write_file(tmp, out) then return nil, "sem permissão de escrita em " .. dir end
  local ok, err = os.rename(tmp, path)
  if not ok then os.remove(tmp); return nil, tostring(err) end
  return what
end

-- ===========================================================================
--  Capa dos ports instalados pelo hub na lista de Ports do EmulationStation
--  * a capa e a mesma do catalogo (a que aparece no hub); sem ela, usa a
--    cover.png/screenshot.png que o proprio port trouxer;
--  * a imagem fica dentro da pasta do port (ou em ports/images, se o port nao
--    tiver uma pasta so) com o nome <id>-cover.png/.jpg;
--  * sem entrada no gamelist.xml: cria uma (nome, descricao, capa, genero);
--    com entrada: so completa image/thumbnail que faltam, nunca troca o que o
--    usuario, o PortMaster ou um scraper colocaram;
--  * nao mexe em nenhum outro jogo; copia de seguranca na 1a alteracao.
--  O registro do que foi feito fica no installed.json, para a desinstalacao
--  desfazer so o que o hub criou.
-- ===========================================================================
local IMG_TAGS = { "image", "thumbnail" }

local function gamelist_path() return C.PORTS_DIR .. "/gamelist.xml" end

--- grava o gamelist.xml (copia de seguranca na 1a vez; troca atomica)
local function save_list(old_text, out)
  local path = gamelist_path()
  if old_text then
    local bak = path .. ".porthub.bak"
    if not U.file_size(bak) then U.write_file(bak, old_text) end
  end
  local tmp = path .. ".porthub.tmp"
  if not U.write_file(tmp, out) then return nil, "sem permissão de escrita em " .. C.PORTS_DIR end
  local ok, err = os.rename(tmp, path)
  if not ok then os.remove(tmp); return nil, tostring(err) end
  return true
end

--- bloco <game> cujo <path> e o script (devolve inicio, fim, bloco)
local function find_block(text, script)
  local pos = 1
  while true do
    local a, b = text:find("<game[%s>].-</game>", pos)
    if not a then return nil end
    local blk = text:sub(a, b)
    local p = blk:match("<path>%s*(.-)%s*</path>")
    if p then
      p = p:gsub("&amp;", "&")
      if p == "./" .. script or p == script or p:sub(-#script - 1) == "/" .. script then return a, b, blk end
    end
    pos = b + 1
  end
end

local function has_tag(block, tag)
  return block:find("<" .. tag .. "[%s>]") or block:find("<" .. tag .. "/>")
end

--- tipo real da imagem pelo conteudo
local function img_ext(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local h = f:read(8) or ""
  f:close()
  if h:sub(1, 8) == "\137PNG\r\n\26\n" then return "png" end
  if h:sub(1, 3) == "\255\216\255" then return "jpg" end
  return nil
end

local function copy_file(src, dst)
  local data = U.read_file(src)
  if not data or #data == 0 then return false end
  return U.write_file(dst, data) and true or false
end

--- acrescenta/completa a entrada de um port. Devolve info { mode, script, image } ou nil, erro
local function write_entry(p, script, rel_img)
  local path = gamelist_path()
  local text = U.read_file(path)
  local function tags_for(ind, nl)
    local t = {}
    for _, tg in ipairs(IMG_TAGS) do t[#t + 1] = ind .. "<" .. tg .. ">" .. esc(rel_img) .. "</" .. tg .. ">" .. nl end
    return t
  end
  local function new_entry(nl)
    local t = { "\t<game>", "\t\t<path>./" .. esc(script) .. "</path>", "\t\t<name>" .. esc(p.name or script) .. "</name>" }
    local desc = p.description and p.description ~= "" and p.description or p.short
    if desc and desc ~= "" then t[#t + 1] = "\t\t<desc>" .. esc(desc) .. "</desc>" end
    for _, tg in ipairs(IMG_TAGS) do t[#t + 1] = "\t\t<" .. tg .. ">" .. esc(rel_img) .. "</" .. tg .. ">" end
    if p.category and p.category ~= "" then t[#t + 1] = "\t\t<genre>" .. esc(p.category) .. "</genre>" end
    t[#t + 1] = "\t</game>"
    return table.concat(t, nl) .. nl
  end
  local out, mode
  if not text or not text:find("%S") then
    out = '<?xml version="1.0"?>\n<gameList>\n' .. new_entry("\n") .. "</gameList>\n"
    mode = "added"
  else
    local nl = text:find("\r\n", 1, true) and "\r\n" or "\n"
    local s, e, block = find_block(text, script)
    if block then
      local add_tags = {}
      for _, tg in ipairs(IMG_TAGS) do if not has_tag(block, tg) then add_tags[#add_tags + 1] = tg end end
      if #add_tags == 0 then return { mode = "kept", script = script } end
      local child = block:match("\n([ \t]*)<") or "\t\t"
      local gind = text:sub(1, s - 1):match("\n([ \t]*)$") or "\t"
      local close = block:find("</game>%s*$")
      local head = block:sub(1, close - 1):gsub("[ \t]*$", "")
      local ins = {}
      for _, tg in ipairs(add_tags) do ins[#ins + 1] = child .. "<" .. tg .. ">" .. esc(rel_img) .. "</" .. tg .. ">" .. nl end
      out = text:sub(1, s - 1) .. head .. (head:sub(-1) == "\n" and "" or nl) .. table.concat(ins) .. gind .. "</game>" .. text:sub(e + 1)
      mode = "updated"
    else
      local a, p0 = nil, 1
      while true do
        local x = text:find("</gameList>", p0, true)
        if not x then break end
        a, p0 = x, x + 1
      end
      if not a then return nil, "gamelist.xml sem </gameList>" end
      out = text:sub(1, a - 1):gsub("[ \t]*$", "") .. new_entry(nl) .. text:sub(a)
      mode = "added"
    end
  end
  local ok, err = save_list(text, out)
  if not ok then return nil, err end
  return { mode = mode, script = script, image = rel_img }
end

--- Coloca a capa de um port recem-instalado no gamelist.xml.
--- entries = itens instalados (nomes em /roms/ports). cover_file = capa do
--- catalogo ja baixada (caminho absoluto) ou nil. Devolve info ou nil, motivo.
function E.add_port(p, entries, cover_file)
  local dir = C.PORTS_DIR
  local scripts, folders = {}, {}
  for _, n in ipairs(entries or {}) do
    if n:lower():match("%.sh$") then scripts[#scripts + 1] = n
    elseif U.is_dir(dir .. "/" .. n) then folders[#folders + 1] = n end
  end
  if #scripts == 0 then return nil, "port sem script .sh" end
  local slug = U.slug(p.id or p.name or scripts[1])
  -- 1) capa do catalogo, copiada para junto do port
  local rel, abs_img
  local ext = cover_file and img_ext(cover_file)
  if ext then
    local sub = (#folders == 1) and folders[1] or "images"
    if sub == "images" then U.exec_ok("mkdir -p " .. U.shq(dir .. "/images")) end
    abs_img = dir .. "/" .. sub .. "/" .. slug .. "-cover." .. ext
    if not copy_file(cover_file, abs_img) then return nil, "não foi possível copiar a capa" end
    rel = "./" .. sub .. "/" .. slug .. "-cover." .. ext
  else
    -- 2) imagem que o proprio port trouxe
    for _, f in ipairs(folders) do
      for _, cand in ipairs({ "cover.png", "cover.jpg", "screenshot.png", "screenshot.jpg" }) do
        if not rel and img_ext(dir .. "/" .. f .. "/" .. cand) then rel = "./" .. f .. "/" .. cand end
      end
    end
  end
  if not rel then return nil, "sem capa" end
  local done = {}
  for _, sc in ipairs(scripts) do
    local info, err = write_entry(p, sc, rel)
    if not info then return nil, err end
    if info.mode ~= "kept" then done[#done + 1] = info end
  end
  return { entries = done, image_file = abs_img }
end

--- Desfaz o que add_port fez (na desinstalacao): remove a entrada criada pelo
--- hub ou so as tags de imagem que ele acrescentou. Nunca mexe em outras.
function E.remove_port(info)
  if type(info) ~= "table" then return nil end
  local path = gamelist_path()
  local text = U.read_file(path)
  local changed = false
  if text then
    for _, it in ipairs(info.entries or {}) do
      local s, e, block = find_block(text, it.script or "")
      if block then
        local nblock
        if it.mode == "added" then
          -- remove o bloco inteiro (e a quebra de linha que sobra)
          local before = text:sub(1, s - 1):gsub("[ \t]*$", "")
          local after = text:sub(e + 1):gsub("^\r?\n", "")
          text = before .. after
          changed = true
        elseif it.mode == "updated" and it.image then
          nblock = block
          for _, tg in ipairs(IMG_TAGS) do
            local pat = "\n[ \t]*<" .. tg .. ">" .. esc(it.image):gsub("%p", "%%%0") .. "</" .. tg .. ">"
            nblock = nblock:gsub(pat, "")
          end
          if nblock ~= block then
            text = text:sub(1, s - 1) .. nblock .. text:sub(e + 1)
            changed = true
          end
        end
      end
    end
    if changed then save_list(nil, text) end
  end
  if info.image_file and U.file_size(info.image_file) then os.remove(info.image_file) end
  return changed
end

return E
