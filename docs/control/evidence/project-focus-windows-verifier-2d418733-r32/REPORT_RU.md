# PROJECT-FOCUS WINDOWS DELTA VERIFIER R3.2 — VERIFICATION REPORT

Дата: 2026-09-06
Роль: FRESH INDEPENDENT VERIFIER (Windows)
Метод: независимый fresh clone `C:\distributed-world-simulator\r32-win-verify`, source не изменялся.

## Subject

```text
HEAD:  2d4187337b556807ca72feebd4bd03245de389b3
TREE:  c8e4ba2f6f981229e6bd27b63ef77c4a565ee7b5
```

Checkout: exact HEAD/TREE совпали, `git status --porcelain` пуст до и после всех проверок.

## main / control

```text
origin/main = c9e3b9d311818c5c55f16861d6c298aba5458990  (drift отсутствует, = expected main)
origin/control/project-focus-harness-reconciliation-r1 = 2d418733... (= subject HEAD)
```

## Delta 284a23d2..2d418733

Только ожидаемые файлы:

```text
M scripts/harness/evidence_provenance.py
M tests/harness/test_scheduler_policy_provenance.py
```

Изменений runtime/scenes/executions/acceptance/history нет.

## Главная проверка — полный 14-файловый ContractBundle fence

`_current_bundle_contract_paths()` выводит полный текущий dependency set из
**committed** `config/control/harness/harness-policy.v1.json`: сам файл policy
проходит `committed_bytes(..., immutable=False)` ДО чтения любых путей —
dirty harness-policy физически не может подменить пути, потому что падает
`PROVENANCE_WORKTREE_MODIFIED` на собственном blob-сравнении (git
`hash-object --path` против `ls-tree HEAD`). Выведенный набор = 14
уникальных существующих файлов:

```text
config/control/project-program-registry.v1.json
config/control/harness/harness-policy.v1.json
project-goals.v1.json, checkpoint-catalog.v1.json, scheduler-policy.v1.json,
work-order.schema.v1.json, event.schema.v1.json, project-epoch.schema.v1.json,
risk-policy.v1.json, review-policy.v1.json, repair-doctrine.v1.json,
evidence-map.schema.v1.json, human-attention.schema.v1.json,
continuation-policy.v1.json
```

Для generation >= 81 все 14 файлов проверяются в
`committed_enforcement_generation()` ДО вывода committed epoch. Прежний
hardcoded 5-файловый список (R3.1) полностью поглощён новым набором;
порядок строже — fence теперь до epoch-binding, а не после.

### Fail-closed доказательства (assertions проверены, не только имена)

- dirty repair-doctrine → `PROVENANCE_WORKTREE_MODIFIED`: PASS
  (test_dirty_repair_doctrine_is_rejected_before_reducer_can_weaken_repair_map;
  изменяет `repair_map_fields` на `[]` и требует отказ и в
  `committed_enforcement_generation`, и в `load_guard_context`)
- dirty scheduler → `PROVENANCE_WORKTREE_MODIFIED`: PASS
  (test_dirty_scheduler_policy_is_rejected_by_generation_fence +
  test_guard_context_rejects_dirty_scheduler_before_event_reduction)
- assume-unchanged repair-doctrine → fail closed: PASS
  (`git update-index --assume-unchanged` + dirty → отказ;
  скрытие индекса не помогает, т.к. guard сравнивает bytes через hash-object)
- assume-unchanged scheduler → fail closed: PASS (аналогично)
- каждый из 14 ContractBundle файлов, изменённый отдельно →
  `PROVENANCE_WORKTREE_MODIFIED`: PASS
  (test_every_current_contract_bundle_dependency_is_worktree_fenced,
  14 subTest-мутаций + восстановление + повторная зелёная проверка)
- dirty harness-policy indirection → fail closed: PASS
  (harness-policy входит в 14-файловую матрицу; структурно путь-резолвер
  сам прогоняет committed_bytes по policy до чтения путей)

