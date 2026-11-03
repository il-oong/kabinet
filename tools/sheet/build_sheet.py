#!/usr/bin/env python3
"""입력 가구 데이터(furniture.json) -> '우리 양식' A3 제작도면 PDF(reportlab) + DXF(ezdxf).

하나의 레이아웃 모델(Sheet.items: 시트 좌표 mm, 좌상단 원점, y 아래로)을 만들고
PDF / DXF 렌더러가 같은 모델을 그린다.  양식 좌표는 SHEET_FORMAT_ANALYSIS.md §2~§8 기준.

실행:  python3 -I tools/sheet/build_sheet.py --json output_samples/furniture.json --out output_samples
       (옵션) --name 가구명  --site 현장명  --scale 25  --font C:/Windows/Fonts/malgun.ttf
"""
import argparse, datetime, json, math, os, sys

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

    def line(self, x1, y1, x2, y2, st="OUT"):
        self.items.append(("L", x1, y1, x2, y2, st))

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

    def poly(self, pts, st="OUT", closed=False):
        self.items.append(("P", list(pts), st, closed))

    def rect(self, x1, y1, x2, y2, st="OUT"):
        self.poly([(x1, y1), (x2, y1), (x2, y2), (x1, y2)], st, True)

    def circ(self, cx, cy, r, st="OUT"):
        self.items.append(("C", cx, cy, r, st))

    def fill(self, pts, color):
        self.items.append(("F", list(pts), color))

    def text(self, x, y, s, size=2.4, c="k", a="l", rot=0):
        if s:
            self.items.append(("T", x, y, s, size, c, a, rot))

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
        k = x1 + y1
        while k < x2 + y2:
            lo, hi = max(x1, k - y2), min(x2, k - y1)
            if hi - lo > 0.05:
                self.line(lo, k - lo, hi, k - hi, st)
            k += step


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


SHORT = {"서랍장(2단)M": "서랍장\n(2단)M", "장(2단)": "장\n(2단)", "조리장(1D)L/R": "조리장\n(1D)L/R",
         "식기세척기 M": "식기\n세척기 M", "조리장(1D)L/R (싱크)": "조리장\n(1D)L/R", "로봇청소기서랍장(1D)L/R": "로봇청소기\n서랍장(1D)",
         "OPEN(EP 판넬/벽장용 20T)": "OPEN"}


def draw_plan(sh, m, ox, oy, s, labels=True, size=1.8):
    """평면(TOP VIEW). plan x: 좌->우, y: 0=싱크면(B) 앞 -> D=서랍면(A) 앞."""
    X = lambda x: ox + x * s
    Y = lambda y: oy + y * s
    # 몸통(숨은선) — 카운터 아래
    for md in m.bm:
        sh.rect(X(md["x"]), Y(0), X(md["x"] + md["w"]), Y(m.dB), "THIN")
        if labels:
            for k, ln in enumerate(SHORT.get(md["name"], md["name"]).split("\n")):
                nl = SHORT.get(md["name"], md["name"]).count("\n") + 1
                sh.text(X(md["x"] + md["w"] / 2), Y(m.dB / 2) + (k - (nl - 1) / 2) * size * 1.2 + size * 0.35, ln, size, "g", "c")
    for md in m.ab:
        sh.rect(X(md["x"]), Y(m.dB), X(md["x"] + md["w"]), Y(m.D), "THIN")
        if labels:
            for k, ln in enumerate(SHORT.get(md["name"], md["name"]).split("\n")):
                nl = SHORT.get(md["name"], md["name"]).count("\n") + 1
                sh.text(X(md["x"] + md["w"] / 2), Y(m.dB + m.dA / 2) + (k - (nl - 1) / 2) * size * 1.2 + size * 0.35, ln, size, "g", "c")
    # 상판
    sh.rect(X(0), Y(0), X(m.W), Y(m.D), "OUT")
    sh.line(X(m.W / 2), Y(0), X(m.W / 2), Y(m.D), "THIN")
    sx, sy, sw, sd, sr = m.sink
    sh.rrect(X(sx), Y(sy), X(sx + sw), Y(sy + sd), max(sr * s, 0.4), "OUT")
    sh.circ(X(sx + sw / 2), Y(sy / 2 + 15), max(35 * s, 0.7), "OUT")     # 수전
    return X, Y


