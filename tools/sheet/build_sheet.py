#!/usr/bin/env python3
"""입력 가구 데이터(furniture.json) -> '우리 양식' A3 제작도면 PDF(reportlab) + DXF(ezdxf).

하나의 레이아웃 모델(Sheet.items: 시트 좌표 mm, 좌상단 원점, y 아래로)을 만들고
PDF / DXF 렌더러가 같은 모델을 그린다.  양식 좌표는 SHEET_FORMAT_ANALYSIS.md §2~§8 기준.

실행:  python3 -I tools/sheet/build_sheet.py --json output_samples/furniture.json --out output_samples
       (옵션) --name 가구명  --site 현장명  --scale 25  --font C:/Windows/Fonts/malgun.ttf
"""
import argparse, contextlib, datetime, functools, json, math, os, sys

from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import ezdxf
from ezdxf.enums import TextEntityAlignment

# ----------------------------------------------------------------- 설정 변수
FURNITURE_NAME = "__-1"            # PROJECT TITLE 에 들어가는 가구명 (파일명 stem)
SITE_LOCATION = "판교 푸르지오 그랑블"
SCALE_DEN = 25                     # 1/25  (1/20, 1/25, 1/30 중)
DATE_TEXT = datetime.date.today().strftime("%Y.%m.%d")
# 폰트: 사용자 PC 에서는 맑은 고딕 경로를 지정(--font 또는 환경변수 SHEET_FONT).
FONT_CANDIDATES = [
    os.environ.get("SHEET_FONT", ""),
    r"C:\Windows\Fonts\malgun.ttf",
    "/usr/share/fonts/truetype/malgun.ttf",
    "/usr/share/fonts/truetype/malgun/malgun.ttf",
    "/mnt/c/Windows/Fonts/malgun.ttf",
    "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",       # 이 샌드박스의 대체 폰트
]
DXF_FONT_FILE = "malgun.ttf"       # DXF 텍스트 스타일에 지정되는 폰트(열람 PC 의 맑은 고딕)

PW, PH = 420.0, 297.0
PT = 25.4 / 72.0

# 스타일: 이름 -> (DXF 레이어, 선굵기 pt, RGB)
STY = {
    "OUT":   ("OUTLINE", 0.72, (0, 0, 0)),
    "FR":    ("FRAME", 0.36, (0, 0, 0)),
    "SEC":   ("FRAME", 0.72, (0, 0, 0)),
    "FRTH":  ("FRAME", 2.83, (0, 0, 0)),
    "DIM":   ("DIM", 0.36, (185, 185, 185)),
    "DIMT":  ("DIM", 0.36, (110, 110, 110)),
    "THIN":  ("THIN", 0.12, (125, 125, 125)),
    "HATCH": ("THIN", 0.12, (170, 170, 170)),
    "BLUE":  ("NOTE_BLUE", 0.24, (0, 0, 255)),
    "RED":   ("NOTE_RED", 0.36, (222, 0, 56)),
    "REDT":  ("NOTE_RED", 0.72, (222, 0, 56)),
}
TXT = {"k": ("TEXT", (0, 0, 0)), "g": ("TEXT", (110, 110, 110)), "b": ("NOTE_BLUE", (0, 0, 255)),
       "r": ("NOTE_RED", (222, 0, 56)), "w": ("TEXT", (255, 255, 255))}
LAYER_ORDER = ["OUTLINE", "DIM", "THIN", "NOTE_BLUE", "NOTE_RED", "FRAME", "TEXT"]
DXF_LW = [0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140, 158, 200, 211]

FONT_USED = {"path": None, "name": None}


def setup_font(user_path=None):
    cands = ([user_path] if user_path else []) + FONT_CANDIDATES
    for p in cands:
        if p and os.path.exists(p):
            try:
                pdfmetrics.registerFont(TTFont("KF", p, subfontIndex=0))
                FONT_USED["path"] = p
                FONT_USED["name"] = os.path.basename(p)
                return p
            except Exception as e:      # noqa
                print("font fail", p, e, file=sys.stderr)
    raise SystemExit("한글 TTF 를 찾지 못했습니다. --font 로 malgun.ttf 경로를 지정하세요.")


def tw(s, size):
    """문자열 폭(mm). size = em 크기(mm)."""
    return pdfmetrics.stringWidth(s, "KF", size / PT) * PT


def fmt(n):
    return f"{int(round(n)):,}"


# ----------------------------------------------------------------- 레이아웃 모델
class Sheet:
    def __init__(self, name):
        self.name = name
        self.items = []
        self.groups = []       # items 와 같은 길이: 뷰(BLOCK) 이름, None = 도곽/표제란(FRAME)
        self._cur = None
        self._last = (None, None)
        self._names = set()
        self.den = None        # 이 시트의 축척 분모(예 25 -> 1/25). DXF 는 이 값만큼 키워 실치수(1:1)로 낸다

    def _add(self, it):
        self.items.append(it)
        self.groups.append(self._cur)

    @contextlib.contextmanager
    def group(self, base):
        """이 안에서 그리는 항목을 한 뷰(DXF BLOCK)로 묶는다. 중첩 호출은 바깥 그룹에 합쳐지고,
        같은 base 를 연속 호출하면 같은 블록(예: 평면 + 치수 + 마커)이다."""
        if self._cur is not None:
            yield
            return
        if self._last[0] == base:
            name = self._last[1]
        else:
            name, n = base, 2
            while name in self._names:
                name = f"{base}_{n}"; n += 1
            self._names.add(name)
        self._last = (base, name); self._cur = name
        try:
            yield
        finally:
            self._cur = None

    def line(self, x1, y1, x2, y2, st="OUT"):
        self._add(("L", x1, y1, x2, y2, st))

    def dashed(self, x1, y1, x2, y2, st="THIN", d=1.6, g=0.9):
        L = math.hypot(x2 - x1, y2 - y1)
        if L < 1e-6:
            return
        ux, uy = (x2 - x1) / L, (y2 - y1) / L
        t = 0.0
        while t < L:
            e = min(t + d, L)
            self.line(x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e, st)
            t = e + g

    def chain(self, x1, y1, x2, y2, st="FR", seg=(8.0, 1.4, 0.8, 1.4)):
        """긴 쇄선(절단선): 긴 선-간격-점-간격 반복."""
        L = math.hypot(x2 - x1, y2 - y1)
        ux, uy = (x2 - x1) / L, (y2 - y1) / L
        t, k = 0.0, 0
        while t < L:
            e = min(t + seg[k % 4], L)
            if k % 2 == 0:
                self.line(x1 + ux * t, y1 + uy * t, x1 + ux * e, y1 + uy * e, st)
            t = e; k += 1

    def poly(self, pts, st="OUT", closed=False):
        self._add(("P", list(pts), st, closed))

    def rect(self, x1, y1, x2, y2, st="OUT"):
        self.poly([(x1, y1), (x2, y1), (x2, y2), (x1, y2)], st, True)

    def circ(self, cx, cy, r, st="OUT"):
        self._add(("C", cx, cy, r, st))

    def fill(self, pts, color):
        self._add(("F", list(pts), color))

    def text(self, x, y, s, size=2.4, c="k", a="l", rot=0):
        if s:
            self._add(("T", x, y, s, size, c, a, rot))

    def rrect(self, x1, y1, x2, y2, r, st="OUT"):
        pts = []
        for (cx, cy, a0) in ((x2 - r, y1 + r, -90), (x2 - r, y2 - r, 0), (x1 + r, y2 - r, 90), (x1 + r, y1 + r, 180)):
            for k in range(7):
                a = math.radians(a0 + 90 * k / 6)
                pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.poly(pts, st, True)

    def arc(self, cx, cy, r, a0, a1, st="OUT", n=16):
        self.poly([(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
                    cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)], st)

    def hatch_rect(self, x1, y1, x2, y2, step=1.6, st="HATCH"):
        """닫힌 사각 안을 45° 해칭 — 영역마다 HATCH 엔티티 1개(낱개 사선 LINE 으로 분해하지 않는다). step = 종이 mm 간격"""
        self._add(("H", [(x1, y1), (x2, y1), (x2, y2), (x1, y2)], st, step))


def view(base):
    """그리기 함수(첫 인자 sh)를 한 뷰(BLOCK)로 묶는 데코레이터."""
    def deco(fn):
        @functools.wraps(fn)
        def w(sh, *a, **k):
            with sh.group(base):
                return fn(sh, *a, **k)
        return w
    return deco


def hatch_lines(pts, step):
    """PDF 용: HATCH 영역(사각)을 45° 선분 목록으로 푼다(PDF 에는 해칭 객체가 없음)."""
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
    out = []
    k = x1 + y1
    while k < x2 + y2:
        lo, hi = max(x1, k - y2), min(x2, k - y1)
        if hi - lo > 0.05:
            out.append((lo, k - lo, hi, k - hi))
        k += step
    return out


# ----------------------------------------------------------------- 치수·마커 도우미
DSZ = 2.4


def _small_pos(i, n, a1, a2, tw_, horizontal=True):
    """폭이 좁아 글자가 안 들어갈 때 글자 중심 좌표."""
    if i == 0 and n > 1:
        return a1 - 0.8 - tw_ / 2
    return a2 + 0.8 + tw_ / 2


def dim_h(sh, xs, y, labels, ref=None, size=DSZ):
    """수평 치수. xs = 경계 x 목록(시트 mm), labels = 구간별 문자열."""
    n = len(labels)
    sgn = 0 if ref is None else (1 if y > ref else -1)
    for x in xs:
        if ref is not None:
            sh.line(x, ref + sgn * 0.8, x, y + sgn * 1.2, "DIM")
        sh.line(x - 0.7, y + 0.7, x + 0.7, y - 0.7, "DIMT")
    sh.line(xs[0] - 0.8, y, xs[-1] + 0.8, y, "DIM")
    for i, lab in enumerate(labels):
        a1, a2 = xs[i], xs[i + 1]
        w = tw(lab, size)
        if a2 - a1 >= w + 0.8:
            sh.text((a1 + a2) / 2, y - 0.8, lab, size, "k", "c")
        else:
            sh.text(_small_pos(i, n, a1, a2, w), y - 0.8, lab, size, "k", "c")


def dim_v(sh, x, ys, labels, ref=None, size=DSZ, side=-1):
    """수직 치수. ys = 경계 y 목록(시트 mm, 오름차순). 글자 90° 회전."""
    n = len(labels)
    sgn = 0 if ref is None else (1 if x > ref else -1)
    for y in ys:
        if ref is not None:
            sh.line(ref + sgn * 0.8, y, x + sgn * 1.2, y, "DIM")
        sh.line(x - 0.7, y + 0.7, x + 0.7, y - 0.7, "DIMT")
    sh.line(x, ys[0] - 0.8, x, ys[-1] + 0.8, "DIM")
    for i, lab in enumerate(labels):
        a1, a2 = ys[i], ys[i + 1]
        w = tw(lab, size)
        if a2 - a1 >= w + 0.8:
            sh.text(x + side * 0.8, (a1 + a2) / 2, lab, size, "k", "c", 90) if side < 0 else \
                sh.text(x + 0.8 + size * 0.75, (a1 + a2) / 2, lab, size, "k", "c", 90)
        else:
            cy = a2 + 0.8 + w / 2 if i < n - 1 or n == 1 else a2 + 0.8 + w / 2
            xx = x - 0.8 if side < 0 else x + 0.8 + size * 0.75
            sh.text(xx, cy, lab, size, "k", "c", 90)


def marker(sh, cx, cy, label, direction="up", r=3.3):
    """단면/입면 방향 마커: 원 + 삼각형 + 'A / ELE'."""
    sh.circ(cx, cy, r, "OUT")
    sh.text(cx, cy + 0.9, label, 2.6, "k", "c")
    sh.text(cx, cy + 2.2, "ELE", 1.1, "k", "c")
    t = 2.6
    if direction == "up":
        sh.fill([(cx - 2.4, cy - r), (cx + 2.4, cy - r), (cx, cy - r - t)], (0, 0, 0))
    elif direction == "down":
        sh.fill([(cx - 2.4, cy + r), (cx + 2.4, cy + r), (cx, cy + r + t)], (0, 0, 0))
    elif direction == "left":
        sh.fill([(cx - r, cy - 2.4), (cx - r, cy + 2.4), (cx - r - t, cy)], (0, 0, 0))
    else:
        sh.fill([(cx + r, cy - 2.4), (cx + r, cy + 2.4), (cx + r + t, cy)], (0, 0, 0))


