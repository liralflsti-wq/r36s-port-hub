# R36S PORT HUB — Manual completo (0.3 BETA)

Ports de jogos e utilitários para o console R36S, criados por fãs e para fãs.

Projeto **independente** do KMP: nenhum arquivo do KMP foi alterado ou é necessário. Ele serviu apenas de referência técnica (veja `docs/ANALISE_KMP.md`).

## Instalação no R36S (dArkOS / ArkOS)

1. Copie o conteúdo de `R36S-PORT-HUB-BETA.zip` para a pasta `ports` do cartão (`/roms/ports`, ou `/roms2/ports` se usar 2 cartões). Deve ficar assim:
   ```
   /roms/ports/R36S PORT HUB.sh
   /roms/ports/r36sporthub/
   ```
2. Reinicie o EmulationStation (ou o console). O hub aparece em **Ports**.
3. Conecte o Wi-Fi do console antes de baixar jogos.

**Requisitos:** PortMaster instalado com o runtime **love_11.5** (o mesmo usado pelo KMP — se o KMP abre no seu console, o hub também abre), `curl` ou `wget` e `unzip` (já vêm no dArkOS).

## Controles

| Botão | Ação |
|---|---|
| Direcional / analógico esquerdo | Navegar |
| **A** | Selecionar / confirmar |
| **B** | Voltar / cancelar download |
| **L1 / R1** | Trocar categoria (na loja) / rolar página (nos detalhes) |
| **Y** | Atualizar catálogo (na loja) |
| **X** | Excluir jogo (em Meus Ports) / limpar a pesquisa / cancelar na Central de Downloads |
| **SELECT** | Marcar/desmarcar favorito |
| **START** | Abre a Central de Downloads em segundo plano, de qualquer tela (não cancela nem reinicia nada). Em **Sobre o Projeto**, abre a janela de apoio ao projeto (QR Code Pix) |
| **FN** | Tira um print da tela e salva em `/roms/print` (PNG 640×480, nome com data e hora) |
| **SELECT + START** | Sem função no app |

## Telas

- **Abertura**: splash com logo, slogan, tag BETA e barra de carregamento real
  - No primeiro acesso, vêm depois **SELECT LANGUAGE** (Português, English, Русский) e o **Aviso importante** no idioma escolhido. **A** confirma.
  - Nos acessos seguintes, a splash leva ao **Aviso importante** (sempre aparece ao abrir) e depois ao menu.
- **Menu principal**: Central de Conteúdo (antiga Loja de Ports), Categorias, Meus Ports, Configurações, Sobre o Projeto, Sair (com opção de reiniciar o EmulationStation)
  - **EM DESTAQUE** (caixa à direita): vitrine com os jogos e utilitários marcados com `"featured": true` no catálogo, na ordem do catálogo (ou de `featured_order`). Cada item mostra capa, nome, etiqueta JOGO/UTILITÁRIO, categoria e tamanho, e o contador (ex.: 2/4). A troca é automática a cada 5 s, com deslizamento suave, um brilho discreto na capa e indicadores que mostram o tempo até o próximo. **L1/R1** (indicados na parte de baixo da caixa) trocam manualmente e pausam a rotação por alguns segundos; o direcional e os analógicos não mexem no destaque. Com as animações desligadas ou no modo econômico, não há rotação automática e a troca manual é instantânea. Funciona offline com o catálogo e as capas em cache.
- **Central de Conteúdo**: três áreas independentes, **Ports de Jogos**, **BIOS do Sistema** e **Ports Utilitários e Ferramentas**. As áreas de ports têm suas abas (Todos, categorias da área, Instalados); jogos, ferramentas e BIOS nunca aparecem na mesma lista. Detalhes de BIOS em **BIOS do Sistema** abaixo.
- **Categorias**: 13 categorias de jogos e 4 de utilitários (Manutenção, Diagnóstico do sistema, Testes de controles, Ferramentas de sistema), com ícones. "Testes de controles" reúne os três tipos de teste (analógicos, botões e completo), cada um identificado na lista. Cada bloco abre a área certa já filtrada, e uma categoria vazia avisa que não há ports disponíveis nela.
- **Meus Ports**: abas Ports de Jogos e Utilitários & Ferramentas, só com o que está instalado
- **Atalhos da Central de Conteúdo**: Pesquisar, Favoritos, Novidades e Downloads
  - **Pesquisar**: teclado virtual. Busca pelo nome nos jogos e utilitários do catálogo; os resultados mudam a cada letra e aparecem agrupados por área. "Nenhum resultado" quando não há correspondência. X limpa a busca.
  - **Favoritos**: SELECT marca ou desmarca um port com estrela (na loja, na pesquisa ou na página do port). A lista é salva em `favorites.json` e tem abas por área.
  - **Novidades e Atualizações**: novos ports, ports atualizados e atualizações disponíveis para o que você tem instalado. Usa somente os campos do catálogo (veja docs/CATALOGO.md); sem dados, mostra "Não existem novidades no momento".
  - **Central de Downloads**: fila com os estados Aguardando, Baixando, Extraindo, Instalando, Concluído, Erro e Cancelado. Mostra porcentagem, tamanho baixado/total e velocidade reais, bloqueia downloads duplicados e permite cancelar com confirmação. Na janela de progresso, **Y** manda o download para segundo plano. O histórico fica em `downloads.json`.
- **Informações do Console** (Configurações → Informações do console → Todos os detalhes): cartão SD, memória RAM, sistema, arquitetura, kernel, modelo do aparelho e PortMaster/runtimes. Somente leitura; Y atualiza os dados
- **Configurações**: central com 9 categorias em cartões (Aparência e personalização, Áudio, Rede e conectividade, Bateria e energia, Controles, Downloads e atualizações, Backup e restauração, Notificações e Informações do console). Detalhes em **Configurações** abaixo.
- **Loja**: abas de categoria, lista com capa, tamanho e selo INSTALADO/ATUALIZAR, pré-visualização
- **Página do port**: capa, nome, categoria, versão, tamanho, status, descrição rolável e botão **INSTALAR / REINSTALAR / ATUALIZAR**
- **Instalação**: etapas Download → Verificação → Extração → Instalação, com barra, MB baixados, velocidade e tempo restante

## Biblioteca de jogos (emuladores) — 0.4.8

Menu principal → **Biblioteca de jogos** (no NEON GRID: atalho **Biblioteca** e painel lateral). Primeira etapa do **R36 Hub OS**: os jogos dos emuladores abrem direto pelo hub.

- O hub lê o `es_systems.cfg` do próprio console (`/etc/emulationstation/es_systems.cfg` no dArkOS/dArkOSRE): sistemas, pastas de ROMs, extensões, comando e emuladores/cores. Nada é copiado nem alterado.
- Procura os jogos em segundo plano nas pastas de cada sistema (até 3 níveis de subpasta). Sistemas sem jogos não aparecem. **Y** procura de novo.
- Nomes, capas, descrição, desenvolvedor e gênero vêm do `gamelist.xml` de cada pasta (o mesmo do EmulationStation). Nada é gravado nas pastas de ROMs.
- **A** joga: o hub fecha, o launcher roda o comando do sistema com `%ROM%`, `%EMULATOR%`, `%CORE%` e `%GOVERNOR%` preenchidos como o EmulationStation faz e, ao sair do jogo, o hub abre de novo no mesmo sistema.
- **X** escolhe o emulador/core: na lista de sistemas, o padrão do sistema; na lista de jogos, só daquele jogo. Sem escolha, vale o primeiro emulador e o primeiro core do `es_systems.cfg`.
- **SELECT** marca favorito; **Recentes** e **Favoritos** aparecem no topo da biblioteca.
- Os ports continuam em Meus Ports (o sistema "ports" não entra na biblioteca).
- Arquivos do hub: `library_choices.json`, `library_favorites.json` e `library_recent.json` (pasta de dados do app).

## Configurações (Central de Configurações, reorganizada na 0.4.8)

A tela principal mostra 17 cartões em 3 colunas (3 linhas visíveis por vez). Cada cartão tem ícone, nome, descrição curta e o estado atual. Direcional escolhe, **L1/R1** passam uma página, **A** abre e **B** volta; o rodapé mostra a posição (ex.: 5/17). Cada opção aparece num cartão só. Dentro de cada categoria:

- Interruptores ligam e desligam (A, ou esquerda/direita).
- Escolhas e sliders mudam com esquerda/direita.
- Embaixo aparece a explicação da opção escolhida.
- Telas de lista e de leitura abrem com A; B volta.

