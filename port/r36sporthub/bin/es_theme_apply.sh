#!/bin/bash
# R36S PORT HUB - ativa um tema do EmulationStation (ThemeSet do es_settings.cfg)
#
# Uso: es_theme_apply.sh TEMA ARQUIVO_CFG PASTA_BACKUP
#
# Roda como unidade separada do systemd (systemd-run), FORA do grupo de processos
# do EmulationStation: parar o EmulationStation nao mata este script.
# Passos: para o EmulationStation -> backup -> troca so a linha ThemeSet
# (mantendo dono e permissoes do arquivo) -> confere -> inicia o EmulationStation.
# O EmulationStation e SEMPRE iniciado de novo, mesmo se a troca falhar.

THEME="$(printf '%s' "$1" | tr -cd 'A-Za-z0-9._-')"
CFG="$2"
BAK="$3"

start_es() { systemctl start emulationstation; }
trap start_es EXIT

[ -n "$THEME" ] && [ -n "$CFG" ] || exit 1

systemctl stop emulationstation
sleep 1

if [ -f "$CFG" ]; then
  mkdir -p "$BAK" 2>/dev/null
  cp -f "$CFG" "$BAK/es_settings.cfg.bak"
  TMP="$(mktemp)"
  if grep -q 'name="ThemeSet"' "$CFG"; then
    sed "s|<string name=\"ThemeSet\" value=\"[^\"]*\" */>|<string name=\"ThemeSet\" value=\"$THEME\" />|" "$CFG" > "$TMP"
  else
    cat "$CFG" > "$TMP"
    echo "<string name=\"ThemeSet\" value=\"$THEME\" />" >> "$TMP"
  fi
  # grava por cima do conteudo: dono e permissoes do arquivo continuam os mesmos
  if grep -q "name=\"ThemeSet\" value=\"$THEME\"" "$TMP"; then
    cat "$TMP" > "$CFG"
  fi
  rm -f "$TMP"
  if ! grep -q "name=\"ThemeSet\" value=\"$THEME\"" "$CFG"; then
    cat "$BAK/es_settings.cfg.bak" > "$CFG"
    echo "[es_theme_apply] ThemeSet nao conferiu; arquivo original restaurado"
  fi
  sync
fi
exit 0