# ----------------------------------------------------------------- 양식 틀 (§2)
def furniture_frame(sh, title, subject, sheet_no, scale_den, hdr, boundary=114.3, hdr2=("FRONT VIEW_ DOOR", "FRONT VIEW_ BODY")):
    L, R = 9.4, 410.6
    sh.rect(4.5, 3.2, 415.5, 293.9, "FR")
    sh.rect(L, 8.1, R, 289.0, "FRTH")
    # 헤더 행
    sh.line(L, 18.0, R, 18.0, "SEC")
    sh.text(17.2, 14.5, hdr[0], 4.2, "k")
    sh.text(218.3, 14.5, "NOTE", 4.2, "k")
    sh.line(210.3, 8.6, 210.3, boundary, "SEC")
    for y in (30.1, 42.1, 54.2):
        sh.line(210.3, y, R, y, "FR")
    # TOP/FRONT 경계 + FRONT 헤더 행
    sh.line(L, boundary, R, boundary, "SEC")
    sh.line(L, boundary + 9.9, R, boundary + 9.9, "SEC")
    sh.text(17.2, boundary + 6.5, hdr2[0], 4.2, "k")
    sh.text(218.3, boundary + 6.5, hdr2[1], 4.2, "k")
    # 표제란
    sh.line(L, 267.5, R, 267.5, "SEC")

    def tag(x, y, label, w):
        sh.rect(x, y, x + w, y + 2.7, "OUT")
        sh.fill([(x, y), (x + w, y), (x + w, y + 2.7), (x, y + 2.7)], (85, 85, 85))
        sh.text(x + 0.8, y + 2.05, label, 1.7, "w", "l")

    tag(58.2, 272.7, "SITE LOCATION", 22.0); sh.line(58.2, 276.2, 218.0, 276.2, "OUT")
    tag(58.2, 283.4, "PROJECT TITLE", 22.0); sh.line(58.2, 286.4, 218.0, 286.4, "OUT")
    tag(230.3, 272.7, "SHEET NO.", 22.0); sh.line(230.3, 276.2, 294.3, 276.2, "OUT")
    tag(230.3, 283.4, "SUBJECT TITLE", 22.0); sh.line(230.3, 286.4, 294.3, 286.4, "OUT")
    tag(306.9, 272.7, "DATE", 10.5); sh.line(306.9, 276.2, 363.4, 276.2, "OUT")
    tag(306.9, 283.4, "SCALE", 10.5); sh.line(306.9, 286.4, 363.4, 286.4, "OUT")
    sh.text(84.0, 275.0, SITE_LOCATION, 4.2)
    sh.text(84.0, 285.2, title, 4.2)
    sh.text(256.0, 275.0, sheet_no, 4.2)
    sh.text(256.0, 285.2, subject, 3.4)
    sh.text(321.0, 275.0, DATE_TEXT, 3.4)
    sh.text(321.0, 285.2, f"1/{scale_den}", 4.2)


def plan_frame(sh, room_title, sub_title, scale_den):
    sh.rect(4.5, 3.2, 415.5, 293.9, "FR")
    sh.text(17.0, 21.0, room_title, 8.5)
    sh.text(19.0, 277.0, SITE_LOCATION, 4.9)
    sh.text(19.0, 286.4, sub_title, 4.9)
    sh.text(400.0, 286.4, f"SCALE 1/{scale_den}", 4.9, "k", "r")


# ----------------------------------------------------------------- 가구 모델 -> 도형
EP, BT, DT = 20, 18, 20            # 측판·천판 EP 20T / 몸통 18T / 도어 20T
CH_H, CH_W, CH_GAP = 60, 40, 25    # 목찬넬 60*40, 상판 하단과 도어 상단 사이 25
TOP_IN = 862                       # 몸통 상판(18T) 하단... 천판 EP 880~900, 18T 상판 862~880
BOT_IN = 118                       # 하판 100~118
RAIL = 13                          # 서랍 레일 한쪽 여유


class Model:
    def __init__(self, data):
        self.d = data
        o = data["overall"]
        self.W, self.D, self.H = o["W"], o["D"], o["H"]
        self.top_t, self.body_H, self.kick = o["top_thickness"], o["body_H"], o["kick"]
        self.dB = data["depth_split"]["B_sink_side"]
        self.dA = data["depth_split"]["A_drawer_side"]
        self.bm = data["B_side"]["plan_modules"]
        self.ab = data["A_side"]["bays"]
        sc = data["countertop"]["sink_cutout"]
        self.sink = (sc["x_from_plan_left"], sc["y_from_back"], sc["w"], sc["d"], sc["corner_R"])
        self.ovl = data["B_side"]["left_overhang"]
        self.cuts = data.get("section_cuts", {"5": 600, "6": 1900, "7": 2300, "8": 2900})

    def mod_at(self, x):
        b = next((md for md in self.bm if md["x"] <= x < md["x"] + md["w"]), None)
        a = next((md for md in self.ab if md["x"] <= x < md["x"] + md["w"]), None)
        return b, a


SHORT = {"서랍장(2단)M": "서랍장\n(2단)M", "장(2단)": "장\n(2단)", "조리장(1D)L/R": "조리장\n(1D)L/R",
         "식기세척기 M": "식기\n세척기 M", "조리장(1D)L/R (싱크)": "조리장\n(1D)L/R", "로봇청소기서랍장(1D)L/R": "로봇청소기\n서랍장(1D)",
         "OPEN(EP 판넬/벽장용 20T)": "OPEN\n(찬넬 없음)"}


def ep_rect(sh, x1, y1, x2, y2, step=0.5):
    """EP 20T 판: 해칭 채움 + 외곽."""
    sh.hatch_rect(x1, y1, x2, y2, step, "HATCH")
    sh.rect(x1, y1, x2, y2, "OUT")


def blue_leader(sh, tx, ty, px, py, text, a="l", size=2.0):
    sh.line(tx, ty - size * 0.35, px, py, "BLUE")
    sh.text(tx, ty, text, size, "b", a)


def red_note(sh, x, y, text, a="l", size=2.0):
    sh.text(x, y, text, size, "r", a)


# ---- 평면 ------------------------------------------------------------
def ep_plan_rects(m):
    """평면에서의 EP 20T 위치(추정): 서랍면 좌단, 싱크면 좌단(후퇴 326), 우단 전체 깊이."""
    return [(0, m.dB, EP, m.D), (m.ovl, 0, m.ovl + EP, m.dB), (m.W - EP, 0, m.W, m.D)]


@view("VIEW_TOP")
def draw_plan(sh, m, ox, oy, s, labels=True, size=1.8):
    """평면(TOP VIEW). plan x: 좌->우, y: 0=싱크면(B) 앞 -> D=서랍면(A) 앞."""
    X = lambda x: ox + x * s
    Y = lambda y: oy + y * s
    for md in m.bm:
        sh.rect(X(md["x"]), Y(0), X(md["x"] + md["w"]), Y(m.dB), "THIN")
        sh.line(X(md["x"]), Y(DT), X(md["x"] + md["w"]), Y(DT), "THIN")          # 도어 20T
        if labels:
            nm = SHORT.get(md["name"], md["name"]); lines = nm.split("\n")
            for k, ln in enumerate(lines):
                sh.text(X(md["x"] + md["w"] / 2), Y(m.dB / 2) + (k - (len(lines) - 1) / 2) * size * 1.2 + size * 0.35, ln, size, "g", "c")
    for md in m.ab:
        sh.rect(X(md["x"]), Y(m.dB), X(md["x"] + md["w"]), Y(m.D), "THIN")
        if md["type"] != "open":
            sh.line(X(md["x"]), Y(m.D - DT), X(md["x"] + md["w"]), Y(m.D - DT), "THIN")
        if labels:
            nm = SHORT.get(md["name"], md["name"]); lines = nm.split("\n")
            for k, ln in enumerate(lines):
                sh.text(X(md["x"] + md["w"] / 2), Y(m.dB + m.dA / 2) + (k - (len(lines) - 1) / 2) * size * 1.2 + size * 0.35, ln, size, "g", "c")
    for (a, b, c, d) in ep_plan_rects(m):                                          # EP 20T
        ep_rect(sh, X(a), Y(b), X(c), Y(d), 0.45)
    sh.rect(X(0), Y(0), X(m.W), Y(m.D), "OUT")                                    # 상판
    sh.line(X(m.W / 2), Y(0), X(m.W / 2), Y(m.D), "THIN")
    sx, sy, sw, sd, sr = m.sink
    sh.rrect(X(sx), Y(sy), X(sx + sw), Y(sy + sd), max(sr * s, 0.4), "OUT")
    sh.circ(X(sx + sw / 2), Y(sy / 2 + 15), max(35 * s, 0.7), "OUT")              # 수전
    return X, Y


@view("VIEW_TOP")
def plan_dims(sh, m, ox, oy, s):
    X = lambda x: ox + x * s
    edges = [0, m.ovl] + [md["x"] + md["w"] for md in m.bm]
    dim_h(sh, [X(e) for e in edges], oy - 5.5, [fmt(b - a) for a, b in zip(edges, edges[1:])], ref=oy)
    dim_h(sh, [X(0), X(m.W)], oy - 11.5, [fmt(m.W)], ref=oy)
    ed = sorted(set([0, m.ab[0]["x"]] + [b["x"] + b["w"] for b in m.ab] + [m.W]))
    dim_h(sh, [X(e) for e in ed], oy + m.D * s + 5.5, [fmt(b - a) for a, b in zip(ed, ed[1:])], ref=oy + m.D * s)
    dim_v(sh, ox - 5.5, [oy, oy + m.dB * s, oy + m.D * s], [fmt(m.dB), fmt(m.dA)], ref=ox)
    dim_v(sh, ox - 11.5, [oy, oy + m.D * s], [fmt(m.D)], ref=ox)
    # EP 20T 파란 주석 (싱크면 좌단 EP 위치로 지시선)
    ex, ey = X(m.ovl + EP / 2), oy
    sh.line(ex, ey, ex + 19.0, oy - 16.5, "BLUE")
    sh.text(ex + 19.5, oy - 16.0, "측판 EP 20T (양단·추정) / 도어 20T", 1.7, "b", "l")


@view("VIEW_TOP")
def plan_markers(sh, m, ox, oy, s):
    """B(위)·A(아래) 정면 방향 + C(좌)·D(우) 측면 방향 마커."""
    cy = oy + m.D * s / 2
    marker(sh, ox + m.W * s + 8, oy + 7, "B", "up")
    marker(sh, ox + m.W * s + 8, oy + m.D * s - 7, "A", "down")
    marker(sh, ox + m.W * s + 8, cy, "D", "left")
    marker(sh, ox - 25.0, cy, "C", "right")
    # 단면 절단선 1·2: 가구 밖 위·아래로 연장, 양 끝에 번호 마커(보는 방향 = +x, 우측)
    yt, yb = oy - 19.0, oy + m.D * s + 14.5
    for num, xc in m.cuts.items():
        x = ox + xc * s
        sh.chain(x, yt + 3.3, x, yb - 3.3, "FR")
        sh.line(x - 2.2, yt + 5.0, x + 2.2, yt + 5.0, "SEC"); sh.line(x - 2.2, yb - 5.0, x + 2.2, yb - 5.0, "SEC")
        marker(sh, x, yt, num, "right")
        marker(sh, x, yb, num, "right")


@view("KEYPLAN")
def draw_keyplan(sh, m, face, x0=12.0, y0=19.5, w=26.0):
    rd = m.d["room_assumed"]
    s = w / rd["W"]
    h = rd["D"] * s
    sh.rect(x0, y0, x0 + w, y0 + h, "OUT")
    wt = 150 * s
    sh.rect(x0 + wt, y0 + wt, x0 + w - wt, y0 + h - wt, "THIN")
    ix = x0 + (rd["W"] - m.W) / 2 * s
    iy = y0 + 1100 * s
    sh.rect(ix, iy, ix + m.W * s, iy + m.D * s, "OUT")
    cx = ix + m.W * s / 2
    if face == "B":
        sh.fill([(cx - 1.6, iy - 3.4), (cx + 1.6, iy - 3.4), (cx, iy - 0.6)], (222, 0, 56))
    elif face == "A":
        sh.fill([(cx - 1.6, iy + m.D * s + 3.4), (cx + 1.6, iy + m.D * s + 3.4), (cx, iy + m.D * s + 0.6)], (222, 0, 56))
    elif face == "C":
        cy = iy + m.D * s / 2
        sh.fill([(ix - 3.4, cy - 1.6), (ix - 3.4, cy + 1.6), (ix - 0.6, cy)], (222, 0, 56))
    else:
        cy = iy + m.D * s / 2
        sh.fill([(ix + m.W * s + 3.4, cy - 1.6), (ix + m.W * s + 3.4, cy + 1.6), (ix + m.W * s + 0.6, cy)], (222, 0, 56))


def faucet(sh, X, Z, xc, ztop=1020, hgt=230):
    pts = [(X(xc), Z(ztop)), (X(xc), Z(ztop + hgt - 60))]
    r = 60
    for k in range(0, 9):
        a = math.radians(180 - 90 * k / 8)
        pts.append((X(xc + r + r * math.cos(a)), Z(ztop + hgt - 60 + r * math.sin(a))))
    pts.append((X(xc + 2 * r), Z(ztop + hgt - 140)))
    sh.poly(pts, "THIN")


# ---- 정면 공통 --------------------------------------------------------
def b_view_modules(m):
    """B면 정면(싱크면에서 본 모습)은 평면 x 가 좌우 반전."""
    return sorted([dict(md, vx=m.W - (md["x"] + md["w"])) for md in m.bm], key=lambda a: a["vx"])


def elev_frame(sh, m, ox, gy, s):
    X = lambda x: ox + x * s
    Z = lambda z: gy - z * s
    sh.rect(X(0), Z(m.H), X(m.W), Z(m.body_H), "OUT")        # 상판 T120
    sh.line(X(m.W / 2), Z(m.H), X(m.W / 2), Z(m.body_H), "THIN")
    return X, Z


def ep_band(sh, X, Z, m, x0, x1):
    """천판 EP 20T (상판 아래 880~900)."""
    ep_rect(sh, X(x0), Z(m.body_H), X(x1), Z(m.body_H - EP), 0.5)


def elev_dims(sh, m, X, Z, edges, labels):
    top = Z(m.H)
    dim_h(sh, [X(e) for e in edges], top - 11.0, labels, ref=top)
    dim_h(sh, [X(0), X(m.W)], top - 17.0, [fmt(m.W)], ref=top)
    dim_v(sh, X(0) - 6.0, [Z(m.body_H), Z(0)], [fmt(m.body_H)], ref=X(0))
    dim_v(sh, X(0) - 12.0, [Z(m.H), Z(0)], [fmt(m.H)], ref=X(0))
    dim_v(sh, X(m.W) + 6.0, [Z(m.H), Z(m.body_H), Z(m.kick), Z(0)], [fmt(m.top_t), fmt(m.body_H - m.kick), fmt(m.kick)], ref=X(m.W), side=1)


