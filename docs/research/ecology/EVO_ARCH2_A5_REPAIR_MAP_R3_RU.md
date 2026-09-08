# EVO ARCH2 A5 — Repair Map R3

Дата: 2026-09-08  
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

## RM-A5-11 — accepted A2 headroom bounds growth handoff

Fresh Reviewer на A5 HEAD `7825822d34b154602040174cdd76d1e0409b3881` обнаружил P2: при почти или полностью заполненном A2 `development.received` новый положительный A5 growth grant мог попасть в `DevelopmentInterpreterV1.begin_tick()` и завершить lifecycle ошибкой `A5_DEVELOPMENT_BEGIN:RESOURCE_OVERFLOW`.

Причина: accepted A2 намеренно ограничивает текущий физический development stock через `B.MAX_STOCK`, а A5 до RM-A5-11 вычислял transfer только из metabolic reserves, inherited policy и environmental activation.

RM-A5-11 ограничивает каждый новый growth grant фактическим свободным A2 headroom:

```text
requested_growth = min(metabolic_fraction, inherited_max_transfer)
accepted_growth  = min(requested_growth, B.MAX_STOCK - development.received)
```

Если headroom исчерпан, передача по этому ресурсу равна нулю. Непринятая часть остаётся в `metabolic_reserves` и не записывается как оплаченный `resource_ledger.growth_transferred`.

Это сохраняет существующий cross-ledger seal:

```text
A5 resource_ledger.growth_transferred == A2 development.received
```

и не требует изменения accepted A2/A4.

Важно: `development.received` в A2 — не произвольный telemetry/lifetime counter. Accepted A2 валидирует:

```text
received == reserves + spent
spent == current body structural cost + branch energy
```

Поэтому искусственно расширять или сворачивать A2 `received` в A5 нельзя без нарушения принятой физической модели. Gross return из body/development обратно в environment или metabolism не вводится скрыто; такой обратный поток относится к отдельному A6 decomposition/environmental-feedback contract и потребует собственного ledger.

## RM-A5-11 bounded witness

Добавлен отдельный oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_11_growth_headroom.gd
```

Он проверяет два boundary-сценария:

1. валидное A5 состояние с `development.received.material_mg == B.MAX_STOCK` выполняет реальный population step без `RESOURCE_OVERFLOW`; новый material остаётся metabolic и не дебетуется как growth;
2. при свободном headroom ровно 7 единиц вычисленный material grant ограничивается ровно 7 единицами.

Дополнительно проверяются bounded A2 received, сохранение A5→A2 transfer seal и валидность итогового lifecycle state.

## Acceptance witness

`arch2_a5_reviewer_repairs.gd` сохраняет прежние Reviewer counterexamples. RM-A5-11 oracle является дополнительным bounded negative/positive control и не заменяет основной A5 exact gate.

После публикации RM-A5-11 все прежние Reviewer/Verifier verdicts считаются stale. Требуются на одном финальном exact HEAD:

1. RM-A5-11 oracle;
2. A5 exact + reviewer-repair gates;
3. A4 exact regression;
4. A0–A3 exact regression;
5. VIS5.0–VIS5.5 regression;
6. fresh independent Reviewer без blocking findings;
7. fresh exact Verifier PASS.

Только после этого создаётся immutable `acceptance/eco-evo-arch2-a5-r1`. Merge/main promotion остаётся отдельным human gate.
