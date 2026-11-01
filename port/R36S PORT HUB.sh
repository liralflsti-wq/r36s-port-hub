#!/bin/bash
# =============================================================================
#  R36S PORT HUB (BETA) - launcher
#  Ports para o R36S (dArkOS / ArkOS e derivados).
#  Usa o runtime LOVE 11.5 do PortMaster, do mesmo jeito que o KMP.
# =============================================================================

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
XDG_DATA_HOME_ORIG="$XDG_DATA_HOME"

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

HAS_PM=0
if [ -f "$controlfolder/control.txt" ]; then
  source "$controlfolder/control.txt"
  [ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
  get_controls
  HAS_PM=1
fi

# "directory" vem do control.txt (roms ou roms2). Sem PortMaster, assume roms.
directory=${directory:-roms}

GAMEDIR="/$directory/ports/r36sporthub"
CONFDIR="$GAMEDIR/conf"

mkdir -p "$CONFDIR" "$GAMEDIR/tmp"
cd "$GAMEDIR" || exit 1

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "[launcher] R36S PORT HUB BETA - $(date)"
echo "[launcher] GAMEDIR=$GAMEDIR  PortMaster=$HAS_PM ($controlfolder)"

# Dados do app (cache do catalogo, capas, registro de instalados)
export XDG_DATA_HOME="$CONFDIR"

# Informacoes que o app usa para saber onde instalar
export PORTHUB_XDG_ORIG="$XDG_DATA_HOME_ORIG"
[ -d "$controlfolder" ] && export PORTHUB_PM_DIR="$controlfolder"
export PORTHUB_DIR="$GAMEDIR"
export PORTHUB_PORTS_DIR="/$directory/ports"

rm -f "$CONFDIR/.restart_es"
rm -f "$CONFDIR/.run_tool"
rm -f "$CONFDIR/.power"
rm -f "$CONFDIR/.es_theme"
rm -f "$CONFDIR/.restart_app"

# -----------------------------------------------------------------------------
# Atualizacoes do hub (Configuracoes > Downloads e atualizacoes > Atualizacoes)
# O app grava um diario em backups/.journal:
#   state=applying -> a instalacao foi interrompida no meio: restaura o backup
#   state=pending  -> instalada; ao abrir, vira "booting"
#   state=booting  -> se o app fechar sem confirmar que abriu, restaura o backup
# So arquivos do hub ("R36S PORT HUB.sh" e r36sporthub/...) sao tocados.
# -----------------------------------------------------------------------------
PORTSD="/$directory/ports"
UPD_J="$GAMEDIR/backups/.journal"
upd_get() { sed -n "s/^$1=//p" "$UPD_J" 2>/dev/null | head -n 1; }
upd_restore() {
  id="$1"
  case "$id" in ""|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
  B="$GAMEDIR/backups/$id"
  [ -d "$B/files" ] || [ -f "$B/added.txt" ] || return 1
  # arquivos que a atualizacao criou
  if [ -f "$B/added.txt" ]; then
    while IFS= read -r rel; do
      case "$rel" in ""|/*|*..*) continue ;; esac
      case "$rel" in "R36S PORT HUB.sh"|r36sporthub/*) rm -f -- "$PORTSD/$rel" ;; esac
    done < "$B/added.txt"
  fi
  # arquivos antigos de volta (copia + troca por renomeacao)
  if [ -d "$B/files" ]; then
    ( cd "$B/files" && find . -type f ) | while IFS= read -r f; do
      rel="${f#./}"
      case "$rel" in *..*) continue ;; esac
      case "$rel" in "R36S PORT HUB.sh"|r36sporthub/*) ;; *) continue ;; esac
      case "$rel" in r36sporthub/conf/*|r36sporthub/backups/*|r36sporthub/update/*|r36sporthub/gravacoes/*|r36sporthub/logs/*|r36sporthub/bios/*|r36sporthub/bios_url.txt) continue ;; esac
      dst="$PORTSD/$rel"
      mkdir -p "$(dirname "$dst")"
      cp -p "$B/files/$rel" "$dst.porthub_restore" && mv -f "$dst.porthub_restore" "$dst"
      case "$rel" in *.sh|r36sporthub/bin/*) chmod +x "$dst" 2>/dev/null ;; esac
    done
  fi
  sync
  return 0
}
upd_recover() {
  UPD_ID=$(upd_get backup)
  echo "[launcher] Atualizacao: restaurando a versao anterior (backup $UPD_ID; motivo: $1)"
  if upd_restore "$UPD_ID"; then
    { echo "from=$(upd_get from)"; echo "to=$(upd_get to)"; echo "package=$(upd_get package)"; echo "reason=$1"; } > "$GAMEDIR/backups/.last_recovery"
    rm -f "$UPD_J"
    sync
    return 0
  fi
  echo "[launcher] Atualizacao: backup $UPD_ID nao encontrado; nada foi restaurado"
  mv -f "$UPD_J" "$UPD_J.invalido" 2>/dev/null
  return 1
}
case "$(upd_get state)" in
  applying) upd_recover "instalacao interrompida" ;;
  booting) upd_recover "a versao nova nao abriu" ;;
esac
UPD_RETRY=0

# O app pode pedir para abrir uma ferramenta externa (ex.: R36S Analog Tester).
# Ela roda com o app fechado (tela e controles livres) e, ao sair dela,
# o R36S PORT HUB abre de novo, na tela de onde a ferramenta foi chamada.
while true; do

  # versao recem-instalada: esta abertura precisa ser confirmada pelo app
  if [ "$(upd_get state)" = "pending" ]; then
    sed -i 's/^state=pending$/state=booting/' "$UPD_J" 2>/dev/null
    sync
  fi

  if [ "$HAS_PM" = "1" ] && [ -f "$controlfolder/runtimes/love_11.5/love.txt" ]; then
    export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
    export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
    source "$controlfolder/runtimes/love_11.5/love.txt"

    $GPTOKEYB "$LOVE_GPTK" &
    pm_platform_helper "$LOVE_BINARY"
    $LOVE_RUN "$GAMEDIR/game.love"
    LOVE_RC=$?
    [ "$HAS_PM" = "1" ] && pm_finish
  elif command -v love >/dev/null 2>&1; then
    echo "[launcher] Runtime love_11.5 do PortMaster nao encontrado; usando 'love' do sistema."
    love "$GAMEDIR/game.love"
  else
    echo "[launcher] ERRO: runtime LOVE 11.5 nao encontrado."
    echo "[launcher] Abra o PortMaster e instale qualquer port que use LOVE (ex.: o KMP) para baixar o runtime love_11.5."
    if [ -w /dev/tty1 ]; then
      printf "\033c\n\n  R36S PORT HUB\n\n  Runtime LOVE 11.5 nao encontrado.\n  Instale-o pelo PortMaster e tente novamente.\n" > /dev/tty1
      sleep 6
    fi
    exit 1
  fi


  # O app fechou com erro (ex.: travou sem conseguir gravar o proprio registro):
  # guarda uma copia do log desta execucao em r36sporthub/logs/
  if [ -n "$LOVE_RC" ] && [ "$LOVE_RC" != "0" ]; then
    mkdir -p "$GAMEDIR/logs"
    LOGF="$GAMEDIR/logs/erro_$(date +%Y%m%d_%H%M%S)_saida.txt"
    { echo "R36S PORT HUB - o aplicativo fechou com o codigo $LOVE_RC"; echo "Data: $(date)"; echo "Sistema: $CFW_NAME  Arquitetura: $DEVICE_ARCH";
      echo "============================================================"; tail -n 200 "$GAMEDIR/log.txt"; } > "$LOGF" 2>/dev/null
    sed -i -E 's/(PASS |[Ss]enha[ =:]+|[Pp]assword[ =:]+|psk[ =:]+)[^ ]+/\1******/g' "$LOGF" 2>/dev/null
    echo "[launcher] Registro do erro salvo em $LOGF"
  fi
  LOVE_RC=""

  # o app nao confirmou que a versao nova abriu: volta para a anterior e abre de novo
  if [ "$(upd_get state)" = "booting" ]; then
    if upd_recover "a versao nova fechou antes de abrir" && [ "$UPD_RETRY" = "0" ]; then
      UPD_RETRY=1
      continue
    fi
  fi

  # o app pediu para reiniciar (ex.: depois de instalar uma atualizacao)
  if [ -f "$CONFDIR/.restart_app" ]; then
    rm -f "$CONFDIR/.restart_app"
    echo "[launcher] Reiniciando o R36S PORT HUB"
    continue
  fi

  [ -f "$CONFDIR/.run_tool" ] || break
  TOOL_REQ=$(head -n 1 "$CONFDIR/.run_tool" 2>/dev/null)
  rm -f "$CONFDIR/.run_tool"
  TOOL_ID=${TOOL_REQ%%|*}
  case "$TOOL_ID" in
    analog_tester) TOOL_SH="$GAMEDIR/tools/R36S_Analog_Tester.sh" ;;
    *) TOOL_SH="" ;;
  esac
  [ -n "$TOOL_SH" ] && [ -f "$TOOL_SH" ] || break
  echo "[launcher] Abrindo ferramenta: $TOOL_ID"
  bash "$TOOL_SH"
  echo "[launcher] Ferramenta encerrada; voltando ao R36S PORT HUB"
  export PORTHUB_RETURN="$TOOL_REQ"
