#!/usr/bin/env python3
"""수동 교차검증: Ruby 로 만든 시트 DXF 를 ezdxf 로 읽어 audit 오류/엔티티 수를 출력.
사용:  python3 -I tools/sheet/verify_dxf.py out.dxf
"""
import collections, sys
import ezdxf

d = ezdxf.readfile(sys.argv[1])
a = d.audit()
print('audit errors:', len(a.errors), [str(e) for e in a.errors][:5])
print('layers:', sorted(l.dxf.name for l in d.layers))
print('entities:', dict(collections.Counter(e.dxftype() for e in d.modelspace())))
print('images:', [i.dxf.get('image_def_handle') for i in d.modelspace().query('IMAGE')])
