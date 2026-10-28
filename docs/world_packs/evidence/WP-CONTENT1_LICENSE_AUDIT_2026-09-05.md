# WP-CONTENT1 — Milestone Evidence: LICENSE_AND_PROVENANCE_AUDIT

- Track: `WP-CONTENT1`
- Branch: `work/world-packs-content1-cc0-library-r1`
- Implementation commit (tested_head): `2ad3b948c159f33ad612c34cc35f48540e3a920d`
- Date (UTC): 2026-09-05
- Milestone: `LICENSE_AND_PROVENANCE_AUDIT`

## Deliverables

- `docs/world_packs/sources/LICENSE_AUDIT_2026-09-05_RU.md` — per-candidate
  аудит: lane, license, verification record, author provenance, measured.
- `tests/world_packs/content_catalog/test_source_policy.py` — новый
  machine-gate `test_license_and_provenance_audit` (lane separation,
  baseline = CC0/PDDL + verified; reference_only/rejected — явно; measured
  только с evidence URL).

## Результат аудита

6/6 descriptors → baseline redistributable lane, CC0, verification
records на месте, measured claims = 0, авторы не выдуманы (null там, где
не наблюдались). Basalt/measured gap зафиксирован честно.

## Validation

На точном implementation HEAD `2ad3b948` (после push):

```
python -m pytest tests/world_packs/content_catalog -q
18 passed
```
