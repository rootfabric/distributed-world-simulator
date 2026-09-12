# EVO ARCH2 A5 — Regulatory Growth + Resource-Funded Survival/Reproduction R1

Дата: 2026-09-06  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
База: immutable `acceptance/eco-evo-arch2-a4-r1` → `4b0f772ff39592262b853f7293bbd5403558b145`.

## Назначение

A5 добавляет первый bounded lifecycle поверх принятых A0–A4 контрактов. Он не меняет GenomeV2, BodyGraph, A2 interpreter или A4 field contracts. Вместо этого вводится аддитивный наследуемый `OrganismBlueprintV1`, объединяющий принятый `OrganismGenomeV2` с целочисленной `LifeHistoryProgramV1`.

Целевая цепочка A5:

```text
OrganismBlueprintV1
  GenomeV2 + inherited LifeHistoryProgramV1
                ↓
OrganismLifeStateV1
  metabolic reserves + explicit source/sink ledger
                ↓
A4 local sample + typed resource demands
                ↓
A4 deterministic shared allocation
                ↓
actual grants → assimilation
  nutrient + organic → internal material
  water             → internal water
  light             → explicitly recorded external energy source
                ↓
maintenance
                ↓
regulatory growth budget → accepted A2 interpreter
                ↓
survival / starvation
                ↓
funded reproduction → bounded propagule
```

## Главное изменение относительно прежних ECO experiments

A5 не использует `net_resource_proxy`, top-K, synthetic fitness rank или принудительное удаление худших особей. Runtime сортирует только идентификаторы для детерминизма. Биологический исход возникает из доступных stock, allocation, maintenance, regulation и способности оплатить развитие/размножение.

Это ещё не полный population evolution runtime: A3 mutation/crossover не вызываются автоматически при рождении. A5 propagule наследует точный blueprint родителя. Подключение наследуемой мутации к population reproduction должно быть отдельным последующим bounded этапом, чтобы не смешивать жизненный цикл и оператор эволюции.

## Наследуемая life-history policy

`LifeHistoryProgramV1` использует только integer/fixed-point параметры:

- basal/per-absorber uptake для `water_mg`, `nutrient_mg`, `organic_mg`;
- growth gates по light/water/temperature/competition;
- photosynthesis conversion с явным external-energy source;
- maintenance water/energy costs;
- fraction/caps для growth transfer;
- starvation tolerance;
- maturity, reproduction interval, required reproductive modules;
- bounded offspring count, exact offspring endowment и reproduction fee.

Policy входит в biological hash `OrganismBlueprintV1`, то есть это наследуемая биологическая программа, а не renderer/profile setting.

## Resource accounting

A5 хранит два разделённых ledger-а:

1. A4 world field ledger — authoritative для исследовательского local field;
2. A5 organism ledger — authoritative только для research lifecycle candidate.

Организм явно записывает:

```text
initial founder / parent-transfer endowment
field_intake:
  water_mg
  nutrient_mg
  organic_mg
external_energy_mj
assimilated internal resources
maintenance debit
growth transfer to A2
reproduction transfer to propagules
reproduction cost
remaining metabolic reserves
```

Инвариант на каждый internal resource:

```text
initial + assimilated
==
metabolic_reserves
+ maintenance
+ growth_transferred
+ reproduction_transferred
+ reproduction_cost
```

Дополнительно:

```text
assimilated.material_mg == field_intake.nutrient_mg + field_intake.organic_mg
assimilated.water_mg    == field_intake.water_mg
assimilated.energy_mj   == external_energy_mj
```

Таким образом энергия от света не маскируется как будто она пришла из консервативного A4 stock.

## Priority / survival semantics

Порядок tick фиксирован:

```text
sample
→ shared A4 allocation
→ assimilation
→ maintenance
→ regulatory growth
→ reproduction
```

Если maintenance полностью не оплачен, новый growth tick не запускается. `starvation_ticks` увеличивается; при достижении inherited limit особь становится `alive=false`. Мёртвая особь остаётся в state/population и не удаляется top-K механизмом. Corpse/decomposition возврат в environment намеренно отложен до A6 persistent environmental feedback; поэтому её body/reserves не исчезают из ledger.

## Regulatory growth

Growth activation вычисляется из inherited thresholds и текущих A4 channels:

- minimum light;
- minimum water;
- temperature window;
- maximum competition.

После gate используется deterministic permille activation. Только оплаченная часть `metabolic_reserves` переводится в accepted A2 development state. A5 не вызывает старый synthetic unlimited grant path.

## Reproduction

Размножение требует одновременно:

- `alive=true`;
- оплаченный maintenance;
- maturity age;
- reproduction interval;
- достаточное число реальных `reproductive` modules в phenotype;
- полную оплату offspring endowment и reproduction fee.

Сначала выполняется atomic parent debit, затем создаётся bounded typed `PropaguleV1`. Child materialization получает ровно оплаченный endowment, а его A2 body начинает с нулевым `received`, поэтому ткань не создаётся бесплатно.

Вместо прежнего потенциального eager `for seed_count` A5 ограничивает одно событие максимум четырьмя propagules, а весь population step — максимум 512 propagules.

## Shared-resource population step

`ResourceLifecycleRuntimeV1.step_population()`:

- принимает до 128 individuals;
- делает sample каждого living individual;
- собирает все resource demands;
- вызывает один общий A4 deterministic allocation;
- только после этого обновляет индивидуальные lifecycle states;
- возвращает population в canonical ID order.

Это важно: особи в одном поле действительно конкурируют за один stock, а не получают ресурсы последовательными private callbacks.

## Acceptance scenarios R1

Focused exact oracle проверяет:

- strict policy/blueprint/lifecycle contracts;
- explicit founder endowment и отсутствие бесплатного A2 body grant;
- field→organism exact mass intake;
- explicit external light energy provenance;
- same blueprint / rich vs dark regulatory growth divergence;
- starvation death without rank deletion;
- funded parent reproduction;
- same blueprint with no resource funding cannot reproduce;
- child endowment exactly equals parent transfer;
- two-individual shared contention is pro-rata and input-order independent;
- lifecycle + field restart replay equals uninterrupted execution.

Focused pre-publication result:

```text
EVO_ARCH2_A5_EXACT assertions=69 failed=0
```

## Authority boundary

A5 R1 остаётся `RESEARCH_ONLY`.

Не заявляется:

- production ecology authority;
- canonical World Query/Matter owner;
- server-region lifecycle authority;
- network replication;
- canonical persistence promotion;
- full population genetics/evolution;
- decomposition/niche feedback (A6);
- main merge.

A5 может быть принят только как exact research source после fresh independent Reviewer + fresh exact Verifier. Global PC0 RED не может быть автоматически переименован в GREEN.


## Финальный focused evidence

```text
EVO_ARCH2_A5_EXACT assertions=69 failed=0
fresh process x2: byte-identical
log SHA-256: 1e7cfe8c41052b71571a0b2df0761efcc417c8e170ffb930e9e9d192fd93a0d1
```


## RM-A5-01 — cross-ledger A2 transfer seal

Lifecycle validation теперь требует `resource_ledger.growth_transferred == development.received` по каждому internal resource. Это связывает metabolic ledger с accepted A2 resource ledger и fail-closed отклоняет snapshots с межконтурной рассинхронизацией.