def plan_dims(sh, m, ox, oy, s):
    X = lambda x: ox + x * s
    # 상단: 모듈 + 전체
    edges = [0, m.ovl] + [md["x"] + md["w"] for md in m.bm]
    dim_h(sh, [X(e) for e in edges], oy - 5.5, [fmt(b - a) for a, b in zip(edges, edges[1:])], ref=oy)
    dim_h(sh, [X(0), X(m.W)], oy - 11.5, [fmt(m.W)], ref=oy)
    # 하단: 서랍면 베이
    ed = [0] + [m.ab[0]["x"]] + [b["x"] + b["w"] for b in m.ab] + [m.W]
    ed = sorted(set(ed))
    dim_h(sh, [X(e) for e in ed], oy + m.D * s + 5.5, [fmt(b - a) for a, b in zip(ed, ed[1:])], ref=oy + m.D * s)
    # 좌측: 깊이
    dim_v(sh, ox - 5.5, [oy, oy + m.dB * s, oy + m.D * s], [fmt(m.dB), fmt(m.dA)], ref=ox)
    dim_v(sh, ox - 11.5, [oy, oy + m.D * s], [fmt(m.D)], ref=ox)


def draw_keyplan(sh, m, face, x0=12.0, y0=19.5, w=26.0):
    """키 플랜 썸네일: 작은 평면 + 빨간 삼각형(보는 방향)."""
    rd = m.d["room_assumed"]
    s = w / rd["W"]
    h = rd["D"] * s
    sh.rect(x0, y0, x0 + w, y0 + h, "OUT")
    wt = 150 * s
    sh.rect(x0 + wt, y0 + wt, x0 + w - wt, y0 + h - wt, "THIN")
    ix = x0 + (rd["W"] - m.W) / 2 * s
    iy = y0 + 1100 * s * 1.0
    sh.rect(ix, iy, ix + m.W * s, iy + m.D * s, "OUT")
    cx = ix + m.W * s / 2
    if face == "B":
        sh.fill([(cx - 1.6, iy - 3.4), (cx + 1.6, iy - 3.4), (cx, iy - 0.6)], (222, 0, 56))
    else:
        sh.fill([(cx - 1.6, iy + m.D * s + 3.4), (cx + 1.6, iy + m.D * s + 3.4), (cx, iy + m.D * s + 0.6)], (222, 0, 56))


def faucet(sh, X, Z, xc, ztop=1020, hgt=230):
    pts = [(X(xc), Z(ztop)), (X(xc), Z(ztop + hgt - 40))]
    for k in range(1, 9):
        a = math.radians(180 - 90 * k / 8)
        pts.append((X(xc) + 0.0 + (1 - math.cos(math.radians(90 * k / 8))) * -1 * 0 + 0, 0))
    pts = [(X(xc), Z(ztop)), (X(xc), Z(ztop + hgt - 60))]
    r = 60
    for k in range(0, 9):
        a = math.radians(180 - 90 * k / 8)
        pts.append((X(xc + r + r * math.cos(a)), Z(ztop + hgt - 60 - 0 + r * math.sin(a))))
    pts.append((X(xc + 2 * r), Z(ztop + hgt - 140)))
    sh.poly(pts, "THIN")


# ----------------------------------------------------------------- 정면도
def b_view_modules(m):
    """B면 정면(싱크면에서 본 모습)은 평면 x 가 좌우 반전."""
    out = []
    for md in m.bm:
        out.append(dict(md, vx=m.W - (md["x"] + md["w"])))
    return sorted(out, key=lambda a: a["vx"])


