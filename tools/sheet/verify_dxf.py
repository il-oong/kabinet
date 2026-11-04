#!/usr/bin/env python3
"""생성 DXF 검증 (수동 교차검증, ezdxf 필요).

사용:  python3 -I tools/sheet/verify_dxf.py out.dxf [furniture.json] [--structure-only] [--no-hinge] [--no-overlap-ep]
 0) 구조 검사: 핸들 중복·미해결 참조(330/340/350/360)·$HANDSEED·LAYOUT/CLASSES/DIMSTYLE/필수 OBJECTS
 1) ezdxf audit 오류 0
 2) 시트 도곽(FRAME 굵은 사각) 폭 = 420 x 시트 배수 (1:1 실치수 규칙) -> 시트별 배수 출력
 3) 치수 문자 = 측정 길이: 치수선(DIM 레이어 선)의 눈금(DIMT) 사이 길이(mm)와 근처 TEXT 숫자가 일치하는지
    (확대 상세 시트 'detail' 은 확대 배율이 있어 제외)
 4) furniture.json 이 있으면 가구 W/H/D 와 같은 길이의 치수선이 가구 시트에 있는지
종료코드 0 = 통과.
"""
import collections, json, math, re, sys
import ezdxf


# ---------------------------------------------------------------- 구조 검사 (CAD 호환)
HANDLE_DEF = {"5", "105"}
HANDLE_REF = {"330", "340", "350", "360", "390", "391", "380", "331"}
REQUIRED_OBJECTS = {"ACAD_GROUP", "ACAD_LAYOUT", "ACAD_MLINESTYLE", "ACAD_PLOTSETTINGS", "ACAD_PLOTSTYLENAME", "ACAD_MATERIAL", "ACAD_COLOR", "ACAD_VISUALSTYLE"}


HINGE_RE = re.compile(r"힌지|hinge|경첩", re.I)


