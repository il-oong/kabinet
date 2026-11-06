#!/usr/bin/env python3
"""기준 DXF(최종본 A)·샘플 PDF 를 좌표 단위로 덤프해 마크다운으로 만든다.
사용:
  python3 -I tools/sheet/dump_reference.py reference/final_A.dxf --md REFERENCE_SPEC.md \
      [--spec-dir reference/spec] [--compare output_samples/_____-1/sheet_1대1.dxf] [--pdf reference/sample_format_original.pdf]
- 모든 좌표는 '시트 원점(FRAME_SHEETn 삽입점) 기준'이며 실치수 mm(real) 와 용지 mm(paper = real/den) 를 병기한다.
- --spec-dir 이 있으면 시트별 전체 덤프를 spec/sheetN.md 로, 없으면 한 파일에 합친다.
- 기준 파일은 읽기 전용이다(수정 금지)."""
import argparse, collections, math, os, re, sys
import ezdxf

R = lambda v: ("%.1f" % v).rstrip("0").rstrip(".") if abs(v - round(v)) > 1e-6 else str(int(round(v)))


def sheets_of(d):
    ms = d.modelspace()
    fr = {}
    for e in ms:
        if e.dxftype() == "INSERT" and e.dxf.name.startswith("FRAME_SHEET"):
            fr[int(e.dxf.name[len("FRAME_SHEET"):])] = (e.dxf.insert.x, e.dxf.insert.y)
    labels = {}
    for e in ms:
        if e.dxftype() == "TEXT" and e.dxf.layer == "SHEET_FRAME_INFO":
            m = re.match(r"\[(\d+)\]\s*(.*?)\s*\(1/(\d+)", e.dxf.text)
            if m:
                labels[int(m.group(1))] = (m.group(2), int(m.group(3)), e.dxf.text)
    return fr, labels


def pts_of(e):
    t = e.dxftype()
    if t == "LINE":
        return [(e.dxf.start.x, e.dxf.start.y), (e.dxf.end.x, e.dxf.end.y)]
    if t == "LWPOLYLINE":
        return [(p[0], p[1]) for p in e.get_points()]
    if t in ("TEXT", "MTEXT"):
        return [(e.dxf.insert.x, e.dxf.insert.y)]
    if t in ("CIRCLE", "ARC"):
        c, r = e.dxf.center, e.dxf.radius
        return [(c.x - r, c.y - r), (c.x + r, c.y + r)]
    if t == "DIMENSION":
        return [(e.dxf.defpoint.x, e.dxf.defpoint.y), (e.dxf.defpoint2.x, e.dxf.defpoint2.y), (e.dxf.defpoint3.x, e.dxf.defpoint3.y)] \
            if e.dxf.hasattr("defpoint2") else [(e.dxf.defpoint.x, e.dxf.defpoint.y)]
    if t == "HATCH":
        out = []
        for p in e.paths:
            if hasattr(p, "vertices"):
                out += [(v[0], v[1]) for v in p.vertices]
            elif hasattr(p, "edges"):
                for ed in p.edges:
                    if hasattr(ed, "start"):
                        out += [tuple(ed.start)[:2], tuple(ed.end)[:2]]
        return out
    if t == "LEADER":
        return [(v[0], v[1]) for v in e.vertices]
    return []


def bbox(pts):
    if not pts:
        return None
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


class Ctx:
    def __init__(self, ox, oy, den):
        self.ox, self.oy, self.den = ox, oy, den

    def pt(self, p, ins=(0, 0)):
        x, y = p[0] + ins[0] - self.ox, p[1] + ins[1] - self.oy
        return "(%s, %s) [paper %s, %s]" % (R(x), R(y), R(x / self.den), R(y / self.den))

    def v(self, x):
        return "%s [paper %s]" % (R(x), R(x / self.den))


