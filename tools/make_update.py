#!/usr/bin/env python3
"""
R36S PORT HUB - pacotes de atualizacao (update_manifest.json + SHA-256)

Uso:
  make_update.py full PORTS_DIR
      Grava PORTS_DIR/update_manifest.json com TODOS os arquivos do hub
      (usado pelo tools/build.sh no pacote completo).

  make_update.py baseline PORTS_DIR SAIDA.json
      Guarda a lista (caminho -> sha256) da versao entregue, para comparar
      na proxima atualizacao incremental.

  make_update.py incremental --base BASE.json --ports PORTS_DIR --out PACOTE.zip
                 [--min VERSAO_MINIMA] [--max VERSAO_MAXIMA] [--desc "texto"]
                 [--mudanca "texto"]... [--correcao "texto"]... [--notas NOTAS.txt]
      Monta o ZIP incremental: so arquivos novos ou alterados desde BASE,
      com update_manifest.json na raiz. Pronto para a pasta r36sporthub/update.

PORTS_DIR e a pasta "ports" gerada pelo build (tem "R36S PORT HUB.sh" e r36sporthub/).
A versao e lida de src/config.lua (C.VERSION_NUM e C.VERSION).

Notas da versao (aparecem no hub antes de instalar e na primeira abertura):
  --mudanca / --correcao podem repetir; ou um arquivo --notas com linhas
  "+ texto" (o que mudou) e "* texto" (o que foi corrigido).
"""
import hashlib, json, os, re, sys, zipfile, datetime, argparse, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCHER = "R36S PORT HUB.sh"
APP = "r36sporthub"
PROTECTED = {"conf", "tmp", "logs", "gravacoes", "update", "backups", "bios", "bios_url.txt", "catalog.json",
             "catalog_url.txt", "update_url.txt", "log.txt"}


def version():
    src = open(os.path.join(ROOT, "src", "config.lua"), encoding="utf-8").read()
    num = re.search(r'C\.VERSION_NUM\s*=\s*"([^"]+)"', src).group(1)
    lab = re.search(r'C\.VERSION\s*=\s*L\("([^"]+)"\)', src).group(1)
    return num, lab


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def hub_files(ports):
    """caminhos relativos (com /) de tudo que pertence ao hub no build"""
    out = []
    if os.path.isfile(os.path.join(ports, LAUNCHER)):
        out.append(LAUNCHER)
    base = os.path.join(ports, APP)
    for d, dirs, files in os.walk(base):
        rel_d = os.path.relpath(d, ports).replace(os.sep, "/")
        if rel_d == APP:
            dirs[:] = [x for x in dirs if x not in PROTECTED and not x.startswith("libs.")]
        for f in files:
            rel = rel_d + "/" + f
            top = rel.split("/")[1]
            if top in PROTECTED:
                continue
            if os.path.islink(os.path.join(d, f)):
                sys.exit("link simbolico nao permitido: " + rel)
            out.append(rel)
    return sorted(out)


def manifest(ports, files, kind, vmin=None, vmax=None, desc="", changes=None, fixes=None):
    num, lab = version()
    m = {
        "format": 1,
        "name": "R36S PORT HUB",
        "type": kind,
        "version": num,
        "version_label": lab,
        "date": datetime.date.today().isoformat(),
        "description": desc,
        "files": [{"path": p, "size": os.path.getsize(os.path.join(ports, p)),
                   "sha256": sha256(os.path.join(ports, p))} for p in files],
    }
    if changes:
        m["changes"] = changes
    if fixes:
        m["fixes"] = fixes
    if vmin:
        m["min_version"] = vmin
    if vmax:
        m["max_version"] = vmax
    return m


def cmd_full(ports):
    files = hub_files(ports)
    m = manifest(ports, files, "full", desc="Pacote completo do R36S PORT HUB.")
    with open(os.path.join(ports, "update_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=1)
    print("manifesto completo:", len(files), "arquivos, versao", m["version"])


def cmd_baseline(ports, out):
    num, lab = version()
    d = {"version": num, "version_label": lab, "date": datetime.datetime.now().isoformat(timespec="seconds"),
         "files": {p: sha256(os.path.join(ports, p)) for p in hub_files(ports)}}
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    print("base gravada:", out, "versao", num, len(d["files"]), "arquivos")


def cmd_incremental(a):
    base = json.load(open(a.base, encoding="utf-8"))
    num, lab = version()
    if base.get("version") == num:
        sys.exit("a versao em src/config.lua (%s) e a mesma da base: aumente C.VERSION_NUM" % num)
    changed = [p for p in hub_files(a.ports) if base["files"].get(p) != sha256(os.path.join(a.ports, p))]
    if not changed:
        sys.exit("nenhum arquivo mudou desde a base")
    changes, fixes = list(a.mudanca or []), list(a.correcao or [])
    if a.notas:
        for line in open(a.notas, encoding="utf-8"):
            line = line.strip()
            if line.startswith("+"):
                changes.append(line[1:].strip())
            elif line.startswith("*"):
                fixes.append(line[1:].strip())
    m = manifest(a.ports, changed, "incremental", vmin=a.min or base.get("version"), vmax=a.max,
                 desc=a.desc or ("Atualização %s (a partir da %s)." % (lab, base.get("version_label", base.get("version")))),
                 changes=changes, fixes=fixes)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with zipfile.ZipFile(a.out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        # permissoes Unix (0644) no manifesto: sem elas o zipinfo mostra "?rw-------"
        # e o leitor do hub (0.4/0.4.1) desalinha os tamanhos dos outros arquivos
        zi = zipfile.ZipInfo("update_manifest.json", date_time=time.localtime()[:6])
        zi.create_system = 3
        zi.external_attr = (0o100644 & 0xFFFF) << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(zi, json.dumps(m, ensure_ascii=False, indent=1))
        for p in changed:
            z.write(os.path.join(a.ports, p), p)
    print("pacote:", a.out, "versao", num, "arquivos:", ", ".join(changed))


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    if sys.argv[1] == "full" and len(sys.argv) == 3:
        cmd_full(sys.argv[2])
    elif sys.argv[1] == "baseline" and len(sys.argv) == 4:
        cmd_baseline(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "incremental":
        ap = argparse.ArgumentParser()
        ap.add_argument("cmd"); ap.add_argument("--base", required=True); ap.add_argument("--ports", required=True)
        ap.add_argument("--out", required=True); ap.add_argument("--min"); ap.add_argument("--max"); ap.add_argument("--desc")
        ap.add_argument("--mudanca", action="append"); ap.add_argument("--correcao", action="append"); ap.add_argument("--notas")
        cmd_incremental(ap.parse_args())
    else:
        print(__doc__); sys.exit(1)


if __name__ == "__main__":
    main()
