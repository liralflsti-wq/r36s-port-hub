
## 0.5.5 — Mascotes 3D low-poly

- **3D de verdade no LÖVE:** canvas com profundidade e shader próprio (luz, borda, contorno).
  Se o aparelho não aguentar, volta sozinho para o 2D.
- **8 mascotes originais em GLB**, gerados por `tools/make_mascots_glb.py`:
  - os 6 de antes: slime, robô, gatinho, fantasminha, caveira das sombras e dragãozinho;
  - 2 novos: cavaleiro dragão (carta Atualização do hub) e corujinha (carta Teste de velocidade).
  - Os chapéus também viraram 3D (`hats.glb`).
- **Módulos:** MascotRegistry (`registry.json`), MascotLoader, AnimationController (10 animações),
  MascotDialog (falas com personalidade, frequência, gancho para IA), MascotWidget e MascotSelector.
- **Nova cor "Cor original":** a cor de cada mascote, agora a padrão.
- **Configurações em Meu perfil:** mostrar, tamanho, qualidade (3D, 3D leve, 2D), animações e falas.
- **Novos eventos:** o mascote comenta a atualização do hub e se despede no menu Sair.
- **Documentação:** `docs/MASCOTES_3D.md`.

## 0.5.5 — Correções do mascote 3D, álbuns e falas

- **OpenGL ES (R36S):** o shader do 3D não ligava no console (precisão diferente nas duas metades do
  shader) e o mascote caía no 2D. Corrigido e testado em OpenGL ES 2.0. Quando o 3D falha, o motivo
  vai para o log e aparece em "Qualidade do mascote".
- **Aura e efeito no 3D:** agora acompanham a altura real do modelo. A aura ganhou anel no chão e
  faíscas subindo; os efeitos giram com profundidade (passam atrás e na frente do mascote).
- **Álbuns:** nova tela com 4 álbuns por ano (um por trimestre). Cada álbum mostra capa, nome, data
  de lançamento e progresso; os que ainda não saíram aparecem como "Em breve". A abre as cartas daquela
  temporada. As temporadas ganharam ano, trimestre e data de lançamento (`A.SEASONS`).
- **Cérebro do mascote** (`core/mascot3d/brain.lua`), com dados reais do hub:
  - comenta as telas que você abre: Central, detalhes do port, Meus Ports, favoritos, biblioteca de
    jogos dos emuladores, downloads, configurações, álbuns e outras;
  - avisa ports novos no catálogo e versão nova do hub;
  - conta a novidade depois de atualizar;
  - dá dicas de jogos do catálogo.
  - Há um intervalo entre falas, conforme a frequência escolhida, e cada tela comenta no máximo
    1 vez a cada 4 minutos.

## 0.5.5 — Criaturas digitais em pixel art (BITPOCKET)

- **Visual em pixel art:** o mascote 3D virou um bichinho virtual em pixel art. Os sprites são
  pré-renderizados dos modelos 3D, com paleta retrô e contorno, e 10 animações quadro a quadro. O 3D não
  roda mais no console: os modelos ficam em `tools/mascot_src`.
- **48 criaturas originais:** 8 linhas × 6 formas (Inicial, Intermediária, Avançada, Alternativa, Suprema e
  Secreta), cada uma com nome, elemento, raridade, habilidade, descrição, história e atributos.
- **Evolução ramificada:** depende de nível, felicidade, saúde, treinos, atributos e interações. Cada linha
  tem um requisito secreto próprio. A cena de evolução é animada no LCD, e o painel de evolução tem
  galeria e histórico.
- **Aparelho BITPOCKET:** 5 modelos desbloqueáveis, medidores de energia, felicidade e saúde, ações
  (alimentar, brincar, treinar, descansar, carinho) e 2 minigames (Reflexo e Memória).
- **Enciclopédia:** formas descobertas e bloqueadas, raridades, atributos, histórias e como obter cada uma.
- **Dados:** nível e XP por linha, cuidados, contadores, formas descobertas e histórico no `mascot.json`,
  com validação. Os dados antigos foram migrados sem perda.
- **Falas:** o mascote avisa quando está pronto para evoluir e quando está com fome ou triste.
- **Configuração:** a "Qualidade do mascote" (3D) virou "Estilo do mascote" (Pixel art ou Desenho simples).
- **Testes:** 33 verificações automáticas. Detalhes em `docs/CRIATURAS_DIGITAIS.md`.

## 0.5.5 — Assistente no lugar dos mascotes

- **Removido:** o sistema de mascotes e criaturas (aparelho BITPOCKET, cuidados, minigames, evolução,
  enciclopédia e sprites). Isso também resolveu o travamento da Enciclopédia e da Evolução, que recarregavam
  imagens grandes do SD a cada quadro. A cópia de segurança está em `archive/`.
- **Novo:** o assistente local (robô de armadura azul, nome padrão Nexo).
  - Cumprimenta e avisa ports novos, erros (com explicação) e pendências.
  - Registra um diário de atividades.
  - Responde 8 perguntas com dados reais.
  - **L2** abre o assistente de qualquer tela.
  - Detalhes em `docs/ASSISTENTE.md`.

## 0.5.5 — Assistente em 3D (drone flutuante)

- **Novo visual:** o robô em imagem virou um drone flutuante 3D de design original (`tools/make_assistant_glb.py`),
  com sombreamento suave e brilho especular. Tem imagem 2D de reserva para aparelhos sem 3D.
- **Animações:** parado, falar, acenar, pensar, apontar, alerta, comemorar e cochilar, cada uma ligada aos
  eventos do hub.
- **Falas:** muito mais variadas e em tom profissional.
  - Cumprimentos conforme a hora e o dia da semana, apresentação na primeira vez e boas-vindas depois de
    alguns dias fora.
  - Variações para cada evento.
  - Comentários úteis em mais telas.
  - 18 dicas.
