#!/usr/bin/env python3
"""기준(최종본) DXF 와 생성 DXF 의 구조를 비교한다 — 시트 구성·레이어·엔티티 종류·텍스트 키워드·스타일.
사용: python3 -I tools/sheet/compare_to_reference.py 기준.dxf 생성.dxf   (종료코드 0 = 허용 범위 내)
기준 = 사용자가 CAD 에서 마무리한 아일랜드 최종본(149fea82-_____.dxf). 같은 프로젝트 다른 가구(B)가 같은 방식인지 확인한다."""
import collections, re, sys
import ezdxf

KEYWORDS = ["경기도 수원시 영통구 광교호수공원로 80", "광교아이파크 101동 4601호", "SITE INFO", "NOTE", "현장 주소", "주의사항",
            "DOOR : 한솔 엘리 내추럴", "손잡이 : 목찬넬", "SITE LOCATION", "PROJECT TITLE", "SHEET NO.", "SUBJECT TITLE",
            "** 8시50분 차량 입차 불가 입니다. 꼭 8시 50분 이후 입차해주세요.", "현관번호 7777"]
CORE_LAYERS = {"OUTLINE", "DIM", "THIN", "FRAME", "TEXT", "NOTE_BLUE", "NOTE_RED", "SHEET_FRAME_INFO"}
KINDS = {"DIMENSION", "HATCH", "TEXT", "LINE", "LWPOLYLINE"}


def info(path):
    d = ezdxf.readfile(path)
    ents = []
    for b in d.blocks:
        if not b.name.startswith("*"):
            ents += list(b)
    ents += [e for e in d.modelspace()]
    sheets = sorted((e.dxf.insert.x, e.dxf.text) for e in d.modelspace() if e.dxftype() == "TEXT" and e.dxf.layer == "SHEET_FRAME_INFO")
    names = [re.sub(r"^\[\d+\]\s*|\s*\(1/.*$", "", t).strip() for _, t in sheets]
    texts = set()
    for e in ents:
        if e.dxftype() == "TEXT":
            texts.add(e.dxf.text.strip())
        elif e.dxftype() == "MTEXT":
            texts.add(e.text.strip())
    return dict(d=d, names=names, layers={e.dxf.layer for e in ents if e.dxf.hasattr("layer")}, kinds=collections.Counter(e.dxftype() for e in ents),
                texts=texts, blocks=[b.name for b in d.blocks if not b.name.startswith("*")],
                dimstyles={s.dxf.name for s in d.dimstyles}, styles={s.dxf.name for s in d.styles}, units=d.header.get("$INSUNITS"))


def main():
    ref, cand = info(sys.argv[1]), info(sys.argv[2])
    ok = True
    def line(label, good, detail=""):
        nonlocal ok
        ok &= bool(good)
        print(f"  [{'OK ' if good else 'FAIL'}] {label} {detail}")
    print("== 기준 vs 생성 구조 비교")
    print("  시트(기준):", ref["names"]); print("  시트(생성):", cand["names"])
    line("첫 시트 = 현장 안내", cand["names"][:1] == ref["names"][:1], f"({cand['names'][:1]})")
    line("마지막 시트 = 확인표", cand["names"][-1:] == ref["names"][-1:])
    allowed = set(ref["names"]) | {"furniture", "photos", "view3d"}
    line("시트 종류가 기준의 부분집합", all(n in allowed or n.startswith("furniture") for n in cand["names"]))
    line("핵심 레이어 모두 존재", CORE_LAYERS <= cand["layers"], f"(없음: {sorted(CORE_LAYERS - cand['layers'])})")
    line("엔티티 종류(DIMENSION/HATCH/TEXT/LINE/LWPOLYLINE) 모두 존재", all(cand["kinds"][k] > 0 for k in KINDS))
    for k in sorted(KINDS):
        print(f"      {k:11s} 기준 {ref['kinds'][k]:6d}  생성 {cand['kinds'][k]:6d}")
    line("블록: FRAME_SHEET*/VIEW_* 구조", any(b.startswith("FRAME_SHEET") for b in cand["blocks"]) and any(b.startswith("VIEW_") for b in cand["blocks"]))
    line("DIMSTYLE KAB·텍스트 스타일 MALGUN·단위 mm", {"KAB"} <= cand["dimstyles"] and "MALGUN" in cand["styles"] and cand["units"] == 4)
    miss = [k for k in KEYWORDS if not any(k in t for t in cand["texts"])]
    refmiss = [k for k in KEYWORDS if not any(k in t for t in ref["texts"])]
    line("키워드(주소·재질·현장 안내·표제란)", not miss, f"(생성에 없음: {miss}; 기준에도 없음: {refmiss})")
    line("BODY 재질 줄 없음(기준은 삭제)", not any(t.startswith("BODY :") for t in cand["texts"]))
    line("힌지 문자 없음", not any(re.search("힌지|hinge|경첩", t, re.I) for t in cand["texts"]))
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