def elev_frame(sh, m, ox, gy, s, ovl_left=True):
    """카운터 + 걸레받이 틀. ox = 뷰 좌측, gy = 바닥선 y."""
    X = lambda x: ox + x * s
    Z = lambda z: gy - z * s
    sh.rect(X(0), Z(m.H), X(m.W), Z(m.body_H), "OUT")        # 상판
    sh.line(X(m.W / 2), Z(m.H), X(m.W / 2), Z(m.body_H), "THIN")
    return X, Z


def elev_dims(sh, m, X, Z, xs_edges, labels, ox, s, right_x):
    top = Z(m.H)
    dim_h(sh, [X(e) for e in xs_edges], top - 11.0 if True else top, labels, ref=top - 0.0)
    dim_h(sh, [X(0), X(m.W)], top - 17.0, [fmt(m.W)], ref=top)
    dim_v(sh, X(0) - 6.0, [Z(m.body_H), Z(0)], [fmt(m.body_H)], ref=X(0))
    dim_v(sh, X(0) - 12.0, [Z(m.H), Z(0)], [fmt(m.H)], ref=X(0))
    dim_v(sh, X(m.W) + 6.0, [Z(m.H), Z(m.body_H), Z(m.kick), Z(0)], [fmt(m.top_t), fmt(m.body_H - m.kick), fmt(m.kick)], ref=X(m.W), side=1)


def draw_b_door(sh, m, ox, gy, s):
    X, Z = elev_frame(sh, m, ox, gy, s)
    mods = b_view_modules(m)
    bodyW = m.W - m.ovl
    k, h = m.kick, m.body_H
    sh.rect(X(0), Z(h), X(bodyW), Z(k), "OUT")
    sh.line(X(0), Z(k), X(bodyW), Z(k), "OUT")
    sh.rect(X(10), Z(k), X(bodyW - 10), Z(0), "OUT")        # 걸레받이
    for md in mods:
        x0, w, t = md["vx"], md["w"], md["type"]
        if x0 > 0:
            sh.line(X(x0), Z(k), X(x0), Z(h), "OUT")
        cx = X(x0 + w / 2)
        if t == "robot":
            sh.line(X(x0), Z(710), X(x0 + w), Z(710), "OUT")
            sh.text(cx, Z(805) + 0.7, "서랍", 2.0, "g", "c")
            _hinge(sh, X, Z, x0, w, k, 710)
        elif t in ("door", "door_sink"):
            _hinge(sh, X, Z, x0, w, k, h)
        elif t == "dishwasher":
            sh.text(cx, Z(500) + 0.7, "식기세척기", 2.2, "k", "c")
            sh.line(X(x0 + 80), Z(820), X(x0 + w - 80), Z(820), "OUT")
        elif t == "cabinet":
            sh.line(X(x0), Z(500), X(x0 + w), Z(500), "OUT")
            _hinge(sh, X, Z, x0, w, k, 500)
            _hinge(sh, X, Z, x0, w, 500, h)
        elif t == "drawer2":
            sh.line(X(x0), Z(500), X(x0 + w), Z(500), "OUT")
            for z in (300, 700):
                sh.line(X(x0 + w / 2 - 150), Z(z + 150 if z == 700 else z + 150), X(x0 + w / 2 + 150), Z(z + 150), "THIN")
            sh.text(cx, Z(300), "서랍(2단)", 2.0, "g", "c")
    faucet(sh, X, Z, mods_sink_vx(m) + 425)
    return X, Z


def mods_sink_vx(m):
    sx, sy, sw, sd, sr = m.sink
    return m.W - (sx + sw)


def _hinge(sh, X, Z, x0, w, z0, z1):
    """도어 열림 표기: 힌지측(좌) 모서리 -> 손잡이측 중간 사선(점선)."""
    zm = (z0 + z1) / 2
    sh.dashed(X(x0 + 8), Z(z0 + 8), X(x0 + w - 8), Z(zm), "THIN")
    sh.dashed(X(x0 + 8), Z(z1 - 8), X(x0 + w - 8), Z(zm), "THIN")
    sh.line(X(x0 + w - 40), Z(zm - 60), X(x0 + w - 40), Z(zm + 60), "OUT")        # 손잡이


