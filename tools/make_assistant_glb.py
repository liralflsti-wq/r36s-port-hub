#!/usr/bin/env python3
# =============================================================================
#  (base de geometria e exportacao GLB, vinda do antigo gerador de mascotes)
#  Saida: assets/mascots/<id>.glb  (glTF 2.0 binario, sem dependencias)
#         assets/mascots/hats.glb  (acessorios, um no por chapeu)
#  Cada mascote e montado por PECAS (nos do glTF) com o ponto de articulacao
#  (pivo) no lugar certo, para o AnimationController mexer cada uma:
#    root > body > head > (eye_l, eye_r, mouth, ear_*, horn_*, hat_anchor)
#               > arm_l, arm_r, leg_l, leg_r, tail, wing_l, wing_r ...
#  Sombreamento chapado (normal por face) e cor por vertice. Pecas com
#  extras.tint=true sao pintadas em tons de cinza e recebem a cor escolhida
#  pelo jogador no shader; extras.emissive=true brilha (sem luz).
#  Coordenadas: Y para cima, frente para +Z, pes em y=0, altura ~1.0.
#  Uso: python3 tools/make_mascots_glb.py [pasta_saida]
# =============================================================================
import json, math, os, struct, sys

# ---------------------------------------------------------------- geometria
def ico(sub=1):
    t = (1 + 5 ** 0.5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    v = [norm(p) for p in v]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
         (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
         (8, 6, 7), (9, 8, 1)]
    for _ in range(sub):
        cache = {}
        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                p = norm(tuple((v[a][i] + v[b][i]) / 2 for i in range(3)))
                v.append(p); cache[k] = len(v) - 1
            return cache[k]
        nf = []
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = nf
    return [tuple(v[i] for i in tri) for tri in f]

def norm(p):
    l = math.sqrt(sum(c * c for c in p)) or 1
    return tuple(c / l for c in p)

def box():
    P = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
    Q = [(4, 5, 6, 7), (1, 0, 3, 2), (0, 4, 7, 3), (5, 1, 2, 6), (3, 7, 6, 2), (0, 1, 5, 4)]
    out = []
    for a, b, c, d in Q:
        out += [(P[a], P[b], P[c]), (P[a], P[c], P[d])]
    return out

def cyl(seg=8, r0=1.0, r1=1.0, caps=True):
    """cilindro/cone de y=0 a y=1 (raio r0 embaixo, r1 em cima)"""
    out = []
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        b0 = (math.sin(a0) * r0, 0, math.cos(a0) * r0); b1 = (math.sin(a1) * r0, 0, math.cos(a1) * r0)
        t0 = (math.sin(a0) * r1, 1, math.cos(a0) * r1); t1 = (math.sin(a1) * r1, 1, math.cos(a1) * r1)
        if r1 > 0:
            out += [(b0, b1, t1), (b0, t1, t0)]
        else:
            out += [(b0, b1, (0, 1, 0))]
        if caps:
            out.append(((0, 0, 0), b1, b0))
            if r1 > 0:
                out.append(((0, 1, 0), t0, t1))
    return out

def cone(seg=8):
    return cyl(seg, 1.0, 0.0)

def tri2(a, b, c):
    """triangulo de duas faces (asas, capas)"""
    return [(a, b, c), (a, c, b)]

def rotm(rx, ry, rz):
    rx, ry, rz = map(math.radians, (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    X = ((1, 0, 0), (0, cx, -sx), (0, sx, cx))
    Y = ((cy, 0, sy), (0, 1, 0), (-sy, 0, cy))
    Z = ((cz, -sz, 0), (sz, cz, 0), (0, 0, 1))
    def mm(A, B):
        return tuple(tuple(sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)) for i in range(3))
    return mm(Y, mm(X, Z))

def xform(tris, s=(1, 1, 1), r=(0, 0, 0), t=(0, 0, 0)):
    if isinstance(s, (int, float)):
        s = (s, s, s)
    R = rotm(*r)
    out = []
    for tri in tris:
        nt = []
        for p in tri:
            q = (p[0] * s[0], p[1] * s[1], p[2] * s[2])
            q = tuple(R[i][0] * q[0] + R[i][1] * q[1] + R[i][2] * q[2] for i in range(3))
            nt.append((q[0] + t[0], q[1] + t[1], q[2] + t[2]))
        # escala negativa inverte a ordem dos vertices
        if s[0] * s[1] * s[2] < 0:
            nt = [nt[0], nt[2], nt[1]]
        out.append(tuple(nt))
    return out

# ---------------------------------------------------------------- modelo
class Model:
    def __init__(self, mid):
        self.id = mid
        self.parts = {}   # nome -> dict(parent, pivot, tris=[(tri, rgb)], extras)
        self.order = []

    def part(self, name, parent=None, pivot=(0, 0, 0), **extras):
        self.parts[name] = {"parent": parent, "pivot": pivot, "tris": [], "extras": extras}
        self.order.append(name)
        return name

    def add(self, name, tris, rgb):
        self.parts[name]["tris"] += [(t, rgb) for t in tris]

    def tri_count(self):
        return sum(len(p["tris"]) for p in self.parts.values())

def facenormal(a, b, c):
    u = [b[i] - a[i] for i in range(3)]; v = [c[i] - a[i] for i in range(3)]
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    return norm(n)

def model_bounds(model):
    """altura (pes em y=0 ate o topo), largura e profundidade do modelo"""
    ys, xs, zs = [0.0], [0.0], [0.0]
    for p in model.parts.values():
        for tri, _ in p["tris"]:
            for v in tri:
                xs.append(abs(v[0])); ys.append(v[1]); zs.append(abs(v[2]))
    return {"height": round(max(ys), 4), "width": round(2 * max(xs), 4), "depth": round(2 * max(zs), 4)}

def write_glb(model, path):
    nodes, meshes, accessors, views = [], [], [], []
    blob = bytearray()
    index = {n: i for i, n in enumerate(model.order)}

    def push(data, target=34962):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(data)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(views) - 1

    for name in model.order:
        p = model.parts[name]
        par = p["parent"]
        ppiv = model.parts[par]["pivot"] if par else (0, 0, 0)
        node = {"name": name, "translation": [round(p["pivot"][i] - ppiv[i], 5) for i in range(3)]}
        ex = {k: v for k, v in p["extras"].items() if v}
        if ex:
            node["extras"] = ex
        if p["tris"]:
            pos, col = bytearray(), bytearray()
            mn, mx = [1e9] * 3, [-1e9] * 3
            for tri, rgb in p["tris"]:
                for v in tri:
                    lv = [v[i] - p["pivot"][i] for i in range(3)]
                    for i in range(3):
                        mn[i] = min(mn[i], lv[i]); mx[i] = max(mx[i], lv[i])
                    pos += struct.pack("<3f", *lv)
                    col += struct.pack("<4B", *[max(0, min(255, int(round(c * 255)))) for c in rgb], 255)
            cnt = len(p["tris"]) * 3
            a0 = len(accessors)
            accessors.append({"bufferView": push(pos), "componentType": 5126, "count": cnt, "type": "VEC3",
                              "min": [round(x, 5) for x in mn], "max": [round(x, 5) for x in mx]})
            # sem NORMAL: pelo glTF 2.0 o leitor calcula a normal chapada de cada
            # face (e o visual low-poly que queremos), e o arquivo fica 1/3 menor
            accessors.append({"bufferView": push(col), "componentType": 5121, "normalized": True, "count": cnt,
                              "type": "VEC4"})
            meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": a0, "COLOR_0": a0 + 1},
                                                         "mode": 4}]})
            node["mesh"] = len(meshes) - 1
        nodes.append(node)
    for name in model.order:
        par = model.parts[name]["parent"]
        if par:
            nodes[index[par]].setdefault("children", []).append(index[name])
    roots = [index[n] for n in model.order if not model.parts[n]["parent"]]
    while len(blob) % 4:
        blob.append(0)
    gltf = {"asset": {"version": "2.0", "generator": "R36S PORT HUB make_mascots_glb.py"},
            "scene": 0, "scenes": [{"name": model.id, "nodes": roots}], "nodes": nodes, "meshes": meshes,
            "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}],
            "extras": {"triangles": model.tri_count(), **model_bounds(model)}}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    with open(path, "wb") as f:
        f.write(out)
    return len(out)


