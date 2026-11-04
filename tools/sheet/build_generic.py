#!/usr/bin/env python3
"""임의 가구 JSON -> 우리 양식 PDF + DXF(흰/어두운 배경) — 범용 시트 빌더.

build_sheet.py(주방 아일랜드 전용 프로토타입)의 도곽·치수·마커·EP/목찬넬 상세·렌더러를 그대로 가져다 쓰고
(회귀 없음), 가구 JSON(일렬 모듈형)에서 페이지를 만든다.

JSON 스키마 (output_samples/<이름>/furniture.json):
{
  "site": "판교 푸르지오 그랑블", "furniture_name": "...", "type": "하부장|싱크대|아일랜드|붙박이장|키큰장|...",
  "overall": {"W":..,"H":..,"D":..,"top_thickness":..,"kick":..},
  "ep": {"left":bool,"right":bool,"top":bool,"thickness":20},
  "channel": true|false,                    # 목찬넬 손잡이(상세 쪽 생성)
  "modules": [{"name","x","z","w","h","d","type":"doors|drawers|open|appliance","doors":n,"drawers":n,
               "shelves":[z..],"rods":[z..],"label":"짧은 표기"}],
  "sink": {"x","y","w","d"} | null,         # 상판 싱크 컷 (평면 좌표: x 왼쪽 기준, y 뒤 기준)
  "cut_x": 정수|null,                       # 단면 1 절단 위치(없으면 가운데 모듈)
  "notes": {"DOOR","BODY","handle"}, "room": {"W","D","name"}, "table_rows": [[항목, 가정값, 확인방법]...],
  "flags": ["추정 사항 ..."]
}
실행: python3 -I tools/sheet/build_generic.py output_samples/<이름>/furniture.json [--out DIR] [--name 가구명] [--font TTF] [--scale N]
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_sheet as bs   # noqa: E402
from build_sheet import Sheet, fmt, view  # noqa: E402

EP, BT, DT, CH_H, CH_GAP = 20, 18, 20, 60, 25


def norm(d):
    o = d.setdefault("overall", {})
    o.setdefault("top_thickness", 0); o.setdefault("kick", 0)
    d.setdefault("ep", {}); d["ep"].setdefault("thickness", EP)
    if d.get("channel"): d["ep"]["top"] = False          # 목찬넬 하부장은 천판 EP 없음(찬넬이 상단 마감·손잡이)
    for m in d.get("modules", []):
        m.setdefault("x", 0); m.setdefault("z", o["kick"]); m.setdefault("d", o["D"]); m.setdefault("type", "open")
        m.setdefault("doors", 0); m.setdefault("drawers", 0); m.setdefault("shelves", []); m.setdefault("rods", [])
    d.setdefault("notes", {})
    n = d["notes"]
    n.setdefault("DOOR", "목림 지정 자재 (확인필요)"); n.setdefault("BODY", "목림 지정 자재 (확인필요)")
    n.setdefault("handle", "목찬넬 (확인필요)" if d.get("channel") else "지정 손잡이 (확인필요)")
    d.setdefault("room", {"W": 5200, "D": 3400, "name": "공간"})
    d.setdefault("flags", [])
    return d


def ep_bounds(d):
    """EP 가 있는 쪽을 뺀 몸통 가로 범위 [lo, hi] (EP 안쪽면)."""
    ep = d["ep"]; t = ep["thickness"]; W = d["overall"]["W"]
    return (t if ep.get("left") else 0), (W - t if ep.get("right") else W)


def clipped(d):
    """모듈 목록을 EP 안쪽 범위로 줄인 복사본 — 끝 모듈의 몸통·전판·선반이 EP 두께 구간에 겹치지 않게."""
    lo, hi = ep_bounds(d)
    out = []
    for md in d["modules"]:
        a, b = max(md["x"], lo), min(md["x"] + md["w"], hi)
        out.append(dict(md, x=a, w=max(b - a, 0)))
    return out


def ep_row(sh, d, X, y, ref):
    """가로 EP 줄: EP | 몸통 | EP (EP 가 있는 쪽만)."""
    ep = d["ep"]; t = ep["thickness"]; W = d["overall"]["W"]
    lo, hi = ep_bounds(d)
    if lo == 0 and hi == W:
        return False
    xs = ([0, lo] if lo else [0]) + ([hi, W] if hi < W else [W])
    xs = sorted(set(xs))
    bs.dim_h(sh, [X(x) for x in xs], y, [fmt(b - a) for a, b in zip(xs, xs[1:])], ref=ref, size=1.9)
    return True


def pick_scale(d, max_w=140.0, max_h=88.0, max_d=44.0):
    o = d["overall"]
    for den in (20, 25, 30, 40, 50, 60, 80):
        if o["W"] / den <= max_w and o["H"] / den <= max_h and o["D"] / den <= max_d:
            return den
    return 100


def fronts(d, md):
    k = md["z"] + 4
    ztop = md["z"] + md["h"]
    under_top_ep = d["ep"].get("top") and ztop >= d["overall"]["H"] - d["overall"]["top_thickness"] - 0.5
    if under_top_ep: ztop -= d["ep"]["thickness"]                    # 천판 EP(가로 20T) 아래로
    top = ztop - CH_GAP if d.get("channel") else ztop - 4        # 찬넬: 상판 하면(또는 천판 EP 하면)에서 25 아래
    if md["type"] == "drawers":
        n = max(md["drawers"], 1)
        gap = CH_GAP if d.get("channel") else 3
        fh = (top - k - gap * (n - 1)) // n
        return [(k + i * (fh + gap), k + i * (fh + gap) + fh) for i in range(n)]
    if md["type"] == "doors":
        return [(k, top)]
    return []


# ------------------------------------------------------------------ 뷰
@view("VIEW_TOP")
def draw_plan(sh, d, ox, oy, s, labels=True):
    o = d["overall"]; W, D = o["W"], o["D"]
    for md in clipped(d):
        x0, x1 = ox + md["x"] * s, ox + (md["x"] + md["w"]) * s
        y1 = oy + md["d"] * s
        sh.rect(x0, oy + (D - md["d"]) * s, x1, oy + D * s, "THIN")
        if md["type"] in ("doors", "drawers"):
            sh.line(x0, oy + (D - DT) * s, x1, oy + (D - DT) * s, "THIN")
        if labels and md["w"] * s > 8:
            sh.text((x0 + x1) / 2, oy + (D - md["d"] / 2) * s + 0.6, md.get("label", md["name"]), 1.8, "g", "c")
    ep = d["ep"]; t = ep["thickness"]
    if ep.get("left"): bs.ep_rect(sh, ox, oy, ox + t * s, oy + D * s, 0.45)
    if ep.get("right"): bs.ep_rect(sh, ox + (W - t) * s, oy, ox + W * s, oy + D * s, 0.45)
    sh.rect(ox, oy, ox + W * s, oy + D * s, "OUT")
    sk = d.get("sink")
    if sk:
        sh.rrect(ox + sk["x"] * s, oy + sk["y"] * s, ox + (sk["x"] + sk["w"]) * s, oy + (sk["y"] + sk["d"]) * s, max(25 * s, 0.4), "OUT")


@view("VIEW_TOP")
def plan_dims(sh, d, ox, oy, s):
    o = d["overall"]; W, D = o["W"], o["D"]
    xs = sorted({0, W} | {round(m["x"]) for m in d["modules"]} | {round(m["x"] + m["w"]) for m in d["modules"]})
    if len(xs) > 2:
        bs.dim_h(sh, [ox + x * s for x in xs], oy - 5.5, [fmt(b - a) for a, b in zip(xs, xs[1:])], ref=oy)
    top_y = 11.5
    if ep_row(sh, d, lambda x: ox + x * s, oy - 11.5, oy):
        top_y = 17.5                                    # 모듈 / EP|몸통|EP / 전체 3단
    bs.dim_h(sh, [ox, ox + W * s], oy - top_y, [fmt(W)], ref=oy)
    bs.dim_v(sh, ox - 5.5, [oy, oy + D * s], [fmt(D)], ref=ox)


def cut_x(d):
    if d.get("cut_x") is not None:
        return d["cut_x"]
    mods = [m for m in d["modules"] if m["type"] in ("doors", "drawers")] or d["modules"]
    m = mods[len(mods) // 2]
    return m["x"] + m["w"] / 2.0


@view("VIEW_TOP")
def plan_markers(sh, d, ox, oy, s):
    o = d["overall"]; W, D = o["W"], o["D"]
    cy = oy + D * s / 2
    bs.marker(sh, ox + W * s + 8, oy + D * s - 8, "A", "down")
    bs.marker(sh, ox + W * s + 8, cy, "D", "left")
    bs.marker(sh, ox - 25.0, cy, "C", "right")
    x = ox + cut_x(d) * s
    yt, yb = oy - 25.0, oy + D * s + 14.5
    sh.chain(x, yt + 3.3, x, yb - 3.3, "FR")
    sh.line(x - 2.2, yt + 5.0, x + 2.2, yt + 5.0, "SEC"); sh.line(x - 2.2, yb - 5.0, x + 2.2, yb - 5.0, "SEC")
    bs.marker(sh, x, yt, "1", "right"); bs.marker(sh, x, yb, "1", "right")


@view("KEYPLAN")
def keyplan(sh, d, x0=12.0, y0=19.5, w=26.0):
    rd = d["room"]; s = w / rd["W"]; h = rd["D"] * s
    sh.rect(x0, y0, x0 + w, y0 + h, "OUT")
    wt = 150 * s
    sh.rect(x0 + wt, y0 + wt, x0 + w - wt, y0 + h - wt, "THIN")
    o = d["overall"]
    ix = x0 + (rd["W"] - o["W"]) / 2 * s
    sh.rect(ix, y0 + wt, ix + o["W"] * s, y0 + wt + o["D"] * s, "OUT")
    cx = ix + o["W"] * s / 2; by = y0 + wt + o["D"] * s
    sh.fill([(cx - 1.6, by + 3.4), (cx + 1.6, by + 3.4), (cx, by + 0.6)], (222, 0, 56))


def elev_frame(sh, d, ox, gy, s):
    o = d["overall"]
    X = lambda v: ox + v * s
    Z = lambda v: gy - v * s
    if o["top_thickness"] > 0:
        sh.rect(X(0), Z(o["H"]), X(o["W"]), Z(o["H"] - o["top_thickness"]), "OUT")
    return X, Z


def elev_dims(sh, d, X, Z):
    o = d["overall"]; top = Z(o["H"]); body = o["H"] - o["top_thickness"]
    xs = sorted({0, o["W"]} | {round(m["x"]) for m in d["modules"]} | {round(m["x"] + m["w"]) for m in d["modules"]})
    if len(xs) > 2:
        bs.dim_h(sh, [X(x) for x in xs], top - 11.0, [fmt(b - a) for a, b in zip(xs, xs[1:])], ref=top)
    if ep_row(sh, d, X, top - 17.0, top):
        bs.dim_h(sh, [X(0), X(o["W"])], top - 23.0, [fmt(o["W"])], ref=top)
    else:
        bs.dim_h(sh, [X(0), X(o["W"])], top - 17.0, [fmt(o["W"])], ref=top)
    if o["top_thickness"] > 0:
        bs.dim_v(sh, X(0) - 6.0, [Z(body), Z(0)], [fmt(body)], ref=X(0))
    bs.dim_v(sh, X(0) - 12.0, [Z(o["H"]), Z(0)], [fmt(o["H"])], ref=X(0))
    if o["kick"] > 0:
        bs.dim_v(sh, X(o["W"]) + 6.0, [Z(body), Z(o["kick"]), Z(0)], [fmt(body - o["kick"]), fmt(o["kick"])], ref=X(o["W"]), side=1)


def ep_strips(sh, d, X, Z, body, k):
    ep = d["ep"]; t = ep["thickness"]; o = d["overall"]
    # 측판 EP 는 상판 하면(body)부터 바닥(0)까지 걸레받이 구간 포함 연속 한 장, 천판 EP 는 측판 EP 사이
    if ep.get("left"): bs.ep_rect(sh, X(0), Z(body), X(t), Z(0), 0.5)
    if ep.get("right"): bs.ep_rect(sh, X(o["W"] - t), Z(body), X(o["W"]), Z(0), 0.5)
    if ep.get("top"): bs.ep_rect(sh, X(t if ep.get("left") else 0), Z(body), X(o["W"] - (t if ep.get("right") else 0)), Z(body - t), 0.5)


@view("VIEW_FRONT_DOOR")
def door_view(sh, d, ox, gy, s):
    o = d["overall"]; X, Z = elev_frame(sh, d, ox, gy, s)
    body = o["H"] - o["top_thickness"]; k = o["kick"]
    if body > k: sh.rect(X(ep_bounds(d)[0]), Z(body), X(ep_bounds(d)[1]), Z(k), "OUT")        # 몸통 외곽 = 측판 EP 안쪽면 사이
    if k > 0: sh.rect(X(d["ep"]["thickness"] if d["ep"].get("left") else 10), Z(k), X(o["W"] - (d["ep"]["thickness"] if d["ep"].get("right") else 10)), Z(0), "OUT")   # 걸레받이: 측판 EP 사이
    for md in clipped(d):
        lo_, hi_ = ep_bounds(d)
        zb, zt = md["z"], md["z"] + md["h"]
        if md["x"] > lo_: sh.line(X(md["x"]), Z(zb), X(md["x"]), Z(zt - (d["ep"]["thickness"] if d["ep"].get("top") else 0)), "OUT")
        if md["type"] == "doors":
            n = max(md["doors"], 1); dw = (md["w"] - 3.0 * (n - 1) - 6.0) / n
            for i in range(n):
                xa = md["x"] + 3.0 + i * (dw + 3.0)
                for (z0, z1) in fronts(d, md):
                    sh.rect(X(xa), Z(z1), X(xa + dw), Z(z0), "OUT")
                    if d.get("channel"):
                        sh.rect(X(xa), Z(z1 + CH_GAP), X(xa + dw), Z(z1), "OUT")
        elif md["type"] == "drawers":
            for (z0, z1) in fronts(d, md):
                sh.rect(X(md["x"] + 3), Z(z1), X(md["x"] + md["w"] - 3), Z(z0), "OUT")
                if d.get("channel"): sh.rect(X(md["x"] + 3), Z(z1 + CH_GAP), X(md["x"] + md["w"] - 3), Z(z1), "OUT")
                if md["w"] * s > 12: bs.dim_v(sh, X(md["x"] + md["w"]) - 3.0, [Z(z1), Z(z0)], [fmt(z1 - z0)], size=1.7)
        elif md["type"] == "appliance":
            sh.text(X(md["x"] + md["w"] / 2), Z((zb + zt) / 2), md.get("label", md["name"]), 2.0, "r", "c")
            sh.dashed(X(md["x"] + 5), Z(zb), X(md["x"] + 5), Z(zt), "RED")
        if d.get("channel") and md["type"] in ("doors", "drawers") and md["w"] * s > 12:
            top_f = fronts(d, md)[-1][1] if fronts(d, md) else zt
            bs.blue_leader(sh, X(md["x"] + md["w"] * 0.5), Z(top_f - 110), X(md["x"] + md["w"] * 0.5), Z(top_f + CH_GAP / 2), "목찬넬 60*40", "l", 1.8)
    ep_strips(sh, d, X, Z, body, k)
    elev_dims(sh, d, X, Z)
    if k > 0: sh.text(X(o["W"] / 2), Z(k / 2) + 0.6, f"걸레받이 H{fmt(k)}", 1.7, "g", "c")
    return X, Z


@view("VIEW_FRONT_BODY")
def body_view(sh, d, ox, gy, s):
    o = d["overall"]; X, Z = elev_frame(sh, d, ox, gy, s)
    body = o["H"] - o["top_thickness"]; k = o["kick"]
    if body > k: sh.rect(X(ep_bounds(d)[0]), Z(body), X(ep_bounds(d)[1]), Z(k), "OUT")        # 몸통 외곽 = 측판 EP 안쪽면 사이
    if k > 0: sh.rect(X(d["ep"]["thickness"] if d["ep"].get("left") else 10), Z(k), X(o["W"] - (d["ep"]["thickness"] if d["ep"].get("right") else 10)), Z(0), "OUT")   # 걸레받이: 측판 EP 사이
    for md in clipped(d):
        lo_, hi_ = ep_bounds(d)
        zb, zt = md["z"], md["z"] + md["h"]
        if md["x"] > lo_: sh.rect(X(md["x"] - 9), Z(zt - (d["ep"]["thickness"] if d["ep"].get("top") else 0)), X(md["x"] + 9), Z(zb), "THIN")
        sh.line(X(md["x"]), Z(zb), X(md["x"] + md["w"]), Z(zb), "THIN")
        for sv in md["shelves"]:
            zz = zb + sv
            sh.rect(X(md["x"] + (9 if md["x"] > lo_ else 0)), Z(zz + 9), X(md["x"] + md["w"] - (9 if md["x"] + md["w"] < hi_ else 0)), Z(zz - 9), "THIN")
        for rv in md["rods"]:
            sh.dashed(X(md["x"] + 12), Z(zb + rv), X(md["x"] + md["w"] - 12), Z(zb + rv), "BLUE", 2.0, 1.0)
            if md["w"] * s > 14: sh.text(X(md["x"] + md["w"] / 2), Z(zb + rv) - 1.0, "옷걸이봉", 1.6, "b", "c")
        if md["type"] == "drawers":
            for (z0, z1) in fronts(d, md):
                sh.rect(X(md["x"] + 22), Z(z0 + 140), X(md["x"] + md["w"] - 22), Z(z0 + 30), "THIN")
        if md["type"] == "appliance":
            sh.rect(X(md["x"] + 7), Z(zt - 5), X(md["x"] + md["w"] - 7), Z(zb + 5), "RED")
            bs.red_note(sh, X(md["x"] + md["w"] / 2), Z((zb + zt) / 2), md.get("label", md["name"]), "c", 1.8)
        elif md["w"] * s > 10 and not md["shelves"]:
            sh.text(X(md["x"] + md["w"] / 2), Z((zb + zt) / 2), md.get("label", md["name"]), 1.7, "g", "c")
        if d.get("channel"):
            for (z0, z1) in fronts(d, md):
                sh.rect(X(md["x"] + 1.5), Z(z1 + CH_GAP), X(md["x"] + md["w"] - 1.5), Z(z1 + CH_GAP - CH_H), "BLUE")
    ep_strips(sh, d, X, Z, body, k)
    elev_dims(sh, d, X, Z)
    x = X(cut_x(d)); yt = Z(o["H"]) - 29.0; yb = gy + 9.5
    sh.chain(x, yt + 3.3, x, yb - 3.3, "FR")
    sh.line(x - 2.2, yt + 5.0, x + 2.2, yt + 5.0, "SEC"); sh.line(x - 2.2, yb - 5.0, x + 2.2, yb - 5.0, "SEC")
    bs.marker(sh, x, yt, "1", "right"); bs.marker(sh, x, yb, "1", "right")
    return X, Z


@view("NOTE")
def note_block(sh, d, lines):
    n = d["notes"]
    sh.text(218.3, 26.6, "DOOR : " + n["DOOR"], 3.9)
    sh.text(218.3, 38.6, "BODY : " + n["BODY"], 3.9)
    sh.text(218.3, 50.6, "손잡이 : " + n["handle"], 3.9, "r" if "확인" in n["handle"] else "k")
    y = 61.0
    for t, c in lines:
        sh.text(218.3, y, t, 3.0, c); y += 5.3


def default_notes(d):
    o = d["overall"]
    L = [(f"*W{fmt(o['W'])} x H{fmt(o['H'])} x D{fmt(o['D'])} (mm) - 도면 DIMENSION 값", "k")]
    if any(d["ep"].get(k) for k in ("left", "right", "top")):
        L.append((f"*EP = 마감판 {d['ep']['thickness']}T (측판·천판) / 몸통 18T / 도어 20T", "b"))
    if d.get("channel"): L.append(("*목찬넬 60*40 : 전판 상단(천판 하단 25 이격) (확인필요)", "r"))
    L.append(("*선반 18T · 뒷판 9T · 서랍 레일 13*2 (일반 기준, 추정)", "k"))
    for f in d["flags"][:5]: L.append(("*" + f, "r"))
    L.append(("*단면 1 : SIDE VIEW 시트 / 확인 목록 : 생산 확인표", "k"))
    return L


# ------------------------------------------------------------------ 페이지
def page_furniture(d, den, no):
    s = 1.0 / den; o = d["overall"]
    sh = Sheet("furniture"); sh.den = den
    bs.furniture_frame(sh, d["furniture_name"], d.get("type", "가구").split("(")[0][:12] + " 정면/평면", no, den, ("TOP VIEW",))
    keyplan(sh, d)
    ox, oy = 50.0, 50.0
    draw_plan(sh, d, ox, oy, s); plan_dims(sh, d, ox, oy, s); plan_markers(sh, d, ox, oy, s)
    note_block(sh, d, default_notes(d))
    gy = min(124.2 + 26.0 + o["H"] * s, 262.0)
    with sh.group("VIEW_FRONT_DOOR"):             # 마커·캡션도 뷰 블록 안에
        door_view(sh, d, 30.0, gy, s); bs.marker(sh, 30.0 + o["W"] * s / 2, gy + 10.0, "A", "up")
        sh.text(30.0, gy + 19.0, "도어 20T / 전판 간격 3 / 걸레받이 (추정)", 2.0, "b")
    with sh.group("VIEW_FRONT_BODY"):
        body_view(sh, d, 240.0, gy, s); bs.marker(sh, 240.0 + o["W"] * s / 2, gy + 10.0, "A", "up")
        sh.text(240.0, gy + 19.0, "몸통 18T · 칸막이 18T · 선반 18T · 뒷판 9T (추정)", 2.0, "b")
    return sh


def page_side(d, den, no):
    s = 1.0 / den; o = d["overall"]; D = o["D"]; k = o["kick"]; body = o["H"] - o["top_thickness"]
    sh = Sheet("side")
    den_top = max(den, -(-int(o["H"]) // 62))             # 상단 구획(높이 ~70mm)에 들어가도록 측면도 축척을 키움
    bs.furniture_frame(sh, d["furniture_name"], "좌·우 측면 / 단면 1", no, den_top, ("SIDE VIEW (LEFT / RIGHT)",),
                       hdr2=("SECTION 1  (단면)", "SECTION 1  (상세)"))
    note_block(sh, d, [("*C = 좌측면 / D = 우측면 (전면 = 오른쪽/왼쪽 화살표)", "k"), ("*단면 1 : TOP VIEW · 정면 BODY 절단선과 연결", "k")] + default_notes(d)[1:4])
    s = 1.0 / den_top                                     # 시트 전체(측면도+단면)를 같은 축척으로 그려 DXF 1:1 유지
    sh.den = den_top
    gy = 30.0 + o["H"] * s + 12.0
    for idx, (ox, flip) in enumerate(((48.0, False), (140.0, True))):
      with sh.group("VIEW_SIDE_RIGHT" if flip else "VIEW_SIDE_LEFT"):
        Y = (lambda v, ox=ox: ox + (D - v) * s) if flip else (lambda v, ox=ox: ox + v * s)
        Z = lambda v: gy - v * s
        a, b = sorted((Y(0), Y(D)))
        ep = d["ep"]; has = ep.get("left") if idx == 0 else ep.get("right")
        if o["top_thickness"] > 0: sh.rect(a, Z(o["H"]), b, Z(body), "OUT")
        if has: bs.ep_rect(sh, a, Z(body), b, Z(0), 0.5)               # 측판 EP 바닥까지
        else: sh.rect(a, Z(body), b, Z(k), "OUT")
        if k > 0 and not has: sh.rect(*sorted((Y(60), Y(D - 60)))[:1], Z(k), sorted((Y(60), Y(D - 60)))[1], Z(0), "OUT")
        bs.dim_v(sh, a - 6.0, [Z(o["H"]), Z(0)], [fmt(o["H"])], ref=a)
        bs.dim_h(sh, [a, b], Z(o["H"]) - 8.0, [fmt(D)], ref=Z(o["H"]))
        bs.marker(sh, (a + b) / 2, gy + 16.0, "D" if flip else "C", "up")
        # 전면 방향: 도면 정면(앞)은 평면 아래쪽 = 측면도에서 오른쪽(좌측면) / 왼쪽(우측면)
        bs.block_arrow(sh, (b - 2) if not flip else (a + 2), gy + 9.0, 7.0, "right" if not flip else "left")
        bs.shaded_label(sh, (b - 9.0) if not flip else (a + 9.0), gy + 10.0, "전면", 2.2, "r" if not flip else "l")
    draw_section(sh, d, 70.0, 222.0, s)
    return sh


@view("SECTION")
def draw_section(sh, d, ox, gy, s):
    o = d["overall"]; D = o["D"]; k = o["kick"]; body = o["H"] - o["top_thickness"]
    X = lambda v: ox + v * s
    Z = lambda v: gy - v * s
    if o["top_thickness"] > 0: sh.rect(X(0), Z(o["H"]), X(D), Z(body), "OUT")
    sh.rect(X(DT), Z(body), X(D - 9), Z(k), "OUT")
    sh.rect(X(D - 9), Z(body), X(D), Z(k), "THIN")
    sh.rect(X(DT), Z(body - BT), X(D - 9), Z(body), "THIN")
    sh.rect(X(DT), Z(k), X(D - 9), Z(k + BT), "THIN")
    sh.rect(X(0), Z(body - (CH_GAP if d.get("channel") else 4)), X(DT), Z(k + 4), "OUT")      # 도어 20T
    if d.get("channel"):
        xb, zc = DT, body                               # 목찬넬 상단 = 상판 하면(천판 EP 없음)
        pts = [(xb + 22, zc), (xb + 40, zc), (xb + 40, zc - CH_H), (xb, zc - CH_H), (xb, zc - CH_H + 18), (xb + 22, zc - CH_H + 18)]
        sh.poly([(X(a), Z(b)) for a, b in pts], "OUT", True)
    if k > 0: sh.rect(X(60), Z(k), X(D - 60), Z(0), "OUT")
    cx = cut_x(d)
    mid = next((m for m in d["modules"] if m["x"] <= cx < m["x"] + m["w"]), d["modules"][0])
    for sv in mid["shelves"]:
        zz = mid["z"] + sv; sh.rect(X(DT), Z(zz + 9), X(D - 29), Z(zz - 9), "OUT")
    for rv in mid["rods"]:
        sh.circ(X(D / 2), Z(mid["z"] + rv), max(14 * s, 0.7), "OUT")
    if mid["type"] == "drawers":
        for (z0, z1) in fronts(d, mid):
            sh.rect(X(DT + 13), Z(z0 + 140), X(DT + min(500, D - 80)), Z(z0 + 30), "THIN")
    if mid["type"] == "appliance":
        sh.rect(X(DT + 10), Z(mid["z"] + mid["h"] - 5), X(D - 30), Z(mid["z"] + 5), "RED")
    bs.dim_h(sh, [X(0), X(D)], Z(o["H"]) - 8.0, [fmt(D)], ref=Z(o["H"]))
    bs.dim_v(sh, X(0) - 6.0, [Z(o["H"]), Z(0)], [fmt(o["H"])], ref=X(0))
    bs.front_labels_row(sh, X(0), X(D), gy + 12.0, "전면", "후면") if hasattr(bs, "front_labels_row") else None
    bs.marker(sh, (X(0) + X(D)) / 2, gy + 24.0, "1", "right")
    sh.text((X(0) + X(D)) / 2 + 8, gy + 25.2, f"SECTION 1  (X={fmt(cx)}, 추정 위치)", 2.4, "k", "l")


def page_detail(d, den, no):
    sh = Sheet("detail"); sh.den = den
    bs.furniture_frame(sh, d["furniture_name"], "EP / 목찬넬 상세", no, den, ("DETAIL",), hdr2=("DETAIL", "DETAIL"))
    note_block(sh, d, [(f"*EP = 마감판 {d['ep']['thickness']}T / 몸통 18T / 도어 20T", "b")] +
               ([("*목찬넬 60*40 = 손잡이 (확인필요, 기본값)", "r")] if d.get("channel") else []))
    with sh.group("NOTE"):
        sh.text(17.0, 28.0, "※ EP 위치는 도면의 'EP 판넬 [..T]' 라벨 기준(추정)", 2.6, "r")
    with sh.group("DETAIL_EP"):
        bs.detail_title(sh, 17.0, 139.0, 1, "측판 EP 상세 - 평면 (1/5)")
        bs.edge_ep_plan(sh, None, 60.0, 160.0, 0.2)
    if d.get("channel"):
        with sh.group("DETAIL_CHANNEL"):
            bs.detail_title(sh, 218.3, 139.0, 2, "목찬넬 상세 - 측면 (1/2)")
            bs.edge_section(sh, 262.0, 178.0, 0.5, 60, 62, 0, True, True)
            bs.shaded_label(sh, 240.0, 232.0, "전면 (도어 쪽)", 2.4); bs.shaded_label(sh, 330.0, 232.0, "후면 (벽 쪽)", 2.4, "r")
    return sh


def page_floor(d, no):
    o = d["overall"]; room = d["room"]
    den = next((x for x in (20, 25, 30, 40, 50) if room["W"] / x <= 270 and room["D"] / x <= 185), 50)
    s = 1.0 / den
    sh = Sheet("floor"); sh.den = den
    bs.SITE_LOCATION = d.get("site", bs.SITE_LOCATION)
    bs.plan_frame(sh, room["name"], f"{room['name']} {d['furniture_name']} 평면도", den)
    with sh.group("VIEW_PLAN"):
        wt = 150; ox, oy = 62.0, 62.0
        X = lambda v: ox + v * s; Y = lambda v: oy + v * s
        for a, b, c, e in ((-wt, -wt, room["W"] + wt, 0), (-wt, room["D"], room["W"] + wt, room["D"] + wt), (room["W"], 0, room["W"] + wt, room["D"]), (-wt, 0, 0, room["D"])):
            sh.rect(X(a), Y(b), X(c), Y(e), "OUT"); sh.hatch_rect(X(a), Y(b), X(c), Y(e))
        ix = (room["W"] - o["W"]) / 2.0
        draw_plan(sh, d, X(ix), Y(0), s)
        bs.dim_h(sh, [X(ix), X(ix + o["W"])], Y(o["D"]) + 8, [fmt(o["W"])], ref=Y(o["D"]))
        bs.dim_v(sh, X(ix) - 6, [Y(0), Y(o["D"])], [fmt(o["D"])], ref=X(ix))
        bs.dim_h(sh, [X(0), X(room["W"])], Y(-wt) - 6.0, [fmt(room["W"])], ref=Y(-wt))
        bs.dim_v(sh, X(room["W"] + wt) + 7.0, [Y(0), Y(room["D"])], [fmt(room["D"])], ref=X(room["W"] + wt), side=1)
        bs.marker(sh, X(ix + o["W"] / 2), Y(o["D"]) + 22.0, "A", "up")
        bs.marker(sh, X(ix) - 22.0, Y(o["D"] / 2), "C", "right"); bs.marker(sh, X(ix + o["W"]) + 22.0, Y(o["D"] / 2), "D", "left")
        sh.text(X(room["W"]) - 3, Y(room["D"]) - 3, "※ 공간 규격은 가정(확인필요)", 2.2, "r", "r")
    return sh


def page_table(d, den=25):
    rows = d.get("table_rows") or []
    base = [["도어 재질·색상", "목림 지정 자재 (샘플 문구)", "지정 자재 확인"], ["서랍 레일", "좌우 13 여유 (추정)", "레일 제품 규격 확인"],
            ["뒷판·후면 마감", "뒷판 9T (추정)", "후면 마감 사양 확인"], ["선반", "18T, 핀 96 간격 (추정)", "선반 위치 확정"],
            ["EP 20T 위치", "도면 EP 라벨 기준 (추정)", "원본 도면 EP 지시 대조"], ["콘센트·배선 타공", "위치 미정", "전기 도면 확인"],
            ["공간 규격", "평면도 공간은 가정치", "현장 실측"]]
    rows = rows + [[f, "도면에서 읽지 못함/추정", "확인 필요"] for f in d["flags"]] + base
    sh = Sheet("table"); sh.den = den
    sh.rect(4.5, 3.2, 415.5, 293.9, "FR")
    sh.text(17.0, 21.0, "생산 확인표", 8.5)
    sh.text(19.0, 277.0, d.get("site", ""), 4.9); sh.text(19.0, 286.4, f"{d['furniture_name']} 생산 확인표 (추정값 확인 필요)", 4.9)
    cols = [(15.0, 14.0, "번호"), (29.0, 62.0, "항목"), (91.0, 170.0, "현재 가정값"), (261.0, 140.0, "확인 방법")]
    y0, hh = 34.0, 9.0
    rh = max(min((255.0 - hh) / len(rows), 12.4), 7.0); xe = 401.0
    sh.rect(15.0, y0, xe, y0 + hh + rh * len(rows), "SEC")
    sh.fill([(15.0, y0), (xe, y0), (xe, y0 + hh), (15.0, y0 + hh)], (85, 85, 85))
    for x, w, t in cols: sh.text(x + 2.0, y0 + 6.2, t, 3.6, "w", "l")
    for x, w, t in cols[1:]: sh.line(x, y0, x, y0 + hh + rh * len(rows), "FR")
    for i, (a, b, c) in enumerate(rows):
        y = y0 + hh + i * rh
        if i < len(rows) - 1: sh.line(15.0, y + rh, xe, y + rh, "FR")
        sh.text(cols[0][0] + 7.0, y + rh / 2 + 1.2, str(i + 1), 3.4, "k", "c")
        for (x, w, _t), txt, col in ((cols[1], a, "k"), (cols[2], b, "r"), (cols[3], c, "b")):
            sh.text(x + 2.0, y + rh / 2 + 1.2, txt, 3.3, col, "l")
    return sh


def build(d, scale=None):
    d = norm(d)
    den = scale or d.get("scale") or pick_scale(d)
    pages = ([bs.page_info(d, d["furniture_name"])] if bs.site_info_of(d) is not None else []) + [page_floor(d, ""), page_furniture(d, den, "NO.001"), page_side(d, den, "NO.002")]
    if d["ep"].get("left") or d["ep"].get("right") or d["ep"].get("top") or d.get("channel"):
        pages.append(page_detail(d, den, "NO.003"))
    pages.append(page_table(d, den))
    return pages, den


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("json"); ap.add_argument("--out", default=None); ap.add_argument("--name", default=None)
    ap.add_argument("--site", default=None); ap.add_argument("--scale", type=int, default=None); ap.add_argument("--font", default=None)
    ap.add_argument("--no-blocks", action="store_true", help="뷰를 BLOCK 으로 묶지 않고 낱개 엔티티로 출력")
    ap.add_argument("--paper", action="store_true", help="DXF 를 예전 종이 mm 좌표(축소)로 출력 (기본: 1:1 실치수)")
    a = ap.parse_args()
    d = json.load(open(a.json, encoding="utf-8"))
    if a.name: d["furniture_name"] = a.name
    if a.site: d["site"] = a.site
    bs.SITE_LOCATION = d.get("site", bs.SITE_LOCATION); bs.FURNITURE_NAME = d.get("furniture_name", "")
    bs.setup_font(a.font)
    pages, den = build(d, a.scale)
    out = a.out or os.path.dirname(os.path.abspath(a.json))
    os.makedirs(out, exist_ok=True)
    bs.SCALE_DEN = den
    bs.render_pdf(pages, os.path.join(out, "sheet.pdf"))
    bs.render_dxf(pages, os.path.join(out, "sheet.dxf"), "white", real=not a.paper, blocks=not a.no_blocks)
    bs.render_dxf(pages, os.path.join(out, "sheet_dark.dxf"), "dark", real=not a.paper, blocks=not a.no_blocks)
    print("ok", d["furniture_name"], "scale 1/%d" % den, "pages", len(pages), "font", bs.FONT_USED["name"])


if __name__ == "__main__":
    main()