done

# O app pede para reiniciar o EmulationStation (para a lista de Ports atualizar)
if [ -f "$CONFDIR/.restart_es" ] && [ ! -f "$CONFDIR/.power" ]; then
  rm -f "$CONFDIR/.restart_es"
  # Loja de Temas pediu para ativar um tema: o ThemeSet do es_settings.cfg (o mesmo
  # que o menu do EmulationStation grava) so e trocado com o EmulationStation parado,
  # porque ele guarda as configuracoes na memoria. Backup antes; se a troca nao
  # conferir, o arquivo original volta.
  THEME_REQ=""
  if [ -f "$CONFDIR/.es_theme" ]; then
    THEME_REQ=$(head -n 1 "$CONFDIR/.es_theme" | tr -cd 'A-Za-z0-9._-')
    rm -f "$CONFDIR/.es_theme"
    # so um tema que existe numa pasta de temas do EmulationStation
    THEME_OK=""
    for TD in /etc/emulationstation/themes "${HOME:-/home/ark}/.emulationstation/themes" "/$directory/themes"; do
      [ -n "$THEME_REQ" ] && [ -d "$TD/$THEME_REQ" ] && THEME_OK=1
    done
    [ -n "$THEME_OK" ] || THEME_REQ=""
  fi
  echo "[launcher] Reiniciando EmulationStation... ${THEME_REQ:+(tema: $THEME_REQ)}"
  sync
  if [ -n "$THEME_REQ" ]; then
    # A troca precisa do EmulationStation parado, mas este launcher e filho dele:
    # um "systemctl stop" aqui mataria o proprio launcher (e o EmulationStation
    # nao voltaria). Por isso a troca roda numa unidade separada do systemd.
    ESCFG="${HOME:-/home/ark}/.emulationstation/es_settings.cfg"
    [ -f "$ESCFG" ] || ESCFG="/home/ark/.emulationstation/es_settings.cfg"
    APPLY="$GAMEDIR/bin/es_theme_apply.sh"
    if command -v systemd-run >/dev/null 2>&1 && [ -f "$APPLY" ] \
        && sudo -n systemd-run --no-block --collect --unit="porthub-es-theme-$$" \
             /bin/bash "$APPLY" "$THEME_REQ" "$ESCFG" "$CONFDIR" >/dev/null 2>&1; then
      echo "[launcher] Tema sendo aplicado fora do EmulationStation (systemd-run)"
    else
      # sem systemd-run/sudo: so reinicia, sem trocar o tema (nada fica parado)
      echo "[launcher] systemd-run indisponivel: tema NAO aplicado; reiniciando o EmulationStation"
      ( sleep 1; sudo systemctl restart emulationstation 2>/dev/null || systemctl restart emulationstation ) &
    fi
  else
    ( sleep 1; sudo systemctl restart emulationstation 2>/dev/null || systemctl restart emulationstation ) &
  fi
fi

# O app pede para desligar ou reiniciar o console (Sair -> Desligar/Reiniciar console).
# So acontece depois que o app fechou; grava o cartao antes.
if [ -f "$CONFDIR/.power" ]; then
  POWER_REQ=$(head -n 1 "$CONFDIR/.power" 2>/dev/null)
  rm -f "$CONFDIR/.power" "$CONFDIR/.restart_es"
  case "$POWER_REQ" in
    poweroff|reboot)
      echo "[launcher] Pedido do app: $POWER_REQ"
      sync
      sleep 1
      sudo -n systemctl "$POWER_REQ" 2>/dev/null \
        || sudo -n "$POWER_REQ" 2>/dev/null \
        || systemctl "$POWER_REQ" 2>/dev/null \
        || "$POWER_REQ"
      ;;
  esac
fi