| Categoria | Opções |
|---|---|
| Preferências | Idioma (A abre a tela de escolha com as bandeiras; a troca vale na hora), Tela ao abrir, Botão B no menu principal, Notificações na tela, **Posição das notificações** (embaixo no centro, em cima no centro, canto superior direito, canto inferior direito), Confirmações e informações, Alertas e erros, **Aviso de nova versão do hub**, Som das notificações, Testar notificação, Restaurar preferências |
| Aparência e personalização | Tema, Tamanho do texto, Brilho da tela, Ajustes do console (R36 Control), Animações da interface, Restaurar aparência original |
| Áudio | Música de fundo, Volume da música, Efeitos sonoros, Volume dos efeitos |
| Rede e conectividade | Gerenciar Wi-Fi, Rede Wi-Fi, Sinal, Conexão, IP local, Diagnóstico de rede (interface, gateway, DNS e testes), Velocidade da internet, Transmissão e gravação, Verificação dos repositórios |
| Servidor FTP | Ligar/desligar, Endereço, Usuário, Senha, Estado, Configurar servidor FTP, Tutorial, Transferências e histórico, Avisar transferências concluídas, Avisar falhas |
| Catálogo de ports | Atualizar catálogo agora, Atualizar ao abrir o hub, Última atualização online, Conteúdo, Ordenação das listas, Ordenar favoritos |
| Downloads | Central de Downloads, Avisos de downloads em segundo plano, Histórico, Repetir downloads com falha, Limpar histórico |
| Meus Ports | Abrir Meus Ports, Abrir Favoritos, Ports encontrados, Verificador de integridade, Instalações incompletas, Atualizar informações, Limpar favoritos |
| **Armazenamento** | Espaço de cada cartão (livre, total e % usado), Memória RAM, Espaço ocupado pelos ports, Cache de capas (limpar), Gerenciador de arquivos, Otimizador e manutenção do microSD, Verificador do cartão SD |
| Bateria e energia | Carga, Estado e os dados que o sistema informar (alimentação, tensão, saúde, temperatura), Análise da bateria, Modo econômico |
| Controles | Testar analógicos e botões (R36S Analog Tester), Último relatório, Todos os testes de controles, Mapa dos botões |
| Informações do console | Analisador de Console, Data e hora, Dispositivo, Processador, Resolução da tela, Arquitetura, Sistema, Temperatura do processador, Todos os detalhes |
| Atualizações do hub | Versão instalada, Atualização via rede, Atualização local, Histórico de atualizações, Backups e recuperação |
| PortMaster e runtimes | Gerenciar PortMaster, Atualizar runtimes |
| Backup e restauração | Último backup, o que entra (preferências, favoritos, FTP, históricos, catálogo local), Fazer backup agora, Restaurar backup, Exportar para o cartão, Importar do cartão, Histórico de backups |
| Diagnóstico e suporte | Executar diagnóstico (Y repete, X exporta relatório), **Registro de erros** (abre o leitor no arquivo mais recente; esquerda/direita troca de arquivo; B volta para Diagnóstico e suporte), Histórico de erros de comunicação, Componentes do hub, Informações para o suporte |
| Sobre o projeto | Nome, Versão, Desenvolvedor, Sobre o R36S PORT HUB, Licenças, Aviso importante (só leitura) |

- **Efeitos sonoros**: os sons são gerados pelo próprio app, sem arquivos de áudio.
- **Backup**: fica em `conf/love/r36sporthub/backup/`. Nunca inclui ports instalados nem arquivos de jogos.
- **Exportar para o cartão**: cria `ports/r36sporthub/configuracoes/<data>/` com os itens marcados. A senha do FTP nunca é exportada. **Importar do cartão** lista as 5 exportações mais recentes e pede confirmação antes de substituir.
- **Restaurar preferências**: volta tela inicial, saída, notificações, sons, música, animações, tamanho do texto, ordenação e gravação ao padrão. Idioma, tema, brilho, FTP, favoritos e históricos não mudam. Uma cópia fica em `settings.antes_de_restaurar.txt`.
- **Aviso de versão nova**: ao abrir o hub (com Wi-Fi), ele confere em segundo plano o link oficial de atualização, lendo só o começo do pacote. Se a versão for maior que a instalada, um texto desliza no alto da tela inicial, entre a logo e a data, e o rodapé mostra **SELECT Atualizar**. SELECT abre a Atualização via rede. Nada é baixado sozinho. O aviso some depois de atualizar e reiniciar. Sem internet, não aparece nada. Desliga em Atualizações do hub > Avisar quando sair versão nova (chave `upd_notify`).
- **Relatório para o suporte**: `ports/r36sporthub/logs/relatorio_suporte_<data>.txt` (os 5 mais recentes ficam guardados). Senhas não entram.
- **Histórico de erros de comunicação**: até 30 falhas de acesso à internet (catálogo, atualizações, downloads, repositórios), só com o endereço do servidor, em `netlog.json`.
- **Instalações incompletas**: ports instalados pelo hub em que falta algum item registrado na instalação (script ou pasta principal).
- **Onde ficam as escolhas**: em `settings.txt`, nas chaves `start_screen`, `exit_mode`, `notif_pos`, `upd_notify`, `cat_auto`, `cat_last`, `list_sort`, `fav_sort`, `notif_downloads`, `ftp_notif_done`, `ftp_notif_fail`, `music_vol`, `sfx`, `sfx_vol`, `anim`, `eco`, `notif`, `notif_info`, `notif_alert`, `notif_sound` e `backup_groups`.

## Registro de erros

Quando o R36S PORT HUB apresenta um erro ou problema, ele grava um arquivo de texto na pasta `r36sporthub/logs/` (dentro do port):

- `erro_AAAAMMDD_HHMMSS.txt`: o app travou (erro fatal) ou uma tarefa em segundo plano falhou. Traz a mensagem, onde aconteceu, a tela aberta, versão, idioma, sistema e as últimas linhas do registro do app.
- `erro_AAAAMMDD_HHMMSS_saida.txt`: gravado pelo launcher quando o app fecha com código de erro (ex.: travou sem conseguir gravar o próprio registro), com as últimas 200 linhas do `log.txt`.
- `problemas_AAAA-MM-DD.txt`: um arquivo por dia com as falhas mostradas na tela (download que falhou, instalação recusada…).

Avisos na tela:

- **Tarefa em segundo plano que falhou** (o app continua funcionando): aparece o aviso "Uma tarefa em segundo plano falhou. Detalhes em Configurações > Informações do console > Registro de erros." Se várias falharem seguidas, o aviso aparece no máximo uma vez a cada 10 segundos. Segue a opção **Alertas e erros** de Notificações.
- **Erro fatal** (o app travou): aparece a tela de erro com a mensagem, o caminho do arquivo do registro e "Aperte START para fechar o R36S PORT HUB".
- Falhas mostradas numa janela de erro já são o próprio aviso.

Senha do FTP, chaves de Wi-Fi e senhas que apareçam no texto são trocadas por `******`. Ficam os 30 arquivos mais recentes. Em **Configurações → Informações do console → Registro de erros** dá para ver quantos existem e abrir a pasta no Gerenciador de arquivos.

## Analisador de Console

Fica em **Configurações → Informações do console → Analisador de Console**. Ele lê só informações do próprio aparelho, sem gravar nada no sistema e sem usar a internet:

- `/proc/cpuinfo` e `/proc/meminfo`;
- a Device Tree carregada (`/proc/device-tree`);
- `/sys/class/drm`, `/sys/class/power_supply` e `/sys/block`;
- `/etc/os-release`.

Depois compara o que leu com a base `src/data/console_signatures.json`.

**A base**
- Tem 135 placas.
- Foi gerada a partir dos arquivos DTB publicados pelos projetos dArkOSRE-R36, ArkOS4Clone e R36S-DTB, pelo `tools/mkconsoledb.py`.
- Cada entrada guarda o nome da placa, o compatible, a assinatura do painel (sha1 da `panel-init-sequence`), a resolução e a fonte, com o commit.

**Resultados possíveis**
- compatível com assinaturas conhecidas do R36S;
- possível variante ou revisão;
- possível clone;
- outro modelo;
- não identificado.

A confiança é dada só em texto: Alta, Média, Baixa ou Insuficiente. O analisador nunca confirma a autenticidade do aparelho.

**Relatório**: **A** exporta um TXT para `r36sporthub/relatorios/`. O último resultado fica guardado para você ver de novo.

## Velocidade da internet

Abra **Configurações → Rede e conectividade → Velocidade da internet**, ou aperte **X** dentro do **Diagnóstico de rede**. O teste mede três coisas:

- **Latência**: mediana de 5 conexões, com a variação entre elas.
- **Download**: até 25 MB ou 12 segundos.
- **Upload**: até 8 MB ou 12 segundos.

Os números são os medidos pelo `curl`, usando os servidores públicos do teste da Cloudflare (`speed.cloudflare.com`). Cada teste usa cerca de 33 MB de dados, por isso ele só roda quando você pede. O último resultado fica salvo e aparece nas duas telas.

## R36S Analog Tester (testes de controles)