def check_no_hinge(path, verbose=True):
    """생성 DXF 에 힌지 문자·도어 열림(여닫이) 사선이 없는지 검사. 사선 = DIM·해칭 색이 아닌 비축각 LINE 중 종이 4mm(x시트 배수) 이상 긴 것,
    또는 같은 선분이 이어진 호 모양(THIN 비축각 짧은 선 12개 이상 연속). 반환 (통과, 문제 목록)"""
    d = ezdxf.readfile(path)
    ents = []
    for e in d.modelspace():
        if e.dxftype() == "INSERT":
            ents += list(e.virtual_entities())
        else:
            ents.append(e)
    infos = []
    for e in ents:
        if e.dxftype() == "TEXT" and e.dxf.layer == "SHEET_FRAME_INFO":
            m = re.search(r"\(1/(\d+)", e.dxf.text)
            infos.append((e.dxf.insert.x, float(m.group(1)) if m else 1.0))
    infos.sort()
    def kof(x):
        k = 1.0
        for ix, ik in infos:
            if x >= ix - 5 * ik:
                k = ik
        return k
    probs = []
    texts = [e.dxf.text for e in ents if e.dxftype() == "TEXT" and HINGE_RE.search(e.dxf.text)]
    if texts:
        probs.append(f"힌지 문자 {len(texts)}개 (예 {texts[:3]})")
    diag = []
    for e in ents:
        if e.dxftype() != "LINE" or e.dxf.layer in ("DIM", "SHEET_FRAME_INFO", "NOTE_BLUE", "NOTE_RED"):   # 지시선(leader)은 주석
            continue
        a, b = e.dxf.start, e.dxf.end
        dx, dy = abs(b.x - a.x), abs(b.y - a.y)
        if dx < 1e-3 or dy < 1e-3:
            continue
        if e.dxf.hasattr("true_color") and ezdxf.colors.int2rgb(e.dxf.true_color) in ((165, 165, 165), (120, 120, 120), (130, 130, 130)):
            continue                                   # 해칭 색
        L = math.hypot(dx, dy)
        k = kof(min(a.x, b.x))
        if L > 4.0 * k:
            diag.append((round(a.x), round(a.y), round(L / k, 1)))
    if diag:
        probs.append(f"긴 사선 LINE(도어 열림 의심) {len(diag)}개 (예 {diag[:3]})")
    # 힌지 컵·보링처럼 보이는 소형 원(THIN/OUTLINE, 반지름 < 종이 1mm) · 짧은 THIN 선(< 종이 5mm, 해칭·치수 제외)
    small_c = [e for e in ents if e.dxftype() == "CIRCLE" and e.dxf.layer == "THIN" and e.dxf.radius < 1.0 * kof(e.dxf.center.x)]
    if small_c:
        probs.append(f"소형 CIRCLE(보링·힌지 컵 의심) {len(small_c)}개 (예 {[(round(e.dxf.center.x), round(e.dxf.center.y)) for e in small_c[:3]]})")
    short_l = []
    chains = collections.Counter()
    cand = []
    for e in ents:
        if e.dxftype() == "LINE" and e.dxf.layer == "THIN":
            a_, b_ = e.dxf.start, e.dxf.end
            L = math.hypot(b_.x - a_.x, b_.y - a_.y)
            if 0 < L < 2.5 * kof(min(a_.x, b_.x)) and abs(a_.x - b_.x) < 1e-6:   # 도어 가장자리 눈금처럼 짧은 세로선(수평 레일선·상판 이음선은 제외)
                k_ = kof(min(a_.x, b_.x))
                if abs(a_.y - b_.y) < 1e-6:
                    key = ("h", round(a_.y / k_))
                elif abs(a_.x - b_.x) < 1e-6:
                    key = ("v", round(a_.x / k_))
                else:
                    key = ("d", round((a_.y - (b_.y - a_.y) / (b_.x - a_.x) * a_.x) / k_))
                chains[key] += 1
                cand.append((key, (round(a_.x), round(a_.y), round(L / k_, 1))))
    for key, info in cand:
        if chains[key] < 3:                      # 같은 선 위에 3개 이상 이어지면 파선(점선 패턴)으로 본다
            short_l.append(info)
    if short_l:
        probs.append(f"짧은 세로 THIN 선 {len(short_l)}개(도어 가장자리 눈금 의심) (예 {short_l[:3]})")
    arcs = [e for e in ents if e.dxftype() == "ARC"]
    if arcs:
        probs.append(f"ARC {len(arcs)}개(도어 열림 호 의심)")
    if verbose:
        print("힌지/도어 열림 표기 검사:", "0건 OK" if not probs else "문제 %d건" % len(probs))
        for pr in probs:
            print("  -", pr)
    return not probs, probs


def _clip_len(p, q, r):
    """선분 p-q 가 사각 r=(x0,y0,x1,y1) 안(내부)에 놓인 길이 (Liang-Barsky)."""
    x0, y0, x1, y1 = r
    dx, dy = q[0] - p[0], q[1] - p[1]
    t0, t1 = 0.0, 1.0
    for pp, qq in ((-dx, p[0] - x0), (dx, x1 - p[0]), (-dy, p[1] - y0), (dy, y1 - p[1])):
        if abs(pp) < 1e-12:
            if qq < 0:
                return 0.0
        else:
            t = qq / pp
            if pp < 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
            if t0 > t1:
                return 0.0
    return (t1 - t0) * math.hypot(dx, dy)


