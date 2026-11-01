# Loja de Temas (EmulationStation)

Utilitários & Ferramentas → Ferramentas de sistema → **Loja de Temas**.

## Identificação do sistema

Somente leitura, por soma de evidências (nunca por uma informação isolada). Só confiança **alta** conta como confirmada; senão o usuário escolhe o sistema manualmente (SELECT).

| Sistema | Evidências |
|---|---|
| dArkOSRE | `/usr/share/plymouth/themes/text.plymouth` com `title=dArkOSRE (...)` + `/home/ark/.config/.VERSION` + `/etc/emulationstation/themes` → `/roms/themes` |
| dArkOS | `title=dArkOS (...)` + as mesmas evidências |
| ArkOS | `title=ArkOS ...` + as mesmas evidências |
| AmberELEC, ROCKNIX, JELOS | `/etc/os-release` (NAME/ID) + pastas próprias em `/storage` |
| KNULLI, Batocera | `/etc/os-release` + `/userdata` / `batocera.version` |

(As evidências de dArkOS/dArkOSRE foram conferidas nos scripts de build do dArkOS e no `files/ROOTFS` do dArkOSRE-R36.) A versão do EmulationStation não é exposta de forma confiável por esses sistemas: aparece como "não informada".

## Catálogo

O catálogo fica **fora do código**: `catalogo-temas/temas.json` (pronto para subir ao GitHub). Link "raw" em `config.lua` → `C.ES_THEMES_URL` ou no arquivo `es_themes_url.txt` na pasta `r36sporthub`. Sem link, o app usa a cópia `src/catalog/es_themes.json`; o último catálogo online fica em cache.

```json
{
  "catalog_version": 1,
  "updated": "AAAA-MM-DD",
  "systems": { "darkosre": { "name": "dArkOSRE", "themes_dir": "/roms/themes", "sources": ["..."] } },
  "themes": [
    {
      "id": "es-theme-albedo",
      "name": "Albedo",
      "description": "Texto curto",
      "author": "mluizvitor",
      "project_url": "https://github.com/mluizvitor/es-theme-albedo",
      "download_url": "https://github.com/mluizvitor/es-theme-albedo/archive/refs/heads/main.zip",
      "folder": "es-theme-albedo",
      "preview": "https://.../albedo.png",
      "resolution": "640x480",
      "es_min": null, "es_max": null,
      "size": null, "sha256": null,
      "files": 701, "weight": "completo",
      "updated": "2026-05-17",
      "popularity": null,
      "compat": { "arkos": "compativel", "darkos": "experimental", "darkosre": "experimental" }
    }
  ]
}
```

- `compat`: `testado` (testado no aparelho por quem mantém o catálogo), `compativel` (fonte confiável indica funcionamento) ou `experimental`. Um tema só aparece para os sistemas listados aqui.
- `weight`: `leve` (menos de 400 arquivos e sem vídeos/sons) ou `completo`.
- `popularity`: opcional (número); sem ele o filtro "Populares" informa que o catálogo não tem esse dado.
- Temas sem `download_url` http(s), sem `folder` seguro ou sem `compat` são ignorados.

### Conteúdo atual (41 temas)

Gerado a partir da **Emulationstation OGA Theme Gallery** (Jetup13), só com os temas marcados como funcionando em **640x480**. Cada repositório foi conferido (ramo principal, data do último commit, presença de `theme.xml`, quantidade de arquivos). O link de download é o ZIP oficial do GitHub do próprio projeto.

- ArkOS: `compativel` (a galeria testa em aparelhos ArkOS).
- dArkOS: `compativel` para os temas que acompanham as imagens oficiais do dArkOS (Freeplay, Minimal-ArkOS, NES-Box, Switch, Replica); os demais `experimental`.
- dArkOSRE: `compativel` para Colorful v2 (acompanha o dArkOSRE-R36); os demais `experimental`.
- AmberELEC, ROCKNIX, KNULLI, JELOS, Batocera: nenhum tema ainda (sem link direto verificado). As páginas oficiais estão em `systems.*.sources`.
- Nenhum tema está como `testado`: o R36S PORT HUB ainda não testou nenhum no aparelho.

Fontes pesquisadas que **não** viraram downloads diretos: ThemeGallery e R36S-dArkOS-Enhanced-Setup-Tool (djparentx; os anexos da release "themes" não puderam ser conferidos), Minun UI, handhelds.wiki R36S_Themes, páginas de temas de KNULLI/ROCKNIX/Batocera.

