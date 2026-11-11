#!/usr/bin/env python3
"""Gera a familia de icones de linha do R36S PORT HUB (0.5.0).

Saida: src/assets/icons/line/<id>.png, 64x64, branco sobre transparente.
O app pinta cada icone com a cor do tema (ui/icons.lua). Estilo unico:
traco de 5 px (na escala 64) com pontas arredondadas, cantos arredondados,
preenchimentos so em detalhes pequenos.

Uso: python3 tools/make_icons.py
"""
import math
import os
from PIL import Image, ImageDraw

S = 4                 # desenha em 256x256 e reduz (anti-serrilhado)
N = 64 * S
W = 5 * S             # largura do traco
OUT = os.path.join(os.path.dirname(__file__), "..", "src", "assets", "icons", "line")
WHITE = (255, 255, 255, 255)


class Ic:
    def __init__(self):
        self.im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def p(v):
        return v * S

    def line(self, *pts, w=W):
        pts = [(self.p(x), self.p(y)) for x, y in pts]
        self.d.line(pts, fill=WHITE, width=w, joint="curve")
        for x, y in (pts[0], pts[-1]):
            self.d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE)
        for x, y in pts[1:-1]:
            self.d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE)

    def rect(self, x, y, w, h, r=6, fill=False, lw=W):
        box = (self.p(x), self.p(y), self.p(x + w), self.p(y + h))
        if fill:
            self.d.rounded_rectangle(box, radius=self.p(r), fill=WHITE)
        else:
            self.d.rounded_rectangle(box, radius=self.p(r), outline=WHITE, width=lw)

    def circle(self, cx, cy, r, fill=False, lw=W):
        box = (self.p(cx - r), self.p(cy - r), self.p(cx + r), self.p(cy + r))
        if fill:
            self.d.ellipse(box, fill=WHITE)
        else:
            self.d.ellipse(box, outline=WHITE, width=lw)

    def arc(self, cx, cy, r, a0, a1, lw=W):
        box = (self.p(cx - r), self.p(cy - r), self.p(cx + r), self.p(cy + r))
        self.d.arc(box, a0, a1, fill=WHITE, width=lw)
        for a in (a0, a1):
            x = self.p(cx) + self.p(r) * math.cos(math.radians(a)) - (lw / 2) * math.cos(math.radians(a))
            y = self.p(cy) + self.p(r) * math.sin(math.radians(a)) - (lw / 2) * math.sin(math.radians(a))
            self.d.ellipse((x - lw / 2, y - lw / 2, x + lw / 2, y + lw / 2), fill=WHITE)

    def poly(self, *pts, fill=True):
        pts = [(self.p(x), self.p(y)) for x, y in pts]
        if fill:
            self.d.polygon(pts, fill=WHITE)
        else:
            self.d.line(pts + [pts[0]], fill=WHITE, width=W, joint="curve")

    def dot(self, x, y, r=3.5):
        self.circle(x, y, r, fill=True)

    def clear_circle(self, cx, cy, r):
        box = (self.p(cx - r), self.p(cy - r), self.p(cx + r), self.p(cy + r))
        self.d.ellipse(box, fill=(0, 0, 0, 0))

    def save(self, name):
        im = self.im.resize((64, 64), Image.LANCZOS)
        im.save(os.path.join(OUT, name + ".png"), optimize=True)


ICONS = {}


def icon(*names):
    def deco(fn):
        for n in names:
            ICONS[n] = fn
        return fn
    return deco


def gear(i, cx, cy, r_out, r_in, teeth=8):
    i.circle(cx, cy, r_in, lw=7 * S)
    for k in range(teeth):
        a = k * 2 * math.pi / teeth
        i.line((cx + math.cos(a) * r_in, cy + math.sin(a) * r_in),
               (cx + math.cos(a) * r_out, cy + math.sin(a) * r_out), w=10 * S)


