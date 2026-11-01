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

return E
