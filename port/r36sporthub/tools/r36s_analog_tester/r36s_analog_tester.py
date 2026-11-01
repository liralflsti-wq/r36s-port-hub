#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# R36S Analog Tester - por LagdoLira
import os, sys, time, struct, fcntl, select, glob, math, re, zlib, array

EV_KEY, EV_ABS = 1, 3
FMT = 'llHHi'
SZ = struct.calcsize(FMT)
HAT_X, HAT_Y = 0x10, 0x11

# Botoes de acao como estao impressos no R36S (layout Nintendo):
#        X
#      Y   A
#        B
# codigo evdev -> letra do botao. Se no seu aparelho estiver trocado, ajuste aqui.
FACE_LAYOUT = {0x130: 'B', 0x131: 'A', 0x133: 'X', 0x134: 'Y'}
KEYNAMES = {
    0x130: 'BOTÃO ' + FACE_LAYOUT[0x130], 0x131: 'BOTÃO ' + FACE_LAYOUT[0x131],
    0x132: 'BTN C', 0x133: 'BOTÃO ' + FACE_LAYOUT[0x133],
    0x134: 'BOTÃO ' + FACE_LAYOUT[0x134], 0x135: 'BTN Z', 0x136: 'L1', 0x137: 'R1', 0x138: 'L2',
    0x139: 'R2', 0x13a: 'SELECT', 0x13b: 'START', 0x13c: 'HOTKEY', 0x13d: 'L3',
    0x13e: 'R3',
    0x2c0: 'SELECT (TRIG1)', 0x2c1: 'START (TRIG2)', 0x2c2: 'L3 (TRIG3)',
    0x2c3: 'R3 (TRIG4)', 0x2c4: 'FN (TRIG5)', 0x220: 'DPAD CIMA', 0x221: 'DPAD BAIXO', 0x222: 'DPAD ESQ',
    0x223: 'DPAD DIR',
}
# icone de cada botao: (tipo, texto)  -> desenhado por draw_icon()
KEYICONS = {
    0x130: ('face', FACE_LAYOUT[0x130]), 0x131: ('face', FACE_LAYOUT[0x131]),
    0x133: ('face', FACE_LAYOUT[0x133]), 0x134: ('face', FACE_LAYOUT[0x134]),
    0x136: ('pill', 'L1'), 0x137: ('pill', 'R1'), 0x138: ('pill', 'L2'), 0x139: ('pill', 'R2'),
    0x13a: ('pill', 'SELECT'), 0x13b: ('pill', 'START'), 0x13c: ('pill', 'HOTKEY'),
    0x13d: ('stick', 'L3'), 0x13e: ('stick', 'R3'),
    0x2c0: ('pill', 'SELECT'), 0x2c1: ('pill', 'START'), 0x2c2: ('stick', 'L3'),
    0x2c3: ('stick', 'R3'), 0x2c4: ('pill', 'FN'),
    0x220: ('dpad', 'U'), 0x221: ('dpad', 'D'), 0x222: ('dpad', 'L'), 0x223: ('dpad', 'R'),
}
AXNAMES = {0: 'X', 1: 'Y', 2: 'Z', 3: 'RX', 4: 'RY', 5: 'RZ'}
SOUTH, EAST, NORTH, WEST = 0x130, 0x131, 0x133, 0x134
BTN_A = next(c for c, l in FACE_LAYOUT.items() if l == 'A')
BTN_B = next(c for c, l in FACE_LAYOUT.items() if l == 'B')
SELECT, START, L1, R1, L2, R2 = 0x13a, 0x13b, 0x136, 0x137, 0x138, 0x139
NAV_UP = (('K', 0x220), ('H', HAT_Y, -1))
NAV_DOWN = (('K', 0x221), ('H', HAT_Y, 1))
# No R36S, SELECT/START/L3/R3/FN tambem chegam como TRIG1..TRIG5 (BTN_TRIGGER_HAPPY1..5)
TRIG_SELECT, TRIG_START, TRIG_L3, TRIG_R3, TRIG_FN = 0x2c0, 0x2c1, 0x2c2, 0x2c3, 0x2c4
START_ANY, SELECT_ANY = (START, TRIG_START), (SELECT, TRIG_SELECT)
NAV_OK = (('K', SOUTH), ('K', EAST), ('K', START), ('K', TRIG_START))


def ioc_read(nr, size):
    return (2 << 30) | (size << 16) | (ord('E') << 8) | nr


def bits_from(buf):
    return {i * 8 + b for i, byte in enumerate(buf) for b in range(8) if (byte >> b) & 1}


def get_bits(fd, ev, nbytes):
    buf = bytearray(nbytes)
    try:
        fcntl.ioctl(fd, ioc_read(0x20 + ev, nbytes), buf)
    except OSError:
        return set()
    return bits_from(buf)


def get_name(fd):
    buf = bytearray(256)
    try:
        fcntl.ioctl(fd, ioc_read(0x06, 256), buf)
        return bytes(buf).split(b'\0')[0].decode('utf-8', 'replace')
    except OSError:
        return '?'


def get_absinfo(fd, code):
    buf = bytearray(24)
    try:
        fcntl.ioctl(fd, ioc_read(0x40 + code, 24), buf)
        return struct.unpack('6i', bytes(buf))
    except OSError:
        return None


def keys_down(fd):
    buf = bytearray(96)
    try:
        fcntl.ioctl(fd, ioc_read(0x18, 96), buf)
    except OSError:
        return set()
    return bits_from(buf)


def key_icon(code):
    if code in KEYICONS:
        return KEYICONS[code]
    return ('pill', key_label(code)[:9])


def key_label(code):
    if code in KEYNAMES:
        return KEYNAMES[code]
    if 0x2c0 <= code < 0x2e0:
        return 'TRIG%d' % (code - 0x2c0 + 1)
    return 'BTN %x' % code


class Btn:
    def __init__(self, label, order, icon=None):
        self.label, self.order = label, order
        self.icon = icon or ('pill', label[:9])
        self.down = False
        self.down_since = 0.0
        self.last_up = 0.0
        self.presses = 0
        self.releases = 0
        self.chatter = 0

    def press(self, now):
        if self.down:
            return
        if self.last_up and now - self.last_up < 0.025:
            self.chatter += 1
        self.down, self.down_since = True, now
        self.presses += 1

    def release(self, now):
        if not self.down:
            return
        if now - self.down_since < 0.012:
            self.chatter += 1
        self.down, self.last_up = False, now
        self.releases += 1

    def status(self, now):
        if self.down and now - self.down_since > 4.0:
            return 'PRESO'
        if self.chatter:
            return 'CHATTER'
        if self.presses == 0 and self.releases == 0:
            return 'NÃO TESTADO'
        return 'OK'


class Axis:
    def __init__(self, code, info):
        val, mn, mx = info[0], info[1], info[2]
        self.code, self.min, self.max = code, mn, mx
        self.center = (mn + mx) / 2.0
        self.half = max((mx - mn) / 2.0, 1.0)
        self.val = self.start = val
        self.reset(time.time(), initial=True)

    def reset(self, now, initial=False):
        self.lo = self.hi = self.val
        self.stable_since = now
        self.sectors = set()
        self.spikes = 0
        self.cand = None
        self.minabs = None
        self.rest = None
        if initial:
            self.drift = abs(self.norm(self.val)) > 0.10 and self.half > 3
            self.drift_val = self.norm(self.val) if self.drift else 0.0
        else:
            self.drift, self.drift_val = False, 0.0

    def norm(self, v):
        return max(-1.0, min(1.0, (v - self.center) / self.half))

    def update(self, v, now):
        h = self.half
        d = v - self.val
        if abs(d) > 0.02 * h:
            self.stable_since = now
        # pico de leitura: salto grande que volta logo ao valor anterior
        if self.cand and now - self.cand[1] < 0.05 and abs(v - self.cand[0]) < 0.15 * h \
                and abs(self.val - self.cand[0]) > 0.35 * h:
            self.spikes += 1
            self.cand = None
        elif abs(d) > 0.35 * h:
            self.cand = (self.val, now)
        else:
            self.cand = None
        a = abs(v - self.center) / h
        if a > 0.002 and (self.minabs is None or a < self.minabs):
            self.minabs = a
        self.val = v
        self.lo, self.hi = min(self.lo, v), max(self.hi, v)

    def check_drift(self, now):
        n = abs(self.norm(self.val))
        if now - self.stable_since > 1.5 and 0.10 < n < 0.5:
            self.drift, self.drift_val = True, self.norm(self.val)

    def name(self):
        return 'EIXO ' + AXNAMES.get(self.code, str(self.code))

    def status(self):
        if self.rest:
            m, j = self.rest
            if abs(m) > 0.10:
                return 'DERIVA'
            if j > 0.06:
                return 'MEXENDO SOZINHO'
        if self.spikes >= 2:
            return 'LEITURA INSTÁVEL'
        if self.drift:
            return 'DERIVA'
        span = (self.hi - self.lo) / (2.0 * self.half)
        if span < 0.10:
            return 'NÃO TESTADO'
        lo_n, hi_n = self.norm(self.lo), self.norm(self.hi)
        if lo_n > -0.7 or hi_n < 0.7:
            return 'SEM ALCANCE'
        return 'OK'


