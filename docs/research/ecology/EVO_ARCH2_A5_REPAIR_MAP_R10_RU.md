# EVO ARCH2 A5 — Repair Map R10

Дата: 2026-09-08  
Work Order: `EVO-ARCH2-A5-20260906-R1`  
Scope: research-only; accepted A0–A4, production/main/network/Matter authority не изменяются.

Fresh review exact A5 source `79d3c27c812727ddf59a5c046e7ee10a33d2fb00` после успешного verifier RM-A5-15..17 нашёл три новых causal persisted-state counterexample. Поэтому прежний verifier остаётся historical evidence и не разрешает acceptance до нового exact verifier + нового fresh review.

## RM-A5-18 — propagule materialization bound to exact paid parent state

Проблема: `sequence` и canonical `id` можно было изменить согласованно. Старый `parent_state_hash` проверялся только как синтаксически допустимый hash, поэтому сам propagule не доказывал, что объявленный offspring sequence действительно был оплачен родителем.

Новый fail-closed contract:

```text
materialize_propagule(propagule, blueprint, paid_parent_state)
validate_propagule(propagule, blueprint, paid_parent_state)
```

Структурные проверки propagule выполняются первыми. Для успешной валидации затем обязательно требуется exact paid-parent witness:

```text
LS.validate(paid_parent_state, blueprint) == PASS
paid_parent_state.individual_id == propagule.parent_id
LS.state_hash(paid_parent_state, blueprint) == propagule.parent_state_hash
propagule.sequence ∈ latest paid reproduction event sequence range
propagule.birth_tick == paid parent lifecycle tick == latest reproduction tick
propagule.position_mm == paid parent position
paid_parent_state.last_events contains REPRODUCED
```

Без `paid_parent_state` materialization запрещён. Это намеренно меняет A5 research persistence contract: persisted/queued propagule должен храниться вместе с authoritative exact parent-after-payment receipt либо эквивалентным trusted state record; один mutable propagule не является достаточным доказательством оплаты.

Дополнительно исправлен скрытый provenance defect: раньше `_reproduce()` вычислял `parent_state_hash`, а `REPRODUCED` добавлялся уже после hash. Теперь событие добавляется до `LS.validate()`/`LS.state_hash()`, поэтому hash propagule точно совпадает с возвращаемым parent state.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_18_propagule_paid_parent_binding.gd
```

Oracle проверяет positive materialization, отсутствие witness, coherent `sequence+id` forgery, birth tamper, position tamper и stale parent state.

## RM-A5-19 — reproduction history requires paid maintenance lower bound

Проблема: сохранённый state мог сохранить reproduction history, уменьшить cumulative maintenance ledger и вернуть ту же величину в metabolic reserves. Общая conservation equation оставалась истинной, хотя runtime требует `maintenance_paid` перед каждым reproduction event.

Для `event_count > 0` persistent validator теперь требует минимум одну оплаченную root-module maintenance стоимость на каждое событие:

```text
maintenance.water_mg
>= event_count * metabolism.maintenance_water_per_module_mg

maintenance.energy_mj
>= event_count * metabolism.maintenance_energy_per_module_mj
```

Это консервативная нижняя граница, а не попытка восстановить полный исторический размер тела: runtime может заплатить больше, но не может законно произвести reproduction event с меньшей cumulative оплатой, потому что root module существует всегда.

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_19_reproduction_maintenance_history.gd
```

Oracle получает реальное first-tick reproduction событие с ненулевой water/energy maintenance, затем строит conservation-preserving refund tamper отдельно для water и energy и требует serialize/deserialize rejection.

## RM-A5-20 — A2 development counters bounded by lifecycle age

Проблема: `OrganismStateV1` сам по себе допускает internally-valid development history, но A5 lifecycle раньше не запрещал присоединить её к слишком молодому `OrganismLifeStateV1`. Это позволяло persisted snapshot заявлять morphology, которую A5 ещё не успел вырастить.

A5 может открыть/продвинуть не более одного A2 lifecycle grant/tick за один lifecycle tick, поэтому добавлены causal bounds:

```text
development.tick <= age_ticks
development.grant_seq <= age_ticks
```

Executable oracle:

```text
validation/ecology/evo_arch2_a5/rm_a5_20_development_lifecycle_age.gd
```

Positive witness строится только реальными A5→A2 steps. Затем его lifecycle age уменьшается ниже уже существующей development history без изменения самого internally-valid A2 state; validator обязан fail-closed вернуть `LIFE_DEVELOPMENT_CAUSALITY`.

## Compatibility repairs

Новый propagule contract сделал старые positive witnesses намеренно неполными. Обновлены только A5 tests, которые materialize/validate честно выпущенный propagule: они сохраняют exact parent-after-payment state из того же reproduction result и передают его как witness.

Synthetic offspring counter boundary test использует zero-maintenance policy, потому что его цель — проверить lifetime counter range, а не сфабриковать миллион исторических maintenance payments.

## Fresh acceptance fence R10

После финального implementation HEAD/TREE требуется новый fail-closed exact verifier:

```text
cold import
A5 core x2 + byte-identical
A5 reviewer repairs x2 + byte-identical
RM-A5-11..20 x2 + byte-identical
A4 exact
A0-A3 exact
VIS5.0-VIS5.5
final tracked tree clean
```

Verifier обязан завершаться failure на любом `SCRIPT ERROR`, `Parse Error`, `ERROR:` или `FAIL:`. После verifier PASS требуется новый fresh independent review exact final HEAD/TREE. Только `0 new blocking findings` разрешает immutable research acceptance.
