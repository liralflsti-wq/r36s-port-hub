# Ajustes do R36S PORT HUB (BETA)

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/menu.lua` | Menu com 6 opções na ordem pedida; "Configurações" substitui os itens soltos "Atualizar Catálogo" e "Música" |
| `src/ui/screens/settings.lua` | **Novo**: tela de Configurações (música, catálogo, runtimes) |
| `src/core/runtimes.lua` | **Novo**: gerenciador da atualização de runtimes e recuperação de atualização interrompida |
| `src/threads/runtimes_thread.lua` | **Novo**: download, validação por md5, backup, instalação e restauração |
| `src/ui/overlay.lua` | Painel de progresso, confirmação e resultado dos runtimes |
| `src/core/scan.lua` | Varredura ampliada: `.port`, `GAMEDIR=` dos scripts, capa do `port.json`, lista de todos os ports do cartão; pasta sozinha não identifica jogo |
| `src/core/manifest.lua` | ATUALIZAÇÃO quando a versão instalada é conhecida; lista de ports fora do catálogo; varredura com intervalo mínimo |
| `src/core/catalog.lua` | "Instalados" inclui os ports do cartão; campo `pm_name` |
| `src/core/covers.lua` | Capas por caminho absoluto (`port.json`); limpeza do cache de capas |
| `src/ui/screens/details.lua` | Página para ports que estão no cartão mas fora do catálogo |
| `src/main.lua` | Atualização do catálogo com resultado (novos/alterados/removidos); integração dos runtimes |
| `src/config.lua` | URLs dos runtimes, opção de URL dinâmica, pastas do PortMaster |
| `port/R36S PORT HUB.sh` | Informa ao app a pasta do PortMaster encontrada |
| `README.md`, `docs/CATALOGO.md` | Documentação das novidades |

## Gerenciador de arquivos

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/files.lua` | **Novo**: navegação pelo cartão SD, com as opções Extrair aqui e Instalar como port |
| `src/ui/screens/settings.lua` | 4º item, "Gerenciador de arquivos" (painéis compactados para caber na tela) |
| `src/threads/install_thread.lua` | Modo para arquivo local (sem download), modo "extrair aqui" (sem as regras de port) e exclusão do arquivo compactado só após sucesso |
| `src/core/installer.lua`, `src/ui/overlay.lua` | Opções do arquivo local e mensagens de extração |
| `src/main.lua` | Registro da nova tela |

## Autoria e exclusão de jogos

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/about.lua` | "Desenvolvido por LagdoLira" no topo da tela |
| `src/ui/screens/store.lua` | Em Meus Ports: botão X (Excluir jogo) e dica no rodapé |
| `src/core/uninstall.lua` | **Novo**: identifica com segurança os arquivos do jogo e monta o plano de exclusão |
| `src/threads/delete_thread.lua` | **Novo**: apaga os itens em segundo plano, revalidando cada um |
| `src/core/scan.lua` | Guarda as evidências de cada port (itens do port.json/.port, GAMEDIR), sem mudar o reconhecimento |
| `src/main.lua` | Confirmação, execução e atualização automática da lista |
| `src/ui/overlay.lua` | Aviso "Excluindo..." durante a remoção |

## Logo oficial

| Arquivo | Alteração |
|---|---|
| `src/assets/logo/logo_header.png`, `logo_menu.png`, `logo_about.png` | **Novos**: logo oficial sem o fundo branco, em tamanhos prontos para 640×480 |
| `src/ui/gfx.lua` | O logo em imagem substitui o nome em texto no cabeçalho de todas as telas e na função `G.logo` |
| `src/ui/screens/menu.lua`, `src/ui/screens/about.lua` | Posição do logo |
| `port/r36sporthub/logo.png`, `cover.png` | Logo em tamanho original e nova imagem do hub no EmulationStation |

## Áreas, categorias, brilho, START e BETA

| Arquivo | Alteração |
|---|---|
| `src/catalog/catalog.json` | Daytona USA Arcade e as entradas fictícias de exemplo removidos; catálogo embutido vazio |
| `src/core/categories.lua` | **Novo**: áreas (Ports de Jogos / Utilitários & Ferramentas), 19 categorias oficiais, apelidos e regra de área |
| `src/core/catalog.lua` | Cada port recebe área e categoria oficial; lista fixa de categorias (com contagem, mesmo vazias); filtro por área |
| `src/ui/icons.lua` | **Novo**: ícones retrô das 19 categorias e das 2 áreas |
| `src/ui/screens/sections.lua` | **Novo**: tela da Loja de Ports com as duas áreas |
| `src/ui/screens/store.lua` | Listagem por área (abas da área) e Meus Ports com abas por área; mensagens para listas vazias |
| `src/ui/screens/categories.lua` | Refeita: dois grupos, ícones, cores diferentes por área, rolagem |
| `src/core/brightness.lua` | **Novo**: brilho via brightnessctl (método do ArkOS/dArkOS), com reserva por sysfs, conferência do resultado e preferência salva |
| `src/ui/screens/settings.lua` | Item "Brilho da tela" com barra deslizante; START sem ação |
| `src/core/input.lua`, `src/main.lua` e as telas | START sem nenhuma ação (suporte mantido, reservado); atalho SELECT+START desativado; brilho reaplicado ao abrir |
| `src/config.lua`, `menu.lua`, `about.lua`, launcher, `gameinfo.xml`, `fetch.sh` | Versão BETA; "Loja Comunitária" removido |
| `tools/build.sh` | Pacote passa a se chamar `R36S-PORT-HUB-BETA.zip` |

## Pesquisa, favoritos, Central de Downloads, console e novidades

| Arquivo | Alteração |
|---|---|
| `src/core/categories.lua` | Testes de analógicos/botões/controles unificados em "Testes de controles", com 3 tipos; ids antigos continuam aceitos |
| `src/core/catalog.lua` | Campo `test_type`; ordenação por tipo; filtro de favoritos; campos de novidades (`added`, `updated_at`, `changelog`, `news`) |
| `src/core/favorites.lua` | **Novo**: favoritos persistentes (`favorites.json`) |
| `src/core/downloads.lua` | **Novo**: fila e histórico da Central de Downloads, em volta do instalador existente |
| `src/core/news.lua` | **Novo**: lista de novidades a partir dos dados reais do catálogo |
| `src/core/sysinfo.lua` | **Novo**: leitura das informações do console (somente leitura) |
| `src/ui/portrow.lua` | **Novo**: linha de port compartilhada (capa, estrela, tipo, selo INSTALADO/ATUALIZAR) |
| `src/ui/screens/search.lua`, `downloads.lua`, `news.lua`, `console.lua` | **Novas** telas |
| `src/ui/screens/sections.lua` | Atalhos Pesquisar, Favoritos, Novidades e Downloads |
| `src/ui/screens/store.lua` | Linha compartilhada, modo Favoritos e SELECT para favoritar |
| `src/ui/screens/details.lua` | Área, tipo de teste, estrela, SELECT e estado da fila no botão |
| `src/ui/screens/settings.lua` | Item "Informações do console" e lista com rolagem |
| `src/ui/overlay.lua` | Y = segundo plano; avisos rápidos para downloads em segundo plano |
| `src/main.lua` | Downloads passam pela fila; registro das telas novas |
| `src/ui/gfx.lua` | A fonte pixelada troca Á/Í, que ela não desenha bem, pela letra sem acento |
| `src/ui/icons.lua` | Ícones de pesquisa, novidades e download |

## Tela Sobre o Projeto

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/about.lua` | Novo texto de apresentação, logo do desenvolvedor no lugar do nome, botão "Canal do YouTube" (A), texto rolável e aviso de direitos autorais no final |
| `src/assets/logo/dev_logo.png` | **Novo**: logo Lag do Lira (só as margens vazias foram retiradas; proporção original mantida) |
| `src/lib/qrencode.lua` | **Novo**: gerador de QR Code em Lua puro (luaqrcode, licença BSD), usado para abrir o canal pelo celular |
| `port/r36sporthub/licenses/LICENSE.luaqrcode.md` | Licença da biblioteca de QR Code |

## Servidor FTP (Configurações > Servidor FTP)

| Arquivo | Alteração |
|---|---|
| `src/threads/ftp_thread.lua` | **Novo**: servidor FTP real em Lua (LuaSocket do LÖVE), numa thread do próprio app. Modo passivo (PASV/EPSV), login obrigatório, anônimo recusado, só rede local, raiz presa ao cartão SD (bloqueia `../` e links que saem dele), recebimento em arquivo temporário renomeado só no fim, confirmação no console para pastas importantes, nenhum comando do cliente é executado |
| `src/core/ftp.lua` | **Novo**: gerencia início/parada (manual), configuração em `ftp.json` (permissão 600, senha inicial aleatória), validação de porta/usuário/senha, porta em uso, teste de conexão real, atividade em tempo real, histórico `ftp_history.json` (sem credenciais) e avisos |
| `src/core/net.lua` | **Novo**: IP local/interface/Wi-Fi lidos de `ip`, do kernel (`/proc`) ou do LuaSocket, sem nunca usar 127.0.0.1 |
| `src/ui/screens/ftp.lua` | **Nova** tela: INICIAR, PARAR, TESTAR CONEXÃO, porta, usuário, senha (Y mostra/oculta), SALVAR CONFIGURAÇÕES, estado, IP, clientes, QR Code só com o endereço e aviso de segurança |
| `src/ui/screens/ftp_activity.lua` | **Nova**: abas ATIVIDADE FTP e HISTÓRICO FTP (cancelar transferência, limpar histórico com confirmação) |
| `src/ui/screens/ftp_help.lua` | **Nova**: COMO CONECTAR PELO CELULAR e PELO COMPUTADOR, com IP, porta e usuário reais |
| `src/ui/screens/textinput.lua` | **Novo**: teclado na tela reutilizável (texto e só números, senha oculta) |
| `src/ui/screens/settings.lua` | Item "Servidor FTP" com o estado atual |
| `src/main.lua` | Atualiza o FTP a cada quadro, mostra os pedidos de confirmação, pergunta antes de sair com o servidor ligado e o para ao fechar |
| `src/ui/gfx.lua` | Fonte pixelada também troca Ó, Ú e É pela letra sem acento |
| `src/dev/autotest.lua` | Comandos de teste `waitfile`, `touch`, `waitdialog` (só no pacote de desenvolvimento) |

## Ferramentas de manutenção e status do Wi-Fi

