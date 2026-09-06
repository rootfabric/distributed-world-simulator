# WP-CONTENT1 — CC0 Candidate Library Index (2026-09-05)

Discovery-каталог реальных внешних кандидатов. Все факты — только наблюдённые
на страницах источников (см. `docs/world_packs/RESEARCH_AND_SOURCES_RU.md`
и per-candidate JSON). Никакие bytes не скачаны; SHA-256/expected_bytes
отсутствуют до реального onboarding. Никаких payloads в Git.

| candidate_id | family | lane | license | provenance class | intended families |
|---|---|---|---|---|---|
| candidate/polyhaven/rock-face | rock_cliff | baseline | CC0-1.0 | photogrammetry | fractured-rock |
| candidate/polyhaven/rock-face-03 | rock_cliff | baseline | CC0-1.0 | photogrammetry | fractured-rock |
| candidate/polyhaven/gravelly-sand | sand_gravel | baseline | CC0-1.0 | photogrammetry | sand |
| candidate/ambientcg/ground037 | soil_ground | baseline | CC0-1.0 | photogrammetry | soil-ground |
| candidate/ambientcg/ice001 | ice | baseline | CC0-1.0 | procedural | ice |
| candidate/ambientcg/snow001 | snow | baseline | CC0-1.0 | procedural | snow |

Descriptors: `config/world_packs/library/candidates/<family>/*.v1.json`
(schema: `config/world_packs/library/candidates/schema/candidate_source.v1.json`).

## Явные non-claims

- Ни один кандидат не является measured basalt / planetary ice /
  lunar regolith эталоном; все — честно помеченные artistic/
  photogrammetry/procedural surface looks.
- measured basalt / metal-rich asteroid материалы в библиотеке ОТСУТСТВУЮТ
  (зафиксированный gap, фиктивные эталоны не создаются).
- Fab и иные reference-only источники в baseline не входят (lane policy,
  `docs/world_packs/sources/SOURCE_POLICY_RU.md`).

## Следующий шаг (integration)

Выбор конкретных small variants (1K/2K), фактическая загрузка и хеширование
через WP-ASSET1 fetch/cache, `review_status → bytes_verified`, затем
surface family binding (WP-SURFACE1).
