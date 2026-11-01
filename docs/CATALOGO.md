# Catálogo de ports (JSON)

O R36S PORT HUB lê a lista de jogos de um arquivo JSON. Para adicionar, editar ou remover jogos **não é preciso mudar o aplicativo**: basta atualizar o JSON publicado.

## Onde o app procura o catálogo

1. **URL online** – definida em `src/config.lua` (`C.CATALOG_URL`) **ou** no arquivo `/roms/ports/r36sporthub/catalog_url.txt` (uma linha com a URL; tem prioridade).
   O último catálogo baixado fica em cache e é usado quando o console está sem internet.
2. **Catálogo local** – `/roms/ports/r36sporthub/catalog.json` (útil para testar antes de publicar; só é usado quando não há URL configurada).
3. **Catálogo embutido** no app, que vem **vazio** (sem jogos de exemplo). A loja mostra "Nenhum port ainda" até um catálogo ser configurado.

A URL precisa entregar o JSON direto (sem página HTML). Exemplo:

- GitHub: `https://raw.githubusercontent.com/<usuario>/<repo>/main/catalog.json`

## Formato

```json
{
  "catalog_version": 1,
  "title": "R36S PORT HUB - catálogo oficial",
  "updated": "2026-11-01",
  "categories": [
    { "id": "acao", "name": "Ação" },
    { "id": "plataforma", "name": "Plataforma" }
  ],
  "ports": [
    {
      "id": "meu-jogo",
      "name": "Meu Jogo",
      "description": "Descrição completa. Pode ter várias linhas (use \\n).",
      "short": "Resumo de uma linha (opcional).",
      "category": "plataforma",
      "version": "1.2",
      "size_bytes": 157910476,
      "download_url": "https://exemplo.com/r36s-meu-jogo/Meu%20Jogo.zip",
      "cover": "https://exemplo.com/r36s-meu-jogo/capa.png",
      "md5": "0123456789abcdef0123456789abcdef",
      "author": "Nome de quem fez o port",
      "requires_files": false,
      "featured": true
    }
  ]
}
```

### Campos de cada port

| Campo | Obrigatório | Descrição |
|---|---|---|
| `id` | sim* | Identificador único (letras, números, `-`). Não mude depois de publicado: é ele que liga o port ao registro de instalados. *Se faltar, é gerado a partir do nome. |
| `name` | sim | Nome exibido. |
| `description` | não | Texto da página do port (rolável). |
| `short` | não | Resumo da lista; se faltar, usa a 1ª linha da descrição. |
| `category` | não | Categoria do port. Use um dos ids oficiais abaixo; nomes como `"Ação"` ou apelidos em inglês (`racing`, `shooter`…) também são reconhecidos. Um nome diferente vira uma categoria extra na área do port. |
| `section` | não | Área da loja: `"games"` (Ports de Jogos) ou `"tools"` (Utilitários & Ferramentas). Se faltar, é deduzida pela categoria; sem categoria conhecida, vai para Ports de Jogos. |
| `version` | não | Versão do port. Se mudar, quem já instalou vê **ATUALIZAR**. |
| `size_bytes` | recomendado | Tamanho exato do ZIP em bytes. Usado para o progresso, checagem de espaço e para confirmar que o download veio completo. Também aceita `size` como texto (`"150 MB"`), só para exibição. |
| `size_label` | não | Texto do tamanho, se quiser personalizar. |
| `download_url` | sim** | Link direto do pacote: **ZIP, RAR (RAR4/RAR5) ou 7z**. O formato é reconhecido pelo conteúdo do arquivo, não pela extensão. **Sem link o botão aparece como "EM BREVE". |
| `cover` | não | URL de uma imagem PNG/JPG (recomendado 300×400, até ~150 KB). Sem capa, o app gera uma capa retrô. |
| `sha256` / `md5` | não | Checksum do ZIP. Se informado, arquivo diferente = "arquivo corrompido". |
| `author` | não | Quem fez o port. |
| `requires_files` | não | `true` mostra o aviso "Requer arquivos do jogo original". |
| `notes` | não | Observações extras exibidas após a descrição. |
| `featured` | não | `true` coloca o port no "Em destaque" do menu. |
| `pm_name` | não | Nome do pacote no PortMaster (ex.: `"sprout.zip"`). Liga o port do catálogo a um jogo instalado pelo PortMaster mesmo que os nomes sejam diferentes. |
| `test_type` | não | Só para a categoria `testes_de_controles`: `"analogicos"`, `"botoes"` ou `"completo"` (padrão). Os ids antigos `testes_de_analogicos` e `testes_de_botoes` continuam aceitos e viram esses tipos. |
| `added` | não | Data em que o port entrou no catálogo (`AAAA-MM-DD`). Aparece em Novidades como **NOVO**. |
| `updated_at` | não | Data da última atualização do port (`AAAA-MM-DD`). Aparece em Novidades como **ATUALIZADO**. |
| `changelog` | não | O que mudou na versão (texto curto, exibido em Novidades). |
| `install_check` | não | Lista de arquivos que indicam que o port já está instalado (ex.: `["Meu Jogo.sh"]`). Se faltar, o app usa o nome do jogo e o nome do ZIP. |
| `allow_no_script` | não | `true` aceita pacotes sem `.sh` na raiz (padrão: recusa, para não instalar no lugar errado). |

### Compatibilidade (opcional): `compat` ou `attr`

Usados pelo **Verificador de compatibilidade** da loja. Todos os campos são opcionais; informe só o que foi realmente testado ou documentado pelo port. Sem nenhum deles, o port aparece como **NÃO VERIFICADO** (nunca como incompatível).

