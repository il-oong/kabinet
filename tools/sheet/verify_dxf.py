#!/usr/bin/env python3
"""생성 DXF 검증 (수동 교차검증, ezdxf 필요).

사용:  python3 -I tools/sheet/verify_dxf.py out.dxf [furniture.json]
 1) ezdxf audit 오류 0
 2) 시트 도곽(FRAME 굵은 사각) 폭 = 420 x 시트 배수 (1:1 실치수 규칙) -> 시트별 배수 출력
 3) 치수 문자 = 측정 길이: 치수선(DIM 레이어 선)의 눈금(DIMT) 사이 길이(mm)와 근처 TEXT 숫자가 일치하는지
    (확대 상세 시트 'detail' 은 확대 배율이 있어 제외)
 4) furniture.json 이 있으면 가구 W/H/D 와 같은 길이의 치수선이 가구 시트에 있는지
종료코드 0 = 통과.
"""
import collections, json, math, re, sys
import ezdxf

TOL = 1.5


def num(s):
    m = re.fullmatch(r"\s*(-?[\d,]+(?:\.\d+)?)\s*", s or "")
    return float(m.group(1).replace(",", "")) if m else None


def main():
    path = sys.argv[1]
    fj = json.load(open(sys.argv[2], encoding="utf-8")) if len(sys.argv) > 2 else None
    d = ezdxf.readfile(path)
    ok = True
    a = d.audit()
    print("audit errors:", len(a.errors)); ok &= len(a.errors) == 0
    print("INSUNITS:", d.header.get("$INSUNITS"), "layers:", sorted(l.dxf.name for l in d.layers))
    msp = d.modelspace()
    ents = list(msp)
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
                    print(f"  MISMATCH {sname}: 측정 {seg:.1f} mm, 근처 문자 {cand[:5]}")
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
