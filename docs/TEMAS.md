# Temas do R36S PORT HUB

Configurações → **Temas** lista os temas instalados. **A** aplica o tema na hora (sem reiniciar). A escolha fica salva em `theme.txt`, na pasta de dados do app (`r36sporthub/conf/...`), e é aplicada automaticamente ao abrir. Se o tema salvo não puder ser carregado, o app volta ao **Tema Padrão** e avisa.

Nesta versão vêm dois temas: **Tema Padrão** (o visual original) e **NEON GRID — Gaming Dashboard** (identidade visual própria do hub: fundo escuro com grade, verde neon, cartões de jogos e um dashboard na tela inicial). O NEON GRID substitui o antigo tema verde e preto (id `xbox`): quem usava o tema antigo passa automaticamente para o NEON GRID, sem perder as outras preferências.

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
  "id": "neongrid",
  "name": "NEON GRID",
  "description": "Texto curto exibido na lista",
  "version": "2.0",
  "author": "R36S PORT HUB",
  "preview": "preview.png",
  "colors": {
    "bg0": "#07090b", "bg1": "#10151a", "bg2": "#18212a", "bg3": "#123826", "line": "#243039",
    "text": "#eefcf3", "dim": "#9fb3a8", "faint": "#5d6f66",
    "accent": "#39ff88", "accent2": "#7dffc0",
    "yellow": "#ffd23f", "green": "#39ff88", "red": "#ff4d6a", "orange": "#ff9f43",
    "black": "#000000", "shadow": "#00000090"
  },
  "buttons": { "a": "#39ff88", "b": "#ff4d6a", "x": "#3fb6ff", "y": "#ffd23f",
    "l1": "#9fb3a8", "r1": "#9fb3a8", "start": "#9fb3a8", "select": "#9fb3a8", "dpad": "#9fb3a8" },
  "style": { "background": "neongrid", "layout": "dashboard", "round": 0.7, "glow": "#1fd170", "scanlines": false }
}
```

- `colors`: **todas** as 16 cores são obrigatórias (`#rrggbb` ou `#rrggbbaa`). Faltou uma → o tema é recusado.
  - `bg0` fundo, `bg1` painéis, `bg2`/`bg3` painéis secundários/selecionados, `line` bordas, `text`/`dim`/`faint` textos, `accent` destaque e seleção, `accent2` destaque secundário (informações, barras), `yellow`/`green`/`red`/`orange` avisos e estados.
- `buttons`: cores dos ícones dos botões (opcional).
- `style.background`: `"retro"` (grade e scanlines, do tema padrão), `"modern"` (preto com brilho e diagonais) ou `"neongrid"` (quase preto, grade em perspectiva e horizonte iluminado).
- `style.layout`: `"dashboard"` troca a tela inicial pelo dashboard (destaque, atalhos, jogos recentes, novidades e painel lateral com SELECT) e a página do port pela versão com grade de informações e ações Instalar / Iniciar / Remover / Favoritar. Sem esse campo, as telas clássicas continuam.
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

## Migração do antigo tema (id `xbox`)

- O id antigo `xbox` virou `neongrid`. Ao abrir, se `theme.txt` tiver `xbox`, o hub aplica o NEON GRID e regrava `theme.txt` com `neongrid`.
- O mesmo vale para backups e exportações antigas que trazem `xbox` no `theme.txt`.
- Não há tema duplicado: a pasta `themes/xbox/` não existe mais dentro do `game.love`.
- Voltar para a versão anterior (Atualizações > Backups e recuperação): a 0.4.6 não conhece o id `neongrid` e abre com o Tema Padrão, avisando. As outras preferências continuam.