class State:
    def __init__(self, devs):
        self.devs = devs
        self.btns, self.axes, self.hat_prev = {}, {}, {}
        self.screen = 'splash'
        self.t_screen = time.time()
        self.menu_idx = 0
        self.nav = []
        self.stick_latch = False
        self.combo_latch = False
        self.last_key = '-'
        self.report_saved = None
        self.rest_t0 = None
        self.rest_samples = {}
        self.maxr = {}
        for d in devs:
            for c in sorted(d['keys']):
                self.btns[('K', c)] = Btn(key_label(c), c, key_icon(c))
            for c, info in d['abs'].items():
                if c in (HAT_X, HAT_Y):
                    neg, pos = (('ESQ', 'DIR') if c == HAT_X else ('CIMA', 'BAIXO'))
                    ineg, ipos = (('L', 'R') if c == HAT_X else ('U', 'D'))
                    self.btns[('H', c, -1)] = Btn('HAT ' + neg, 0x400 + c * 2, ('dpad', ineg))
                    self.btns[('H', c, 1)] = Btn('HAT ' + pos, 0x400 + c * 2 + 1, ('dpad', ipos))
                    self.hat_prev[c] = 0
                else:
                    self.axes[c] = Axis(c, info)
            for c in d['down']:
                b = self.btns.get(('K', c))
                if b:
                    b.down, b.down_since = True, time.time()

    # ---- eventos ----
    def handle(self, typ, code, val, now):
        if typ == EV_KEY and val in (0, 1):
            b = self.btns.get(('K', code))
            if b:
                if val:
                    if not b.down:
                        self.nav.append(('K', code))
                        self.last_key = '%s (0x%x) apertado' % (b.label, code)
                    b.press(now)
                else:
                    b.release(now)
        elif typ == EV_ABS:
            if code in self.hat_prev:
                prev = self.hat_prev[code]
                if prev != val:
                    if prev:
                        self.btns[('H', code, prev)].release(now)
                    if val:
                        self.nav.append(('H', code, val))
                        self.btns[('H', code, val)].press(now)
                        self.last_key = 'HAT 0x%x = %d' % (code, val)
                    self.hat_prev[code] = val
            elif code in self.axes:
                self.axes[code].update(val, now)
        self.update_sectors()

    def sticks(self):
        codes = sorted(self.axes)
        return [(self.axes[codes[i]], self.axes[codes[i + 1]]) for i in range(0, len(codes) - 1, 2)]

    def update_sectors(self):
        for i, (ax, ay) in enumerate(self.sticks()):
            x, y = ax.norm(ax.val), ay.norm(ay.val)
            r = math.hypot(x, y)
            if r > 0.3:
                sec = int(((math.atan2(y, x) + math.pi) / (2 * math.pi)) * 16) % 16
                m = self.maxr.setdefault(i, {})
                m[sec] = max(m.get(sec, 0.0), r)
                if r > 0.55:
                    ax.sectors.add(sec)

    def stick_reach(self, i):
        m = self.maxr.get(i)
        if not m or len(m) < 8:
            return None
        return sum(min(v, 1.0) for v in m.values()) / len(m)

    def tick(self, now):
        for ax in self.axes.values():
            ax.check_drift(now)
        if self.rest_t0 is not None:
            el = now - self.rest_t0
            if el > 0.8:
                for c, ax in self.axes.items():
                    self.rest_samples.setdefault(c, []).append(ax.norm(ax.val))
            if el >= 5.0:
                for c, ax in self.axes.items():
                    s = self.rest_samples.get(c) or [ax.norm(ax.val)]
                    ax.rest = (sum(s) / len(s), max(s) - min(s))
                self.rest_t0, self.rest_samples = None, {}

    def start_rest(self, now):
        self.rest_t0, self.rest_samples = now, {}

    def reset_axes(self, now):
        for ax in self.axes.values():
            ax.reset(now)
        self.maxr, self.rest_t0 = {}, None

    def held(self, groups, secs, now):
        """groups: codigos (ou tuplas de codigos equivalentes) que devem estar apertados juntos."""
        ts = []
        for g in groups:
            g = g if isinstance(g, tuple) else (g,)
            down = [b for b in (self.btns.get(('K', c)) for c in g) if b and b.down]
            if not down:
                return False
            ts.append(min(b.down_since for b in down))
        return now - max(ts) >= secs

    # ---- relatorio ----
    def axis_lines(self):
        out = []
        for c in sorted(self.axes):
            ax = self.axes[c]
            extra = 'min=%d max=%d centro_inicial=%d' % (ax.lo, ax.hi, ax.start)
            if ax.rest:
                extra += ' repouso: desvio=%+.0f%% oscilação=%.0f%%' % (ax.rest[0] * 100, ax.rest[1] * 100)
            if ax.drift:
                extra += ' desvio=%+.0f%%' % (ax.drift_val * 100)
            if ax.spikes:
                extra += ' picos=%d' % ax.spikes
            if ax.minabs is not None:
                extra += ' zona_morta~%.1f%%' % (ax.minabs * 100)
            out.append((ax.name(), ax.status(), extra))
        for i, (ax, ay) in enumerate(self.sticks()):
            cov = len(ax.sectors)
            st = 'OK' if cov >= 13 else ('NÃO TESTADO' if cov == 0 else 'COBERTURA PARCIAL')
            rc = self.stick_reach(i)
            out.append(('STICK %d CÍRCULO' % (i + 1), st,
                        'setores=%d/16 alcance=%s' % (cov, '%.0f%%' % (rc * 100) if rc else '--')))
        return out

    def button_lines(self, now):
        return [(b.label, b.status(now), 'apertos=%d chatter=%d' % (b.presses, b.chatter))
                for b in sorted(self.btns.values(), key=lambda b: b.order)]

    def lines(self, now):
        return self.button_lines(now) + self.axis_lines()

    def stick_diff(self):
        a, b = self.stick_reach(0), self.stick_reach(1)
        if a is None or b is None:
            return None
        return abs(a - b)

    def report_text(self, now):
        al, bl = self.axis_lines(), self.button_lines(now)
        bad = [l for l in al + bl if l[1] != 'OK']
        t = ['R36S ANALOG TESTER - RELATÓRIO', time.strftime('%Y-%m-%d %H:%M:%S'), '',
             'Dispositivos: ' + ', '.join(d['name'] for d in self.devs), '']
        t.append('PROBLEMAS / PENDÊNCIAS: %d' % len(bad) if bad else 'Nenhuma falha detectada.')
        for n, s, e in bad:
            t.append('  [!] %-18s %-20s %s' % (n, s, e))
        d = self.stick_diff()
        if d is not None:
            t += ['', 'Diferença de alcance entre os analógicos: %.0f%%' % (d * 100)]
        t += ['', 'ANALÓGICOS:'] + ['  %-18s %-20s %s' % l for l in al]
        t += ['', 'BOTÕES:'] + ['  %-18s %-20s %s' % l for l in bl]
        return '\n'.join(t) + '\n'

    def save_report(self, now):
        path = os.path.join(os.environ.get('REPORT_DIR', '/tmp'), 'relatorio_controles.txt')
        try:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(self.report_text(now))
            self.report_saved = path
        except OSError:
            self.report_saved = None


def open_devices():
    devs = []
    for path in sorted(glob.glob('/dev/input/event*')):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        name = get_name(fd)
        kb = get_bits(fd, EV_KEY, 96)
        keys = {c for c in kb if 0x120 <= c < 0x140 or 0x220 <= c < 0x300}
        ab = get_bits(fd, EV_ABS, 8)
        lname = name.lower()
        looks_pad = any(w in lname for w in ('joy', 'pad', 'controller', 'adc', 'gamepad'))
        if not keys and not looks_pad:
            os.close(fd)
            continue
        absd = {}
        for c in ab:
            if c <= 5 or c in (HAT_X, HAT_Y):
                info = get_absinfo(fd, c)
                if info:
                    absd[c] = info
        if not keys and not absd:
            os.close(fd)
            continue
        devs.append({'fd': fd, 'name': name, 'keys': keys, 'abs': absd,
                     'down': keys_down(fd) & keys})
    return devs


def pump(state, devs, timeout):
    fds = [d['fd'] for d in devs]
    r, _, _ = select.select(fds, [], [], timeout)
    now = time.time()
    for fd in r:
        try:
            data = os.read(fd, SZ * 64)
        except OSError:
            continue
        for i in range(0, len(data) - SZ + 1, SZ):
            _, _, typ, code, val = struct.unpack(FMT, data[i:i + SZ])
            state.handle(typ, code, val, now)
    state.tick(now)
    return now


MENU_ITEMS = ['Testar analógicos', 'Testar botões', 'Sair (Exit)']


def go(state, screen, now):
    state.screen, state.t_screen = screen, now
    state.nav = []
    state.combo_latch = True  # exige soltar os botoes antes de aceitar novo atalho


