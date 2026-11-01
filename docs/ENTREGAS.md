# Regra de entrega do R36S PORT HUB

Padrão combinado entre o desenvolvimento e o usuário.

| Pedido | O que é entregue |
|---|---|
| **"ATUALIZAÇÃO DO PROJETO"** | Um **ZIP incremental** pronto para `r36sporthub/update/`: só arquivos novos ou alterados desde a última versão entregue, com `update_manifest.json` (versão, versão mínima, data, descrição, lista de arquivos com tamanho e SHA-256). Instala pela **Atualização local** do próprio hub. Não leva dados do usuário (configurações, logs, gravações, catálogo, links). |
| **"PROJETO COMPLETO"** | O **texto consolidado do projeto para o Claude IA**: funcionalidades aprovadas, alterações desde a última versão consolidada, arquitetura, requisitos e regras, separando o que está implementado, planejado e ainda não implementado. |
| **"Me passe o projeto"** | Pacote completo para instalar (`R36S-PORT-HUB-BETA.zip`, com manifesto), código-fonte e `temas.json`. |

## Como montar a atualização incremental

1. Aumente `C.VERSION` e `C.VERSION_NUM` em `src/config.lua` (ex.: `0.4.1 BETA` / `0.4.1`).
2. `tools/build.sh`
3. `python3 tools/make_update.py incremental --base releases/entregue.json --ports build/ports --out build/R36S-PORT-HUB-update-0.4.1.zip`
   (`--min` padrão = versão da base; `--desc "texto"` opcional).
   Notas que o hub mostra antes de instalar e na primeira abertura: `--mudanca "texto"` e `--correcao "texto"` (podem repetir) ou `--notas NOTAS.txt` com linhas `+ o que mudou` e `* o que foi corrigido`. Toda atualização entregue leva essas notas.
4. Depois de entregar, grave a nova base: `python3 tools/make_update.py baseline build/ports releases/entregue.json`.

Observação: todo o código e as imagens ficam dentro do `game.love` (cerca de 7,7 MB), então quase toda atualização leva esse arquivo inteiro. O ganho do pacote incremental está nos demais arquivos.

A base (`releases/entregue.json`) é gravada sempre que um pacote completo ou incremental é entregue. O console precisa ter recebido antes um pacote completo com o Gerenciador de atualizações (0.4 BETA ou mais nova).