# ============================================================== DRONE ASSISTENTE
# Assistente do R36S PORT HUB: drone flutuante original (arte em codigo).
# Cabeca branca polida com visor de vidro escuro e olhos ciano, corpo pequeno
# que termina num propulsor de luz, maos que flutuam soltas, anel de luz na
# cintura e "orelhas" com aro luminoso. Pecas com nome para a animacao:
#   root > body > (head > visor, eye_l, eye_r, ear_l, ear_r, antenna_tip),
#   halo, thruster, hand_l, hand_r
# extras: smooth (sombreamento suave), gloss (brilho), emissive (luz propria)
# Uso: python3 tools/make_assistant_glb.py  -> src/assets/assistant/drone.glb

WHITE = (0.93, 0.95, 0.98)
SHELL2 = (0.78, 0.82, 0.88)
NAVY = (0.10, 0.16, 0.32)
NAVY2 = (0.16, 0.24, 0.45)
GLASS = (0.03, 0.05, 0.10)
CYAN = (0.35, 0.92, 1.0)
CYAN2 = (0.6, 0.98, 1.0)

def torus(R, r, seg=32, side=8):
    out = []
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        for j in range(side):
            b0, b1 = 2 * math.pi * j / side, 2 * math.pi * (j + 1) / side
            def p(a, b):
                return ((R + r * math.cos(b)) * math.cos(a), r * math.sin(b), (R + r * math.cos(b)) * math.sin(a))
            out += [(p(a0, b0), p(a1, b0), p(a1, b1)), (p(a0, b0), p(a1, b1), p(a0, b1))]
    return out

