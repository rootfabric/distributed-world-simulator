# EVO ARCH2 A5 — Repair Map R3

Дата: 2026-09-07  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; production/main/network/Matter authority не изменяются.

## RM-A5-05 — bounded deterministic demand IDs

Fresh review истории A5 сохранил один применимый P2 после RM-A5-01..04.

Проблема: `C.identifier()` разрешает `individual_id` длиной до 128 символов. A5 ранее строил demand id как:

```text
<individual_id>.life.<tick>.<resource>
```

Поэтому корректный 108–128-символьный organism ID порождал `request_id` длиннее 128 символов. `Ports.validate_demand()` отклонял такой запрос как `DEMAND_ID_RESOURCE`, и весь `step_population()` падал, хотя organism state был валиден.

Исправление: lifecycle demand identity теперь строится независимо от длины organism ID:

```text
life/<sha256(individual_id)>/<tick>/<resource>
```

Используется полный 64-символьный SHA-256. Исходный `organism_id` по-прежнему хранится отдельным typed полем demand/grant и не подменяется hash-идентичностью.

Инварианты:

- generated request ID проходит `C.identifier()` / `Ports.validate_demand()`;
- длина generated ID остаётся меньше 128 для всех допустимых A5 ticks/resources;
- разные max-length organism IDs дают разные request IDs в executable witness;
- input-order-independent A4 allocation сохраняется;
- organism identity в `grant.organism_id` остаётся исходной строкой;
- accepted A0–A4 contracts не меняются.

## Acceptance witness

`arch2_a5_reviewer_repairs.gd` расширяется max-length контрпримером:

1. два различных `individual_id` длиной ровно 128 символов проходят A5 state creation;
2. generated demands для обоих имеют bounded/valid request IDs;
3. request ID sets не пересекаются;
4. совместный `step_population()` с реальным non-zero uptake проходит успешно.

После публикации RM-A5-05 все прежние Reviewer/Verifier verdicts считаются stale. Требуются fresh exact Verifier и fresh independent Reviewer нового exact HEAD.
