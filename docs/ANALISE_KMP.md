# Análise técnica do KMP (referência)

O KMP original **não foi modificado**. Este documento resume o que foi encontrado e o que o R36S PORT HUB reaproveitou.

## Arquitetura e linguagem

| Item | KMP |
|---|---|
| Linguagem | Lua (código ofuscado em `main.lua`, ~97 KB, 1 arquivo) |
| Motor | LÖVE 11.5, via runtime `love_11.5` do PortMaster |
| Lançador | `KMP.sh` → `control.txt` do PortMaster → `get_controls` → `$GPTOKEYB "$LOVE_GPTK"` → `$LOVE_RUN game.love` |
| Resolução lógica | 640×480, escalada para a tela |
| Dados do app | `XDG_DATA_HOME=$GAMEDIR/conf/` → `conf/love/kdownloader_pm/` (configurações e cache do catálogo) |
| Catálogo | JSON baixado de um Google Apps Script (planilha) para `/tmp/kpm_catalog.json`, com cache local |
| Hospedagem | Pixeldrain (também converte links do Google Drive e Dropbox) |

## Controles físicos

- `love.gamepadpressed` com o mapeamento SDL fornecido pelo PortMaster (`SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"`).
- Mapa: direcional → navegação, **A** confirmar, **B** voltar, **X/Y** ações, **L1/R1** página, **START/SELECT** menu.
- Também trata `love.keypressed` (teclas geradas pelo gptokeyb) e repetição ao segurar direcionais.

## Como os ports são organizados e executados

- Destino: `/roms/ports` (SD1) ou `/roms2/ports` (SD2).
- O ZIP é extraído **diretamente** dentro de `/roms/ports` com `unzip -o` (sobrescreve sem perguntar).
- Depois roda `chmod +x /roms/ports/*.sh`.
- O EmulationStation lista cada `Jogo.sh` da raiz de `/roms/ports`; a pasta de dados fica ao lado (`jogo/`). Por isso o KMP pede para reiniciar o EmulationStation.
- "Instalado" = existe `/roms/ports/<nome>` ou `/roms/ports/<nome>.sh`.

## Download

- Em `love.thread` (não trava a interface), com `curl -L -s -k` e fallback para `wget`.
- Progresso: a thread principal mede o tamanho do arquivo `.part` e compara com `sizeBytes` do catálogo.
- Verificação: os primeiros bytes precisam começar com `PK`; se vier HTML/JSON, mostra o título da página como erro.
- Espaço: `df -P -m`. Capas baixadas em `/roms/ports/images`.

## O que foi reaproveitado no R36S PORT HUB

- Mesmo **runtime e lançador** (PortMaster + LÖVE 11.5 + gptokeyb + `XDG_DATA_HOME` na pasta do port).
- Mesma estratégia de **controles** (gamepad SDL + teclas do gptokeyb, com filtro de duplicatas).
- **Download em thread** com curl → wget, user-agent e acompanhamento pelo tamanho do `.part`.
- Verificação do cabeçalho `PK` e mensagem clara quando o servidor devolve uma página HTML.
- Detecção de "já instalado" pelo nome do `.sh` (para ports instalados por fora do hub).
- `chmod +x` nos scripts e aviso para reiniciar o EmulationStation.

## O que foi feito diferente (melhorias exigidas)

| KMP | R36S PORT HUB |
|---|---|
| Extrai direto em `/roms/ports` com `-o` (sobrescreve) | Extrai numa pasta temporária, analisa e só então move; **pede confirmação** antes de substituir |
| Pastas-embrulho viram diretórios duplicados | Remove embrulhos (`Jogo/Jogo.sh`, `ports/…`, `roms/ports/…`) |
| Atualização apaga arquivos extras do usuário | Atualização **mescla**: arquivos do port são atualizados, saves e dados do jogo são mantidos |
| Sem cancelamento real do curl | Cancela o processo de download (PID) e limpa os temporários |
| `-k` sempre (sem verificar certificado) | Verifica o certificado; só usa `-k` se o console falhar no TLS |
| Sem checagem de tamanho exato/checksum | Confere tamanho exato, `sha256`/`md5` (opcional), CRC do ZIP e caminhos inseguros |
| Espaço só para o ZIP | Checa espaço para o ZIP **e** para o conteúdo descompactado |
| Catálogo preso ao Apps Script | Catálogo JSON em qualquer URL + cache offline |
