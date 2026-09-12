# EVO ARCH2 A5 — Repair Map R9

Дата: 2026-09-08  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; accepted A0–A4, production/main/network/Matter authority не изменяются.

Fresh Independent Codex Reviewer завершил review exact source:

```text
HEAD = 5af7fc68d91b4eeac01873925da5ad1af69e176e
TREE = 9397ededeea4236c6d8be652622a8cc93e6d29ca
review completed = 2026-09-08T09:02:59Z
```

и нашёл три новых blocking persisted-state counterexample. Поэтому verifier `34206597997` и этот review после публикации R9 source являются historical/stale и не дают acceptance. Acceptance ref до нового verifier + нового fresh review запрещён.

## RM-A5-15 — reproduction ledger bound to offspring count

Проблема: policy-valid persisted state мог объявить ненулевые `reproduction_count`, `propagule_seq` и schedule, но оставить `resource_ledger.reproduction_transferred` и `reproduction_cost` нулевыми. Общая conservation equation могла оставаться истинной за счёт неизменённых initial/reserves, хотя runtime никогда не создаёт такую историю: `_reproduce()` сначала списывает точный бюджет, затем увеличивает offspring counters.

Для inherited reproduction policy и `C = reproduction_count` validator теперь требует по каждому internal resource:

```text
reproduction_transferred[resource]
== C * reproduction.endowment[resource]
```

и:

```text
reproduction_cost.material_mg == 0
reproduction_cost.water_mg    == 0
reproduction_cost.energy_mj   == C * reproduction.fee_energy_mj
```

Проверка выполняется независимо от общей conservation equation, поэтому compensated tamper — уменьшить paid ledger и вернуть единицу в reserve — fail-closed отклоняется.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_15_reproduction_ledger.gd
```

Oracle сначала создаёт реальный nonzero funded reproduction event с двумя offspring, проверяет точный transfer/cost на каждого ребёнка, затем строит conservation-preserving unpaid-transfer и unpaid-fee counterexamples, проверяет serialize/deserialize rejection и positive canonical roundtrip.

## RM-A5-16 — persisted reproduction requires inherited reproductive modules

Проблема: root-only development state без `reproductive` modules мог заявить policy-aligned positive reproduction history. Runtime требует `required_reproductive_modules` перед каждым reproduction event; accepted A2 interpreter в A5 не удаляет существующие модули и не меняет их role, поэтому текущий phenotype без inherited threshold доказывает невозможность такой истории.

При `event_count > 0` validator теперь компилирует accepted current phenotype и требует:

```text
phenotype.module_roles.reproductive
>= blueprint.life_history.reproduction.required_reproductive_modules
```

Нулевой reproduction history не получает нового требования.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_16_reproductive_module_history.gd
```

Negative control использует root-only development с положительной, иначе policy-valid history и требует rejection. Positive control реально выращивает reproductive module до maturity, затем выполняет runtime reproduction и проверяет persisted/roundtrip validity.

## RM-A5-17 — reproduction history excludes current starvation window

Проблема: `starvation_ticks = N > 0` означает, что последние `N` lifecycle ticks имели unpaid maintenance. В A5 reproduction на каждом таком tick блокируется `maintenance_paid`, но persisted validator разрешал объявить `last_reproduction_tick` внутри этого окна.

Для `event_count > 0` добавлен temporal invariant:

```text
last_reproduction_tick
<= age_ticks - starvation_ticks
```

При `starvation_ticks == 0` он сводится к уже существующему `last_reproduction_tick <= age_ticks`. Новый death reason не вводится; starvation policy RM-A5-13 сохраняется.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_17_starvation_reproduction_window.gd
```

Oracle сначала получает реальный reproduction event, затем два последовательных unpaid-maintenance ticks. Реальная история остаётся на последнем paid boundary и валидна; tamper, переносящий последний reproduction в первый либо второй starvation window, отклоняется. Проверяется canonical roundtrip валидного boundary state.

## Compatibility repairs for historical witnesses

RM-A5-16 намеренно делает validator строже. Старые reviewer/RM14 tests содержали synthetic positive histories, где private `_reproduce()` вызывался до фактического выращивания reproductive module. Runtime такого состояния не создаёт.

Вместо ослабления нового invariant эти witnesses переведены на достижимый путь:

```text
rich A4 sample/allocation
→ funded A5 growth
→ accepted A2 development
→ real reproductive module
→ reproduction/history checks
```

Общий reviewer assertion contract сохраняется `29/29`; RM-A5-14 assertion contract сохраняется `21/21`.

## Fresh acceptance fence R9

После последнего R9 implementation commit требуется новый immutable HEAD/TREE и fresh fail-closed exact verifier:

```text
cold import
A5 core x2 + byte-identical
A5 reviewer repairs x2 + byte-identical
RM-A5-11 x2 + byte-identical
RM-A5-12 x2 + byte-identical
RM-A5-13 x2 + byte-identical
RM-A5-14 x2 + byte-identical
RM-A5-15 x2 + byte-identical
RM-A5-16 x2 + byte-identical
RM-A5-17 x2 + byte-identical
A4 exact
A0-A3 exact
VIS5.0-VIS5.5
final tracked tree clean
```

Verifier обязан fail-closed завершаться на любом `SCRIPT ERROR`, `Parse Error`, `ERROR:` или `FAIL:`; formal success без чистого полного лога не является evidence.

После genuine verifier PASS требуется новый `@codex review` на новом exact HEAD/TREE. Review на `5af7fc68...` считается stale. Только `0 new blocking findings` разрешает immutable research acceptance.
