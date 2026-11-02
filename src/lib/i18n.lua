-- =============================================================================
--  Traducao centralizada (pt-BR, en, ru)
--  O texto em portugues e a chave. Os dicionarios ficam em i18n/<idioma>.lua.
--    L("texto")  -> traducao no idioma atual (ou o proprio texto)
--    I.tr(s)     -> usado pelas funcoes de desenho: aceita texto ja traduzido
--                   em qualquer idioma (ou em MAIUSCULAS) e devolve no atual.
--  Nenhuma tela precisa saber qual idioma esta ativo.
-- =============================================================================
local utf8 = require("utf8")
local I = { lang = "pt-BR", dicts = {}, rev = {}, rev_up = {}, keys = {}, built = false }

I.LANGS = {
  { id = "pt-BR", name = "Português (Brasil)", short = "PORTUGUÊS (BRASIL)", label = "Português", flag = "br" },
  { id = "en", name = "English", short = "ENGLISH", label = "English", flag = "us" },
  { id = "ru", name = "Русский", short = "РУССКИЙ", label = "Русский", flag = "ru" },
}
local VALID = { ["pt-BR"] = true, en = true, ru = true }

local function load_dict(lang)
  if lang == "pt-BR" then return {} end
  if I.dicts[lang] == nil then
    local ok, d = pcall(require, "i18n." .. lang)
    I.dicts[lang] = (ok and type(d) == "table") and d or {}
  end
  return I.dicts[lang]
end

function I.valid(lang) return VALID[lang] == true end

function I.set(lang)
  if not VALID[lang] then lang = "pt-BR" end
  I.lang = lang
  load_dict(lang)
end

function I.L(s)
  if I.lang == "pt-BR" or type(s) ~= "string" then return s end
  local d = I.dicts[I.lang] or load_dict(I.lang)
  return d[s] or s
end

-- maiusculas com acentos e cirilico (sem depender de ui/gfx)
local UP = {}
do
  local pairs_ = { "áÁ", "àÀ", "âÂ", "ãÃ", "éÉ", "êÊ", "íÍ", "óÓ", "ôÔ", "õÕ", "úÚ", "çÇ", "üÜ", "ёЁ" }
  for _, p in ipairs(pairs_) do
    local lo, hi = p:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
    UP[lo] = hi
  end
  -- а..я -> А..Я
  for cp = 0x430, 0x44F do UP[utf8.char(cp)] = utf8.char(cp - 0x20) end
end
function I.upper(s)
  s = tostring(s or ""):upper()
  return (s:gsub("[\194-\244][\128-\191]*", function(ch) return UP[ch] or ch end))
end

--- indice reverso: qualquer traducao conhecida -> chave em portugues
local function build()
  I.built = true
  for _, l in ipairs(I.LANGS) do
    if l.id ~= "pt-BR" then
      for k, v in pairs(load_dict(l.id)) do
        I.keys[k] = true
        I.rev[v] = I.rev[v] or k
        I.rev_up[I.upper(v)] = I.rev_up[I.upper(v)] or k
      end
    end
  end
  for _, l in ipairs(I.LANGS) do
    if l.id ~= "pt-BR" then
      for k in pairs(I.dicts[l.id]) do I.rev_up[I.upper(k)] = I.rev_up[I.upper(k)] or k end
    end
  end
end

-- nomes de botoes e siglas que nunca sao traduzidos
local KEEP = { SELECT = true, START = true, A = true, B = true, X = true, Y = true,
  L1 = true, R1 = true, L2 = true, R2 = true, L3 = true, R3 = true, OK = true, FN = true }

--- traducao na hora de desenhar
function I.tr(s)
  if type(s) ~= "string" or s == "" or KEEP[s] then return s end
  if not I.built then build() end
  local d = I.dicts[I.lang] or {}
  if d[s] then return d[s] end                 -- chave em portugues
  -- em portugues, um texto que ja e chave fica como esta (ex.: "Download" nao
  -- pode virar "Baixar" so porque as duas tem a mesma traducao em ingles)
  if I.lang == "pt-BR" and I.keys[s] then return s end
  local k = I.rev[s]                           -- ja traduzido (outro idioma)
  if k then return I.lang == "pt-BR" and k or (d[k] or k) end
  k = I.rev_up[s]                              -- versao em MAIUSCULAS
  if k then return I.upper(I.lang == "pt-BR" and k or (d[k] or k)) end
  -- mensagem guardada com codigo no fim, ex.: "Falha de conexao...\n(7)"
  local base, suf = s:match("^(.-)(%s+[%(%[][%w%-]+[%)%]])$")
  if base and base ~= "" then
    local t = I.tr(base)
    if t ~= base then return t .. suf end
  end
  return s
end

return I
