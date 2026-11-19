# ________ep-1

- 추정 용도: 냉장고장 데코 ep-1/ep-2 (문자 '냉장고장 데코 ep-1', '냉장고장 (1D)', '일반키큰장(2D)') — 냉장고 위 상부장 4칸 + 키큰장 EP 도면 (추정)
- 입력 형식: 텍스트 DXF AC1032 (CP949), DIMENSION 47개·MTEXT 20개 직접 판독
- 크기/구성: W3160 × H2450 × D740: 상부장 610×4(H740, D580 추정) + 일반키큰장 702(2D). EP 판넬 20T(좌우). ep-2 시트는 `________ep-2/` 로 별도 재구성(같은 가구의 2번째 시트)
- 신뢰도: 중간
- 불확실: 냉장고 규격 미표기(자리만 표시), 상부장 깊이 580, EP 위치, 키큰장 선반
- 재생성: `python3 -I tools/sheet/build_generic.py output_samples/________ep-1/furniture.json --name 가구명` (아일랜드는 `build_sheet.py`)
- 산출물: sheet.pdf, sheet.dxf(흰 배경), sheet_dark.dxf(어두운 배경), furniture.json, preview-N.png(60dpi)

## v1.26.1 — 최종본(A) 기준
- 재질 `DOOR : 한솔 엘리 내추럴`·`손잡이 : 목찬넬`, 현장 안내 쪽 포함. `sheet_1대1.dxf` 추가(=sheet.dxf).
- ep-2 와의 관계: 같은 가구 세트. 상부장 높이 ep-1=740, ep-2=540 으로 원본 간 충돌 — 각각 원본값 유지, 사용자 확인 필요. 총폭 ep-1=3160, ep-2=3267(필러 87 + EP 20 포함).
