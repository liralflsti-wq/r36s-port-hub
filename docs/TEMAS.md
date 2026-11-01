# Temas do R36S PORT HUB

Configurações → **Temas** lista os temas instalados. **A** aplica o tema na hora (sem reiniciar). A escolha fica salva em `theme.txt`, na pasta de dados do app (`r36sporthub/conf/...`), e é aplicada automaticamente ao abrir. Se o tema salvo não puder ser carregado, o app volta ao **Tema Padrão** e avisa.

Nesta versão vêm dois temas: **Tema Padrão** (o visual original) e **Tema Xbox** (inspirado na identidade do Xbox, sem logotipos ou marcas oficiais).

## Onde ficam

| Tipo | Pasta |
|---|---|
| Temas que acompanham o app | `src/themes/<id>/` (dentro do `game.love`) |
| Temas baixados (futuro) | `<dados do app>/user_themes/<id>/` — separados dos arquivos do app; instalar ou remover um tema nunca altera os temas inclusos |

Cada tema é **só dados** (nenhum código é executado):

```
<id>/
  theme.json    identificação, cores, botões e estilo
  preview.png   pré-visualização 320x240 (opcional)
  logo_header.png / logo_menu.png / logo_about.png   logo própria do tema (opcional; altura 32, 74 e 62 px, largura conforme a proporção)
```

## theme.json

```json
{
  "id": "xbox",
  "name": "Tema Xbox",
  "description": "Texto curto exibido na lista",
  "version": "1.0",
  "author": "Nome",
  "preview": "preview.png",
  "colors": {
    "bg0": "#0b0b0b", "bg1": "#1a1a1a", "bg2": "#232323", "bg3": "#1f3a1f", "line": "#2f2f2f",
    "text": "#ffffff", "dim": "#b3b3b3", "faint": "#6e6e6e",
    "accent": "#52b043", "accent2": "#9bd88f",
    "yellow": "#ffb900", "green": "#52b043", "red": "#e81123", "orange": "#f7630c",
    "black": "#000000", "shadow": "#00000080"
  },
  "buttons": { "a": "#52b043", "b": "#e81123", "x": "#2d8cf0", "y": "#ffb900",
    "l1": "#b3b3b3", "r1": "#b3b3b3", "start": "#b3b3b3", "select": "#b3b3b3", "dpad": "#b3b3b3" },
  "style": { "background": "modern", "round": 0.4, "glow": "#107c10", "scanlines": false }
}
```

- `colors`: **todas** as 16 cores são obrigatórias (`#rrggbb` ou `#rrggbbaa`). Faltou uma → o tema é recusado.
  - `bg0` fundo, `bg1` painéis, `bg2`/`bg3` painéis secundários/selecionados, `line` bordas, `text`/`dim`/`faint` textos, `accent` destaque e seleção, `accent2` destaque secundário (informações, barras), `yellow`/`green`/`red`/`orange` avisos e estados.
- `buttons`: cores dos ícones dos botões (opcional).
- `style.background`: `"retro"` (grade e scanlines, do tema padrão) ou `"modern"` (preto com brilho e diagonais).
- `style.round`: cantos (1 = arredondado como o padrão, 0 = retos).
- `style.glow`: cor do brilho do fundo. `style.scanlines`: linhas de TV antiga.

## Catálogo de temas no GitHub (futuro)

**Ainda não está ativo.** A opção **BAIXAR NOVOS TEMAS** só informa que o catálogo remoto ainda será configurado. O endereço fica em `config.lua` → `C.THEMES_CATALOG_URL` (vazio) ou no arquivo `themes_url.txt` na pasta `r36sporthub` (uma linha).

Formato previsto do índice (`themes.json` no repositório):

```json
{
  "themes": [
    {
      "id": "nome-do-tema",
      "name": "Nome exibido",
      "description": "Descrição curta",
      "version": "1.0",
      "author": "Autor",
      "preview": "https://raw.githubusercontent.com/USUARIO/REPO/main/nome-do-tema/preview.png",
      "url": "https://github.com/USUARIO/REPO/releases/download/temas/nome-do-tema.zip",
      "size": 51234,
      "sha256": "..."
    }
  ]
}
```

O `.zip` de cada tema deve conter `theme.json` (e `preview.png`) na raiz. Na integração, o app vai baixar, conferir `sha256`, validar o `theme.json` e instalar em `user_themes/<id>/`.