# ---------------------------------------------------------------- canais
@icon("set_store", "store")
def _(i):  # sacola de compras
    i.rect(12, 22, 40, 32, 7)
    i.arc(32, 22, 10, 180, 360)
    i.dot(24, 32); i.dot(40, 32)


@icon("games", "library")
def _(i):  # controle
    i.rect(6, 20, 52, 28, 13)
    i.line((17, 34), (27, 34)); i.line((22, 29), (22, 39))
    i.dot(40, 31, 3.2); i.dot(46, 37, 3.2)


@icon("set_grid", "cats")
def _(i):
    for x in (10, 34):
        for y in (10, 34):
            i.rect(x, y, 20, 20, 5)


@icon("set_myports", "mine")
def _(i):  # caixa com check
    i.rect(10, 16, 44, 38, 7)
    i.line((10, 26), (54, 26))
    i.line((24, 40), (30, 46), (42, 34))
    i.line((20, 10), (44, 10))


@icon("set_favorites", "favorites")
def _(i):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        r = 24 if k % 2 == 0 else 10.5
        pts.append((32 + math.cos(a) * r, 34 + math.sin(a) * r))
    i.poly(*pts, fill=False)


@icon("download", "set_downloads")
def _(i):
    i.line((32, 8), (32, 38))
    i.line((20, 27), (32, 39), (44, 27))
    i.line((10, 40), (10, 52), (54, 52), (54, 40))


@icon("settings", "set_settings")
def _(i):
    gear(i, 32, 32, 25, 15)
    i.clear_circle(32, 32, 6)


@icon("set_about", "about")
def _(i):
    i.circle(32, 32, 24)
    i.dot(32, 20, 3.8)
    i.line((32, 29), (32, 45))


@icon("set_exit", "exit")
def _(i):  # botao de energia
    i.arc(32, 34, 20, 300, 240)
    i.line((32, 8), (32, 32))


# ---------------------------------------------------------------- sistema
@icon("set_ftp", "ftp")
def _(i):  # pasta com setas
    i.rect(8, 16, 48, 36, 6)
    i.line((8, 22), (8, 14), (24, 14), (29, 19))
    i.line((24, 40), (24, 28)); i.line((19, 32), (24, 27), (29, 32))
    i.line((40, 28), (40, 40)); i.line((35, 36), (40, 41), (45, 36))


@icon("set_network", "wifi", "network")
def _(i):
    for r in (26, 17, 8):
        i.arc(32, 48, r, 225, 315)
    i.dot(32, 48, 4)


@icon("set_battery", "battery")
def _(i):
    i.rect(6, 20, 46, 26, 6)
    i.rect(53, 28, 6, 10, 2, fill=True)
    i.rect(12, 26, 10, 14, 2, fill=True)
    i.rect(25, 26, 10, 14, 2, fill=True)


@icon("set_tools", "portmaster", "tools")
def _(i):  # chave inglesa + chave de fenda cruzadas
    i.line((12, 52), (34, 30))
    i.arc(42, 22, 11, 0, 270)
    i.line((52, 52), (24, 24))
    i.line((18, 12), (12, 18), (20, 26), (26, 20), (18, 12))


@icon("set_updates", "updates")
def _(i):
    i.arc(32, 32, 21, 200, 470)
    i.poly((12, 12), (24, 26), (8, 28))
    i.line((32, 22), (32, 34), (40, 38))


@icon("set_appearance", "themes")
def _(i):  # paleta de pintor
    i.arc(32, 32, 24, 0, 300)
    i.line((53, 20), (46, 30), (52, 40))
    i.dot(22, 22); i.dot(34, 16); i.dot(18, 36); i.dot(28, 46)


@icon("set_console", "system", "console")
def _(i):  # console portatil (R36S)
    i.rect(14, 6, 36, 52, 7)
    i.rect(20, 12, 24, 18, 3)
    i.line((21, 42), (29, 42)); i.line((25, 38), (25, 46))
    i.dot(38, 40, 2.8); i.dot(42, 45, 2.8)