O teste de analógicos e botões **R36S Analog Tester** (por LagdoLira, versão 1.2) vem dentro do hub, em `r36sporthub/tools/`. Você abre por dois caminhos:

- **Configurações → Controles → Testar analógicos e botões**;
- **Central de Conteúdo → Ports Utilitários e Ferramentas → Testes de controles**.

**Como funciona**
1. A tela do teste explica o que ele faz e mostra o último relatório.
2. **ABRIR TESTE** fecha o hub e o launcher abre o teste.
3. Para sair do teste, use START + SELECT ou L1 + R1 para voltar ao menu dele e escolha **Sair**.
4. O hub abre de novo, sozinho, na mesma tela, com o relatório atualizado.

Com downloads em andamento, o teste não abre. Se o servidor FTP estiver ligado, o hub pede para parar o servidor antes de abrir.

O relatório fica em `r36sporthub/tools/r36s_analog_tester/relatorio_controles.txt`.

## Idiomas

O app inteiro funciona em **Português (Brasil)**, **English** e **Русский**.

- No primeiro acesso, o idioma é escolhido na tela SELECT LANGUAGE.
- Para trocar depois, use **Configurações → Aparência e personalização → Idioma**. A mudança vale na hora, sem reiniciar o app.
- A escolha fica em `settings.txt`.

Detalhes, estrutura das traduções e como corrigir um texto: **`docs/IDIOMAS.md`**.

## BIOS do Sistema

**Central de Conteúdo → BIOS do Sistema** baixa, confere e instala BIOS para os emuladores do dArkOSRE. Nada é baixado, instalado ou apagado sem confirmação.

- **Pasta de BIOS**: vem da configuração do RetroArch do console (`system_directory` em `~/.config/retroarch/retroarch.cfg` ou `retroarch32`). Sem ela, o hub usa o padrão documentado do dArkOS: `/roms/bios` (ou `/roms2/bios` com dois cartões), se existir. Se nenhuma for encontrada, nada é instalado. O hub não cria a pasta.
- **Onde cada BIOS fica**: tabela da wiki do ArkOS (o dArkOS herda as pastas), em `src/core/bios_ref.lua`. Algumas ficam em subpastas (`dc/`, `neocd/`, `keropi/`, `xmil/`, `same_cdi/bios/`) e algumas na pasta de ROMs do sistema (`advision.zip`, `astrocde.zip`; cópia recomendada do `neogeo.zip`). A pasta de ROMs nunca é criada pelo hub.
- **Como uma BIOS é reconhecida**: pelo MD5, comparado com o banco `System.dat` do libretro (`src/core/bios_db.lua`, gerado por `tools/mkbiosdb.py`). Uma pasta ou um nome não bastam.
- **Estados**: INSTALADA (MD5 de uma versão conhecida), AUSENTE, ATUALIZAÇÃO DISPONÍVEL (a atual não confere com nenhuma versão conhecida e a do pacote confere), VERIFICAÇÃO PENDENTE (o arquivo existe, mas a versão não pôde ser confirmada; o hash serve só para identificação), INCOMPATÍVEL (nome conhecido, tamanho diferente de todas as versões) e ERRO NA INSTALAÇÃO.
- **Baixar pacote de BIOS**: consulta a fonte oficial do projeto (`C.BIOS_URL`: `https://archive.org/download/bios-r-36s/Bios%20r36s.rar`), mostra nome e tamanho e baixa depois do A. O download aparece na Central de Downloads e não instala nada. Para usar outro pacote, coloque o link direto (uma linha) em `r36sporthub/bios_url.txt`. Sem nenhum link, a tela avisa que a fonte não está configurada.
- **Analisar e instalar**: lista o pacote antes de extrair (recusa caminhos `../`, absolutos e links), testa a integridade, extrai em `r36sporthub/bios/tmp/` e identifica cada arquivo. O resumo mostra INSTALAR, ATUALIZAR, IDÊNTICA, VERIFICAÇÃO PENDENTE, SEM PASTA, INCOMPATÍVEL, DUPLICADO, DOCUMENTO e NÃO RECONHECIDO. Só BIOS reconhecidas vêm marcadas; A marca/desmarca e Y instala as marcadas.
- **Instalação**: antes de trocar uma BIOS, o arquivo atual vai para `r36sporthub/backups/bios/<data>/`, com a mesma estrutura de pastas e um `meta.json` (nome, caminho, tamanho, MD5, SHA-256, data). Cada arquivo instalado é conferido pelo MD5. Se algo falhar, tudo volta como estava. Se o console desligar no meio, a próxima abertura desfaz o que ficou pela metade e avisa.
- **Histórico e backups**: instalações, restaurações, recuperações e limpezas. A em uma instalação com backup restaura as BIOS que ela substituiu. Backups nunca são apagados automaticamente.
- **Limpeza de arquivos de instalação**: mostra o pacote baixado e as pastas temporárias com o espaço que será liberado e apaga só depois da confirmação. Só apaga o que o próprio hub registrou em `r36sporthub/bios/registro.json`; BIOS instaladas, backups e outros arquivos ficam.
- Extração: ZIP, 7Z e RAR, com a ferramenta que o console tiver (7-Zip do hub, 7z/7zz/7za, unzip ou unrar). Veja em Configurações → Downloads e atualizações → Atualizações quais formatos estão disponíveis.

## Tamanho do texto

**Configurações → Aparência e personalização → Tamanho do texto**: use esquerda/direita para escolher **Pequeno**, **Padrão**, **Grande** ou **Muito grande** (A também avança e, depois do último, volta ao primeiro). A mudança vale na hora para todo o aplicativo e fica salva.

- Mudam as letras dos textos, das listas, das descrições e dos diálogos. A logo, as etiquetas e os botões em letra pixelada mantêm o tamanho, porque essa fonte só fica nítida no tamanho original.
- Se um texto não couber no espaço dele, a letra diminui sozinha até o tamanho padrão; se ainda assim não couber, o texto termina com "…". Nas janelas de confirmação, os botões crescem e o texto se ajusta para a janela caber na tela.
- Algumas telas cheias de informação em posições fixas ficam sempre no tamanho padrão: Servidor FTP, Transmissão e gravação, Loja de Temas do EmulationStation, análise de um pacote de atualização, resultado do R36S Analog Tester, compatibilidade de um port e os painéis de progresso.

## Brilho da tela

**Configurações → Aparência e personalização → Brilho da tela**: use esquerda/direita para ajustar de 5% a 100%, em passos de 5%. O mínimo é 5% para a tela nunca apagar por completo. O valor fica salvo e é reaplicado quando a loja abre.

