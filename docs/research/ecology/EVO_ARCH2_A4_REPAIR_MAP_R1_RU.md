# EVO ARCH2 A4 — Repair Map R1

Дата: 2026-09-06.  
Fresh Reviewer subject: `86aebc9bca53992a182246337de05374ae891dac`.  
Work Order: `EVO-ARCH2-A4-20260906-R1`.

## Reviewer verdict

`FIX_REQUIRED` — один P1 blocking finding: локальный `sample()` формально посещал только затронутые cells, но перед этим `F.validate_state(state)` и `state_hash(state)` выполняли полный O(total cells) scan/hash. Поэтому заявленный locality contract не был настоящим.

## RM-A4-01 — local sample must not scan the full field

**Affected:** `environment_field_contract_v1.gd`, `local_environment_field_v1.gd`, exact A4 acceptance.

**Root cause:** integrity validation и spatial query были слиты в одну операцию. Полная валидация state нужна на mutation/persistence boundary, но не перед каждым organism read.

**Repair:**

- field state стал opaque sealed value;
- каждый cell имеет content-addressed `integrity_hash`;
- field имеет cached full-state `integrity_hash`;
- create/write path делает full validation, conservation validation и reseal;
- persistence `serialize()/deserialize()` остаётся full-validation boundary;
- read path делает только fixed-size `validate_read_header()` + validation/hash затронутых cells;
- `sample.source.field_hash` использует уже проверенный cached full-state seal и не сериализует весь field повторно;
- arbitrary external Dictionary mutation не является field API write и будет отвергнута следующим full write/persistence validation.

**Preserved invariants:** exact conservation, owner/epoch/revision fencing, deterministic allocation, canonical serialization, A2 bridge, no production authority.

**Required refresh:** cold import, A4 exact twice byte-identical, A0-A3 regression, VIS5 regression, fresh Reviewer on repaired exact HEAD, fresh exact Verifier on repaired exact HEAD.
