# WP-CONTENT1 — License & Provenance Audit (2026-09-05)

Milestone: `LICENSE_AND_PROVENANCE_AUDIT`.
Аудит затрагивает все descriptors, хранящиеся в
`config/world_packs/library/candidates/**` на HEAD этого документа.

## Аудит-правила (maшино-проверены тестом `test_license_and_provenance_audit`)

1. Каждый descriptor принадлежит ровно одной lane:
   - **baseline redistributable** — `fidelity_tier != reference_only`,
     `review_status != rejected`; лицензия ∈ {CC0-1.0, PDDL-1.0} с
     verification record (`method != not_verified`, есть `verified_url`);
   - **reference_only** — `fidelity_tier == reference_only`; permissive
     expression допускается только с verification record;
   - **rejected** — `review_status == rejected` + обязательный
     `rejection_reason`.
2. Никакой measured claim без `measured_evidence_url`.
3. Author ≠ null только при `author_observed_on`.

## Результаты по кандидатам

| candidate_id | lane | license | verified | author | measured | verdict |
|---|---|---|---|---|---|---|
| candidate/polyhaven/rock-face | baseline | CC0-1.0 (polyhaven.com/license) | page_license_statement 2026-09-05 | Dario Barresi / Greg Zaal (observed) | false | OK |
| candidate/polyhaven/rock-face-03 | baseline | CC0-1.0 (polyhaven.com/license) | page_license_statement 2026-09-05 | null (не наблюдался — не выдуман) | false | OK |
| candidate/polyhaven/gravelly-sand | baseline | CC0-1.0 (polyhaven.com/license) | page_license_statement 2026-09-05 | Dario Barresi (observed) | false | OK |
| candidate/ambientcg/ground037 | baseline | CC0-1.0 (docs.ambientcg.com/license/) | page_license_statement 2026-09-05 | null (не наблюдался) | false | OK |
| candidate/ambientcg/ice001 | baseline | CC0-1.0 (docs.ambientcg.com/license/) | page_license_statement 2026-09-05 | null (не наблюдался) | false | OK |
| candidate/ambientcg/snow001 | baseline | CC0-1.0 (docs.ambientcg.com/license/) | page_license_statement 2026-09-05 | null (не наблюдался) | false | OK |

## Выводы

- Все 6 кандидатов — baseline redistributable lane, CC0, без measured
  claims; научная provenance нигде не заявлена (классы
  photogrammetry/procedural, artistic использование).
- Known gap (из research): basalt / metal-rich / measured asteroid
  материалами библиотека НЕ располагает; artistic analogues честно
  помечены. Фиктивных measured-эталонов не создаём.
- Требование к будущему onboarding: `bytes_verified` возможен только после
  реальной загрузки и хеширования (WP-ASSET1 / integration), не в discovery.
- Fab/reference-only источники в baseline library не смешиваются (lane
  separation policy §3 SOURCE_POLICY_RU.md).

Проверка: `python -m pytest tests/world_packs/content_catalog -q` — 18 passed
на HEAD этого milestone.