def dump_block(out, d, ctx, name, ins, lim_lines=4000):
    b = d.blocks.get(name)
    ents = list(b)
    pts = []
    for e in ents:
        pts += pts_of(e)
    bb = bbox([(p[0] + ins[0], p[1] + ins[1]) for p in pts])
    cnt = collections.Counter(e.dxftype() for e in ents)
    out.append("\n#### 블록 `%s` — 삽입점 %s, 엔티티 %d (%s)" % (name, ctx.pt(ins), len(ents), ", ".join("%s %d" % kv for kv in sorted(cnt.items()))))
    if bb:
        out.append("- bbox(시트 원점 기준): x %s ~ %s, y %s ~ %s (폭 %s, 높이 %s)" % (
            R(bb[0] - ctx.ox), R(bb[2] - ctx.ox), R(bb[1] - ctx.oy), R(bb[3] - ctx.oy), R(bb[2] - bb[0]), R(bb[3] - bb[1])))
    bylayer = collections.defaultdict(list)
    for e in ents:
        bylayer[e.dxf.layer].append(e)
    for layer in sorted(bylayer):
        es = bylayer[layer]
        out.append("\n##### 레이어 %s (%d)" % (layer, len(es)))
        lines = [e for e in es if e.dxftype() == "LINE"]
        polys = [e for e in es if e.dxftype() == "LWPOLYLINE"]
        hatches = [e for e in es if e.dxftype() == "HATCH"]
        dims = [e for e in es if e.dxftype() == "DIMENSION"]
        texts = [e for e in es if e.dxftype() in ("TEXT", "MTEXT")]
        other = [e for e in es if e.dxftype() in ("CIRCLE", "ARC", "LEADER", "INSERT", "SOLID")]
        if lines:
            hz = sorted({(round(e.dxf.start.y + ins[1] - ctx.oy, 1), round(min(e.dxf.start.x, e.dxf.end.x) + ins[0] - ctx.ox, 1),
                          round(max(e.dxf.start.x, e.dxf.end.x) + ins[0] - ctx.ox, 1)) for e in lines if abs(e.dxf.start.y - e.dxf.end.y) < 1e-6})
            vt = sorted({(round(e.dxf.start.x + ins[0] - ctx.ox, 1), round(min(e.dxf.start.y, e.dxf.end.y) + ins[1] - ctx.oy, 1),
                          round(max(e.dxf.start.y, e.dxf.end.y) + ins[1] - ctx.oy, 1)) for e in lines if abs(e.dxf.start.x - e.dxf.end.x) < 1e-6})
            dg = [e for e in lines if abs(e.dxf.start.x - e.dxf.end.x) >= 1e-6 and abs(e.dxf.start.y - e.dxf.end.y) >= 1e-6]
            lt = collections.Counter((e.dxf.linetype, e.dxf.lineweight) for e in lines)
            out.append("- LINE %d (수평 %d, 수직 %d, 사선 %d); linetype/lineweight: %s" % (len(lines), len(hz), len(vt), len(dg),
                       ", ".join("%s/%s ×%d" % (k[0], k[1], v) for k, v in lt.items())))
            if hz:
                out.append("- 수평선 y=… : x1→x2 (real mm, 시트 원점 기준)")
                out += ["  - y=%s : %s → %s (길이 %s)" % (R(y), R(a), R(b), R(b - a)) for y, a, b in hz[:lim_lines]]
            if vt:
                out.append("- 수직선 x=… : y1→y2")
                out += ["  - x=%s : %s → %s (길이 %s)" % (R(x), R(a), R(b), R(b - a)) for x, a, b in vt[:lim_lines]]
            for e in dg[:200]:
                out.append("  - 사선 (%s,%s)→(%s,%s)" % (R(e.dxf.start.x + ins[0] - ctx.ox), R(e.dxf.start.y + ins[1] - ctx.oy),
                                                      R(e.dxf.end.x + ins[0] - ctx.ox), R(e.dxf.end.y + ins[1] - ctx.oy)))
        for e in polys:
            vs = [(p[0] + ins[0] - ctx.ox, p[1] + ins[1] - ctx.oy) for p in e.get_points()]
            out.append("- LWPOLYLINE %s%d점: %s (lineweight %s)" % ("닫힘 " if e.closed else "", len(vs), " → ".join("(%s,%s)" % (R(x), R(y)) for x, y in vs[:12]) + (" …" if len(vs) > 12 else ""), e.dxf.lineweight))
        for e in hatches:
            bbh = bbox([(p[0] + ins[0] - ctx.ox, p[1] + ins[1] - ctx.oy) for p in pts_of(e)])
            out.append("- HATCH 패턴 %s scale %s angle %s, 경계 %d개, bbox %s" % (
                e.dxf.pattern_name, R(e.dxf.pattern_scale) if e.dxf.hasattr("pattern_scale") else "-", R(e.dxf.pattern_angle) if e.dxf.hasattr("pattern_angle") else "-",
                len(e.paths), ("x %s~%s y %s~%s" % tuple(R(v) for v in (bbh[0], bbh[2], bbh[1], bbh[3]))) if bbh else "-"))
        for e in dims:
            try:
                meas = e.get_measurement()
                meas = R(meas) if isinstance(meas, (int, float)) else str(meas)
            except Exception:
                meas = "?"
            dp = [("defpoint", e.dxf.defpoint)] + [(k, e.dxf.get(k)) for k in ("defpoint2", "defpoint3") if e.dxf.hasattr(k)]
            out.append("- DIMENSION 스타일 %s, 값 %s, 문구 '%s', 각도 %s, %s" % (
                e.dxf.dimstyle, meas, e.dxf.text, R(e.dxf.get("angle", 0)),
                "; ".join("%s=(%s,%s)" % (k, R(v.x + ins[0] - ctx.ox), R(v.y + ins[1] - ctx.oy)) for k, v in dp if v is not None)))
        for e in texts:
            if e.dxftype() == "TEXT":
                out.append("- TEXT '%s' 삽입 %s 높이 %s 정렬(h%s,v%s) 회전 %s 스타일 %s" % (
                    e.dxf.text, ctx.pt((e.dxf.insert.x, e.dxf.insert.y), ins), R(e.dxf.height), e.dxf.get("halign", 0), e.dxf.get("valign", 0), R(e.dxf.get("rotation", 0)), e.dxf.style))
            else:
                out.append("- MTEXT '%s' 삽입 %s 높이 %s 스타일 %s" % (e.text.replace("\n", "\\n"), ctx.pt((e.dxf.insert.x, e.dxf.insert.y), ins), R(e.dxf.char_height), e.dxf.style))
        for e in other:
            t = e.dxftype()
            if t in ("CIRCLE", "ARC"):
                out.append("- %s 중심 %s 반지름 %s%s" % (t, ctx.pt((e.dxf.center.x, e.dxf.center.y), ins), R(e.dxf.radius),
                           (" 각도 %s~%s" % (R(e.dxf.start_angle), R(e.dxf.end_angle))) if t == "ARC" else ""))
            elif t == "INSERT":
                out.append("- INSERT %s 삽입 %s" % (e.dxf.name, ctx.pt((e.dxf.insert.x, e.dxf.insert.y), ins)))
            else:
                out.append("- %s bbox %s" % (t, bbox(pts_of(e))))


