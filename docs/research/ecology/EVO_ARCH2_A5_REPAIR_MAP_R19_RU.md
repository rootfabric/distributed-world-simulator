# EVO ARCH2 A5 — Repair Map R19

Дата: 2026-09-09  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## RM-A5-31 — RM26 oracle validity repair

Источник: exact RM30 verifier на `3b6d1675ca9668f946265c8ce86e12dbae6b5e1d` впервые падал на `rm_a5_26_development_starvation_window.gd` до выполнения causal assertions: `funded_runtime_witness_runs`.

Root cause оказался в validation fixture, а не в A5 runtime. Oracle строил development program с `differentiate("support", ...)`, тогда как canonical `DevelopmentProgramV1.validate_action()` запрещает `differentiate` для ролей `support` и `transport`. Поэтому `_genome()` возвращал invalid/empty genome, далее blueprint/founder были пустыми, а `step_population()` закономерно не мог создать funded runtime history.

Repair:

1. invalid `differentiate("support", [0,10,0], 1)` заменён на canonical `extend("support", [0,10,0], 1)`;
2. добавлены explicit positive setup controls `blueprint_valid` и `founder_valid`;
3. `_run_ticks()` теперь сохраняет исходный `result.error`, чтобы setup/runtime failure больше не маскировался общим `funded_runtime_witness_runs`;
4. semantic target RM26 не менялся: persisted A2 `tick/grant_seq` должны укладываться в `age_ticks - starvation_ticks`.

После добавления двух setup controls ожидаемый oracle marker: `EVO_ARCH2_A5_RM26 assertions=11 failed=0`.

Это test/evidence repair. Production/runtime A5 semantics этим RM не изменяются.

## Verifier process repair

Параллельно устранён инфраструктурный fan-out validation-ветки: исторические `evo-arch2-a5-exact-verifier-r10.yml` … `r17.yml` удалены из текущего validation tree. Оставлен один canonical A5 verifier с `concurrency.group=eco-arch2-a5-canonical-verifier` и `cancel-in-progress=true`. Старые уже созданные GitHub runs остаются историческим хвостом очереди, но новые pushes больше не размножают A5 jobs.

## Acceptance

A5 остаётся `READY_FOR_FRESH_ACCEPTANCE`. Требуются exact canonical verifier и fresh independent review на одном финальном RM-A5-01..31 HEAD/TREE.
