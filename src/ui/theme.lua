-- =============================================================================
--  Identidade visual: loja gamer retro, tema escuro
-- =============================================================================
local T = {}

local function hex(h, a)
  h = h:gsub("#", "")
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end
T.hex = hex

T.c = {
  bg0 = hex("#0a0c16"),
  bg1 = hex("#11142a"),
  bg2 = hex("#191d3a"),
  bg3 = hex("#232852"),
  line = hex("#2c3263"),
  text = hex("#eef0ff"),
  dim = hex("#9aa0cc"),
  faint = hex("#5d638f"),
  accent = hex("#ff4f8b"),   -- rosa neon
  accent2 = hex("#38d6ff"),  -- ciano
  yellow = hex("#ffd447"),
  green = hex("#3ddc84"),
  red = hex("#ff5c6c"),
  orange = hex("#ff9f43"),
  black = hex("#000000"),
  shadow = hex("#000000", 0.45),
}

-- Cores dos botoes (estilo controle retro)
T.btn = {
  a = hex("#ff5c6c"), b = hex("#ffd447"), x = hex("#38d6ff"), y = hex("#3ddc84"),
  l1 = hex("#9aa0cc"), r1 = hex("#9aa0cc"), start = hex("#9aa0cc"), select = hex("#9aa0cc"),
  dpad = hex("#9aa0cc"),
}

T.W, T.H = 640, 480

-- Estilo do tema atual (fundo, cantos arredondados...). Ver core/themes.lua
T.style = { background = "retro", round = 1.0, glow = hex("#381f66"), scanlines = true }

