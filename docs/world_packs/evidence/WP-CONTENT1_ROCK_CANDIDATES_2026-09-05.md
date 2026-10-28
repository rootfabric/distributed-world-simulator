# WP-CONTENT1 — Milestone Evidence: ROCK_AND_CLIFF_CANDIDATES

- Track: `WP-CONTENT1`
- Branch: `work/world-packs-content1-cc0-library-r1`
- Implementation commit (tested_head): `6ef34fb8c6ad4ff741b82191c5fe7650463dc044`
- Date (UTC): 2026-09-05
- Milestone: `ROCK_AND_CLIFF_CANDIDATES`

## Deliverables

- `config/world_packs/library/candidates/rock_cliff/polyhaven-rock-face.v1.json`
- `config/world_packs/library/candidates/rock_cliff/polyhaven-rock-face-03.v1.json`
- `tests/world_packs/content_catalog/test_source_policy.py` — добавлен тест
  присутствия ≥2 rock_cliff descriptors с анти-выдумкой hash.

## Provenance basis

Факты взяты ТОЛЬКО из зафиксированных наблюдений страниц источников в
`docs/world_packs/RESEARCH_AND_SOURCES_RU.md` (проверено 2026-09-05):

- `polyhaven.com/a/rock_face` — 1K–16K, полный перечисленный PBR set,
  2.4 m width, reddish weathered rock; авторы Dario Barresi / Greg Zaal
  (наблюдались на странице).
- `polyhaven.com/a/rock_face_03` — rock/cliff PBR до 16K; автор на странице
  не наблюдался → честный `null`, не выдуман.
- Лицензия CC0 (assets): `polyhaven.com/license`; previews/logos сайта
  не считаются CC0 (applies_to = downloadable_assets).

Все descriptors: `review_status=discovery`, `sha256=null`,
`expected_bytes=null`, `pbr_maps_observed=[]` до выбора конкретного
варианта. Никаких measured/mineral claims — класс photogrammetry,
`measured_reference=false`.

## Validation

На точном implementation HEAD `6ef34fb8` (после push):

```
python -m pytest tests/world_packs/content_catalog -q
14 passed
```

## Boundaries respected

- Никаких payloads в Git; только JSON descriptors.
- Дополнительно проверено через web_search: независимого подтверждения
  per-asset авторов rock_face_03 не найдено → автор остался null.
