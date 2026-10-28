# EVO ARCH2 — A4 Environmental Field Interface / Local Conservative Fields R1

Статус: IMPLEMENTATION IN PROGRESS. База: accepted A0–A3 `6f7e267f287eae978d8dac8d54a1b730c4afbfd4`.

## Цель

A4 вводит research-only пространственный слой между организмом и средой:

```text
Organism ports
    ↕
Environment Field Interface
    ↕
Bounded local field cells
```

Это не production World Query, не новый Matter owner и не server-region authority. Поля содержат owner/revision metadata только как будущий contract shape и reject stale writes; production binding отложен до отдельного Harness-controlled этапа.

## Разделение величин

Консервативные запасы:

```text
water_mg
nutrient_mg
organic_mg
```

Для каждого поля хранится точный ledger:

```text
current = initial + external_inputs - granted_outputs - explicit_sinks
```

Неконсервативные/derived сигналы:

```text
light        0..1000
temperature  0..1000
competition  0..1000
mechanical   0..1000
```

A4 не объявляет light или temperature материальными запасами.

## Пространственная модель

R1 использует bounded 2D surface patch в координатах мира, миллиметры, row-major cells. `sample(position, extent)` читает только пересекающиеся local cells. Allocation строит bounded cell claims; нет `each organism × every organism`.

## Консервативное распределение

Batch demands нормализуются независимо от входного порядка. Для каждого cell/resource claims распределяются pro-rata integer arithmetic; остаток после floor выдаётся в стабильном порядке request id. Сумма grants никогда не превышает stock.

Deposits и sinks проходят через типизированные effects и отражаются в ledger. Непосредственные `Plant -> Soil/Water` callbacks запрещены.

## Взаимодействие с A2

Field sample адаптируется в `dws.ecology.environment-sample.v2`, который расширяет прежний synthetic environment contract, сохраняя старые A0–A3 fixtures. A2 interpreter получает те же `channels/supports`, но теперь sample содержит source identity owner/epoch/revision/tick/field_hash/cell ids.

A4 не подменяет A5 lifecycle: conservative field grants пока не являются полной моделью оплаченного survival/reproduction.

## Acceptance

- strict malformed/stale/out-of-bounds rejection;
- sample locality;
- deterministic replay и input-order independence;
- exact conservation before/after demands/effects;
- no overdraft under contention;
- field sample реально меняет development outcome одного genotype;
- preserved A0–A3 exact acceptance.

## Local read integrity / cached seal

A4 field state is an opaque sealed value. Each cell has a content-addressed integrity seal and the field has a cached full-state seal. Full cell/conservation validation and resealing happen at create/write/persistence boundaries. `sample()` validates only the fixed-size header and the cells intersecting the query, then reports the already verified cached field seal as provenance. It does not recompute a full-field hash on every organism read. Arbitrary external mutation of the returned Dictionary is outside the field API contract and is rejected by the next full write/persistence validation; mutation through field methods always reseals before returning.