@icon("set_analyzer", "console_info")
def _(i):  # chip
    i.rect(16, 16, 32, 32, 5)
    i.rect(25, 25, 14, 14, 2, fill=True)
    for v in (24, 32, 40):
        i.line((v, 6), (v, 12)); i.line((v, 52), (v, 58))
        i.line((6, v), (12, v)); i.line((52, v), (58, v))


@icon("set_audio")
def _(i):
    i.poly((8, 24), (18, 24), (30, 12), (30, 52), (18, 40), (8, 40))
    i.arc(32, 32, 12, 315, 405)
    i.arc(32, 32, 22, 315, 405)


@icon("set_controls")
def _(i):  # analogico
    i.circle(32, 36, 18)
    i.circle(32, 36, 7, fill=True)
    i.line((32, 6), (32, 12)); i.line((26, 12), (32, 6), (38, 12))


@icon("set_backup")
def _(i):  # caixa de arquivo
    i.rect(8, 12, 48, 12, 4)
    i.rect(12, 24, 40, 30, 5)
    i.line((26, 34), (38, 34))


@icon("set_notify")
def _(i):  # sino
    i.line((14, 44), (50, 44))
    i.arc(32, 30, 14, 180, 360)
    i.line((18, 30), (18, 44)); i.line((46, 30), (46, 44))
    i.arc(32, 46, 6, 0, 180)
    i.line((32, 10), (32, 14))


@icon("set_text")
def _(i):
    i.line((10, 52), (26, 12), (42, 52))
    i.line((15, 38), (37, 38))
    i.line((44, 52), (54, 52))


@icon("set_led")
def _(i):  # lampada
    i.arc(32, 26, 16, 135, 405)
    i.line((24, 40), (24, 46), (40, 46), (40, 40))
    i.line((26, 54), (38, 54))


@icon("set_sdmaint", "set_storage", "storage", "sd")
def _(i):  # cartao SD
    i.poly((18, 6), (48, 6), (48, 58), (14, 58), (14, 18), fill=False)
    for x in (24, 31, 38):
        i.line((x, 14), (x, 22))


@icon("set_clock", "clock")
def _(i):
    i.circle(32, 32, 24)
    i.line((32, 18), (32, 32), (42, 38))


@icon("set_prefs", "prefs")
def _(i):  # controles deslizantes
    for y, x in ((16, 22), (32, 42), (48, 28)):
        i.line((8, y), (56, y))
        i.circle(x, y, 6, fill=True)


@icon("set_lang", "language")
def _(i):  # globo
    i.circle(32, 32, 24)
    i.d.ellipse((i.p(22), i.p(8), i.p(42), i.p(56)), outline=WHITE, width=W)
    i.line((8, 32), (56, 32))


@icon("set_catalog", "catalog")
def _(i):  # lista
    for y in (16, 32, 48):
        i.dot(12, y, 4)
        i.line((22, y), (54, y))


@icon("set_diag", "diagnostico_do_sistema")
def _(i):  # pulso
    i.rect(6, 10, 52, 44, 7)
    i.line((12, 34), (22, 34), (27, 22), (35, 44), (40, 30), (52, 30))


@icon("manutencao")
def _(i):  # chave inglesa
    i.line((12, 52), (34, 30))
    i.arc(42, 22, 12, 0, 270)


@icon("testes_de_controles", "testes_de_analogicos", "testes_de_botoes")
def _(i):
    i.rect(6, 20, 52, 28, 13)
    i.circle(20, 34, 6)
    i.dot(40, 30, 3.2); i.dot(46, 37, 3.2)


@icon("ferramentas_de_sistema")
def _(i):
    gear(i, 26, 26, 16, 8, 6)
    i.line((40, 40), (54, 54))
    i.line((34, 46), (46, 34))


@icon("search")
def _(i):
    i.circle(27, 27, 16)
    i.line((39, 39), (54, 54))


