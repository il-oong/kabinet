# reference — 사용자 제공 기준 파일 (수정 금지)

| 파일 | 내용 | 용도 |
|---|---|---|
| `final_A.dxf` | **최종본(정답)** — 사용자가 "이게 최종본이야, 이렇게 되어야 해"라고 올린 DXF (원본 업로드명 `149fea82-_____.dxf`) | 양식·구성·치수 표기·NOTE(재질)·레이어의 **기준**. 우리 생성기 결과와 비교할 정답 |
| `original_B.dwg` | 재구성 대상 **원본 도면** DWG (업로드명 `e21d1154-___-1.dwg`) | 가구 치수의 출처. **치수는 바꾸지 않는다**(양식만 최종본 방식으로 적용) |
| `sample_format_original.pdf` | 최초 양식 샘플 PDF 42쪽(판교 푸르지오 그랑블, 2026.04.10) | 도곽·헤더·표제란·선 규칙의 원 양식 |

- 출처: 사용자가 Claude 세션에 직접 업로드(2026-11).
- 이 파일들은 **수정하지 말고** 참고용으로만 쓴다(.dwg 는 AC10xx 바이너리, 읽으려면 aspose-cad 로 DXF 변환 — CLAUDE.md 참조).
- 원칙: 원본(B)의 가구 치수는 해치지 않고 최종본(A)의 양식·규칙만 적용한다. 규칙과 원본 치수가 충돌하면 확인표에 "원본값 / 규칙 적용값"을 병기한다.
- 상세 분석은 `REFERENCE_SPEC.md`(작성 중)와 `SHEET_FORMAT_ANALYSIS.md` 참조.

## 추가 파일
- `original_B_converted.dxf` — `original_B.dwg` 를 aspose-cad 로 변환한 DXF(inch 단위·글자는 폴리선 획·레이어 `0` 워터마크 포함, 8.4MB). 읽기 전용 참고.
- `originals/island_2cf8a67e.dwg`, `originals/island_7f646231.dxf` — 이전 아일랜드 원본 도면.
- `spec/` — `REFERENCE_SPEC.md` 의 시트별 전체 덤프와 샘플 PDF 벡터 추출, `rules.md` 규칙 해설.
- `.gitattributes` 로 DXF diff 는 숨김 처리.
