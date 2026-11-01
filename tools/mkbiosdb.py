#!/usr/bin/env python3
"""Gera src/core/bios_db.lua a partir do System.dat do libretro.

Uso: python3 tools/mkbiosdb.py tools/ref/System.dat src/core/bios_db.lua [commit]

Fonte: https://github.com/libretro/libretro-database/blob/master/dat/System.dat
("System, firmware, and BIOS files used by libretro cores."). So copia o que
esta no arquivo: nome (caminho dentro da pasta de BIOS), tamanho, MD5 e SHA-1.
Nada e acrescentado a mao.
"""
import re, sys

src, out = sys.argv[1], sys.argv[2]
commit = sys.argv[3] if len(sys.argv) > 3 else ""
text = open(src, encoding="utf-8").read()
version = (re.search(r'^\s*version\s+(\S+)', text, re.M) or [None, "?"])[1]
system = None
rows = []
rx = re.compile(r'rom \(\s*name\s+("([^"]+)"|(\S+))(.*)\)')
for line in text.splitlines():
    m = re.match(r'\s*comment\s+"(.*)"\s*$', line)
    if m and m.group(1) != "System":
        system = m.group(1)
        continue
    m = rx.search(line)
    if m:
        name = m.group(2) or m.group(3)
        kv = dict(re.findall(r'(size|crc|md5|sha1)\s+(\w+)', m.group(4)))
        if "md5" not in kv:
            continue
        rows.append((name, int(kv.get("size", -1)), kv["md5"].lower(), kv.get("sha1", "").lower(), system or "?"))

def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

systems = sorted({r[4] for r in rows})
sid = {s: i + 1 for i, s in enumerate(systems)}
with open(out, "w", encoding="utf-8") as f:
    f.write("-- =============================================================================\n")
    f.write("--  Banco de hashes de BIOS (gerado por tools/mkbiosdb.py, nao editar a mao)\n")
    f.write("--  Fonte: libretro-database, dat/System.dat %s%s\n" % (version, (" (commit " + commit + ")") if commit else ""))
    f.write("--  https://github.com/libretro/libretro-database/blob/master/dat/System.dat\n")
    f.write("--  n = caminho dentro da pasta de BIOS, s = tamanho, m = MD5, h = SHA-1, y = sistema\n")
    f.write("-- =============================================================================\n")
    f.write("local M = {}\n")
    f.write("M.SOURCE = %s\n" % q("libretro-database System.dat " + version + ((" " + commit[:12]) if commit else "")))
    f.write("M.SYSTEMS = {\n")
    for s in systems:
        f.write("  %s,\n" % q(s))
    f.write("}\n")
    f.write("M.LIST = {\n")
    for name, size, md5, sha1, s in rows:
        f.write("  { n = %s, s = %d, m = %s, h = %s, y = %d },\n" % (q(name), size, q(md5), q(sha1), sid[s]))
    f.write("}\n")
    f.write("return M\n")
print("entradas:", len(rows), "sistemas:", len(systems), "versao:", version)
