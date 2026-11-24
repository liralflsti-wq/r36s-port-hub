# Assistente do R36S PORT HUB (0.5.5)

O assistente **Nexo** (o nome pode ser trocado) substitui o antigo sistema de mascotes. Ele é um drone flutuante
3D de design original: cabeça branca polida, topo azul-marinho, visor em faixa com olhos quadrados de pixel, mãos
que flutuam soltas, anel de luz na cintura e propulsor. Ele é 100% local:
funciona sem internet e não roda IA pesada no console. Mesmo assim, responde rápido e com precisão,
porque lê os dados reais do hub.

## O que ele faz

- **Cumprimenta** com bom dia, boa tarde ou boa noite, usando o nome do perfil, e dá um resumo curto
  do dia ao abrir o hub.
- **Avisa sozinho:**
  - ports novos no catálogo;
  - versão nova do hub;
  - erros, já com a explicação e o que fazer;
  - port instalado, removido ou download cancelado;
  - carta nova;
  - despedida no menu Sair.
- **Lembra das pendências** uma vez por dia:
  - ports com atualização e versão nova do hub;
  - downloads na fila ou com falha;
  - arquivos de port no cartão esperando instalação;
  - lista do EmulationStation para reiniciar;
  - pouco espaço no SD e bateria baixa;
  - Wi-Fi desligado;
  - nome do perfil ainda não definido.
- **Comenta as telas** com informação útil. Exemplos: o tamanho do port comparado ao espaço livre, e se
  o port já está instalado ou tem atualização.
- **Diário de atividades** (`activity.json`): instalações, remoções, erros, jogos abertos, cartas,
  FTP, atualizações e o catálogo. Com isso ele responde "O que eu fiz hoje?".

## Tela do assistente

**L2** abre a tela de qualquer lugar; ela também fica em Meu perfil › Assistente.

| Pergunta | Resposta |
|---|---|
| Resumo do dia | Saudação, ports instalados e novos, atualizações, erros e pendências |
| Tem port novo? | Lista dos novos, com categoria e tamanho (X abre a Central) |
| Deu algum erro? | Erros do dia (log de problemas e downloads com falha), com explicação e solução |
| O que falta fazer? | Pendências reais, com atalho X para resolver |
| O que eu fiz hoje? | Atividades do diário, com horário |
| Como está meu console? | Versão, SD, bateria, Wi-Fi, ports, jogos da biblioteca, favoritos, cartas |
| O que mudou na versão? | Notas da última atualização e histórico |
| Me dá uma dica | Dica do hub e sugestão de jogo do catálogo |

## Configurações (Meu perfil)

- Mostrar assistente.
- Tamanho: pequeno, médio ou grande.
- Falas: bastante, normal, pouco ou em silêncio.
- Nome do assistente.

## Arquivos

| Arquivo | Papel |
|---|---|
| `core/assistant/init.lua` | Estado (`assistant.json`), saudação, eventos e balões |
| `core/assistant/journal.lua` | Diário de atividades |
| `core/assistant/knowledge.lua` | Respostas com dados reais e explicação de erros (`K.provider` deixa ligar uma IA no futuro) |
| `core/assistant/brain.lua` | O que ele fala sozinho, com controle de frequência |
| `ui/assistant.lua` | Desenho do drone 3D (canvas com profundidade), reserva 2D, balão e o canto da tela |
| `core/assistant3d/` | `loader.lua` (lê o GLB), `render.lua` (sombreamento suave, brilho especular, contorno), `anim.lua` (animações) |
| `tools/make_assistant_glb.py` | Gera `assets/assistant/drone.glb` (modelo em código) |
| `ui/screens/assistant.lua` | A tela de perguntas |
| `assets/assistant/` | `drone.glb` e as imagens 2D de reserva (`drone_front.png`, `drone_small.png`) |

## Animações

| Animação | Quando aparece |
|---|---|
| Parado | Sempre: flutua, o anel gira, o propulsor pulsa e ele pisca |
| Falar | Enquanto há balão: gesticula, e os olhos pulsam no ritmo |
| Acenar | Ao cumprimentar e na despedida |
| Pensar | Quando você faz uma pergunta: mão no queixo, olhos para cima, antena piscando |
| Apontar | Logo depois, mostrando a resposta |
| Alerta | Em erros: luzes vermelhas, recua e treme |
| Comemorar | Port instalado ou carta nova: giro com pulinhos e olhos sorrindo |
| Cochilar | Depois de 2 minutos sem nenhum botão: abaixa a cabeça, olhos fechados, luzes fracas |

O sistema de mascotes e criaturas foi removido. A cópia de segurança está em `archive/mascote_digipet_0.5.5.tar.gz`,
fora do pacote.
