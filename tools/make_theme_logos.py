#!/usr/bin/env python3
"""Gera as logos dos temas: Sky Warriors (padrao) e Moonlight Blade (--moonblade) a partir das logos padrao do hub
(assets/logo/*.png): rosa -> laranja/dourado, roxo -> azul royal, ciano fica
turquesa claro. Saida: src/themes/skywarriors/logo_*.png"""
import colorsys, os, sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
SRC = os.path.join(ROOT, "assets", "logo")
MOON = "--moonblade" in sys.argv
DST = os.path.join(ROOT, "themes", "moonblade" if MOON else "skywarriors")

def remap(px, pink, purple, cyan, gray=None):
    """troca as tres familias de cor da logo padrao: cada uma = (h graus, fator s, fator v)"""
    r, g, b, a = px
    if a == 0:
        return px
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    deg = h * 360
    if s < 0.12:
        tgt = gray
    elif deg >= 300 or deg < 25:
        tgt = pink
    elif 225 <= deg < 300:
        tgt = purple
    elif 160 <= deg < 225:
        tgt = cyan
    else:
        tgt = None
    if tgt:
        nh, sf, vf = tgt
        h, s, v = nh / 360, min(1.0, s * sf + (0.15 if sf > 1 else 0)), min(1.0, v * vf)
    nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
    return (round(nr * 255), round(ng * 255), round(nb * 255), a)

def recolor_moon(px):
    """rosa -> vermelho sangue, roxo do escudo -> preto, ciano -> prata/branco"""
    r, g, b, a = px
    if a == 0:
        return px
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    deg = h * 360
    if s < 0.12:
        nh, ns, nv = 0, 0, v
    elif deg >= 300 or deg < 25:      # letras R36S e moldura: vermelho (claro = quase branco)
        if v > 0.85:
            nh, ns, nv = 355 / 360, s * 0.35, 1.0
        else:
            nh, ns, nv = 355 / 360, min(1.0, s * 1.2 + 0.2), min(1.0, v * 0.95)
    elif 225 <= deg < 300:            # escudo: preto azulado
        nh, ns, nv = 250 / 360, 0.25, v * 0.35
    elif 160 <= deg < 225:            # PORT HUB e brilhos: prata
        nh, ns, nv = 220 / 360, 0.06, min(1.0, v * 1.05)
    else:
        nh, ns, nv = h, s, v
    nr, ng, nb = colorsys.hsv_to_rgb(nh, ns, min(1.0, nv))
    return (round(nr * 255), round(ng * 255), round(nb * 255), a)

def recolor(px):
    r, g, b, a = px
    if a == 0:
        return px
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    deg = h * 360
    if s < 0.12:                      # cinzas/brancos: leve tom azul
        nh, ns, nv = 210 / 360, s * 0.6, v
    elif deg >= 300 or deg < 25:      # rosa/vermelho -> laranja ate dourado (claro = mais amarelo)
        nh = (28 + 22 * v) / 360
        ns = min(1.0, s * 1.15 + 0.15)
        nv = min(1.0, v * 1.05 + 0.05)
    elif 225 <= deg < 300:            # roxo do escudo -> azul royal
        nh, ns, nv = 216 / 360, min(1.0, s * 1.05), v * 1.05
    elif 160 <= deg < 225:            # ciano -> turquesa do ceu
        nh, ns, nv = 192 / 360, s, v
    else:
        nh, ns, nv = h, s, v
    nr, ng, nb = colorsys.hsv_to_rgb(nh, ns, min(1.0, nv))
    return (round(nr * 255), round(ng * 255), round(nb * 255), a)

def main():
    os.makedirs(DST, exist_ok=True)
    for name in ("logo_header.png", "logo_menu.png", "logo_about.png", "logo_splash.png"):
        im = Image.open(os.path.join(SRC, name)).convert("RGBA")
        fn = recolor_moon if MOON else recolor
        im.putdata([fn(p) for p in list(im.getdata())])
        im.save(os.path.join(DST, name), optimize=True)
        print("ok", name, im.size)

if __name__ == "__main__":
    sys.exit(main())