## Fontes do ThemeMaster e tamanho de tela

A loja usa as mesmas fontes do ThemeMaster, com a interface do hub (`core/esgallery.lua`):

- **Galeria** (modo "Theme Gallery" do ThemeMaster): a tabela do README da Emulationstation-OGA-Theme-Gallery (Jetup13), com imagem e compatibilidade por tela (480x320, 640x480, 854x480, 960x544, 720x720: funciona / não testado / não funciona). Em 31/10/2026: 55 temas; em 640x480, 41 funcionam, 7 não testados e 7 não funcionam.
- **Coleções do GitHub** (modo "GitHub Repository" do ThemeMaster): os repositórios `es-theme*` de cada autor da lista de coleções do ThemeMaster (Jetup13, CodyV59, farfenkugell, EmuELEC, RetroPie) ou da lista do `ThemeMaster.cfg`, se o ThemeMaster estiver no console. Aparecem no filtro **Coleções**, marcados como não testados.

O catálogo do hub (`temas.json`) vem primeiro e recebe da galeria a compatibilidade por tela; os temas que só existem na galeria ou nas coleções entram depois, sem repetir repositório. Galeria e coleções são consultadas no máximo a cada 6 h (cópia salva em `es_gallery_cache.json`); sem internet, a loja usa a última cópia ou, sem nenhuma, o catálogo do hub. Quando a galeria ou as coleções mudam, a loja muda junto, sem versão nova do hub.

**SELECT** abre a escolha de **Sistema** e de **Tamanho da tela** (esquerda/direita troca a aba). O tamanho começa no detectado pelo console (DRM) e fica salvo quando escolhido. Na tela escolhida, os temas que a galeria marca como "não funciona" não aparecem; os que funcionam vêm antes dos não testados, e a instalação de um não testado avisa antes.

Download: temas só da galeria usam o ZIP do ramo principal (`/archive/HEAD.zip`); os das coleções usam o ramo informado pela API (`/archive/refs/heads/<ramo>.zip`). As validações da instalação são as mesmas abaixo.

## Instalação segura

1. Compatibilidade confirmada (sistema detectado com confiança alta ou escolhido manualmente) e pasta de temas existente (não é criada).
2. Download para `r36sporthub/tmp/estheme_job` com progresso (B cancela).
3. ZIP válido (`unzip -t`), sha256 se informado.
4. Nenhum caminho absoluto, `..` ou link simbólico (ZIP Slip bloqueado).
5. Espaço livre ≥ tamanho descompactado + margem.
6. Extração na pasta temporária; precisa ter `theme.xml` (na raiz ou nas pastas de sistema).
7. Pasta existente → backup em `r36sporthub/tmp/estheme_backups/`.
8. Mover para a pasta de temas. Nenhum script é executado; o tema **não** é aplicado automaticamente.

9. Confirmação: depois de mover, o `theme.xml` precisa estar no destino; senão a versão anterior volta.

Um tema que já existe no console **não é baixado de novo**: X mostra onde ele está. Reinstalar/atualizar só aparece quando o tema está incompleto ou quando o catálogo tem uma versão mais nova que a data instalada, e grava na **mesma pasta** (nunca duplica).

## Reconhecimento dos temas do console

Feito no sistema de arquivos, ao abrir a loja e depois de instalar, remover ou ativar (`core/esthemes_scan.lua`). Não depende só do histórico da loja.

**Como o dArkOS/dArkOSRE organiza os temas** (conferido nos scripts de build):
- `/etc/emulationstation/themes` é um link para `/roms/themes`; com dois cartões, `/home/ark/.emulationstation/themes` aponta para `/roms2/themes`. O hub lê essas pastas (e a pasta configurada no ThemeMaster), sem repetir o mesmo destino.
- Os temas de fábrica são `git clone` colocados em `/tempthemes` e copiados para `/roms/themes` no primeiro boot (`expandtoexfat.sh`). dArkOS (rk3326): freeplay, minimal-arkos, nes-box, switch, replica. dArkOSRE-R36: colorful-v2 e retrooz (além da base do dArkOS).
- O tema em uso é o `ThemeSet` de `~/.emulationstation/es_settings.cfg` (nome da pasta). No dArkOSRE o padrão é `es-theme-retrooz`.