def block_stats(d, name):
    ents = list(d.blocks.get(name))
    pts = []
    for e in ents:
        pts += pts_of(e)
    return collections.Counter(e.dxftype() for e in ents), bbox(pts), ents


def view_summary(d, ctx, name, ins):
    """뷰 블록 요약 — 외곽(OUTLINE) 사각형, DIMENSION 값 목록, 수직 분할선 간격."""
    ents = list(d.blocks.get(name))
    out = []
    dv = []
    for e in ents:
        if e.dxftype() == "DIMENSION":
            try:
                dv.append(round(e.get_measurement()))
            except Exception:
                pass
    if dv:
        c = collections.Counter(dv)
        out.append("  - 치수 값(mm): " + ", ".join("%d×%d" % (k, v) if v > 1 else str(k) for k, v in sorted(c.items(), reverse=True)))
    ol = [e for e in ents if e.dxftype() == "LWPOLYLINE" and e.dxf.layer == "OUTLINE" and e.closed and len(list(e.get_points())) == 4]
    for e in ol[:12]:
        vs = [(p[0] + ins[0] - ctx.ox, p[1] + ins[1] - ctx.oy) for p in e.get_points()]
        bb = bbox(vs)
        out.append("  - OUTLINE 4점 사각형: x %s~%s, y %s~%s (%s × %s)" % (R(bb[0]), R(bb[2]), R(bb[1]), R(bb[3]), R(bb[2] - bb[0]), R(bb[3] - bb[1])))
    return out


