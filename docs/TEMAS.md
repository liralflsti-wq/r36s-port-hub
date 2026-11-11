# Temas do R36S PORT HUB

Configurações → **Temas** lista os temas instalados. **A** aplica o tema na hora (sem reiniciar). A escolha fica salva em `theme.txt`, na pasta de dados do app (`r36sporthub/conf/...`), e é aplicada automaticamente ao abrir. Se o tema salvo não puder ser carregado, o app volta ao **Tema Padrão** e avisa. Sem escolha salva (primeira abertura), o app usa o **Pastel Pop Edition**.

Nesta versão vêm quatro temas, nesta ordem:

| id | Nome | Tela inicial | Cartões | Seleção |
|---|---|---|---|---|
| `pastel` | Pastel Pop Edition (padrão, tema claro) | carrossel | brancos com borda colorida | salto + contorno roxo/azul |
| `wiiblue` | Wii Blue Edition | grade de canais | brancos, texto azul-escuro | halo azul + leve aumento |
| `neongrid` | Neon Grid Edition | grade de canais | escuros | contorno neon pulsante + cantos de mira |
| `default` | Tema Padrão | menu em lista | painéis escuros | moldura rosa |

Os três primeiros usam **a mesma estrutura** (mesmas telas, menus, botões, dados e estados): só cores, fundo, cartões e efeitos mudam. O antigo tema verde e preto (id `xbox`) continua sendo migrado para o `neongrid`.

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
  logo_header.png / logo_menu.png / logo_about.png / logo_splash.png   logo própria do tema (opcional; altura 32, 74, 62 e 170 px, largura conforme a proporção)
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
  "style": { "background": "neongrid", "layout": "channels", "round": 0.7, "glow": "#00cfff", "scanlines": false,
    "focus": "#39ff88", "effect": "neon",
    "card": { "fill": "#121a2e", "line": "#26355a", "text": "#f4f8ff", "dim": "#91a5c0", "faint": "#56688a", "icon": "#00f0ff" } }
}
```

- `colors`: **todas** as 16 cores são obrigatórias (`#rrggbb` ou `#rrggbbaa`). Faltou uma → o tema é recusado.
  - `bg0` fundo, `bg1` painéis, `bg2`/`bg3` painéis secundários/selecionados, `line` bordas, `text`/`dim`/`faint` textos, `accent` destaque e seleção, `accent2` destaque secundário (informações, barras), `yellow`/`green`/`red`/`orange` avisos e estados.
- `buttons`: cores dos ícones dos botões (opcional).
- `style.background`: `"retro"` (grade e scanlines, do tema padrão), `"modern"` (preto com brilho e diagonais), `"neongrid"` (quase preto, grade em perspectiva e horizonte iluminado) `"wii"` (degradê azul, faixas horizontais discretas e arcos claros na base) ou `"pastel"` (moldura em degradê ciano/azul/roxo, área clara pontilhada e formas pastel desfocadas).
- `style.layout`: `"carousel"` troca a tela inicial pelo **carrossel** (Pastel Pop); `"channels"` pela **grade de canais** (Wii Blue e Neon Grid); `"dashboard"` usa o painel NEON GRID da 0.4.7. Os dois trocam também a página do port pela versão com grade de informações e ações Instalar / Iniciar / Remover / Favoritar. Sem esse campo, as telas clássicas continuam.
- `style.card` (opcional): cores dos **cartões compartilhados** (canais, áreas da Central, categorias, cartões de Configurações): `fill`, `line`, `text`, `dim`, `faint`, `icon`. Sem ele, os cartões usam as cores dos painéis. Em cartão claro, as cores de estado ficam mais escuras automaticamente para manter o contraste.
- `style.focus`: cor da seleção dos cartões. `style.effect`: `"pop"` (cartão salta, contorno roxo/azul, Pastel Pop), `"soft"` (halo e leve aumento, Wii Blue) ou `"neon"` (contorno pulsante e cantos de mira, Neon Grid); sem ele, moldura simples.
- `style.chrome`: `"pill"` desenha a barra do topo e a de dicas como pílulas brancas flutuantes (Pastel Pop).
- Tema claro: basta usar cores claras em `bg0`/`bg1` e escuras em `text`/`dim` — as telas seguem a paleta.
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

## Componentes compartilhados (para quem desenvolve)

- `ui/gfx.lua` → `G.card(x, y, w, h, on, k, r)`: desenha o cartão do tema ativo e devolve a paleta do conteúdo (`text`, `dim`, `faint`, `icon`, `light`). `G.focus_k(chave, on)` anima o foco (0..1); `G.ink(cor, paleta)` escurece cores de estado em cartão claro. Uma tela nova que use esses três funciona nos dois temas sem código próprio de tema.
- `ui/channels.lua`: tela inicial em canais; as ações são as do menu (`menu.lua`: `S.open`, `S.exit_dialog`).
- `ui/icons.lua`: família de ícones de linha em `assets/icons/line/` (64x64, branco, pintada com a cor do tema), gerada por `tools/make_icons.py`. Os ícones antigos continuam como reserva.