**Identificação de cada pasta** (da evidência mais forte para a mais fraca): marcador `.porthub_theme` gravado pelo hub → registro de instalação do hub → repositório de origem em `.git/config` (cruza com o `project_url` do catálogo, mesmo que a pasta tenha outro nome) → registro do ThemeMaster (`data/<tema>.version`) → nome da pasta **com** `theme.xml`.

**Origem:** do sistema (lista de build do sistema detectado), R36S PORT HUB, ThemeMaster ou do usuário.

**Estados:** ATIVO (é o ThemeSet e a pasta existe), INSTALADO, INSTALAÇÃO INCOMPLETA (sem `theme.xml` ou com `<include>` apontando para arquivo ausente), DISPONÍVEL (só no catálogo) e NÃO VERIFICADO (pasta sem permissão de leitura). "Instalado" nunca vira "ativo" sozinho.

O filtro **Instalados** mostra todos os temas do console, inclusive os que não estão no catálogo (com a imagem do próprio tema ou a do ThemeMaster, quando existir).

## Ativação

Usa o mecanismo do próprio EmulationStation: o `ThemeSet` do `es_settings.cfg` (o mesmo do menu Configurações da interface > Tema). Como o EmulationStation guarda as configurações na memória enquanto roda, o hub não edita o arquivo com ele aberto: grava o pedido em `conf/.es_theme` e fecha. O launcher é filho do EmulationStation (parar o EmulationStation mataria o launcher), então ele entrega a troca para uma unidade separada do systemd (`systemd-run` → `bin/es_theme_apply.sh`), que para o EmulationStation, faz backup (`conf/es_settings.cfg.bak`), troca só a linha `ThemeSet` mantendo dono e permissões do arquivo, confere e **sempre** inicia o EmulationStation de novo (mesmo se a troca falhar). Sem `systemd-run`, o EmulationStation só é reiniciado e o tema não é trocado (a loja avisa na próxima abertura). Só é aceito um nome de pasta que existe numa pasta de temas. Na próxima abertura da loja, o hub confere se o `ThemeSet` realmente mudou e avisa.

## Remoção segura

Com confirmação, para temas do usuário, do hub ou do ThemeMaster. Nunca: temas do sistema, o tema ativo (a loja oferece escolher outro antes), pastas que são links, pastas com links internos, pastas sem `theme.xml` (não dá para confirmar que são só de um tema) ou caminhos fora da pasta de temas.

## ThemeMaster (JohnIrvine1433/ThemeMaster 5.5.1)

Analisado a partir do RAR enviado (nada foi executado): `ThemeMaster.sh` (launcher), `ThemeMaster/ThemeMaster` (script bash com `dialog`), `updater`, `tm-joypad` e `tm-viewer` (binários aarch64), `*.dialogrc`, `changelog`, `ThemeMaster.nfo`.

Como ele funciona: identifica o sistema pelo título do Plymouth (dArkOSRE contém "ArkOS" → pasta `/roms/themes/`); catálogo = tabela da Emulationstation-OGA-Theme-Gallery (Jetup13), com compatibilidade por resolução e imagem de cada tema, guardada em `data/gallery.db` e `data/<repo>.png`; instala baixando o zipball da API do GitHub e copiando por cima da pasta; guarda a data do último commit em `data/<tema>.version` para achar atualizações; considera instalada qualquer subpasta; remove com `rm -rf` sem conferências; não identifica o tema ativo.

Aproveitado na loja do hub: o mesmo catálogo de origem (a galeria OGA, já usada para gerar `temas.json`); a pasta de temas configurada no `ThemeMaster.cfg`; os registros `data/<tema>.version` (origem "ThemeMaster" e aviso de atualização pela data); `data/gallery.db` (autor dos temas que não estão no catálogo do hub) e `data/<repo>.png` (pré-visualização local, sem baixar de novo); a ideia de atualização por data do último commit.

Descartado: a interface `dialog` e os binários `tm-joypad`/`tm-viewer` (a interface do hub é a principal); download pelo zipball da API do GitHub (tem limite de consultas e não traz tamanho; a loja usa o link do catálogo com as validações acima); a cópia por cima sem backup e a remoção sem conferências; o autoatualizador e a contagem de downloads; a instalação em lote.