def inner_dim(sh, X, Z, x, z0, z1, label, size=1.7, st="THIN", c="k"):
    """칸 내부 높이 치수(작은 세로 치수)."""
    xs = X(x)
    sh.line(xs, Z(z0), xs, Z(z1), st)
    for z in (z0, z1):
        sh.line(xs - 0.5, Z(z) + 0.5, xs + 0.5, Z(z) - 0.5, st)
    sh.text(xs - 0.5, (Z(z0) + Z(z1)) / 2, label, size, c, "c", 90)


def pins(sh, X, Z, xl, xr, z0, z1):
    """선반핀 구멍(32mm 계열 대신 96 간격 단순 표기 / 추정)."""
    z = z0
    while z <= z1:
        for x in (xl, xr):
            sh.circ(X(x), Z(z), 0.3, "THIN")
        z += 96


def fronts(m, n):
    """전판 n단 분할: 하단 걸레받이 위 4, 단간 = 찬넬 틈 25, 상단 = 천판 EP 하단(880)에서 25 아래(855). [(z0,z1)]"""
    k, top = m.kick, m.body_H - EP - CH_GAP
    gap = CH_GAP
    fh = (top - (k + 4) - gap * (n - 1)) // n
    out, z = [], k + 4
    for _ in range(n):
        out.append((z, z + fh)); z += fh + gap
    out[-1] = (out[-1][0], top)
    return out


def ep_ends(sh, m, X, Z, xs):
    for x in xs:
        ep_rect(sh, X(x), Z(m.body_H), X(x + EP), Z(m.kick), 0.5)


def cut_marks(sh, m, X, Z, positions, gy, direction="right"):
    """정면 단면 마커 1·2: 위·아래 양 끝에 번호 마커 + 긴 쇄선 절단선(마커 쪽 굵은 끝선)."""
    yt, yb = Z(m.H) - 23.0, gy + 9.5
    for num, x in positions:
        xx = X(x)
        sh.chain(xx, yt + 3.3, xx, yb - 3.3, "FR")
        sh.line(xx - 2.2, yt + 5.0, xx + 2.2, yt + 5.0, "SEC"); sh.line(xx - 2.2, yb - 5.0, xx + 2.2, yb - 5.0, "SEC")
        marker(sh, xx, yt, num, direction)
        marker(sh, xx, yb, num, direction)


# ---- B면 정면(싱크면) --------------------------------------------------
def b_fronts(m, md):
    """B면 모듈의 전판(도어/서랍) 목록 [(z0, z1, 찬넬여부, 종류)]. 도어·서랍 상단 = 상판 하단 25 아래(875)."""
    k, top, t = m.kick, m.body_H - EP - CH_GAP, md["type"]
    if t == "drawer2":
        return [(a, b, True, "drawer") for a, b in fronts(m, 2)]
    if t in ("door", "door_sink"):
        return [(k + 4, top, True, "door")]
    if t == "cabinet":
        return [(a, b, True, "door") for a, b in fronts(m, 2)]
    if t == "robot":
        return [(k + 4, 690, True, "door"), (715, top, True, "drawer")]
    return [(k + 4, top, False, "dw")]


def a_fronts(m, md):
    return [] if md["type"] == "open" else [(a, b, True, "drawer") for a, b in fronts(m, 2)]


def chan_rect(x0, w, zt):
    """목찬넬 위치(정면, 도어 제거 시): 전판 상단 + 25(틈) = 천장(zc)에서 아래로 60. DOOR·BODY 공통 x 범위."""
    zc = zt + CH_GAP
    return x0 + 1.5, zc - CH_H, x0 + w - 1.5, zc


def draw_front_panel(sh, X, Z, x0, w, fr):
    """닫힌 정면의 전판(도어/서랍) + 상단 목찬넬 홈(외곽 0.72 + 안쪽 0.36 이중선)."""
    z0, z1, chan, kind = fr
    sh.rect(X(x0 + 1.5), Z(z1), X(x0 + w - 1.5), Z(z0), "OUT")
    if chan:
        xa, zb, xb, zt = chan_rect(x0, w, z1)
        sh.rect(X(xa), Z(z1 + CH_GAP), X(xb), Z(z1), "OUT")                       # 전판 상단 25 틈(손가락 진입구)
        sh.rect(X(xa + 12), Z(z1 + CH_GAP - 6), X(xb - 12), Z(z1 + 6), "FR")
        sh.rect(X(xa), Z(zt), X(xb), Z(zb), "THIN") if False else None
        sh.dashed(X(xa), Z(zb), X(xb), Z(zb), "THIN", 1.2, 0.8)                    # 뒤쪽 찬넬 하단(가려진 선)


def chan_label(sh, X, Z, x0, w, zt):
    cx = X(x0 + w * 0.5)
    blue_leader(sh, cx - 1.0, Z(zt - 110), cx, Z(zt + CH_GAP / 2), "목찬넬 60*40", "l", 1.8)


def chan_dims(sh, X, Z, x, m):
    """찬넬 높이 위치 치수(파랑): 상판 하단~전판 상단 25, 찬넬 60."""
    c = m.body_H - EP                                   # 천판 EP 하단
    inner_dim(sh, X, Z, x, c - CH_GAP, c, "25", 1.6, "BLUE", "b")
    inner_dim(sh, X, Z, x + 45, c - CH_H, c, "60", 1.6, "BLUE", "b")


def mods_sink_vx(m):
    sx, sy, sw, sd, sr = m.sink
    return m.W - (sx + sw)


@view("VIEW_FRONT_DOOR")
def draw_b_door(sh, m, ox, gy, s):
    X, Z = elev_frame(sh, m, ox, gy, s)
    mods = b_view_modules(m)
    bodyW = m.W - m.ovl
    k, h = m.kick, m.body_H
    sh.rect(X(0), Z(h), X(bodyW), Z(k), "OUT")
    sh.rect(X(10), Z(k), X(bodyW - 10), Z(0), "OUT")
    ep_band(sh, X, Z, m, 0, bodyW)
    ep_ends(sh, m, X, Z, [0, bodyW - EP])
    for md in mods:
        x0, w, t = md["vx"], md["w"], md["type"]
        cx = X(x0 + w / 2)
        for i, fr in enumerate(b_fronts(m, md)):
            draw_front_panel(sh, X, Z, x0, w, fr)
            if fr[3] == "drawer" and t == "drawer2":
                inner_dim(sh, X, Z, x0 + w - 40, fr[0], fr[1], fmt(fr[1] - fr[0]))
        if t == "dishwasher":
            sh.text(cx, Z(500) + 0.7, "식기세척기", 2.2, "k", "c")
            sh.line(X(x0 + 80), Z(820), X(x0 + w - 80), Z(820), "OUT")
        elif t == "robot":
            sh.text(cx, Z(795), "서랍", 1.8, "g", "c")
    drw = next(md for md in mods if md["type"] == "drawer2")
    drs = next(md for md in mods if md["type"] == "door_sink")
    chan_label(sh, X, Z, drw["vx"], drw["w"], b_fronts(m, drw)[1][1])
    chan_label(sh, X, Z, drs["vx"], drs["w"], b_fronts(m, drs)[0][1])
    chan_dims(sh, X, Z, drw["vx"] + 40, m)
    faucet(sh, X, Z, mods_sink_vx(m) + 425)
    sh.text(X(bodyW / 2), Z(k / 2) + 0.6, "걸레받이 H100", 1.7, "g", "c")
    return X, Z


@view("VIEW_FRONT_BODY")
def draw_b_body(sh, m, ox, gy, s):
    X, Z = elev_frame(sh, m, ox, gy, s)
    mods = b_view_modules(m)
    bodyW = m.W - m.ovl
    k, h = m.kick, m.body_H
    sh.rect(X(0), Z(h), X(bodyW), Z(k), "OUT")
    sh.rect(X(10), Z(k), X(bodyW - 10), Z(0), "OUT")
    ep_band(sh, X, Z, m, 0, bodyW)
    ep_ends(sh, m, X, Z, [0, bodyW - EP])
    sh.rect(X(EP), Z(TOP_IN + 18), X(bodyW - EP), Z(TOP_IN), "THIN")       # 상판(18T)
    sh.rect(X(EP), Z(BOT_IN), X(bodyW - EP), Z(k), "THIN")                  # 하판(18T)
    for md in mods:
        x0, w, t = md["vx"], md["w"], md["type"]
        xl = max(x0, EP) + (9 if x0 > 0 else 0)
        xr = min(x0 + w, bodyW - EP) - (9 if x0 + w < bodyW else 0)
        if x0 > 0:
            sh.rect(X(x0 - 9), Z(TOP_IN), X(x0 + 9), Z(BOT_IN), "THIN")      # 칸막이 18T
        cx = X(x0 + w / 2)
        if t == "robot":
            sh.line(X(xl), Z(710), X(xr), Z(710), "THIN")
            sh.rect(X(xl + RAIL), Z(870), X(xr - RAIL), Z(745), "THIN")
            sh.rect(X(xl), Z(409), X(xr), Z(391), "THIN"); pins(sh, X, Z, xl + 25, xr - 25, 200, 650)
            sh.text(cx, Z(780) + 0.6, "서랍통", 1.7, "g", "c")
            red_note(sh, cx, Z(550), "로봇청소기", "c", 1.8); red_note(sh, cx, Z(550) - 2.2, "수납(확인필요)", "c", 1.6)
            inner_dim(sh, X, Z, x0 + 30, BOT_IN, 391, fmt(391 - BOT_IN)); inner_dim(sh, X, Z, x0 + 30, 409, 710, fmt(710 - 409))
        elif t == "door":
            sh.rect(X(xl), Z(509), X(xr), Z(491), "THIN"); pins(sh, X, Z, xl + 25, xr - 25, 200, 780)
            inner_dim(sh, X, Z, x0 + 30, BOT_IN, 491, fmt(491 - BOT_IN)); inner_dim(sh, X, Z, x0 + 30, 509, TOP_IN, fmt(TOP_IN - 509))
            sh.text(cx, Z(300), "선반 18T", 1.7, "g", "c")
        elif t == "door_sink":
            sh.text(cx, Z(450), "싱크 하부", 2.0, "b", "c")
            sh.circ(X(x0 + w - 70), Z(200), max(40 * s, 0.6), "BLUE")
            blue_leader(sh, cx - 4, Z(130), X(x0 + w - 70), Z(200), "배수 타공 Φ80(추정)", "r", 1.7)
            inner_dim(sh, X, Z, x0 + 30, BOT_IN, TOP_IN, fmt(TOP_IN - BOT_IN))
        elif t == "dishwasher":
            sh.rect(X(x0 + 7), Z(855), X(x0 + 607), Z(40), "RED")
            red_note(sh, cx, Z(560), "식기세척기 W598", "c", 1.8)
            red_note(sh, cx, Z(560) - 2.2, "H815*D572(추정)", "c", 1.7)
            red_note(sh, cx, Z(420), "설치 W600 / 상부여유 45", "c", 1.5)
            sh.circ(X(x0 + w - 60), Z(150), max(30 * s, 0.5), "BLUE")
            blue_leader(sh, cx - 6, Z(100), X(x0 + w - 60), Z(150), "급수·전원 Φ60", "r", 1.6)
        elif t == "cabinet":
            sh.rect(X(xl), Z(509), X(xr), Z(491), "THIN"); pins(sh, X, Z, xl + 25, xr - 25, 200, 780)
            inner_dim(sh, X, Z, x0 + 30, BOT_IN, 491, fmt(491 - BOT_IN)); inner_dim(sh, X, Z, x0 + 30, 509, TOP_IN, fmt(TOP_IN - 509))
        elif t == "drawer2":
            f = fronts(m, 2)
            for (z0, z1) in f:
                bx0, bx1 = xl + RAIL + 9, xr - RAIL - 9
                sh.rect(X(bx0), Z(z0 + 150), X(bx1), Z(z0 + 30), "THIN")     # 서랍통
                sh.line(X(xl), Z(z0 + 30), X(bx0), Z(z0 + 30), "THIN")       # 레일
                sh.line(X(bx1), Z(z0 + 30), X(xr), Z(z0 + 30), "THIN")
            inner_dim(sh, X, Z, x0 + w - 40, f[0][0], f[0][1], fmt(f[0][1] - f[0][0]))
            inner_dim(sh, X, Z, x0 + w - 40, f[1][0], f[1][1], fmt(f[1][1] - f[1][0]))
            sh.text(cx, Z(340), "서랍통 W%d(추정)" % (w - 44), 1.7, "g", "c")
        for fr in b_fronts(m, md):                                           # 목찬넬 위치(DOOR 뷰와 동일 좌표)
            if fr[2]:
                xa, zb, xb, zt = chan_rect(x0, w, fr[1])
                sh.rect(X(xa), Z(zt), X(xb), Z(zb), "BLUE")
    drw = next(md for md in mods if md["type"] == "drawer2")
    chan_dims(sh, X, Z, drw["vx"] + 40, m)
    ex = X(10)
    sh.line(ex, Z(60), ex, gy + 3.6, "BLUE")
    sh.text(ex, gy + 7.5, "측판 EP 20T", 2.0, "b", "l")
    cut_marks(sh, m, X, Z, [(n, m.W - xc) for n, xc in m.cuts.items()], gy, "left")
    return X, Z


