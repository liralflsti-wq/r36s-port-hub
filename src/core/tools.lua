-- =============================================================================
--  Ferramentas integradas ao hub (Utilitarios & Ferramentas)
--  Nao sao ports para baixar: abrem uma tela do proprio app. Todas sao
--  somente leitura e so trabalham quando o usuario pede.
-- =============================================================================
local L = require("lib.i18n").L
local T = {}

T.LIST = {
  { id = "hub_tool_sd", name = L("Analisador do cartão SD"), screen = "sdanalyzer", icon = "manutencao",
    short = L("Espaço total, usado e livre, tamanho de cada pasta e os maiores arquivos do cartão. Somente leitura.") },
  { id = "hub_tool_sdcheck", name = L("Verificador do cartão SD"), screen = "sdcheck", icon = "manutencao",
    short = L("Fabricante, modelo, capacidade informada e pistas de cartão falsificado, mais teste rápido de velocidade.") },
  { id = "hub_tool_integrity", name = L("Verificador de integridade dos ports"), screen = "integrity", icon = "manutencao",
    short = L("Confere script, pasta de dados, itens do PortMaster e runtimes de cada port instalado. Somente leitura.") },
  { id = "hub_tool_net", name = L("Diagnóstico de rede"), screen = "netdiag", icon = "manutencao",
    short = L("Wi-Fi, nome da rede, IP, gateway, DNS, sinal, testes de acesso à internet e ao GitHub e velocidade da internet.") },
  { id = "hub_tool_esthemes", name = L("Loja de Temas"), screen = "esthemes", icon = "ferramentas_de_sistema",
    category = L("Ferramentas de sistema"), category_id = "ferramentas_de_sistema",
    short = L("Temas do EmulationStation compatíveis com o sistema do console: visualizar, baixar, instalar e desinstalar.") },
  { id = "hub_tool_analog", name = "R36S Analog Tester", screen = "tester", icon = "testes_de_controles",
    category = L("Testes de controles"), category_id = "testes_de_controles", test_type = "completo",
    short = L("Teste dos dois analógicos (alcance, zona morta, deriva) e de todos os botões, com relatório. Por LagdoLira.") },
}

for _, t in ipairs(T.LIST) do
  t.builtin = true
  t.section = "tools"
  t.category = t.category or L("Manutenção")
  t.category_id = t.category_id or "manutencao"
  t.size_label = L("Integrado ao hub")
  t.version = t.version or ""
end

--- ferramentas que aparecem num filtro da loja (area tools: Todos ou Manutencao)
function T.for_filter(section, filter)
  if section ~= "tools" then return {} end
  if filter == "all" then return T.LIST end
  local out = {}
  for _, t in ipairs(T.LIST) do
    if filter == "cat:" .. t.category_id then out[#out + 1] = t end
  end
  return out
end

return T
