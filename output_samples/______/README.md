# ______

- 추정 용도: 주방 하부장 (문자 '주방 하부장', '조리장(2D)B', '서랍장(2단)M')
- 입력 형식: 텍스트 DXF AC1032 (CP949)
- 크기/구성: W1552 × H912(상판 12) × D600: 조리장(2D)B 900 + 서랍장(2단)M 652, 걸레받이 100
- 신뢰도: 중간~높음
- 불확실: 서랍/도어 세부 분할(385/324, 331.5/377.5)은 칸 구성 추정, 싱크 없음
- 재생성: `python3 -I tools/sheet/build_generic.py output_samples/______/furniture.json --name 가구명` (아일랜드는 `build_sheet.py`)
- 산출물: sheet.pdf, sheet.dxf(흰 배경), sheet_dark.dxf(어두운 배경), furniture.json, preview-N.png(60dpi)

## v1.25.7
- 총높이 900 = 상판 12 + 몸통 888(걸레받이 100 포함, 추정) → 순 몸통 788. 양개도어·서랍장 상·하부 목찬넬(전판 상/하/단간 25 틈, 추정). 뷰를 시트 패널 가운데로 정렬. `sheet_1대1.dxf` = 1:1 실치수(블록·DIMENSION 포함).