def logic_step(state, now):
    """Retorna True para encerrar o programa."""
    nav, state.nav = state.nav, []
    both_down = state.held((START_ANY, SELECT_ANY), 0, now)
    l1r1_down = all(state.btns.get(('K', c)) and state.btns[('K', c)].down for c in (L1, R1))
    if not (both_down or l1r1_down):
        state.combo_latch = False
    both = state.held((START_ANY, SELECT_ANY), 0.3, now) and not state.combo_latch
    back = both or (state.held((L1, R1), 1.0, now) and not state.combo_latch)

    if state.screen == 'splash':
        if nav or now - state.t_screen > 20:
            go(state, 'menu', now)
    elif state.screen == 'menu':
        if both:
            return True
        sticks = state.sticks()
        if sticks:
            y = sticks[0][1].norm(sticks[0][1].val)
            if abs(y) < 0.3:
                state.stick_latch = False
            elif abs(y) > 0.6 and not state.stick_latch:
                state.stick_latch = True
                nav.append(('H', HAT_Y, -1 if y < 0 else 1))
        for k in nav:
            if k in NAV_UP:
                state.menu_idx = (state.menu_idx - 1) % len(MENU_ITEMS)
            elif k in NAV_DOWN:
                state.menu_idx = (state.menu_idx + 1) % len(MENU_ITEMS)
            elif k in NAV_OK:
                if state.menu_idx == 2:
                    return True
                go(state, ('analog', 'buttons')[state.menu_idx], now)
                break
    else:
        if back:
            state.save_report(now)
            go(state, 'menu', now)
        elif state.screen == 'analog':
            for k in nav:
                if k == ('K', BTN_A) and state.rest_t0 is None:
                    state.start_rest(now)  # botao A: teste de repouso
                elif k == ('K', BTN_B):
                    state.reset_axes(now)  # botao B: zerar medicoes
    return False


# ------------------------------------------------------------ interface grafica
# Renderizador em software (sem dependencias) -> pygame ou /dev/fb0 direto.
FONT = bytes.fromhex('000000000000000000000000000000000010101010101000101000000000006c6c6c00000000000000000000000016347e2c2cfe48580000000000103c7470381c145c3c101000000060d0d066184c1a1a0c0000000000386060707adace6c7e000000000010101000000000000000000000081810303030303010180800000030301018181818181030300000000010543c3c541000000000000000000000101010fe10101000000000000000000000000018183030000000000000003c3c000000000000000000000000000000181800000000000404080818103020604000000000386c64667666646c38000000000078181818181818187e0000000000384c0c0c1c1830607c0000000000384c0c0c380c044c7800000000000c1c3c2c6c4c7e0c0c00000000007c6060780c04044c3800000000003c64607c6c66666c3800000000007c0c0c1c18183030300000000000386c646c386c446c3c0000000000386c4c4c6e3c044c380000000000000000181800001818000000000000000018180000181830300000000000061c70701c0600000000000000000000fe00fe000000000000000000c0781e0e78c00000000000003c4c0c1810100010100000000000003c66deb6b2b2f6de603c0000003838382c6c7c4446c600000000007c4c464c7c4646467c00000000001c306060606060301c0000000000786c66666666666c7800000000007e6060607c6060607e00000000007e6060607c6060606000000000003c606060606e66663c0000000000646464647c6464646400000000007c181818181818187c00000000003c0c0c0c0c0c0c0c780000000000464c787878784c4c46000000000060606060606060607e0000000000eeeeeefeded6c6c6c6000000000066667676565e4e4e4e0000000000386c6646c646666c3800000000007c6666667c606060600000000000386c6646c646666c3c0c000000007c6c646c786c6c66660000000000386460703c0c064c380000000000fe18181818181818180000000000464646464646466c3c0000000000c646646c6c2c3838380000000000c2c2d6defe6e6e6c6c0000000000c66c3c3818387c6cc60000000000c6646c3c381818181800000000007e0e0c1c383070607e000000003c3030303030303030303c0000000040602030101808080c04000000381818181818181818183800000000383c460000000000000000000000000000000000000000ffff000020100000000000000000000000000000007c04067e666e7e000000006060607c6c6666666c7c000000000000003c60606060603c000000000404043c6c4cc44c6c3c00000000000000386c467e40603c000000001c18107c101010101010000000000000003c6c4444446c3c044c00006060607c6c6464646464000000001818007818181818187e0000000018180078181818181818181800006060606c7c78786c6c6600000000f030303030303030301c00000000000000fcd6d6d6d6d6d6000000000000007c6c646464646400000000000000386c4646466c38000000000000007c6c6666666c7c606000000000003c6c4cc44c6c3c040400000000003e303020202020000000000000003864603c0c4c3c000000000030307c30303030301c000000000000006c6c6c6c6c6c7c0000000000000046646c6c38383800000000000000c2c2d65e7e6c6c000000000000006c6c3818386c6600000000000000c6646c2c3c3818183000000000007c0c1c3830607c000000001c1818103070301018181c000000101010101010101010101010000070101010181c1810101070000000000000000000721c000000000000000000000000000000000000000000000010100010101010101000000008083c6c6868686c3c08080000001c3030307c3030307e00000000000000447c24247c44000000000000c66c6cfe38fe181818000000000000101010100000101010100000003c6030786c643c1c0c78000000002c00000000000000000000000000003846baa2ba4638000000000000380c3c6c3c003c00000000000000000000046c586c0400000000000000000000fe0606000000000000000000000000000000000000000000003846babaaa46380000000000003c00000000000000000000000000382c2c380000000000000000000000001010fe101000fe0000000000380818303c0000000000000000003808180c3800000000000000000c1800000000000000000000000000000064646464646c7e60600000007c74f4747414141414140000000000000000181800000000000000000000000000000000000838000000301010103c000000000000000000382c242c38003c00000000000000000000486c366c480000000000e0202020fe38cc0c143e04000000e0202020fe38fc0604181e000000f0107010f638cc0c143e040000000000001818001818303060640030103838382c6c7c4446c600000008103838382c6c7c4446c6000000382c3838382c6c7c4446c600000034383838382c6c7c4446c60000002c003838382c6c7c4446c600000038283838382c6c7c4446c600000000003e3868684e7848c8ce00000000001c306060606060301c08180030107e6060607c6060607e00000008187e6060607c6060607e000000382c7e6060607c6060607e0000002c007e6060607c6060607e00000030107c181818181818187c00000008107c181818181818187c000000382c7c181818181818187c0000002c007c181818181818187c0000000000786c6666f666666c78000000343866667676565e4e4e4e0000003010386c6646c646666c380000000810386c6646c646666c38000000382c386c6646c646666c380000003438386c6646c646666c380000002c00386c6646c646666c3800000000000000446c38386c440000000000003e6c6e5ef676646cf80000003010464646464646466c3c0000000810464646464646466c3c000000382c464646464646466c3c0000002c00464646464646466c3c0000000810c6646c3c38181818180000000000607c6666667c60606000000000386c6c7878786c66667c000000002010007c04067e666e7e000000000c18007c04067e666e7e00000000382c007c04067e666e7e000000000034387c04067e666e7e00000000002c007c04067e666e7e000000003828387c04067e666e7e00000000000000fc1e127ed0da6e000000000000003c60606060603c08180000301000386c467e40603c000000000c1800386c467e40603c00000000182c00386c467e40603c00000000002c00386c467e40603c000000002010007818181818187e000000000c18007818181818187e00000000382c007818181818187e00000000002c007818181818187e000000003438780c3c6446466c38000000000034387c6c646464646400000000201000386c4646466c38000000000c1800386c4646466c3800000000382c00386c4646466c3800000000003438386c4646466c3800000000002c00386c4646466c3800000000000000181800fe001818000000000000003e6c5e76766c78000000002010006c6c6c6c6c6c7c000000000c18006c6c6c6c6c6c7c00000000382c006c6c6c6c6c6c7c00000000002c006c6c6c6c6c6c7c000000000c1800c6646c2c3c3818183000006060607c6c6666666c7c60600000002c00c6646c2c3c3818183000000000003c3c3c3c0000000000')
BG, PANEL = (16, 18, 26), (36, 40, 54)
GREY, GREEN, DGREEN = (70, 74, 90), (60, 210, 100), (30, 110, 60)
YELLOW, RED, ORANGE, WHITE = (235, 195, 40), (230, 60, 60), (240, 140, 40), (235, 235, 240)
DIM, BLUE = (150, 154, 170), (70, 130, 230)
STATUS_COL = {'OK': DGREEN, 'NÃO TESTADO': GREY, 'CHATTER': YELLOW, 'PRESO': RED,
              'DERIVA': ORANGE, 'SEM ALCANCE': ORANGE, 'COBERTURA PARCIAL': YELLOW,
              'MEXENDO SOZINHO': RED, 'LEITURA INSTÁVEL': YELLOW}
BAD = ('CHATTER', 'PRESO', 'DERIVA', 'SEM ALCANCE', 'MEXENDO SOZINHO', 'LEITURA INSTÁVEL')
BPP = {'rgb': 3, 'bgra': 4, 'rgba': 4, 'rgb565': 2}


def glyph_index(ch):
    o = ord(ch)
    if 32 <= o <= 126:
        return o - 32
    if 160 <= o <= 255:
        return 95 + o - 160
    if o == 0x2022:
        return 191
    return 31


def wrap(s, n):
    lines, cur = [], ''
    for w in s.split():
        if len(cur) + len(w) + (1 if cur else 0) > n:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + ' ' + w) if cur else w
    return lines + ([cur] if cur else [])


# ---- fonte moderna (Poppins / Inter, licenca OFL) pre-renderizada em fonte_menu.bin
FONT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonte_menu.bin')
_FONTS = None


def load_fonts():
    """Carrega os glifos suavizados (anti-aliasing). Se faltar o arquivo, o app usa a fonte antiga."""
    global _FONTS
    if _FONTS is not None:
        return _FONTS
    _FONTS = {}
    try:
        with open(FONT_FILE, 'rb') as fh:
            d = zlib.decompress(fh.read())
        o = 1
        for _ in range(d[0]):
            n = d[o]
            name = d[o + 1:o + 1 + n].decode()
            o += 1 + n
            asc, desc, cap, ng = struct.unpack_from('<BBBH', d, o)
            o += 5
            gl = {}
            for _ in range(ng):
                cp, adv, ox, oy, w, h = struct.unpack_from('<HHbbBB', d, o)
                o += 8
                gl[chr(cp)] = (adv / 16.0, ox, oy, w, h, d[o:o + w * h])
                o += w * h
            _FONTS[name] = {'asc': asc, 'desc': desc, 'cap': cap, 'g': gl}
    except Exception as e:  # noqa
        sys.stderr.write('fonte moderna indisponivel: %r\n' % (e,))
        _FONTS = {}
    return _FONTS