def draw_b_body(sh, m, ox, gy, s):
    X, Z = elev_frame(sh, m, ox, gy, s)
    mods = b_view_modules(m)
    bodyW = m.W - m.ovl
    k, h = m.kick, m.body_H
    sh.rect(X(0), Z(h), X(bodyW), Z(k), "OUT")
    sh.rect(X(10), Z(k), X(bodyW - 10), Z(0), "OUT")
    for md in mods:
        x0, w, t = md["vx"], md["w"], md["type"]
        if x0 > 0:
            sh.line(X(x0), Z(k), X(x0), Z(h), "OUT")
        cx = X(x0 + w / 2)
        if t == "robot":
            sh.rect(X(x0 + 20), Z(900 - 10), X(x0 + w - 20), Z(710 + 10), "THIN")
            sh.line(X(x0 + 20), Z(450), X(x0 + w - 20), Z(450), "THIN")
            sh.text(cx, Z(600), "로봇청소기", 2.0, "b", "c")
        elif t == "door":
            sh.line(X(x0 + 20), Z(500), X(x0 + w - 20), Z(500), "THIN")
            sh.text(cx, Z(250) + 0.7, "선반", 1.8, "g", "c")
        elif t == "door_sink":
            sh.text(cx, Z(500) + 0.7, "싱크 하부", 2.0, "b", "c")
            sh.dashed(X(x0 + 40), Z(700), X(x0 + w - 40), Z(700), "BLUE")
        elif t == "dishwasher":
            sh.rect(X(x0 + 7), Z(880), X(x0 + 607), Z(k + 5), "THIN")
            sh.text(cx, Z(500), "식기세척기 W600", 2.0, "r", "c")
            sh.text(cx, Z(500) - 2.6, "(확인필요)", 1.8, "r", "c")
        elif t == "cabinet":
            sh.line(X(x0 + 20), Z(500), X(x0 + w - 20), Z(500), "THIN")
        elif t == "drawer2":
            for z0, z1 in ((k + 10, 490), (510, h - 10)):
                sh.rect(X(x0 + 20), Z(z1), X(x0 + w - 20), Z(z0), "THIN")
    return X, Z


def draw_a_elev(sh, m, ox, gy, s, body=False):
    """A면(서랍면) 정면: 평면 x 그대로."""
    X, Z = elev_frame(sh, m, ox, gy, s)
    k, h = m.kick, m.body_H
    sh.rect(X(0), Z(h), X(m.W), Z(k), "OUT")
    sh.rect(X(30), Z(k), X(m.W - 30), Z(0), "OUT")
    for md in m.ab:
        x0, w, t = md["x"], md["w"], md["type"]
        sh.line(X(x0), Z(k), X(x0), Z(h), "OUT")
        cx = X(x0 + w / 2)
        if t == "open":
            sh.line(X(x0), Z(k + md["shelf_h"]), X(x0 + w), Z(k + md["shelf_h"]), "THIN")
            sh.text(cx, Z(650), "OPEN", 2.2, "g", "c")
            sh.text(cx, Z(k + md["shelf_h"] / 2), "(선반 추정)", 1.8, "g", "c")
        else:
            sh.line(X(x0), Z(500), X(x0 + w), Z(500), "OUT")
            for zc in (300, 700):
                sh.line(X(x0 + w / 2 - 150), Z(zc + 150), X(x0 + w / 2 + 150), Z(zc + 150), "THIN")
            sh.text(cx, Z(300), "서랍(2단)", 2.0, "g", "c")
    sh.line(X(m.W), Z(k), X(m.W), Z(h), "OUT")
    sh.rect(X(0), Z(h), X(20), Z(k), "OUT")        # EP 판넬 20T
    return X, Z


