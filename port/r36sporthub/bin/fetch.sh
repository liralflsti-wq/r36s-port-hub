#!/bin/sh
# R36S PORT HUB - auxiliar de download (curl com fallback para wget)
#
# Uso:
#   fetch.sh get  URL SAIDA ARQ_PID ARQ_RC [MAX_SEGUNDOS]
#       Baixa URL para SAIDA. Grava o PID do processo de download em ARQ_PID
#       (para permitir cancelar) e o codigo de saida final em ARQ_RC.
#       Tenta retomar (-C -) em quedas de conexao, ate 3 tentativas.
#   fetch.sh head URL
#       Imprime o tamanho (Content-Length) final do arquivo, se o servidor informar.
#   fetch.sh part URL SAIDA BYTES
#       Baixa so o comeco do arquivo (os primeiros BYTES), para ler o manifesto
#       de um pacote .zip sem baixar tudo. Codigo de saida 0 se gravou algo.
#
# Codigos em ARQ_RC: 0 = ok; 143/137 = cancelado; outros = erro do curl/wget.

MODE="$1"
URL="$2"
UA="Mozilla/5.0 (R36S-PORT-HUB/BETA)"

have() { command -v "$1" >/dev/null 2>&1; }

# Erros de TLS/certificado: consoles com relogio/certificados antigos falham aqui.
is_tls_error() {
  case "$1" in 35|51|53|54|58|59|60|77|83|90|91) return 0 ;; esac
  return 1
}

if [ "$MODE" = "head" ]; then
  if have curl; then
    OUT=$(curl -sIL --max-time 20 -A "$UA" "$URL" 2>/dev/null)
    RC=$?
    if is_tls_error "$RC"; then OUT=$(curl -sIL -k --max-time 20 -A "$UA" "$URL" 2>/dev/null); fi
    echo "$OUT" | tr -d '\r' | grep -i '^content-length:' | tail -n 1 | awk '{print $2}'
  elif have wget; then
    wget --spider -S --no-check-certificate -T 20 -U "$UA" "$URL" 2>&1 | tr -d '\r' \
      | grep -i 'content-length:' | tail -n 1 | awk '{print $2}'
  fi
  exit 0
fi

if [ "$MODE" = "part" ]; then
  OUTFILE="$3"
  BYTES="${4:-262144}"
  LAST=$((BYTES - 1))
  rm -f "$OUTFILE"
  if have curl; then
    curl -L -s --connect-timeout 20 --max-time 40 -r "0-$LAST" -A "$UA" "$URL" 2>/dev/null | head -c "$BYTES" > "$OUTFILE"
    if [ ! -s "$OUTFILE" ]; then
      curl -L -s -k --connect-timeout 20 --max-time 40 -r "0-$LAST" -A "$UA" "$URL" 2>/dev/null | head -c "$BYTES" > "$OUTFILE"
    fi
  elif have wget; then
    wget -q -O - --no-check-certificate -T 30 -U "$UA" "$URL" 2>/dev/null | head -c "$BYTES" > "$OUTFILE"
  fi
  [ -s "$OUTFILE" ] && exit 0
  exit 1
fi

if [ "$MODE" != "get" ]; then
  echo "modo invalido" >&2
  exit 2
fi

OUTFILE="$3"
PIDFILE="$4"
RCFILE="$5"
MAXT="${6:-0}"

rm -f "$RCFILE"
mkdir -p "$(dirname "$OUTFILE")" 2>/dev/null

trap 'echo 143 > "$RCFILE"; exit 143' TERM INT

run_dl() {
  # $1 = extra flags (ex.: -k). Roda em segundo plano e espera, para que o PID
  # gravado seja o do curl/wget (assim o cancelamento interrompe de verdade).
  if have curl; then
    if [ "$MAXT" -gt 0 ] 2>/dev/null; then MT="--max-time $MAXT"; else MT=""; fi
    if [ -s "$OUTFILE" ]; then RESUME="-C -"; else RESUME=""; fi
    # shellcheck disable=SC2086
    curl -L -f -s -S --connect-timeout 20 --speed-limit 1 --speed-time 60 $MT $RESUME $1 \
      -A "$UA" -o "$OUTFILE" "$URL" &
  elif have wget; then
    W=""
    [ -n "$1" ] && W="--no-check-certificate"
    # shellcheck disable=SC2086
    wget -q -c -T 30 $W -U "$UA" -O "$OUTFILE" "$URL" &
  else
    echo 127 > "$RCFILE"
    exit 127
  fi
  CPID=$!
  echo "$CPID" > "$PIDFILE"
  wait "$CPID"
  return $?
}

ATTEMPT=0
FLAGS=""
RC=1
while [ $ATTEMPT -lt 4 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  run_dl "$FLAGS"
  RC=$?
  [ $RC -eq 0 ] && break
  # cancelado (SIGTERM/SIGKILL)
  if [ $RC -eq 143 ] || [ $RC -eq 137 ] || [ $RC -eq 130 ]; then break; fi
  if is_tls_error "$RC" && [ -z "$FLAGS" ]; then
    echo "[fetch] erro TLS ($RC); tentando novamente sem verificar certificado" >&2
    FLAGS="-k"
    continue
  fi
  # 33 = servidor nao aceita retomar: recomeca do zero
  if [ $RC -eq 33 ]; then rm -f "$OUTFILE"; continue; fi
  # quedas de conexao/tempo esgotado: tenta retomar
  case "$RC" in 7|18|28|52|55|56|92|4) sleep 2; continue ;; esac
  break
done

echo "$RC" > "$RCFILE"
exit "$RC"