| Arquivo | Alteração |
|---|---|
| `src/core/tools.lua` | **Novo**: as 3 ferramentas integradas, que aparecem em Utilitários & Ferramentas → Todos e → Manutenção (selo INTEGRADO) |
| `src/ui/screens/sdanalyzer.lua` + `src/threads/sdscan_thread.lua` | **Novo**: Analisador do cartão SD (total/usado/livre, tamanho de cada pasta com navegação, 60 maiores arquivos). Só roda quando o usuário pede, em segundo plano, cancelável, somente leitura |
| `src/ui/screens/integrity.lua` + `src/threads/integrity_thread.lua` | **Novo**: Verificador de integridade (ÍNTEGRO / ATENÇÃO / ERRO) para ports do hub, PortMaster e cópia manual: script (vazio, #!, CRLF), pasta de dados (port.json/GAMEDIR/nome), pasta vazia, links quebrados, temporários, itens do port.json, itens instalados pelo hub, PortMaster e runtimes. Separa "confirmado" de "não foi possível confirmar". Somente leitura |
| `src/ui/screens/netdiag.lua` + `src/threads/nettest_thread.lua` | **Novo**: Diagnóstico de rede (Wi-Fi, nome da rede, IPv4, interface, gateway, DNS, sinal, teste de internet por IP e por nome, teste do GitHub por DNS/conexão/HTTPS). Estados CONECTADO, DESCONECTADO, SEM ACESSO À INTERNET, VERIFICANDO CONEXÃO, INFORMAÇÕES INDISPONÍVEIS |
| `src/core/net.lua` + `src/threads/net_thread.lua` | Leitura da rede em segundo plano (a cada 4 s) e funções de gateway, DNS, nome da rede (iwgetid/iw/nmcli/wpa_cli, o que existir) e sinal (/proc/net/wireless) |
| `src/ui/screens/menu.lua` | Rodapé da tela inicial: ícone + "CONECTADO / IP: x" ou "DESCONECTADO / IP: INDISPONÍVEL" |
| `src/ui/screens/store.lua`, `src/ui/portrow.lua` | Ferramentas integradas na lista (A abre a ferramenta) |
| `src/ui/screens/sections.lua`, `src/ui/screens/categories.lua` | Contagem das ferramentas integradas na área e na categoria Manutenção |
| `src/ui/screens/ftp.lua`, `ftp_help.lua` | Usam a leitura de rede em segundo plano |
| `src/main.lua` | Inicia/para a leitura de rede; registra as telas novas |

## Cadastro TEMPORÁRIO: Daytona USA (Arcade) — somente para teste

| Arquivo | Alteração |
|---|---|
| `src/catalog/catalog.json` | Cadastro temporário do Daytona USA (lista `games`, dados exatamente como enviados). **Para remover:** apague o item da lista `games` (deixe `"games": []`) |
| `src/core/catalog.lua` | Aceita `rip_url` como link de download (além de `download_url`) e lê os campos opcionais `platform`, `source` e `file_type` |
| `src/ui/screens/details.lua` | Mostra Plataforma, Origem e Formato do arquivo no topo da descrição, quando o catálogo informa |

## Central de Downloads em segundo plano (START)

| Arquivo | Alteração |
|---|---|
| `src/main.lua` | START agora abre a Central de Downloads (`App.open_downloads`): não duplica a tela, manda a janela de progresso para segundo plano sem interromper e respeita diálogos/confirmações abertos. Ao sair com downloads ativos ou na fila, pergunta antes |
| `src/core/downloads.lua` | Etapas Download/Extração/Instalação com estado e % reais, tipo de operação, tempo e velocidade média; histórico salvo com esses dados; arquivo local pula o download, "só extrair" pula a instalação |
| `src/ui/screens/downloads.lua` | Nova apresentação: capa/ícone, tipo, estado com %, barra, números reais, etapas, selo INSTALADO; A = progresso/tirar da fila; X = limpar histórico com confirmação |
| `src/ui/screens/menu.lua` | Opção "Downloads em segundo plano" abaixo de Meus Ports (7 itens) |
| `src/ui/screens/sections.lua` | Atalho Downloads usa a mesma central |
| `src/ui/overlay.lua` | Aviso do segundo plano indica o START |

## Ícones das categorias (imagens)

| Arquivo | Alteração |
|---|---|
| `src/assets/icons/*.png` | **Novos**: 19 ícones 64×64 (17 categorias + `games` e `tools` das áreas), brancos com fundo transparente |
| `src/ui/icons.lua` | Usa `assets/icons/<id>.png` quando existe, pintado com a cor da tela (área, selecionado, apagado); tamanhos grandes em escala inteira para a pixel art não distorcer. Sem a imagem, continua o desenho antigo (pesquisa, novidades, download e estrela seguem desenhados) |

## Daytona USA (teste final) e tela de detalhes

| Arquivo | Alteração |
|---|---|
| `src/catalog/catalog.json` | Daytona USA (ainda temporário): categoria `corrida`, descrição e `author` "@mpjsilvaa". Links de download e capa sem alteração |
| `src/ui/screens/details.lua` | Etiquetas de plataforma e INSTALADO; descrição organizada em DESCRIÇÃO e INFORMAÇÕES (Plataforma, Categoria, Port disponibilizado por, Espaço ocupado, Origem, Formato); "Espaço ocupado" = soma real dos arquivos instalados do port (script + pasta própria, sem runtimes nem outros jogos), recalculada ao abrir e após instalar/reinstalar; etiqueta de tamanho "?" não aparece mais |

## Print da tela (botão FN)

| Arquivo | Alteração |
|---|---|
| `src/core/input.lua` | Botão FN (`guide` no SDL) vira a ação de print (antes repetia o SELECT); F12 faz o mesmo no teclado. Botões sem função são anotados no log.txt |
| `src/main.lua` | Print em qualquer tela, até com janelas abertas: PNG em `<cartão>/print` (ex.: `/roms/print`), nome `print_AAAAMMDD_HHMMSS.png`, sem sobrescrever; o aviso rápido não aparece na imagem |

## Aviso inicial

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/disclaimer.lua` | Botão do aviso inicial: ícone do A + "PARA CONTINUAR", centralizados juntos (antes "CONTINUAR PARA A LOJA") |

## Versão 0.1 BETA, Atualização do sistema e catálogo limpo

| Arquivo | Alteração |
|---|---|
| `src/config.lua` | Versão **0.1 BETA** (`C.VERSION`) e número `C.VERSION_NUM = "0.1"` para comparar atualizações; `C.UPDATE_URL` (vazio até o link do GitHub ficar pronto) |
| `src/core/update.lua` + `src/threads/update_thread.lua` | **Novo**: verifica a última versão (Release do GitHub ou JSON), baixa com progresso real, confere tamanho/sha256, extrai, valida a estrutura e troca os arquivos com cópia de segurança e retorno automático em caso de falha. Dados do usuário não são tocados |
| `src/ui/screens/update.lua` | **Nova** tela: sem link / verificando / atualizado / nova versão (com novidades) / atualizando / instalada / erro |
| `src/ui/screens/settings.lua` | Item "Atualização do sistema" |
| `src/main.lua` | Atualização roda em segundo plano; downloads de ports esperam a atualização; sair durante a troca de arquivos é bloqueado |
| `src/catalog/catalog.json` | **Daytona USA removido**: catálogo embutido vazio, aguardando o link do catálogo no GitHub |
| `src/ui/screens/details.lua` | "Port disponibilizado por" não aparece mais |

## Apoio ao projeto (Pix) em Sobre o Projeto

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/about.lua` | START abre a janela "APOIE O PROJETO" com o QR Code Pix (gerado do código "copia e cola" informado, CRC conferido) e um texto pedindo apoio; atalho "START Apoiar" em destaque ao lado de "A Abrir canal"; B, A ou START fecham |
| `src/main.lua` | START usa a função própria da tela quando ela existe (só Sobre o Projeto); em todas as outras telas continua abrindo a Central de Downloads |

## Sistema de temas + Tema Xbox

| Arquivo | Alteração |
|---|---|
| `src/themes/default/theme.json` + `preview.png` | **Novo**: o tema original descrito em dados (cores idênticas às de antes) |
| `src/themes/xbox/theme.json` + `preview.png` | **Novo**: Tema Xbox (preto, cinza-escuro, verde #107C10/#52B043, botões A/B/X/Y nas cores do controle, cantos mais retos, fundo moderno sem scanlines) |
| `src/core/themes.lua` | **Novo**: lista temas inclusos e instalados (`user_themes/`), valida o theme.json, aplica sem reiniciar, salva em `theme.txt`, volta ao padrão se o tema salvo falhar; endereço do catálogo futuro |
| `src/ui/screens/themes.lua` | **Nova** tela Temas: lista com amostra de cores, pré-visualização (só a do item selecionado é carregada), descrição, "EM USO", A aplica; item BAIXAR NOVOS TEMAS informa que o catálogo ainda será configurado |
| `src/ui/theme.lua` | `T.apply_palette` troca as cores dentro das tabelas existentes (todas as telas mudam juntas); `T.style` |
| `src/ui/gfx.lua` | Cantos seguem `T.style.round`; fundo "retro" (padrão) ou "modern" (Xbox); scanlines opcionais |
| `src/ui/screens/settings.lua` | Item "Temas" (mostra o tema atual) |
| `src/main.lua` | Aplica o último tema ao abrir; registra a tela |
| `src/config.lua` | `C.THEMES_CATALOG_URL` (vazio) |
| `docs/TEMAS.md` | **Novo**: estrutura dos temas e formato do catálogo futuro |

## Logo própria do Tema Xbox

| Arquivo | Alteração |
|---|---|
| `src/themes/xbox/logo_header.png`, `logo_menu.png`, `logo_about.png` | **Novos**: logo verde do R36S PORT HUB (da imagem enviada; margens vazias retiradas, proporção mantida, mesmos tamanhos da logo original) |
| `src/ui/gfx.lua` | A logo vem do tema atual quando ele tem `logo_*.png`; senão, a original. Ao trocar de tema, as logos do tema anterior saem da memória |
| `src/core/themes.lua` | Detecta a logo do tema |
| `src/themes/xbox/preview.png` | Pré-visualização atualizada com a logo verde |

## Logos novas (Tema Padrão e Tema Xbox)

| Arquivo | Alteração |
|---|---|
| `src/assets/logo/logo_header.png`, `logo_menu.png`, `logo_about.png` | Substituídas pela nova logo rosa/ciano em escudo (Tema Padrão) |
| `src/themes/xbox/logo_header.png`, `logo_menu.png`, `logo_about.png` | Substituídas pela nova logo verde em escudo (Tema Xbox) |
| `src/themes/*/preview.png` | Pré-visualizações refeitas com as logos novas |

Margens vazias retiradas e proporção original mantida (1,48 : 1): 47×32 (cabeçalho), 110×74 (menu), 92×62 (Sobre).

## Indicador de bateria (rodapé da tela inicial)

| Arquivo | Alteração |
|---|---|
| `src/core/battery.lua` | **Novo**: lê `/sys/class/power_supply/` (bateria com `type` = Battery: `capacity` e `status`; carregador Mains/USB: `online`). Ignora baterias de periféricos (`scope` = Device). Sem `capacity` legível → indisponível (nunca inventa valor). Leitura de arquivos do kernel a cada 20 s, sem processos |
| `src/ui/screens/menu.lua` | Rodapé: Wi-Fi (sem mudança no funcionamento) + ícone de bateria e percentual no canto direito; 4 níveis (alta ≥75, média ≥40, baixa ≥15, crítica <15 piscando), raio quando carregando, "?" + INDISPONÍVEL sem leitura; cores do tema ativo |

## Ícone do direcional

| Arquivo | Alteração |
|---|---|
| `src/ui/gfx.lua` | O ícone "+" das dicas de botões virou um direcional (cruz com setas nas quatro pontas), na cor do tema. Só o desenho mudou; a navegação continua igual |

## Verificador do cartão SD (Manutenção)

| Arquivo | Alteração |
|---|---|
| `src/core/sdcard.lua` | **Novo**: lê o que o cartão informa em `/sys/block/mmcblkN/device/` (name, manfid, oemid, date, serial, type, hwrev, fwrev) e `/sys/block/mmcblkN/size`; traduz códigos de fabricantes conhecidos; gera pistas (fabricante zerado/desconhecido, data inconsistente, modelo genérico, série zerada). Somente leitura |
| `src/threads/sdspeed_thread.lua` | **Novo**: teste leve de velocidade: grava 64 MB na pasta temporária do hub (com fsync), lê de volta sem cache (leitura direta ou limpeza do cache; se nenhuma for possível, a leitura aparece como indisponível) e apaga o arquivo |
| `src/ui/screens/sdcheck.lua` | **Nova** tela: identificação, pistas e velocidade; L1/R1 trocam de cartão quando há dois |
| `src/core/tools.lua`, `src/main.lua` | Quarta ferramenta integrada em Manutenção |

Sem teste completo de gravação/leitura da capacidade (pesado para o R36S); a tela avisa que a capacidade informada não prova a capacidade real.

## Relógio

| Arquivo | Alteração |
|---|---|
| `src/ui/gfx.lua` | Cabeçalho de todas as telas mostra a hora (HH:MM) no canto direito; o texto de informação da tela fica à esquerda dela, com um separador |
| `src/ui/screens/menu.lua` | Tela inicial: dia da semana, data e hora no alto, à direita, acima do "Em destaque" |

A hora é a do sistema do console (fuso configurado no dArkOS), lida a cada quadro sem custo extra.

## Loja de Temas (EmulationStation)

| Arquivo | Alteração |
|---|---|
| `src/core/osdetect.lua` | **Novo**: identifica dArkOSRE, dArkOS, ArkOS, AmberELEC, ROCKNIX, KNULLI, JELOS e Batocera por evidências somadas, com versão e confiança; pasta de temas real; tema em uso no ES |
| `src/core/esthemes.lua` | **Novo**: catálogo (online > cache > cópia do app), filtros por sistema, registro de instalados, instalação em thread, desinstalação segura |
| `src/threads/estheme_thread.lua` | **Novo**: baixar, conferir ZIP, bloquear ZIP Slip/links, conferir espaço, extrair, validar theme.xml, backup, instalar |
| `src/ui/screens/esthemes.lua` | **Nova** tela: sistema/versão/confiança, filtros (Compatíveis, Populares, Recentes, Leves, Completos, Instalados), pré-visualização, VISUALIZAR, BAIXAR E INSTALAR, DESINSTALAR, escolha manual do sistema |
| `src/catalog/es_themes.json` + `catalogo-temas/temas.json` | **Novo**: catálogo com 41 temas verificados (galeria OGA, 640x480) |
| `src/core/tools.lua` | Loja de Temas como ferramenta integrada em "Ferramentas de sistema" |
| `src/config.lua` | `C.ES_THEMES_URL` |
| `src/main.lua` | Registro da tela; sair bloqueado durante a instalação de tema |
| `docs/LOJA_TEMAS.md` | **Novo**: detecção, formato do catálogo, fontes e regras de instalação |

## Loja de Ports: texto verde removido

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/sections.lua` | Removido o texto "+ N ferramentas integradas" do card Utilitários & Ferramentas (ficava por baixo do "A Entrar"); a contagem voltou à posição original, igual ao card de jogos |

## Loja de Temas: só sistemas com temas

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/esthemes.lua` | A escolha de sistema mostra só os sistemas que têm temas no catálogo (hoje dArkOSRE, dArkOS e ArkOS), com a contagem de compatíveis e experimentais de cada um. Quando o catálogo ganhar temas para outro sistema, ele volta a aparecer sozinho |

## Multilíngue (pt-BR, English, Русский) e nova abertura

| Arquivo | Alteração |
|---|---|
| `src/lib/i18n.lua` | **Novo**: idioma atual, `L()` (texto em português é a chave), `tr()` na hora de desenhar e índice reverso (troca o texto já montado de um idioma pelo atual, inclusive em MAIÚSCULAS). Nomes de botões nunca são traduzidos |
| `src/i18n/en.lua`, `src/i18n/ru.lua` | **Novos**: dicionários com todos os textos do app, incluindo o Aviso Importante completo |
| `src/core/prefs.lua` | **Novo**: `settings.txt` em `chave=valor` (`language`, `disclaimer_ok`, `music`) com gravação segura (temporário + renomear) |
| `src/core/music.lua` | Passa a usar `Prefs`, então não apaga as outras chaves de `settings.txt` |
| `src/ui/screens/splash.lua` | **Nova**: logo, nome, slogan, tag BETA e barra de carregamento real, que avança uma etapa por quadro |
| `src/ui/screens/language.lua` | **Nova**: SELECT LANGUAGE com bandeiras desenhadas. No primeiro acesso, as dicas aparecem no idioma destacado. Em Configurações, marca o idioma EM USO |
| `src/ui/screens/disclaimer.lua` | Traduzido. A confirmação fica gravada e o aviso só aparece uma vez. No primeiro acesso, B volta à escolha de idioma |
| `src/ui/screens/settings.lua` | Novo item **Idioma**, depois de Temas |
| `src/main.lua` | Idioma aplicado antes de carregar as telas. Nova sequência de abertura: splash → idioma → aviso → menu. `App.set_language` atualiza todas as telas abertas, os nomes de categorias e as ferramentas sem reiniciar. START (downloads) fica bloqueado na abertura |
| `src/ui/gfx.lua`, `src/ui/theme.lua` | `G.text`, `G.text_fit`, `G.wrap`, `G.tag` e as medidas de fonte traduzem antes de desenhar e medir. Fontes de reserva Inter com cirílico |
| `assets/fonts/Inter-*-Cyrillic.otf` | **Novas**: só o alfabeto cirílico, cerca de 41 KB cada (licença OFL em `licenses/LICENSE.Inter.txt`) |
| `src/lib/util.lua` | `U.upper` com cirílico. Unidades por idioma (Б/КБ/МБ/ГБ, с/мин/ч em russo). Novo `U.format_speed` |
| `src/threads/*` e chamadas | Cada tarefa recebe o idioma em `job.lang`, então as mensagens das threads saem no idioma certo |
| Todas as telas | Textos passaram para `L()`. Ajustes de layout para textos longos: rótulos do FTP, aviso do FTP, botão Apoiar em Sobre, teclas do teclado virtual, selo EM USO nos temas, motivo na Atividade FTP, teste de velocidade do cartão |
| `src/core/catalog.lua` | Campos opcionais `description_en/ru` e `short_en/ru` nos ports (`Catalog.text`) |
| `src/catalog/es_themes.json`, `catalogo-temas/temas.json` | Descrições em inglês e russo dos 41 temas |
| `docs/IDIOMAS.md` | **Novo**: como funciona, onde fica salvo e como corrigir uma tradução |

## Configurações reformuladas

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/settings.lua` | **Refeita** como central de categorias: 9 cartões em 3 × 3, com ícone, nome, descrição curta, estado atual e indicador de acesso. Só mostra estados que já estão em memória |
| `src/ui/screens/settings_cat.lua` | **Nova**: tela de cada categoria com interruptores, sliders, escolhas, ações e informações. Explicação da opção selecionada no rodapé e rolagem |
| `src/ui/settings_defs.lua` | **Novo**: definição das 9 categorias. Todas as opções executam ações reais |
| `src/ui/icons.lua` | 9 ícones novos desenhados em código (paleta, alto-falante, Wi-Fi, bateria, controle, download, disquete, sino, chip) |
| `src/core/sfx.lua` | **Novo**: efeitos sonoros gerados em código (navegar, confirmar, voltar, notificação), com liga/desliga e volume |
| `src/core/backup.lua` | **Novo**: backup e restauração por grupos (preferências, favoritos, FTP, históricos) na pasta `backup/` dos dados do app |
| `src/core/music.lua` | Volume da música ajustável e salvo (`music_vol`) |
| `src/core/battery.lua` | `B.details()`: tensão, saúde, temperatura e carregador, só quando o sistema informa |
| `src/core/sysinfo.lua` | `I.temperature()`: temperatura do processador (`/sys/class/thermal`), só se existir |
| `src/main.lua` | Notificações filtradas pelas escolhas do usuário (`App.toast`). Som nas ações e nas notificações. Animações (`App.pulse`, `App.animations`). Modo econômico em 20 FPS. `App.apply_restored` aplica um backup restaurado sem reiniciar |
| `src/ui/overlay.lua`, `details.lua`, `about.lua`, `menu.lua` | Pulsos e troca automática do destaque respeitam Animações e Modo econômico |
| `src/config.lua` | `C.ECO_FPS = 20` |
| `src/i18n/en.lua`, `src/i18n/ru.lua` | Textos das novas telas |

## Correção: música do menu na abertura

| Arquivo | Alteração |
|---|---|
| `src/core/music.lua` | A splash pedia a faixa principal antes de o áudio ser iniciado. O pedido ficava marcado como atendido, e a música só começava ao entrar numa tela com outra faixa (ex.: Configurações). Agora, se a faixa pedida ainda não foi aberta, ela é iniciada quando o áudio fica pronto |

## R36S Analog Tester integrado

| Arquivo | Alteração |
|---|---|
| `port/r36sporthub/tools/` | **Novo**: R36S Analog Tester 1.2 (LagdoLira), arquivos originais sem alteração, com o LEIA-ME |
| `port/R36S PORT HUB.sh` | O launcher passou a rodar em laço. Se o app pedir uma ferramenta (`conf/.run_tool`), ela roda com o app fechado e, depois, o app abre de novo com `PORTHUB_RETURN` |
| `src/main.lua` | `App.launch_tool`: confere downloads e FTP antes e grava o pedido para o launcher. Na volta, o app reabre direto na tela do teste (Configurações → Controles ou Loja) |
| `src/ui/screens/tester.lua` | **Nova**: o que o teste faz, como sair, botão ABRIR TESTE e o último relatório (com rolagem, nomes e estados traduzidos) |
| `src/core/tools.lua` | O tester aparece como ferramenta integrada em Utilitários & Ferramentas → Testes de controles |
| `src/ui/settings_defs.lua` | Controles: Testar analógicos e botões, Último relatório, Todos os testes, Mapa dos botões |
| `src/ui/screens/settings.lua`, `store.lua` | Volta para a categoria certa depois do teste |
| `tools/build.sh` | Script do teste com permissão de execução no pacote |

## Velocidade da internet

| Arquivo | Alteração |
|---|---|
| `src/threads/speedtest_thread.lua` | **Novo**: latência (TCP, mediana de 5), download (`/__down`) e upload (`/__up`) no `speed.cloudflare.com`, medidos pelo `curl`, com limite de 12 s por etapa |
| `src/ui/screens/netdiag.lua` | Nova seção VELOCIDADE DA INTERNET, preenchida etapa por etapa. **X** testa a velocidade. Mostra o último teste salvo (`speed_last` em `settings.txt`). Textos que faltavam traduzir agora usam `L()` |
| `src/ui/settings_defs.lua` | Rede e conectividade ganhou **Velocidade da internet**, com o último resultado. Ao abrir, roda o diagnóstico e o teste de velocidade |
| `src/core/tools.lua` | Descrição do Diagnóstico de rede atualizada |

## Analisador de Console

| Arquivo | Alteração |
|---|---|
| `src/threads/consoleid_thread.lua` | **Novo**: coleta somente leitura em 7 etapas: sistema, CPU, RAM, Device Tree (model, compatible, painel com sha1 da panel-init-sequence, display-timings, GPU), tela (DRM), bateria e armazenamento. Não lê números de série nem MAC |
| `src/core/consoleid.lua` | **Novo**: compara com a base, calcula diferenças em relação à referência do R36S (ROCKNIX: RK3326, 4× Cortex-A35, 1 GB, 640x480, sem eMMC), dá a classificação e a confiança, guarda o último resultado e exporta o TXT |
| `src/data/console_signatures.json` | **Novo**: 135 placas e 38 assinaturas de painel, com fonte e commit de cada uma |
| `src/ui/screens/consoleid.lua` | **Nova**: tela inicial, etapas da análise, resultado (abas RESULTADO e INFORMAÇÕES COLETADAS) e exportação |
| `src/ui/settings_defs.lua`, `settings_cat.lua`, `icons.lua` | Opção nova com ícone próprio em Informações do console |
| `tools/mkconsoledb.py`, `fdtparse.py`, `fdt2.py`, `fdt3.py` | Geração da base a partir dos DTB publicados |

## Correção: painel não identificado no Analisador de Console

| Arquivo | Alteração |
|---|---|
| `src/threads/consoleid_thread.lua` | No aparelho, `/proc/device-tree` é um link para `/sys/firmware/devicetree/base`, e o `find` não entra num link usado como ponto de partida. Por isso a assinatura do painel não era lida. Agora o analisador lê primeiro `/sys/firmware/devicetree/base` e chama o `find` com `/` no fim do caminho |

## Gerenciador de Wi-Fi completo

| Arquivo | Alteração |
|---|---|
| `src/core/wifi.lua` | **Novo**: pedidos ao NetworkManager do sistema pelo `nmcli` (estado, pesquisa, redes salvas, conectar, reconectar, desconectar, esquecer, rádio). A senha vai pelo editor do `nmcli` na entrada padrão, nunca na linha de comando. Tenta `sudo -n` se o NetworkManager negar permissão |
| `src/threads/wifi_thread.lua` | **Novo**: roda cada pedido em segundo plano |
| `src/core/wifijob.lua` | **Novo**: inicia os pedidos e guarda o último estado para as outras telas |
| `src/ui/screens/wifi.lua` | **Nova**: Gerenciar Wi-Fi (interruptor, conexão atual, abas REDES DISPONÍVEIS e REDES SALVAS, conectar/desconectar/esquecer) |
| `src/ui/screens/wifi_connect.lua` | **Nova**: conectar a uma rede (senha com mostrar/ocultar, CONECTAR/CANCELAR, estados da conexão, nova tentativa após senha errada) |
| `src/ui/screens/textinput.lua` | Modo `full`: maiúsculas/minúsculas, números, todos os símbolos ASCII, espaço, apagar, OK e cancelar |
| `src/ui/settings_defs.lua` | Rede e conectividade: opção Gerenciar Wi-Fi e as linhas rede Wi-Fi, tipo de conexão, sinal, gateway e DNS (atualizadas a cada 6 s) |
| `src/main.lua` | Telas novas registradas |
| `src/i18n/en.lua`, `ru.lua` | Textos novos traduzidos |

## Correção: Wi-Fi "desconectado" e sinal 0% no Diagnóstico de rede

| Arquivo | Alteração |
|---|---|
| `src/core/net.lua` | `wifi_iface` ignorava a ordem das interfaces e pegava a `p2p0` (interface virtual Wi-Fi Direct do driver Realtek, sempre "down"). Agora prefere a interface em uso, depois a que está "up", e deixa a `p2p*` por último. `signal`: o driver 8188eu informa 0 e -256 dBm em `/proc/net/wireless`; valores inválidos são descartados e o sinal vem do `iw dev <if> link` ou do NetworkManager (`nmcli ... IN-USE,SIGNAL`) |
| `src/threads/nettest_thread.lua` | Passa a interface com IP para a escolha da interface Wi-Fi |

## Desligar e reiniciar o console (menu Sair)

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/menu.lua` | A janela "Sair" virou uma lista: Sair, Reiniciar lista, **Reiniciar console**, **Desligar console** e Voltar. Desligar/Reiniciar pedem confirmação (CANCELAR vem selecionado) |
| `src/ui/overlay.lua` | Diálogo em lista vertical (`list = true`): rótulo + descrição, navegação para cima/baixo |
| `src/main.lua` | `App.power_request`: fecha o app pelo mesmo caminho do "Sair" (avisa sobre downloads, FTP, atualização e instalação de tema) e só então grava o pedido em `conf/.power` |
| `port/R36S PORT HUB.sh` | Depois que o app fecha: `sync` e `systemctl poweroff`/`reboot` (com `sudo -n`, com alternativas). Apaga pedidos antigos ao abrir; com pedido de energia, não reinicia o EmulationStation |
| `src/i18n/en.lua`, `ru.lua` | Textos novos |

## Capa, logo e fundo na lista de Ports

| Arquivo | Alteração |
|---|---|
| `port/r36sporthub/cover.png` | **Nova** capa 640x480 (logo, sol retrô e grade neon) |
| `port/r36sporthub/fanart.png` | **Novo** fundo 1280x720 sem texto, para temas que usam fanart |
| `port/r36sporthub/gameinfo.xml` | image, thumbnail, marquee (logo.png) e fanart |
| `src/core/esgamelist.lua` | **Novo**: ao abrir, coloca a entrada do hub em `/roms/ports/gamelist.xml` (ou só completa as imagens que faltam). Não mexe em outros jogos nem troca imagens já definidas; faz `gamelist.xml.porthub.bak` na 1ª alteração; grava com arquivo temporário |
| `src/main.lua` | Chama o passo acima na abertura e avisa uma vez |
| `tools/mkart.py` | Gera `cover.png` e `fanart.png` a partir do logo |

## Aviso importante em toda abertura

| Arquivo | Alteração |
|---|---|
| `src/main.lua` | O Aviso importante volta a aparecer toda vez que o app abre (antes, depois de aceito uma vez, não aparecia mais). A escolha de idioma continua só no primeiro acesso. Voltar de uma ferramenta (Analog Tester) não repete o aviso. Os avisos rápidos da abertura (tema, capa na lista de Ports) esperam o aviso ser confirmado para não cobrir o botão |

## Capa sem "loja"

| Arquivo | Alteração |
|---|---|
| `port/r36sporthub/cover.png`, `fanart.png` | Capa regerada: "PORTS, FERRAMENTAS E MAIS PARA O R36S" e "Downloads • FTP • Wi-Fi • Temas • Diagnósticos" (sem "loja") |
| `port/r36sporthub/gameinfo.xml`, `src/core/esgamelist.lua` | Nova descrição: "Central de ports e ferramentas para o R36S…". Se a entrada no `gamelist.xml` ainda tiver a descrição antiga escrita pelo hub, ela é trocada; descrições feitas pelo usuário não são mexidas |
| `tools/mkart.py` | Textos novos |

## Sem aviso da capa na abertura

| Arquivo | Alteração |
|---|---|
| `src/main.lua` | Removido o aviso "Capa do R36S PORT HUB adicionada…". A entrada no `gamelist.xml` continua sendo feita em silêncio |

## Gerenciador de arquivos: recortar/colar, excluir e extrair com pergunta

| Arquivo | Alteração |
|---|---|
| `src/ui/screens/files.lua` | **X** (ou **A** num arquivo) abre as opções do item: Extrair aqui e Instalar como port (só em ZIP/RAR/7z), Recortar, Excluir e Cancelar. **Y** cola o item recortado na pasta aberta (mover; nunca sobrescreve; não move pasta para dentro dela mesma). Excluir pede confirmação (CANCELAR selecionado) e avisa quando é pasta principal do cartão. Itens protegidos: raízes dos cartões, a pasta e o script do hub, PortMaster, `gamelist.xml` e o arquivo em extração |
| `src/threads/fileop_thread.lua` | **Novo**: move (`mv -n`) e exclui (`rm -rf`) em segundo plano, confere o resultado e faz `sync` |
| `src/ui/overlay.lua` | Extrair aqui não apaga mais o compactado sozinho: ao terminar, pergunta EXCLUIR / MANTER (MANTER selecionado) |
| `src/i18n/en.lua`, `ru.lua` | Textos novos |

## Controle do LED

| Arquivo | Alteração |
|---|---|
| `src/core/led.lua` | **Novo**: lê `/sys/class/leds`, ignora LEDs de carga/bateria e saídas que não são LED, junta vermelho/verde/azul de mesma função como LED RGB, descobre brilho (max_brightness) e efeitos (triggers do kernel: timer, pattern, heartbeat). Aplica, salva em `led.json`, guarda o estado original e restaura. Usa `sudo -n` se o sistema negar a escrita |
| `src/ui/screens/led.lua` | **Nova**: estado real do LED, ligar/desligar, cor (RGB), brilho (PWM), efeito, aplicar ao ligar, restaurar padrão; tela de "sem controle" com o motivo |
| `port/r36sporthub/bin/led_boot.sh` | **Novo**: usado só pelo serviço opcional; valida nomes e valores e escreve apenas em `/sys/class/leds/<led>/` |
| `src/ui/settings_defs.lua`, `src/ui/icons.lua` | Opção "Controle do LED" (com ícone) em Aparência e personalização |
| `src/main.lua` | Tela registrada; reaplica a escolha salva ao abrir |
| `tools/build.sh` | Permissão de execução do `led_boot.sh` |
| `src/i18n/en.lua`, `ru.lua` | Textos novos |

## Otimizador e manutenção do microSD

| Arquivo | Alteração |
|---|---|
| `src/core/sdmaint.lua` | **Novo**: partições (`lsblk` ou `/proc/partitions`, `blkid` para desmontadas), montagens e opções (`/proc/mounts`, `/dev/root` pelo `/proc/cmdline`), uso (`df -Pk`), ferramentas (procura também em /sbin), suporte a descarte (`/sys/block/<cartão>/queue`) |
| `src/threads/sdmaint_thread.lua` | **Novo**: analisar (du/find), duplicados (tamanho → hash do 1º MB → hash completo), integridade (montagem ro, dmesg, dumpe2fs/tune2fs, flags exFAT), fsck só leitura de partição desmontada (confere de novo antes), fstrim, sync, limpeza da pasta tmp do hub. Progresso real e cancelamento |
| `src/ui/screens/sdmaint.lua` | **Nova**: cartão, partições e as 7 ferramentas |
| `src/ui/screens/sdmaint_run.lua` | **Nova**: execução com progresso, resultados, plano de verificação por partição e relatório TXT sem sobrescrever |
| `src/ui/settings_defs.lua`, `src/ui/icons.lua` | Opção nova (com ícone) em Informações do console |
| `src/main.lua` | Telas registradas |
| `src/i18n/en.lua`, `ru.lua` | Textos novos |

## Verificador de compatibilidade dos ports

| Arquivo | Alteração |
|---|---|
| `src/core/compat.lua` | **Novo**: identifica o console uma vez (modelo, SoC, arquitetura, sistema, kernel, glibc, RAM, tela, gráficos, PortMaster e runtimes), guarda a impressão digital do ambiente (`compat_env.txt`) para saber se mudou, lê os requisitos do port (`compat` ou `attr` do PortMaster) e classifica (compatível, experimental, incompatível, não verificado), com cache por port |
| `src/ui/screens/compat.lua` | **Nova**: painel compacto + "ver detalhes da compatibilidade" |
| `src/ui/screens/store.lua` | Etiqueta de compatibilidade no painel do port em foco |
| `src/ui/screens/details.lua` | Etiqueta sob a capa, resumo na caixa de texto e **Y** para os detalhes |
| `src/core/catalog.lua` | Mantém os campos `compat` e `attr` do catálogo |
| `src/ui/overlay.lua` | Refaz a análise depois de instalar um port ou atualizar runtimes |
| `src/main.lua` | Detecção na abertura; tela registrada |
| `docs/CATALOGO.md` | Campos de compatibilidade |
| `src/i18n/en.lua`, `ru.lua` | Textos novos |

## Versão 0.2 BETA e varredura do projeto

| Arquivo | Alteração |
|---|---|
| `src/config.lua` | Versão **0.2 BETA** (`C.VERSION_NUM = "0.2"`) |
| `README.md`, `tools/mkart.py`, `port/r36sporthub/cover.png` | Número da versão (a capa foi gerada de novo) |
| `src/threads/install_thread.lua` | `avail` (espaço livre na extração) passou a ser variável local; antes vazava como variável global |
| `src/threads/runtimes_thread.lua`, `src/core/runtimes.lua` | A atualização de runtimes passou a usar o idioma escolhido nas mensagens de andamento (antes sempre em português) |
| `src/ui/screens/about.lua` | O texto "Apoiar" não passa mais da borda do cartão do YouTube em idiomas com palavras longas (em russo, "Abrir canal" ficou "Открыть") |
| `src/i18n/en.lua`, `ru.lua` | Textos que faltavam; entradas repetidas removidas |

## Data e hora

| Arquivo | Alteração |
|---|---|
| `src/core/clock.lua` | **Novo**: hora do sistema nos formatos escolhidos (12/24 h, ordem da data). Lê a diferença para UTC do próprio sistema (`env -u TZ date +%z`) na abertura, depois de trocar o fuso e a cada 10 minutos, porque um programa aberto não percebe a troca de fuso |
| `src/core/datetime.lua` | **Novo**: estado (`timedatectl show`, `/etc/localtime`, RTC, serviço ativo, última sincronização do systemd-timesyncd) e alterações (`timedatectl set-timezone/set-ntp/set-time`; sem timedatectl: link de `/etc/localtime` e `date -s` + `hwclock -w`). Tenta sem sudo e, se negado, `sudo -n`. Fuso validado na base IANA; números de data conferidos |
| `src/threads/datetime_thread.lua`, `src/core/dtjob.lua` | **Novos**: consultas e alterações em segundo plano |
| `src/ui/screens/datetime.lua`, `tzpicker.lua`, `datetime_edit.lua` | **Novas**: tela principal, escolha do fuso (regiões + pesquisa) e ajuste manual |
| `src/ui/settings_defs.lua`, `src/ui/icons.lua` | Opção "Data e hora" (com ícone) em Informações do console; datas exibidas no formato escolhido |
| `src/ui/gfx.lua`, `src/ui/screens/menu.lua`, `consoleid.lua`, `netdiag.lua`, `ftp_activity.lua` | Relógio e datas no formato escolhido |
| `src/main.lua` | Telas registradas; relógio confere o fuso periodicamente |
| `src/i18n/en.lua`, `ru.lua` | Textos novos |

## R36 Control no hub (LED de verdade) e aviso na Data e hora

| Arquivo | Alteração |
|---|---|
| `src/core/r36ctl.lua` | **Novo**: mesmos ajustes e comandos do "R36 Control.sh" do dArkOSRE: perfil do LED de aviso da bateria (`batt_life_warning/*.py` → `/usr/local/bin/batt_life_warning.py` + `batt_led.service`), gama, caminho de áudio (`amixer` + `ogage`), volume ao ligar e o `/etc/r36_config.ini`. Valores conferidos; `sudo -n` |
| `src/threads/r36ctl_thread.lua`, `src/ui/screens/r36control.lua` | **Novos**: execução em segundo plano e a tela |
| `src/ui/settings_defs.lua` | "Ajustes do console (R36 Control)" em Informações do console; "Controle do LED" (Aparência) abre essa tela |
| `src/core/led.lua`, `src/ui/screens/led.lua`, `port/r36sporthub/bin/led_boot.sh` | **Removidos**: usavam `/sys/class/leds`, que não controla o LED do R36S no dArkOSRE (o LED é um GPIO do serviço `batt_led.service`). Na abertura, o hub apaga o serviço `r36sporthub-led` se a versão anterior o tiver criado |
| `src/ui/screens/datetime.lua` | Aviso: com a sincronização ligada, o console acerta a data e a hora sozinho ao ligar com internet |
| `src/main.lua`, `tools/build.sh`, `src/i18n/en.lua`, `ru.lua` | Tela registrada, limpeza do serviço antigo, textos |

## Gerenciador inteligente do PortMaster

- Nova opção **Configurações → Downloads e atualizações → Gerenciar PortMaster** (não há categoria "Sistema"; a grade já está cheia). Opções: Instalar, Atualizar, Verificar instalação, Reparar, Verificar runtimes e Histórico de operações.
- Descoberta pelas fontes oficiais do PortMaster-GUI (`version.json` da release mais recente, o mesmo que o PortMaster usa; API de releases para canal, pre-release e sha256). Só a versão **estável** é instalada; alfa/beta são apenas informadas.
- Fluxo seguro: download temporário → sha256/md5 + teste do ZIP + caminhos + compatibilidade → extração temporária → backup → gravação por rename → md5 de cada arquivo → limpeza. Falhou? O backup é restaurado e conferido.
- Ports, saves, `config/`, temas, `autoinstall/` e `libs/*.squashfs` preservados (conferido ao fim da atualização).
- Runtimes: usa o atualizador existente; o resultado dele aparece na tela.
- Integração com a Central de Downloads (mesma lista, etapas, velocidade e histórico).
- Recuperação na abertura de operação interrompida.
- Arquivos novos: `src/core/pmcore.lua`, `src/core/pmmanager.lua`, `src/threads/pm_thread.lua`, `src/ui/screens/pmmanager.lua`.

## Loja de Temas: reconhecimento, ativação e ThemeMaster

- A loja lê as pastas reais de temas do dArkOS/dArkOSRE (`/roms/themes` via `/etc/emulationstation/themes`, `~/.emulationstation/themes`) e identifica cada tema pelo marcador do hub, `.git/config`, registro do ThemeMaster ou nome da pasta com `theme.xml`.
- Novos estados: ATIVO, INSTALADO, INSTALAÇÃO INCOMPLETA, DISPONÍVEL, NÃO VERIFICADO; origem: do sistema, do usuário, R36S PORT HUB, ThemeMaster.
- "Instalados" mostra todos os temas do console. Tema existente não é baixado de novo; atualização/reinstalação na mesma pasta.
- Ativar: ThemeSet do `es_settings.cfg`, aplicado pelo launcher com o EmulationStation parado (backup + conferência).
- Remover: com confirmação; nunca temas do sistema, o ativo, links ou pastas sem `theme.xml`.
- Catálogo online consultado no máximo a cada 6 h; sem internet, a loja continua com o catálogo conhecido e avisa.
- ThemeMaster analisado e aproveitado (registros, pasta configurada, galeria e imagens locais); interface e binários dele não são usados.
- Arquivo novo: `src/core/esthemes_scan.lua`. Alterados: `src/core/esthemes.lua`, `src/ui/screens/esthemes.lua`, `src/threads/estheme_thread.lua`, `port/R36S PORT HUB.sh`.

## Correção: tela preta ao ativar tema

- Ao ativar um tema, o console ficava parado numa tela preta: o launcher do hub é filho do EmulationStation, e o `systemctl stop emulationstation` encerrava o próprio launcher antes de trocar o tema e iniciar o EmulationStation de novo.
- Agora a troca roda numa unidade separada do systemd (`systemd-run` + `port/r36sporthub/bin/es_theme_apply.sh`), que sempre inicia o EmulationStation no final, mesmo se a troca falhar. O dono e as permissões do `es_settings.cfg` são mantidos.

## Loja de Temas com as fontes do ThemeMaster e escolha do tamanho de tela

- A loja lê a galeria OGA e as coleções do GitHub (as mesmas fontes do ThemeMaster) e junta com o catálogo do hub, sem repetir temas. Atualiza sozinha (no máximo a cada 6 h), com cópia para usar sem internet.
- SELECT: abas Sistema e Tamanho da tela (480x320, 640x480, 854x480, 960x544, 720x720), com quantos temas funcionam e quantos não foram testados em cada uma.
- Cada tema mostra se funciona na tela escolhida; novo filtro Coleções.
- Arquivo novo: `src/core/esgallery.lua`. Alterados: `src/core/esthemes.lua`, `src/ui/screens/esthemes.lua`.

## Registro de erros

- Novo `src/core/errlog.lua`: erros fatais, erros de tarefas em segundo plano e falhas mostradas na tela viram arquivos em `r36sporthub/logs/`, sem senhas, mantendo os 30 mais recentes.
- O launcher guarda o final do `log.txt` quando o app fecha com código de erro.
- Configurações → Informações do console → Registro de erros (quantidade e atalho para a pasta).

## Versão 0.3 BETA, README para o GitHub e guia dos catálogos

- Versão **0.3 BETA** (`C.VERSION_NUM = "0.3"`); capa e fundo da lista de Ports gerados de novo.
- `README.md` novo, para a página do GitHub (ícones, selos, telas, funções, instalação, catálogos). O manual completo anterior foi para `docs/MANUAL.md`.
- `docs/images/`: capa e capturas do simulador usadas no README.
- `GUIA_GITHUB_CATALOGOS.txt`: como publicar no GitHub e ligar ao hub o catálogo de ports/utilitários, a Loja de Temas do EmulationStation, os temas do hub (download ainda não ativo) e a atualização do hub.

## Verificador do cartão SD: classe de velocidade e atalho; varredura

- O Verificador do cartão SD (Utilitários & Ferramentas → Manutenção) continua no projeto e agora também tem atalho em Configurações → Informações do console.
- Nova linha **Classe**: lida do registro SSR do cartão (`/sys/block/mmcblkN/device/ssr`, quando o kernel informa): Classe 2–10, U1/U3, V6–V90, A1/A2. Cartão sem classe declarada vira pista; depois do teste de velocidade, gravação abaixo do mínimo da classe declarada também.
- Varredura: lint de todo o código (sem erros novos), traduções completas (en/ru), 25 telas abertas nos 3 idiomas sem erro, FTP 31/31 e testes do Gerenciador do PortMaster.
- Traduções: confiança da detecção do sistema e tipo do tema (leve/completo) agora traduzidos na Loja de Temas; texto do Verificador do cartão SD não passa mais da borda em russo.

## Desinstalar jogos, gerenciador de arquivos e R36 Control

- Meus Ports: "Excluir" virou **Desinstalar**. Além do registro do hub, port.json, .port e GAMEDIR, a pasta do jogo agora também é encontrada quando o script a cita de outra forma (`cd /roms/ports/...`, `gamedir=`, `PORTDIR=`) ou quando tem o mesmo nome do script. Sem pasta encontrada, só o script é removido (avisado na confirmação). A confirmação lista exatamente o que será apagado e como foi identificado; as proteções continuam (itens do sistema, pastas usadas por outro jogo, pastas montadas).
- Gerenciador de arquivos: **Colar nesta pasta** e **Colar dentro de <pasta>** no menu de opções (também com a pasta vazia, pelo item "voltar"); **Instalar como port** também para uma pasta já extraída com script `.sh` na raiz (copia para a pasta de ports, nunca sobrescreve, desfaz se falhar).
- Ajustes do console (R36 Control): só em Aparência e personalização (saiu de Informações do console).

## Transmissão e gravação da tela do hub

- Configurações → Rede e conectividade → **Transmissão e gravação** (`ui/screens/streamrec.lua`, `ui/screens/recordings.lua`).
- Captura só do canvas 640x480 do hub (`core/screencap.lua`); o canvas próprio só existe enquanto algo é capturado. Indicadores AO VIVO/REC desenhados depois da captura (não entram no vídeo).
- Codificação por blocos 32x32, só os que mudaram, RGB + zlib (`lib/tilecodec.lua`, LuaJIT FFI).
- Transmissão: servidor HTTP próprio em thread (`threads/stream_thread.lua`, `core/stream.lua`), portas 8090–8099, código aleatório por sessão, só endereços privados, Host numérico, só GET, sem arquivos, até 3 visualizadores, cliente lento recebe quadro completo quando alcança. Página com CSP restrita, somente visualização, reconexão e aviso de encerramento.
- Gravação: `threads/rec_thread.lua`, `core/recorder.lua`, `core/recordings.lua`. MP4 via ffmpeg (libx264 ultrafast ou mpeg4, MP4 fragmentado: o arquivo continua legível se o console desligar). Sem ffmpeg: `.r36rec` + `tools/converter_gravacao.html` (copiada para a pasta das gravações). Pausa sem contar o tempo pausado; para sozinha com o cartão quase cheio; finaliza ao sair do app.
- A atualização do hub não toca em `gravacoes/` nem `logs/`.
- Testes (simulador): página e fluxo por cliente Python (11/11: código errado 404, POST 405, Host por nome 400, quadros completos, aviso de encerramento) e pelo Chromium (imagem idêntica à tela, aviso ao encerrar); MP4 de 5 s conferido com ffprobe; .r36rec conferido e convertido para WebM no Chromium; pausa; telas nos 3 idiomas; FTP 31/31; Gerenciador do PortMaster.
- Não testado no R36S: custo da leitura do canvas na GPU Mali, presença do ffmpeg no dArkOSRE e uso de CPU da gravação MP4.

## Gerenciador de atualizações (0.4 BETA)

- Versão **0.4 BETA**. Configurações → Downloads e atualizações → **Atualizações** (substitui "Atualização do sistema"): Atualização local, Atualização via rede, Versão atual, Histórico e Gerenciar backups.
- Pasta `r36sporthub/update/` (criada com `LEIA-ME.txt`). Formatos ZIP/7Z/RAR identificados pelos primeiros bytes; ferramentas testadas no console (7-Zip do hub, 7z/7zz/7za, unzip, unrar).
- Módulos: `core/updater/` (manager, folder, formats, rules, integrity, backup, history), `threads/updater_thread.lua` (probe, analyze, install, restore, download), telas `updmgr`, `upd_local`, `upd_pkg`, `upd_history`, `upd_backups`; `ui/screens/update.lua` virou a Atualização via rede e usa o mesmo instalador. `threads/update_thread.lua` (instalador antigo) removido.
- Manifesto `update_manifest.json` com SHA-256 por arquivo; pacote completo sem manifesto aceito com identificação parcial (versão lida do `game.love`).
- Backup por atualização (3 mais recentes), diário `backups/.journal` e recuperação no lançador (instalação interrompida ou versão nova que não abre). `.restart_app` reabre o hub.
- `tools/make_update.py` (manifesto completo no build, base da versão entregue e ZIP incremental); `docs/ENTREGAS.md` com a regra de entrega.
- Testes (simulador, 7-Zip x64 no lugar do 7zzs arm64): ZIP, ZIP com pasta, 7Z, RAR (leitura), pacote completo sem manifesto, caminho `../` e `conf/` recusados, link recusado, versão incompatível, arquivo corrompido, arquivo que não é pacote, SHA-256 errado (mesmo tamanho), falha simulada no meio da instalação (restaurado), instalação, restauração de backup, download pela rede com SHA-256, confirmação na abertura, aviso de recuperação e restauração pelo lançador (interrompida e versão que não abre; backup inválido ignorado).
- Não testado no R36S: o `7zzs` arm64 do hub executando a partir de `/tmp`, e o ciclo real do lançador com o runtime do PortMaster.

## Novidades de cada atualização

- Manifesto com `changes` (o que mudou) e `fixes` (o que foi corrigido), além de `description`.
- Antes de instalar: a análise do pacote mostra quantas mudanças e correções há; Y abre a lista. Depois de instalar, Y também.
- Na primeira abertura da versão nova (depois do aviso inicial) abre sozinha a tela **Novidades** (`ui/screens/upd_notes.lua`, com rolagem). Se a atualização foi instalada por uma versão do hub que ainda não guardava as notas, a versão nova as lê do manifesto do pacote na pasta `update`.
- O Histórico guarda as notas; Y mostra as novidades da atualização selecionada.
- `tools/make_update.py incremental` aceita `--mudanca`, `--correcao` e `--notas`.
- Testado no simulador: notas na análise, depois da instalação, na primeira abertura (com e sem o arquivo de notas) e traduções.

## Tamanho do texto e conferência do modo econômico (0.4.1 BETA)

- **Configurações → Aparência e personalização → Tamanho do texto**: Pequeno, Padrão, Grande e Muito grande (esquerda/direita; A avança e volta ao começo). Vale na hora, sem reiniciar, e fica em `settings.txt` (`font_size`), que já entra no Backup e restauração.
- Só as fontes de texto (Chakra Petch e o cirílico da Inter) mudam: Pequeno −1 px, Grande +2 px, Muito grande +3 px. As fontes pixeladas (logo, etiquetas, botões, títulos em pixel) ficam fixas, porque só ficam nítidas no tamanho original.
- Para não haver texto sobreposto ou saindo da tela (`ui/gfx.lua`, `ui/theme.lua`):
  - quando um texto não cabe no espaço reservado, a fonte diminui sozinha, de 1 em 1 px, até o tamanho padrão; se ainda não couber, é encurtado com "…" (`G.fit`, `G.text_fit`, `G.text`, `G.fit_lines`);
  - caixas de texto com largura nunca usam mais linhas do que o tamanho padrão usaria;
  - linhas de lista com título e texto menor embaixo (`G.row_fonts`), espaçamentos fixos entre linhas (`G.step`), dicas do rodapé, cabeçalho, diálogos (os botões em lista crescem; o corpo diminui ou é encurtado para a janela caber na tela), descrições das Configurações e cartões da central de Configurações se ajustam;
  - telas de painel com posições fixas e muita informação ficam sempre no tamanho padrão: Servidor FTP, Transmissão e gravação, Loja de Temas do EmulationStation, análise de pacote de atualização, resultado do R36S Analog Tester, compatibilidade do port, painéis de progresso (instalação, runtimes, desinstalação), cartão do YouTube em Sobre o projeto e faixa do cartão no Analisador do cartão SD.
- No tamanho Padrão o visual não muda (comparação de capturas com a 0.4: só a tela Aparência, com a linha nova, ficou diferente). Exceção pequena: na central de Configurações, a descrição que não cabe em 2 linhas agora termina com "…".
- Ajustes pontuais para texto maior: rótulos das tabelas (FTP, transmissão, PortMaster, Informações do console, Atualizações, Diagnóstico de rede), nome do idioma ao lado de EM USO, lista de temas do hub, itens do Gerenciador de atualizações, rodapé do menu principal (dicas + rede + bateria).
- **Modo econômico conferido**: limita a tela a 20 quadros por segundo (normal: 30) e desliga as animações decorativas. Medido no simulador (Xvfb, desenho por software): menu principal 30,3 → 20,1 quadros/s e processador 29,9% → 19,8%; Central de Downloads 30,3 → 20,1 quadros/s e 27,6% → 19,2%. A preferência salva é lida ao abrir o app.
- Corrigido no modo econômico: três pulsos ainda animavam com o modo ligado (moldura da etapa atual nos painéis de instalação e de runtimes, botão do aviso inicial). Agora param junto com as outras animações. Barras de "carregando", cursor de texto e aviso de bateria crítica continuam, porque mostram estado.
- Arquivos: `src/ui/theme.lua`, `src/ui/gfx.lua`, `src/main.lua`, `src/ui/settings_defs.lua`, `src/ui/icons.lua`, `src/ui/overlay.lua`, `src/i18n/en.lua`, `src/i18n/ru.lua`, `src/dev/autotest.lua` e as telas `about`, `consoleid`, `compat`, `console`, `disclaimer`, `esthemes`, `ftp`, `integrity`, `language`, `menu`, `netdiag`, `pmmanager`, `recordings`, `sdanalyzer`, `settings`, `settings_cat`, `streamrec`, `tester`, `themes`, `upd_backups`, `upd_history`, `upd_local`, `upd_pkg`, `updmgr`, `wifi` e `ui/portrow.lua`.
- Testado no simulador (LÖVE 11.5, 640x480): 55 telas e diálogos capturados em Padrão e Muito grande (pt-BR), Muito grande em russo e Pequeno em inglês. Não testado no R36S real.

- Entregue como atualização incremental `R36S-PORT-HUB-update-0.4.1.zip` (só `r36sporthub/game.love`; versão mínima 0.4). Testado no simulador: análise e instalação pela Atualização local de um hub 0.4 (SHA-256 conferido, backup criado) e abertura da 0.4.1.

## Avisos do registro de erros (0.4.2)

- Tarefa em segundo plano que falha (`love.threaderror`): além de gravar o registro em `r36sporthub/logs/`, mostra um aviso rápido de erro que aponta para Configurações > Informações do console > Registro de erros. No máximo um aviso a cada 10 s; respeita a opção Alertas e erros das Notificações.
- **Corrigido**: a tela de erro fatal nunca aparecia. `main.lua` guardava `love.errorhandler` como tela padrão, mas no LÖVE 11.5 ela se chama `love.errhand` nesse momento; o tratador de erro falhava e o hub simplesmente fechava (o registro já era gravado antes). Agora a tela aparece, com o caminho do registro salvo.
- A tela de erro padrão do LÖVE só fechava com Esc (teclado). Agora fecha com START (ou qualquer botão de um controle sem mapeamento), depois de 1 s.
- Textos novos traduzidos (en, ru). Arquivos: `src/main.lua`, `src/i18n/en.lua`, `src/i18n/ru.lua`, `src/dev/autotest.lua` (comando `errscreen`).
- Testado no simulador: aviso em pt-BR e ru, aviso repetido suprimido dentro de 10 s, registro gravado em cada falha, tela de erro fatal desenhada com o caminho do registro e a instrução do START. Não testado: fechar a tela de erro com START (o simulador não tem controle) e o comportamento no R36S real.

## Central de Conteúdo e BIOS do Sistema (0.4.2)

- "Loja de Ports" virou **Central de Conteúdo** (menu: "Jogos, BIOS, utilitários e ferramentas"; no topo da Central: "Ports de Jogos, BIOS, Ports Utilitários e Ferramentas"). Três cartões: Ports de Jogos, **BIOS do Sistema** e Ports Utilitários e Ferramentas. Ids internos sem mudança (`store`, `games`, `tools`): favoritos, catálogo, histórico e atalhos seguem iguais. Novo apelido de seção no catálogo: `ports_utilitarios_e_ferramentas`.
- **BIOS do Sistema** (`core/bios.lua`, `core/bios_ref.lua`, `core/bios_db.lua`, `threads/bios_thread.lua`, telas `bios`, `bios_list`, `bios_pkg`, `bios_hist`): pasta pelo `retroarch.cfg` (ou o padrão documentado do dArkOS), tabela de pastas da wiki do ArkOS, reconhecimento pelo MD5 do `System.dat` do libretro (v1.19.0, commit 764ef77a9f52, 519 entradas), estados reais, download pela Central de Downloads (entrada externa, sem gerenciador novo), análise com extração temporária, instalação com backup, diário e conferência do MD5, restauração, recuperação na abertura e limpeza só do que o hub registrou.
- Central de Downloads: duas mudanças que só valem para entradas novas: `download_only` (download sem etapas de extração/instalação) e `screen` (A abre a tela da operação; o PortMaster continua abrindo a dele).
- Proteções: `r36sporthub/bios/` e `bios_url.txt` entram nas pastas de dados que nenhuma atualização substitui (`core/updater/rules.lua`, lançador e `tools/make_update.py`).
- `config.lua`: `C.BIOS_URL` fica vazio (o link do pacote é configurado em `bios_url.txt`, no cartão). `tools/mkbiosdb.py` + `tools/ref/System.dat` regeneram o banco de hashes.
- Testado no simulador (servidor local, pacote ZIP de teste com arquivos falsos e banco de teste via `PORTHUB_BIOS_TESTDB`): consulta da fonte, download com progresso na Central de Downloads, análise (reconhecida, nome conhecido, tamanho errado, duplicada, documento, não reconhecida, pasta de ROMs ausente, nome com maiúsculas diferentes no exFAT), instalação com subpasta `dc/` e cópia em ROMs/neogeo, substituição com backup, falha simulada no 4º arquivo (tudo desfeito, pasta criada removida), recuperação de instalação interrompida na abertura, restauração de backup, limpeza; telas em pt-BR, en, ru e Muito grande.
- **Não testado**: o pacote real de BIOS (o servidor de origem não é acessível daqui), extração de RAR (o simulador não tem 7-Zip/unrar), a leitura do `retroarch.cfg` e as pastas reais do dArkOSRE, e o R36S real.

- Entregue como `R36S-PORT-HUB-update-0.4.2.zip` (lançador + `game.love`; versão mínima 0.4). Corrigido no `tools/make_update.py`: o `update_manifest.json` ia sem permissões Unix e o leitor do hub desalinhava os tamanhos dos outros arquivos do pacote (o leitor em `core/updater/formats.lua` também passou a aceitar esse caso). Testado: análise e instalação pela Atualização local do hub 0.4, SHA-256 conferidos e abertura da 0.4.2.

## Atualização local, desinstalação e análise da bateria (0.4.3 BETA)

- **Atualizações**: depois de instalar com sucesso, o hub pergunta se quer excluir ou manter o arquivo de atualização (só aquele arquivo; nunca a pasta `update`).
- **Meus Ports**: a confirmação de desinstalação mostra o arquivo de inicialização (`.sh`) e a pasta do jogo que serão removidos.
- **Meus Ports**: se a pasta do jogo não for localizada, Y abre um navegador de pastas para escolher a pasta manualmente (só pastas dentro da pasta de ports; protegidas e links são recusados).
- Nova **Análise da bateria** (Informações do console): nível, estado, tensão, corrente, capacidade e carregador, com o tempo estimado para a carga completa calculado com os dados reais do sistema.
- **Corrigido**: no aviso importante, com letra grande o texto ficava cortado. Agora ele rola com o direcional e o botão PARA CONTINUAR fica sempre visível.
- **Corrigido**: na desinstalação, o registro do jogo só é removido quando todos os arquivos foram apagados; se os arquivos já não existirem, dá para só limpar o registro.
- Entregue como `R36S-PORT-HUB-update-0.4.3.zip` (só `r36sporthub/game.love`; versão mínima 0.4).

## Catálogo online oficial de ports (0.4.4 BETA)

- O hub agora busca o catálogo oficial de ports no GitHub do projeto (`ports.json`). Sem internet, usa o último catálogo baixado.
- URL em `src/config.lua` (`C.CATALOG_URL`) e cópia publicada em `ports.json`, na raiz do repositório.
- Entregue como `R36S-PORT-HUB-update-0.4.4.zip` (só `r36sporthub/game.love`; versão mínima 0.4).

## Link oficial de atualização e botão INSTALAR (0.4.5 BETA)

- O botão do port não instalado agora diz **INSTALAR** (antes BAIXAR).
- Atualização via rede ligada ao link oficial do projeto no GitHub (última Release). O hub lê a versão, as mudanças e as correções direto do pacote, sem baixar tudo.
- Atualização via rede: **Y** mostra as novidades completas antes de baixar.
- **Corrigido**: erro "Download incompleto: o tamanho do arquivo não confere" em ports cujo tamanho no catálogo é arredondado; agora vale o tamanho informado pelo servidor.
- Entregue como `R36S-PORT-HUB-update-0.4.5.zip` (lançador auxiliar `fetch.sh` + `r36sporthub/game.love`; versão mínima 0.4).

## Varredura de erros e traduções (0.4.6 BETA)

- Varredura: sintaxe de todos os 151 arquivos Lua, JSON, scripts .sh e
  gameinfo.xml; todas as chaves usadas em L() conferidas em en/ru;
  marcadores (%s, %d) e quebras de linha das traduções; abertura de todas as
  telas e categorias de Configurações em pt-BR, en e ru no simulador,
  procurando erros, texto em português sobrando e variáveis globais.
- Corrigido `lib/i18n.lua`: em pt-BR, um texto que já é chave em português
  podia ser trocado por outra chave com a mesma tradução em inglês
  ("Download" aparecia como "Baixar"; "Data" como "Dados"). Agora a chave em
  português sempre fica como está.
- Corrigido en: "Dados" (taxa da transmissão) era traduzido como "Data", que
  ao desenhar virava "Date". Agora "Data rate".
- ru: "Runtime" padronizado como "Рантайм" (antes "Среда", que também é
  "quarta-feira"); "Runtimes instalados" → "Установленные рантаймы".
- en: adicionadas as chaves "RUNTIMES" e "Runtime " (só existiam em ru).


## Vitrine EM DESTAQUE animada (0.4.6 BETA)

- Mesma caixa da tela inicial (posição, tamanho, borda, fundo e título
  iguais; conferido pixel a pixel que o resto da tela não mudou).
- Seleção só pelo catálogo: entram apenas itens com `"featured": true`,
  jogos e utilitários na mesma sequência, na ordem do catálogo ou pelo novo
  campo opcional `featured_order`. Acabou o preenchimento automático com os
  primeiros ports quando não havia destaques: agora aparece "Nenhum destaque
  no catálogo.". Depois de atualizar o catálogo, a lista é refeita (itens
  novos entram, removidos saem) e continua no mesmo item se ele seguir em
  destaque. Offline usa o catálogo e as capas em cache.
- Cada item: capa, nome, etiqueta JOGO/UTILITÁRIO (as mesmas cores da página
  do port), categoria e tamanho (o tamanho desce uma linha quando não cabe) e
  contador 2/4 no canto.
- Animação: saída deslizando e esmaecendo, entrada pelo lado oposto, brilho
  discreto que atravessa a capa ao chegar, moldura pulsando na cor do tipo e
  indicadores animados (o atual alarga e enche conforme o tempo até a próxima
  troca). Uma troca por vez; troca a cada 5 s.
- Esquerda/direita (ou L1/R1) no menu trocam o destaque e pausam a rotação
  por 8 s. A capa do próximo item é pedida antes (cache de capas).
- Animações desligadas ou modo econômico: sem rotação automática (como diz a
  opção Animações da interface) e troca manual instantânea, sem brilho.
- Arquivos: `ui/screens/menu.lua`, `core/catalog.lua` (`featured_order`),
  `i18n/en.lua`, `i18n/ru.lua`, `docs/CATALOGO.md`, `docs/MANUAL.md`.
- Testado no simulador: um e vários jogos, utilitários, alternância jogo ↔
  ferramenta, indicadores, capas, item sem capa, nenhum destaque, catálogo
  offline (cache), atualização do catálogo com destaque removido e novo
  utilitário, temas Padrão e Xbox, pt-BR/en/ru, texto Grande e Muito grande,
  modo econômico e animações desligadas.

## Correção: BIOS do Sistema fechava o hub sem link configurado (0.4.6 BETA)

- Erro relatado no R36S: ao abrir **BIOS do Sistema**, o hub fechava com
  `ui/gfx.lua:70: bad argument #1 to 'getWidth' (string expected, got nil)`.
- Causa: na versão publicada o link do pacote de BIOS fica vazio no código
  (`C.BIOS_URL = ""`, configurado no cartão em `bios_url.txt`). A tela tentava
  tirar o nome e o servidor de um link vazio.
- Correção (`ui/screens/bios.lua`, `core/bios.lua`): sem link, o painel mostra
  "Fonte não configurada" e onde colocar o link; "Baixar pacote de BIOS"
  mostra um aviso com o caminho do `bios_url.txt` e não inicia nada
  (`Bios.url_ok()`; a thread também recusa consultar ou baixar sem link).
  Textos novos traduzidos em en/ru.
- Testado no simulador: tela de BIOS sem link e com link no `bios_url.txt`;
  varredura de todas as telas em pt-BR/en/ru sem erros.
- Link oficial do pacote de BIOS definido no código:
  `C.BIOS_URL = https://archive.org/download/bios-r-36s/Bios%20r36s.rar`
  (o `bios_url.txt` no cartão continua podendo trocar o link).

## Capa dos jogos na lista de Ports do sistema (0.4.6 BETA)

- Antes a capa só aparecia dentro do hub. Agora, ao instalar um port do
  catálogo, o hub copia a capa do catálogo para a pasta do jogo
  (`<id>-cover.png/.jpg`; `ports/images/` se o port não tiver uma pasta só)
  e põe o jogo no `/roms/ports/gamelist.xml` do EmulationStation com nome,
  descrição, gênero, `image` e `thumbnail`. Sem capa no catálogo, usa a
  `cover.png`/`screenshot.png` do próprio port.
- Entrada já existente: só completa `image`/`thumbnail` que faltam; nada do
  usuário, do PortMaster ou de scrapers é trocado; outros jogos não são
  tocados; cópia de segurança `gamelist.xml.porthub.bak` e gravação atômica.
- O que foi feito fica no `installed.json`; a desinstalação pelo hub remove a
  entrada que o hub criou (ou só as tags de imagem que ele acrescentou) e a
  imagem copiada. Reinstalar recoloca a imagem.
- A mensagem de instalação avisa que o jogo aparece com a capa depois de
  reiniciar o EmulationStation.
- Arquivos: `core/esgamelist.lua` (`add_port`, `remove_port`),
  `core/installer.lua`, `core/uninstall.lua`, `core/covers.lua`
  (`disk_file`, `fetch_file`), `ui/overlay.lua`, `i18n/en.lua`, `i18n/ru.lua`.
- Testado no simulador: gamelist.xml com outros jogos (preservados e
  backup igual ao original), jogo novo com capa do catálogo, jogo sem capa no
  catálogo com cover.png própria, jogo com entrada do usuário sem imagem (só
  imagem acrescentada), reinstalação recolocando a capa apagada, desinstalação
  removendo só o que o hub criou; XML válido. Não testado no
  EmulationStation real do R36S.

## QR Code ampliado em Sobre o Projeto (0.4.6 BETA)

- Nas janelas **Apoie o projeto** (PIX) e **Canal do YouTube**, o botão A
  abre o QR Code em tela cheia (fundo branco, módulos maiores). A ou B
  voltam. Arquivo:
  `ui/screens/about.lua` (+ textos em en/ru).

## Correções da gravação e do atualizador; gravação a 30 FPS (0.4.6 BETA)

- **Gravação fechava com erro** (`threads/rec_thread.lua:93: attempt to index
  local 'img' (a nil value)`, relatado no R36S): a thread lia dois quadros
  seguidos e, quando o primeiro vinha vazio e o segundo chegava no meio,
  tentava liberar um quadro inexistente. Corrigido: só descarta quadros
  antigos quando o primeiro existe.
- **Gravação falhava sem explicar** (`Gravação: falha nil nil`): o fim da
  gravação agora informa quantos quadros chegaram e quantos foram ao ffmpeg,
  e a tela mostra "Nenhum quadro da tela chegou à gravação." quando for o caso.
- **Quadros da gravação**: 10, 15 ou 30 FPS. Ao escolher 30 aparece um aviso
  (usa mais o processador; no modo econômico a tela vai até 20 FPS).
- **Hub fechava depois de instalar uma atualização** (`core/updater/manager.lua:85:
  Could not read from file.`, relatado no R36S): depois de trocar o
  `game.love`, o app em execução não consegue mais ler o próprio pacote; ao
  voltar e abrir a Atualização local ele fechava. Agora, depois de instalar
  (ou restaurar um backup), A ou B reiniciam o app, e o gerenciador recusa
  novas operações até reiniciar.
- Varredura de traduções e de todas as telas em pt-BR/en/ru: sem erros novos.
- Arquivos: `threads/rec_thread.lua`, `core/recorder.lua`,
  `ui/screens/streamrec.lua`, `core/updater/manager.lua`,
  `ui/screens/upd_pkg.lua`, `ui/screens/upd_backups.lua`, `i18n/en.lua`,
  `i18n/ru.lua`, `docs/MANUAL.md`.

## Central de Configurações (0.4.7 BETA)

- A tela de Configurações passou de 9 para 18 categorias, em grade com
  rolagem (L1/R1 mudam de página, contador n/18 no rodapé). Novas categorias:
  Preferências, Idiomas, Catálogo de ports, Meus Ports, Servidor FTP,
  Favoritos e jogos, Atualizações do hub, Ferramentas, Diagnóstico e suporte e
  Sobre o projeto. Opções que já existiam foram reagrupadas, nenhuma foi
  removida.
- Novidades: tela ao abrir, comportamento do B no menu principal, restaurar
  preferências e aparência, atualização automática do catálogo (liga/desliga) e
  data da última atualização, ordenação das listas e dos favoritos, limpar cache
  de capas, avisos de downloads em segundo plano, repetir downloads com falha,
  espaço ocupado por port, instalações incompletas, verificação dos
  repositórios, histórico de erros de comunicação, avisos do FTP, jogos
  acessados recentemente, componentes do hub, exportar/importar configurações
  no cartão, histórico de backups, diagnóstico do aplicativo com relatório para
  o suporte, licenças e aviso importante em modo leitura.
- Segurança: confirmações de exclusão, desinstalação, restauração e
  atualização continuam obrigatórias. Comandos de verificação rodam em segundo
  plano e só leem arquivos. A senha do FTP nunca vai para exportações ou
  relatórios.
- Comunidade: por enquanto só o canal do YouTube; o link do grupo entra numa
  próxima versão.
- Arquivos novos: `core/netlog.lua`, `core/shjob.lua`, `threads/shjob_thread.lua`,
  `core/diag.lua`, `ui/screens/infolist.lua`, `ui/settings_extra.lua`.
  Alterados: `ui/settings_defs.lua`, `ui/screens/settings.lua`, `ui/icons.lua`,
  `core/backup.lua`, `core/errlog.lua`, `ui/screens/disclaimer.lua`, `main.lua`,
  `ui/screens/menu.lua`, `ui/overlay.lua`, `core/ftp.lua`, `core/downloads.lua`,
  `ui/screens/store.lua`, `core/update.lua`, `i18n/en.lua`, `i18n/ru.lua`.

## Tela inicial: rodapé da rede e troca do destaque (0.4.7 BETA)

- O rodapé mostra só o ícone do Wi-Fi: verde quando conectado, vermelho
  riscado quando desconectado e amarelo enquanto verifica. O IP continua em
  Configurações > Rede e conectividade.
- EM DESTAQUE troca manualmente só com L1/R1. Direcional e analógicos não
  mudam mais o destaque. Os ícones L1 e R1 aparecem na parte de baixo da caixa,
  ao lado dos indicadores.
- Arquivo: `ui/screens/menu.lua`.

## Aviso de versão nova na tela inicial (0.4.7 BETA)

- Ao abrir o hub, depois que a rede responde, o hub consulta em segundo plano o
  link oficial de atualização (lê só o começo do pacote, cerca de 256 KB).
- Se houver versão maior que a instalada, aparece no alto da tela inicial, entre
  a logo e a data, uma faixa com texto deslizante: versão nova disponível e como
  atualizar. O texto passa, some e recomeça. Com as animações desligadas, fica
  parado.
- SELECT na tela inicial abre a Atualização via rede, e o rodapé mostra a dica.
  Nada é baixado ou instalado sozinho.
- O aviso some depois de atualizar e reiniciar. Sem internet, ou com o link fora
  do ar, não aparece nada.
- Liga/desliga: Configurações > Atualizações do hub > Avisar quando sair versão
  nova (chave `upd_notify`, ligado por padrão).
- Arquivos: `core/updnotice.lua` (novo), `ui/screens/menu.lua`, `main.lua`,
  `ui/settings_extra.lua`, `i18n/en.lua`, `i18n/ru.lua`.

## NEON GRID — Gaming Dashboard (0.4.7 BETA)

- O tema verde e preto (id `xbox`, "Tema Xbox") virou **NEON GRID — Gaming
  Dashboard**, com identidade própria: nome, descrição, cores (verde neon
  #39ff88 sobre quase preto), fundo `neongrid` (grade em perspectiva e
  horizonte iluminado) e pré-visualização nova. Nenhuma marca ou recurso de
  terceiros. A pasta passou de `themes/xbox/` para `themes/neongrid/`.
- Migração: `theme.txt` com `xbox` (inclusive vindo de backup/exportação) é
  aplicado como `neongrid` e regravado. Ao voltar para a 0.4.6 pelo backup, o
  hub abre com o Tema Padrão (com aviso) e as preferências continuam.
- Com o NEON GRID, a tela inicial vira um dashboard (destaque, atalhos, jogos
  recentes, novidades do catálogo, painel lateral com SELECT) e a página do
  port ganha grade de informações e as ações Instalar/Iniciar/Remover/Favoritar.
  O Tema Padrão continua com as telas clássicas.
- **Iniciar** (novo): o hub grava `conf/.run_port` e fecha; o launcher aceita
  só um `.sh` existente na raiz da pasta de ports (sem `/` nem `..`), roda com
  `XDG_DATA_HOME`, `LD_LIBRARY_PATH` e `SDL_GAMECONTROLLERCONFIG` originais e
  sem as variáveis do hub e, ao sair do jogo, reabre o hub na página do port.
- Arquivos: `themes/neongrid/` (theme.json e preview.png novos; logos mantidas),
  `core/themes.lua` (aliases e migração, `style.layout`), `ui/gfx.lua` (fundo
  `neongrid`), `ui/neon_dash.lua` (novo), `ui/screens/menu.lua`,
  `ui/screens/details.lua`, `ui/icons.lua` (ícones set_store, set_grid,
  set_exit), `main.lua` (Iniciar, volta do jogo, migração na restauração),
  `R36S PORT HUB.sh` (`.run_port`), `ui/screens/themes.lua`, `i18n/en.lua`,
  `i18n/ru.lua`, `docs/TEMAS.md`, `docs/MANUAL.md`, `README.md`,
  `GUIA_GITHUB_CATALOGOS.txt`.

## Iniciar também no Tema Padrão (0.4.7 BETA)

- A página do port no Tema Padrão ganhou o botão **INICIAR** entre o botão
  principal e VOLTAR. Ele só aparece quando o port está instalado e tem script
  `.sh` na pasta de ports. Usa o mesmo fluxo do NEON GRID (confirmação,
  `conf/.run_port`, volta para a página do port).
- Com três botões, todos usam a fonte pixelada menor quando algum texto não cabe.
- Arquivo: `ui/screens/details.lua`.

## Biblioteca de jogos — etapa 2 do R36 Hub OS (0.4.8 BETA)

- Nova Biblioteca de jogos: lê o `es_systems.cfg` do console (126 sistemas no
  dArkOSRE-R36), procura as ROMs em segundo plano (`find`, até 3 níveis), usa o
  `gamelist.xml` para nome, capa e informações e abre o jogo com o mesmo comando
  do EmulationStation, pelo launcher (`conf/.run_game`), com o hub fechado.
  Volta para a biblioteca no mesmo sistema ao sair do jogo.
- Escolha de emulador/core por sistema e por jogo, favoritos e recentes próprios.
- Menu clássico com 8 itens (passo de 44 px); NEON GRID com 8 atalhos (2x4) e
  Biblioteca no painel lateral.
- Arquivos: `core/library.lua`, `ui/screens/library.lua`,
  `ui/screens/library_games.lua` (novos); `main.lua` (abrir jogo, volta, bloqueio
  comum com o Iniciar), `ui/screens/menu.lua`, `ui/neon_dash.lua`,
  `R36S PORT HUB.sh` (`.run_game`), `config.lua` (0.4.8), `i18n/en.lua`,
  `i18n/ru.lua`, `docs/MANUAL.md`.

## Modo R36 Hub OS no hub (0.4.8 BETA)

- Quando o supervisor do R36 Hub OS abre o hub (variável `R36HUBOS=1`), o hub
  vira a interface principal: o B do menu e o item "Sair" viram **Energia**
  (Reiniciar a interface, Reiniciar console, Desligar console), "Reiniciar
  lista" some, a versão mostra "R36 Hub OS x.y • 0.4.8 BETA" e o NEON GRID
  mostra "R36 HUB OS" no cabeçalho.
- O launcher (`R36S PORT HUB.sh`) agora sai com o código do app (o supervisor
  usa para contar falhas), não reinicia o EmulationStation no modo R36 Hub OS e
  aceita `--restaurar-ultimo-backup` (usado pelo menu de recuperação).
- Rodando como port no dArkOSRE normal, nada muda.
- Arquivos: `config.lua`, `ui/screens/menu.lua`, `ui/neon_dash.lua`, `main.lua`,
  `ui/overlay.lua`, `R36S PORT HUB.sh`, `i18n/en.lua`, `i18n/ru.lua`.

## Configurações reorganizadas (0.4.8 BETA)

- Cada opção ficou num cartão só, sem repetição. 17 cartões: Preferências,
  Aparência, Áudio, Rede, Servidor FTP, Catálogo, Downloads, Meus Ports,
  **Armazenamento** (novo), Bateria e energia, Controles, Informações do console,
  Atualizações do hub, PortMaster e runtimes, Backup, Diagnóstico e suporte e
  Sobre o projeto.
- Removidos: o cartão Idiomas (o idioma fica em Preferências; A abre a tela de
  escolha com as bandeiras, a mesma da primeira abertura) e o cartão Favoritos e jogos (favoritos e ordenação foram para
  Meus Ports e Catálogo; a lista de jogos acessados do ES saiu, a Biblioteca tem
  Recentes).
- Armazenamento reúne o cartão microSD (espaço de cada cartão), a memória RAM, o
  espaço ocupado pelos ports, o cache de capas, o Gerenciador de arquivos, o
  Otimizador do microSD e o Verificador do cartão SD, que saíram dos outros cartões.
- Informações do console ficou só com o que identifica o aparelho; a Análise da
  bateria foi para Bateria e energia, e rede e cartão SD saíram dela.
- Rede ficou com as linhas principais; interface, gateway e DNS continuam no
  Diagnóstico de rede.
- Ferramentas virou "PortMaster e runtimes"; Componentes do hub ficam só no
  Diagnóstico e o Verificador de integridade só em Meus Ports. O Gerenciador de
  atualizações (que repetia as outras opções) saiu do cartão Atualizações.
- Novas opções em Preferências: **Posição das notificações** (4 posições, com
  exemplo na hora) e **Aviso de nova versão do hub** (liga/desliga).
- Registro de erros: abre um leitor de texto no arquivo mais recente (rolagem,
  L1/R1 por página, esquerda/direita troca de arquivo) e B volta para
  Diagnóstico e suporte.
- Gerenciador de arquivos: nova opção **Copiar** (X ou A no item). Y ou
  Opções > Colar cola a cópia na pasta aberta; na mesma pasta ela ganha o nome
  "(cópia)". Nunca sobrescreve, confere o espaço livre e apaga só a cópia
  incompleta se falhar. Não cola dentro da pasta do hub.
- Arquivos: `ui/settings_defs.lua`, `ui/settings_extra.lua`, `ui/overlay.lua`,
  `ui/icons.lua` (set_storage), `ui/screens/files.lua`,
  `threads/fileop_thread.lua`, `ui/screens/textview.lua` (novo), `main.lua`,
  `i18n/en.lua`, `i18n/ru.lua`.

## Catálogo: nova tentativa automática (0.4.8 BETA)

- Se o catálogo online falhar na abertura sem o usuário ter pedido (ex.: o Wi-Fi
  ainda conectando), o hub tenta de novo sozinho a cada 20 s, só com a rede
  conectada, até 3 vezes, sem mostrar avisos. Para quando o catálogo online
  carrega ou quando "Atualizar ao abrir o hub" está desligado.
- O estado "Offline (cache)" virou "Cache (último baixado)": ele só quer dizer
  que o catálogo em uso é o último baixado, não que o console está sem rede.
- Arquivos: `main.lua`, `core/catalog.lua`, `i18n/en.lua`, `i18n/ru.lua`.



## 0.5.0 BETA — Redesign: Wii Blue Edition + Neon Grid Edition

- **Pastel Pop Edition** (novo, padrão na primeira abertura, tema claro): inspirado nos menus do 3DS e do Wii U — moldura em degradê azul e roxo, fundo claro pontilhado com formas pastel, cartões brancos com bordas coloridas que saltam ao selecionar, barras em pílula e **tela inicial em carrossel** (`ui/carousel.lua`) com balão de informações do canal.
- Pastel Pop: tela inicial sem o EM DESTAQUE (os outros temas mantêm).
- **Vitrine de capas** no Pastel Pop (`ui/coverview.lua`): listas de Ports de Jogos/Utilitários, Meus Ports, Favoritos e jogos da Biblioteca com fundo da capa esmaecida, coluna de capas, nome grande com pílulas e painel com Detalhes, Descrição e Compatibilidade. Recortes de tela aninhados (`G.clip`) para capas dentro da coluna.
- Biblioteca: família própria de ícones de console (154 sistemas, arte original, `tools/make_system_icons.py` → `assets/systems/`) e ícones do próprio usuário em `r36sporthub/icones/sistemas/<sistema>.png` (o hub não inclui ícones de terceiros).
- **Biblioteca em prateleiras** no Pastel Pop (`ui/shelf.lua`): consoles em cima (ícones genéricos por tipo de aparelho, 8 novos na família de linha), jogos do console embaixo com miniaturas das capas do gamelist (120x160, cache de 14); cima/baixo trocam de fileira.
- **Wii Blue Edition** (novo): fundo azul profundo em degradê, cartões brancos arredondados, ícones azuis, seleção com halo azul e leve aumento; logos azuis próprias.
- **Neon Grid Edition** (NEON GRID atualizado): paleta nova (fundos #080B16/#10172A/#151D32, verde neon, ciano, rosa), cartões escuros com contorno neon pulsante e cantos de mira. Mantém a grade em perspectiva e as logos verdes.
- **Tela inicial em canais** nos dois temas (substitui o dashboard do NEON GRID): grade 3x3 com Central de Conteúdo (com o destaque), Biblioteca, Categorias, Meus Ports, Favoritos, Downloads, Configurações, Sobre e Sair; resumos reais; animação de entrada; L1/R1 trocam o destaque. Só o ícone do Wi-Fi (sem IP).
- **Cartões compartilhados** (`G.card`) na Central de Conteúdo, Categorias e Configurações; página do port com capa em destaque e ações nos dois temas.
- **Família de ícones de linha** (79 ícones, `assets/icons/line/`, gerada por `tools/make_icons.py`), pintada com a cor de cada tema.
- Informações do Console: bateria, rede/IP e versão do PORT HUB.
- Armazenamento: **Baixar todas as capas do catálogo** — baixa de uma vez, em segundo plano, as capas que ainda não estão no console (mostra quantas faltam e o progresso; A de novo cancela; troca de tela não interrompe).
- Aparência: atalho **Temas do EmulationStation**; Restaurar aparência volta ao Wii Blue Edition. Ordem dos temas: Wii Blue, Neon Grid, Padrão.
- Tema Padrão mantido (menu em lista). Nenhuma função removida; o painel NEON GRID antigo continua disponível como layout `dashboard`.