# ---- A면 정면(서랍면) --------------------------------------------------
def draw_a_elev(sh, m, ox, gy, s, body=False):
    """A면(서랍면) 정면: 평면 x 그대로."""
    X, Z = elev_frame(sh, m, ox, gy, s)
    k, h = m.kick, m.body_H
    sh.rect(X(0), Z(h), X(m.W), Z(k), "OUT")
    sh.rect(X(30), Z(k), X(m.W - 30), Z(0), "OUT")
    ep_band(sh, X, Z, m, 0, m.W)
    ep_ends(sh, m, X, Z, [0, m.W - EP])
    if body:
        sh.rect(X(EP), Z(TOP_IN + 18), X(m.W - EP), Z(TOP_IN), "THIN")
        sh.rect(X(EP), Z(BOT_IN), X(m.W - EP), Z(k), "THIN")
    for md in m.ab:
        x0, w, t = md["x"], md["w"], md["type"]
        cx = X(x0 + w / 2)
        xl, xr = x0 + 9, x0 + w - 9
        if body and x0 > EP:
            sh.rect(X(x0 - 9), Z(TOP_IN), X(x0 + 9), Z(BOT_IN), "THIN")
        elif not body:
            sh.line(X(x0), Z(k), X(x0), Z(h), "OUT")
        if t == "open":
            zs = k + md["shelf_h"]
            if body:
                sh.rect(X(EP), Z(zs + 9), X(x0 + w - 9), Z(zs - 9), "THIN"); pins(sh, X, Z, EP + 25, x0 + w - 34, 150, 800)
                inner_dim(sh, X, Z, x0 + 60, BOT_IN, zs - 9, fmt(zs - 9 - BOT_IN)); inner_dim(sh, X, Z, x0 + 60, zs + 9, TOP_IN, fmt(TOP_IN - zs - 9))
            sh.text(cx, Z(650), "OPEN (찬넬 없음)", 2.0, "g", "c")
            sh.text(cx, Z(k + md["shelf_h"] / 2), "선반 18T(추정)", 1.8, "g", "c")
            continue
        fs = a_fronts(m, md)
        if not body:
            for fr in fs:
                draw_front_panel(sh, X, Z, x0, w, fr)
                inner_dim(sh, X, Z, x0 + w - 40, fr[0], fr[1], fmt(fr[1] - fr[0]))
            sh.text(cx, Z(170), "서랍(2단)", 2.0, "g", "c")
        else:
            for (z0, z1, _c, _k) in fs:
                bx0, bx1 = xl + RAIL, xr - RAIL
                sh.rect(X(bx0), Z(z0 + 150), X(bx1), Z(z0 + 30), "THIN")
                sh.line(X(xl), Z(z0 + 30), X(bx0), Z(z0 + 30), "THIN"); sh.line(X(bx1), Z(z0 + 30), X(xr), Z(z0 + 30), "THIN")
                sh.rect(X(x0 + 1.5), Z(z1), X(x0 + w - 1.5), Z(z0), "THIN")
            inner_dim(sh, X, Z, x0 + 40, fs[0][0], fs[0][1], fmt(fs[0][1] - fs[0][0]))
            inner_dim(sh, X, Z, x0 + 40, fs[1][0], fs[1][1], fmt(fs[1][1] - fs[1][0]))
            sh.text(cx, Z(190), "서랍통 W%d (레일 13*2, 추정)" % (w - 18 - 2 * RAIL), 1.7, "g", "c")
            for fr in fs:                                                       # 목찬넬 위치(DOOR 뷰와 동일 좌표)
                xa, zb, xb, zt = chan_rect(x0, w, fr[1])
                sh.rect(X(xa), Z(zt), X(xb), Z(zb), "BLUE")
    if not body:
        b2, b3 = m.ab[1], m.ab[2]
        chan_label(sh, X, Z, b2["x"], b2["w"], a_fronts(m, b2)[1][1])
        chan_label(sh, X, Z, b3["x"], b3["w"], a_fronts(m, b3)[0][1])
    chan_dims(sh, X, Z, m.ab[1]["x"] + 40, m)
    sh.line(X(m.W), Z(k), X(m.W), Z(h), "OUT")
    sh.text(X(m.W / 2), Z(k / 2) + 0.6, "걸레받이 H100", 1.7, "g", "c")
    ex = X(10)
    sh.line(ex, Z(60), ex, gy + 3.6, "BLUE")
    sh.text(ex, gy + 7.5, "측판 EP 20T", 2.0, "b", "l")
    if body:
        cut_marks(sh, m, X, Z, list(m.cuts.items()), gy, "right")
    return X, Z


def a_dims(sh, m, X, Z):
    top = Z(m.H)
    ed = sorted(set([0, 20] + [b["x"] + b["w"] for b in m.ab] + [m.W]))
    dim_h(sh, [X(e) for e in ed], top - 11.0, [fmt(b - a) for a, b in zip(ed, ed[1:])], ref=top)
    dim_h(sh, [X(0), X(m.W)], top - 17.0, [fmt(m.W)], ref=top)
    dim_v(sh, X(0) - 6.0, [Z(m.body_H), Z(0)], [fmt(m.body_H)], ref=X(0))
    dim_v(sh, X(0) - 12.0, [Z(m.H), Z(0)], [fmt(m.H)], ref=X(0))
    dim_v(sh, X(m.W) + 6.0, [Z(m.H), Z(m.body_H), Z(m.kick), Z(0)], [fmt(m.top_t), fmt(m.body_H - m.kick), fmt(m.kick)], ref=X(m.W), side=1)


# ---- 측면 / 단면 ------------------------------------------------------
def channel_poly(sh, X, Z, xb, zc, sign=1):
    """목찬넬 60*40 단면(ㄴ형, 실선). xb = 도어 뒷면 좌표, zc = 천장(천판 EP 하단) z, sign=+1 뒤쪽이 +x / -1 뒤쪽이 -x.
    수직 다리(18T)는 천장에서 60 아래로 뒤쪽에, 수평 플랜지(18T)는 하단에서 도어 쪽으로 -> 도어 위 25 틈으로 손가락이 들어가는 홈."""
    pts = [(xb + sign * 22, zc), (xb + sign * 40, zc), (xb + sign * 40, zc - CH_H),
           (xb, zc - CH_H), (xb, zc - CH_H + 18), (xb + sign * 22, zc - CH_H + 18)]
    sh.poly([(X(x), Z(z)) for x, z in pts], "OUT", True)


@view("VIEW_SIDE")
def draw_end_view(sh, m, ox, gy, s, side):
    """좌측면도(C, side='L') / 우측면도(D, side='R'). 가로축=깊이."""
    k, h = m.kick, m.body_H
    Y = (lambda y: ox + y * s) if side == "L" else (lambda y: ox + (m.D - y) * s)
    Z = lambda z: gy - z * s
    sh.rect(Y(0) if side == "L" else Y(m.D), Z(m.H), Y(m.D) if side == "L" else Y(0), Z(h), "OUT")    # 상판 T120
    sh.rect(Y(60) if side == "L" else Y(m.D - 60), Z(k), Y(m.D - 60) if side == "L" else Y(60), Z(0), "OUT")   # 걸레받이
    def band(y0, y1, z0, z1, ep=False):
        a, b = sorted((Y(y0), Y(y1)))
        if ep:
            ep_rect(sh, a, Z(z1), b, Z(z0), 0.5)
        else:
            sh.rect(a, Z(z1), b, Z(z0), "OUT")
    if side == "L":
        band(0, m.dB, k, h, True)               # 싱크면 측판 EP (326 후퇴 -> 뒤쪽에 보임)
        band(m.dB, m.D, k, h, True)             # 서랍면 측판 EP (OPEN 베이 끝, 앞쪽)
        sh.line(Y(m.dB), Z(k), Y(m.dB), Z(h), "OUT")
    else:
        band(0, m.D, k, h, True)
    faucet(sh, lambda y: Y(y), Z, 62)
    # 치수
    top = Z(m.H)
    a0, a1 = (Y(0), Y(m.D)) if side == "L" else (Y(m.D), Y(0))
    dim_h(sh, [a0, a1], top - 12.0, [fmt(m.D)], ref=top)
    if side == "L":
        dim_h(sh, [Y(0), Y(m.dB), Y(m.D)], Z(0) + 6.0, [fmt(m.dB) + " 싱크면", fmt(m.dA) + " 서랍면"], ref=Z(0))
    else:
        dim_h(sh, [Y(m.D), Y(m.dB), Y(0)], Z(0) + 6.0, [fmt(m.dA) + " 서랍면", fmt(m.dB) + " 싱크면"], ref=Z(0))
    dim_v(sh, a0 - 6.0, [Z(h), Z(0)], [fmt(h)], ref=a0)
    dim_v(sh, a0 - 12.0, [Z(m.H), Z(0)], [fmt(m.H)], ref=a0)
    dim_v(sh, a1 + 6.0, [Z(m.H), Z(h), Z(k), Z(0)], [fmt(m.top_t), fmt(h - k), fmt(k)], ref=a1, side=1)
    # 주석
    if side == "L":
        sh.text(Y(m.dB / 2), Z(450), "싱크면 측판 EP(326 후퇴·추정)", 1.8, "b", "c")
        sh.text(Y(m.dB + m.dA / 2), Z(450), "서랍면 EP", 1.8, "b", "c")
    else:
        sh.text(Y(m.D / 2), Z(450), "측판 EP 20T 전체 깊이(추정)", 1.8, "b", "c")
    return Y, Z


@view("SECTION")
def draw_section(sh, m, ox, gy, s, xc):
    """절단면(정면 마커 1·2): 평면 x=xc 에서 깊이 방향으로 자른 단면. B(싱크면) 좌 / A(서랍면) 우."""
    X = lambda y: ox + y * s
    Z = lambda z: gy - z * s
    k, h = m.kick, m.body_H
    mb, ma = m.mod_at(xc)
    D, dB = m.D, m.dB
    sh.rect(X(0), Z(m.H), X(D), Z(h), "OUT")                                  # 상판 T120
    ep_rect(sh, X(0), Z(h), X(D), Z(h - EP), 0.5)                             # 천판 EP 20T
    sh.rect(X(60), Z(k), X(D - 60), Z(0), "OUT")                              # 걸레받이
    # 공통: 뒷판 9T (등 맞댐)
    sh.rect(X(dB - 9), Z(TOP_IN), X(dB), Z(BOT_IN), "THIN")
    sh.rect(X(dB), Z(TOP_IN), X(dB + 9), Z(BOT_IN), "THIN")
    # 하판 / 상판(18T)
    chan_b = mb["type"] not in ("dishwasher", "robot")
    chan_a = ma["type"] != "open"
    for (y0, y1) in ((DT + (40 if chan_b else 0), dB - 9), (dB + 9, D - DT - (40 if chan_a else 0))):
        sh.rect(X(y0), Z(BOT_IN), X(y1), Z(k), "THIN")
        sh.rect(X(y0), Z(TOP_IN + 18), X(y1), Z(TOP_IN), "THIN")
    # 상판 하부 보강대 60*18 (뒤쪽 등 맞댐 면)
    for (y0, y1) in ((dB - 9 - 60, dB - 9), (dB + 9, dB + 9 + 60)):
        sh.rect(X(y0), Z(TOP_IN), X(y1), Z(TOP_IN - 18), "THIN")
    # ---- B (싱크면) ----
    t = mb["type"]
    if t not in ("dishwasher", "robot"):
        sh.rect(X(0), Z(h - EP - CH_GAP), X(DT), Z(k + 4), "OUT")               # 도어 20T (상단 = 천판 하단 25 아래)
        channel_poly(sh, X, Z, DT, h - EP, +1)                                  # 목찬넬
    if t in ("door", "cabinet"):
        sh.rect(X(DT), Z(509), X(dB - 9), Z(491), "OUT")
        for y in (DT + 30, dB - 9 - 30):
            sh.circ(X(y), Z(500), 0.3, "THIN")
        inner_dim(sh, X, Z, 300, BOT_IN, 491, fmt(491 - BOT_IN)); inner_dim(sh, X, Z, 300, 509, TOP_IN, fmt(TOP_IN - 509))
    elif t == "drawer2":
        for (z0, z1) in fronts(m, 2):
            sh.rect(X(0), Z(z1), X(DT), Z(z0), "OUT")                          # 서랍 전판 20T
            sh.rect(X(DT + RAIL), Z(z0 + 150), X(DT + 500), Z(z0 + 30), "THIN")  # 서랍통 D500
            sh.line(X(DT), Z(z0 + 30), X(DT + 500), Z(z0 + 30), "THIN")
        inner_dim(sh, X, Z, 200, fronts(m, 2)[0][0], fronts(m, 2)[0][1], fmt(fronts(m, 2)[0][1] - fronts(m, 2)[0][0]))
        blue_leader(sh, X(100), Z(560), X(DT + 250), Z(190), "서랍레일 L500(추정)", "l", 1.7)
    elif t == "robot":
        sh.rect(X(0), Z(h - EP - CH_GAP), X(DT), Z(715), "OUT")
        sh.rect(X(DT + RAIL), Z(870), X(DT + 500), Z(745), "THIN")
        sh.rect(X(0), Z(690), X(DT), Z(k + 4), "OUT")
        sh.rect(X(DT), Z(409), X(dB - 9), Z(391), "OUT")
        red_note(sh, X(100), Z(300), "로봇청소기 수납", "l", 1.7)
    elif t == "dishwasher":
        sh.rect(X(DT + 10), Z(855), X(DT + 10 + 572), Z(40), "RED")
        red_note(sh, X(60), Z(520), "식기세척기 D572", "l", 1.7)
        red_note(sh, X(60), Z(520) - 2.2, "H815 / 상여유 45", "l", 1.6)
        red_note(sh, X(60), Z(520) - 4.4, "후면 배관 여유 49", "l", 1.6)
    elif t == "door_sink":
        sx, sy, sw, sd, sr = m.sink
        sh.dashed(X(sy), Z(h), X(sy), Z(h - 200), "BLUE"); sh.dashed(X(sy + sd), Z(h), X(sy + sd), Z(h - 200), "BLUE")
        sh.dashed(X(sy), Z(h - 200), X(sy + sd), Z(h - 200), "BLUE")
        sh.line(X(sy + sd / 2), Z(h - 200), X(sy + sd / 2), Z(250), "BLUE")
        sh.circ(X(dB - 5), Z(200), 0.7, "BLUE")
        blue_leader(sh, X(70), Z(330), X(sy + sd / 2), Z(330), "배수관 Φ40 / 타공 Φ80(추정)", "l", 1.6)
        sh.text(X(sy + sd / 2), Z(h - 100), "싱크볼", 1.7, "b", "c")
    # ---- A (서랍면) ----
    ta = ma["type"]
    if ta == "open":
        zs = k + ma["shelf_h"]
        sh.rect(X(dB + 9), Z(zs + 9), X(D - 20), Z(zs - 9), "OUT")
        sh.text(X(dB + 9 + 180), Z(650), "OPEN", 2.0, "g", "c")
        inner_dim(sh, X, Z, dB + 40, BOT_IN, zs - 9, fmt(zs - 9 - BOT_IN)); inner_dim(sh, X, Z, dB + 40, zs + 9, TOP_IN, fmt(TOP_IN - zs - 9))
    else:
        for (z0, z1) in fronts(m, 2):
            sh.rect(X(D - DT), Z(z1), X(D), Z(z0), "OUT")
            sh.rect(X(D - DT - 400), Z(z0 + 150), X(D - DT - RAIL), Z(z0 + 30), "THIN")     # 서랍통 D400
            sh.line(X(D - DT - 400), Z(z0 + 30), X(D - DT), Z(z0 + 30), "THIN")
        channel_poly(sh, X, Z, D - DT, h - EP, -1)
        channel_poly(sh, X, Z, D - DT, fronts(m, 2)[0][1] + CH_GAP, -1)
        inner_dim(sh, X, Z, D - 150, fronts(m, 2)[1][0], fronts(m, 2)[1][1], fmt(fronts(m, 2)[1][1] - fronts(m, 2)[1][0]))
    # 천판 EP 라벨 / 보강대 라벨
    sh.line(X(dB * 0.55), Z(1000) + 0, X(dB * 0.55), Z(h - 10) + 0, "BLUE")
    sh.text(X(dB * 0.55) - 0.5, Z(1000) - 0.6, "천판 EP 20T", 1.7, "b", "r")
    # 치수
    top = Z(m.H)
    dim_h(sh, [X(0), X(D)], top - 6.0, [fmt(D)], ref=top)
    dim_h(sh, [X(0), X(dB), X(D)], Z(0) + 6.0, [fmt(dB), fmt(m.dA)], ref=Z(0))
    dim_v(sh, X(0) - 6.0, [Z(h), Z(0)], [fmt(h)], ref=X(0))
    dim_v(sh, X(0) - 12.0, [Z(m.H), Z(0)], [fmt(m.H)], ref=X(0))
    dim_v(sh, X(D) + 6.0, [Z(m.H), Z(h), Z(k), Z(0)], [fmt(m.top_t), fmt(h - k), fmt(k)], ref=X(D), side=1)
    return X, Z


