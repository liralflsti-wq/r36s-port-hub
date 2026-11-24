# Voz do Nexo (pausada)

- Voz criada no ElevenLabs: "Nexo" (voice_id GqpxZgPEqvocq4Td55Tw), estilo IA de nave.
- `voice.lua`: módulo pronto (toca assets/assistant/voice/<sha1 10>.ogg quando a fala é fixa e o idioma é pt-BR).
  Para religar: voltar o arquivo para src/core/assistant/, chamar V.play(text) em A.say e recolocar o ajuste
  "Voz do assistente" em Meu perfil.
- `falas_fixas.json`: 126 falas fixas (~6.400 caracteres ≈ 6.400 créditos).
- Bloqueio: o download de elevenlabsusercontent.com precisa estar liberado nos domínios permitidos do Claude.