O método é o mesmo do próprio ArkOS/dArkOS. O serviço de atalhos do sistema ([ogage](https://github.com/christianhaitian/ogage)) muda o brilho com o comando `brightnessctl`, que atua na luz de fundo do painel em `/sys/class/backlight/<dispositivo>`. A loja tenta, nesta ordem, `brightnessctl`, `sudo -n brightnessctl`, a escrita direta em `/sys/class/backlight/<dispositivo>/brightness` e a mesma escrita com `sudo -n`. Depois de cada ajuste, ela lê o valor de volta. Se o brilho real não mudou, o controle aparece como **INDISPONÍVEL**, com o motivo, em vez de mostrar um número que não faz efeito.

## Trilha sonora

| Faixa | Onde toca |
|---|---|
| **Tema principal – R36S PORT HUB** (identidade sonora oficial) | Aviso inicial e menu principal |
| **Tema de navegação – Retro Arcade** | Loja, categorias, página do port e "Sobre" |
| **Tema de download – Download Power** | Durante download, extração e instalação |

As trocas de faixa são feitas com transição suave. As músicas tocam em streaming, o que gasta pouca memória, e foram convertidas para OGG Vorbis com volume igualado. Para ligar ou desligar, use **Configurações → Áudio → Música de fundo**. O volume da música fica em **Áudio → Volume da música**. As escolhas ficam salvas no console.

## Reconhecimento dos ports já instalados

Ao abrir a loja (e sempre que entra num port ou termina uma instalação), o hub examina a pasta `/roms/ports` do console e reconhece os jogos instalados **por qualquer meio**: pelo próprio hub, pelo PortMaster, pelo KMP ou copiados à mão. A comparação ignora maiúsculas, acentos, espaços e pontuação, e usa:

1. o registro do próprio hub (`installed.json`);
2. o `port.json` do PortMaster dentro da pasta do port (nome do ZIP, título, itens e capa);
3. arquivos `.port` (título, versão, script), na raiz ou dentro da pasta do port;
4. a linha `GAMEDIR=` de cada script `.sh`, para descobrir a pasta de dados do jogo;
5. o `gamelist.xml` do EmulationStation (nome exibido → script);
6. um script `.sh` com o nome do jogo, o `id`, o `pm_name` ou o nome do ZIP do catálogo;
7. ou a lista `install_check` do catálogo, quando informada (tem prioridade).

O nome de uma pasta, sozinho, nunca identifica um jogo: é preciso existir o script `.sh`, que é o que o EmulationStation executa.

**Meus Ports** mostra todos os ports do cartão. Os que estão no catálogo aparecem com os dados da loja, e os demais aparecem com o selo **NO CONSOLE**, o nome vindo do PortMaster ou do EmulationStation e a capa do `port.json`, quando houver. Cada jogo do catálogo aparece como **NÃO INSTALADO**, **INSTALADO** ou **ATUALIZAR**. O último só aparece quando a versão instalada é conhecida, pelo registro do hub ou por um arquivo `.port`, e é diferente da versão do catálogo.

O jogo aparece com o selo **INSTALADO** (ou **ATUALIZAR**, se a versão do catálogo for mais nova), e a página mostra o que foi encontrado. Ao apertar **REINSTALAR/ATUALIZAR**, o hub avisa que o jogo já está no console e lista os arquivos encontrados:

- **OK**: baixa, extrai e instala de novo, sem perguntar outra vez. Os arquivos do port são atualizados, e saves e arquivos extras são mantidos.
- **CANCELAR**: não baixa nada (opção já selecionada, por segurança).

O menu principal mostra quantos ports existem no console.

## Atualizar runtimes do PortMaster

**Configurações → Downloads e atualizações → Atualizar runtimes** usa o pacote `runtimes.all.aarch64.zip` da release `2026-10-22_1343` do PortMaster. O endereço fica em `src/config.lua`.

Estrutura real do pacote, verificada antes de implementar: 48 arquivos `.squashfs` na raiz, sem pastas, que o PortMaster carrega de `<PortMaster>/libs/`. O `ports.json` da mesma release traz o **md5 e o tamanho** de cada runtime, e é ele que garante a integridade.

1. Localiza o PortMaster (pasta informada pelo launcher, `/roms/ports/PortMaster`, `/opt/system/Tools/PortMaster`…) e usa a pasta `libs/`.
2. Baixa o índice (`ports.json`), o que também confirma a conexão com a internet.
3. Compara os runtimes instalados com o índice (tamanho e md5). Se tudo já estiver em dia, **não baixa nada**.
4. Confere o espaço livre para o ZIP e para os arquivos novos.
5. Mostra quantos runtimes são novos e quantos são atualizações, e o tamanho do download, e **pede confirmação**.
6. Baixa o pacote (cerca de 1,95 GB) com progresso real, velocidade, tempo restante e retomada se a conexão cair.
7. Valida o tamanho e a assinatura ZIP e examina a estrutura: só arquivos `.squashfs` são considerados; caminhos inseguros ou duplicados recusam o pacote.
8. Extrai **apenas** os runtimes necessários para `libs/.porthub_staging` e confere o md5 de cada um. Até aqui nada dos runtimes atuais foi tocado.
9. Move os runtimes antigos (e o `.md5` ao lado, se houver) para `libs/.porthub_backup_<data>` e coloca os novos no lugar. Se qualquer passo falhar, o backup é restaurado.
10. Apaga o ZIP, a pasta temporária e o backup, e mostra o resultado.

Outros arquivos da pasta `libs` e as configurações e dados dos jogos nunca são alterados. Se o console desligar no meio, na próxima abertura o hub devolve ao lugar o que ficou só no backup.

**Para o futuro:** com `C.RUNTIMES_AUTO_LATEST = true`, o hub consulta a API do GitHub e usa a release mais recente que contenha o pacote. Isso é necessário porque nem toda release publica o `runtimes.all.aarch64.zip`: a de 2026-10-30, por exemplo, não tem. Também dá para trocar a URL sem recompilar, criando `r36sporthub/runtimes_url.txt` (linha 1: URL do ZIP; linha 2, opcional: URL do `ports.json`).

## Gerenciar PortMaster

**Configurações → Downloads e atualizações → Gerenciar PortMaster** (não existe uma categoria "Sistema"; a grade de configurações já está cheia, então a opção fica junto de "Atualizar runtimes" e "Atualizações").

A tela mostra, sempre a partir de verificações reais: status (Instalado / Não instalado / Instalação incompleta), versão instalada (arquivo `PortMaster/version`), última versão estável (com a data da consulta; **Y** consulta de novo), atualização (Disponível / Atualizado / Não verificado) e runtimes (Íntegros / Incompletos / Verificação necessária, resultado do atualizador de runtimes). Abaixo, o console: modelo, arquitetura da CPU e dos pacotes, sistema, variante do R36, kernel, pasta do PortMaster, iniciador, espaço livre e permissão de gravação. O que não puder ser lido aparece como "não identificado".

**Fontes oficiais (sem URL de pacote fixa no código):**
- `https://github.com/PortsMaster/PortMaster-GUI/releases/latest/download/version.json`: o mesmo arquivo que o próprio PortMaster usa para se atualizar. Traz, por canal (`stable`, `beta`, `alpha`), a versão, a URL do `PortMaster.zip` e o md5.
- API de releases `api.github.com/repos/PortsMaster/PortMaster-GUI/releases`: canal no nome da release ("(stable)", "(beta)", "(alpha)"), indicador de pre-release e sha256 de cada arquivo. Se o `version.json` falhar, a release estável vem daqui (nunca pre-release ou rascunho) e o md5 vem do `PortMaster.zip.md5` da mesma release.
- Pacote escolhido: **somente** `PortMaster.zip` (nome exato e URL `…/PortMaster-GUI/releases/download/<versão>/PortMaster.zip`). `muos.portmaster.zip`, `trimui.portmaster.zip` e `retrodeck.portmaster.zip` são de outros sistemas; `Install*.PortMaster.sh` são instaladores autoextraíveis e nunca são executados.

**Validação:** sha256 (quando a API informa) e md5 oficial; tamanho; `unzip -t`; todos os caminhos dentro de `PortMaster/`, sem `..` ou links; versão dentro do pacote igual à da release; o pacote precisa ter os arquivos da arquitetura do console (`gptokeyb`, `7zzs.aarch64`, `runtimes/love_11.5/love.aarch64`) e o `mod_dArkOSRE.txt` (ou dArkOS/ArkOS). Sem md5 nem sha256, nada é instalado.

**Instalar:** só quando não existe nenhuma instalação. Mesmo destino do instalador oficial no ArkOS/dArkOS: `/opt/system/Tools/PortMaster` (é a `/roms/tools`), com o `PortMaster.sh` movido para `/opt/system/Tools`. Extrai para uma pasta temporária na mesma partição, move a pasta pronta e ajusta permissões como o PortMaster oficial (`chmod -R 777` apenas em ext4/ext3/overlay). Depois, cada arquivo é conferido por md5.

**Atualizar:** compara a versão instalada com a estável. Só os arquivos do pacote são gravados (como na atualização feita pelo próprio PortMaster): `config/`, `themes/`, `autoinstall/`, `libs/*.squashfs`, ports e saves não fazem parte dele e não são tocados. Antes, cada arquivo que vai mudar ganha backup (`.porthub_pm/backup` ao lado da pasta do PortMaster). A gravação é "arquivo novo + rename", segura até para o `love` e o `gptokeyb` que o próprio hub está usando. O modo de controle do PortMaster (padrão/xbox) é mantido. Ao fim, md5 de cada arquivo e uma conferência de que ports/saves, runtimes e configurações continuam iguais; se algo falhar, o backup é restaurado e conferido.

**Verificar:** INSTALAÇÃO ÍNTEGRA, ATUALIZAÇÃO DISPONÍVEL, ARQUIVOS AUSENTES, INSTALAÇÃO INCOMPLETA, PERMISSÕES INCORRETAS, DEPENDÊNCIA AUSENTE (python3, bash, unzip) ou NÃO FOI POSSÍVEL VERIFICAR. Com a lista md5 guardada pelo hub (feita a partir do pacote oficial da versão instalada) a comparação é arquivo por arquivo; sem ela, só os essenciais são conferidos e **X** faz a verificação completa (baixa o pacote oficial da versão instalada). Arquivos diferentes do oficial são listados como "diferentes", não como "corrompidos".

**Reparar:** baixa o pacote oficial **da versão instalada**, compara cada arquivo e mostra a lista antes de mudar qualquer coisa. Restaura só arquivos oficiais ausentes ou diferentes (com backup), e corrige permissões. `pylibs.zip` (o PortMaster extrai e apaga) e `gamecontrollerdb.txt` (modo de controle) não são tratados como defeito.

**Runtimes:** continuam com o atualizador existente (Atualizar runtimes). "Verificar runtimes" abre esse mesmo atualizador; o resultado dele vira o estado mostrado na tela. Nenhum runtime é removido ou baixado em duplicidade.

**Central de Downloads:** download, validação, extração e instalação aparecem na mesma central, com progresso, velocidade, etapas e histórico. Só uma operação do PortMaster por vez, e ela não começa com outro download ou instalação em andamento.

**Histórico:** data, operação, versão anterior e nova, URL oficial, método de conferência, resultado e erros (sem senhas ou tokens).

**Recuperação:** um diário em `.porthub_pm/state` registra a gravação. Se o console desligar no meio, na próxima abertura o hub restaura o backup e só informa "restaurado" se o md5 de cada arquivo voltou ao original.

**Nunca:** executa scripts baixados, usa sudo, mexe em bootloader/partições, formata, apaga ports, saves, configurações ou runtimes.

## Desinstalar um jogo (Meus Ports → X)

Em **Meus Ports**, selecione o jogo e pressione **X** (**Desinstalar**). A confirmação lista exatamente o que será apagado (script `.sh`, pasta do jogo e demais itens do port, com o tamanho) e como os arquivos foram identificados, com as opções **CANCELAR** (selecionada) e **DESINSTALAR**. Depois, a lista é atualizada na hora.

Os arquivos do jogo são identificados por, nesta ordem:

1. o registro de instalação da própria loja;
2. o `port.json` do PortMaster (lista de itens do port);
3. um arquivo `.port` do jogo;
4. a pasta declarada no `GAMEDIR=` do script;
5. a pasta citada no script de outra forma (`cd /roms/ports/...`, `gamedir=`, `PORTDIR=`);
6. a pasta com o mesmo nome do script.

Se nenhuma pasta for encontrada, só o script `.sh` é removido (a confirmação avisa). A desinstalação é recusada quando:

- a pasta é usada por outro jogo;
- o item é protegido: `PortMaster`, runtimes/`libs`, `images`, `gamelist.xml` ou o próprio hub;
- há algo montado dentro da pasta.

Links simbólicos são removidos sem apagar o destino, e nada fora de `/roms/ports` é tocado.

## Gerenciador de arquivos

Em **Configurações → Downloads e atualizações → Gerenciador de arquivos**, você navega pelo cartão SD (`/roms` e `/roms2`, se existir), começando na pasta de ports. Pastas aparecem primeiro, depois os arquivos **ZIP, RAR e 7z** com uma etiqueta amarela, depois os demais arquivos.

**X** (ou **A** num arquivo) abre as opções do item:

- **Extrair aqui** (ZIP, RAR, 7z): descompacta na mesma pasta, mantendo a estrutura do arquivo. Ao terminar, pergunta se o arquivo compactado deve ser excluído (**EXCLUIR** ou **MANTER**).
- **Instalar como port** (ZIP, RAR, 7z): instala em `/roms/ports` com as mesmas verificações da loja: script `.sh`, remoção de pastas-embrulho, permissões e itens protegidos. Depois da instalação, o compactado é excluído.
- **Recortar**: guarda o item; abra a pasta de destino e aperte **Y** para colar (mover). Nunca sobrescreve um item com o mesmo nome.
- **Excluir**: apaga o arquivo ou a pasta inteira, depois de confirmar.

A extração usa o mesmo instalador da loja: confere espaço livre, extrai numa pasta temporária, **pergunta antes de substituir** arquivos que já existem e só então move tudo para o destino. Se houver erro, se o arquivo estiver corrompido ou se você cancelar, nada é alterado e o arquivo compactado é mantido.

Não podem ser movidos nem excluídos: a raiz dos cartões, a pasta e o script do R36S PORT HUB, o PortMaster, o `gamelist.xml` e um arquivo que esteja sendo extraído.

Controles: **A** abre a pasta ou mostra as opções do arquivo, **X** opções, **Y** colar, **B** volta uma pasta, **L1/R1** (ou esquerda/direita) passam de página.

## Transmissão e gravação da tela do hub

Configurações → Rede e conectividade → **Transmissão e gravação** mostra a interface do R36S PORT HUB ao vivo no navegador do computador e grava vídeos dela no cartão SD. Só a tela do hub é capturada: jogos, EmulationStation e o resto do sistema não aparecem.

**Transmitir**
1. Conecte o R36S ao Wi-Fi e use **INICIAR TRANSMISSÃO**.
2. O console mostra o IP real, a porta (8090, ou a próxima livre até 8099), o endereço completo e um QR Code.
3. No computador, na mesma rede Wi-Fi, abra o Firefox ou o Chromium e digite o endereço completo (ele termina com um código).

- Funciona só na rede local, sem internet, sem nuvem e sem instalar nada no computador.
- O código no fim do endereço muda a cada transmissão; endereços antigos deixam de funcionar.
- A página é somente visualização: não controla o console e não dá acesso a arquivos. Até 3 computadores ao mesmo tempo.
- **Quadros da transmissão**: 5, 10 ou 15 por segundo. Só as partes da tela que mudaram são enviadas.
- **ENCERRAR TRANSMISSÃO** fecha tudo; a página do navegador avisa que a transmissão terminou. Ao entrar num jogo o hub fecha e a transmissão termina.
- Enquanto está ligada, aparece **AO VIVO** no canto inferior direito da tela do console (só no console, não no vídeo).

**Gravar**
- **INICIAR GRAVAÇÃO**, **PAUSAR/RETOMAR** e **FINALIZAR GRAVAÇÃO**. Transmissão e gravação são independentes.
- Arquivos em `r36sporthub/gravacoes/`, com nome automático de data e hora (`gravacao_AAAA-MM-DD_HH-MM-SS`).
- Formato **MP4** quando o console tem o `ffmpeg` com codificador H.264 (libx264) ou MPEG-4. Sem ele, o hub avisa e grava no formato leve **.r36rec**: copie o arquivo pelo FTP e abra `converter_gravacao.html` (fica na mesma pasta) no Firefox ou Chromium do PC para assistir ou converter em vídeo WebM (a conversão leva o mesmo tempo da gravação).
- **Quadros da gravação**: 10, 15 ou 30 por segundo. Sem som. 30 FPS usa mais o processador; no modo econômico a tela do hub tem no máximo 20 quadros por segundo.
- Durante a gravação aparece **REC** com a duração no canto inferior direito (só no console). A tela mostra formato, duração, tamanho e arquivo.
- Nada começa sozinho e nada é apagado automaticamente. Com menos de 64 MB livres a gravação não começa; se o cartão chegar perto de encher, ela é finalizada e salva. Ao sair do app, a gravação é finalizada e salva.
- **Gravações salvas** lista os arquivos com data, duração e tamanho; **Abrir pasta das gravações** abre a pasta no Gerenciador de arquivos.

## Servidor FTP

Configurações → Rede e conectividade → **Configurar servidor FTP** transfere arquivos entre o cartão SD do R36S e um celular ou computador na mesma rede Wi-Fi.

- O servidor só liga em **INICIAR** e desliga em **PARAR** (ou ao sair do app, que pergunta antes). Nunca liga sozinho.
- Porta padrão **2121** (a 21 não é usada). Usuário padrão `r36s` e uma senha aleatória criada no primeiro uso; troque em Porta/Usuário/Senha e confirme em **SALVAR CONFIGURAÇÕES**. A senha fica em `ftp.json` (permissão 600) na pasta de dados do app, nunca no código. **Y** mostra/oculta a senha.
- A raiz é o cartão SD onde ficam os ports (detectado pelo ponto de montagem). `../` e links que apontem para fora dele são bloqueados; a raiz não pode ser excluída. Excluir/renomear pastas do primeiro nível, do hub, do PortMaster ou da bios pede confirmação no console.
- Só aceita clientes da rede local, apenas modo passivo, sem acesso anônimo. Comandos `SITE` são recusados.
- Arquivo recebido é gravado como temporário e só ganha o nome final quando chega inteiro; transferências interrompidas são descartadas.
- **Atividade FTP** mostra nome, ENVIO/RECEBIMENTO, tamanho, porcentagem, velocidade atual e média, tempo e status. **Histórico FTP** guarda as últimas transferências (sem credenciais).
- O FTP não criptografa senha nem arquivos: use só na rede de casa. FTPS/SFTP ficam para uma versão futura.
- Clientes testados: protocolo FTP padrão (FileZilla, gerenciadores de arquivos Android com FTP, Explorador do Windows).

## Capa na lista de Ports

O pacote traz `cover.png` (capa), `logo.png` (marquee) e `fanart.png` (fundo) em `r36sporthub/`. Quem instala pelo PortMaster recebe a capa pelo `gameinfo.xml`. Quem só extrai o ZIP em `/roms/ports`: abra o R36S PORT HUB uma vez (ele acrescenta a própria entrada no `gamelist.xml`, sem mexer nos outros jogos) e use **Sair → Reiniciar lista**.

**Capa dos jogos instalados pelo hub:** ao instalar um port do catálogo, o hub copia a capa do catálogo (a mesma que aparece no hub) para a pasta do jogo, com o nome `<id>-cover.png` (ou `.jpg`), e coloca o jogo no `gamelist.xml` da pasta de Ports com nome, descrição, gênero e capa. Se o catálogo não tiver capa, usa a `cover.png`/`screenshot.png` que o próprio port trouxer. Se o jogo já tiver entrada no `gamelist.xml`, o hub só completa a imagem que faltar; nunca troca o que você, o PortMaster ou um scraper colocaram, e não mexe em outros jogos (cópia de segurança em `gamelist.xml.porthub.bak` na primeira alteração). A capa aparece depois de **Sair → Reiniciar lista**. Ao desinstalar pelo hub, ele desfaz só o que ele mesmo colocou.

## Otimizador e manutenção do microSD

**Configurações → Informações do console → Otimizador e manutenção do microSD** mostra o cartão (fabricante e modelo informados pelo cartão, capacidade, usado, livre, %) e cada partição (formato, tamanho, ponto de montagem, somente leitura ou leitura e gravação). Tudo vem do sistema (`/sys/block`, `lsblk` ou `/proc/partitions`, `/proc/mounts`, `df`). Com dois cartões, L1/R1 troca.

- **Analisar armazenamento**: pastas e arquivos (acima de 10 MB) que mais ocupam em cada partição montada. Somente leitura.
- **Verificar integridade**: partição montada como somente leitura (sinal de erro), erros do cartão e do sistema de arquivos no registro do sistema (`dmesg`), estado do ext4 (`dumpe2fs`/`tune2fs`) e o aviso de falha de mídia do exFAT. O que não pôde ser verificado aparece como **NÃO VERIFICADO**, separado dos problemas.
- **Verificar erros do sistema de arquivos**: mostra para cada partição a ferramenta (`fsck.exfat`, `fsck.vfat`, `e2fsck`) e se ela existe no sistema. Partições montadas **nunca** são verificadas nem desmontadas; só uma partição desmontada pode ser verificada, em modo somente leitura (`-n`), depois de confirmar. Reparos não são feitos pelo hub: a tela explica como fazer no computador, depois de um backup.
- **Otimização compatível**: gravar dados pendentes (`sync`), TRIM (`fstrim`, só quando o kernel informa suporte a descarte do cartão) e limpar temporários de instalações interrompidas do próprio hub. Cada operação é explicada e confirmada antes.
- **Localizar arquivos duplicados**: compara o conteúdo por hash (`md5sum`), só arquivos de 1 MB ou mais, nas partições de dados. Mostra nome, pasta e tamanho; nada é apagado.
- **Desfragmentação**: não existe como função; a tela explica por que não é recomendada em memória flash.
- **Gerar relatório**: grava `relatorios/microsd_AAAAMMDD_HHMMSS.txt` na pasta do hub, sem sobrescrever outro arquivo.

O hub nunca formata, reparticiona, desmonta ou mexe no boot. Ferramenta ausente ou sem permissão aparece como tal, sem simular resultado.

## Data e hora

**Configurações → Informações do console → Data e hora** mostra o relógio real do sistema (com segundos), o dia da semana, o fuso e a diferença para UTC, o estado da sincronização e da internet.

- **Sincronização automática (internet)**: liga/desliga o serviço de horário do próprio sistema (`timedatectl set-ntp`, o mesmo comando dos scripts do dArkOS). Estados: Sincronizado, Sincronizando, Aguardando conexão, Sincronização indisponível, Modo manual, Erro ao atualizar. **Sincronizar agora** pede uma sincronização e só confirma quando o sistema registra uma sincronização nova. Sem internet, a hora atual é mantida e o serviço do sistema tenta de novo sozinho. Com a sincronização ligada, se o console ligar já conectado à internet, o próprio sistema acerta a data e a hora.
- **Fuso horário**: todas as zonas da base IANA instalada (`/usr/share/zoneinfo`), por região (L1/R1) e com pesquisa (Y). Mostra a diferença para UTC e a hora local antes de aplicar (`timedatectl set-timezone`). O instante do relógio não muda; o horário de verão segue as regras da base.
- **Ajustar data e hora manualmente**: dia, mês, ano, hora, minutos e segundos, com **SALVAR ALTERAÇÕES** e confirmação. Grava no relógio do sistema (`timedatectl set-time`) e desliga a sincronização antes.
- **Formato da hora** (24 h ou 12 h) e **Formato da data** (DD/MM/AAAA, MM/DD/AAAA ou AAAA-MM-DD): só mudam a exibição no hub (relógio do topo, menu e datas das telas).
- Alterações no sistema usam `sudo -n` quando o sistema nega o comando normal (no dArkOS o polkit vem desligado). Sem permissão, a tela avisa e nada muda. O hub não guarda senhas.

## Verificador de compatibilidade

Na Central de Conteúdo, o port em destaque mostra uma etiqueta: **COMPATÍVEL**, **EXPERIMENTAL**, **INCOMPATÍVEL** ou **NÃO VERIFICADO**. A página do port traz o resumo, e **Y** abre **Ver detalhes da compatibilidade**: o que foi detectado no console, o que o port exige, o que foi atendido, o que falta saber e o motivo da classificação.

- O console é identificado uma vez na abertura, sem internet: modelo (Analisador de Console ou Device Tree), SoC, arquitetura, sistema e versão, kernel, glibc, RAM, tela, gráficos, PortMaster e runtimes instalados. Muda o sistema ou os runtimes? A análise é refeita e a tela avisa.
- Os requisitos vêm do catálogo (campos `compat` ou `attr`, veja `docs/CATALOGO.md`). Sem requisitos, o port fica **NÃO VERIFICADO**: o hub não inventa nada e não marca como incompatível por falta de dados.
- Somente análise: nada é executado, instalado ou alterado.

## Ajustes do console (R36 Control)

**Configurações → Informações do console → Ajustes do console (R36 Control)** traz para o hub os ajustes do "R36 Control" do dArkOSRE, com os mesmos arquivos e comandos do sistema (`/etc/r36_config.ini`, lido pelo `r36_config.sh` a cada boot). **Aparência e personalização → Controle do LED** abre esta mesma tela.

- **LED de aviso da bateria**: o LED perto de FN/START/SELECT é ligado por um pino GPIO e controlado pelo serviço `batt_led.service` do sistema. A lista mostra os perfis do próprio dArkOSRE para a variante do aparelho (R36S original, clone ou Soy Sauce), com a explicação de cada um (ex.: "Vermelho com a bateria em 20% ou menos"). Com o carregador ligado, o hardware assume o LED.
- **Correção de gama** (0.4 a 1.8): vale no próximo boot. Para testar na hora: segure R3 e use esquerda/direita.
- **Saída de áudio**: alto-falante + fone (com detecção) ou só alto-falante. Aplica na hora e reinicia o `ogage`.
- **Volume ao ligar**: 10% a 100% ou Manual (o sistema não força o volume).
- **Ver configuração atual** e **Apagar configuração** (o sistema recria com os valores padrão no próximo boot).
- Alterações usam `sudo -n`, como o script do sistema. Fora do dArkOSRE, a tela informa que os ajustes não existem.

## Sair, desligar e reiniciar

**Sair** (no menu ou com B) abre uma lista: **Sair**, **Reiniciar lista** (reinicia o EmulationStation para mostrar ports novos), **Reiniciar console**, **Desligar console** e **Voltar**. Desligar e reiniciar pedem confirmação. O app fecha primeiro, com os mesmos avisos do Sair (downloads, FTP), e o lançador grava o cartão (`sync`) antes de desligar ou reiniciar.

## Gerenciador de Wi-Fi

Configurações → Rede e conectividade → **Gerenciar Wi-Fi** pesquisa redes próximas e conecta o console à internet.

- Usa o gerenciador de rede do próprio dArkOSRE: **NetworkManager** (comando `nmcli`), o mesmo que a opção "Wifi Toggle" do sistema instala e liga. O hub não tem um gerenciador próprio; só faz pedidos ao NetworkManager.
- **REDES DISPONÍVEIS** (L1/R1 troca de aba, **Y** pesquisa de novo): nome, barras de sinal, cadeado para rede protegida e as marcas CONECTADA/SALVA. Só aparecem redes que o sistema encontrou.
- Ao escolher uma rede: sinal, segurança, campo de senha (teclado na tela com maiúsculas, números, símbolos e espaço; **Y** mostra/oculta), **CONECTAR** e **CANCELAR**. A senha precisa ter de 8 a 63 caracteres. Se a senha estiver errada, dá para digitar de novo sem pesquisar outra vez.
- O hub só mostra "Conectado" quando o NetworkManager informa a interface ativa **e** com IP. Mensagens: conectando, conectado, senha incorreta, rede indisponível, falha, tempo limite e adaptador não encontrado.
- **REDES SALVAS**: conectar, desconectar e esquecer (com confirmação). A senha nunca é exibida.
- Interruptor do Wi-Fi (liga/desliga o rádio pelo NetworkManager) aparece só quando o sistema informa o estado do rádio.
- Em Rede e conectividade também aparecem rede Wi-Fi, tipo de conexão, sinal, gateway e DNS, atualizados a cada poucos segundos. O IP 127.0.0.1 nunca é mostrado como conexão.
- **Senha**: vai para o NetworkManager pela entrada padrão do `nmcli` (não aparece na lista de processos) e fica guardada por ele em `/etc/NetworkManager/system-connections` (só o root lê). O hub não grava a senha em arquivos, logs ou relatórios e não envia nada para fora.
- Redes corporativas (802.1X/EAP) e WEP não são suportadas por aqui.
- Se houver download em andamento, o hub avisa antes de trocar ou desligar a rede. Nada é cancelado pelo hub. O FTP passa a usar o IP novo sozinho.
- Sem `nmcli` no sistema, a tela explica que é preciso ativar o Wi-Fi pelo "Wifi Toggle" do dArkOSRE primeiro.

## Ferramentas de manutenção

Em Central de Conteúdo → Ports Utilitários e Ferramentas → Manutenção ficam 4 ferramentas integradas ao hub (não são downloads). Todas são somente leitura e só trabalham quando você pede:

- **Analisador do cartão SD**: espaço total/usado/livre, tamanho de cada pasta (A entra, B volta) e os maiores arquivos. A soma é do tamanho dos arquivos; o espaço ocupado no cartão pode ser um pouco maior.
- **Verificador de integridade dos ports**: ÍNTEGRO, ATENÇÃO ou ERRO para cada port do console (instalado pelo hub, pelo PortMaster ou copiado a mão), com o detalhe de cada verificação e o que não pôde ser confirmado.
- **Verificador do cartão SD** (também em Configurações → Informações do console): fabricante, modelo, capacidade informada, data, série e **classe de velocidade** (Classe 2–10, U1/U3, V6–V90, A1/A2, lidas do registro SSR do cartão quando o sistema o informa) que o próprio cartão informa, pistas de cartão genérico/falsificado (inclusive cartão sem classe declarada e gravação abaixo do mínimo da classe) e teste rápido de velocidade (64 MB, apagado no fim). Não faz o teste completo de capacidade.
- **Diagnóstico de rede**: Wi-Fi, nome da rede, IP, gateway, DNS, sinal e testes reais de internet e do GitHub. Wi-Fi conectado e internet funcionando aparecem separados.

A tela inicial mostra no rodapé o estado da rede (CONECTADO / IP ou DESCONECTADO / IP: INDISPONÍVEL), atualizado em segundo plano.

## Downloads em segundo plano

A central abre pelo botão **START** (em qualquer tela) ou pela opção **Downloads em segundo plano** do menu principal, logo abaixo de Meus Ports. Os dois caminhos levam à mesma tela e aos mesmos dados.

- Cada item mostra nome, capa ou ícone, tipo de operação, estado (AGUARDANDO, BAIXANDO, EXTRAINDO, INSTALANDO, CONCLUÍDO, ERRO, CANCELADO), % e barra reais, tamanho baixado/total, velocidade e as etapas Download / Extração / Instalação, cada uma com seu resultado (etapas que não se aplicam aparecem como PULADA).
- O selo INSTALADO só aparece depois que a instalação termina e o port é encontrado no console.
- Um download por vez; os outros ficam na fila. Trocar de tela não interrompe nada. Os downloads só continuam com o app aberto: ao sair com algo em andamento, o app pergunta antes.
- **A** mostra a janela de progresso (onde **B** cancela) ou tira um item da fila. **X** pede confirmação e limpa só o histórico (jogos e arquivos não são apagados; o que está em andamento continua).
- O histórico (downloads.json) guarda nome, data, resultado, tamanho, velocidade média e etapas, sem dados sensíveis, e continua depois de reabrir o app.

## Atualizações

Configurações → Downloads e atualizações → **Atualizações** reúne: **Atualização local**, **Atualização via rede**, **Versão atual**, **Histórico de atualizações** e **Gerenciar backups**. Nada é instalado sem confirmação.

**Atualização local**
1. Copie o pacote (`.zip`, `.7z` ou `.rar`) para `r36sporthub/update/` (pelo FTP ou pelo Gerenciador de arquivos). A pasta é criada sozinha e tem um `LEIA-ME.txt`.
2. Abra Atualização local: aparecem nome, formato, tamanho, data e a versão (lida do manifesto).
3. Escolha o pacote: o hub lê o conteúdo sem extrair e mostra tipo, versão, compatibilidade, arquivos que serão substituídos e criados, tamanho do backup e qualquer problema.
4. Confirme. O progresso mostra cada etapa: verificando, validando a integridade, extraindo, conferindo o SHA-256, preparando o backup, instalando e finalizando (porcentagem só quando dá para calcular).
5. No fim, **Reiniciar o app agora** abre a versão nova.
6. Na primeira abertura da versão nova aparece a tela **Novidades**, com o resumo, **O que mudou** e **Correções** (vem do manifesto). Antes de instalar, Y mostra a mesma lista; no Histórico, Y mostra as novidades de cada atualização.

Formatos: o hub usa o 7-Zip que vem com ele (`bin/7zzs`, ZIP/7Z/RAR) e, se não funcionar, 7z/7zz/7za, `unzip` ou `unrar` do sistema. A tela Atualizações mostra os formatos realmente disponíveis no console.

**Atualização via rede**: verifica a fonte oficial, mostra a versão instalada e a disponível e as novidades, baixa o pacote para a pasta `update` com progresso real (B cancela) e abre a mesma análise e instalação da atualização local. A fonte ainda não está configurada: coloque o link em `r36sporthub/update_url.txt` (ou `C.UPDATE_URL` no `config.lua`):
1. **Repositório no GitHub** (`https://github.com/USUARIO/REPO`): o hub lê a última Release (tag = versão, primeiro `.zip` anexado = pacote).
2. **JSON** (ex.: "raw" do GitHub): `{ "version": "0.4.1", "url": "https://.../pacote.zip", "size": 12345, "sha256": "...", "notes": "O que mudou" }`.

**Pacote** (`update_manifest.json` na raiz, ou numa única pasta dentro do arquivo):
```json
{ "format": 1, "name": "R36S PORT HUB", "version": "0.4.1", "version_label": "0.4.1 BETA",
  "min_version": "0.4", "max_version": "0.4.99", "date": "2026-11-01", "description": "Resumo da versão",
  "changes": ["O que mudou"], "fixes": ["O que foi corrigido"],
  "files": [ { "path": "r36sporthub/game.love", "size": 7753694, "sha256": "..." } ] }
```
O pacote completo da distribuição também traz o manifesto. Um pacote sem manifesto só é aceito se tiver a estrutura do hub (`R36S PORT HUB.sh` + `r36sporthub/game.love`); a versão é lida de dentro do `game.love` e ele aparece como "identificação parcial", com aviso.

**Segurança**
- Só "R36S PORT HUB.sh" e arquivos dentro de `r36sporthub/` podem ser trocados. Nunca `conf/`, `tmp/`, `logs/`, `gravacoes/`, `update/`, `backups/`, `catalog.json`, `catalog_url.txt`, `update_url.txt`, ports, PortMaster, EmulationStation ou o sistema.
- Recusa `../`, caminhos absolutos, links, itens fora do pacote, arquivos fora do manifesto, tamanho ou SHA-256 diferentes e destinos que sejam links ou levem para fora do hub.
- Teste de integridade do arquivo compactado, extração numa pasta temporária e nova conferência no disco. Nenhum script do pacote é executado.
- Pacote com versão mínima/máxima fora da instalada não é instalado. Mesma versão ou mais antiga: só com confirmação e aviso.

**Backup e recuperação**
- Antes de trocar, os arquivos atuais vão para `r36sporthub/backups/<data>_v<versão>/` (com `meta.json` e a lista dos arquivos novos). Ficam os 3 mais recentes; o mais antigo só é apagado depois que uma atualização nova termina bem.
- Se um arquivo falhar, tudo volta na hora. Se o console desligar no meio, o lançador restaura o backup na próxima abertura.
- Depois de instalar, a primeira abertura precisa ser confirmada pelo app; se a versão nova fechar antes, o lançador volta sozinho para a anterior e abre de novo (o histórico registra).
- **Gerenciar backups**: restaurar (o estado atual também vai para um backup antes) ou apagar, sempre com confirmação.

**Histórico**: versão anterior, versão instalada, data, origem (local, rede, backup ou recuperação automática), pacote, resultado e erro.

Para quem desenvolve: `tools/make_update.py` gera o manifesto do pacote completo (o `build.sh` já chama), guarda a base da versão entregue (`baseline`) e monta o ZIP incremental só com os arquivos novos ou alterados (`incremental`). Veja `docs/ENTREGAS.md`.

## Temas

Configurações → Aparência e personalização → **Tema**: **Tema Padrão** (original) e **NEON GRID — Gaming Dashboard** (identidade própria: fundo escuro com grade e verde neon; a tela inicial vira um dashboard e a página do port ganha as ações Instalar, Iniciar, Remover e Favoritar). A aplica na hora; a escolha fica salva e volta ao abrir o app. **Baixar novos temas** ficará ativo quando o catálogo de temas no GitHub for configurado. Detalhes em `docs/TEMAS.md`.

### NEON GRID — dashboard da tela inicial

Com o NEON GRID ativo, a tela inicial vira um dashboard:

- **Cabeçalho**: logo, nome do tema e versão, aviso de versão nova (quando houver), Wi-Fi, bateria, data e hora.
- **Destaque**: capa grande, nome, JOGO/UTILITÁRIO, plataforma (se o catálogo informar), categoria, tamanho, se está instalado e a compatibilidade. **L1/R1** trocam o destaque.
- **Atalhos**: Conteúdo, Categorias, Meus Ports, Favoritos, Downloads e Configurações (com contadores quando há o que mostrar).
- **Jogos recentes**: ports abertos pela lista de Ports do EmulationStation (lastplayed) e instalados pelo hub, mais novos primeiro.
- **Novidades do catálogo**: o que o catálogo marca como novo ou atualizado e atualizações disponíveis para o que está instalado.
- Ao escolher um cartão, o destaque mostra os dados dele (**SELECIONADO**).

Controles: **direcional** navega entre destaque, atalhos e fileiras; **A** abre; **X** favorita/desfavorita o cartão; **Y** mostra as informações (tipo, categoria, plataforma, desenvolvedor, tamanho, estado e compatibilidade); **SELECT** abre e fecha o **painel lateral de navegação rápida** (Central de Conteúdo, Categorias, Meus Ports, Favoritos, Central de Downloads, Novidades, Temas, Configurações, Sobre e Sair; com versão nova, "Atualizar o hub agora" aparece primeiro); **START** continua abrindo os Downloads; **B** sai (como no menu clássico).

### NEON GRID — página do port

Capa em destaque, grade com Plataforma, Categoria, Tamanho, Desenvolvedor, Compatibilidade e Estado ("não informado" quando o catálogo não traz o dado), descrição rolável e as ações conforme o estado:

- **INSTALAR / REINSTALAR / ATUALIZAR**: mesmo fluxo de sempre (com as confirmações).
- **INICIAR**: só para ports instalados com script `.sh` na pasta de ports. Pede confirmação; o hub fecha, o launcher roda o script do port com o ambiente original do sistema e, ao sair do jogo, o hub abre de novo na página do port. Se o FTP estiver ligado, ele é parado antes.
- **REMOVER**: abre a mesma confirmação de desinstalação de Meus Ports.
- **FAVORITAR / DESFAVORITAR** (também com SELECT).

Esquerda/direita escolhem a ação, cima/baixo rolam a descrição, Y abre a compatibilidade e B volta.

No **Tema Padrão**, a página do port também mostra o botão **INICIAR** (entre o botão principal e VOLTAR) quando o port está instalado e tem script `.sh` na pasta de ports. Funciona do mesmo jeito: confirmação, o hub fecha, o jogo abre e o hub volta na página do port.


## Loja de Temas (EmulationStation)

Utilitários & Ferramentas → Ferramentas de sistema → **Loja de Temas**: identifica o sistema do console (prioridade dArkOSRE) e mostra só os temas compatíveis, com pré-visualização, filtros, instalação segura (sem executar scripts, com backup e proteção contra ZIP Slip) e desinstalação dos temas instalados pelo app. O tema nunca é aplicado sozinho: escolha-o no EmulationStation. Detalhes em `docs/LOJA_TEMAS.md`.

A loja reconhece também os temas que já estão no console (de fábrica, do usuário, do hub e do ThemeMaster), mostra INSTALADO / ATIVO / INSTALAÇÃO INCOMPLETA / DISPONÍVEL / NÃO VERIFICADO, ativa um tema pelo `ThemeSet` do EmulationStation (o hub fecha e o EmulationStation reinicia) e remove com segurança temas que não são do sistema. Detalhes em `docs/LOJA_TEMAS.md`.

## Formatos de pacote

O instalador aceita **ZIP**, **RAR** (RAR4 e RAR5) e **7z**. O ZIP usa o `unzip` do sistema. RAR e 7z usam o **7-Zip 26.02** oficial para ARM64, incluso em `r36sporthub/bin/7zzs` (binário estático, licença em `licenses/7-Zip-License.txt`). Antes de usar, o binário é copiado para `/tmp`, porque o cartão pode não permitir executar programas. Se o console já tiver `7zz`/`7z` ou `unrar`, eles servem como alternativa.

Pacotes RAR/7z feitos no Windows não guardam permissões. Por isso, depois de instalar, o hub dá permissão de execução aos scripts `.sh` e aos binários do port, e permissão de acesso às pastas. Arquivos protegidos por senha são recusados com uma mensagem clara.

## Como a instalação funciona

1. Confere a pasta de ports, permissão de escrita e espaço livre.
2. Baixa o ZIP em segundo plano (curl → wget), com retomada em quedas de Wi-Fi.
3. Verifica: download completo, tamanho exato, assinatura ZIP (`PK`), checksum opcional e caminhos inseguros.
4. Confere o espaço para descompactar e extrai numa **pasta temporária** (`r36sporthub/tmp`, no mesmo cartão).
5. Analisa a estrutura: remove pastas-embrulho e lixo, exige um `.sh` na raiz e ignora itens protegidos.
6. Se algo já existir em `/roms/ports`, **pergunta antes de substituir**; na atualização, saves e arquivos extras do usuário são mantidos.
7. Move para `/roms/ports` preservando a estrutura, aplica `chmod +x`, apaga o ZIP temporário e registra a instalação.
8. Mostra sucesso (com opção de reiniciar a lista do EmulationStation) ou o erro, sem deixar lixo para trás.

Erros tratados: sem conexão, link removido (HTTP 4xx/5xx), página HTML no lugar do ZIP, download incompleto, ZIP corrompido, checksum diferente, falta de espaço (para baixar e para extrair), sem permissão, pacote sem script, cancelamento pelo usuário e interrupção (temporários são limpos na próxima abertura).

## Catálogo

Ainda não há catálogo definitivo: o app vem sem jogos (a loja mostra "Nenhum port ainda"). Para publicar o catálogo real, veja **`docs/CATALOGO.md`** — basta um JSON online e a URL em `r36sporthub/catalog_url.txt`.

## Estrutura do projeto

```
port/                         → o que vai para /roms/ports
  R36S PORT HUB.sh            → lançador (PortMaster + LÖVE 11.5)
  r36sporthub/
    game.love                 → o app (gerado por tools/build.sh)
    bin/fetch.sh              → downloads (curl/wget, retomada, cancelamento)
    gameinfo.xml, cover.png, licenses/
src/                          → código-fonte do app (Lua / LÖVE 11.5)
  main.lua, conf.lua, config.lua
  core/   catalog, installer, manifest, scan, covers, fetcher, input, music, runtimes, wifi, wifijob
  threads/install_thread.lua  → download + verificação + extração + instalação
  threads/fetch_thread.lua    → catálogo e capas
  threads/runtimes_thread.lua → atualização dos runtimes do PortMaster
  threads/pm_thread.lua → Gerenciador do PortMaster (core/pmcore.lua, core/pmmanager.lua)
  threads/wifi_thread.lua     → pedidos ao NetworkManager (nmcli) sem travar a tela
  ui/     theme, gfx, overlay, screens/ (splash, language, disclaimer, menu, store, categories, details, settings, about…)
  lib/    json, util, i18n
  i18n/   en.lua, ru.lua           → traduções (a chave é o texto em português)
  catalog/catalog.json        → catálogo de exemplo embutido
  dev/                        → testes automáticos (fora do pacote final)
docs/   ANALISE_KMP.md, CATALOGO.md, catalog.example.json
tools/build.sh                → gera game.love e o ZIP de instalação
```

Para gerar o pacote: `tools/build.sh` → `build/R36S-PORT-HUB-BETA.zip`.

Dados do app no console: `/roms/ports/r36sporthub/conf/love/r36sporthub/` (cache do catálogo, capas, `installed.json`, `settings.txt` com idioma, aviso aceito e música). Log da última execução: `/roms/ports/r36sporthub/log.txt`.

## Licenças

Fontes Press Start 2P, Chakra Petch e Inter (recorte cirílico): SIL Open Font License (em `licenses/`). LÖVE: licença zlib. Os jogos e ports listados pertencem aos seus respectivos autores.

Feito pela comunidade, para a comunidade!
