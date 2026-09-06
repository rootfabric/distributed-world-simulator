# EVO ARCH2 A4 — EXACT RESEARCH SOURCE ACCEPTANCE R1

Дата: 2026-09-06

## Verdict

```text
A4 Environmental Field Interface / Local Conservative Fields
RESEARCH_SOURCE_ACCEPTED
```

Это принятие исследовательского source subject. Оно не является merge в `main`, production promotion, передачей World Query/Matter/network ownership или активацией A5.

## Exact immutable subject

```text
implementation branch:
feature/eco-evo-arch2-a4-environment-fields-r1

HEAD:
4b0f772ff39592262b853f7293bbd5403558b145

TREE:
301f57e0f42011c5340ff5dc7bfac98059643831

immutable acceptance ref:
acceptance/eco-evo-arch2-a4-r1
    -> 4b0f772ff39592262b853f7293bbd5403558b145
```

A4 построен поверх принятого A0–A3 subject `6f7e267f287eae978d8dac8d54a1b730c4afbfd4`.

## Что принято

A4 вводит research-only слой локальных environmental fields:

- stable millimetre/cell addressing;
- консервативные `water_mg`, `nutrient_mg`, `organic_mg` stocks;
- exact source/input/output/sink ledger;
- локальные non-conservative signals `light`, `temperature`, `competition`, `mechanical`;
- typed organism sample/demand/effect ports без прямых callback-связей;
- owner / owner_epoch / revision fencing;
- field → A2 development-sample bridge;
- bounded field size/work limits;
- deterministic input-order-independent contention.

## Repair train

### RM-A4-01 — genuine local reads

Первый Reviewer обнаружил, что `sample()` формально посещал одну cell, но перед чтением выполнял full-field validation/hash.

Repair:

```text
READ:
fixed header
+ touched cell integrity seals
+ cached verified field seal provenance

WRITE / CREATE / SERIALIZE / DESERIALIZE:
full conservation + integrity validation
```

Таким образом point/local sample больше не выполняет hidden O(total field cells) scan.

### RM-A4-02 — footprint reachability

Reviewer обнаружил возможность создать поле, часть которого лежала вне диапазона typed sample/demand/effect ports.

Repair требует, чтобы полный X/Z footprint поля находился внутри ±10,000,000 mm address envelope. Недостижимые conservative stocks больше нельзя создать.

Контрольные примеры:

```text
64×64 × 1,000,000 mm from origin 0 -> REJECT
exact ±10,000,000 mm boundary       -> ACCEPT
```

### RM-A4-03 — residual pro-rata fairness

Reviewer обнаружил, что после первичного pro-rata прохода остаток мог забираться лексикографически первым `request_id`.

Repair распределяет residual stock пропорционально текущему unmet demand в каждом `(cell, resource)` bucket. `request_id` используется только для deterministic integer-remainder tie-break.

Контрпример Reviewer-а теперь:

```text
cell stocks: [0, 150]
demands:     a=100, b=100
result:      a=75, b=75
```

Reverse input order даёт те же grants и тот же resulting state hash.

## Fresh independent Reviewer

PR: `#568`.

Fresh review был запрошен только для exact repaired subject:

```text
HEAD = 4b0f772ff39592262b853f7293bbd5403558b145
TREE = 301f57e0f42011c5340ff5dc7bfac98059643831
```

Codex Review Summary:

```text
Completed: 2026-09-06T09:10:04Z
Commit:    4b0f772
New blocking findings: 0
PR reaction: +1 at 2026-09-06T09:10:06Z
```

Все три исторических finding-thread имеют точные repair replies и переведены в resolved после fresh clean review.

```text
Reviewer verdict:
PASS / NO BLOCKING FINDINGS
```

## Fresh exact Verifier

Validation workflow выполнялся read-only на self-hosted Linux runner и checkout-ил exact source SHA, а не validation branch source.

```text
run: 34023700814
job: 101460820886
```

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

### Exact identity

```text
HEAD = 4b0f772ff39592262b853f7293bbd5403558b145
TREE = 301f57e0f42011c5340ff5dc7bfac98059643831
PASS
```

### Cold import

```text
empty .godot
Script Error = 0
Parse Error  = 0
ERROR        = 0
PASS
```

Cold log SHA-256:

```text
ce4b689521630089a9d34e4e8d8a6b9baac2dee391d4e56bd3c94dabbfaefa11
```

### A4 exact

```text
EVO_ARCH2_A4_EXACT
32 / 32 PASS ×2
```

Fresh-process logs byte-identical:

```text
SHA-256:
9219859164b961c5150a44738bd17fac591c548feb01ad237970eb9b07a39df1
```

### A0–A3 preserved regression

```text
86 / 86 PASS
```

### VIS5 preserved regression

```text
VIS5.0   87 / 87   PASS
VIS5.1   70 / 70   PASS
VIS5.2   57 / 57   PASS
VIS5.3  101 / 101  PASS
VIS5.4   92 / 92   PASS
VIS5.5  114 / 114  PASS
---------------------------
TOTAL   521 / 521  PASS
```

Финальная tracked-tree проверка после runtime validation: CLEAN.

```text
Verifier verdict:
PASS
```

## Project Control truth label

Exact Project Control run:

```text
run: 34023681529
HEAD: 4b0f772ff39592262b853f7293bbd5403558b145
result: FAILURE
```

RED не переименован в GREEN. Run продолжает показывать существующий глобальный G/ECO Matter/registry dependency drift. Новый A4-specific owner/scope RED в его findings не наблюдался.

Поэтому:

```text
global_pc0_green_inferred = false
production_promotion      = false
main_integration          = false
merge_requires_human      = true
```

## Что НЕ принято

- A5 lifecycle / survival / reproduction;
- production environment adapter;
- canonical World Query binding;
- canonical Matter binding;
- server-region field authority;
- network replication of A4 fields;
- merge в `main`.

## Closure

```text
A0 Architecture Reconciliation                 ACCEPTED
A1 Genome / Program / Body / Phenotype          ACCEPTED
A2 Bounded Modular Development                  ACCEPTED
A3 Safe Structural Mutation + Morphology Lab V2 ACCEPTED
A4 Environmental Field Interface                ACCEPTED

A0 -> A4 research architecture train:
ACCEPTED
```

Следующий этап должен открываться новым bounded Work Order; существующий exact A4 source subject сохраняется immutable evidence.