@icon("news")
def _(i):  # estrela de novidade / brilho
    i.line((32, 8), (32, 22)); i.line((32, 42), (32, 56))
    i.line((8, 32), (22, 32)); i.line((42, 32), (56, 32))
    i.line((16, 16), (24, 24)); i.line((40, 40), (48, 48))
    i.line((48, 16), (40, 24)); i.line((24, 40), (16, 48))


@icon("bios")
def _(i):  # chip com "B"
    i.rect(14, 14, 36, 36, 5)
    for v in (24, 32, 40):
        i.line((v, 6), (v, 12)); i.line((v, 52), (v, 58))
    i.line((26, 22), (26, 42))
    i.arc(30, 27, 5, 270, 450); i.arc(31, 37, 6, 270, 450)


@icon("generic")
def _(i):
    i.rect(10, 10, 44, 44, 9)
    i.dot(32, 32, 6)


# ---------------------------------------------------------------- categorias
@icon("acao")
def _(i):  # explosao
    pts = []
    for k in range(16):
        a = -math.pi / 2 + k * math.pi / 8
        r = 25 if k % 2 == 0 else 13
        pts.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    i.poly(*pts, fill=False)


@icon("aventura")
def _(i):  # bussola
    i.circle(32, 32, 24)
    i.poly((32, 14), (38, 32), (32, 50), (26, 32))


@icon("rpg")
def _(i):  # espada
    i.line((46, 10), (54, 10), (54, 18), (26, 46))
    i.line((46, 10), (18, 38))
    i.line((14, 34), (30, 50))
    i.line((18, 46), (10, 54))


@icon("plataforma")
def _(i):
    i.rect(6, 40, 16, 16, 3); i.rect(24, 40, 16, 16, 3); i.rect(42, 40, 16, 16, 3)
    i.rect(24, 22, 16, 16, 3); i.rect(42, 22, 16, 16, 3)
    i.rect(42, 6, 16, 14, 3)


@icon("corrida")
def _(i):  # bandeira quadriculada
    i.line((12, 8), (12, 58))
    i.rect(16, 10, 38, 26, 3)
    for r in range(3):
        for c in range(4):
            if (r + c) % 2 == 0:
                i.rect(18 + c * 9, 12 + r * 7.5, 8, 7, 1, fill=True)


@icon("luta")
def _(i):  # luva
    i.rect(14, 10, 36, 32, 14)
    i.rect(18, 42, 26, 14, 3)
    i.line((24, 24), (34, 24))


@icon("tiro")
def _(i):  # mira
    i.circle(32, 32, 20)
    i.line((32, 4), (32, 18)); i.line((32, 46), (32, 60))
    i.line((4, 32), (18, 32)); i.line((46, 32), (60, 32))
    i.dot(32, 32, 4)


@icon("terror")
def _(i):  # fantasma
    i.arc(32, 28, 18, 180, 360)
    i.line((14, 28), (14, 54), (20, 48), (26, 54), (32, 48), (38, 54), (44, 48), (50, 54), (50, 28))
    i.dot(25, 28, 3.5); i.dot(39, 28, 3.5)


@icon("puzzle")
def _(i):
    i.rect(10, 18, 36, 36, 5)
    i.circle(28, 14, 6)
    i.circle(50, 36, 6)


@icon("estrategia")
def _(i):  # torre de xadrez
    i.line((18, 10), (18, 18), (46, 18), (46, 10))
    i.line((28, 10), (28, 14)); i.line((36, 10), (36, 14))
    i.line((22, 18), (22, 46)); i.line((42, 18), (42, 46))
    i.rect(14, 46, 36, 10, 3)


@icon("arcade")
def _(i):  # fliperama (joystick)
    i.rect(10, 38, 44, 18, 5)
    i.line((32, 38), (32, 20))
    i.circle(32, 14, 8, fill=True)
    i.dot(44, 47, 3.5)


@icon("esportes")
def _(i):  # bola
    i.circle(32, 32, 24)
    i.poly((32, 22), (41, 29), (38, 40), (26, 40), (23, 29), fill=False)