def a_dims(sh, m, X, Z, ox, s):
    top = Z(m.H)
    ed = sorted(set([0, 20] + [b["x"] + b["w"] for b in m.ab] + [m.W]))
    dim_h(sh, [X(e) for e in ed], top - 11.0, [fmt(b - a) for a, b in zip(ed, ed[1:])], ref=top)
    dim_h(sh, [X(0), X(m.W)], top - 17.0, [fmt(m.W)], ref=top)
    dim_v(sh, X(0) - 6.0, [Z(m.body_H), Z(0)], [fmt(m.body_H)], ref=X(0))
    dim_v(sh, X(0) - 12.0, [Z(m.H), Z(0)], [fmt(m.H)], ref=X(0))
    dim_v(sh, X(m.W) + 6.0, [Z(m.H), Z(m.body_H), Z(m.kick), Z(0)], [fmt(m.top_t), fmt(m.body_H - m.kick), fmt(m.kick)], ref=X(m.W), side=1)


# ----------------------------------------------------------------- 측면도 (단면)
def draw_side(sh, m, ox, gy, s):
    X = lambda x: ox + x * s
    Z = lambda z: gy - z * s
    k, h, tt = m.kick, m.body_H, m.top_t
    sh.rect(X(0), Z(m.H), X(m.D), Z(h), "OUT")                   # 상판
    sh.rect(X(0), Z(h), X(m.D), Z(k), "OUT")                      # 몸통
    sh.rect(X(60), Z(k), X(m.D - 60), Z(0), "OUT")                # 걸레받이(60 들임)
    sh.line(X(m.dB), Z(k), X(m.dB), Z(h), "OUT")                  # B/A 경계 측판
    sh.rect(X(0), Z(h - 15), X(20), Z(k), "THIN")                 # 도어 두께
    sh.rect(X(m.D - 20), Z(h - 15), X(m.D), Z(k), "THIN")
    sx, sy, sw, sd, sr = m.sink
    sh.dashed(X(sy), Z(h), X(sy), Z(h - 200), "THIN")             # 싱크볼
    sh.dashed(X(sy + sd), Z(h), X(sy + sd), Z(h - 200), "THIN")
    sh.dashed(X(sy), Z(h - 200), X(sy + sd), Z(h - 200), "THIN")
    faucet(sh, X, Z, sy + sd + 40, ztop=m.H, hgt=230)
    sh.rect(X(m.dB + 20), Z(h - 10), X(m.D - 20), Z(h - 10 - 380), "THIN")   # 서랍면 서랍 박스(추정)
    sh.rect(X(m.dB + 20), Z(h - 10 - 400), X(m.D - 20), Z(k + 10), "THIN")
    sh.text(X(m.dB / 2), Z(450), "싱크면 650", 2.2, "g", "c")
    sh.text(X(m.dB + m.dA / 2), Z(910 - 400 - 5) , "", 2.2, "g", "c")
    top = Z(m.H)
    dim_h(sh, [X(0), X(sy), X(sy + sd), X(m.D)], top - 6.0, [fmt(sy), fmt(sd), fmt(m.D - sy - sd)], ref=top)
    dim_h(sh, [X(0), X(m.D)], top - 12.0, [fmt(m.D)], ref=top)
    dim_h(sh, [X(0), X(m.dB), X(m.D)], Z(0) + 6.0, [fmt(m.dB), fmt(m.dA)], ref=Z(0))
    dim_v(sh, X(0) - 6.0, [Z(h), Z(0)], [fmt(h)], ref=X(0))
    dim_v(sh, X(0) - 12.0, [Z(m.H), Z(0)], [fmt(m.H)], ref=X(0))
    dim_v(sh, X(m.D) + 6.0, [Z(m.H), Z(h), Z(k), Z(0)], [fmt(tt), fmt(h - k), fmt(k)], ref=X(m.D), side=1)
    return X, Z


