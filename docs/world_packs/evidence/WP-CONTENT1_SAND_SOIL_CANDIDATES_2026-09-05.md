# WP-CONTENT1 — Milestone Evidence: SAND_AND_SOIL_CANDIDATES

- Track: `WP-CONTENT1`
- Branch: `work/world-packs-content1-cc0-library-r1`
- Implementation commit (tested_head): `de1387fc99210e261aac985ece5b7fcc4f144c00`
- Date (UTC): 2026-09-05
- Milestone: `SAND_AND_SOIL_CANDIDATES`

## Deliverables

- `config/world_packs/library/candidates/sand_gravel/polyhaven-gravelly-sand.v1.json`
- `config/world_packs/library/candidates/soil_ground/ambientcg-ground037.v1.json`
- coverage-тест sand_gravel ≥1 и soil_ground ≥1.

## Provenance basis (observed-only, из RESEARCH_AND_SOURCES_RU.md, 2026-09-05)

- `polyhaven.com/a/gravelly_sand` — автор Dario Barresi (наблюдался);
  1K–16K; страницы перечисляют diffuse, AO, normal GL/DX, roughness,
  displacement, ARM (записано в `pbr_maps_observed`); 2.5 m width.
- `ambientcg.com/view?id=Ground037` — 1K–8K JPG/PNG PBR archives,
  photogrammetry, ~2.1×2.1 m; сайт сообщает reprocessed color map
  2021-01-24. Автор не наблюдался → `null`. Каналы выбранного archive
  не заявляются (`pbr_maps_observed=[]`).

Оба: `review_status=discovery`, `sha256=null`, `expected_bytes=null`,
без measured claims. ambientCG лицензия CC0 распространяется и на
previews (`applies_to=assets_and_previews`) — как заявлено на
`docs.ambientcg.com/license/`.

## Validation

На точном implementation HEAD `de1387fc` (после push):

```
python -m pytest tests/world_packs/content_catalog -q
15 passed
```
