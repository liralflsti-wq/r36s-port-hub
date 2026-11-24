#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R36S PORT HUB - envio dos ports para o Internet Archive (archive.org)
e geracao do catalogo (catalog.json) com os links prontos para o hub.

ANTES DE USAR (uma vez so):
    pip install internetarchive
    ia configure            <- voce digita o seu e-mail e senha do archive.org
                               (o script nunca ve a sua senha)

USO:
    1) Ver o que vai ser enviado (NADA e enviado):
       python3 enviar_ports_archive.py "/home/lucaslira/Área de trabalho/Telegram donwload/"

    2) Enviar de verdade:
       python3 enviar_ports_archive.py "/home/lucaslira/Área de trabalho/Telegram donwload/" --enviar

COMO OS PORTS SAO RECONHECIDOS NA PASTA:
    a) Uma pasta por jogo (recomendado):
         Daytona USA/
           Daytona USA.zip   (ou .7z / .rar)  <- pacote do port
           description.txt                    <- descricao (opcional)
           Daytona USA cover.png              <- capa (opcional; .png/.jpg)
    b) Arquivos soltos: "Daytona USA.zip" + "Daytona USA cover.png" + "Daytona USA.txt"

Cada jogo vira um item proprio no archive.org (identificador: <prefixo>-<nome>).
Ao final sao gravados, na pasta escolhida:
    catalog.json         -> catalogo para o R36S PORT HUB (links do archive.org)
    relatorio_envio.csv  -> o que foi enviado, tamanho, md5 e resultado