### Previous provenance regressions

Все 24 теста `test_harness_evidence_provenance.py` ok (1 symlink skip,
см. ниже), включая historical generation-80 replay
(test_historical_review_contract_is_preserved), dirty registry downgrade,
forged guard context, dirty continuation-policy → legacy hard-block.

## Focused tests

```text
test_scheduler_policy_provenance.py: 6 tests, OK
test_harness_evidence_provenance.py:  24 tests, OK (skipped=1)
test_harness_autonomy_runtime.py:     4 tests, OK
```

## Full Harness (Windows)

Discovery: `Ran 233 tests, FAILED (errors=1, skipped=3)`, где единственная
error — `_FailedTest.test_project_overview`: импорт-плейсхолдер из-за
затенения namespace-пакета `tests` чужим site-packages пакетом в данной
Windows-среде (та же особенность среды, что и в R3.1; модуль запущен
отдельно с явной регистрацией namespace-пакета: 12 tests, 0 failures,
0 errors).

```text
итого: 244 tests / 0 failures / 0 errors / 3 skips
```

Оценка skips (каждый отдельно):
1. `test_path_traversal_and_symbolic_link_are_rejected` — WinError 1314:
   ОС не даёт создать symlink-fixture без привилегий; допустимый
   Windows-specific skip.
2–3. `test_live_proposed_r3_*` (2 шт.) — «live proposed-R3 projection
   requires GitHub Actions with all remote refs fetched»; выполняется
   только в CI-раннере, локально недостижим; допустимый environmental skip.

PASS-критерий failures=0 / errors=0 выполнен.

## Candidate

```text
python -m harness.control_candidate_validation  → OK (exit 0)
  CONTROL COMPARISON BASE: c9e3b9d311818c5c55f16861d6c298aba5458990
  CANDIDATE REGISTRY GENERATION OK: 81
python -m harness.cli overview --candidate      → exit 0
python -m harness.cli check-consistency --candidate → exit 0
authority=CANDIDATE_NON_AUTHORIZING, runtime_authorized=false,
primary_lane=MVP
```

## PowerShell 7 (pwsh -NoProfile -File .\CONTROL_DEVELOPMENT.ps1)

```text
-Overview           exit=0
-CheckConsistency   exit=3, detail=PROJECT_CONSISTENCY_ERRORS
-Drive              exit=3, detail=EPOCH_REGISTRY_GENERATION_MISMATCH
-CloseMission       exit=3, detail=EPOCH_REGISTRY_GENERATION_MISMATCH
-Overview -Candidate           exit=0, CANDIDATE_NON_AUTHORIZING, runtime_authorized=false
-CheckConsistency -Candidate   exit=0, CANDIDATE_NON_AUTHORIZING, runtime_authorized=false
```

Drive/CloseMission с `-Candidate` не запускались. Canonical pre-merge
baseline воспроизведён точно.

## Exact CI provenance (независимая проверка через gh api)

```text
run:       34025114584
headSha:   2d4187337b556807ca72feebd4bd03245de389b3
conclusion: SUCCESS
Harness:   "Ran 244 tests" + "OK" (complete Harness regression discovery)
artifact:  9986805524 (project-control-report)
SHA256(zip 9986805524) = 56c694daaf570b731fd30cd36c9aa0285b19d0da67959f926e8967681427f4e4  — EXACT MATCH
```

## PC0 (из artifact run 34025114584)

```text
standard   = YELLOW (overall_health, project-control-report.json)
directional = YELLOW (overall_health, directional-watch-report.json)
```

GREEN не объявляется.

## Финал

```text
HEAD: 2d4187337b556807ca72feebd4bd03245de389b3
TREE: c8e4ba2f6f981229e6bd27b63ef77c4a565ee7b5
git status --porcelain: пусто (clean before / clean after)
```

```text
runtime tested: NO
Godot used:    NO
source modified: NO
```

## Вердикт

PASS — по критериям данного задания. PASS не разрешает merge.