# ----------------------------------------------------------------- NOTE
def note_block(sh, d, face):
    n = d["note"]
    sh.text(218.3, 26.6, "DOOR : " + n["DOOR"], 3.9)
    sh.text(218.3, 38.6, "BODY : " + n["BODY"], 3.9)
    sh.text(218.3, 50.6, "손잡이 : " + n["handle"], 3.9, "r")
    y = 61.5
    lines = [("*싱크볼 컷 W850*D450 (상판 시트 판독, 추정)", "r"),
             ("*식기세척기 W600 빌트인 (확인필요)", "r"),
             ("*쿡탑 : 스트로만 후드일체형 4구 JJ-HI01 (위치 확인필요)", "r"),
             ("*상판 1,800 x 2분할 T120 / 싱크면 650 · 서랍면 450", "k"),
             ("*도어 : 주방장 도어 공용 부엌 도어 - KK DR 112", "k")]
    if face == "A":
        lines.append(("*서랍장(2단)M x3 / OPEN 1 (서랍 단 높이 추정)", "k"))
    for s_, c in lines:
        sh.text(218.3, y, s_, 3.5, c)
        y += 7.4


# ----------------------------------------------------------------- 페이지 조립
def page_floor(m, scale_den):
    sh = Sheet("floor")
    rd = m.d["room_assumed"]
    plan_frame(sh, rd["name"], f"{rd['name']} 아일랜드 평면도", scale_den)
    s = 1.0 / scale_den
    wt = 150
    ox, oy = 62.0, 62.0                      # 실 내부 좌상단(시트 mm)
    RW, RD = rd["W"], rd["D"]
    X = lambda x: ox + x * s
    Y = lambda y: oy + y * s
    # 벽 띠 (좌측벽은 출입구 개구부 900 포함)
    sh.rect(X(-wt), Y(-wt), X(RW + wt), Y(0), "OUT"); sh.hatch_rect(X(-wt), Y(-wt), X(RW + wt), Y(0))
    sh.rect(X(-wt), Y(RD), X(RW + wt), Y(RD + wt), "OUT"); sh.hatch_rect(X(-wt), Y(RD), X(RW + wt), Y(RD + wt))
    sh.rect(X(RW), Y(0), X(RW + wt), Y(RD), "OUT"); sh.hatch_rect(X(RW), Y(0), X(RW + wt), Y(RD))
    o0, o1 = 2300, 3200
    sh.rect(X(-wt), Y(0), X(0), Y(o0), "OUT"); sh.hatch_rect(X(-wt), Y(0), X(0), Y(o0))
    sh.rect(X(-wt), Y(o1), X(0), Y(RD), "OUT"); sh.hatch_rect(X(-wt), Y(o1), X(0), Y(RD))
    sh.line(X(0), Y(o0), X(0), Y(o1), "THIN")
    sh.line(X(-wt), Y(o0), X(-wt), Y(o1), "THIN")
    # 문(회전 호 R900)
    sh.line(X(-wt), Y(o0), X(-wt - 900), Y(o0), "OUT") if False else None
    sh.line(X(0), Y(o0), X(900), Y(o0), "OUT")
    sh.arc(X(0), Y(o1), 900 * s, -90, 0, "THIN", 18) if False else sh.arc(X(0), Y(o0), 900 * s, 0, 90, "THIN", 18)
    # 아일랜드
    ix, iy = (RW - m.W) / 2, 1100
    px, py = plan_xy = draw_plan(sh, m, X(ix), Y(iy), s, True, 2.1)
    Xi = lambda x: X(ix) + x * s
    edges = [0, m.ovl] + [md["x"] + md["w"] for md in m.bm]
    dim_h(sh, [Xi(e) for e in edges], Y(iy) - 4.5, [fmt(b - a) for a, b in zip(edges, edges[1:])], ref=Y(iy))
    dim_h(sh, [Xi(0), Xi(m.W)], Y(iy) - 10.0, [fmt(m.W)], ref=Y(iy))
    dim_v(sh, Xi(0) - 5.0, [Y(iy), Y(iy + m.D)], [fmt(m.D)], ref=Xi(0))
    # 실 치수
    dim_h(sh, [X(0), X(RW)], Y(-wt) - 6.0, [fmt(RW)], ref=Y(-wt))
    dim_v(sh, X(RW + wt) + 7.0, [Y(0), Y(RD)], [fmt(RD)], ref=X(RW + wt), side=1)
    dim_h(sh, [X(0), Xi(0)], Y(RD) + 8, [fmt(ix)], ref=Y(RD))
    dim_h(sh, [Xi(m.W), X(RW)], Y(RD) + 8, [fmt(RW - ix - m.W)], ref=Y(RD))
    dim_v(sh, X(RW) - 8.0, [Y(0), Y(iy)], [fmt(iy)], ref=X(RW))
    dim_v(sh, X(RW) - 8.0, [Y(iy + m.D), Y(RD)], [fmt(RD - iy - m.D)], ref=X(RW))
    # 방향 마커 (B = 싱크면 위쪽에서 / A = 서랍면 아래쪽에서)
    marker(sh, Xi(m.W / 2), Y(iy) - 22.0, "B", "down")
    marker(sh, Xi(m.W / 2), Y(iy + m.D) + 22.0, "A", "up")
    sh.text(X(RW) - 3, Y(RD) - 3, "※ 실 규격 5,200x3,400 / 출입구 위치는 가정(확인필요)", 2.2, "r", "r")
    return sh