Itens que ja existem no archive.org com o mesmo identificador NAO sao sobrescritos
(use --prefixo para escolher outro, ou --atualizar para enviar so arquivos novos/alterados).
"""
import argparse
import csv
import datetime
import hashlib
import json
import os
import re
import sys
import unicodedata

PACOTES = (".zip", ".7z", ".rar")
IMAGENS = (".png", ".jpg", ".jpeg")


def slug(texto):
    t = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode("ascii")
    t = re.sub(r"[^A-Za-z0-9]+", "-", t).strip("-").lower()
    return t or "port"


def md5_arquivo(caminho):
    h = hashlib.md5()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloco)
    return h.hexdigest()


def tipo_real(caminho):
    """formato pelo conteudo (assinatura), nao pela extensao"""
    with open(caminho, "rb") as f:
        cab = f.read(8)
    if cab.startswith(b"PK\x03\x04"):
        return "zip"
    if cab.startswith(b"7z\xbc\xaf\x27\x1c"):
        return "7z"
    if cab.startswith(b"Rar!\x1a\x07"):
        return "rar"
    return None


def ler_texto(caminho):
    for enc in ("utf-8", "latin-1"):
        try:
            with open(caminho, encoding=enc) as f:
                return f.read().strip()
        except UnicodeDecodeError:
            continue
    return ""


def achar_capa(pasta, nome):
    cands = []
    for arq in os.listdir(pasta):
        base, ext = os.path.splitext(arq)
        if ext.lower() in IMAGENS:
            b = base.lower()
            if b in (nome.lower() + " cover", nome.lower() + "_cover", nome.lower() + "-cover", "cover", "capa"):
                return os.path.join(pasta, arq)
            if "cover" in b or "capa" in b:
                cands.append(os.path.join(pasta, arq))
    return cands[0] if cands else None


def achar_descricao(pasta, nome):
    for n in ("description.txt", "descricao.txt", "descrição.txt", nome + ".txt"):
        p = os.path.join(pasta, n)
        if os.path.isfile(p):
            return p
    return None


def listar_jogos(raiz):
    jogos, avisos = [], []
    # a) uma pasta por jogo
    for item in sorted(os.listdir(raiz)):
        p = os.path.join(raiz, item)
        if os.path.isdir(p):
            pacotes = [a for a in sorted(os.listdir(p)) if os.path.splitext(a)[1].lower() in PACOTES]
            if not pacotes:
                avisos.append(f"Pasta sem .zip/.7z/.rar (ignorada): {item}")
                continue
            if len(pacotes) > 1:
                avisos.append(f"Pasta com mais de um pacote, usando '{pacotes[0]}': {item}")
            jogos.append({"nome": item, "pacote": os.path.join(p, pacotes[0]),
                          "capa": achar_capa(p, item), "descricao": achar_descricao(p, item)})
    # b) arquivos soltos na raiz
    for arq in sorted(os.listdir(raiz)):
        p = os.path.join(raiz, arq)
        base, ext = os.path.splitext(arq)
        if os.path.isfile(p) and ext.lower() in PACOTES:
            jogos.append({"nome": base, "pacote": p,
                          "capa": achar_capa(raiz, base), "descricao": achar_descricao(raiz, base)})
    return jogos, avisos


def main():
    ap = argparse.ArgumentParser(description="Envia ports para o archive.org e gera o catalog.json do R36S PORT HUB")
    ap.add_argument("pasta", help="pasta com os ports")
    ap.add_argument("--enviar", action="store_true", help="envia de verdade (sem isto, so mostra o plano)")
    ap.add_argument("--prefixo", default="r36s-porthub", help="inicio do identificador de cada item (padrao: r36s-porthub)")
    ap.add_argument("--atualizar", action="store_true", help="permite enviar para itens que ja existem (so arquivos novos/alterados)")
    args = ap.parse_args()

    raiz = os.path.abspath(os.path.expanduser(args.pasta))
    if not os.path.isdir(raiz):
        sys.exit(f"Pasta nao encontrada: {raiz}")

    jogos, avisos = listar_jogos(raiz)
    for a in avisos:
        print("AVISO:", a)
    if not jogos:
        sys.exit("Nenhum .zip/.7z/.rar encontrado.")

    ia = None
    if args.enviar:
        try:
            import internetarchive as ia
        except ImportError:
            sys.exit("Instale antes:  pip install internetarchive   e depois rode:  ia configure")

    catalogo = {"catalog_version": 1, "title": "R36S PORT HUB - catalogo",
                "updated": datetime.date.today().isoformat(), "categories": [], "ports": []}
    relatorio = []
    usados = set()

    for j in jogos:
        nome = j["nome"]
        pac = j["pacote"]
        fmt = tipo_real(pac)
        tam = os.path.getsize(pac)
        if not fmt:
            print(f"IGNORADO (arquivo nao e ZIP/7z/RAR de verdade): {pac}")
            relatorio.append([nome, "", os.path.basename(pac), tam, "", "ignorado: formato invalido"])
            continue
        ident = f"{args.prefixo}-{slug(nome)}"[:100]
        while ident in usados:
            ident += "-2"
        usados.add(ident)
        print(f"\n== {nome}")
        print(f"   item: https://archive.org/details/{ident}")
        print(f"   pacote: {os.path.basename(pac)} ({fmt}, {tam / 1048576:.1f} MB)")
        print(f"   capa: {os.path.basename(j['capa']) if j['capa'] else '(nenhuma)'}")
        print(f"   descricao: {os.path.basename(j['descricao']) if j['descricao'] else '(nenhuma)'}")

        descricao = ler_texto(j["descricao"]) if j["descricao"] else ""
        md5 = md5_arquivo(pac)
        resultado = "plano (nada enviado)"

        if args.enviar:
            item = ia.get_item(ident)
            if item.exists and not args.atualizar:
                print("   JA EXISTE no archive.org: nao foi enviado (use --atualizar ou outro --prefixo).")
                resultado = "ja existe (nao enviado)"
            else:
                arquivos = [pac] + [x for x in (j["capa"], j["descricao"]) if x]
                meta = {"title": nome, "mediatype": "software",
                        "description": descricao or f"Port de {nome} para o R36S (R36S PORT HUB).",
                        "subject": ["R36S", "PortMaster", "port", "R36S PORT HUB"]}
                try:
                    r = ia.upload(ident, files=arquivos, metadata=meta, verbose=True, checksum=True, retries=5, retries_sleep=10)
                    falhas = [x for x in r if getattr(x, "status_code", 200) >= 400]
                    resultado = "enviado" if not falhas else f"falhou ({len(falhas)} arquivo(s))"
                except Exception as e:  # sem internet, login invalido, etc.
                    resultado = f"falhou: {e}"
                print("   resultado:", resultado)

        port = {"id": slug(nome), "name": nome, "description": descricao,
                "ia_item": ident, "ia_file": os.path.basename(pac), "size_bytes": tam, "md5": md5}
        if j["capa"]:
            port["ia_cover"] = os.path.basename(j["capa"])
        catalogo["ports"].append(port)
        relatorio.append([nome, ident, os.path.basename(pac), tam, md5, resultado])

    with open(os.path.join(raiz, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalogo, f, ensure_ascii=False, indent=2)
    with open(os.path.join(raiz, "relatorio_envio.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["jogo", "item_archive_org", "arquivo", "tamanho_bytes", "md5", "resultado"])
        w.writerows(relatorio)

    print("\nCatalogo gerado: ", os.path.join(raiz, "catalog.json"))
    print("Relatorio:       ", os.path.join(raiz, "relatorio_envio.csv"))
    if not args.enviar:
        print("\nNada foi enviado. Confira a lista acima e rode de novo com --enviar.")
    else:
        print("\nO archive.org pode levar alguns minutos para liberar os arquivos depois do envio.")


if __name__ == "__main__":
    main()
