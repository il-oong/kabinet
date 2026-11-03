#!/usr/bin/env python3
"""종이 축척으로 그려진 시트 DXF 를 1:1 실치수(mm)로 변환한다.

사용: python3 -I tools/sheet/to_real_scale.py 입력.dxf [출력.dxf]
 - 시트는 X 방향으로 500mm 간격(폭 420 x 297)으로 놓여 있다고 가정(build_sheet/build_generic 규칙).
 - 시트별 축척은 표제란/평면도의 'SCALE 1/N' 또는 '1/N' 글자에서 읽는다(없으면 25).
 - 각 시트를 자기 원점 기준으로 N 배 확대 → 가구 형상의 1 단위 = 실제 1mm. 시트끼리는 겹치지 않게 재배치.
 - 문자 높이·해칭 패턴 배율도 N 배. 선 굵기는 절대값이라 그대로.
주의: 확대 상세(1/5·1/2 등 별도 배율로 그린 작은 도면)는 시트 배율 N 이 곱해져 '실물 N/k 배' 크기가 된다. 보고서에 표시된다.
"""
import re, sys, collections
import ezdxf
from ezdxf.math import Matrix44

PITCH, W, H = 500.0, 420.0, 297.0
SC_RE = re.compile(r'^(?:SCALE\s*)?1/(\d{1,3})$')

def sheet_index(x):
    return int((x + 40) // PITCH)

def detect_scale(ms, idx):
    x0 = idx * PITCH
    cands = []
    for e in ms:
        if e.dxftype() != 'TEXT': continue
        p = e.dxf.insert
        if not (x0 - 1 <= p.x <= x0 + W + 1 and p.y < 40): continue
        m = SC_RE.match(e.dxf.text.strip())
        if m: cands.append((p.y, int(m.group(1))))
    if not cands:
        for e in ms:
            if e.dxftype() != 'TEXT': continue
            p = e.dxf.insert
            if x0 - 1 <= p.x <= x0 + W + 1 and p.y < 60:
                m = SC_RE.match(e.dxf.text.strip())
                if m: cands.append((p.y, int(m.group(1))))
    return cands[0][1] if cands else 25

def convert(src, dst):
    doc = ezdxf.readfile(src)
    ms = doc.modelspace()
    groups = collections.defaultdict(list)
    for e in ms:
        t = e.dxftype()
        if t == 'TEXT' and e.dxf.layer == 'SHEET_FRAME_INFO':
            pass
        if t in ('LINE',): x = e.dxf.start.x
        elif t in ('TEXT', 'MTEXT'): x = e.dxf.insert.x
        elif t == 'CIRCLE': x = e.dxf.center.x
        elif t == 'LWPOLYLINE':
            pts = list(e.get_points('xy')); x = pts[0][0] if pts else 0
        elif t == 'HATCH':
            from ezdxf import bbox
            b = bbox.extents([e]); x = (b.extmin.x + b.extmax.x) / 2 if b.has_data else 0
        else:
            x = getattr(getattr(e.dxf, 'insert', None), 'x', 0) or 0
        groups[sheet_index(x)].append(e)
    report, cursor = [], 0.0
    for idx in sorted(groups):
        n = detect_scale(ms, idx)
        ox = idx * PITCH
        mat = Matrix44.translate(-ox, 0, 0) @ Matrix44.scale(n, n, n) @ Matrix44.translate(cursor, 0, 0)
        for e in groups[idx]:
            e.transform(mat)
            if e.dxftype() == 'HATCH':
                e.dxf.pattern_scale = e.dxf.pattern_scale * n
        report.append((idx + 1, n, cursor, W * n, H * n))
        cursor += W * n * 1.1
    # 모델 공간 초기 뷰: 첫 시트 전체
    n0 = report[0][1]
    doc.set_modelspace_vport(height=H * n0 * 1.1, center=(W * n0 / 2, H * n0 / 2))
    doc.header['$INSUNITS'] = 4
    doc.header['$LIMMIN'] = (0, 0); doc.header['$LIMMAX'] = (cursor, H * max(r[1] for r in report))
    doc.header['$LTSCALE'] = float(n0)
    doc.saveas(dst)
    return report

if __name__ == '__main__':
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit('.', 1)[0] + '_1to1.dxf'
    for i, n, ox, w, h in convert(src, dst):
        print(f'시트{i}: 1/{n} → x={ox:,.0f} 폭 {w:,.0f} x {h:,.0f} mm')
    print('저장:', dst)