def sheet_range(fr, n):
    xs = sorted(v[0] for v in fr.values())
    x0 = fr[n][0]
    nxt = [x for x in xs if x > x0]
    return x0, (nxt[0] if nxt else x0 + 1e9)


def frame_summary(d, ctx, n):
    out = []
    ents = list(d.blocks.get("FRAME_SHEET%d" % n))
    cnt = collections.Counter(e.dxftype() for e in ents)
    pts = []
    for e in ents:
        pts += pts_of(e)
    bb = bbox(pts)
    out.append("- 프레임 블록 FRAME_SHEET%d: 엔티티 %s" % (n, dict(cnt)))
    if bb:
        out.append("- 프레임 외곽 bbox: x %s~%s, y %s~%s → 시트 크기 %s × %s (real) = %s × %s (paper, 1/%d)" % (
            R(bb[0]), R(bb[2]), R(bb[1]), R(bb[3]), R(bb[2] - bb[0]), R(bb[3] - bb[1]), R(ctx.v and (bb[2] - bb[0]) / ctx.den), R((bb[3] - bb[1]) / ctx.den), ctx.den))
    return out, bb


def dump_dxf(path, args):
    d = ezdxf.readfile(path)
    fr, labels = sheets_of(d)
    ms = d.modelspace()
    head = []
    head.append("## 1. 문서 정보 (`%s`)" % os.path.basename(path))
    head.append("- DXF 버전 %s, `$INSUNITS` %s, `$DWGCODEPAGE` %s, `$LTSCALE` %s, `$MEASUREMENT` %s" % (
        d.dxfversion, d.header.get("$INSUNITS"), d.header.get("$DWGCODEPAGE"), d.header.get("$LTSCALE"), d.header.get("$MEASUREMENT")))
    head.append("- 모델 공간 엔티티: %s" % dict(collections.Counter(e.dxftype() for e in ms)))
    head.append("- 블록 %d개(익명 `*` 제외 %d), 레이어 %d개, 텍스트 스타일: %s, 선종류: %s" % (
        len(d.blocks), len([b for b in d.blocks if not b.name.startswith("*")]), len(d.layers),
        ", ".join(s.dxf.name for s in d.styles), ", ".join(l.dxf.name for l in d.linetypes)))
    ds = [x for x in d.dimstyles if x.dxf.name == "KAB"]
    if ds:
        s = ds[0].dxf
        head.append("- DIMSTYLE KAB: dimtxt %s, dimasz %s, dimexo %s, dimexe %s, dimgap %s, dimdec %s, dimclrd/e/t %s/%s/%s, dimtxsty %s, dimtad %s, dimlfac %s" % tuple(
            s.get(k, "-") for k in ("dimtxt", "dimasz", "dimexo", "dimexe", "dimgap", "dimdec", "dimclrd", "dimclre", "dimclrt", "dimtxsty", "dimtad", "dimlfac")))
    head.append("\n### 1.1 시트 배치 (모델 공간)")
    head.append("| 시트 | 제목 | 배율 den | 원점(real) | 크기(real) | 크기(paper mm) | 라벨 TEXT |")
    head.append("|---|---|---|---|---|---|---|")
    order = sorted(fr)
    ctxs, per = {}, {}
    for n in order:
        title, den, raw = labels.get(n, ("?", 25, "?"))
        ctx = Ctx(fr[n][0], fr[n][1], den)
        ctxs[n] = ctx
        _, bb = frame_summary(d, ctx, n)
        w, h = (bb[2] - bb[0], bb[3] - bb[1]) if bb else (0, 0)
        per[n] = (title, den, w, h)
        head.append("| %d | %s | 1/%d | (%s, %s) | %s × %s | %s × %s | `%s` |" % (n, title, den, R(fr[n][0]), R(fr[n][1]), R(w), R(h), R(w / den), R(h / den), raw))
    head.append("- 시트 간격(피치): " + ", ".join(R(fr[order[i + 1]][0] - fr[order[i]][0]) for i in range(len(order) - 1)) + " (real mm; 원 시트 폭의 1.1배)")
    head.append("\n### 1.2 레이어 표")
    cnt = collections.Counter()
    for b in d.blocks:
        if not b.name.startswith("*") or b.name.startswith("*D"):
            for e in b:
                cnt[e.dxf.layer] += 1
    for e in ms:
        cnt[e.dxf.layer] += 1
    head.append("| 레이어 | ACI 색 | lineweight(1/100mm) | linetype | 엔티티 수(블록 포함) |")
    head.append("|---|---|---|---|---|")
    for l in d.layers:
        head.append("| %s | %s | %s | %s | %d |" % (l.dxf.name, l.dxf.color, l.dxf.lineweight, l.dxf.linetype, cnt.get(l.dxf.name, 0)))
    # 시트별 상세
    sheet_md = {}
    for n in order:
        title, den, w, h = per[n]
        ctx = ctxs[n]
        x0, x1 = sheet_range(fr, n)
        out = ["# 시트 %d — %s (1/%d, %s × %s real = %s × %s paper)" % (n, title, den, R(w), R(h), R(w / den), R(h / den)),
               "원점 = FRAME_SHEET%d 삽입점 (%s, %s). 아래 좌표는 모두 이 원점 기준 real mm 이고 `[paper …]` 는 1/%d 한 용지 mm." % (n, R(fr[n][0]), R(fr[n][1]), den)]
        fo, _ = frame_summary(d, ctx, n)
        out += fo
        inserts = []
        for e in ms:
            if e.dxftype() == "INSERT":
                nm = e.dxf.name
                m = re.search(r"_S(\d+)$", nm)
                belongs = (int(m.group(1)) == n) if m else (nm == "FRAME_SHEET%d" % n or (x0 <= e.dxf.insert.x < x1))
                if belongs:
                    inserts.append((nm, (e.dxf.insert.x, e.dxf.insert.y)))
        out.append("\n## 뷰·블록 목록")
        out.append("| 블록 | 삽입점(시트 원점 기준) | 엔티티 | bbox(x1,y1,x2,y2) |")
        out.append("|---|---|---|---|")
        for nm, ins in inserts:
            c, bb, _ = block_stats(d, nm)
            bs = "(%s,%s,%s,%s)" % tuple(R(v + (ins[0] if i % 2 == 0 else ins[1]) - (ctx.ox if i % 2 == 0 else ctx.oy)) for i, v in enumerate(bb)) if bb else "-"
            out.append("| %s | (%s, %s) | %d | %s |" % (nm, R(ins[0] - ctx.ox), R(ins[1] - ctx.oy), sum(c.values()), bs))
        out.append("\n## 뷰별 요약")
        for nm, ins in inserts:
            if nm.startswith("VIEW_") or nm.startswith("SECTION") or nm.startswith("DETAIL") or nm.startswith("KEYPLAN"):
                out.append("- **%s**" % nm)
                out += view_summary(d, ctx, nm, ins)
        out.append("\n## 전체 덤프")
        for nm, ins in inserts:
            dump_block(out, d, ctx, nm, ins)
        sheet_md[n] = out
    return d, head, per, sheet_md


