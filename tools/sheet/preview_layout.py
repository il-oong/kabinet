#!/usr/bin/env python3
"""가구 도면(LayOut) 쪽 배치 미리보기 PNG — Ruby `SheetLayout` 계획(JSON)을 그대로 그린다.
LayOut 은 이 환경에서 실행할 수 없으므로, 쪽 수·뷰 배치·배율 표기·치수 여백·표제란을 눈으로 확인하는 용도.
뷰 안의 가구는 같은 크기(W×D×H)의 단순 상자 + 칸 나눔 예시로 그린다(실제 모델 선은 아님).
사용: python3 -I tools/sheet/preview_layout.py --name 붙박이장 --size 2740 600 2300 [--out output_samples/layout_preview] [--pages iso,front,side]
출력: <out>/<name>_p1.png ... (4 px/mm = 1680x1188)"""
import argparse, json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

K = 4.0
FONT = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SITE = "경기도 수원시 영통구 광교호수공원로 80 광교아이파크 101동 4601호"
GRAY, DARK, RED, BLUE = (110, 112, 108), (40, 44, 40), (134, 60, 73), (31, 95, 168)


def font(pt):                       # pt -> px (1pt = 0.3528 mm)
    return ImageFont.truetype(FONT, max(8, int(pt * 0.3528 * K)))


def load_plan(size, pages):
    out = subprocess.run(["ruby", os.path.join(HERE, "export_layout_plan.rb"), *map(str, size), pages], check=True, capture_output=True, text=True).stdout
    return json.loads(out)


class Page:
    def __init__(self):
        self.im = Image.new("RGB", (int(420 * K), int(297 * K)), "white")
        self.d = ImageDraw.Draw(self.im)

    def P(self, x, y):
        return (x * K, y * K)

    def line(self, x1, y1, x2, y2, c=GRAY, w=1, dash=False):
        if not dash:
            self.d.line([self.P(x1, y1), self.P(x2, y2)], fill=c, width=w)
            return
        import math
        L = math.hypot(x2 - x1, y2 - y1)
        n = max(1, int(L / 2.0))
        for i in range(0, n, 2):
            a, b = i / n, min((i + 1) / n, 1)
            self.d.line([self.P(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a), self.P(x1 + (x2 - x1) * b, y1 + (y2 - y1) * b)], fill=c, width=w)

    def rect(self, x, y, w, h, c=DARK, wd=2, fill=None):
        self.d.rectangle([self.P(x, y), self.P(x + w, y + h)], outline=c, width=wd, fill=fill)

    def text(self, s, x, y, pt=8, c=DARK, anchor="la"):
        self.d.text(self.P(x, y), s, fill=c, font=font(pt), anchor=anchor)

    def dim_h(self, x1, x2, y, label, off):
        yy = y - off
        self.line(x1, y - 1, x1, yy - 1.5, GRAY); self.line(x2, y - 1, x2, yy - 1.5, GRAY)
        self.line(x1, yy, x2, yy, GRAY)
        self.text(label, (x1 + x2) / 2, yy - 0.6, 7, RED, "ms")

    def dim_v(self, x, y1, y2, label, off):
        xx = x + off
        s = 1 if off > 0 else -1
        self.line(x + s, y1, xx + s * 1.5, y1, GRAY); self.line(x + s, y2, xx + s * 1.5, y2, GRAY)
        self.line(xx, y1, xx, y2, GRAY)
        tmp = Image.new("RGBA", (int(40 * K), int(8 * K)), (255, 255, 255, 0))
        ImageDraw.Draw(tmp).text((tmp.width / 2, tmp.height / 2), label, fill=RED, font=font(7), anchor="mm")
        tmp = tmp.rotate(90, expand=True)
        self.im.paste(tmp, (int((xx + (1.2 if s > 0 else -1.2)) * K - tmp.width / (2 if s > 0 else 1) ), int((y1 + y2) / 2 * K - tmp.height / 2)), tmp)


def nice(v):
    return "%d" % round(v)


def draw_view(pg, v, size):
    x, y, w, h = v["rect"]; den = v["den"]; name = v["name"]
    W, D, H = size
    ai, bi = {"front": (W, H), "top": (W, D), "side_r": (D, H), "side_l": (D, H)}[name]
    clip = v.get("clip")
    pg.rect(x, y, w, h, DARK, 3)
    # 칸 나눔 예시
    if name == "front":
        n = 2 if W < 1500 else 4
        for i in range(1, n):
            pg.line(x + w * i / n, y, x + w * i / n, y + h, GRAY, 2)
        pg.line(x, y + h * 0.5, x + w, y + h * 0.5, BLUE, 2, dash=True)
    elif name == "top":
        pg.line(x, y + h * 0.12, x + w, y + h * 0.12, GRAY, 2)
    else:
        pg.line(x + w * 0.15, y, x + w * 0.15, y + h, GRAY, 2)
        pg.line(x, y + h * 0.5, x + w, y + h * 0.5, BLUE, 2, dash=True)
    rows = []
    if name == "front" and not clip:
        rows = [("door", "%d/%d EQ" % (W, 2)), ("body", nice(W - 36)), ("all", nice(W))]
    elif not clip:
        rows = [("all", nice(ai))]
    else:
        rows = [("win", nice(clip[1] - clip[0]))]
    side = -1 if name == "side_l" else 1
    for i, (_, lab) in enumerate(rows):
        pg.dim_h(x, x + w, y, lab, 6 + 7 * i)
    edge = x if name == "side_l" else x + w
    pg.dim_v(edge, y, y + h, nice(bi), side * 12)
    cap_y = y + h + 6 + 8
    pg.line(v["outer"][0], cap_y, v["outer"][0] + max(v["outer"][2], 72), cap_y, GRAY, 2)
    pg.text("%s  SCALE 1/%d" % (v["label"], den), v["outer"][0] + 7, cap_y - 6, 9, DARK)
    # 바깥 사각형(여백 포함) — 점선, 겹침 확인용
    pg.rect(*v["outer"], c=(190, 200, 215), wd=1)


