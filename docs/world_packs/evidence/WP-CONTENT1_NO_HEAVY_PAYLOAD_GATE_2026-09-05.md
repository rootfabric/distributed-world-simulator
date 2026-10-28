# WP-CONTENT1 — Milestone Evidence: NO_HEAVY_GIT_PAYLOAD_GATE

- Track: `WP-CONTENT1`
- Branch: `work/world-packs-content1-cc0-library-r1`
- Implementation commit (tested_head): `ed8c888b1de296b2abb1e0b56bb1d7859f63a169`
- Date (UTC): 2026-09-05
- Milestone: `NO_HEAVY_GIT_PAYLOAD_GATE`

## Deliverables

- `tests/world_packs/content_catalog/test_source_policy.py` — новый gate
  `test_git_tracked_payloads_are_text_and_small`: сканирует именно
  git-tracked файлы (`git ls-files`) под `config/world_packs/library/candidates`
  и `docs/world_packs/sources`; допустимы только .json/.md, размер ≤ 256 KiB,
  отсутствие NUL-байтов (binary payload smell). Плюс ранее существовавший
  working-tree allowlist тест.

## Факты

- В Git под content-paths трека нет ни одного бинарного/тяжёлого файла;
  все payloads (реальные PBR archives) остаются вне Git до separate
  onboarding через WP-ASSET1 content-addressable cache.

## Validation

На точном implementation HEAD `ed8c888b` (после push):

```
python -m pytest tests/world_packs/content_catalog -q
19 passed
```
