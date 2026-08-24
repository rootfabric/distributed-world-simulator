# V0 P6 R3 — сводка выполнения Work Order V0-P6-R3-WO-001

Дата: 2026-08-24 (UTC+10)
Ветка: `repair/v0-p6-persistence-exactly-once-r1`
Тестируемый/ревьюируемый HEAD: см. «Exact heads» ниже.
Риск: HIGH (persistence/replay semantics после влитого checkpoint'а,
exactly-once admission, коррекция прежде завышенных claims).

## Exact heads

```text
base (origin/main на старте миссии) ... 9ade3233f8d9f16b77edcc8cf273fe8e649d5637
шаг 5 process-restart gate ............ a070af8af4c7686ef2063cf1644cf52c4e1f60ea
ретракция + event 0004 ................ 9c411aa7...
soak gate + runner .................... dc7ac584c3bc7b22b8ab43159b5bce36e9c0204c
regression fence findings ............. aadab1ca..., b14da054..., <этот коммит>
```

Каждый runtime-прогон выполнялся на закоммиченном состоянии; новые файлы
после финальных прогонов не меняли runtime-scope.

## Реестр предикатов WO (24)

| # | Предикат | Статус | Доказательство |
|---|----------|--------|----------------|
| 1 | PROJECT_EPOCH_CREATED | PASS | executions/E2026-08-24-V0-P6-R3/project-epoch.v1.json |
| 2 | V0_P6_R3_WORK_ORDER_ISSUED | PASS | work-orders/V0-P6-R3-WO-001.v1.json |
| 3 | V0_P6_R3_REPAIR_MAP_READY | PASS | repairs/V0-P6-R3-REPAIR-MAP-001.v1.json |
| 4 | PRIVATE_PERSISTENCE_REMOVED_PASS | PASS | focused suite 16/16 (`PRIVATE_PERSISTENCE_REMOVED_PASS`), a070af8a |
| 5 | CANONICAL_OWNER_COMPOSITION_PASS | PASS* | suite 16/16; *scope: fixtures с контрактной формой owners; live-surface proof помечен scope-маркером теста |
| 6 | PENDING_RETRY_FAIL_CLOSED_PASS | PASS | suite 16/16 |
| 7 | OPERATION_ID_RETIREMENT_CANNOT_REEXECUTE_PASS | PASS | suite 16/16 |
| 8 | REAL_PROCESS_RESTART_RECOVERY_PASS | PASS | два ОС-процесса, жёсткий kill, bytes-only recovery, `REAL_PROCESS_RESTART_DELEGATED_RECOVERY_PASS`; live-stack restart остаётся за принятым M6-раннером (scope-маркер в тесте) |
| 9 | ZERO_PRIVATE_WRITE_PASS | PASS | suite 16/16 |
| 10 | FALSE_COMPLETION_EVIDENCE_RETRACTED_PASS | PASS | 2026-08-24_V0_P6_R3_FALSE_COMPLETION_RETRACTION_RU.md, commit 9c411aa7 |
| 11 | THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME | **PASS** | elapsed=1800013 ms (30.00 мин), checkpoints=29, reconnects 2+2, 51/51 assertions, `V0_P6_R3_SOAK_SUITE_PASS`; artifacts/test-results/p6-r3-soak-suite-410928/ |
| 12 | V0_P6_P7_P11_MCP_VISUAL_EVIDENCE_PASS | **PASS** | MCP-сессия исполнена автономно на этой машине (Ubuntu, double a13da4feb, SHA bfa7ce63…, breakpoint-mcp 1.82.0, addon 1.7.0): Сценарии 1–2 `docs/MCP_GODOT.md`, 17/17 проверок, managed stop подтверждён; exact head 20b00f89, изолированный worktree. См. `2026-08-24_V0_P6_R3_MCP_VISUAL_EVIDENCE_RU.md`, event 0008 |
| 13 | FULL_WORLD_CORE_REGRESSION_PASS | **ОТКРЫТ (блокеры вне ветки)** | census 293 шага: всё GREEN кроме (A) nx2+eg45 — доказанно унаследованные RED чистого main 9ade3233, (B) 5 display-fenced тестов. См. REGRESSION_FENCE_FINDINGS |
| 14 | POST_BUILD_CRITIQUE_COMPLETED | PENDING | роль post-build critique после данного документа |
| 15 | EVIDENCE_MAP_COMPLETE | PENDING | карта собирается по мере ролей |
| 16 | INDEPENDENT_REVIEWER_PASS | PENDING | fresh isolated role на exact head |
| 17 | INDEPENDENT_VERIFIER_PASS | PENDING | fresh isolated role на exact head |
| 18 | REVIEW_HEAD_EXACT_AND_FRESH | PENDING | фиксируется при ревью |
| 19 | TESTED_HEADS_EXACT_AND_FRESH | PASS-на-момет | все прогоны = закоммиченные HEAD; перефиксация при ревью |
| 20 | STANDARD_PC0_NON_RED | PENDING-реран | предварительный прогон: новых находок ветки нет; формальный реран на закрытии |
| 21 | DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS | PENDING-реран | аналогично |
| 22 | CRITICAL_CROSS_BRANCH_OVERLAP_ZERO | PENDING-аудит | на закрытии |
| 23 | HUMAN_ATTENTION_QUEUE_EMPTY_OR_RESOLVED | PENDING | зависит от решения по п.12–13 |
| 24 | V0_P6_R3_REPAIR_CHECKPOINT_PROPOSED | БЛОКИРОВАН до 14–17, 20–23 | guard AUDITED→CHECKPOINT_PROPOSED |

## Честное резюме состояния

Реализация ремонта завершена и подкреплена исполнимыми доказательствами:
focused suite 16/16, реальный process-restart гейт, литеральный 30-минутный
two-client real-time soak (новое доказательство этой сессии), полная ретракция
ложных claims R2, census regression без единого нового дефекта ветки.

До checkpoint proposal остались две категории работы:

1. **Environment-gate — ЗАКРЫТ (2026-08-24)**: MCP visual evidence исполнен
   автономно на этой машине через предоставленную среду (double-Godot +
   breakpoint-mcp host, X11 :0); предикат №12 → PASS, HA-001 снят (event 0008).
2. **Чужие дефекты**: nx2 и eg45 — унаследованные RED чистого main;
   ремонт возможен только в отдельных линиях (scripts/network — forbidden
   paths данного WO).
3. **Роли контроля**: post-build critique, fresh exact-head Reviewer и
   Verifier, Evidence Map, формальный PC0, затем proposal.

Статус миссии: `VERIFYING — implementation complete; verification partially
complete; one predicate honestly open (other-lane blockers nx2+eg45)`.
