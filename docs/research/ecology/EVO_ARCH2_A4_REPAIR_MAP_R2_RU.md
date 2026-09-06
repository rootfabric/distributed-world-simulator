# EVO ARCH2 A4 — Repair Map R2

Дата: 2026-09-06
Work Order: `EVO-ARCH2-A4-20260906-R1`
Scope: research-only A4; production/main/network/Matter ownership не изменяются.

## История

Первоначальный A4 subject `86aebc9b...` получил Reviewer P1: point `sample()` скрыто выполнял full-field validation/hash. `RM-A4-01` в `e2a0cbb...` ввёл cached field/per-cell integrity seals и перенёс полный scan на create/write/persistence boundaries.

Fresh review после RM-A4-01 выявил ещё две проблемы. Этот Repair Map закрывает их совместно; прежние reviewer/verifier verdicts являются historical и не переносятся на новый subject.

## RM-A4-02 — Field footprint / port reachability

Проблема: разрешённая геометрия могла выходить за координатный диапазон typed sample/demand/effect ports (±10,000,000 mm), создавая консервативные stocks, к которым невозможно обратиться.

Исправление:

- единый `MAX_PORT_COORD_MM = 10_000_000`;
- `valid_footprint()` требует, чтобы полный X/Z footprint поля находился внутри этого диапазона;
- `create()` fail-closed отклоняет недостижимое поле;
- `validate_read_header()` повторяет invariant для восстановленного/входного state;
- точный footprint на границе диапазона разрешён.

Acceptance witness:

- `64×64 × 1_000_000 mm` от origin 0 → rejected;
- `origin_x=-10_000_000`, width=20, cell=1_000_000 → exact +10_000_000 boundary accepted.

## RM-A4-03 — Residual allocation must remain pro-rata

Проблема: после основного per-cell pro-rata прохода старый последовательный residual sweep мог отдать остаток лексикографически первому `request_id`.

Reviewer counterexample:

```text
cell stocks: [0, 150]
demands: a=100, b=100, оба охватывают обе cells
old result: 100 / 50
required fair result: 75 / 75
```

Исправление:

- residual stock обрабатывается детерминированно по cell/resource bucket;
- для каждой cell вычисляются текущие unmet amounts всех достижимых demands;
- доступный residual распределяется пропорционально unmet demand;
- `request_id` используется только как стабильный tie-break для целочисленного remainder;
- input array order не влияет на grants или resulting state hash.

Acceptance witness:

```text
[0,150] + 100/100 -> 75/75
forward order == reverse order
```

## Сохранённые инварианты

- exact `water_mg`, `nutrient_mg`, `organic_mg` conservation;
- no overdraft;
- owner / owner_epoch / revision fencing;
- typed organism demand/effect/sample ports;
- RM-A4-01 O(local) sample read path: fixed header + touched cell seals only;
- cached field seal as sample provenance;
- full conservation/integrity validation на create/write/serialize/deserialize boundaries;
- A2 environment bridge;
- research-only authority boundary.

## Focused evidence до публикации

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

```text
EVO_ARCH2_A4_EXACT assertions=32 failed=0
fresh process ×2: byte-identical
log SHA-256: 041ecfcd5a492697b7dd77dd72d892798370517c6142b27ae0c5297c1bad57c8
sample-locality-static: PASS
```

Это implementer evidence. После публикации обязателен fresh exact verifier + fresh independent reviewer на новом exact HEAD.
