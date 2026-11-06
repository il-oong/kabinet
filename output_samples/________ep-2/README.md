# ________ep-2

- 추정 용도: 냉장고장 데코 ep-2 (문자 '냉장고장 데코 ep-2', '주방장 도어 - KK DR 112') — ep-1 과 동일 가구의 두 번째 시트(EP 판재·세부 상세용 추정)
- 입력 형식: 텍스트 DXF AC1032 (ANSI_949 / CP949), DIMENSION 27개·MTEXT 7개 직접 판독
- 크기/구성: W3160 × H2450 × D740: 상부장 610×4 (H740, D580) + 일반키큰장 702 (2D, H2450, D740). EP 판넬 20T (좌/우)
- 추가 반영(ep-2 세부): 키큰장 내부 선반 4장 (z=385/1057/1419/1781, ep-2 세부 치수 362.5·672 반영/추정), 도어 힌지 방향은 원도면 참조
- 신뢰도: 중간 (ep-1 와 동일 가구 — ep-2 는 EP·세부 확인용)
- 불확실: 냉장고 규격 미표기(자리만 표시), 상부장 깊이 580, 선반 간격, EP 세부 치수, 도어 열림 방향(힌지) 자동 반영 없음
- 재생성: `python3 -I tools/sheet/build_generic.py output_samples/________ep-2/furniture.json --name '냉장고장 데코 ep-2'`
- 산출물: sheet.pdf, sheet.dxf(흰 배경), sheet_dark.dxf(어두운 배경), furniture.json, preview-N.png(60dpi)
