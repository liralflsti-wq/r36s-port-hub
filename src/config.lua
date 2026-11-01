-- =============================================================================
--  R36S PORT HUB - configuracao
--  Para trocar o catalogo NAO e preciso mexer no codigo do app: basta publicar
--  um catalog.json em qualquer endereco (ex.: um arquivo "raw" do GitHub).
--  Veja docs/CATALOGO.md.
-- =============================================================================
local L = require("lib.i18n").L
local C = {}

C.APP_NAME = L("R36S PORT HUB")
C.VERSION = L("0.4.2 BETA")       -- texto exibido
C.VERSION_NUM = "0.4.2"        -- numero usado para comparar com a atualizacao

-- Atualizacao do sistema (Configuracoes > Atualizacao do sistema).
-- Link do repositorio no GitHub (ex.: https://github.com/USUARIO/REPO, usa a
-- ultima Release) ou de um JSON { "version", "url", "sha256", "notes" }.
-- Tambem pode ser definido em <pasta do app>/update_url.txt (sobrescreve este).
C.UPDATE_URL = "https://raw.githubusercontent.com/liralflsti-wq/r36s-port-hub/main/update.json"

-- Catalogo de temas (Configuracoes > Temas > Baixar novos temas). Vazio ate o
-- repositorio de temas ser publicado. Tambem pode ser definido em
-- <pasta do app>/themes_url.txt. Formato esperado: veja docs/TEMAS.md.
C.THEMES_CATALOG_URL = ""

-- Loja de Temas do EmulationStation (Utilitarios & Ferramentas > Ferramentas de
-- sistema). Link "raw" do temas.json no GitHub. Vazio = usa a copia que vem no
-- app (catalog/es_themes.json). Tambem pode ir em <pasta do app>/es_themes_url.txt
C.ES_THEMES_URL = "https://raw.githubusercontent.com/liralflsti-wq/r36s-port-hub/main/temas.json"
C.TAGLINE = L("Ports de jogos e utilitários para o console R36S, criados por fãs e para fãs.")

-- Endereco do catalogo online (JSON). Deixe vazio enquanto nao houver um
-- catalogo oficial: o app usa entao o catalogo local (veja ordem abaixo).
C.CATALOG_URL = ""

-- Central de Conteudo > BIOS do Sistema: pacote de BIOS (link direto do arquivo).
-- O link NAO vem no codigo: configure em <pasta do app>/bios_url.txt (uma linha).
-- Vazio = a tela avisa que a fonte ainda nao foi configurada.
C.BIOS_URL = ""

-- Ordem de busca do catalogo:
--  1) C.CATALOG_URL (online)  -> salvo em cache para uso offline
--  2) <pasta do app>/catalog_url.txt (uma linha com a URL; sobrescreve a de cima)
--  3) <pasta do app>/catalog.json   (catalogo local, para testes)
--  4) cache do ultimo catalogo online baixado
--  5) catalogo de exemplo embutido no app

-- Pastas (definidas pelo launcher .sh; os valores padrao servem para o R36S)
C.PORTS_DIR = os.getenv("PORTHUB_PORTS_DIR") or "/roms/ports"
C.APP_DIR = os.getenv("PORTHUB_DIR") or (C.PORTS_DIR .. "/r36sporthub")
C.TMP_DIR = C.APP_DIR .. "/tmp"          -- mesma particao de /roms/ports (mover = instantaneo)
C.FETCH_SH = C.APP_DIR .. "/bin/fetch.sh"

-- Margem de seguranca de espaco livre (bytes) exigida alem do necessario
C.SPACE_MARGIN = 32 * 1024 * 1024

-- Itens da pasta de ports que pertencem ao sistema/outras ferramentas.
-- Se um pacote trouxer algo com esses nomes na raiz, o item e IGNORADO
-- (nunca substitui o original). Comparacao sem diferenciar maiusculas.
C.PROTECTED_NAMES = {
  ["portmaster"] = true, ["portmaster.sh"] = true, ["gamelist.xml"] = true,
  ["r36sporthub"] = true, ["r36s port hub.sh"] = true,
}

-- =============================================================================
--  Runtimes do PortMaster (Configuracoes > Atualizar runtimes)
-- =============================================================================
-- Pacote com todos os runtimes aarch64 (versao especifica, definida pelo projeto)
C.RUNTIMES_RELEASE = "2026-10-22_1343"
C.RUNTIMES_ZIP_URL = "https://github.com/PortsMaster/PortMaster-New/releases/download/"
  .. C.RUNTIMES_RELEASE .. "/runtimes.all.aarch64.zip"
-- Indice da MESMA release: traz md5 e tamanho de cada runtime (verificacao)
C.RUNTIMES_INDEX_URL = "https://github.com/PortsMaster/PortMaster-New/releases/download/"
  .. C.RUNTIMES_RELEASE .. "/ports.json"
C.RUNTIMES_ZIP_NAME = "runtimes.all.aarch64.zip"
C.RUNTIMES_ARCH = "aarch64"

-- Futuro: URL dinamica. Com true, o app consulta a API do GitHub e usa a release
-- mais recente que contenha C.RUNTIMES_ZIP_NAME (se falhar, usa a URL fixa acima).
-- Tambem e possivel sobrescrever a URL sem recompilar, criando
-- <pasta do app>/runtimes_url.txt (linha 1: URL do zip; linha 2: URL do ports.json).
C.RUNTIMES_AUTO_LATEST = false
C.RUNTIMES_API_URL = "https://api.github.com/repos/PortsMaster/PortMaster-New/releases?per_page=15"

-- Onde procurar o PortMaster (o launcher tambem informa a pasta encontrada)
C.PORTMASTER_DIRS = {}
for _, d in ipairs({
  os.getenv("PORTHUB_PM_DIR") or "",
  C.PORTS_DIR .. "/PortMaster",
  "/roms/ports/PortMaster",
  "/roms2/ports/PortMaster",
  "/opt/system/Tools/PortMaster",
  "/opt/tools/PortMaster",
  os.getenv("PORTHUB_XDG_ORIG") and (os.getenv("PORTHUB_XDG_ORIG") .. "/PortMaster") or "",
}) do
  if d ~= "" then C.PORTMASTER_DIRS[#C.PORTMASTER_DIRS + 1] = d end
end

-- Capas: quantas ficam carregadas na memoria ao mesmo tempo
C.COVER_CACHE_MAX = 14

-- Quadros por segundo maximos (baixo consumo de CPU/bateria)
C.MAX_FPS = 30
C.ECO_FPS = 20   -- modo economico

return C