def diff_section(ref, cand_path):
    out = ["## 차이표 — 최종본 A 대 우리 생성 결과 (`%s`)" % cand_path]
    c = ezdxf.readfile(cand_path)
    cf, cl = sheets_of(c)
    rf, rl = sheets_of(ref)

    def agg(d):
        r = collections.defaultdict(collections.Counter)
        for b in d.blocks:
            if b.name.startswith("*") and not b.name.startswith("*D"):
                continue
            key = re.sub(r"(_S\d+)$", "", b.name) + (re.search(r"_S(\d+)$", b.name).group(1) if re.search(r"_S(\d+)$", b.name) else "")
            for e in b:
                r[b.name][e.dxftype()] += 1
        return r

    ra, ca = agg(ref), agg(c)
    out.append("\n### 시트 구성")
    out.append("| 구분 | A | 우리 |")
    out.append("|---|---|---|")
    out.append("| 시트 수/순서 | %d: %s | %d: %s |" % (len(rl), ", ".join(rl[k][0] for k in sorted(rl)), len(cl), ", ".join(cl[k][0] for k in sorted(cl))))
    out.append("| 블록 수 | %d | %d |" % (len(ref.blocks), len(c.blocks)))
    out.append("| DXF 버전 | %s | %s |" % (ref.dxfversion, c.dxfversion))
    out.append("\n### 블록별 엔티티 수 (다른 것만)")
    out.append("| 블록 | A | 우리 |")
    out.append("|---|---|---|")
    n = 0
    for nm in sorted(set(ra) | set(ca)):
        if nm.startswith("*D"):
            continue
        if dict(ra.get(nm, {})) != dict(ca.get(nm, {})):
            n += 1
            out.append("| %s | %s | %s |" % (nm, dict(ra.get(nm, {})) or "-", dict(ca.get(nm, {})) or "-"))
    if n == 0:
        out.append("| (차이 없음) | | |")

    def texts(d):
        s = collections.Counter()
        for b in d.blocks:
            if b.name.startswith("*") and not b.name.startswith("*D"):
                continue
            for e in b:
                if e.dxftype() == "TEXT" and e.dxf.text.strip():
                    s[e.dxf.text.strip()] += 1
                elif e.dxftype() == "MTEXT":
                    s[e.text.strip().replace("\n", " ")] += 1
        return s
    ta, tc = texts(ref), texts(c)
    only_a = [t for t in ta if t not in tc]
    only_c = [t for t in tc if t not in ta]
    out.append("\n### 텍스트 차이 (A 에만 있는 것 %d개 / 우리에게만 있는 것 %d개)" % (len(only_a), len(only_c)))
    out.append("- **A 에만 있음 = 생성기가 따라야 할 '정답' 후보** (사용자가 CAD 에서 추가·수정한 값):")
    out += ["  - `%s`" % t for t in sorted(only_a)[:120]]
    out.append("- 우리에게만 있음 (A 에서 사용자가 지운 것):")
    out += ["  - `%s`" % t for t in sorted(only_c)[:120]]

    def dimvals(d):
        s = collections.Counter()
        for b in d.blocks:
            for e in b:
                if e.dxftype() == "DIMENSION":
                    try:
                        s[round(e.get_measurement())] += 1
                    except Exception:
                        pass
        return s
    da, dc = dimvals(ref), dimvals(c)
    out.append("\n### DIMENSION 값 분포 차이 (값: A개수 / 우리개수, 다른 것만)")
    out.append(", ".join("%d: %d/%d" % (k, da.get(k, 0), dc.get(k, 0)) for k in sorted(set(da) | set(dc), reverse=True) if da.get(k, 0) != dc.get(k, 0)) or "(없음)")
    return out


