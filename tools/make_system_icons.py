#!/usr/bin/env python3
"""Gera os icones de console do R36S PORT HUB (arte original, 0.5.0).

Saida: src/assets/systems/<sistema>.png, 192x192.
Cartao claro arredondado, borda em degrade, padrao suave ao fundo, uma
silhueta grande e clara do aparelho no fundo e o desenho do aparelho no
centro em degrade. Desenhos genericos por tipo de aparelho: sem logotipos,
marcas ou personagens. Os nomes dos arquivos sao os sistemas do
es_systems.cfg do dArkOSRE (e alguns nomes comuns de outros sistemas).

Uso: python3 tools/make_system_icons.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

import make_icons as MI

OUT = os.path.join(os.path.dirname(__file__), "..", "src", "assets", "systems")
SZ = 384          # desenha em 384 e reduz para 192
FINAL = 192

PAIRS = [
    ((139, 92, 246), (58, 160, 240)),   # roxo -> azul
    ((249, 115, 22), (234, 179, 8)),    # laranja -> amarelo
    ((236, 72, 153), (168, 85, 247)),   # rosa -> roxo
    ((6, 182, 212), (34, 197, 94)),     # ciano -> verde
    ((244, 63, 94), (249, 115, 22)),    # vermelho -> laranja
    ((99, 102, 241), (236, 72, 153)),   # indigo -> rosa
    ((20, 184, 166), (59, 130, 246)),   # verde-agua -> azul
    ((234, 179, 8), (34, 197, 94)),     # amarelo -> verde
    ((14, 165, 233), (139, 92, 246)),   # azul -> roxo
    ((217, 70, 239), (244, 63, 94)),    # magenta -> vermelho
]

# sistema -> tipo de aparelho
KIND = {}
def kinds(dev, names):
    for n in names.split():
        KIND[n] = dev

kinds("sys_handheld", "psp ppsspp pspminis psvita gba gamegear ngp ngpc wonderswan wonderswancolor atarilynx lynx supervision megaduck gamate gmaster")
kinds("sys_vertical", "gb gbc sgb pokemonmini pokemini vectrex microvision palm")
kinds("sys_dual", "nds n3ds 3ds")
kinds("sys_cart", "nes famicom fds snes sfc snesmsu snes-hacks satellaview sufami n64 n64dd megadrive megadrivemsu genesis "
      "mastersystem sg-1000 sega32x atari2600 atari5200 atari7800 jaguar colecovision coleco intellivision odyssey2 videopac "
      "channelf pcengine supergrafx turbografx16 tg16 virtualboy scv advision astrocade gametank arcadia")
kinds("sys_disc", "psx ps2 segacd megacd saturn dreamcast vmu 3do pcenginecd turbografxcd tg-cd neogeocd pcfx cdimono1 gc wii")
kinds("sys_arcade", "arcade mame mame2003 mame2010 fbneo fba cps1 cps2 cps3 neogeo naomi atomiswave daphne alg model2 model3")
kinds("sys_computer", "msdos dos pc pc98 x68000 x1 macintosh amiga amigacd32 atarist scummvm windows")
kinds("sys_keyboard", "c64 c16 c128 vic20 msx msx2 zxspectrum zx81 amstradcpc gx4000 bbcmicro apple2 atari800 atarixegs ti99 "
      "dragon32 coco thomson enterprise videoton")
kinds("sys_lcd", "gameandwatch lcdgames")
kinds("sys_mini", "pico-8 pico8 tic-80 tic80 wasm-4 wasm4 lowresnx uzebox vircon32 arduboy love2d j2me puzzlescript")
kinds("sys_console", "ports openbor easyrpg doom wolf solarus onscripter cavestory piece kodi retroarch")


def mask_of(dev, px):
    """desenho do aparelho (branco) em px x px"""
    ic = MI.Ic()
    MI.ICONS[dev](ic)
    return ic.im.resize((px, px), Image.LANCZOS)


def gradient(w, h, c1, c2, diag=True):
    g = Image.new("RGBA", (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            k = ((x / w) + (y / h)) / 2 if diag else y / h
            px[x, y] = tuple(int(c1[j] + (c2[j] - c1[j]) * k) for j in range(3)) + (255,)
    return g


GRADS = {}
def grad_cached(c1, c2):
    key = (c1, c2)
    if key not in GRADS:
        GRADS[key] = gradient(SZ, SZ, c1, c2)
    return GRADS[key]


def rounded_mask(box, r):
    m = Image.new("L", (SZ, SZ), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=r, fill=255)
    return m


def make(name, dev, c1, c2):
    img = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
    g = grad_cached(c1, c2)
    # borda em degrade
    outer = rounded_mask((4, 4, SZ - 5, SZ - 5), 70)
    img.paste(g, (0, 0), outer)
    # area clara
    inner_box = (20, 20, SZ - 21, SZ - 21)
    inner = rounded_mask(inner_box, 56)
    tint = gradient(SZ, SZ, (255, 255, 255), tuple(int(255 - (255 - c) * 0.10) for c in c1), diag=False)
    img.paste(tint, (0, 0), inner)
    # padrao de pontos suave
    pat = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
    d = ImageDraw.Draw(pat)
    for y in range(32, SZ - 24, 18):
        for x in range(32 + (9 if (y // 18) % 2 else 0), SZ - 24, 18):
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=c1 + (30,))
    pm = Image.new("L", (SZ, SZ), 0); pm.paste(inner, (0, 0))
    img.alpha_composite(Image.composite(pat, Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0)), pm))
    # silhueta grande e clara ao fundo (canto de baixo, inclinada)
    big = mask_of(dev, 300).rotate(-18, resample=Image.BICUBIC, expand=False)
    ghost = Image.new("RGBA", big.size, c2 + (0,))
    ghost.putalpha(big.getchannel("A").point(lambda a: a * 0.13))
    layer = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
    layer.paste(ghost, (150, 150), ghost)
    img.alpha_composite(Image.composite(layer, Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0)), inner))
    # desenho central em degrade, com sombra suave
    px = 200
    m = mask_of(dev, px).getchannel("A")
    off = ((SZ - px) // 2, (SZ - px) // 2 - 6)
    sh = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0))
    shm = Image.new("L", (SZ, SZ), 0); shm.paste(m, (off[0], off[1] + 8))
    sh.putalpha(shm.filter(ImageFilter.GaussianBlur(7)).point(lambda a: a * 0.22))
    img.alpha_composite(sh)
    col = gradient(px, px, c1, c2)
    fg = Image.new("RGBA", (SZ, SZ), (0, 0, 0, 0)); fg.paste(col, off, m)
    img.alpha_composite(fg)
    out = img.resize((FINAL, FINAL), Image.LANCZOS)
    out.save(os.path.join(OUT, name + ".png"), optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sorted(KIND)
    for n in names:
        h = 0
        for ch in n:
            h = (h * 31 + ord(ch)) % 1000003
        c1, c2 = PAIRS[h % len(PAIRS)]
        make(n, KIND[n], c1, c2)
    print(len(names), "icones em", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