def check_no_overlap_ep(path, tol=0.5, verbose=True):
    """EP 해칭(패턴 HATCH) 영역 안쪽(경계에서 tol 만큼 안)을 몸통 선(OUTLINE/THIN 의 LINE·LWPOLYLINE)이 지나면 겹침.
    EP 경계선과 일치하는 선·EP 를 통째로 감싸는 바깥선은 허용. 반환 (통과, 겹침 목록)"""
    d = ezdxf.readfile(path)
    ents = []
    for e in d.modelspace():
        if e.dxftype() == "INSERT":
            ents += list(e.virtual_entities())
        else:
            ents.append(e)
    regions = []
    for e in ents:
        if e.dxftype() == "HATCH" and not e.dxf.solid_fill:
            for pth in e.paths:
                pts = [(v[0], v[1]) for v in getattr(pth, "vertices", [])]
                if len(pts) >= 3:
                    xs = [a for a, b in pts]; ys = [b for a, b in pts]
                    regions.append((min(xs), min(ys), max(xs), max(ys)))
    segs = []
    for e in ents:
        if e.dxf.layer not in ("OUTLINE", "THIN"):
            continue
        t = e.dxftype()
        if t == "LINE":
            segs.append(((e.dxf.start.x, e.dxf.start.y), (e.dxf.end.x, e.dxf.end.y)))
        elif t == "LWPOLYLINE":
            pts = [(float(x), float(y)) for x, y in e.get_points("xy")]
            for a, b in zip(pts, pts[1:] + ([pts[0]] if e.closed else [])):
                segs.append((a, b))
    bad = []
    for r in regions:
        w, h = r[2] - r[0], r[3] - r[1]
        if w <= 4 * tol or h <= 4 * tol:
            continue
        inner = (r[0] + tol, r[1] + tol, r[2] - tol, r[3] - tol)
        tot = 0.0
        hit = 0
        for a, b in segs:
            if max(a[0], b[0]) < inner[0] or min(a[0], b[0]) > inner[2] or max(a[1], b[1]) < inner[1] or min(a[1], b[1]) > inner[3]:
                continue
            L = _clip_len(a, b, inner)
            if L > tol:
                tot += L; hit += 1
        if hit:
            bad.append((tuple(round(v) for v in r), hit, round(tot)))
    if verbose:
        print(f"EP 겹침 검사: EP/해칭 영역 {len(regions)}개, 몸통 선 침범 {len(bad)}곳 ->", "0건 OK" if not bad else "문제")
        for b in bad[:10]:
            print("  - 영역", b[0], "침범 선", b[1], "개, 길이", b[2])
    return not bad, bad


def raw_pairs(path):
    raw = open(path, "rb").read()
    try:
        txt = raw.decode("cp949")
    except UnicodeDecodeError:
        txt = raw.decode("utf-8", "replace")
    lines = txt.replace("\r\n", "\n").split("\n")
    return [(lines[i].strip(), lines[i + 1].strip()) for i in range(0, len(lines) - 1, 2)]