def dump_pdf(path, maxpages=None):
    import pymupdf
    doc = pymupdf.open(path)
    out = ["# 샘플 양식 PDF 벡터 추출 (`%s`)" % os.path.basename(path),
           "쪽 %d, 좌표 = 용지 mm(좌상단 원점, y 아래로). pt→mm = ×0.3528. 긴 선(≥40mm)·사각형·텍스트만 수록." % len(doc)]
    k = 25.4 / 72
    for i, p in enumerate(doc):
        if maxpages and i >= maxpages:
            break
        out.append("\n## 쪽 %d — %s × %s mm, 벡터 %d" % (i + 1, R(p.rect.width * k), R(p.rect.height * k), len(p.get_drawings())))
        segs = []
        for dr in p.get_drawings():
            w = dr.get("width") or 0
            col = dr.get("color")
            for it in dr["items"]:
                if it[0] == "l":
                    a, b = it[1], it[2]
                    if math.hypot(b.x - a.x, b.y - a.y) * k >= 40:
                        segs.append((round(a.x * k, 1), round(a.y * k, 1), round(b.x * k, 1), round(b.y * k, 1), round(w * k, 2), col))
                elif it[0] == "re":
                    r = it[1]
                    if r.width * k >= 40 or r.height * k >= 40:
                        segs.append((round(r.x0 * k, 1), round(r.y0 * k, 1), round(r.x1 * k, 1), round(r.y1 * k, 1), round(w * k, 2), "rect"))
        segs = sorted(set(segs))[:80]
        for s in segs:
            out.append("- %s (%s,%s)→(%s,%s) 선폭 %s mm 색 %s" % (("사각형" if s[5] == "rect" else "선"), s[0], s[1], s[2], s[3], s[4], s[5] if s[5] != "rect" else "-"))
        n = 0
        for b in p.get_text("dict")["blocks"]:
            for ln in b.get("lines", []):
                t = "".join(sp["text"] for sp in ln["spans"]).strip()
                if t and n < 60:
                    sp = ln["spans"][0]
                    out.append("- TEXT '%s' (%s,%s) 크기 %s mm 폰트 %s" % (t, R(ln["bbox"][0] * k), R(ln["bbox"][1] * k), R(sp["size"] * k), sp["font"]))
                    n += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dxf")
    ap.add_argument("--md")
    ap.add_argument("--spec-dir")
    ap.add_argument("--compare")
    ap.add_argument("--pdf")
    ap.add_argument("--rules", help="규칙 해설 마크다운 파일(앞부분에 삽입)")
    a = ap.parse_args()
    d, head, per, sheet_md = dump_dxf(a.dxf, a)
    md = ["# REFERENCE_SPEC — 최종본(A) 양식 상세 분석 (자동 생성 + 규칙 해설)",
          "> 이 문서는 `python3 -I tools/sheet/dump_reference.py %s --md REFERENCE_SPEC.md ...` 로 생성한다. 기준 파일은 수정 금지." % a.dxf, ""]
    if a.rules and os.path.exists(a.rules):
        md.append(open(a.rules, encoding="utf-8").read())
        md.append("")
    md += head
    if a.compare:
        md.append("")
        md += diff_section(d, a.compare)
    md.append("\n## 시트별 덤프")
    if a.spec_dir:
        os.makedirs(a.spec_dir, exist_ok=True)
        for n, out in sheet_md.items():
            fn = os.path.join(a.spec_dir, "sheet%d_%s.md" % (n, per[n][0]))
            open(fn, "w", encoding="utf-8").write("\n".join(out) + "\n")
            md.append("- 시트 %d (%s): [`%s`](%s)" % (n, per[n][0], fn, fn))
    else:
        for n, out in sheet_md.items():
            md += ["", *out]
    if a.pdf:
        pdf = dump_pdf(a.pdf)
        if a.spec_dir:
            fn = os.path.join(a.spec_dir, "sample_pdf.md")
            open(fn, "w", encoding="utf-8").write("\n".join(pdf) + "\n")
            md.append("- 샘플 PDF 벡터 추출: [`%s`](%s)" % (fn, fn))
        else:
            md += ["", *pdf]
    open(a.md or "REFERENCE_SPEC.md", "w", encoding="utf-8").write("\n".join(md) + "\n")
    print("wrote", a.md, "sheets", len(sheet_md))


if __name__ == "__main__":
    main()