# ---- 상세 ------------------------------------------------------------
def block_arrow(sh, x, y, L, direction, th=1.4):
    """굵은 방향 화살표(채움). (x, y) = 꼬리, direction = up/down/left/right."""
    dx, dy = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}[direction]
    px, py = -dy, dx
    hx, hy = x + dx * L, y + dy * L
    b = L * 0.45
    pts = [(x + px * th / 2, y + py * th / 2), (hx - dx * b + px * th / 2, hy - dy * b + py * th / 2),
           (hx - dx * b + px * th * 1.5, hy - dy * b + py * th * 1.5), (hx, hy),
           (hx - dx * b - px * th * 1.5, hy - dy * b - py * th * 1.5), (hx - dx * b - px * th / 2, hy - dy * b - py * th / 2),
           (x - px * th / 2, y - py * th / 2)]
    sh.fill(pts, (0, 0, 0))


def shaded_label(sh, x, y, text, size=2.4, a="l"):
    """음영 박스 라벨(방향 표기용). (x, y) = 글자 기준선."""
    w = tw(text, size) + 2.0
    x0 = x - 1.0 if a == "l" else (x - w / 2 if a == "c" else x - w + 1.0)
    sh.fill([(x0, y - size * 0.9), (x0 + w, y - size * 0.9), (x0 + w, y + size * 0.35), (x0, y + size * 0.35)], (225, 225, 225))
    sh.text(x0 + 1.0, y, text, size, "k", "l")


def front_back(sh, xf, xb, y, front="전면 (도어 쪽)", back="후면 (벽 쪽)", size=2.4):
    """가로 방향 전면/후면 표기: xf = 전면 쪽 끝, xb = 후면 쪽 끝 (둘 중 어느 쪽이 왼쪽이든 가능)."""
    d = "left" if xf < xb else "right"
    dr = "right" if xf < xb else "left"
    block_arrow(sh, xf + (14.0 if xf < xb else -14.0), y, 10.0, d)
    block_arrow(sh, xb - (14.0 if xf < xb else -14.0), y, 10.0, dr)
    tx = xf + (16.0 if xf < xb else -16.0)
    shaded_label(sh, tx, y + 0.9, front, size, "l" if xf < xb else "r")
    tb = xb - (16.0 if xf < xb else -16.0)
    shaded_label(sh, tb, y + 0.9, back, size, "r" if xf < xb else "l")


@view("DETAIL_CHANNEL")
def edge_section(sh, X0, Y0, sc, door_len, xmax=70, counter_h=0, dims=True, hand=True):
    """③ 목찬넬 측면 단면: 앞(전면)=왼쪽, 뒤(후면)=오른쪽. z 는 천판 EP 하단(0)에서 아래로.
    샘플(33~38쪽 SIDE VIEW 상세)과 같은 구조: 천판 EP 해칭 아래 25 지점에 도어 상단, 찬넬 ㄴ형(수직 다리 18T 는 뒤쪽 천판 아래,
    수평 플랜지 18T 는 하단) -> 도어 위 25 틈으로 들어온 손가락이 도어 뒤 찬넬 홈(약 22 x 42)에 닿는다."""
    X = lambda x: X0 + x * sc
    Y = lambda z: Y0 + z * sc
    ep_rect(sh, X(0), Y(-EP), X(xmax), Y(0), max(0.7, 0.5 * sc * 5) if sc > 0.3 else 0.5)    # 천판 EP 20T 해칭
    if counter_h:
        sh.rect(X(0), Y(-EP - counter_h), X(xmax), Y(-EP), "OUT")                             # 상판 T120
    sh.rect(X(0), Y(CH_GAP), X(DT), Y(CH_GAP + door_len), "OUT")                              # 도어 20T (전면 = 왼쪽)
    pts = [(42, 0), (60, 0), (60, CH_H), (DT, CH_H), (DT, CH_H - 18), (42, CH_H - 18)]
    sh.poly([(X(x), Y(z)) for x, z in pts], "OUT", True)                                      # 목찬넬(ㄴ)
    if hand:
        ay = Y(12)
        sh.line(X(-3), ay, X(38), ay, "BLUE")
        sh.fill([(X(38), ay), (X(38) - 1.6, ay - 0.8), (X(38) - 1.6, ay + 0.8)], (0, 0, 255))
        sh.text(X(2), ay - 1.4, "손 진입", 2.0 if sc > 0.3 else 1.4, "b", "l")
    if dims:
        bx = X(xmax if xmax < 90 else 60) + 4
        bx = X(60) + 4
        sh.line(bx, Y(0), bx, Y(CH_H), "BLUE")                                                 # 60 : 천판 하단 ~ 찬넬 하단
        for z in (0, CH_H):
            sh.line(bx - 0.6, Y(z) + 0.6, bx + 0.6, Y(z) - 0.6, "BLUE")
        sh.text(bx + 2.8, (Y(0) + Y(CH_H)) / 2, "60", 2.4, "b", "c", 90)
        lx = X(-14)                                                                           # 25 : 천판 하단 ~ 도어 상단
        sh.line(lx, Y(0), lx, Y(CH_GAP), "BLUE")
        for z in (0, CH_GAP):
            sh.line(lx - 0.6, Y(z) + 0.6, lx + 0.6, Y(z) - 0.6, "BLUE")
        sh.text(lx - 0.8, (Y(0) + Y(CH_GAP)) / 2, "25", 2.4, "b", "c", 90)
        by = Y(CH_H) + 3
        sh.line(X(DT), by, X(60), by, "BLUE")                                                  # 40 : 도어 뒷면 ~ 찬넬 뒷면
        for x in (DT, 60):
            sh.line(X(x) - 0.6, by + 0.6, X(x) + 0.6, by - 0.6, "BLUE")
        sh.text((X(DT) + X(60)) / 2, by + 3.4, "40", 2.4, "b", "c")
        sh.text(X(DT / 2), Y(CH_GAP + door_len) + 3.2, "20", 2.0, "b", "c")                    # 20 : 도어 두께
    return X, Y


def detail_title(sh, x, y, num, text, size=3.6):
    """상세 제목: 번호 원 + 굵은 글씨 + 굵은 밑줄 (시트 헤더 행과 다른 스타일)."""
    sh.circ(x + 3.0, y - 1.3, 3.0, "OUT")
    sh.text(x + 3.0, y - 0.3, str(num), 3.4, "k", "c")
    tx = x + 8.0
    for dx in (0.0, 0.2):
        sh.text(tx + dx, y, text, size, "k", "l")
    sh.line(tx, y + 1.8, tx + tw(text, size), y + 1.8, "SEC")


def callout(sh, x, y, num, tx=None, ty=None):
    """상세 호출 원(번호) + 지시선."""
    sh.circ(x, y, 2.6, "BLUE")
    sh.text(x, y + 0.9, str(num), 2.6, "b", "c")
    if tx is not None:
        sh.line(x, y, tx, ty, "BLUE")


@view("DETAIL_COUNTERTOP")
def draw_countertop_plan(sh, m, ox, oy, s):
    X = lambda x: ox + x * s
    Y = lambda y: oy + y * s
    sh.rect(X(0), Y(0), X(m.W), Y(m.D), "OUT")
    sh.line(X(m.W / 2), Y(0), X(m.W / 2), Y(m.D), "OUT")                       # 이음선
    sx, sy, sw, sd, sr = m.sink
    sh.rrect(X(sx), Y(sy), X(sx + sw), Y(sy + sd), max(sr * s, 0.4), "OUT")
    sh.circ(X(sx + sw / 2), Y(sy / 2 + 15), max(17.5 * s, 0.5), "OUT")         # 수전 홀
    for xx in (sx - 60, sx + sw):                                              # 하부 보강대(추정)
        sh.rect(X(xx), Y(0), X(xx + 60), Y(m.dB), "BLUE")
    ckx, cky = 481, 65                                                         # 쿡탑 박스(위치 미상)
    for (a, b, c, d) in ((ckx, cky, ckx + 590, cky), (ckx + 590, cky, ckx + 590, cky + 520),
                         (ckx + 590, cky + 520, ckx, cky + 520), (ckx, cky + 520, ckx, cky)):
        sh.dashed(X(a), Y(b), X(c), Y(d), "RED", 1.6, 0.9)
    red_note(sh, X(ckx + 295), Y(cky + 260), "쿡탑 W590*D520", "c", 1.8)
    red_note(sh, X(ckx + 295), Y(cky + 260) + 2.4, "(위치 미상)", "c", 1.7)
    sh.text(X(sx + sw / 2), Y(sy + sd / 2) + 0.7, "싱크 컷", 2.0, "b", "c")
    # 치수 (의미를 라벨로 명시)
    dim_h(sh, [X(0), X(sx), X(sx + sw), X(m.W)], oy - 5.5, ["좌측 끝~컷 %s" % fmt(sx), "컷 %s" % fmt(sw), "컷~우측 끝 %s" % fmt(m.W - sx - sw)], ref=oy, size=2.0)
    dim_h(sh, [X(0), X(m.W / 2), X(m.W)], oy - 11.5, ["상판 1/2  1,800", "상판 2/2  1,800"], ref=oy, size=2.2)
    dim_v(sh, ox - 5.5, [oy, Y(sy), Y(sy + sd), Y(m.D)], [fmt(sy), fmt(sd), fmt(m.D - sy - sd)], ref=ox)
    dim_v(sh, ox - 11.5, [oy, Y(m.D)], [fmt(m.D)], ref=ox)
    sh.text(ox - 16.0, oy + 2.0, "앞(싱크면)", 1.8, "g", "r")
    sh.text(ox - 16.0, oy + m.D * s, "앞(서랍면)", 1.8, "g", "r")
    # 상세 호출: ② 우단 앞쪽 모서리, ③ 서랍면 목찬넬
    callout(sh, X(m.W) + 7.0, Y(0) + 5.0, 2, X(m.W), Y(0) + 1.0)
    callout(sh, X(1350), Y(m.D) + 7.0, 3, X(1350), Y(m.D))
    sh.text(X(1350) + 4.0, Y(m.D) + 8.0, "서랍면 목찬넬", 1.8, "b", "l")


def legend(sh, x, y):
    """범례(상판 평면)."""
    sh.text(x, y, "[범례]", 3.0, "k", "l")
    rows = [("OUT", "상판 외곽 · 싱크 컷 · 이음선(1,800)"), ("BLUE", "상판 하부 보강대 60*18 (추정)"),
            ("RED", "쿡탑 박스 점선 (위치 미상)"), ("CIRC", "수전 홀 Φ35")]
    yy = y + 6.0
    for st, t in rows:
        if st == "CIRC":
            sh.circ(x + 6.0, yy - 1.0, 1.4, "OUT")
        elif st == "RED":
            sh.dashed(x, yy - 1.0, x + 12.0, yy - 1.0, "RED", 1.6, 0.9)
        elif st == "BLUE":
            sh.rect(x, yy - 2.2, x + 12.0, yy, "BLUE")
        else:
            sh.line(x, yy - 1.0, x + 12.0, yy - 1.0, st)
        sh.text(x + 16.0, yy, t, 2.8, "k", "l")
        yy += 5.0