def page_b(m, scale_den, sheet_no, title):
    sh = Sheet("furniture_B")
    furniture_frame(sh, title, "싱크면(B) 정면 / 평면", sheet_no, scale_den, ("TOP VIEW",))
    s = 1.0 / scale_den
    draw_keyplan(sh, m, "B")
    ox, oy = 50.0, 55.0
    draw_plan(sh, m, ox, oy, s)
    plan_dims(sh, m, ox, oy, s)
    marker(sh, ox + m.W * s + 8, oy + 8, "B", "up")
    marker(sh, ox + m.W * s + 8, oy + m.D * s - 8, "A", "down")
    note_block(sh, m.d, "B")
    gy = 222.0
    mods = b_view_modules(m)
    for ox2, fn in ((30.0, draw_b_door), (240.0, draw_b_body)):
        X, Z = fn(sh, m, ox2, gy, s)
        edges = [0] + [md["vx"] + md["w"] for md in mods] + [m.W]
        edges = sorted(set(edges))
        labs = []
        for a, b in zip(edges, edges[1:]):
            labs.append(fmt(b - a))
        elev_dims(sh, m, X, Z, edges, labs, ox2, s, 0)
        marker(sh, X(m.W / 2), gy + 12.0, "B", "up")
    return sh


def page_a(m, scale_den, sheet_no, title):
    sh = Sheet("furniture_A")
    furniture_frame(sh, title, "서랍면(A) 정면 / 측면", sheet_no, scale_den, ("TOP VIEW",), hdr2=("SIDE VIEW", "FRONT VIEW_ DOOR (A면)"))
    s = 1.0 / scale_den
    draw_keyplan(sh, m, "A")
    ox, oy = 50.0, 55.0
    draw_plan(sh, m, ox, oy, s)
    plan_dims(sh, m, ox, oy, s)
    marker(sh, ox + m.W * s + 8, oy + 8, "B", "up")
    marker(sh, ox + m.W * s + 8, oy + m.D * s - 8, "A", "down")
    note_block(sh, m.d, "A")
    gy = 222.0
    # 측면(단면 A-A)
    X, Z = draw_side(sh, m, 80.0, gy, s)
    # 정면 A
    X, Z = draw_a_elev(sh, m, 240.0, gy, s)
    a_dims(sh, m, X, Z, 240.0, s)
    marker(sh, X(m.W / 2), gy + 12.0, "A", "up")
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


