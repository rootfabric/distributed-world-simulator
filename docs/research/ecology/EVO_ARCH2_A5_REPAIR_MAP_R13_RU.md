# EVO ARCH2 A5 — Repair Map R13

Дата: 2026-09-09  
Work Order: `EVO-ARCH2-A5-20260906-R1`

## Источник новых findings

После review-round на `5477a030a23794e2d31663c82edcae6abd6cae85` в PR #573 появились два дополнительных P2 causal finding сверх уже закрытых RM23/RM24.

## RM-A5-25 — Reproductive-module-aware maintenance history

Finding: RM22 доказывал минимальное число оплаченных maintenance ticks, но каждый такой tick оценивал только стоимостью одного root module. После реального reproduction существование inherited `required_reproductive_modules` уже доказано, а accepted A2 не удаляет модули. Значит последующие доказуемо оплаченные ticks должны оплачивать как минимум root + эти reproductive modules.

Repair использует только доказуемый lower bound, без попытки восстановить полную морфологическую историю:

1. `required_paid_ticks` сохраняет прежний root-level bound:
   `max(event_count, survival_paid_ticks, development.grant_seq)`.
2. Для ненулевой reproduction history вычисляется latest possible first reproduction tick:
   `last_reproduction_tick - (event_count - 1) * interval_ticks`.
3. После него lower bound числа paid ticks берётся как максимум из:
   - последующих reproduction events;
   - survival-required paid ticks в suffix;
   - development grants, которые по pigeonhole principle не могли поместиться до first reproduction.
4. На каждый такой post-reproduction paid tick добавляется стоимость `required_reproductive_modules` поверх уже учтённого root.

Такой bound консервативен: он не начисляет maintenance за collector/support modules, если persisted state не доказывает, когда именно они появились.

Executable oracle:
`validation/ecology/evo_arch2_a5/rm_a5_25_reproductive_module_maintenance_history.gd`

Oracle создаёт реальную reproduction/development history, затем conservation-preserving refund до старого root-only floor. Новый validator обязан отклонить его. Exact новый conservative floor остаётся допустимым положительным контролем.

## RM-A5-26 — Development excludes current starvation window

Finding: `development.tick`/`grant_seq <= age_ticks` недостаточно. Последние `starvation_ticks` lifecycle ticks гарантированно были unpaid-maintenance ticks, а `_advance_development()` на них не вызывается.

Repair:

```text
development.tick      <= age_ticks - starvation_ticks
development.grant_seq <= age_ticks - starvation_ticks
```

Executable oracle:
`validation/ecology/evo_arch2_a5/rm_a5_26_development_starvation_window.gd`

Oracle берёт реальную funded development history, затем заявляет согласованный alive starvation suffix без изменения A2 state. Старый validator принимал такой splice; новый обязан отклонить его до ledger checks. Boundary `development.grant_seq == age_ticks - starvation_ticks` остаётся допустимым.

## Acceptance

A5 остаётся `READY_FOR_FRESH_ACCEPTANCE`, но не ACCEPTED. Нужны fresh exact verifier и fresh independent review на одном immutable final HEAD/TREE для RM-A5-01..26.