def arrow(sh, x1, y1, x2, y2, label, size=2.2, a="l", dx=1.5, dy=0.8):
    sh.line(x1, y1, x2, y2, "OUT")
    L = math.hypot(x2 - x1, y2 - y1); ux, uy = (x2 - x1) / L, (y2 - y1) / L
    sh.fill([(x2, y2), (x2 - ux * 2.2 - uy * 0.9, y2 - uy * 2.2 + ux * 0.9), (x2 - ux * 2.2 + uy * 0.9, y2 - uy * 2.2 - ux * 0.9)], (0, 0, 0))
    sh.text(x2 + dx, y2 + dy, label, size, "k", a)


@view("DETAIL_EP")
def edge_ep_plan(sh, m, X0, Y0, sc=0.2):
    """② 측판 EP 상세 - 평면(1/5): 우단 앞쪽(싱크면) 모서리. EP 20T / 몸통 측판 18T / 도어 20T."""
    xr = 3600
    X = lambda x: X0 + (x - (xr - 300)) * sc
    Y = lambda y: Y0 + y * sc
    ep_rect(sh, X(xr - EP), Y(0), X(xr), Y(300), 0.9)                       # 측판 EP 20T (바깥)
    sh.rect(X(xr - EP - BT), Y(DT), X(xr - EP), Y(300), "OUT")              # 몸통 측판 18T
    sh.rect(X(xr - 300), Y(0), X(xr - EP), Y(DT), "OUT")                    # 도어 20T (앞)
    sh.line(X(xr - 300), Y(DT + 18), X(xr - EP - BT), Y(DT + 18), "THIN")
    sh.dashed(X(xr - 300), Y(300), X(xr), Y(300), "THIN")                   # 절단 경계
    sh.text(X(xr - 70), Y(300) - 1.5, "(이하 생략)", 1.8, "g", "c")
    dim_h(sh, [X(xr - EP - BT), X(xr - EP), X(xr)], Y(300) + 7, ["18", "20"], ref=Y(300))
    dim_v(sh, X(xr - 300) - 6, [Y(0), Y(DT)], ["20"], ref=X(xr - 300))
    # 지시선 + 방향 표시(앞/뒤, 안쪽/바깥)
    blue_leader(sh, X(xr) + 6, Y(55), X(xr - EP / 2), Y(55), "측판 EP 20T (바깥쪽 마감판)", "l", 2.0)
    blue_leader(sh, X(xr) + 6, Y(150), X(xr - EP - BT / 2), Y(150), "몸통 측판 18T (안쪽)", "l", 2.0)
    blue_leader(sh, X(xr - 110), Y(0) - 8, X(xr - 110), Y(DT / 2), "도어 20T (전면)", "l", 2.0)
    block_arrow(sh, X(xr - 300) + 5, Y(0) - 3.0, 10.0, "up")
    shaded_label(sh, X(xr - 300) + 9.0, Y(0) - 6.0, "전면 (도어 쪽)", 2.6)
    block_arrow(sh, X(xr - 300) + 5, Y(300) - 12.0, 9.0, "down")
    shaded_label(sh, X(xr - 300) + 9.0, Y(300) - 5.5, "후면 (서랍면 쪽)", 2.4)
    arrow(sh, X(xr - 40), Y(300) + 17.0, X(xr - 40) - 14.0, Y(300) + 17.0, "가구 안쪽", 2.0, "r", -1.0, 0.8)
    sh.text(X(xr - 40) + 1.5, Y(300) + 17.8, "바깥(우단)", 2.0, "k", "l")
    sh.text(X(xr - 300), Y(300) + 24.0, "위치: 가구 우단 앞쪽(싱크면) 모서리 / 위 = 전면(도어), 오른쪽 = 바깥(EP 마감면)", 2.0, "k", "l")
    # 범례
    ly = Y(300) + 31.0
    sh.hatch_rect(X(xr - 300), ly - 2.4, X(xr - 300) + 8.0, ly, 0.5); sh.rect(X(xr - 300), ly - 2.4, X(xr - 300) + 8.0, ly, "OUT")
    sh.text(X(xr - 300) + 11.0, ly, "해칭 = 측판 EP 20T (마감판)", 2.0, "k", "l")
    sh.rect(X(xr - 300) + 66.0, ly - 2.4, X(xr - 300) + 74.0, ly, "OUT")
    sh.text(X(xr - 300) + 77.0, ly, "실선 사각 = 18T 몸통 / 20T 도어", 2.0, "k", "l")


# ----------------------------------------------------------------- NOTE
@view("NOTE")
def note_block(sh, d, lines):
    n = d["note"]
    sh.text(218.3, 26.6, "DOOR : " + n["DOOR"], 3.9)
    sh.text(218.3, 38.6, "BODY : " + n["BODY"], 3.9)
    sh.text(218.3, 50.6, "손잡이 : " + n["handle"], 3.9, "r")
    y = 61.0
    for s_, c in lines:
        sh.text(218.3, y, s_, 3.0, c)
        y += 5.3


NOTE_B = [("*EP = 마감판 20T (측판 양단·천판) / 몸통 18T / 도어 20T / 상판 T120", "b"),
          ("*싱크볼 컷 W850*D450 (상판 시트 판독, 추정) / 수전 Φ35", "r"),
          ("*식기세척기 W600 빌트인 : 제품 W598*H815*D572 (확인필요)", "r"),
          ("*쿡탑 스트로만 후드일체형 4구 JJ-HI01 (위치 확인필요)", "r"),
          ("*상판 1,800 x 2분할 이음 / 상판 하부 보강대 60*18 (추정)", "k"),
          ("*도어 : 주방장 도어 공용 부엌 도어 - KK DR 112", "k"),
          ("*목찬넬 60*40 : 전판 상단(상판 하단 25 이격). OPEN 베이 찬넬 없음", "b"),
          ("*단면 1·2 : SIDE VIEW 시트(NO.003) 참조 / 확인 목록 : NO.005", "k")]
NOTE_A = [("*EP = 마감판 20T (측판 양단·천판) / 몸통 18T / 서랍 전판 20T", "b"),
          ("*서랍장(2단)M x3 : 서랍 전판 363 x 2단, 단간 25(찬넬 틈, 추정)", "k"),
          ("*서랍 레일 : 좌우 13 여유, 레일 L500(싱크면) / L400(서랍면) (추정)", "r"),
          ("*OPEN 1 : 선반 18T 1단 (높이 357, 추정) / 후면 마감판 9T / 찬넬 없음", "k"),
          ("*목찬넬 60*40 : 서랍 전판 상단마다 (상판 하단 25 이격) (손잡이, 확인필요)", "r"),
          ("*콘센트·배선 타공 위치 : 확인필요", "r"),
          ("*단면 1·2 : SIDE VIEW 시트(NO.003) 참조 / 확인 목록 : NO.005", "k")]


# ----------------------------------------------------------------- 페이지 조립
def page_floor(m, scale_den):
    sh = Sheet("floor"); sh.den = scale_den
    rd = m.d["room_assumed"]
    plan_frame(sh, rd["name"], f"{rd['name']} 아일랜드 평면도", scale_den)
    with sh.group("VIEW_PLAN"):
        s = 1.0 / scale_den
        wt = 150
        ox, oy = 62.0, 62.0
        RW, RD = rd["W"], rd["D"]
        X = lambda x: ox + x * s
        Y = lambda y: oy + y * s
        for (a, b, c, d) in ((-wt, -wt, RW + wt, 0), (-wt, RD, RW + wt, RD + wt), (RW, 0, RW + wt, RD), (-wt, 0, 0, 2300), (-wt, 3200, 0, RD)):
            sh.rect(X(a), Y(b), X(c), Y(d), "OUT"); sh.hatch_rect(X(a), Y(b), X(c), Y(d))
        sh.line(X(0), Y(2300), X(900), Y(2300), "OUT")
        sh.arc(X(0), Y(2300), 900 * s, 0, 90, "THIN", 18)
        ix, iy = (RW - m.W) / 2, 1100
        draw_plan(sh, m, X(ix), Y(iy), s, True, 2.1)
        Xi = lambda x: X(ix) + x * s
        edges = [0, m.ovl] + [md["x"] + md["w"] for md in m.bm]
        dim_h(sh, [Xi(e) for e in edges], Y(iy) - 4.5, [fmt(b - a) for a, b in zip(edges, edges[1:])], ref=Y(iy))
        dim_h(sh, [Xi(0), Xi(m.W)], Y(iy) - 10.0, [fmt(m.W)], ref=Y(iy))
        dim_v(sh, Xi(0) - 5.0, [Y(iy), Y(iy + m.D)], [fmt(m.D)], ref=Xi(0))
        dim_h(sh, [X(0), X(RW)], Y(-wt) - 6.0, [fmt(RW)], ref=Y(-wt))
        dim_v(sh, X(RW + wt) + 7.0, [Y(0), Y(RD)], [fmt(RD)], ref=X(RW + wt), side=1)
        dim_h(sh, [X(0), Xi(0)], Y(RD) + 8, [fmt(ix)], ref=Y(RD))
        dim_h(sh, [Xi(m.W), X(RW)], Y(RD) + 8, [fmt(RW - ix - m.W)], ref=Y(RD))
        dim_v(sh, X(RW) - 8.0, [Y(0), Y(iy)], [fmt(iy)], ref=X(RW))
        dim_v(sh, X(RW) - 8.0, [Y(iy + m.D), Y(RD)], [fmt(RD - iy - m.D)], ref=X(RW))
        cy = Y(iy + m.D / 2)
        marker(sh, Xi(m.W / 2), Y(iy) - 22.0, "B", "down")
        marker(sh, Xi(m.W / 2), Y(iy + m.D) + 22.0, "A", "up")
        marker(sh, Xi(0) - 22.0, cy, "C", "right")
        marker(sh, Xi(m.W) + 22.0, cy, "D", "left")
        sh.text(X(RW) - 3, Y(RD) - 3, "※ 실 규격 5,200x3,400 / 출입구 위치는 가정(확인필요)", 2.2, "r", "r")
    return sh


def page_b(m, scale_den, sheet_no, title):
    sh = Sheet("furniture_B"); sh.den = scale_den
    furniture_frame(sh, title, "싱크면(B) 정면 / 평면", sheet_no, scale_den, ("TOP VIEW",))
    s = 1.0 / scale_den
    draw_keyplan(sh, m, "B")
    ox, oy = 50.0, 50.0
    draw_plan(sh, m, ox, oy, s)
    plan_dims(sh, m, ox, oy, s)
    plan_markers(sh, m, ox, oy, s)
    note_block(sh, m.d, NOTE_B)
    gy = 222.0
    mods = b_view_modules(m)
    edges = sorted(set([0] + [md["vx"] + md["w"] for md in mods] + [m.W]))
    labs = [fmt(b - a) for a, b in zip(edges, edges[1:])]
    with sh.group("VIEW_FRONT_DOOR"):             # 치수·방향 마커·캡션도 뷰 블록 안에 (뷰를 옮기면 같이 이동)
        X, Z = draw_b_door(sh, m, 30.0, gy, s)
        elev_dims(sh, m, X, Z, edges, labs)
        marker(sh, X(3450), gy + 10.0, "B", "up")
        sh.text(X(0), gy + 21.0, "도어 20T / 도어 상단 = 천판 하단 25 아래 / 단간 25(찬넬 틈, 추정)", 2.0, "b", "l")
        sh.text(X(0), gy + 24.5, "천판 EP 20T (상판 아래) / 측판 EP 20T", 2.0, "b", "l")
    with sh.group("VIEW_FRONT_BODY"):
        X, Z = draw_b_body(sh, m, 240.0, gy, s)
        elev_dims(sh, m, X, Z, edges, labs)
        marker(sh, X(3450), gy + 10.0, "B", "up")
        sh.text(X(0), gy + 21.0, "몸통 18T / 칸막이 18T / 뒷판 9T(추정) / 선반 18T·핀 96 간격(추정)", 2.0, "b", "l")
        sh.text(X(0), gy + 24.5, "서랍통 레일 13*2 / 걸레받이 H100 / 보강대 60*18 (상판 하부)", 2.0, "b", "l")
    return sh


def page_a(m, scale_den, sheet_no, title):
    sh = Sheet("furniture_A"); sh.den = scale_den
    furniture_frame(sh, title, "서랍면(A) 정면 / 평면", sheet_no, scale_den, ("TOP VIEW",), hdr2=("FRONT VIEW_ DOOR (A면)", "FRONT VIEW_ BODY (A면)"))
    s = 1.0 / scale_den
    draw_keyplan(sh, m, "A")
    ox, oy = 50.0, 50.0
    draw_plan(sh, m, ox, oy, s)
    plan_dims(sh, m, ox, oy, s)
    plan_markers(sh, m, ox, oy, s)
    note_block(sh, m.d, NOTE_A)
    gy = 222.0
    with sh.group("VIEW_FRONT_DOOR"):
        X, Z = draw_a_elev(sh, m, 30.0, gy, s, False)
        a_dims(sh, m, X, Z)
        marker(sh, X(3450), gy + 10.0, "A", "up")
        sh.text(X(0), gy + 21.0, "서랍 전판 20T (363 x 2단, 추정) / 측판 EP 20T / OPEN 베이 선반 18T", 2.0, "b", "l")
    with sh.group("VIEW_FRONT_BODY"):
        X, Z = draw_a_elev(sh, m, 240.0, gy, s, True)
        a_dims(sh, m, X, Z)
        marker(sh, X(3450), gy + 10.0, "A", "up")
        sh.text(X(0), gy + 21.0, "목찬넬 60*40 (서랍 전판 상단·중간) / 서랍통 레일 13*2(추정)", 2.0, "b", "l")
    return sh


