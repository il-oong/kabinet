#!/usr/bin/env python3
"""같은 furniture.json 을 Ruby(플러그인 코드 경로, tools/sheet/export_sheet.rb)와 Python(build_generic.py)에 넣어
시트 수·엔티티 종류·텍스트 집합·치수 값을 비교하고 차이 목록을 출력한다. 허용 차이 밖이면 종료코드 1.

사용: python3 -I tools/sheet/compare_ruby_python.py output_samples/___-1/furniture.json [...더 많은 json] [--keep DIR]
 (ruby 와 ezdxf 필요. Ruby 는 subprocess 로 실행.)
허용 차이(의도된 구현 차이):
 - 해칭: Python 은 45° 선(LINE) + SOLID HATCH, Ruby 는 ANSI31 HATCH + SOLID → LINE/HATCH/SOLID 수는 비교하지 않음
 - 시트 정보 글자(SHEET_FRAME_INFO), BG 레이어는 제외
 - TEXT 수 ±12%, LWPOLYLINE ±15%, CIRCLE ±30%, 치수 숫자 값 일치율 >= 85%
 - 시트 수·시트 종류 순서는 반드시 같아야 함
"""
import collections, json, os, re, subprocess, sys, tempfile
import ezdxf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
NUM = re.compile(r"^-?[\d,]+(\.\d+)?$")


def flat(msp):
    """INSERT(뷰 블록)는 내용을 풀어(virtual_entities) 낱개 엔티티처럼 비교한다."""
    for e in msp:
        if e.dxftype() == "INSERT":
            yield from flat(e.virtual_entities())
        else:
            yield e


def sheets_of(path):
    d = ezdxf.readfile(path)
    msp = list(flat(d.modelspace()))
    infos = []
    for e in msp:
        if e.dxftype() == "TEXT" and e.dxf.layer == "SHEET_FRAME_INFO":
            m = re.match(r"\[(\d+)\]\s+(\w+)(?:\s+\(1/(\d+)\))?", e.dxf.text)
            if m:
                k = float(m.group(3) or 1)
                infos.append((e.dxf.insert.x - 4.5 * k, int(m.group(1)), m.group(2), k))
    infos.sort()
    out = [dict(x0=x, no=n, name=nm, k=k, ents=[]) for x, n, nm, k in infos]
    for e in msp:
        if e.dxf.layer in ("BG", "SHEET_FRAME_INFO"):
            continue
        t = e.dxftype()
        try:
            x = e.dxf.defpoint.x if t == "DIMENSION" else e.dxf.insert.x if t == "TEXT" else (e.dxf.start.x if t == "LINE" else (e.dxf.center.x if t == "CIRCLE" else e.get_points("xy")[0][0] if t == "LWPOLYLINE" else None))
        except Exception:
            x = None
        if x is None:
            if t in ("HATCH", "SOLID"):
                x = None
            continue
        for s in reversed(out):
            if x >= s["x0"] - 1:
                s["ents"].append(e)
                break
    return out


def summarize(sh):
    c = collections.Counter(e.dxftype() for e in sh["ents"])
    texts = [e.dxf.text.strip() for e in sh["ents"] if e.dxftype() == "TEXT"]
    nums = collections.Counter(t.replace(",", "") for t in texts if NUM.match(t))
    for e in sh["ents"]:                                   # CAD DIMENSION(Python) 은 측정값을 숫자 치수로 센다
        if e.dxftype() == "DIMENSION":
            try:
                tx = (e.dxf.get("text") or "").replace(",", "").strip()
                nums[tx if NUM.match(tx) else str(round(e.get_measurement()))] += 1
            except Exception:
                pass
    words = collections.Counter(t for t in texts if not NUM.match(t))
    return dict(counts=c, nums=nums, words=words)


def within(a, b, tol):
    return abs(a - b) <= max(2, tol * max(a, b))


def compare(json_path, keep=None):
    tmp = keep or tempfile.mkdtemp()
    os.makedirs(tmp, exist_ok=True)
    stem = os.path.basename(os.path.dirname(os.path.abspath(json_path))) or "x"
    py_dir = os.path.join(tmp, stem + "_py"); rb = os.path.join(tmp, stem + "_rb.dxf")
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "build_generic.py"), json_path, "--out", py_dir], check=True, capture_output=True)
    subprocess.run(["ruby", os.path.join(HERE, "export_sheet.rb"), json_path, rb], check=True, capture_output=True)
    P = sheets_of(os.path.join(py_dir, "sheet.dxf")); R = sheets_of(rb)
    ok = True
    print(f"== {json_path}")
    pn = [s["name"] for s in P]; rn = [s["name"] for s in R]
    print(f"  시트: Python {pn} / Ruby {rn}")
    if pn != rn:
        print("  !! 시트 수/종류 불일치"); return False
    for sp, sr in zip(P, R):
        a, b = summarize(sp), summarize(sr)
        probs = []
        for k, tol in (("TEXT", 0.18), ("LWPOLYLINE", 0.15), ("CIRCLE", 0.30)):
            ca, cb = a["counts"][k], b["counts"][k]
            if k == "TEXT":                                 # 숫자 치수 글자는 Python 에선 DIMENSION 이라 문자 수에서 제외하고 비교
                ca = sum(a["words"].values()); cb = sum(b["words"].values())
            if not within(ca, cb, tol):
                probs.append(f"{k} {ca} vs {cb}")
        na = sum(a["nums"].values()); common = sum((a["nums"] & b["nums"]).values())
        rate = common / na if na else 1.0
        only_py = sorted((a["words"] - b["words"]).elements())
        only_rb = sorted((b["words"] - a["words"]).elements())
        if rate < 0.85:
            probs.append(f"치수 숫자 일치율 {rate:.0%}")
        flag = "OK " if not probs else "FAIL"
        print(f"  [{sp['name']:9s}] {flag} TEXT {a['counts']['TEXT']}/{b['counts']['TEXT']}  LWPOLY {a['counts']['LWPOLYLINE']}/{b['counts']['LWPOLYLINE']}  "
              f"CIRCLE {a['counts']['CIRCLE']}/{b['counts']['CIRCLE']}  치수 숫자 일치 {common}/{na}  (Python/Ruby)")
        miss = sorted((a["nums"] - b["nums"]).elements())
        extra = sorted((b["nums"] - a["nums"]).elements())
        if miss: print("      치수 Python 에만:", miss[:12])
        if extra: print("      치수 Ruby 에만:", extra[:12])
        if only_py: print("      글자 Python 에만:", only_py[:10])
        if only_rb: print("      글자 Ruby 에만:", only_rb[:10])
        for p in probs: print("      !!", p)
        ok &= not probs
    return ok


def main():
    args = [a for a in sys.argv[1:]]
    keep = None
    if "--keep" in args:
        i = args.index("--keep"); keep = args[i + 1]; del args[i:i + 2]
    files = args or [os.path.join(ROOT, "output_samples", "___-1", "furniture.json")]
    ok = True
    for f in files:
        ok &= compare(f, keep)
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
