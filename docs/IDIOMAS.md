# Idiomas (pt-BR, English, Русский)

O R36S PORT HUB funciona em três idiomas: **Português (Brasil)**, **English** e **Русский**.

## Inicialização

1. **Splash**: logo oficial, nome, slogan *Your Port. Your Console. Your Adventure.*, tag BETA e barra de carregamento **real**. A barra avança uma etapa por vez: configurações, ports instalados, ferramentas, catálogo e espaço livre.
2. **SELECT LANGUAGE**: só no primeiro acesso (ou se o idioma salvo estiver ausente ou inválido).
   - Use o direcional para escolher e **A** para confirmar.
   - As dicas do rodapé aparecem no idioma destacado.
   - O idioma é salvo e aplicado na hora.
3. **AVISO IMPORTANTE**: aparece no idioma escolhido, também só uma vez.
   - **A** grava a confirmação e abre o menu.
   - Na primeira vez, **B** volta para a escolha de idioma.
4. **Nos próximos acessos**: splash e depois o menu, direto.

Trocar o idioma depois **não** mostra o aviso de novo.

## Trocar o idioma

Abra **Configurações → Aparência e personalização → Idioma**.

- O item mostra o idioma atual.
- A tela lista os três idiomas e marca o que está **EM USO**.
- A mudança vale na hora, sem reiniciar. Ao confirmar, você continua na mesma tela.
- **B** volta.

Trocar o idioma não mexe em downloads, histórico, ports, configuração do FTP nem tema.

## Onde fica salvo

Fica no arquivo `settings.txt`, na pasta de dados do app (`conf/love/r36sporthub/`). As linhas usam o formato `chave=valor`:

```
disclaimer_ok=1
language=ru
music=1
```

- A gravação usa um arquivo temporário seguido de renomeação, para não corromper o arquivo.
- Se `language` estiver ausente ou inválido, o app usa pt-BR e pergunta o idioma de novo.
- Se `disclaimer_ok` não for `1`, o aviso aparece.

## Estrutura

| Arquivo | Função |
|---|---|
| `src/lib/i18n.lua` | Idioma atual, lista de idiomas, `L()` e `tr()`, além do índice reverso |
| `src/i18n/en.lua` | Dicionário inglês: `["texto em português"] = "tradução"` |
| `src/i18n/ru.lua` | Dicionário russo, no mesmo formato |
| `src/core/prefs.lua` | Leitura e gravação de `settings.txt` |

- **A chave é o próprio texto em português.**
  - O código chama `L("Configurações")`.
  - Em pt-BR, o texto volta igual.
  - Nos outros idiomas, volta a tradução. Sem tradução, volta o português.
- **Na hora de desenhar**, `G.text`, `G.text_fit`, `G.wrap` e `G.tag`, além de `Font:getWidth` e `getWrap`, passam o texto por `tr()`.
  - Um texto montado num idioma é trocado pelo do idioma atual.
  - Isso também vale para a versão em MAIÚSCULAS.
  - Por isso a troca de idioma vale na hora, inclusive em telas já abertas.
- **Nunca são traduzidos**:
  - nomes de botões (A, B, X, Y, START, SELECT, L1, R1…);
  - nomes de jogos e ports;
  - caminhos e identificadores técnicos;
  - comandos do sistema;
  - os comandos do protocolo FTP.
- **Threads** (instalação, FTP, temas, atualização, verificações) recebem o idioma em `job.lang`. As mensagens delas saem no idioma de quem pediu a tarefa.
- **Unidades**:
  - em russo, `Б/КБ/МБ/ГБ` e `с/мин/ч`;
  - nos demais idiomas, `B/KB/MB/GB` e `s/min/h`.

## Fontes

- A fonte principal (Chakra Petch) não tem cirílico. Por isso, há dois recortes da **Inter** com só o alfabeto cirílico, como fonte de reserva (`setFallbacks`):
  - `assets/fonts/Inter-Regular-Cyrillic.otf`, cerca de 41 KB;
  - `assets/fonts/Inter-SemiBold-Cyrillic.otf`, cerca de 41 KB.
- A licença está em `port/r36sporthub/licenses/LICENSE.Inter.txt`.
- A fonte pixel (Press Start 2P) já tem cirílico.

## Textos do catálogo

Os catálogos podem trazer textos em outros idiomas. Sem eles, aparece o texto original.

- **Ports**: `description_en`, `description_ru`, `short_en`, `short_ru`.
- **Temas do EmulationStation**: `description_en`, `description_ru`. Os 41 temas do catálogo já têm.

## Adicionar ou corrigir uma tradução

1. Encontre o texto em português no código, dentro de `L("...")`.
2. Em `src/i18n/en.lua` e `src/i18n/ru.lua`, adicione ou corrija a linha `["texto em português"] = "tradução"`.
3. Mantenha `%s`, `%d` e `%%`, espaços no começo e no fim e `\n` como no original. Partes de frase são juntadas pelo código.