--- "#rrggbb" ou "#rrggbbaa" -> {r,g,b,a}; nil se invalido
function T.parse_hex(s)
  if type(s) ~= "string" then return nil end
  local h = s:match("^#(%x+)$")
  if not h or (#h ~= 6 and #h ~= 8) then return nil end
  local a = #h == 8 and tonumber(h:sub(7, 8), 16) / 255 or 1
  return hex("#" .. h:sub(1, 6), a)
end

--- Aplica as cores de um tema TROCANDO OS VALORES DENTRO das tabelas ja
--- existentes: telas que guardaram uma cor (ex.: T.c.green) mudam juntas.
function T.apply_palette(colors, buttons, style)
  for k, v in pairs(colors or {}) do
    if T.c[k] then
      T.c[k][1], T.c[k][2], T.c[k][3], T.c[k][4] = v[1], v[2], v[3], v[4] or 1
    else
      T.c[k] = { v[1], v[2], v[3], v[4] or 1 }
    end
  end
  for k, v in pairs(buttons or {}) do
    if T.btn[k] then
      T.btn[k][1], T.btn[k][2], T.btn[k][3], T.btn[k][4] = v[1], v[2], v[3], v[4] or 1
    end
  end
  if style then T.style = style end
end

-- ---------------------------------------------------------------------------
-- Fontes e tamanho do texto (Configuracoes > Aparencia > Tamanho do texto)
-- So as fontes de texto mudam de tamanho. As pixeladas (logo, etiquetas, dicas
-- de botoes) ficam fixas: a Press Start 2P so fica nitida em multiplos de 8.
local PIX = "assets/fonts/PressStart2P-Regular.ttf"
local REG = "assets/fonts/ChakraPetch-Regular.ttf"
local BOLD = "assets/fonts/ChakraPetch-SemiBold.ttf"
local CYR = "assets/fonts/Inter-Regular-Cyrillic.otf"
local CYRB = "assets/fonts/Inter-SemiBold-Cyrillic.otf"

-- arquivo, tamanho padrao, arquivo do cirilico (Inter) e diferenca de tamanho do cirilico
local TEXT_FONTS = {
  small = { REG, 12, CYR, 0 }, body = { REG, 14, CYR, -1 }, bodyb = { BOLD, 14, CYRB, -1 },
  h3 = { BOLD, 16, CYRB, -1 }, h2 = { BOLD, 20, CYRB, -1 }, h1 = { BOLD, 26, CYRB, -1 },
}
T.BASE_SIZE = {}
for k, v in pairs(TEXT_FONTS) do T.BASE_SIZE[k] = v[2] end

--- niveis do tamanho do texto: px somados ao tamanho padrao de cada fonte
T.FONT_LEVELS = {
  { id = "small", delta = -1, label = "Pequeno" },
  { id = "normal", delta = 0, label = "Padrão" },
  { id = "large", delta = 2, label = "Grande" },
  { id = "xlarge", delta = 3, label = "Muito grande" },
}
-- (rotulos traduzidos ao desenhar; as chaves estao em i18n/en.lua e ru.lua)
T.font_level = "normal"

local CACHE = {}       -- "chave|tamanho" -> fonte
T.font_info = setmetatable({}, { __mode = "k" })   -- fonte -> { key=, size= }

local function hook_i18n(font)
  -- largura/quebra de linha sempre do texto no idioma atual (o mesmo que e desenhado)
  local I18N = require("lib.i18n")
  local mt = getmetatable(font)
  local idx = mt and mt.__index
  if type(idx) == "table" and not idx.__porthub_i18n then
    local gw, gwr = idx.getWidth, idx.getWrap
    idx.getWidth = function(self, text) return gw(self, I18N.tr(text)) end
    idx.getWrap = function(self, text, w) return gwr(self, I18N.tr(text), w) end
    idx.__porthub_i18n = true
  end
end

--- fonte de texto `key` no tamanho `size` (criada uma vez e guardada)
function T.text_font(key, size)
  local spec = TEXT_FONTS[key]
  if not spec then return T.f and T.f[key] end
  local ck = key .. "|" .. size
  if CACHE[ck] then return CACHE[ck] end
  local font = love.graphics.newFont(spec[1], size)
  font:setFilter("linear", "linear")
  local ok, f2 = pcall(love.graphics.newFont, spec[3], size + spec[4])
  if ok and f2 then f2:setFilter("linear", "linear"); font:setFallbacks(f2) end
  if key == "body" then font:setLineHeight(1.12) elseif key == "small" then font:setLineHeight(1.1) end
  hook_i18n(font)
  CACHE[ck] = font
  T.font_info[font] = { key = key, size = size }
  return font
end

local function level_delta(id)
  for _, l in ipairs(T.FONT_LEVELS) do if l.id == id then return l.delta end end
  return 0
end

function T.valid_font_level(id)
  for _, l in ipairs(T.FONT_LEVELS) do if l.id == id then return true end end
  return false
end

--- Troca o tamanho do texto. As fontes sao trocadas DENTRO de T.f, entao toda
--- tela que usa T.f.body etc. ja desenha com o tamanho novo.
function T.set_font_level(id)
  if not T.valid_font_level(id) then id = "normal" end
  T.font_level = id
  local d = level_delta(id)
  for k, spec in pairs(TEXT_FONTS) do T.f[k] = T.text_font(k, spec[2] + d) end
end

--- Fontes menores da mesma familia para quando o texto nao cabe: do tamanho
--- atual ate o tamanho padrao (no tamanho padrao ou menor, so a propria fonte).
--- Assim o ajuste nunca muda o visual de quem usa o tamanho padrao.
function T.shrink_chain(font)
  local info = T.font_info[font]
  if not info then return { font } end
  local base = T.BASE_SIZE[info.key]
  local out = { font }
  for size = info.size - 1, base, -1 do out[#out + 1] = T.text_font(info.key, size) end
  return out
end

--- a mesma fonte no tamanho padrao (ou ela mesma se nao for de texto)
function T.base_font(font)
  local info = T.font_info[font]
  if not info or info.size <= T.BASE_SIZE[info.key] then return font end
  return T.text_font(info.key, T.BASE_SIZE[info.key])
end

--- Desenha `fn` com as fontes de texto no tamanho padrao (telas e paineis de
--- posicoes fixas, cheios de informacao, onde texto maior se sobreporia).
function T.with_base_fonts(fn, ...)
  if T.font_level == "normal" then return fn(...) end
  local saved = {}
  for k in pairs(TEXT_FONTS) do saved[k] = T.f[k]; T.f[k] = T.text_font(k, T.BASE_SIZE[k]) end
  local ok, err = xpcall(fn, debug.traceback, ...)
  for k, f in pairs(saved) do T.f[k] = f end
  if not ok then error(err, 0) end
end

function T.load()
  local function f(path, size)
    local font = love.graphics.newFont(path, size)
    font:setFilter("nearest", "nearest")
    return font
  end
  T.f = {
    pix8 = f(PIX, 8),
    pix16 = f(PIX, 16),
    pix24 = f(PIX, 24),
  }
  hook_i18n(T.f.pix8)
  local lvl = require("core.prefs").get("font_size")
  T.set_font_level(T.valid_font_level(lvl) and lvl or "normal")
end

return T
