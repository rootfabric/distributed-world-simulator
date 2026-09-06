# WP-CONTENT1 — Milestone Evidence: ICE_AND_SNOW_CANDIDATES

- Track: `WP-CONTENT1`
- Branch: `work/world-packs-content1-cc0-library-r1`
- Implementation commit (tested_head): `717e5d91eb353d4d34274c153c470b1b7262c74c`
- Date (UTC): 2026-09-05
- Milestone: `ICE_AND_SNOW_CANDIDATES`

## Deliverables

- `config/world_packs/library/candidates/ice/ambientcg-ice001.v1.json`
- `config/world_packs/library/candidates/snow/ambientcg-snow001.v1.json`
- coverage-тесты: ice ≥1, snow ≥1, и полный минимальный discovery-набор
  (rock_cliff, sand_gravel, soil_ground, ice, snow).

## Provenance basis (observed-only, из RESEARCH_AND_SOURCES_RU.md, 2026-09-05)

- `ambientcg.com/view?id=Ice001` — procedural PBR archives 1K–4K, JPG/PNG.
  Каналы/transmission не заявлены до распаковки выбранного archive.
- `ambientcg.com/view?id=Snow001` — procedural PBR archives 1K–8K, JPG/PNG.
- Лицензия CC0 (assets + previews) по `docs.ambientcg.com/license/`.
  Авторы на страницах не наблюдались → `null`.

Оба: `review_status=discovery`, hashes null, `measured_reference=false`,
без planetary-ice optics claims; `matter/water-ice` семантика не затронута.

## Validation

На точном implementation HEAD `717e5d91` (после push):

```
python -m pytest tests/world_packs/content_catalog -q
17 passed
```