def check_structure(path, verbose=True):
    """핸들 중복 / 미해결 참조(330·340·350·360·390) / HANDSEED / 필수 OBJECTS·CLASSES·DIMSTYLE·레이아웃 검사.
    반환: (통과 여부, 문제 목록)"""
    P = raw_pairs(path)
    probs = []
    sec = None
    defs = collections.Counter()
    refs = []
    kinds = collections.Counter()
    seed = None
    root_keys = set()
    cur0 = None
    cur_in_root = False
    objs = collections.Counter()
    owners_dict = {}
    for i, (c, v) in enumerate(P):
        if c == "0" and v == "SECTION":
            sec = P[i + 1][1]
        if c == "0":
            cur0 = v
            if sec == "OBJECTS":
                objs[v] += 1
            if sec == "CLASSES" and v == "CLASS":
                kinds["CLASS"] += 1
        if c == "9" and v == "$HANDSEED":
            seed = P[i + 1][1]
        if c in HANDLE_DEF and sec in ("TABLES", "BLOCKS", "ENTITIES", "OBJECTS"):
            defs[v.upper()] += 1
        elif c in HANDLE_REF and sec in ("TABLES", "BLOCKS", "ENTITIES", "OBJECTS") and v not in ("0", ""):
            refs.append((v.upper(), c, cur0, sec))
    dup = [h for h, n in defs.items() if n > 1]
    if dup:
        probs.append(f"핸들 중복 {len(dup)}개 (예 {dup[:5]})")
    miss = [(h, c, t) for h, c, t, s_ in refs if h not in defs]
    if miss:
        probs.append(f"미해결 참조 {len(miss)}개 (예 {miss[:5]})")
    try:
        mx = max(int(h, 16) for h in defs)
        if seed is None or int(seed, 16) <= mx:
            probs.append(f"$HANDSEED({seed}) <= 최대 핸들({mx:X})")
    except ValueError:
        probs.append("핸들 형식 오류")
    # 루트 딕셔너리 항목 + 필수 객체
    names = []
    k = next((j for j, (c, v) in enumerate(P) if (c, v) == ("0", "DICTIONARY")), None)
    if k is not None:
        j = k + 1
        while j < len(P) and P[j][0] != "0":
            if P[j][0] == "3":
                names.append(P[j][1])
            j += 1
    miss_obj = sorted(REQUIRED_OBJECTS - set(names))
    if miss_obj:
        probs.append(f"루트 DICTIONARY 에 없는 항목: {miss_obj}")
    if objs.get("LAYOUT", 0) < 2:
        probs.append(f"LAYOUT {objs.get('LAYOUT', 0)}개 (Model + Layout1 필요)")
    if kinds["CLASS"] < 3:
        probs.append(f"CLASSES {kinds['CLASS']}개")
    # DIMSTYLE Standard 레코드
    if not any(P[j] == ("0", "DIMSTYLE") and any(q == ("2", "Standard") for q in P[j + 1:j + 12]) for j in range(len(P) - 12)):
        probs.append("DIMSTYLE Standard 레코드 없음")
    # BLOCK_RECORD 의 레이아웃 핸들(340)
    for j, (c, v) in enumerate(P):
        if (c, v) == ("0", "BLOCK_RECORD"):
            blk = P[j + 1:j + 14]
            nm = next((q[1] for q in blk if q[0] == "2"), "")
            if nm in ("*Model_Space", "*Paper_Space") and not any(q[0] == "340" and q[1] not in ("0", "") for q in blk):
                probs.append(f"BLOCK_RECORD {nm} 에 레이아웃 핸들(340) 없음")
    # IMAGE 정합 (IMAGEDEF 경로는 ASCII, 상대경로)
    for j, (c, v) in enumerate(P):
        if (c, v) == ("0", "IMAGEDEF"):
            pth = next((q[1] for q in P[j + 1:j + 20] if q[0] == "1"), "")
            if not pth.isascii() or " " in pth or "(" in pth:
                probs.append(f"IMAGEDEF 경로가 ASCII-안전하지 않음: {pth}")
    if verbose:
        print(f"구조 검사: 핸들 {len(defs)}개, 참조 {len(refs)}개, HANDSEED {seed}, LAYOUT {objs.get('LAYOUT', 0)}, "
              f"CLASS {kinds['CLASS']}, 객체 {sum(objs.values())}개(DICTIONARY {objs.get('DICTIONARY', 0)}) ->",
              "OK" if not probs else "문제 %d건" % len(probs))
        for pr in probs:
            print("  -", pr)
    return not probs, probs

TOL = 1.5