@icon("classicos")
def _(i):  # cartucho
    i.rect(12, 8, 40, 48, 5)
    i.rect(18, 14, 28, 20, 3)
    for x in (20, 28, 36, 44):
        i.line((x, 46), (x, 52))


# ---------------------------------------------------------------- sistemas (Biblioteca)
# Silhuetas genericas por tipo de aparelho (sem logotipos de fabricantes).
@icon("sys_handheld")
def _(i):  # portatil horizontal (tela no meio)
    i.rect(4, 16, 56, 32, 12)
    i.rect(20, 21, 24, 22, 3)
    i.line((9, 32), (15, 32)); i.line((12, 29), (12, 35))
    i.dot(51, 29, 2.6); i.dot(51, 36, 2.6)


@icon("sys_vertical")
def _(i):  # portatil vertical (tela em cima, botoes embaixo)
    i.rect(16, 4, 32, 56, 7)
    i.rect(21, 9, 22, 19, 3)
    i.line((22, 42), (30, 42)); i.line((26, 38), (26, 46))
    i.dot(38, 40, 2.6); i.dot(42, 45, 2.6)


@icon("sys_dual")
def _(i):  # duas telas (dobravel)
    i.rect(12, 4, 40, 26, 5)
    i.rect(18, 9, 28, 16, 2)
    i.rect(12, 34, 40, 26, 5)
    i.rect(22, 38, 20, 14, 2)


@icon("sys_cart")
def _(i):  # console de mesa com cartucho
    i.rect(6, 30, 52, 24, 6)
    i.rect(18, 12, 28, 20, 3)
    i.line((24, 18), (40, 18))
    i.dot(16, 42, 3); i.line((40, 42), (50, 42))


@icon("sys_disc")
def _(i):  # disco
    i.circle(32, 32, 25)
    i.circle(32, 32, 7)
    i.arc(32, 32, 16, 200, 250)


@icon("sys_arcade")
def _(i):  # gabinete de fliperama
    i.poly((14, 6), (50, 6), (50, 58), (14, 58), fill=False)
    i.rect(20, 12, 24, 18, 3)
    i.line((14, 36), (50, 36))
    i.line((26, 46), (26, 40)); i.dot(26, 39, 3.2); i.dot(38, 44, 3)


@icon("sys_computer")
def _(i):  # computador classico
    i.rect(8, 8, 48, 34, 5)
    i.rect(14, 14, 36, 22, 2)
    i.line((24, 42), (22, 50)); i.line((40, 42), (42, 50))
    i.line((12, 54), (52, 54))


@icon("sys_console")
def _(i):  # console de mesa generico
    i.rect(6, 22, 52, 26, 8)
    i.line((14, 40), (30, 40))
    i.dot(44, 35, 3.5)
    i.line((32, 22), (32, 12), (44, 12))


@icon("sys_keyboard")
def _(i):  # computador de teclado (8 bits)
    i.poly((6, 26), (58, 26), (60, 50), (4, 50), fill=False)
    for x in range(12, 54, 8):
        i.dot(x, 34, 2.4)
        i.dot(x + 3, 41, 2.4)
    i.line((20, 46), (44, 46))


@icon("sys_lcd")
def _(i):  # jogo de LCD de bolso
    i.rect(4, 14, 56, 36, 6)
    i.rect(17, 19, 30, 26, 3)
    i.line((8, 32), (13, 32)); i.line((10.5, 29.5), (10.5, 34.5))
    i.dot(53, 32, 3)


@icon("sys_mini")
def _(i):  # console de fantasia / portatil quadrado
    i.rect(12, 6, 40, 52, 10)
    i.rect(18, 12, 28, 24, 4)
    i.line((19, 46), (27, 46)); i.line((23, 42), (23, 50))
    i.dot(39, 44, 2.8); i.dot(44, 48, 2.8)


def main():
    os.makedirs(OUT, exist_ok=True)
    done = {}
    for name, fn in ICONS.items():
        if fn not in done:
            ic = Ic(); fn(ic); done[fn] = ic
        done[fn].save(name)
    print(len(ICONS), "icones em", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