def drone():
    m = Model("drone")
    m.part("root")
    m.part("body", "root", (0, 0.42, 0), smooth=True, gloss=0.8)
    m.add("body", xform(ico(2), (0.25, 0.27, 0.23), t=(0, 0.44, 0)), WHITE)
    m.add("body", xform(cyl(24, 1.0, 0.86), (0.24, 0.07, 0.22), t=(0, 0.26, 0)), NAVY)
    m.add("body", xform(ico(2), (0.17, 0.08, 0.16), t=(0, 0.24, 0)), NAVY2)
    m.part("chest", "body", (0, 0.46, 0.23), emissive=True)
    m.add("chest", xform(cyl(16), (0.045, 0.01, 0.045), r=(90, 0, 0), t=(0, 0.47, 0.225)), CYAN)
    # bocal do propulsor + chama curta em duas camadas
    m.add("body", xform(cyl(16, 0.7, 1.0), (0.09, 0.06, 0.09), t=(0, 0.13, 0)), NAVY2)
    m.part("thruster", "body", (0, 0.13, 0), emissive=True)
    m.add("thruster", xform(cyl(16, 1.0, 0.0, caps=False), (0.075, 0.16, 0.075), r=(180, 0, 0), t=(0, 0.13, 0)), CYAN)
    m.add("thruster", xform(cyl(12, 1.0, 0.0, caps=False), (0.04, 0.1, 0.04), r=(180, 0, 0), t=(0, 0.125, 0)), (0.9, 1.0, 1.0))
    m.part("halo", "root", (0, 0.38, 0), emissive=True)
    m.add("halo", xform(torus(0.36, 0.02, 40, 6), 1, r=(8, 0, 0), t=(0, 0.38, 0)), CYAN2)
    for k in range(3):
        a = k * 2.094
        m.add("halo", xform(ico(1), 0.025, t=(math.cos(a) * 0.36, 0.38 + math.sin(a) * 0.05, math.sin(a) * 0.36)), CYAN2)
    # cabeca
    m.part("head", "body", (0, 0.66, 0), smooth=True, gloss=0.9)
    m.add("head", xform(ico(3), (0.40, 0.33, 0.36), t=(0, 0.94, 0)), WHITE)
    # topo azul-marinho com friso ciano (identidade do hub)
    m.part("cap", "head", (0, 1.15, 0), smooth=True, gloss=0.8)
    m.add("cap", xform(ico(3), (0.30, 0.13, 0.27), t=(0, 1.16, -0.03)), NAVY)

    m.add("head", xform(torus(0.375, 0.022, 40, 6), (1, 1, 0.92), t=(0, 0.74, 0)), NAVY)
    m.part("visor", "head", (0, 0.92, 0.25), smooth=True, gloss=1.0)
    # visor em faixa larga que abraca a cabeca
    m.add("visor", xform(ico(3), (0.36, 0.15, 0.2), t=(0, 0.92, 0.2)), GLASS)
    for side, sx in (("l", -1), ("r", 1)):
        n = m.part("eye_" + side, "head", (sx * 0.105, 0.93, 0.375), emissive=True, smooth=True)
        # olhos quadrados de pixel
        m.add(n, xform(box(), (0.042, 0.042, 0.012), t=(sx * 0.105, 0.925, 0.385)), CYAN)
        e = m.part("ear_" + side, "head", (sx * 0.39, 0.95, 0), smooth=True, gloss=0.7)
        m.add(e, xform(cyl(20), (0.1, 0.06, 0.1), r=(0, 0, sx * 90), t=(sx * 0.36, 0.95, 0)), NAVY2)
        g = m.part("earglow_" + side, "ear_" + side, (sx * 0.43, 0.95, 0), emissive=True)
        m.add(g, xform(torus(0.075, 0.012, 24, 5), 1, r=(0, 0, sx * 90), t=(sx * 0.425, 0.95, 0)), CYAN)
    m.part("antenna", "head", (0, 1.26, 0), smooth=True, gloss=0.6)
    m.add("antenna", xform(cyl(10), (0.012, 0.09, 0.012), t=(0, 1.24, -0.02)), NAVY2)
    m.part("antenna_tip", "antenna", (0, 1.34, -0.02), emissive=True, smooth=True)
    m.add("antenna_tip", xform(ico(2), 0.03, t=(0, 1.345, -0.02)), CYAN)
    # maos flutuantes
    for side, sx in (("l", -1), ("r", 1)):
        n = m.part("hand_" + side, "root", (sx * 0.44, 0.44, 0.06), smooth=True, gloss=0.8)
        m.add(n, xform(ico(2), (0.08, 0.095, 0.07), t=(sx * 0.44, 0.45, 0.06)), WHITE)
        m.add(n, xform(ico(2), (0.03, 0.045, 0.03), r=(0, 0, sx * 35), t=(sx * 0.395, 0.49, 0.09)), WHITE)
        m.add(n, xform(cyl(16), (0.065, 0.035, 0.06), t=(sx * 0.44, 0.34, 0.06)), NAVY)
        m.part("handglow_" + side, n, (sx * 0.44, 0.355, 0.06), emissive=True)
        m.add("handglow_" + side, xform(torus(0.066, 0.006, 20, 4), 1, t=(sx * 0.44, 0.37, 0.06)), CYAN)
    return m

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "src", "assets", "assistant")
    os.makedirs(out, exist_ok=True)
    m = drone()
    size = write_glb(m, os.path.join(out, "drone.glb"))
    print("drone: %d triangulos, %d bytes, %d pecas" % (m.tri_count(), size, len(m.order)))