UI_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ui_imagens.bin')
UI_X, UI_Y = 56, 42          # onde a ilustracao do R36S fica na tela (640x480)
_UI = None
# estilos de destaque: (cor do preenchimento, opacidade, cor do anel, opacidade)
STY = {'press': ((60, 210, 100), 0.55, (170, 255, 195), 1.0),
       'ok': (None, 0, (60, 210, 100), 0.95),
       'pend': (None, 0, (240, 140, 40), 0.95),
       'chat': ((235, 195, 40), 0.40, (255, 235, 140), 1.0),
       'stuck': ((230, 60, 60), 0.60, (255, 140, 140), 1.0)}


def load_ui():
    """Ilustracao do R36S + mascaras de destaque + tampas dos analogicos. None se faltar o arquivo."""
    global _UI
    if _UI is None:
        try:
            with open(UI_FILE, 'rb') as fh:
                d = zlib.decompress(fh.read())
            W, H = struct.unpack_from('<HH', d, 0)
            o = 4
            rgb = d[o:o + W * H * 3]
            o += W * H * 3
            slots = {}
            n = d[o]
            o += 1
            for _ in range(n):
                ln = d[o]
                name = d[o + 1:o + 1 + ln].decode()
                o += 1 + ln
                ox, oy, w, h = struct.unpack_from('<HHHH', d, o)
                o += 8
                fm, rm = d[o:o + w * h], d[o + w * h:o + 2 * w * h]
                o += 2 * w * h
                slots[name] = (ox, oy, w, h, [(i, a / 255.0) for i, a in enumerate(fm) if a],
                               [(i, a / 255.0) for i, a in enumerate(rm) if a])
            caps = []
            nc = d[o]
            o += 1
            for _ in range(nc):
                w, h = struct.unpack_from('<HH', d, o)
                o += 4
                crgb = d[o:o + w * h * 3]
                o += w * h * 3
                caps.append((w, h, crgb, d[o:o + w * h]))
                o += w * h
            _UI = {'console': (W, H, rgb), 'slots': slots, 'caps': caps}
        except Exception as e:  # noqa
            sys.stderr.write('imagens da interface indisponiveis: %r\n' % (e,))
            _UI = {}
    return _UI or None


LOGO_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logo_menu.bin')
_LOGO = None


def load_logo():
    """Logo do menu (RGB ja composta sobre o fundo BG). None se o arquivo faltar."""
    global _LOGO
    if _LOGO is None:
        try:
            with open(LOGO_FILE, 'rb') as fh:
                d = zlib.decompress(fh.read())
            w, h = struct.unpack_from('<HH', d, 0)
            _LOGO = (w, h, d[4:4 + w * h * 3])
        except Exception as e:  # noqa
            sys.stderr.write('logo indisponivel: %r\n' % (e,))
            _LOGO = ()
    return _LOGO