def front_labels_row(sh, xl, xr, y, left, right, size=2.0):
    """좌/우 끝의 전면 방향 표기(굵은 화살표 + 음영 라벨)."""
    block_arrow(sh, xl + 7.0, y, 6.0, "left", 1.2)
    shaded_label(sh, xl + 8.5, y + 0.9, left, size, "l")
    block_arrow(sh, xr - 7.0, y, 6.0, "right", 1.2)
    shaded_label(sh, xr - 8.5, y + 0.9, right, size, "r")


def page_side(m, scale_den, sheet_no, title):
    sh = Sheet("side"); sh.den = scale_den
    furniture_frame(sh, title, "좌·우 측면 / 단면 1·2", sheet_no, scale_den, ("SIDE VIEW (LEFT / RIGHT)",),
                    hdr2=("SECTION 1  (단면)", "SECTION 2  (단면)"))
    s = 1.0 / scale_den
    # 상단: 좌측면도(C) / 우측면도(D)
    gy = 80.0
    with sh.group("VIEW_SIDE_LEFT"):              # 전면 표기·마커·캡션도 뷰 블록 안에
        Y, Z = draw_end_view(sh, m, 48.0, gy, s, "L")
        front_labels_row(sh, 48.0, 48.0 + m.D * s, gy + 12.0, "전면(싱크)", "전면(서랍)")
        marker(sh, 48.0 + m.D * s / 2, gy + 26.0, "C", "up")
        sh.text(48.0 + m.D * s / 2 + 8, gy + 26.0 + 1.2, "SIDE VIEW (LEFT) 좌측면도", 2.6, "k", "l")
    with sh.group("VIEW_SIDE_RIGHT"):
        Y, Z = draw_end_view(sh, m, 140.0, gy, s, "R")
        front_labels_row(sh, 140.0, 140.0 + m.D * s, gy + 12.0, "전면(서랍)", "전면(싱크)")
        marker(sh, 140.0 + m.D * s / 2, gy + 26.0, "D", "up")
        sh.text(140.0 + m.D * s / 2 + 8, gy + 26.0 + 1.2, "SIDE VIEW (RIGHT) 우측면도", 2.6, "k", "l")
    # NOTE
    lines = [("*C = 좌측면(싱크면 좌, 서랍면 우) / D = 우측면(서랍면 좌, 싱크면 우)", "k"),
             ("*측판 EP 20T : 양단 마감 (서랍면 좌단·우단 전체, 싱크면 좌단 326 후퇴)", "b"),
             ("*싱크면 좌단 326 = 상판 돌출(하부 몸통 없음, 추정)", "r"),
             ("*단면 1·2 : TOP VIEW / 정면 BODY 절단선 마커와 연결 (X=2,300 / 2,900)", "k"),
             ("*단면은 좌=싱크면 전면, 우=서랍면 전면 / 중앙 = 등 맞댐(후면)", "b"),
             ("*단면 내부 : 하판 18T, 상판 18T, 뒷판 9T, 선반 18T, 보강대 60*18", "k"),
             ("*목찬넬 60*40 단면 : 상세 ③ (NO.004) 참조", "b")]
    note_block(sh, m.d, lines)
    # 하단: 단면 2개
    gy2 = 222.0
    for ox2, (num, xc) in ((70.0, list(m.cuts.items())[0]), (280.0, list(m.cuts.items())[1])):
        with sh.group(f"SECTION_{num}"):
            X, Z = draw_section(sh, m, ox2, gy2, s, xc)
            front_labels_row(sh, X(0), X(m.D), gy2 + 12.0, "전면(싱크)", "전면(서랍)")
            shaded_label(sh, X(m.dB), gy2 + 18.0, "후면 = 등 맞댐", 2.0, "c")
            marker(sh, ox2 + m.D * s / 2, gy2 + 26.0, num, "right")
            sh.text(ox2 + m.D * s / 2 + 8, gy2 + 27.2, f"SECTION {num}  (X={fmt(xc)}, 추정 위치)", 2.4, "k", "l")
    return sh


def page_detail(m, scale_den, sheet_no, title):
    sh = Sheet("detail"); sh.den = scale_den
    furniture_frame(sh, title, "상판 / EP / 목찬넬 상세", sheet_no, scale_den, ("COUNTERTOP",),
                    hdr2=("DETAIL", "DETAIL"))
    s = 1.0 / scale_den
    with sh.group("DETAIL_COUNTERTOP"):
        detail_title(sh, 17.0, 29.0, 1, "상판 평면도 (1/25)")
        draw_countertop_plan(sh, m, 50.0, 58.0, s)
    note_block(sh, m.d, [("*상판 T120 / 1,800 x 2분할 (이음 1,800)", "k"),
                         ("*싱크 컷 850*450 R25 / 수전 Φ35 (추정)", "r"),
                         ("*EP = 마감판 20T / 몸통 18T / 도어 20T", "b"),
                         ("*생산 확인 목록 : 생산 확인표(NO.005) 참조", "k")])
    with sh.group("LEGEND"):
        legend(sh, 218.3, 83.0)
    # ② 측판 EP 상세
    with sh.group("DETAIL_EP"):
        detail_title(sh, 17.0, 139.0, 2, "측판 EP 상세 - 평면 (1/5)")
        edge_ep_plan(sh, m, 60.0, 156.0, 0.2)
    # ③ 목찬넬 상세 (범례·설명 글까지 한 블록)
    _g = sh.group("DETAIL_CHANNEL"); _g.__enter__()
    detail_title(sh, 218.3, 139.0, 3, "목찬넬 상세 - 측면 (1/2, 위치 1/10)")
    mx, my = 232.0, 158.0
    Xm, Ym = edge_section(sh, mx, my, 0.1, 300, xmax=200, counter_h=120, dims=False, hand=False)
    sh.text(mx, my + 36.0, "측면 일부 (1/10) : 서랍면 도어 상단", 2.0, "k", "l")
    front_back(sh, mx, mx + 60.0, my + 41.0, "전면", "후면", 2.2)
    cxm, cym = Xm(40), Ym(30)
    sh.circ(cxm, cym, 3.2, "BLUE")
    callout(sh, cxm + 8.0, cym - 8.0, 3, cxm + 2.3, cym - 2.3)
    ccx, ccy, cr = 352.0, 196.0, 34.0
    sh.circ(ccx, ccy, cr, "BLUE")
    sh.line(cxm + 3.2 * 0.8, cym + 3.2 * 0.5, ccx - cr * 0.9, ccy - cr * 0.4, "BLUE")
    edge_section(sh, ccx - 11.5, ccy - 13.75, 0.5, 50, xmax=62, dims=True, hand=True)
    sh.text(ccx, ccy - cr - 3.0, "목찬넬 60*40", 4.0, "b", "c")
    front_back(sh, ccx - cr, ccx + cr, ccy + cr + 8.0, "전면 (도어 쪽)", "후면 (벽)", 2.2)
    # 범례
    ly = 208.0
    sh.hatch_rect(232.0, ly - 2.4, 240.0, ly, 0.5); sh.rect(232.0, ly - 2.4, 240.0, ly, "OUT")
    sh.text(243.0, ly, "해칭 = 천판 EP 20T (상판 아래 마감판)", 2.2, "k", "l")
    sh.poly([(232.0, ly + 9.0), (240.0, ly + 9.0), (240.0, ly + 5.6), (236.0, ly + 5.6), (236.0, ly + 2.4), (232.0, ly + 2.4)], "OUT", True)
    sh.text(243.0, ly + 8.0, "ㄴ형 = 목찬넬 (손잡이, 기본값)", 2.2, "k", "l")
    sh.rect(232.0, ly + 12.2, 235.0, ly + 17.0, "OUT")
    sh.text(243.0, ly + 16.2, "얇은 사각 = 도어 20T (전면)", 2.2, "k", "l")
    sh.text(232.0, ly + 23.0, "파랑 치수 : 25 = 천판 하단~도어 상단", 2.0, "b", "l")
    sh.text(232.0, ly + 27.0, "60 = 찬넬 높이 / 40 = 도어 뒷면~찬넬 뒷면 / 20 = 도어", 2.0, "b", "l")
    sh.text(232.0, ly + 31.0, "손 진입 : 도어 위 25 틈 -> 도어 뒤 찬넬 홈", 2.0, "b", "l")
    _g.__exit__(None, None, None)
    return sh


TABLE_ROWS = [
    ("상판 이음", "1,800 위치 2분할, 시공 이음 (추정)", "상판 제작사와 이음 위치 협의"),
    ("싱크 컷·수전 홀", "850*450 R25, 수전 Φ35 (좌 2,628 / 앞 94)", "싱크볼·수전 제품 도면으로 대조"),
    ("상판 하부 보강대", "60*18, 컷 좌우·앞뒤 (추정)", "상판 사양(석재 두께) 확인 후 확정"),
    ("식기세척기", "제품 W598*H815*D572 / 설치 W600, H820, 상 45, 후 49", "모델 확정 후 제품 설치도 대조"),
    ("쿡탑", "4구 W590*D520 JJ-HI01, 위치 미상", "설치 위치·컷 치수 도면 확인"),
    ("로봇청소기 수납", "서랍 앞판 H140 (715~855), 내부 여유 미정", "기기 규격 확인"),
    ("서랍 레일", "좌우 13 여유, 싱크면 L500 / 서랍면 L400", "레일 제품 규격 확인"),
    ("전판 높이·간격", "서랍 363 x 2단, 단간 25(찬넬 틈), 걸레받이 위 4, 상단 = 천판 하단 25 아래", "설계 확정 후 재단도 반영"),
    ("목찬넬(손잡이)", "60*40, 전판 상단, 상판 하단 25 이격 (기본값)", "손잡이 사양 확인(샘플 11~13쪽 참조)"),
    ("EP 20T 위치", "서랍면 좌단, 싱크면 좌단(326 후퇴), 우단 전체, 천판", "원본 EP 지시(`EP 판넬 [20T]`)와 위치 대조"),
    ("뒷판·후면 마감", "등 맞댐 면 뒷판 9T (추정)", "후면 마감 사양 확인"),
    ("선반", "18T, 싱크면 높이 500 / OPEN 357, 핀 96 간격", "선반 위치 확정"),
    ("콘센트·배선 타공", "Φ60~80, 위치 미정", "전기 도면 확인"),
    ("도어 재질·색상", "목림 지정 자재 / 안도크림 색상 (샘플 문구)", "지정 자재 확인"),
    ("단면 절단 위치", "단면 1 : X=2,300 / 단면 2 : X=2,900 (추정)", "제작 협의 후 확정"),
    ("방 평면", "5,200 x 3,400, 출입구 위치 가정", "현장 실측"),
]


def wrap(text, size, width):
    out, cur = [], ""
    for ch in text:
        if tw(cur + ch, size) > width and cur:
            out.append(cur); cur = ch
        else:
            cur += ch
    out.append(cur)
    return out


def page_table(m):
    sh = Sheet("table"); sh.den = SCALE_DEN
    sh.rect(4.5, 3.2, 415.5, 293.9, "FR")
    sh.text(17.0, 21.0, "생산 확인표", 8.5)
    sh.text(19.0, 277.0, SITE_LOCATION, 4.9)
    sh.text(19.0, 286.4, f"{FURNITURE_NAME} 생산 확인표 (추정값 확인 필요)", 4.9)
    cols = [(15.0, 14.0, "번호"), (29.0, 62.0, "항목"), (91.0, 170.0, "현재 가정값"), (261.0, 140.0, "확인 방법")]
    y0, hh, rh = 34.0, 9.0, 12.4
    xe = 401.0
    sh.rect(15.0, y0, xe, y0 + hh + rh * len(TABLE_ROWS), "SEC")
    sh.fill([(15.0, y0), (xe, y0), (xe, y0 + hh), (15.0, y0 + hh)], (85, 85, 85))
    for (x, w, t) in cols:
        sh.text(x + 2.0, y0 + 6.2, t, 3.6, "w", "l")
    for (x, w, t) in cols[1:]:
        sh.line(x, y0, x, y0 + hh + rh * len(TABLE_ROWS), "FR")
    for i, (a, b, c) in enumerate(TABLE_ROWS):
        y = y0 + hh + i * rh
        sh.line(15.0, y + rh, xe, y + rh, "FR") if i < len(TABLE_ROWS) - 1 else None
        sh.text(cols[0][0] + 7.0, y + 7.4, str(i + 1), 3.4, "k", "c")
        for (x, w, _t), txt, col in ((cols[1], a, "k"), (cols[2], b, "r"), (cols[3], c, "b")):
            lines = wrap(txt, 3.3, w - 4.0)
            for j, ln in enumerate(lines[:2]):
                sh.text(x + 2.0, y + 5.4 + j * 4.4 - (2.0 if len(lines) > 1 else -1.0), ln, 3.3, col, "l")
    return sh