```json
"compat": {
  "arch": ["aarch64"],
  "os": ["darkosre", "arkos"],
  "os_exclude": ["batocera"],
  "min_os_version": { "darkosre": "2025.05" },
  "min_kernel": "4.4",
  "min_glibc": "2.28",
  "soc": ["rk3326"],
  "min_ram_mb": 1024,
  "resolutions": ["640x480"],
  "min_resolution": "640x480",
  "gpu": ["gles2"],
  "runtimes": ["love_11.5", "mono>=6.12"],
  "libs": ["libSDL2-2.0.so.0"],
  "files": ["$PORTS/meujogo/gamedata/data.pak"],
  "experimental": false,
  "incompatible": "texto (só se o port não funciona em nenhum R36S)",
  "tested": [ { "device": "R36S", "os": "darkosre", "result": "ok", "note": "placa V21" } ],
  "notes": "observações exibidas na tela de compatibilidade"
}
```

| Campo | O que o hub compara |
|---|---|
| `arch` | `uname -m` do console (`aarch64`, `armhf`, `x86_64`; `arm64` = `aarch64`). Diferente → INCOMPATÍVEL |
| `os` / `os_exclude` | sistema detectado (`darkosre`, `darkos`, `arkos`, `amberelec`, `rocknix`, `knulli`, `jelos`, `batocera`). Fora de `os` → EXPERIMENTAL; em `os_exclude` → INCOMPATÍVEL |
| `min_os_version`, `min_kernel`, `min_glibc` | versões do console (abaixo do mínimo → INCOMPATÍVEL) |
| `soc`, `resolutions` | fora da lista → EXPERIMENTAL |
| `min_ram_mb`, `min_resolution` | abaixo → INCOMPATÍVEL |
| `gpu` | `gles`/`gles2`/`gles3`, `egl`, `drm` (bibliotecas e `/dev/dri`) |
| `runtimes` | runtimes do PortMaster instalados (`PortMaster/libs/*.squashfs` e `PortMaster/runtimes/*`). Nome exato ou `familia>=versao`. Ausente → EXPERIMENTAL com aviso; versão instalada abaixo da mínima → INCOMPATÍVEL |
| `libs`, `files` | arquivos nas pastas padrão de bibliotecas / no console (`$PORTS` = pasta de ports). Ausente → EXPERIMENTAL |
| `tested` | testes registrados: `result` `ok`, `issues` ou `fail` no mesmo aparelho/sistema |
| `experimental` | marca o port como EXPERIMENTAL |

O formato `attr` do `port.json` do PortMaster também é aceito: `arch`, `runtime`, `min_glibc`, `exp` (experimental) e `reqs` (mostrados como requisitos que o hub não sabe verificar).

### Categorias oficiais

| Área | ids de `category` |
|---|---|
| Ports de Jogos (`games`) | `acao`, `aventura`, `rpg`, `plataforma`, `corrida`, `luta`, `tiro`, `terror`, `puzzle`, `estrategia`, `arcade`, `esportes`, `classicos` |
| Utilitários & Ferramentas (`tools`) | `manutencao`, `diagnostico_do_sistema`, `testes_de_controles` (tipos: `analogicos`, `botoes`, `completo` no campo `test_type`), `ferramentas_de_sistema` |

Exemplo de utilitário:

```json
{ "id": "teste-botoes", "name": "Teste de Botões", "section": "tools", "category": "testes_de_controles", "test_type": "botoes",
  "version": "1.0", "size_bytes": 123456, "download_url": "https://…/teste-botoes.zip" }
```

### Novidades (opcional, no topo do catálogo)

```json
"news": [
  { "id": "meu-jogo", "type": "new", "date": "2026-11-01", "text": "Chegou à loja!" },
  { "id": "teste-botoes", "type": "update", "date": "2026-11-03", "text": "Agora testa os gatilhos L2/R2." }
]
```

`type` é `new` ou `update`, e `id` precisa existir em `ports`. A tela de Novidades também usa os campos `added`, `updated_at` e `changelog` de cada port e lista as atualizações disponíveis para os ports instalados.

O app também entende o formato simples do KMP (lista com `name`, `downloadUrl`, `sizeBytes`, `genre`).

## Como o pacote do port deve ser montado (ZIP, RAR ou 7z)

O formato é o mesmo do PortMaster — a raiz do ZIP vira a raiz de `/roms/ports`:

```
Meu Jogo.zip
├── Meu Jogo.sh        ← script que aparece no EmulationStation
└── meujogo/           ← pasta com os arquivos do port
    ├── ...
```

O instalador também corrige automaticamente estes casos (sem criar pastas duplicadas):

- `Meu Jogo/Meu Jogo.sh` + `Meu Jogo/meujogo/` (pasta-embrulho)
- `ports/Meu Jogo.sh` ou `roms/ports/Meu Jogo.sh`
- lixo de Mac/Windows (`__MACOSX`, `.DS_Store`, `Thumbs.db`) é ignorado

Itens que nunca são substituídos: `PortMaster`, `PortMaster.sh`, `gamelist.xml` e a pasta do próprio hub.

## Publicando o catálogo (resumo)

1. Publique o `catalog.json` em um endereço que entregue o JSON direto.
2. Coloque em `download_url` e `cover` os links de cada arquivo (o endereço é escolha sua; o app só abre o link que estiver no catálogo).
3. Coloque a URL do `catalog.json` em `catalog_url.txt` (ou em `config.lua`, antes de gerar o `game.love`).

> Confira o link no navegador antes de publicar: o app precisa receber o arquivo, não uma página de aviso.