class Soft:
    def __init__(self, w, h, fmt):
        self.w, self.h, self.fmt, self.bpp = w, h, fmt, BPP[fmt]
        self.buf = bytearray(w * h * self.bpp)
        self._px, self._glyph, self._spr, self._ui = {}, {}, {}, {}

    def px(self, col):
        p = self._px.get(col)
        if p is None:
            r, g, b = col
            if self.fmt == 'rgb':
                p = bytes((r, g, b))
            elif self.fmt == 'bgra':
                p = bytes((b, g, r, 255))
            elif self.fmt == 'rgba':
                p = bytes((r, g, b, 255))
            else:
                p = (((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)).to_bytes(2, 'little')
            self._px[col] = p
        return p

    def fill(self, col):
        self.buf[:] = self.px(col) * (self.w * self.h)

    def hspan(self, x0, x1, y, p):
        if y < 0 or y >= self.h:
            return
        x0, x1 = max(x0, 0), min(x1, self.w - 1)
        if x1 < x0:
            return
        o = (y * self.w + x0) * self.bpp
        n = x1 - x0 + 1
        self.buf[o:o + n * self.bpp] = p * n

    def rect(self, x, y, w, h, col, border=0):
        p = self.px(col)
        if border:
            for k in range(border):
                self.hspan(x, x + w - 1, y + k, p)
                self.hspan(x, x + w - 1, y + h - 1 - k, p)
            for yy in range(y + border, y + h - border):
                self.hspan(x, x + border - 1, yy, p)
                self.hspan(x + w - border, x + w - 1, yy, p)
        else:
            for yy in range(y, y + h):
                self.hspan(x, x + w - 1, yy, p)

    def circle(self, cx, cy, r, col, width=0):
        p = self.px(col)
        ri = r - width
        for dy in range(-r, r + 1):
            ho = int(math.sqrt(r * r - dy * dy) + 0.5)
            if width == 0 or ri <= 0 or abs(dy) >= ri:
                self.hspan(cx - ho, cx + ho, cy + dy, p)
            else:
                hi = int(math.sqrt(ri * ri - dy * dy) + 0.5)
                self.hspan(cx - ho, cx - hi, cy + dy, p)
                self.hspan(cx + hi, cx + ho, cy + dy, p)

    def line(self, x0, y0, x1, y1, col):  # so horizontal/vertical
        p = self.px(col)
        if y0 == y1:
            self.hspan(min(x0, x1), max(x0, x1), y0, p)
        else:
            for y in range(min(y0, y1), max(y0, y1) + 1):
                self.hspan(x0, x0, y, p)

    def _runs(self, ch, scale):
        key = (ch, scale)
        runs = self._glyph.get(key)
        if runs is None:
            i = glyph_index(ch)
            runs = []
            for row in range(14):
                bits, x = FONT[i * 14 + row], 0
                while x < 8:
                    if (bits >> (7 - x)) & 1:
                        s = x
                        while x < 8 and (bits >> (7 - x)) & 1:
                            x += 1
                        runs.append((s * scale, row * scale, (x - s) * scale))
                    else:
                        x += 1
            self._glyph[key] = runs
        return runs

    def text(self, s, x, y, col, scale=1, center=False):
        if center:
            x -= len(s) * 4 * scale
            y -= 7 * scale
        p = self.px(col)
        for i, ch in enumerate(s):
            if ch == ' ':
                continue
            gx = x + i * 8 * scale
            for dx, dy, ln in self._runs(ch, scale):
                for k in range(scale):
                    self.hspan(gx + dx, gx + dx + ln - 1, y + dy + k, p)


    # ---- formas e texto suavizado ----
    def rrect(self, x, y, w, h, r, col):
        p = self.px(col)
        r = max(0, min(r, w // 2, h // 2))
        for dy in range(h):
            k = min(dy, h - 1 - dy)
            inset = 0
            if k < r:
                d = r - k - 0.5
                inset = int(round(r - math.sqrt(max(r * r - d * d, 0.0))))
            self.hspan(x + inset, x + w - 1 - inset, y + dy, p)

    def logo(self, cx, y):
        """Desenha a logo do menu centrada em cx, topo em y. Retorna False se nao houver logo."""
        lg = load_logo()
        if not lg:
            return False
        w, h, rgb = lg
        rows = self._ui.get('logo')
        if rows is None:
            rows = []
            for r in range(h):
                line = rgb[r * w * 3:(r + 1) * w * 3]
                rows.append(b''.join(self.px((line[i], line[i + 1], line[i + 2])) for i in range(0, w * 3, 3)))
            self._ui['logo'] = rows
        x = cx - w // 2
        for r, rb in enumerate(rows):
            if 0 <= y + r < self.h:
                o = ((y + r) * self.w + x) * self.bpp
                self.buf[o:o + len(rb)] = rb
        return True

    # ---- imagens da interface (ilustracao do R36S, destaques, tampas dos analogicos)
    def conv(self, rgb):
        """bytes RGB (3 por pixel) -> bytes no formato do video."""
        f = self.fmt
        if f == 'rgb':
            return bytes(rgb)
        n = len(rgb) // 3
        if f in ('bgra', 'rgba'):
            o = bytearray(n * 4)
            if f == 'bgra':
                o[0::4], o[2::4] = rgb[2::3], rgb[0::3]
            else:
                o[0::4], o[2::4] = rgb[0::3], rgb[2::3]
            o[1::4], o[3::4] = rgb[1::3], b'\xff' * n
            return bytes(o)
        a = array.array('H', [((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
                              for r, g, b in zip(rgb[0::3], rgb[1::3], rgb[2::3])])
        if sys.byteorder == 'big':
            a.byteswap()
        return a.tobytes()

    def ui_base(self):
        """Quadro de fundo pronto (BG + ilustracao), em cache."""
        b = self._ui.get('base')
        if b is None:
            W, H, rgb = load_ui()['console']
            self.fill(BG)
            cv, rb = self.conv(rgb), W * self.bpp
            for r in range(H):
                o = ((UI_Y + r) * self.w + UI_X) * self.bpp
                self.buf[o:o + rb] = cv[r * rb:(r + 1) * rb]
            b = self._ui['base'] = bytes(self.buf)
        return b

    def ui_patch(self, name, style):
        """Destaque (anel/preenchimento suavizado) sobre o botao `name`, calculado uma vez por estilo."""
        ui = load_ui()
        ox, oy, w, h, fnz, rnz = ui['slots'][name]
        rows = self._ui.get((name, style))
        if rows is None:
            W, H, rgb = ui['console']
            reg = bytearray(w * h * 3)
            for r in range(h):
                sy = oy + r
                if 0 <= sy < H:
                    x0, x1 = max(ox, 0), min(ox + w, W)
                    if x1 > x0:
                        reg[(r * w + x0 - ox) * 3:(r * w + x1 - ox) * 3] = rgb[(sy * W + x0) * 3:(sy * W + x1) * 3]
            fc, fa, rc, ra = STY[style]
            for col, k, nz in ((fc, fa, fnz), (rc, ra, rnz)):
                if col is None or not k:
                    continue
                cr, cg, cb = col
                for i, a in nz:
                    al, o = a * k, i * 3
                    reg[o] = int(reg[o] + (cr - reg[o]) * al)
                    reg[o + 1] = int(reg[o + 1] + (cg - reg[o + 1]) * al)
                    reg[o + 2] = int(reg[o + 2] + (cb - reg[o + 2]) * al)
            cv, rb = self.conv(reg), w * self.bpp
            rows = self._ui[(name, style)] = [cv[r * rb:(r + 1) * rb] for r in range(h)]
        for r, rb_ in enumerate(rows):
            y = UI_Y + oy + r
            if 0 <= y < self.h:
                o = (y * self.w + UI_X + ox) * self.bpp
                self.buf[o:o + len(rb_)] = rb_

    def cap(self, idx, cx, cy):
        """Tampa do analogico (imagem) centrada em (cx, cy). False se nao houver imagem."""
        ui = load_ui()
        if not ui or not ui['caps']:
            return False
        idx %= len(ui['caps'])
        w, h, rgb, al = ui['caps'][idx]
        rows = self._ui.get(('cap', idx))
        if rows is None:
            rows = []
            for r in range(h):
                xs = [x for x in range(w) if al[r * w + x] > 8]
                rows.append((xs[0], self.conv(rgb[(r * w + xs[0]) * 3:(r * w + xs[-1] + 1) * 3])) if xs else None)
            self._ui[('cap', idx)] = rows
        for r, it in enumerate(rows):
            if it:
                x0, b = it
                y, x = cy - h // 2 + r, cx - w // 2 + x0
                if 0 <= y < self.h and x >= 0 and x + len(b) // self.bpp <= self.w:
                    o = (y * self.w + x) * self.bpp
                    self.buf[o:o + len(b)] = b
        return True

    def fwidth(self, s, font):
        f = load_fonts().get(font)
        if not f:
            return len(s) * 8 * (2 if font in ('title', 'item') else 1)
        g = f['g']
        return int(round(sum(g.get(ch, g['?'])[0] for ch in s)))

    def _sprite(self, f, s, col, bg, w):
        sw, sh = w + 2, f['asc'] + f['desc']
        al = bytearray(sw * sh)
        pen, g = 1.0, f['g']
        for ch in s:
            adv, ox, oy, gw, gh, data = g.get(ch, g['?'])
            gx, gy = int(round(pen + ox)), f['asc'] + oy
            for r in range(gh):
                yy = gy + r
                if 0 <= yy < sh:
                    for q in range(gw):
                        xx = gx + q
                        a = data[r * gw + q]
                        if a and 0 <= xx < sw and a > al[yy * sw + xx]:
                            al[yy * sw + xx] = a
            pen += adv
        pal = {}
        rows = []
        for r in range(sh):
            parts = []
            for a in al[r * sw:(r + 1) * sw]:
                q = pal.get(a)
                if q is None:
                    q = pal[a] = self.px(tuple((bg[i] * (255 - a) + col[i] * a) // 255 for i in range(3)))
                parts.append(q)
            rows.append(b''.join(parts))
        return rows, sw, sh

    def ftext(self, s, x, cy, col, font='hint', bg=BG, align='l', dyn=False):
        """Texto com a fonte moderna, centrado verticalmente em cy. bg = cor lisa por tras do texto."""
        f = load_fonts().get(font)
        w = self.fwidth(s, font)
        if align == 'c':
            x -= w // 2
        elif align == 'r':
            x -= w
        if not f:  # fallback: fonte bitmap antiga
            sc = 2 if font in ('title', 'item') else 1
            self.text(s, x, cy - 7 * sc, col, sc)
            return w
        if dyn:  # texto que muda a cada quadro (valores): cache por letra, nao por frase
            base, pen, g = cy + f['cap'] // 2, float(x), f['g']
            for ch in s:
                adv, ox, oy, gw, gh, data = g.get(ch, g['?'])
                if gw and gh:
                    gk = ('d', font, ch, col, bg)
                    rows = self._spr.get(gk)
                    if rows is None:
                        if len(self._spr) > 600:
                            self._spr.clear()
                        pal = {}
                        rows = self._spr[gk] = [b''.join(
                            pal.setdefault(a, self.px(tuple((bg[i] * (255 - a) + col[i] * a) // 255
                                                            for i in range(3))))
                            for a in data[r * gw:(r + 1) * gw]) for r in range(gh)]
                    gx = int(round(pen + ox))
                    if 0 <= gx and gx + gw <= self.w:
                        for r, rb in enumerate(rows):
                            yy = base + oy + r
                            if 0 <= yy < self.h:
                                o = (yy * self.w + gx) * self.bpp
                                self.buf[o:o + len(rb)] = rb
                pen += adv
            return w
        key = (font, s, col, bg)
        spr = self._spr.get(key)
        if spr is None:
            if len(self._spr) > 300:
                self._spr.clear()
            spr = self._spr[key] = self._sprite(f, s, col, bg, w)
        rows, sw, sh = spr
        x0, top = x - 1, cy + f['cap'] // 2 - f['asc']
        if x0 < 0 or x0 + sw > self.w:
            return w
        for i, r in enumerate(rows):
            yy = top + i
            if 0 <= yy < self.h:
                o = (yy * self.w + x0) * self.bpp
                self.buf[o:o + len(r)] = r
        return w


# ------------------------------------------------------------ icones dos botoes fisicos
ICON_BG, ICON_FG, ICON_ACC = (240, 240, 245), (28, 30, 40), BLUE
MUTED = (105, 109, 126)
HINT_ICONS = {'DPAD': ('dpad', None), 'STICK': ('stick_move', ''),
              'L1': KEYICONS[L1], 'R1': KEYICONS[R1], 'START': KEYICONS[START],
              'SELECT': KEYICONS[SELECT]}
for _code, _letter in FACE_LAYOUT.items():
    HINT_ICONS[_letter] = KEYICONS[_code]


def icon_width(spec, h):
    kind, t = spec
    return max(h, len(t) * 8 + 14) if kind == 'pill' else h


def draw_icon(c, spec, x, y, h, active=None):
    """Desenha o icone do botao fisico em (x, y) com altura h. Retorna a largura."""
    kind, t = spec
    w = icon_width(spec, h)
    r = h // 2
    cx, cy = x + r, y + r
    sc = 2 if h >= 30 else 1
    if kind == 'face':  # circulo com a letra impressa no botao
        c.circle(cx, cy, r, ICON_BG)
        c.text(t, cx, cy + sc, ICON_FG, sc, True)
    elif kind == 'pill':  # ombros, START, SELECT...
        c.rrect(x, y, w, h, min(r, 8), ICON_BG)
        c.text(t, x + w // 2, y + h // 2 + 1, ICON_FG, 1, True)
    elif kind == 'stick':  # L3 / R3
        c.circle(cx, cy, r, ICON_BG)
        c.circle(cx, cy, r, ICON_FG, 1)
        c.text(t, cx, cy + 1, ICON_FG, 1, True)
    elif kind == 'stick_move':  # analogico
        c.circle(cx, cy, r, ICON_BG)
        c.circle(cx, cy, max(r - 3, 3), ICON_FG, 1)
        c.circle(cx, cy, max(r // 3, 2), ICON_FG)
    elif kind == 'dpad':  # cruz direcional, braco ativo em azul
        th = max(h // 3, 2)
        S = 3 * th
        x0, y0 = x + (h - S) // 2, y + (h - S) // 2
        c.rect(x0 - 1, y0 + th - 1, S + 2, th + 2, ICON_FG)
        c.rect(x0 + th - 1, y0 - 1, th + 2, S + 2, ICON_FG)
        c.rect(x0, y0 + th, S, th, ICON_BG)
        c.rect(x0 + th, y0, th, S, ICON_BG)
        arm = {'U': (x0 + th, y0, th, th), 'D': (x0 + th, y0 + 2 * th, th, th),
               'L': (x0, y0 + th, th, th), 'R': (x0 + 2 * th, y0 + th, th, th)}.get(t)
        if arm:
            c.rect(arm[0], arm[1], arm[2], arm[3], ICON_ACC)
    return w


def draw_hint(c, fmt, cx, cy, col=DIM, bg=BG, font='hint', ih=20):
    """Texto centrado com icones inline: 'Pressione {A} para iniciar'."""
    parts = []
    for i, piece in enumerate(re.split(r'\{(\w+)\}', fmt)):
        if i % 2:
            parts.append((True, HINT_ICONS[piece]))
        elif piece:
            parts.append((False, piece))
    total = sum(icon_width(v, ih) if ic else c.fwidth(v, font) for ic, v in parts)
    x = cx - total // 2
    for ic, v in parts:
        if ic:
            x += draw_icon(c, v, x, cy - ih // 2, ih)
        else:
            x += c.ftext(v, x, cy, col, font, bg)


def card(c, x, y, w, h, r, fill, border=None, bw=2):
    if border:
        c.rrect(x, y, w, h, r, border)
        c.rrect(x + bw, y + bw, w - 2 * bw, h - 2 * bw, max(r - bw, 0), fill)
    else:
        c.rrect(x, y, w, h, r, fill)


def draw_gamepad(c, x, y):
    c.rect(x, y + 3, 30, 14, DIM)
    c.rect(x + 3, y, 8, 6, DIM)
    c.rect(x + 19, y, 8, 6, DIM)
    c.rect(x + 5, y + 8, 7, 2, BG)
    c.rect(x + 7, y + 6, 3, 7, BG)
    c.circle(x + 20, y + 10, 2, BG)
    c.circle(x + 25, y + 8, 2, BG)


def draw_splash(c, state, devs, now):
    c.fill(BG)
    c.text('R36S Analog Tester', 320, 22, GREEN, 2, True)
    c.line(20, 42, 620, 42, GREY)
    X, W, y = 24, 74, 52

    def para(s, col=WHITE, x=X, w=W, gap=9):
        nonlocal y
        for ln in wrap(s, w):
            c.text(ln, x, y, col)
            y += 16
        y += gap

    para('Ferramenta desenvolvida para testar e diagnosticar os analógicos do R36S de forma simples e rápida.')
    para('O software permite verificar o funcionamento dos controles, identificar possíveis problemas de leitura, '
         'testar os movimentos dos analógicos e observar se os valores estão respondendo corretamente em todas '
         'as direções.')
    para('Ideal para verificar problemas como:', DIM, gap=3)
    for b in ('Analógico puxando para algum lado (drift)', 'Falhas de leitura', 'Movimentos incompletos',
              'Diferenças entre os dois analógicos', 'Áreas mortas (dead zone)',
              'Resposta irregular dos controles'):
        c.text('•', X + 8, y, GREEN)
        c.text(b, X + 28, y, WHITE)
        y += 16
    y += 8
    c.text('Desenvolvido por LagdoLira', X, y + 2, ORANGE)
    draw_gamepad(c, X + 8 * 27, y - 1)
    y += 26
    para('Uma ferramenta simples, feita para quem quer verificar rapidamente a saúde dos analógicos do seu R36S.',
         DIM)
    c.text('Pressione qualquer botão para continuar', 320, 462, GREEN if int(now * 2) % 2 else DIM, 1, True)


def draw_menu(c, state, devs, now):
    c.fill(BG)
    if not c.logo(320, 8):  # sem logo_menu.bin: titulo em texto
        w1, w2 = c.fwidth('R36S ', 'title'), c.fwidth('Analog Tester', 'title')
        x = 320 - (w1 + w2) // 2
        c.ftext('R36S ', x, 48, GREEN, 'title')
        c.ftext('Analog Tester', x + w1, 48, WHITE, 'title')
        c.ftext('Menu principal', 320, 84, DIM, 'sub', BG, 'c')
    for i, label in enumerate(MENU_ITEMS):
        y = 126 + i * 70
        sel = i == state.menu_idx
        fill = DGREEN if sel else PANEL
        card(c, 100, y, 440, 58, 14, fill, GREEN if sel else GREY, 2 if sel else 1)
        c.ftext(label, 320, y + 29, WHITE if sel else DIM, 'item', fill, 'c')
    draw_hint(c, '{DPAD} ou {STICK} navegar      {A} ou {START} confirmar', 320, 372)
    draw_hint(c, '{START}+{SELECT} sair', 320, 402)
    c.ftext('Controles detectados: %d     Último botão: %s' % (len(devs), state.last_key[:34]),
            320, 438, MUTED, 'hint', BG, 'c')
    c.ftext('Desenvolvido por LagdoLira', 320, 462, ORANGE, 'hint', BG, 'c')


CAPR = 32  # raio da tampa do analogico (imagem)
STICK_NAMES = ('Analógico esquerdo', 'Analógico direito')
ZEBRA = (31, 35, 49)


def draw_stick(c, state, pair, i, cx, cy, rad):
    ax, ay = pair
    x, y = ax.norm(ax.val), ay.norm(ay.val)
    active = abs(x) > 0.1 or abs(y) > 0.1
    c.circle(cx, cy, rad, PANEL)
    c.circle(cx, cy, rad, GREEN if active else GREY, 2)
    for sct in range(16):
        ang = -math.pi + (sct + 0.5) * 2 * math.pi / 16
        col = GREEN if sct in ax.sectors else (80, 56, 56)
        c.circle(cx + int(math.cos(ang) * (rad + 9)), cy + int(math.sin(ang) * (rad + 9)), 3, col)
    r = math.hypot(x, y)
    if r > 1:
        x, y = x / r, y / r
    trav = rad - CAPR - 3
    kx, ky = cx + int(x * trav), cy + int(y * trav)
    if not c.cap(i, kx, ky):  # sem imagem: bolinha
        c.circle(kx, ky, 12, GREEN if active else WHITE)
    c.ftext(STICK_NAMES[i] if i < 2 else 'Analógico %d' % (i + 1), cx, cy - rad - 26, WHITE, 'sub', BG, 'c')
    c.ftext('X %+d%%     Y %+d%%' % (int(ax.norm(ax.val) * 100), int(ay.norm(ay.val) * 100)),
            cx, cy + rad + 27, DIM, 'hint', BG, 'c', dyn=True)


def draw_analog(c, state, devs, now):
    c.fill(BG)
    c.ftext('Teste dos analógicos', 16, 22, WHITE, 'item', BG)
    sticks = state.sticks()
    if not sticks:
        c.ftext('Nenhum analógico detectado.', 320, 150, RED, 'item', BG, 'c')
    for i, pair in enumerate(sticks[:2]):
        draw_stick(c, state, pair, i, 110 + i * 420, 152, 68)
    # painel central: teste de repouso
    card(c, 200, 44, 240, 96, 12, PANEL, GREY, 1)
    c.ftext('Teste de repouso', 320, 62, WHITE, 'strong', PANEL, 'c')
    if state.rest_t0 is not None:
        el = now - state.rest_t0
        c.ftext('Solte os analógicos!', 320, 86, ORANGE, 'sub', PANEL, 'c')
        c.rrect(216, 102, 208, 8, 4, GREY)
        fw = int(208 * min(el / 5.0, 1.0))
        if fw >= 8:
            c.rrect(216, 102, fw, 8, 4, ORANGE)
        c.ftext('Medindo... %ds' % max(0, 5 - int(el)), 320, 125, DIM, 'hint', PANEL, 'c', dyn=True)
    elif any(a.rest for a in state.axes.values()):
        badr = any(a.rest and (abs(a.rest[0]) > 0.10 or a.rest[1] > 0.06) for a in state.axes.values())
        c.ftext('Há problema!' if badr else 'Repouso OK', 320, 84, RED if badr else GREEN, 'sub', PANEL, 'c')
        c.ftext('veja os detalhes na tabela', 320, 104, DIM, 'hint', PANEL, 'c')
        draw_hint(c, '{A} repetir o teste', 320, 124, WHITE, PANEL, 'hint', 18)
    else:
        draw_hint(c, 'Pressione {A} para iniciar', 320, 88, WHITE, PANEL, 'sub', 24)
        c.ftext('Solte os analógicos durante 5 s', 320, 120, DIM, 'hint', PANEL, 'c')
    # alcance medio (centro)
    c.ftext('Alcance médio', 320, 164, DIM, 'hint', BG, 'c')
    parts = []
    for i in range(min(2, len(sticks))):
        rr = state.stick_reach(i)
        parts.append('%s %s' % (('Esq', 'Dir')[i], '%d%%' % int(rr * 100) if rr else '--'))
    c.ftext('   '.join(parts) or '--', 320, 188, WHITE, 'strong', BG, 'c', dyn=True)
    d = state.stick_diff()
    if d is not None:
        c.ftext('Diferença: %d%%' % int(d * 100), 320, 214, ORANGE if d > 0.10 else GREEN, 'sub', BG, 'c', dyn=True)

    # ---- tabela inferior: ocupa toda a parte de baixo, tudo centralizado
    card(c, 12, 258, 616, 178, 16, BODY, BODY_EDGE, 1)
    cols = (('Eixo', 100), ('Atual', 84), ('Mín', 84), ('Máx', 84), ('Zona morta', 100), ('Estado', 156))
    x = 16
    centers = []
    for _, wd in cols:
        centers.append(x + wd // 2)
        x += wd
    for (h, _), cxx in zip(cols, centers):
        c.ftext(h, cxx, 279, DIM, 'hint', BODY, 'c')
    c.rect(26, 293, 588, 1, BODY_EDGE)
    codes = sorted(state.axes)[:6]
    if not codes:
        c.ftext('Sem eixos para mostrar', 320, 360, DIM, 'sub', BODY, 'c')
    rh = min(33, 134 // max(len(codes), 1))
    font = 'strong' if rh >= 30 else 'sub'
    for n, code in enumerate(codes):
        ax = state.axes[code]
        st = ax.status()
        ry = 298 + n * rh
        bgc = ZEBRA if n % 2 == 0 else BODY
        if n % 2 == 0:
            c.rrect(20, ry, 600, rh - 2, 8, ZEBRA)
        zm = '%d%%' % int(ax.minabs * 100) if ax.minabs is not None else '--'
        stxt = 'OK' if st == 'OK' else st.capitalize()
        vals = (ax.name().replace('EIXO ', 'Eixo '), '%+d%%' % int(ax.norm(ax.val) * 100),
                '%+d%%' % int(ax.norm(ax.lo) * 100), '%+d%%' % int(ax.norm(ax.hi) * 100), zm, stxt)
        stc = GREEN if st == 'OK' else (DIM if st == 'NÃO TESTADO' else STATUS_COL.get(st, ORANGE))
        colr = (WHITE, WHITE, DIM, DIM, DIM, stc)
        for (hd, wd), cxx, v, cl in zip(cols, centers, vals, colr):
            f = font if c.fwidth(v, font) <= wd - 8 else 'sub'
            c.ftext(v, cxx, ry + (rh - 2) // 2, cl, f, bgc, 'c', dyn=True)
    draw_hint(c, '{A} teste de repouso      {B} zerar medições', 320, 452, DIM, BG, 'hint', 16)
    draw_hint(c, '{START}+{SELECT} (ou {L1}+{R1} 1s): voltar ao menu', 320, 469, DIM, BG, 'hint', 16)


# ---- layout fisico do R36S (tela de teste dos botoes)
# cada controle: lista de entradas equivalentes (tecla evdev e/ou hat) que o acionam
def _face(letter):
    return [('K', c) for c, l in FACE_LAYOUT.items() if l == letter]


SLOTS = {
    'L1': [('K', L1)], 'R1': [('K', R1)], 'L2': [('K', L2)], 'R2': [('K', R2)],
    'U': [('K', 0x220), ('H', HAT_Y, -1)], 'D': [('K', 0x221), ('H', HAT_Y, 1)],
    'L': [('K', 0x222), ('H', HAT_X, -1)], 'R': [('K', 0x223), ('H', HAT_X, 1)],
    'A': _face('A'), 'B': _face('B'), 'X': _face('X'), 'Y': _face('Y'),
    'SELECT': [('K', SELECT), ('K', TRIG_SELECT)], 'START': [('K', START), ('K', TRIG_START)],
    'L3': [('K', 0x13d), ('K', TRIG_L3)], 'R3': [('K', 0x13e), ('K', TRIG_R3)],
    'FN': [('K', TRIG_FN)],
}
SLOT_KEYS = {k for v in SLOTS.values() for k in v}
BODY, BODY_EDGE, SCREEN = (24, 27, 38), (52, 56, 74), (8, 10, 14)
OFF_FILL, OFF_EDGE, OFF_TXT = (30, 32, 42), (58, 62, 78), (95, 99, 115)


def look(state, keys, now):
    """(preenchimento, borda, cor do texto) de um controle conforme o estado dele."""
    bs = [state.btns[k] for k in keys if k in state.btns]
    if not bs:  # este aparelho nao reporta esse botao
        return OFF_FILL, OFF_EDGE, OFF_TXT
    sts = [b.status(now) for b in bs]
    if 'PRESO' in sts:
        return RED, (255, 140, 140), WHITE
    if any(b.down for b in bs):
        return GREEN, (170, 255, 195), (10, 10, 10)
    if 'CHATTER' in sts:
        return YELLOW, (255, 235, 140), (10, 10, 10)
    if all(x == 'NÃO TESTADO' for x in sts):
        return GREY, ORANGE, WHITE
    return DGREEN, GREEN, WHITE


def sh_pill(c, cx, cy, w, h, st, label):
    fill, edge, tc = st
    card(c, cx - w // 2, cy - h // 2, w, h, h // 2, fill, edge, 2)
    c.ftext(label, cx, cy, tc, 'sub', fill, 'c')


def sh_round(c, cx, cy, r, st, label):
    fill, edge, tc = st
    c.circle(cx, cy, r, edge)
    c.circle(cx, cy, r - 2, fill)
    c.ftext(label, cx, cy, tc, 'strong', fill, 'c')


def sh_arm(c, x, y, w, h, st):
    fill, edge, _ = st
    card(c, x, y, w, h, 7, fill, edge, 2)


def sh_stick(c, cx, cy, pair, st, label):
    fill, edge, tc = st
    c.circle(cx, cy, 40, (14, 16, 22))
    c.circle(cx, cy, 40, BODY_EDGE, 2)
    kx = ky = 0
    if pair:
        kx, ky = int(pair[0].norm(pair[0].val) * 16), int(pair[1].norm(pair[1].val) * 16)
    c.circle(cx + kx, cy + ky, 24, edge)
    c.circle(cx + kx, cy + ky, 22, fill)
    c.ftext(label, cx + kx, cy + ky, tc, 'sub', fill, 'c')


def draw_buttons_basic(c, state, devs, now):
    c.fill(BG)
    c.text('TESTE DOS BOTÕES', 10, 8, WHITE, 2)
    lines = state.button_lines(now)
    bad = sum(1 for l in lines if l[1] in BAD)
    pend = sum(1 for l in lines if l[1] == 'NÃO TESTADO')
    L = lambda n: look(state, SLOTS[n], now)  # noqa: E731

    # ombros (atras do corpo)
    sh_pill(c, 112, 66, 128, 26, L('L2'), 'L2')
    sh_pill(c, 528, 66, 128, 26, L('R2'), 'R2')
    sh_pill(c, 112, 96, 150, 28, L('L1'), 'L1')
    sh_pill(c, 528, 96, 150, 28, L('R1'), 'R1')
    # corpo + tela
    card(c, 14, 110, 612, 296, 48, BODY, BODY_EDGE, 2)
    card(c, 184, 126, 272, 190, 10, SCREEN, BODY_EDGE, 2)
    c.ftext('Falhas: %d' % bad, 320, 148, RED if bad else GREEN, 'strong', SCREEN, 'c')
    c.ftext('Pendentes: %d' % pend, 320, 174, ORANGE if pend else GREEN, 'strong', SCREEN, 'c')
    c.rect(204, 192, 232, 1, BODY_EDGE)
    for i, (f, e, t) in enumerate(((GREEN, (170, 255, 195), 'Apertado agora'), (DGREEN, GREEN, 'Testado OK'),
                                   (YELLOW, (255, 235, 140), 'Chatter (repique)'), (RED, (255, 140, 140), 'Preso'),
                                   (GREY, ORANGE, 'Não testado'))):
        yy = 207 + i * 19
        card(c, 222, yy - 6, 14, 12, 3, f, e, 1)
        c.ftext(t, 246, yy, DIM, 'hint', SCREEN)
    c.ftext('Último: %s' % state.last_key[:24], 320, 303, MUTED, 'hint', SCREEN, 'c')

    # D-pad (esquerda, em cima)
    dx, dy, t = 104, 190, 30
    c.rect(dx - t // 2, dy - t // 2, t, t, (40, 44, 58))
    sh_arm(c, dx - t // 2, dy - t - t // 2 - 4, t, t + 4, L('U'))
    sh_arm(c, dx - t // 2, dy + t // 2, t, t + 4, L('D'))
    sh_arm(c, dx - t - t // 2 - 4, dy - t // 2, t + 4, t, L('L'))
    sh_arm(c, dx + t // 2, dy - t // 2, t + 4, t, L('R'))
    # botoes de acao em losango (direita, em cima): X cima, B baixo, Y esquerda, A direita
    fx, fy, o = 536, 190, 40
    sh_round(c, fx, fy - o, 19, L('X'), 'X')
    sh_round(c, fx, fy + o, 19, L('B'), 'B')
    sh_round(c, fx - o, fy, 19, L('Y'), 'Y')
    sh_round(c, fx + o, fy, 19, L('A'), 'A')
    # analogicos (embaixo dos dois)
    sticks = state.sticks()
    sh_stick(c, 104, 330, sticks[0] if len(sticks) > 0 else None, L('L3'), 'L3')
    sh_stick(c, 536, 330, sticks[1] if len(sticks) > 1 else None, L('R3'), 'R3')
    # SELECT / FN / START embaixo da tela
    sh_pill(c, 252, 346, 76, 26, L('SELECT'), 'SELECT')
    sh_pill(c, 320, 346, 48, 26, L('FN'), 'FN')
    sh_pill(c, 388, 346, 76, 26, L('START'), 'START')

    # botoes extras que nao fazem parte do layout (HOTKEY, BTN C, ...)
    extras = sorted(((k, b) for k, b in state.btns.items() if k not in SLOT_KEYS), key=lambda kb: kb[1].order)
    if extras:
        c.ftext('Outros:', 14, 424, DIM, 'hint', BG)
        x, y = 84, 424
        for k, b in extras[:12]:
            w = max(len(b.label[:12]) * 8 + 18, 40)
            if x + w > 630:
                x, y = 14, y + 26
                if y > 440:
                    break
            fill, edge, tc = look(state, [k], now)
            card(c, x, y - 11, w, 22, 11, fill, edge, 2)
            c.text(b.label[:12], x + w // 2, y + 1, tc, 1, True)
            x += w + 6
    draw_hint(c, 'Aperte todos os botões      {START}+{SELECT} (ou {L1}+{R1} 1s): menu', 320, 466)


SLOT_NAMES = {'U': 'D-PAD CIMA', 'D': 'D-PAD BAIXO', 'L': 'D-PAD ESQUERDA', 'R': 'D-PAD DIREITA',
              'A': 'BOTÃO A', 'B': 'BOTÃO B', 'X': 'BOTÃO X', 'Y': 'BOTÃO Y'}
STICK_SRC = {'L3': (167, 315), 'R3': (407, 315)}  # centro dos analogicos na ilustracao (PNG original)
LEGEND = (('Pendente', ORANGE), ('Testado OK', GREEN), ('Chatter', YELLOW), ('Preso', RED))


def slot_style(state, keys, now):
    bs = [state.btns[k] for k in keys if k in state.btns]
    if not bs:
        return None  # o aparelho nao reporta esse botao
    sts = [b.status(now) for b in bs]
    if 'PRESO' in sts:
        return 'stuck'
    if any(b.down for b in bs):
        return 'press'
    if 'CHATTER' in sts:
        return 'chat'
    return 'pend' if all(x == 'NÃO TESTADO' for x in sts) else 'ok'


def draw_buttons(c, state, devs, now):
    if not load_ui():
        return draw_buttons_basic(c, state, devs, now)
    c.buf[:] = c.ui_base()
    lines = state.button_lines(now)
    bad = sum(1 for l in lines if l[1] in BAD)
    pend = sum(1 for l in lines if l[1] == 'NÃO TESTADO')
    c.ftext('Teste dos botões', 16, 22, WHITE, 'item', BG)
    tp, tf = 'Pendentes: %d' % pend, 'Falhas: %d' % bad
    c.ftext(tp, 624, 22, ORANGE if pend else GREEN, 'sub', BG, 'r', dyn=True)
    c.ftext(tf, 624 - c.fwidth(tp, 'sub') - 22, 22, RED if bad else GREEN, 'sub', BG, 'r', dyn=True)

    pressed = []
    for name, keys in SLOTS.items():
        sty = slot_style(state, keys, now)
        if sty:
            c.ui_patch(name, sty)
            if sty in ('press', 'stuck') and any(state.btns[k].down for k in keys if k in state.btns):
                pressed.append(SLOT_NAMES.get(name, name))
    # posicao dos analogicos (bolinha dentro do aro)
    for idx, nm in enumerate(('L3', 'R3')):
        if idx < len(state.sticks()):
            ax, ay = state.sticks()[idx]
            x, y = ax.norm(ax.val), ay.norm(ay.val)
            r = math.hypot(x, y)
            if r > 1:
                x, y = x / r, y / r
            sx, sy = STICK_SRC[nm]
            kx = UI_X + int((sx - 41) * 1.2 + x * 17)
            ky = UI_Y + int((sy - 68) * 1.2 + y * 17)
            act = r > 0.1
            c.circle(kx, ky, 7, (20, 22, 30))
            c.circle(kx, ky, 5, GREEN if act else (235, 235, 240))
    # botoes que nao existem na ilustracao (HOTKEY, BTN C, ...)
    extras = sorted(((k, b) for k, b in state.btns.items() if k not in SLOT_KEYS), key=lambda kb: kb[1].order)
    for k, b in extras:
        if b.down:
            pressed.append(b.label)
    c.ftext('Pressionando: ' + ' + '.join(pressed) if pressed else 'Aperte os botões do console',
            320, 428, GREEN if pressed else DIM, 'strong', BG, 'c', dyn=True)
    if extras:
        wl = [max(len(b.label[:12]) * 8 + 18, 40) for _, b in extras[:8]]
        x = 320 - (sum(wl) + 6 * (len(wl) - 1)) // 2
        for (k, b), w in zip(extras[:8], wl):
            sty = slot_style(state, [k], now)
            fill, edge = {'press': (GREEN, (170, 255, 195)), 'stuck': (RED, (255, 140, 140)),
                          'chat': (YELLOW, (255, 235, 140)), 'pend': (GREY, ORANGE),
                          'ok': (DGREEN, GREEN)}[sty]
            card(c, x, 438, w, 18, 9, fill, edge, 2)
            c.text(b.label[:12], x + w // 2, 448, (10, 10, 10) if sty in ('press', 'chat') else WHITE, 1, True)
            x += w + 6
    else:
        items = [(t, col) for t, col in LEGEND]
        tw = sum(c.fwidth(t, 'hint') + 22 for t, _ in items) - 12
        x = 320 - tw // 2
        for t, col in items:
            c.circle(x + 5, 448, 5, col)
            x += 16 + c.ftext(t, x + 16, 448, DIM, 'hint', BG) + 6
    draw_hint(c, '{START}+{SELECT} (ou {L1}+{R1} 1s): menu', 320, 468, DIM, BG, 'hint', 16)


def draw(c, state, devs, now):
    {'splash': draw_splash, 'menu': draw_menu, 'analog': draw_analog,
     'buttons': draw_buttons}[state.screen](c, state, devs, now)


def setup_pygame():
    import pygame
    pygame.display.init()
    pygame.mouse.set_visible(False)
    try:
        screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
    except pygame.error:
        screen = pygame.display.set_mode((640, 480))
    sw, sh = screen.get_size()
    soft = Soft(640, 480, 'rgb')

    def present():
        pygame.event.pump()
        img = pygame.image.frombuffer(soft.buf, (640, 480), 'RGB')
        if (sw, sh) == (640, 480):
            screen.blit(img, (0, 0))
        else:
            screen.fill((0, 0, 0))
            k = min(sw / 640.0, sh / 480.0)
            sc = pygame.transform.smoothscale(img, (int(640 * k), int(480 * k)))
            screen.blit(sc, ((sw - sc.get_width()) // 2, (sh - sc.get_height()) // 2))
        pygame.display.flip()

    return soft, present, pygame.quit


def setup_fb():
    fd = os.open('/dev/fb0', os.O_RDWR)
    buf = bytearray(160)
    fcntl.ioctl(fd, 0x4600, buf)  # FBIOGET_VSCREENINFO
    xres, yres, _, _, _, _, bpp = struct.unpack('7I', bytes(buf[:28]))
    red_off = struct.unpack('I', bytes(buf[32:36]))[0]
    if xres < 640 or yres < 480:
        os.close(fd)
        raise RuntimeError('framebuffer %dx%d menor que 640x480' % (xres, yres))
    fmt = {32: 'rgba' if red_off == 0 else 'bgra', 16: 'rgb565', 24: 'rgb'}.get(bpp)
    if not fmt:
        os.close(fd)
        raise RuntimeError('framebuffer com %d bpp nao suportado' % bpp)
    try:
        stride = int(open('/sys/class/graphics/fb0/stride').read())
    except (OSError, ValueError):
        stride = xres * bpp // 8
    soft = Soft(640, 480, fmt)
    ox, oy = (xres - 640) // 2, (yres - 480) // 2
    row = 640 * soft.bpp
    try:
        tty = os.open('/dev/tty1', os.O_RDWR)
        fcntl.ioctl(tty, 0x4B3A, 1)  # KD_GRAPHICS
    except OSError:
        tty = None
    if (ox, oy) != (0, 0):
        os.pwrite(fd, bytes(stride * yres), 0)

    def present():
        if stride == row and ox == 0:
            os.pwrite(fd, soft.buf, oy * stride)
        else:
            for y in range(480):
                os.pwrite(fd, soft.buf[y * row:(y + 1) * row], (oy + y) * stride + ox * soft.bpp)

    def close():
        if tty is not None:
            try:
                fcntl.ioctl(tty, 0x4B3A, 0)
                os.close(tty)
            except OSError:
                pass
        os.close(fd)

    return soft, present, close


def run_gui(state, devs, soft, present, close):
    try:
        while True:
            now = pump(state, devs, 0.04)
            if logic_step(state, now):
                break
            draw(soft, state, devs, now)
            present()
    finally:
        close()


# ------------------------------------------------------------ fallback texto
def run_text(state, devs):
    try:
        out = open('/dev/tty1', 'w')
    except OSError:
        out = sys.stdout
    while True:
        now = pump(state, devs, 0.15)
        if logic_step(state, now):
            break
        out.write('\033[H\033[2J')
        out.write('R36S Analog Tester (modo texto) - por LagdoLira\r\n\r\n')
        if state.screen == 'splash':
            out.write('Teste de analógicos e botões do R36S.\r\nPressione qualquer botão...\r\n')
        elif state.screen == 'menu':
            for i, m in enumerate(MENU_ITEMS):
                out.write('%s %s\r\n' % ('>' if i == state.menu_idx else ' ', m))
        else:
            ls = state.axis_lines() if state.screen == 'analog' else state.button_lines(now)
            for n, s, e in ls:
                out.write('%-16s %-18s %s\r\n' % (n, s, e))
            out.write('\r\nSTART+SELECT = voltar ao menu\r\n')
        out.flush()


def main():
    devs = open_devices()
    if not devs:
        msg = 'Nenhum controle encontrado em /dev/input (verifique permissoes).'
        try:
            open('/dev/tty1', 'w').write(msg + '\n')
        except OSError:
            print(msg)
        time.sleep(5)
        return
    state = State(devs)
    want = os.environ.get('BACKEND', 'auto')
    order = {'pygame': ['pygame'], 'fb': ['fb'], 'text': []}.get(want, ['pygame', 'fb'])
    for name in order:
        try:
            soft, present, close = (setup_pygame if name == 'pygame' else setup_fb)()
        except Exception as e:  # backend indisponivel -> tenta o proximo
            sys.stderr.write('backend %s falhou: %r\n' % (name, e))
            continue
        sys.stderr.write('usando backend %s\n' % name)
        run_gui(state, devs, soft, present, close)
        return
    run_text(state, devs)


if __name__ == '__main__':
    main()