def draw_iso_box(pg, box, size):
    x, y, w, h = box
    W, D, H = size
    import math
    c, s = math.cos(math.radians(30)), math.sin(math.radians(30))
    pts = [(0, 0, 0), (W, 0, 0), (W, D, 0), (0, D, 0), (0, 0, H), (W, 0, H), (W, D, H), (0, D, H)]
    pr = [((a - b) * c, -(a + b) * s * 0 + (a + b) * s - cz) for a, b, cz in pts]   # 단순 축측
    xs = [p[0] for p in pr]; ys = [p[1] for p in pr]
    sc = min((w - 30) / (max(xs) - min(xs)), (h - 30) / (max(ys) - min(ys)))
    ox = x + (w - (max(xs) - min(xs)) * sc) / 2 - min(xs) * sc
    oy = y + (h - (max(ys) - min(ys)) * sc) / 2 - min(ys) * sc
    P = [(ox + p[0] * sc, oy + p[1] * sc) for p in pr]
    for a, b in [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]:
        pg.line(P[a][0], P[a][1], P[b][0], P[b][1], DARK, 3)
    face = [P[0], P[1], P[5], P[4]]
    pg.d.polygon([(px * K, py * K) for px, py in face], fill=(232, 226, 214), outline=DARK)


def render(plan, name, size, out):
    os.makedirs(out, exist_ok=True)
    files = []
    tb = plan["title_block"]
    for pgd in plan["pages"]:
        pg = Page()
        pg.rect(8, 8, 404, 281, DARK, 2)
        pg.text("%s - %s" % (name, pgd["title"]), 15, 8, 14)
        sc = ("1/%d" % pgd["scale"]) if pgd["scale"] else "N.T.S"
        pg.text("SCALE " + sc, 405, 8, 13, DARK, "ra")
        pg.line(15, 22, 405, 22, DARK, 2)
        if pgd["id"] == "iso":
            b = pgd["boxes"]
            pg.rect(*b["iso"], c=(190, 200, 215), wd=1)
            draw_iso_box(pg, b["iso"], size)
            pg.text("입체도 (축척 없음)", b["iso"][0] + 2, b["iso"][1] + 1, 9)
            mx, my, mw, mh = b["materials"]
            pg.text("마감재", mx, my, 11); pg.line(mx, my + 8, mx + mw, my + 8, DARK, 2)
            for i, col in enumerate([(226, 214, 190), (200, 200, 196), (120, 96, 72)]):
                sw = (mw - 6) / 3
                pg.rect(mx + i * (sw + 3), my + 11, sw, 21, DARK, 1, col)
            nx, ny, nw, nh = b["memo"]
            pg.text("메모 / 시공 유의사항", nx, ny, 11); pg.line(nx, ny + 8, nx + nw, ny + 8, DARK, 2)
            pg.text("메모를 입력하세요.", nx, ny + 10, 10)
            ox, oy, ow, oh = b["notes"]
            pg.text("도면 구성: 1쪽 입체도 · 2쪽 정면도/평면도 ·\n3쪽 측면도 (가구가 작으면 2쪽에 함께)", ox, oy, 8)
            for r in b.values():
                pg.rect(*r, c=(190, 200, 215), wd=1)
        else:
            for v in pgd["views"]:
                draw_view(pg, v, size)
        note = ("단위 mm · SCALE %s (이 쪽의 모든 뷰 동일)" % sc) if pgd["scale"] else "단위 mm · 입체도는 축척 없음(N.T.S) · 치수는 정면도·평면도·측면도 쪽 참고"
        if pgd.get("window"):
            note += " · 구간 %d~%d mm" % tuple(round(a) for a in pgd["window"])
        pg.text(note, 15, 262.5, 8)
        vals = {"furniture": name, "site": DEFAULT_SITE, "date": "2026-11-26", "author": "", "scale": sc, "page": "%d / %d" % (pgd["number"], pgd["total"])}
        t = (15, 268, 390, 18)
        for y in (t[1], t[1] + 9, t[1] + 18):
            pg.line(t[0], y, t[0] + t[2], y, DARK, 2)
        pg.line(t[0], t[1], t[0], t[1] + 18, DARK, 2); pg.line(t[0] + t[2], t[1], t[0] + t[2], t[1] + 18, DARK, 2)
        for c in tb:
            x, y, w, h = c["rect"]
            pg.line(x + w, y, x + w, y + h, GRAY, 1)
            pg.text(c["label"], x + 2, y + 1.2, 8, DARK)
            pg.text(vals[c["key"]] or "-", x + 22, y + 1.0, 9, DARK)
        fn = os.path.join(out, "%s_p%d.png" % (name, pgd["number"]))
        pg.im.save(fn)
        files.append(fn)
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--size", nargs=3, type=float, required=True, metavar=("W", "D", "H"))
    ap.add_argument("--out", default="output_samples/layout_preview")
    ap.add_argument("--pages", default="iso,front,side")
    a = ap.parse_args()
    plan = load_plan(a.size, a.pages)
    print("problems:", plan.get("problems"))
    for f in render(plan, a.name, a.size, a.out):
        print(f)
    sys.exit(1 if plan.get("problems") else 0)


if __name__ == "__main__":
    main()
