-- =============================================================================
--  Areas da loja e categorias oficiais (com icones)
--  Cada port do catalogo pertence a UMA area:
--    games -> Ports de Jogos
--    tools -> Utilitarios & Ferramentas
--  As categorias sao filtros reais: o campo "category" de cada port do catalogo
--  e comparado com o "id" (ou um apelido) abaixo. Veja docs/CATALOGO.md.
-- =============================================================================
local L = require("lib.i18n").L
local U = require("lib.util")

local K = {}

K.SECTIONS = {
  { id = "games", name = L("Ports de Jogos"), short = L("Jogos") },
  { id = "tools", name = L("Ports Utilitários e Ferramentas"), short = L("Utilitários") },
}
K.SECTION_BY_ID = {}
for _, s in ipairs(K.SECTIONS) do K.SECTION_BY_ID[s.id] = s end

-- id = U.slug do nome (sem acentos); icon = desenho em ui/icons.lua
K.LIST = {
  { id = "acao", name = L("Ação"), section = "games" },
  { id = "aventura", name = L("Aventura"), section = "games" },
  { id = "rpg", name = "RPG", section = "games" },
  { id = "plataforma", name = L("Plataforma"), section = "games" },
  { id = "corrida", name = L("Corrida"), section = "games" },
  { id = "luta", name = L("Luta"), section = "games" },
  { id = "tiro", name = L("Tiro"), section = "games" },
  { id = "terror", name = L("Terror"), section = "games" },
  { id = "puzzle", name = "Puzzle", section = "games" },
  { id = "estrategia", name = L("Estratégia"), section = "games" },
  { id = "arcade", name = "Arcade", section = "games" },
  { id = "esportes", name = L("Esportes"), section = "games" },
  { id = "classicos", name = L("Clássicos"), section = "games" },
  { id = "manutencao", name = L("Manutenção"), section = "tools" },
  { id = "diagnostico_do_sistema", name = L("Diagnóstico do sistema"), section = "tools" },
  { id = "testes_de_controles", name = L("Testes de controles"), section = "tools" },
  { id = "ferramentas_de_sistema", name = L("Ferramentas de sistema"), section = "tools" },
}
K.BY_ID = {}
for _, c in ipairs(K.LIST) do c.icon = c.id; K.BY_ID[c.id] = c end

-- Testes de controles: UMA categoria com tres tipos (campo "test_type" do catalogo)
K.TEST_TYPES = {
  { id = "analogicos", name = L("Teste de analógicos"), short = L("ANALÓGICOS") },
  { id = "botoes", name = L("Teste de botões"), short = L("BOTÕES") },
  { id = "completo", name = L("Teste completo de controles"), short = L("COMPLETO") },
}
K.TEST_TYPE_BY_ID = {}
for i, t in ipairs(K.TEST_TYPES) do t.order = i; K.TEST_TYPE_BY_ID[t.id] = t end
local TEST_TYPE_ALIAS = {
  analogicos = "analogicos", analogico = "analogicos", analog = "analogicos", sticks = "analogicos",
  botoes = "botoes", botao = "botoes", buttons = "botoes", button = "botoes",
  completo = "completo", complete = "completo", full = "completo", controles = "completo", controle = "completo",
}
-- categorias antigas que viraram tipos de "Testes de controles"
local MERGED = { testes_de_analogicos = "analogicos", testes_de_botoes = "botoes", testes_de_controles = "completo" }

-- apelidos aceitos no catalogo (slug -> id oficial)
local ALIAS = {
  action = "acao", adventure = "aventura", platform = "plataforma", platformer = "plataforma",
  racing = "corrida", race = "corrida", fighting = "luta", fight = "luta", shooter = "tiro",
  fps = "tiro", shmup = "tiro", horror = "terror", survival_horror = "terror", puzzles = "puzzle",
  strategy = "estrategia", sports = "esportes", sport = "esportes", esporte = "esportes",
  classic = "classicos", classics = "classicos", classico = "classicos",
  maintenance = "manutencao", diagnostico = "diagnostico_do_sistema", diagnostics = "diagnostico_do_sistema",
  diagnostic = "diagnostico_do_sistema", teste_de_controles = "testes_de_controles",
  controles = "testes_de_controles", controller_test = "testes_de_controles",
  teste_de_analogicos = "testes_de_analogicos", analogicos = "testes_de_analogicos",
  analog_test = "testes_de_analogicos", teste_de_botoes = "testes_de_botoes", botoes = "testes_de_botoes",
  button_test = "testes_de_botoes", ferramentas = "ferramentas_de_sistema", sistema = "ferramentas_de_sistema",
  system_tools = "ferramentas_de_sistema", tools = "ferramentas_de_sistema",
}

local SECTION_ALIAS = {
  games = "games", game = "games", jogos = "games", jogo = "games", ports_de_jogos = "games",
  tools = "tools", tool = "tools", utility = "tools", utilities = "tools", utilitario = "tools",
  utilitarios = "tools", ferramenta = "tools", ferramentas = "tools", utilitarios___ferramentas = "tools",
  utilitarios_e_ferramentas = "tools", ports_utilitarios_e_ferramentas = "tools", ports_utilitarios = "tools",
}

--- id oficial de uma categoria informada no catalogo (ou o proprio slug, se for nova)
--- Devolve tambem o tipo de teste quando a categoria era um dos testes antigos.
function K.resolve(cat)
  local s = U.slug(cat or "")
  s = s:gsub("%-", "_")
  local id = ALIAS[s] or s
  if MERGED[id] then return "testes_de_controles", MERGED[id] end
  return id
end

--- tipo de teste (analogicos | botoes | completo) a partir do campo do catalogo
function K.test_type(raw, from_category)
  local s = U.slug(raw or ""):gsub("%-", "_")
  return TEST_TYPE_ALIAS[s] or from_category or "completo"
end

--- area de um port: campo "section"/"type"/"area" do catalogo; senao, pela categoria
function K.section_of(raw_section, cat_id)
  if raw_section and raw_section ~= "" then
    local s = SECTION_ALIAS[U.slug(raw_section):gsub("%-", "_")]
    if s then return s end
  end
  local c = K.BY_ID[cat_id]
  return c and c.section or "games"
end

return K
