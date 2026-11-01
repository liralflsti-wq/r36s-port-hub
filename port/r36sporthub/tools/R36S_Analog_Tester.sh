#!/bin/bash
# R36S Analog Tester - por LagdoLira
# Menu: Testar analogicos | Testar botoes | Sair
# BACKEND: auto (padrao) | pygame | fb | text
BACKEND=auto

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/r36s_analog_tester"
export REPORT_DIR="$APP"
export BACKEND
export TERM=linux

sudo chmod 666 /dev/tty1 /dev/fb0 /dev/input/event* 2>/dev/null
printf "\033c\033[?25l\033[9;0]" > /dev/tty1 2>/dev/null

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 nao encontrado." > /dev/tty1
    sleep 5
    exit 1
fi

python3 "$APP/r36s_analog_tester.py" 2> "$APP/log.txt"

printf "\033c\033[?25h" > /dev/tty1 2>/dev/null
exit 0
