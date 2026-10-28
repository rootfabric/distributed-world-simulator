# WP-CONTENT1 — Milestone Evidence: SOURCE_POLICY

- Track: `WP-CONTENT1`
- Branch: `work/world-packs-content1-cc0-library-r1`
- Implementation commit (tested_head): `d1ea1bce8a36ca7e79d2aae40369769dfed159a4`
- Date (UTC): 2026-09-05
- Milestone: `SOURCE_POLICY`

## Deliverables

- `config/world_packs/library/candidates/schema/candidate_source.v1.json` —
  JSON Schema (`urn:dws:world_packs:candidate_source:1`) для candidate
  descriptors: family, review_status, upstream identity, license с
  verification-записью, observed facts (sha256/expected_bytes/pbr maps),
  provenance class, intended use.
- `docs/world_packs/sources/SOURCE_POLICY_RU.md` — политика «только
  доказанные факты»: запрет придуманных SHA-256/expected bytes/PBR
  channels/автора/measured provenance до фактической проверки; lanes
  (baseline redistributable / reference_only / rejected); no-payload gate.
- `tests/world_packs/content_catalog/test_source_policy.py` — focused tests.

## Policy invariants, enforced tests

1. `observed.sha256` / `expected_bytes` обязаны быть `null`, пока
   `review_status != bytes_verified` (анти-выдумка hashes).
2. `bytes_verified` требует реальный 64-hex sha256 + expected_bytes > 0.
3. `upstream.author` ≠ null ⇒ обязателен `author_observed_on` URL.
4. `measured_reference=true` ⇒ обязателен `measured_evidence_url`.
5. Все URL — https; конкретный `license.expression` требует verification record.
6. `rejected` требует `rejection_reason`.
7. `pbr_maps_observed` ⊆ известного списка или пустой.
8. No-payload gate: под candidates/** только .json/.md, каждый ≤ 256 KiB.

## Validation

Focused (на точном implementation HEAD `d1ea1bce`, после push):

```
python -m pytest tests/world_packs/content_catalog -q
13 passed
```

Regression scope:

```
python -m pytest tests/world_packs -q
81 passed, 1 failed
```

Единственный failure — `tests/world_packs/test_library_contract.py::test_local_missing_symlink_and_corruption`
падает по environmental причине Windows (создание symlink без привилегии,
`OSError WinError 1314`). Не связан с изменениями WP-CONTENT1; файл вне
allowed paths трека. Первый (низкий) приоритет: перезапуск от администратора
или в среде с включённым Developer Mode.

## Boundaries respected

- Тяжёлых payloads в Git нет (проверено тестом no-payload gate).
- Канонические simulation/control пути не затронуты; изменены только
  allowed paths WP-CONTENT1.
- Ни один внешний кандидат ещё не записан как descriptor — это следующие
  milestones (ROCK_AND_CLIFF_CANDIDATES и далее).