def render_dxf(sheets, path):
    doc = ezdxf.new("R2010", setup=False)
    doc.units = ezdxf.units.MM
    doc.header["$INSUNITS"] = 4
    doc.header["$LWDISPLAY"] = 1
    doc.styles.add("MALGUN", font=DXF_FONT_FILE)
    for lay in LAYER_ORDER:
        ent = [v for v in STY.values() if v[0] == lay]
        col = ent[0][2] if ent else TXT["k"][1]
        lw = max(ent, key=lambda v: v[1])[1] if ent else 0.36
        lwv = min(DXF_LW, key=lambda q: abs(q - lw * PT * 100)) if ent else 13
        if lay == "TEXT":
            col = (0, 0, 0)
        L = doc.layers.add(lay)
        L.rgb = col
        L.dxf.lineweight = lwv
    doc.layers.add("SHEET_FRAME_INFO")
    msp = doc.modelspace()
    for i, sh in enumerate(sheets):
        ox = i * (PW + 80.0)
        Xf = lambda x: ox + x
        Yf = lambda y: PH - y
        for it in sh.items:
            k = it[0]
            if k == "L":
                _, x1, y1, x2, y2, st = it
                lay, w, rgb = STY[st]
                msp.add_line((Xf(x1), Yf(y1)), (Xf(x2), Yf(y2)), dxfattribs=_attr(st))
            elif k == "P":
                _, pts, st, cl = it
                msp.add_lwpolyline([(Xf(x), Yf(y)) for x, y in pts], close=cl, dxfattribs=_attr(st))
            elif k == "C":
                _, cx, cy, r, st = it
                msp.add_circle((Xf(cx), Yf(cy)), r, dxfattribs=_attr(st))
            elif k == "F":
                _, pts, col = it
                h = msp.add_hatch(dxfattribs={"layer": "FRAME" if col == (85, 85, 85) else "OUTLINE", "true_color": ezdxf.colors.rgb2int(col)})
                h.set_solid_fill(); h.paths.add_polyline_path([(Xf(x), Yf(y)) for x, y in pts], is_closed=True)
            elif k == "T":
                _, x, y, s, size, col, a, rot = it
                lay, rgb = TXT[col]
                t = msp.add_text(s, height=size * 0.72, rotation=rot,
                                 dxfattribs={"layer": lay, "style": "MALGUN", "true_color": ezdxf.colors.rgb2int(rgb)})
                al = {"l": TextEntityAlignment.BOTTOM_LEFT, "c": TextEntityAlignment.BOTTOM_CENTER, "r": TextEntityAlignment.BOTTOM_RIGHT}[a]
                t.set_placement((Xf(x), Yf(y)), align=al)
        msp.add_text(f"[{sh.name}]", height=3, dxfattribs={"layer": "SHEET_FRAME_INFO", "style": "MALGUN"}).set_placement((ox + 4.5, PH + 4), align=TextEntityAlignment.BOTTOM_LEFT)
    doc.saveas(path)


def _attr(st):
    lay, w, rgb = STY[st]
    lw = min(DXF_LW, key=lambda q: abs(q - w * PT * 100))
    return {"layer": lay, "true_color": ezdxf.colors.rgb2int(rgb), "lineweight": lw}


def main():
    global FURNITURE_NAME, SITE_LOCATION, SCALE_DEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default=os.path.join(os.path.dirname(__file__), "..", "..", "output_samples", "furniture.json"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "output_samples"))
    ap.add_argument("--name", default=None)
    ap.add_argument("--site", default=None)
    ap.add_argument("--scale", type=int, default=None)
    ap.add_argument("--font", default=None)
    a = ap.parse_args()
    data = json.load(open(a.json, encoding="utf-8"))
    FURNITURE_NAME = a.name or data.get("furniture_name") or FURNITURE_NAME
    SITE_LOCATION = a.site or data.get("site") or SITE_LOCATION
    SCALE_DEN = a.scale or SCALE_DEN
    setup_font(a.font)
    m = Model(data)
    sheets = [page_floor(m, 20), page_b(m, SCALE_DEN, "NO.001", FURNITURE_NAME), page_a(m, SCALE_DEN, "NO.002", FURNITURE_NAME)]
    os.makedirs(a.out, exist_ok=True)
    render_pdf(sheets, os.path.join(a.out, "test_sheet.pdf"))
    render_dxf(sheets, os.path.join(a.out, "test_sheet.dxf"))
    print("font:", FONT_USED["path"], "| name:", FURNITURE_NAME, "| scale 1/%d" % SCALE_DEN)


if __name__ == "__main__":
    main()
