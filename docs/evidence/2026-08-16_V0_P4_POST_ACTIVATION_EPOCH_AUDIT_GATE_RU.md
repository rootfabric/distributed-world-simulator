# V0-P4 — post-activation Project Epoch / execution-base audit gate

**Status:** PREPARED / CONTROL-ONLY VALIDATION / NO P4 RUNTIME MUTATION  
**Work Order:** #118  
**P4 branch:** `feature/v0-p4-construction-real-resources`  
**Declared product execution input:** `repair/v0-p3-visual-interaction-r1@ef3ad5f0afc433802d639171d938e4720b3a46ec`  
**Excluded repair:** PR #117 / `11819f6dd1ea3728382a04737d30a5300de622f7`

## Зачем нужен этот gate

Generation-80 refresh PR #98 исправляет старое требование, по которому V0 runtime должен был каждый раз начинаться byte-for-byte от bare `main`. После принятия refresh `main` остаётся владельцем project state / authorization / Project Epoch, но может объявить отдельный exact V0 product execution base.

До первого P4 production commit нужно доказать, что после движения `main` это объявление действительно стало canonical и что P4 branch всё ещё является безопасным потомком именно объявленного P3.1 input, без скрытого импорта #117 и без production mutation до dispatch.

Для этого добавлен:

```text
RUN_V0_P4_POST_ACTIVATION_EPOCH_AUDIT.ps1
```

## Основной запуск после принятия #98

Из чистого checkout P4 branch:

```powershell
.\RUN_V0_P4_POST_ACTIVATION_EPOCH_AUDIT.ps1 `
    -ExpectedHead <EXACT_CURRENT_P4_HEAD>
```

По умолчанию runner делает fresh fetch всех branch refs, проверяет canonical `origin/main`, создаёт временный detached worktree exact main и выполняет post-main V0 machine regression + standard PC0 + directional PC0.

## Machine checks

Runner fail-closed проверяет:

1. clean exact P4 checkout;
2. `origin/main` registry generation `>= 80`;
3. main-owned registry содержит программу V0 и `product_execution_base`;
4. declared branch ровно `repair/v0-p3-visual-interaction-r1`;
5. declared SHA ровно `ef3ad5f0afc433802d639171d938e4720b3a46ec`;
6. `declares_checkpoint_acceptance == false` — execution input не превращается в ложный P2/P3 acceptance;
7. checkpoint catalog содержит `V0_P4_REAL_RESOURCE_CONSTRUCTION`;
8. current goal graph направлен на этот checkpoint;
9. scheduler действительно требует main-declared product execution base;
10. scheduler сохраняет правило, что execution base не является automatic checkpoint acceptance;
11. pre-H0.3 total runtime mutation workers остаются `1`;
12. remote ref `repair/v0-p3-visual-interaction-r1` всё ещё указывает на exact `ef3ad5f0...`;
13. current P4 HEAD является потомком `ef3ad5f0...`;
14. PR #117 exact SHA не является предком P4 HEAD;
15. P4 passport всё ещё declares `base_commit = ef3ad5f0...`;
16. `runtime_paths` до dispatch пуст;
17. весь diff `ef3ad5f0... -> P4 HEAD` до dispatch ограничен owned prebuild paths:
    - `docs/evidence/2026-08-16_V0_P4_*`;
    - `docs/checkpoints/2026-08-16_V0_P4_*`;
    - `tests/construction/test_v0_p4_*`;
    - `RUN_V0_P4_*`;
    - P4 branch passport;
18. в detached exact-main worktree проходит обновлённый V0 machine checkpoint regression;
19. standard Project Control генерирует report на exact main и `overall_health != RED`;
20. directional Project Control генерирует report и `overall_health != RED`.

## Решения

Полный успешный запуск выдаёт:

```text
V0-P4 post-activation epoch/base audit: CONTINUE
```

и пишет derived artifact:

```text
artifacts/control/v0-p4-post-activation/epoch-base-audit.json
```

`CONTINUE` означает только:

- generation-80 canonical routing присутствует;
- declared execution base совпадает с ожидаемым;
- P4 pre-dispatch lineage/scope чисты;
- post-main PC0 не RED.

`CONTINUE` **не является Director dispatch**, не является P4 acceptance и не разрешает merge. Runner прямо оставляет:

```text
director_dispatch_still_required = true
```

После `CONTINUE` остаётся отдельный governance gate:

```text
Director dispatch
    -> execute existing P4.1 RED contract
    -> apply prepared three-file exact-consume repair
    -> GREEN
```

## Диагностический режим

Для проверки только main-declared lineage/base contract без запуска post-main PC0 существует:

```powershell
.\RUN_V0_P4_POST_ACTIVATION_EPOCH_AUDIT.ps1 `
    -ExpectedHead <HEAD> `
    -SkipPostMainProjectControl
```

Успех в этом режиме выдаёт:

```text
BASE_READY_PC0_NOT_RUN
```

и **не разрешает runtime mutation**.

## Fail-closed причины

Ключевые stop-коды включают:

```text
V0_P4_AUDIT_CONTROL_NOT_ACTIVATED
V0_P4_AUDIT_PRODUCT_BASE_BRANCH_MISMATCH
V0_P4_AUDIT_PRODUCT_BASE_SHA_MISMATCH
V0_P4_AUDIT_EXECUTION_BASE_FALSE_ACCEPTANCE
V0_P4_AUDIT_CHECKPOINT_MISSING
V0_P4_AUDIT_PRODUCT_BASE_REF_MOVED
V0_P4_AUDIT_P4_NOT_DESCENDED_FROM_DECLARED_BASE
V0_P4_AUDIT_EXCLUDED_PR117_IMPORTED
V0_P4_AUDIT_UNAUTHORIZED_PRE_DISPATCH_DIFF
V0_P4_AUDIT_MAIN_V0_MACHINE_REGRESSION_RED
V0_P4_AUDIT_STANDARD_PC0_RED
V0_P4_AUDIT_DIRECTIONAL_PC0_RED
```

Любой такой результат означает `REFRESH_REQUIRED` / STOP до production mutation.

## Текущее состояние на момент подготовки

На момент добавления gate:

- canonical `main` всё ещё `09714b6f2681e3b5cf3f2f9e28416cf9a7378304`, generation 79;
- PR #98 exact refresh candidate `24d89d0b22eaa87a94c3343ad8f36e44c808eb0b` открыт и имеет GREEN Project Control, но свежий post-refresh independent verdict ещё не записан;
- P4 branch до этого шага был `c20310cf804374ab515fd7a363b6471c2b933ac0` и не содержал runtime mutation;
- данный шаг добавляет только runner/evidence/passport synchronization;
- prepared P4.1 production patch остаётся неприменённым.

Таким образом ближайший переход после принятия generation-80 становится deterministic и machine-checkable, а не ручной интерпретацией старых инструкций.
