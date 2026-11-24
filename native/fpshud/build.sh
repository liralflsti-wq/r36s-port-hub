#!/bin/sh
# Compila o contador de FPS (64 e 32 bits) para port/r36sporthub/fpshud/.
# O launcher usa LD_PRELOAD=".../fpshud/$LIB/libporthub_fps.so": o sistema troca
# $LIB pela pasta de bibliotecas do jogo (64 ou 32 bits), entao cada jogo carrega
# a versao certa sem avisos de "wrong ELF class".
#   Debian/Ubuntu (dArkOS, ArkOS): lib/aarch64-linux-gnu e lib/arm-linux-gnueabihf
#   outros sistemas: lib64 (64 bits) e lib (32 bits)
set -e
cd "$(dirname "$0")"
OUT=${OUT:-../../build/fpshud}   # desligado na 0.5.5: nao vai no pacote
rm -rf "$OUT"
mkdir -p "$OUT/lib/aarch64-linux-gnu" "$OUT/lib/arm-linux-gnueabihf" "$OUT/lib64"
FL="-O2 -shared -fPIC -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -Wall -Wno-nonnull-compare"
LK="-Wl,--no-as-needed -l:libdl.so.2 -Wl,-z,nodelete -Wl,-z,max-page-size=4096 -Wl,-z,common-page-size=4096"
aarch64-linux-gnu-gcc $FL -o /tmp/fps64.so fpshud.c $LK
arm-linux-gnueabihf-gcc $FL -U_TIME_BITS -D_TIME_BITS=32 -U_FILE_OFFSET_BITS -o /tmp/fps32.so fpshud.c $LK
aarch64-linux-gnu-strip /tmp/fps64.so
arm-linux-gnueabihf-strip /tmp/fps32.so
cp /tmp/fps64.so "$OUT/lib/aarch64-linux-gnu/libporthub_fps.so"
cp /tmp/fps64.so "$OUT/lib64/libporthub_fps.so"
cp /tmp/fps32.so "$OUT/lib/arm-linux-gnueabihf/libporthub_fps.so"
cp /tmp/fps32.so "$OUT/lib/libporthub_fps.so"