def num(s):
    m = re.fullmatch(r"\s*(-?[\d,]+(?:\.\d+)?)\s*(?:싱크면|서랍면)?\s*", s or "")
    return float(m.group(1).replace(",", "")) if m else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0]
    fj = json.load(open(args[1], encoding="utf-8")) if len(args) > 1 else None
    d = ezdxf.readfile(path)
    ok = True
    a = d.audit()
    print("audit errors:", len(a.errors)); ok &= len(a.errors) == 0
    good, _ = check_structure(path); ok &= good
    if "--no-overlap-ep" in sys.argv:
        good, _ = check_no_overlap_ep(path); ok &= good
    if "--no-hinge" in sys.argv:
        good, _ = check_no_hinge(path); ok &= good
    if "--structure-only" in sys.argv:
        print("RESULT:", "PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
    print("INSUNITS:", d.header.get("$INSUNITS"), "layers:", sorted(l.dxf.name for l in d.layers))
    msp = d.modelspace()
    def _flat(it):
        for e in it:
            if e.dxftype() == "INSERT":
                yield from _flat(e.virtual_entities())
            else:
                yield e
    ents = list(_flat(msp))      # 뷰 블록(INSERT)은 풀어서 검사
    # 해칭/블록: 영역당 HATCH 1개 — 낱개 45° 해칭 선이 남아 있으면 실패
    pat = [e for e in ents if e.dxftype() == "HATCH" and not e.dxf.solid_fill]
    loose = [e for e in ents if e.dxftype() == "LINE" and e.dxf.layer == "THIN" and e.dxf.hasattr("true_color")
             and ezdxf.colors.int2rgb(e.dxf.true_color) in ((165, 165, 165), (120, 120, 120), (130, 130, 130))      # 'HATCH' 스타일 색(해칭 선)
             and abs(abs(e.dxf.end.x - e.dxf.start.x) - abs(e.dxf.end.y - e.dxf.start.y)) < 1e-3 * max(1.0, abs(e.dxf.end.x - e.dxf.start.x))
             and abs(e.dxf.end.x - e.dxf.start.x) > 1e-6]
    nins = sum(1 for e in msp if e.dxftype() == "INSERT")
    print(f"해칭: 패턴 HATCH {len(pat)}개, 낱개 45° 해칭 의심 LINE {len(loose)}개; 블록 정의 {len([b for b in d.blocks if not b.name.startswith('*')])}개 / INSERT {nins}개")
    ok &= len(loose) < 8
    # 도곽 블록(FRAME_SHEET*)에는 도곽·표제란만: 치수(DIM)·마커(CIRCLE)가 있으면 뷰를 옮길 때 남는다
    stray = 0
    for b in d.blocks:
        if b.name.startswith("FRAME_SHEET"):
            stray += sum(1 for e in b if e.dxftype() == "CIRCLE" or e.dxf.layer == "DIM")
    print(f"도곽 블록 안 뷰 요소(치수선·마커): {stray}개")
    ok &= stray == 0
    # 시트 도곽: FRAME 레이어 lineweight 100 사각
    frames = []
    for e in ents:
        if e.dxftype() == "LWPOLYLINE" and e.dxf.layer == "FRAME" and e.dxf.lineweight == 100:
            p = list(e.get_points("xy"))
            xs = [q[0] for q in p]; ys = [q[1] for q in p]
            frames.append((min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)))
    frames.sort()
    sheets = []                              # (x0, 배수 k, 라벨)
    for e in sorted((e for e in ents if e.dxftype() == "TEXT" and e.dxf.layer == "SHEET_FRAME_INFO"), key=lambda e: e.dxf.insert.x):
        m = re.search(r"\(1/(\d+)", e.dxf.text)
        k = float(m.group(1)) if m else 1.0
        sheets.append((e.dxf.insert.x - 4.5 * k, k, e.dxf.text))
    print("sheets:", [(round(x), int(k), t.split()[1]) for x, k, t in sheets])
    for x, k, t in sheets:
        fw = [f for f in frames if x - 1 <= f[0] <= x + 420 * k]
        # 굵은 도곽(있는 시트): 폭 = 401.2 x k (= 420 x k 용지에서 8.9mm 안쪽)
        good = all(abs(f[2] - 401.2 * k) < 0.5 * k for f in fw)
        print(f"  {t}: 배수 {int(k)} -> 용지 420x297 -> {int(420 * k)}x{int(297 * k)}, 굵은 도곽 {'있음 폭 ' + str(round(fw[0][2])) if fw else '없음(평면도)'}", "OK" if good else "FAIL")
        ok &= good
    # 치수 문자 vs 측정
    lines = [e for e in ents if e.dxftype() == "LINE" and e.dxf.layer == "DIM"]
    texts = [(e.dxf.insert.x, e.dxf.insert.y, e.dxf.text, e.dxf.get("rotation", 0), e.dxf.height) for e in ents if e.dxftype() == "TEXT"]
    allk = [k for _, k, _ in sheets] or [1]
    sheets = [(x, k, t) for x, k, t in sheets]
    bad = checked = 0
    for ln in lines:
        (x1, y1, _), (x2, y2, _) = ln.dxf.start, ln.dxf.end
        horiz = abs(y2 - y1) < 1e-6; vert = abs(x2 - x1) < 1e-6
        if not (horiz or vert):
            continue
        # 소속 시트 배수
        sx = min(x1, x2)
        sk = next((k for (x, k, t) in reversed(sheets) if sx >= x - 1), allk[0])
        sname = next((t for (x, k, t) in reversed(sheets) if sx >= x - 1), "")
        if "detail" in sname:
            continue
        L = abs(x2 - x1) if horiz else abs(y2 - y1)
        if L < 8 * sk:
            continue
        # 눈금(DIMT 짧은 선) 위치
        ticks = []
        for t in ents:
            if t.dxftype() == "LINE" and t.dxf.layer == "DIM" and t.dxf.color != 0 or False:
                pass
        # 눈금: 길이 ~2*0.7*sqrt2*k 의 짧은 대각선 중 이 치수선 위에 중심이 있는 것
        cs = []
        for t in lines:
            (a1, b1, _), (a2, b2, _) = t.dxf.start, t.dxf.end
            ln_len = math.hypot(a2 - a1, b2 - b1)
            if abs(ln_len - 2.0 * 0.7 * math.sqrt(2) * sk) < 0.05 * sk * 3:
                cx, cy = (a1 + a2) / 2, (b1 + b2) / 2
                if horiz and abs(cy - y1) < 0.01 and min(x1, x2) - 1 <= cx <= max(x1, x2) + 1: cs.append(cx)
                if vert and abs(cx - x1) < 0.01 and min(y1, y2) - 1 <= cy <= max(y1, y2) + 1: cs.append(cy)
        cs = sorted(set(round(c, 3) for c in cs))
        # 치수선 = 첫~끝 눈금 + 양쪽 0.8k 연장. 보조선(extension line)은 쌓인 치수줄의 눈금과 우연히 같은 선상에 놓일 뿐이라 제외
        if len(cs) < 2 or abs(L - (cs[-1] - cs[0]) - 1.6 * sk) > 0.3 * sk:
            continue
        for c0, c1 in zip(cs, cs[1:]):
            seg = c1 - c0
            if seg < 0.5:
                continue
            mid = (c0 + c1) / 2
            # 문자: 치수선 근처 (수직 오프셋 <= 5k), 수평 치수는 중심 근처, 수직 치수는 rot 90
            cand = []
            for (tx, ty, tt, rot, h) in texts:
                v = num(tt)
                if v is None: continue
                if horiz and abs(ty - y1) <= 5 * sk and abs(tx - mid) <= seg / 2 + 14 * sk and abs(rot) < 1: cand.append(v)
                if vert and abs(tx - x1) <= 8 * sk and abs(ty - mid) <= seg / 2 + 14 * sk and abs(rot - 90) < 1: cand.append(v)
            checked += 1
            if not any(abs(v - seg) <= TOL for v in cand):
                bad += 1
                if bad <= 8:
                    print(f"  MISMATCH {sname}: 측정 {seg:.1f} mm @({x1:.0f},{y1:.0f})-({x2:.0f},{y2:.0f}), 근처 문자 {cand[:5]}")
    print(f"치수 문자 검사: {checked} 구간, 불일치 {bad}")
    ok &= bad == 0
    if fj:
        o = fj["overall"]
        want = {"W": o["W"], "H": o["H"], "D": o["D"]}
        alllen = collections.Counter()
        for ln in lines:
            (x1, y1, _), (x2, y2, _) = ln.dxf.start, ln.dxf.end
            L = max(abs(x2 - x1), abs(y2 - y1))
            for k in set(allk):
                alllen[round(L - 1.6 * k)] += 1
        for key, v in want.items():
            hit = alllen.get(round(v), 0)
            print(f"  치수선 {key}={v}: {'있음' if hit else '없음'} ({hit})")
            ok &= hit > 0
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