# ----------------------------------------------------------------- 렌더러
def render_pdf(sheets, path):
    c = canvas.Canvas(path, pagesize=(PW * 72 / 25.4, PH * 72 / 25.4))
    c.setTitle("test_sheet")
    mm = 72 / 25.4
    for sh in sheets:
        for it in sh.items:
            k = it[0]
            if k == "L":
                _, x1, y1, x2, y2, st = it
                _pen(c, st); c.line(x1 * mm, (PH - y1) * mm, x2 * mm, (PH - y2) * mm)
            elif k == "P":
                _, pts, st, cl = it
                _pen(c, st)
                p = c.beginPath(); p.moveTo(pts[0][0] * mm, (PH - pts[0][1]) * mm)
                for x, y in pts[1:]:
                    p.lineTo(x * mm, (PH - y) * mm)
                if cl:
                    p.close()
                c.drawPath(p, stroke=1, fill=0)
            elif k == "H":
                _, pts, st, step = it
                _pen(c, st)
                for (hx1, hy1, hx2, hy2) in hatch_lines(pts, step):
                    c.line(hx1 * mm, (PH - hy1) * mm, hx2 * mm, (PH - hy2) * mm)
            elif k == "C":
                _, cx, cy, r, st = it
                _pen(c, st); c.circle(cx * mm, (PH - cy) * mm, r * mm, stroke=1, fill=0)
            elif k == "F":
                _, pts, col = it
                c.setFillColorRGB(*[v / 255 for v in col])
                p = c.beginPath(); p.moveTo(pts[0][0] * mm, (PH - pts[0][1]) * mm)
                for x, y in pts[1:]:
                    p.lineTo(x * mm, (PH - y) * mm)
                p.close(); c.drawPath(p, stroke=0, fill=1)
            elif k == "T":
                _, x, y, s, size, col, a, rot = it
                c.saveState()
                c.setFillColorRGB(*[v / 255 for v in TXT[col][1]])
                c.setFont("KF", size / PT)
                c.translate(x * mm, (PH - y) * mm)
                if rot:
                    c.rotate(rot)
                if a == "l":
                    c.drawString(0, 0, s)
                elif a == "c":
                    c.drawCentredString(0, 0, s)
                else:
                    c.drawRightString(0, 0, s)
                c.restoreState()
        c.showPage()
    c.save()


def _pen(c, st):
    lay, w, rgb = STY[st]
    c.setStrokeColorRGB(*[v / 255 for v in rgb])
    c.setLineWidth(w)
    c.setLineCap(0); c.setLineJoin(0)


# DXF 색상 매핑: 배경(white/dark/none)별로 선이 잘 보이도록 RGB 를 변환. int = ACI 번호.
_BG = {"white": (255, 255, 255), "dark": (33, 37, 43)}
_MAP = {
    #            white            dark             none(배경 미지정: ACI7 자동 반전 / 밝은 중간색)
    (0, 0, 0):       ((0, 0, 0),       (255, 255, 255), 7),
    (225, 225, 225): ((225, 225, 225), (70, 74, 80),    (200, 200, 200)),
    (255, 255, 255): ((255, 255, 255), (255, 255, 255), (255, 255, 255)),
    (185, 185, 185): ((150, 150, 150), (150, 150, 150), (150, 150, 150)),
    (110, 110, 110): ((90, 90, 90),    (200, 200, 200), (150, 150, 150)),
    (125, 125, 125): ((110, 110, 110), (190, 190, 190), (150, 150, 150)),
    (170, 170, 170): ((165, 165, 165), (120, 120, 120), (130, 130, 130)),
    (85, 85, 85):    ((85, 85, 85),    (140, 140, 140), (130, 130, 130)),
    (0, 0, 255):     ((0, 0, 255),     (80, 160, 255),  (80, 160, 255)),
    (222, 0, 56):    ((222, 0, 56),    1,               1),
}


def dxf_color(rgb, bg):
    idx = {"white": 0, "dark": 1, "none": 2}[bg]
    v = _MAP.get(tuple(rgb), (tuple(rgb),) * 3)[idx]
    return {"color": v} if isinstance(v, int) else {"true_color": ezdxf.colors.rgb2int(v)}


def render_dxf(sheets, path, bg="white", real=True, default_den=None, blocks=True):
    """DXF 출력. real=True(기본): 1 단위 = 1mm 실치수. 시트 도곽·글자·치수 간격·마커를 시트 축척 배수(den)만큼 키워
    모델 공간에 놓으므로 가구 형상은 실제 mm 좌표다. 시트는 X 방향으로 폭의 10% 간격으로 나란히 배치.
    real=False: 예전 방식(종이 mm 좌표, 시트 간격 80).
    blocks=True(기본): 뷰(TOP VIEW/FRONT/SIDE/상세…)·도곽을 이름 있는 BLOCK + INSERT 1개로 낸다(수정은 EXPLODE/REFEDIT).
    해칭은 항상 영역당 HATCH 1개."""
    dens = [((getattr(sh, "den", None) or default_den or SCALE_DEN) if real else 1) for sh in sheets]
    offs, x = [], 0.0
    for k in dens:
        offs.append(x)
        x += PW * k * 1.1 if real else PW + 80.0
    doc = ezdxf.new("R2010", setup=False)
    doc.units = ezdxf.units.MM
    doc.header["$INSUNITS"] = 4
    doc.header["$LWDISPLAY"] = 1
    doc.header["$LTSCALE"] = float(dens[0])
    doc.header["$DIMSCALE"] = float(dens[0])
    doc.header["$LIMMIN"] = (0.0, 0.0)
    doc.header["$LIMMAX"] = (offs[-1] + PW * dens[-1], PH * max(dens))
    doc.header["$EXTMIN"] = (0.0, 0.0, 0.0)
    doc.header["$EXTMAX"] = (offs[-1] + PW * dens[-1], PH * max(dens) + 10 * max(dens), 0.0)
    doc.styles.add("MALGUN", font=DXF_FONT_FILE)
    layer_rgb = {}
    for st, (lay, w, rgb) in STY.items():
        layer_rgb.setdefault(lay, (rgb, w))
        if w > layer_rgb[lay][1]:
            layer_rgb[lay] = (layer_rgb[lay][0], w)
    layer_rgb["TEXT"] = ((0, 0, 0), 0.36)
    if bg in _BG:
        L = doc.layers.add("BG"); L.color = 7; L.dxf.lineweight = 0
    for lay in LAYER_ORDER:
        rgb, w = layer_rgb[lay]
        L = doc.layers.add(lay)
        c = dxf_color(rgb, bg)
        if "color" in c:
            L.color = c["color"]
        else:
            L.rgb = ezdxf.colors.int2rgb(c["true_color"])
        L.dxf.lineweight = min(DXF_LW, key=lambda q: abs(q - w * PT * 100))
    doc.layers.add("SHEET_FRAME_INFO").color = 8
    msp = doc.modelspace()
    k0 = dens[0]
    doc.set_modelspace_vport(height=PH * k0 * 1.1, center=(PW * k0 / 2, PH * k0 / 2))     # 첫 시트 전체가 보이게
    if bg in _BG:                                       # 맨 뒤 배경(시트 크기 SOLID 채움)
        for i, k in enumerate(dens):
            ox = offs[i]
            h = msp.add_hatch(dxfattribs={"layer": "BG", "true_color": ezdxf.colors.rgb2int(_BG[bg])})
            h.set_solid_fill()
            h.paths.add_polyline_path([(ox, 0), (ox + PW * k, 0), (ox + PW * k, PH * k), (ox, PH * k)], is_closed=True)
    def draw_item(tgt, it, Xf, Yf, kk):
        k = it[0]
        if k == "L":
            _, x1, y1, x2, y2, st = it
            tgt.add_line((Xf(x1), Yf(y1)), (Xf(x2), Yf(y2)), dxfattribs=_attr(st, bg))
        elif k == "P":
            _, pts, st, cl = it
            tgt.add_lwpolyline([(Xf(x), Yf(y)) for x, y in pts], close=cl, dxfattribs=_attr(st, bg))
        elif k == "C":
            _, cx, cy, r, st = it
            tgt.add_circle((Xf(cx), Yf(cy)), r * kk, dxfattribs=_attr(st, bg))
        elif k == "H":                                   # 해칭 영역마다 HATCH 1개(ANSI31). 패턴 배율 = 간격 x 시트 배수
            _, pts, st, step = it
            h = tgt.add_hatch(dxfattribs=_attr(st, bg))
            h.set_pattern_fill("ANSI31", scale=max(step * kk / 3.175 / 0.70710678, 1e-6), angle=0)
            h.paths.add_polyline_path([(Xf(x), Yf(y)) for x, y in pts], is_closed=True)
        elif k == "F":
            _, pts, col = it
            at = {"layer": "FRAME" if col == (85, 85, 85) else "OUTLINE"}
            at.update(dxf_color(col, bg))
            h = tgt.add_hatch(dxfattribs=at)
            h.set_solid_fill(); h.paths.add_polyline_path([(Xf(x), Yf(y)) for x, y in pts], is_closed=True)
        elif k == "T":
            _, x, y, s, size, col, a, rot = it
            lay, rgb = TXT[col]
            at = {"layer": lay, "style": "MALGUN"}
            at.update(dxf_color(rgb, bg))
            t = tgt.add_text(s, height=size * 0.72 * kk, rotation=rot, dxfattribs=at)
            al = {"l": TextEntityAlignment.BOTTOM_LEFT, "c": TextEntityAlignment.BOTTOM_CENTER, "r": TextEntityAlignment.BOTTOM_RIGHT}[a]
            t.set_placement((Xf(x), Yf(y)), align=al)

    for i, sh in enumerate(sheets):
        ox = offs[i]; kk = dens[i]
        Yf = lambda y: (PH - y) * kk
        if blocks:
            # 뷰마다 이름 있는 BLOCK(좌표는 시트 원점 기준 실치수 mm) + 시트 원점에 INSERT 1개. 도곽/표제란 = FRAME_SHEET{n}
            Xl = lambda x: x * kk
            by_name = {}
            for it, g in zip(sh.items, sh.groups):
                by_name.setdefault(g, []).append(it)
            for g, its in by_name.items():
                name = f"FRAME_SHEET{i + 1}" if g is None else f"{g}_S{i + 1}"
                blk = doc.blocks.new(name=name)
                for it in its:
                    draw_item(blk, it, Xl, Yf, kk)
                msp.add_blockref(name, (ox, 0), dxfattribs={"layer": "0"})
        else:
            Xf = lambda x: ox + x * kk
            for it in sh.items:
                draw_item(msp, it, Xf, Yf, kk)
        at = {"layer": "SHEET_FRAME_INFO", "style": "MALGUN"}
        label = f"[{i + 1}] {sh.name}" + (f"  (1/{kk}, 1:1 실치수)" if real else "")
        msp.add_text(label, height=5 * kk, dxfattribs=at).set_placement((ox + 4.5 * kk, (PH + 4) * kk), align=TextEntityAlignment.BOTTOM_LEFT)
    ext_w = offs[-1] + PW * dens[-1]
    msp.reset_extents((0.0, 0.0, 0.0), (ext_w, PH * max(dens) + 10 * max(dens), 0.0))   # $EXTMIN/$EXTMAX
    msp.reset_limits((0.0, 0.0), (ext_w, PH * max(dens)))                                # $LIMMIN/$LIMMAX
    doc.saveas(path)


def _attr(st, bg="white"):
    lay, w, rgb = STY[st]
    lw = min(DXF_LW, key=lambda q: abs(q - w * PT * 100))
    a = {"layer": lay, "lineweight": lw}
    a.update(dxf_color(rgb, bg))
    return a


def build_sheets(m):
    return [page_floor(m, 20),
            page_b(m, SCALE_DEN, "NO.001", FURNITURE_NAME),
            page_a(m, SCALE_DEN, "NO.002", FURNITURE_NAME),
            page_side(m, SCALE_DEN, "NO.003", FURNITURE_NAME),
            page_detail(m, SCALE_DEN, "NO.004", FURNITURE_NAME),
            page_table(m)]


def main():
    global FURNITURE_NAME, SITE_LOCATION, SCALE_DEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default=os.path.join(os.path.dirname(__file__), "..", "..", "output_samples", "furniture.json"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "output_samples"))
    ap.add_argument("--name", default=None)
    ap.add_argument("--site", default=None)
    ap.add_argument("--scale", type=int, default=None)
    ap.add_argument("--font", default=None)
    ap.add_argument("--no-blocks", action="store_true", help="뷰를 BLOCK 으로 묶지 않고 낱개 엔티티로 출력 (기본: 뷰/도곽을 이름 있는 BLOCK+INSERT)")
    ap.add_argument("--paper", action="store_true", help="DXF 를 예전 종이 mm 좌표(축소)로 출력 (기본: 1:1 실치수)")
    ap.add_argument("--dxf-bg", choices=["none", "white", "dark"], default="white",
                    help="DXF 배경: white(기본, 흰 종이+검정 선) / dark(어두운 배경+밝은 선) / none(배경 없음, 검정=ACI7 자동 반전)")
    a = ap.parse_args()
    data = json.load(open(a.json, encoding="utf-8"))
    FURNITURE_NAME = a.name or data.get("furniture_name") or FURNITURE_NAME
    SITE_LOCATION = a.site or data.get("site") or SITE_LOCATION
    SCALE_DEN = a.scale or SCALE_DEN
    setup_font(a.font)
    m = Model(data)
    sheets = build_sheets(m)
    os.makedirs(a.out, exist_ok=True)
    render_pdf(sheets, os.path.join(a.out, "test_sheet.pdf"))
    render_dxf(sheets, os.path.join(a.out, "test_sheet.dxf"), a.dxf_bg, real=not a.paper, blocks=not a.no_blocks)
    if a.dxf_bg == "white":                                   # 어두운 CAD 테마용 보조 파일
        render_dxf(sheets, os.path.join(a.out, "test_sheet_dark.dxf"), "dark", real=not a.paper, blocks=not a.no_blocks)
    print("font:", FONT_USED["path"], "| name:", FURNITURE_NAME, "| scale 1/%d" % SCALE_DEN, "| pages", len(sheets))


if __name__ == "__main__":
    main()
