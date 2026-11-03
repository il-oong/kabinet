#!/usr/bin/env python3
"""ezdxf 가 쓰는 완전한 R2004(AC1018) DXF 골격(HEADER/CLASSES/TABLES/BLOCKS/OBJECTS)을 뽑아
kabinet/output/sheet/dxf_skeleton.rb 의 SKELETON 상수(@@PLACEHOLDER@@ 포함)로 생성한다.

사용: python3 tools/sheet/gen_dxf_skeleton.py   (ezdxf 1.x 필요)
Ruby DxfWriter 가 이 골격에 레이어/스타일/엔티티/IMAGEDEF 만 끼워 넣는다 — Ruby 쪽에는 ezdxf 불필요.
"""
import os
import sys
import tempfile
import ezdxf

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'kabinet', 'output', 'sheet', 'dxf_skeleton.rb')


def read_pairs(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    return [(lines[i].strip(), lines[i + 1]) for i in range(0, len(lines) - 1, 2)]


def main():
    d = ezdxf.new('R2004', setup=False)
    idef = d.add_image_def('img_01.jpg', (800, 600))
    d.modelspace().add_image(idef, (0, 0), (100, 75))   # CLASSES 에 IMAGE/IMAGEDEF_REACTOR 가 들어가게(엔티티는 아래에서 제거)
    tmp = os.path.join(tempfile.mkdtemp(), 'skel.dxf')
    d.saveas(tmp)
    P = read_pairs(tmp)
    out = []
    i = 0
    n = len(P)

    def setval(code, val, start):
        for k in range(start, n):
            if P[k][0] == code:
                P[k] = (code, val)
                return k
        raise KeyError(code)

    # --- HEADER 치환
    def hdr(var, subs):
        k = next(j for j, (c, v) in enumerate(P) if c == '9' and v == var)
        for code, val in subs:
            setval(code, val, k + 1)
    hdr('$DWGCODEPAGE', [('3', 'ANSI_949')])
    hdr('$HANDSEED', [('5', '@@HANDSEED@@')])
    hdr('$EXTMIN', [('10', '@@EXTMINX@@'), ('20', '@@EXTMINY@@'), ('30', '0.0')])
    hdr('$EXTMAX', [('10', '@@EXTMAXX@@'), ('20', '@@EXTMAXY@@'), ('30', '0.0')])
    hdr('$LIMMAX', [('10', '@@EXTMAXX@@'), ('20', '@@EXTMAXY@@')])
    hdr('$LWDISPLAY', [('290', '1')])
    hdr('$INSUNITS', [('70', '4')])
    hdr('$LTSCALE', [('40', '@@LTSCALE@@')])
    hdr('$DIMSTYLE', [('2', 'Standard')])
    hdr('$TEXTSTYLE', [('7', 'Standard')])

    # --- 구역 인덱스
    def sec_range(name):
        s = next(j for j in range(n) if P[j] == ('0', 'SECTION') and P[j + 1][1] == name)
        e = next(j for j in range(s, n) if P[j] == ('0', 'ENDSEC'))
        return s, e
    # ENTITIES: IMAGE 제거 -> @@ENTITIES@@
    s, e = sec_range('ENTITIES')
    P[s + 2:e] = [('@@', 'ENTITIES')]
    n = len(P)

    # TABLES: VPORT 중심/높이, LAYER/STYLE 훅
    s, e = sec_range('TABLES')
    vp = next(j for j in range(s, e) if P[j] == ('2', '*Active'))
    setval('12', '@@VPCX@@', vp); setval('22', '@@VPCY@@', vp); setval('40', '@@VPH@@', vp)

    def table_hook(tname, token):
        s, e = sec_range('TABLES')
        t = next(j for j in range(s, e) if P[j] == ('2', tname) and P[j - 1] == ('0', 'TABLE'))
        # 개수(70)
        k = next(j for j in range(t, e) if P[j][0] == '70')
        base = int(P[k][1])
        P[k] = ('70', '@@%s_COUNT@@' % token)
        endtab = next(j for j in range(k, e) if P[j] == ('0', 'ENDTAB'))
        P[endtab:endtab] = [('@@', token)]
        return base
    base_layers = table_hook('LAYER', 'LAYERS')
    base_styles = table_hook('STYLE', 'STYLES')
    table_hook('BLOCK_RECORD', 'BLOCKRECS')
    n = len(P)
    # BLOCKS: 사용자 정의 블록 훅(ENDSEC 직전)
    bs_, be_ = sec_range('BLOCKS')
    P[be_:be_] = [('@@', 'BLOCKS')]
    n = len(P)

    # OBJECTS: IMAGEDEF/REACTOR 제거, ACAD_IMAGE_DICT 항목 훅
    s, e = sec_range('OBJECTS')
    dict_h = None
    for j in range(s, e):
        if P[j] == ('3', 'ACAD_IMAGE_DICT'):
            dict_h = P[j + 1][1]
    assert dict_h
    # 이미지 딕셔너리 레코드 찾기
    dj = next(j for j in range(s, e) if P[j] == ('5', dict_h) and P[j - 1] == ('0', 'DICTIONARY'))
    # 그 안의 (3 img_01.jpg, 350 x) 쌍 제거 후 훅
    k = next(j for j in range(dj, e) if P[j][0] == '3')
    P[k:k + 2] = [('@@', 'IMAGE_DICT_ENTRIES')]
    n = len(P)
    s, e = sec_range('OBJECTS')
    # IMAGEDEF ~ 다음 DICTIONARYVAR 직전까지 제거(IMAGEDEF, IMAGEDEF_REACTOR)
    a = next(j for j in range(s, e) if P[j] == ('0', 'IMAGEDEF'))
    b = next(j for j in range(a, e) if P[j] == ('0', 'DICTIONARYVAR'))
    P[a:b] = [('@@', 'IMAGE_OBJECTS')]

    max_h = 0
    for c, v in P:
        if c in ('5', '105') and v and not v.startswith('@@'):
            try:
                max_h = max(max_h, int(v, 16))
            except ValueError:
                pass

    body = []
    for c, v in P:
        if c == '@@':
            body.append('@@%s@@' % v)
        else:
            body.append('%3s\n%s' % (c, v))
    text = '\n'.join(body) + '\n'
    text = text.replace('@@ENTITIES@@\n', '@@ENTITIES@@\n')
    assert "DXF_SKEL" not in text
    ruby = '''# 자동 생성 파일 — tools/sheet/gen_dxf_skeleton.py 로 재생성(ezdxf %s 가 쓰는 R2004 골격).
# 직접 수정하지 말 것. @@NAME@@ 자리표시자는 DxfWriter 가 채운다.
module Kabinet
  module Output
    module Sheet
      module DxfSkeleton
        MAX_TEMPLATE_HANDLE = 0x%X
        BASE_LAYER_COUNT = %d
        BASE_STYLE_COUNT = %d
        MODEL_RECORD = '17'   # *Model_Space BLOCK_RECORD 핸들(엔티티 330 소유자)
        IMAGE_DICT = '%s'     # ACAD_IMAGE_DICT 핸들(IMAGEDEF 의 소유자)
        TEXT = <<-'DXF_SKEL'
%sDXF_SKEL
      end
    end
  end
end
''' % (ezdxf.__version__, max_h, base_layers, base_styles, dict_h, text)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(ruby)
    print('wrote', os.path.normpath(OUT), len(text), 'bytes; max handle', hex(max_h), file=sys.stderr)


if __name__ == '__main__':
    main()
