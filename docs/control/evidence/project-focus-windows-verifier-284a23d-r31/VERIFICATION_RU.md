# PROJECT-FOCUS — Независимая Windows-верификация R3.1 (subject 284a23d)

- Дата: 2026-09-06
- Роль: FRESH INDEPENDENT VERIFIER (Windows)
- Среда: Windows, PowerShell 7, Python 3.11, `PYTHONUTF8=1`, отдельный fresh checkout
- Subject:
  - HEAD: `284a23d25eb3c675b78868335746e32704491533`
  - TREE: `8ac0c64e6d683a73b14399989bea5ddecef04b49`
- Trusted predecessor (Windows PASS): `697de1fe6bb6bf934575f4280975d190b9fa948a` (TREE `5ffbf66eb5a42a8731f13880adc93fff3bf7be02`)

## Decision

```text
PASS
```

PASS не разрешает merge. Следующий gate: Fresh Reviewer + Fresh Windows Verifier на exact 284a23d + exact CI success + fresh main/control → HUMAN MERGE / HOLD.

## 1. Live preflight

```text
main:    c9e3b9d311818c5c55f16861d6c298aba5458990  (совпадает с ожидаемым)
control: 284a23d25eb3c675b78868335746e32704491533  (совпадает с ожидаемым)
```

MAIN_DRIFT отсутствует.

## 2. Exact checkout

Fresh detached worktree `r31-verify-284a23d`:

```text
HEAD:   284a23d25eb3c675b78868335746e32704491533
TREE:   8ac0c64e6d683a73b14399989bea5ddecef04b49
status: clean (до и после всех проверок)
```

## 3. Delta относительно 697de1f

```text
1 commit: 284a23d2 fix(harness): fence scheduler policy before event reduction
2 files:
  M scripts/harness/evidence_provenance.py
  A tests/harness/test_scheduler_policy_provenance.py
```

Вне scope (runtime/, scenes/, executions/, acceptance/, historical evidence) изменений нет.

## 4. P1: scheduler committed-byte fence — доказано

`committed_enforcement_generation` (generation 81, `pinned_generation >= PROVENANCE_GENERATION`) теперь вызывает `committed_bytes(..., immutable=False)` для:

```text
harness-policy
review-policy
continuation-policy
risk-policy
scheduler-policy   ← добавлен данным commit
```

`committed_bytes` (scripts/harness/evidence_provenance.py:70-92) сравнивает:

- blob SHA из `git ls-tree HEAD -- ':(literal)<path>'`
- против `git hash-object --path=<path> -- <path>` от фактических worktree bytes

Это байтовое blob-hash сравнение, не `git status`/index. `git update-index --assume-unchanged` не влияет на `hash-object` worktree файла, поэтому скрытие dirty-статуса бесполезно. Дополнительно: symlink-запрет (`is_symlink` + resolve-check) и дубликат-key JSON-декодирование сохранены.

Production path подтверждён исходно:

```text
state_builder.py:790  load_guard_context(root, execution_dir)
  → event_reducer.py:29  committed_enforcement_generation(root, epoch)
      → committed_bytes(scheduler-policy и остальные 4 политики)
state_builder.py:811  reduce_events(..., guard_context)   ← только ПОСЛЕ fence
```

Reducer (`reduce_events` → `_lease_applies` читает `bundle.contracts["scheduler_policy"]["pre_h0_3_runtime_mutation_lease"]`) не получает authority-bearing scheduler, чьи worktree bytes отличаются от HEAD.

## 5. Focused scheduler tests — реально выполнены

```text
python -m unittest discover -s tests/harness -p "test_scheduler_policy_provenance.py" -v
Ran 3 tests — OK
```

Три случая проверены живыми assertions (временный git-репозиторий-фикстура, реальная модификация `scheduler-policy.v1.json`, удаление `pre_h0_3_runtime_mutation_lease`):

1. `test_dirty_scheduler_policy_is_rejected_by_generation_fence` → `PROVENANCE_WORKTREE_MODIFIED` — PASS
2. `test_guard_context_rejects_dirty_scheduler_before_event_reduction` (через `load_guard_context`, до reducer) → `PROVENANCE_WORKTREE_MODIFIED` — PASS
3. `test_assume_unchanged_cannot_hide_dirty_scheduler` (`git update-index --assume-unchanged` + dirty) → `PROVENANCE_WORKTREE_MODIFIED` — PASS

PASS подтверждён выполнением assertions, а не только названиями tests.

## 6. Regression predecessor

```text
test_harness_evidence_provenance.py: Ran 24 tests — OK (skipped=1)
test_harness_autonomy_runtime.py:   Ran 4 tests — OK
```

Skip: `test_path_traversal_and_symbolic_link_are_rejected` — создание symlink-фикстуры требует привилегий (WinError 1314), ожидаемо на Windows; сам symlink-запрет в `committed_bytes` не зависит от фикстуры.

Сохранены: hard-block committed provenance, build_state → Drive, SHA256 review evidence, event guard enforcement, generation 81→80 protection, historical committed gen80 compatibility.

## 7. Full Harness (Windows)

Итог: `241 tests / 0 failures / 0 errors / 3 skips` (совпадает с Linux CI по тестам и результатам).

Разделение запуска (окружение, не дефект репозитория): в системном Python посторонний regular package `C:\Python311\Lib\site-packages\tests` (данные Electrum 2.10) затеняет namespace-package `tests` репозитория. Discovery выполнен штатно (230 tests, где 1 load-error placeholder) и `tests.harness.test_project_overview` (12 tests) — через программную регистрацию namespace-package вне checkout. Ни файл репозитория, ни Python-окружение не изменялись.

Оценка skips:

1. symlink fixture (WinError 1314) — привилегия ОС, ожидаемо на Windows.
2-3. live proposed-R3 projection (×2) — требует GitHub Actions окружения со всеми remote refs, вне локальной Windows-машины.

Все три skip-категории допустимы и не влияют на verdict-критерии.

## 8. Candidate validation

```text
PYTHONPATH=scripts python -m harness.control_candidate_validation → exit 0
CONTROL COMPARISON BASE: c9e3b9d311818c5c55f16861d6c298aba5458990
CANDIDATE REGISTRY GENERATION OK: 81
```

CLI:

```text
python -m harness.cli overview --candidate         → exit 0
python -m harness.cli check-consistency --candidate → exit 0
authority = CANDIDATE_NON_AUTHORIZING
runtime_authorized = false
primary_lane = MVP
```

## 9. Windows PowerShell gate

```text
-Overview                 → 0
-CheckConsistency         → 3 / PROJECT_CONSISTENCY_ERRORS
-Drive                    → 3 / EPOCH_REGISTRY_GENERATION_MISMATCH
-CloseMission             → 3 / EPOCH_REGISTRY_GENERATION_MISMATCH
-Overview -Candidate      → 0 (CANDIDATE_NON_AUTHORIZING, runtime_authorized=false)
-CheckConsistency -Candidate → 0
```

Полностью соответствует canonical reference; fail-closed сохранён. `-Drive -Candidate` и `-CloseMission -Candidate` не запускались (запрещено).

## 10. Exact CI evidence

```text
run:      34022892358 (Project Control) — conclusion: success
headSha:  284a23d25eb3c675b78868335746e32704491533
full Harness discovery: Ran 241 tests — OK (0 failures / 0 errors)
artifact: 9986093166 (project-control-report)
artifact zip SHA256: eaf0eb46e70d78f205a9284e0c1d0845c8427524ba9e18ca01dffb6663b6e7af — точное совпадение
```

CI — machine evidence; independent verdict выдан этой верификацией отдельно.

## 11. PC0

```text
standard PC0:   YELLOW
directional PC0: YELLOW
```

Совпадает с ожидидаемым; overall GREEN не объявляется.

## 12. Verdict-критерии

```text
scheduler dirty bypass CLOSED                  — да (blob-hash fence, тест 1)
assume-unchanged bypass CLOSED                 — да (тест 3, hash-object не зависит от index)
guard context rejects dirty scheduler BEFORE reducer — да (тест 2 + production path state_builder:790→811)
previous provenance protections preserved      — да (regression suites зелёные)
full Harness 0 failures / 0 errors             — да (241/0/0/3 skips)
candidate remains non-authorizing              — да (CANDIDATE_NON_AUTHORIZING, runtime_authorized=false)
canonical state remains fail-closed            — да (0/3/3/3; candidate 0/0)
exact HEAD/TREE clean до и после               — да
runtime tested: NO; Godot used: NO
source modified by verifier: NO (checkout clean; вспомогательные runner-скрипты размещены вне checkout)
unresolved verifier findings                   — нет
```

## 13. Evidence

- Branch: `verify/project-focus-284a23d-windows-r31`
- Commit: `test(control): independently verify project-focus R3.1 on Windows`
- Draft PR (verifier-only, base `control/project-focus-harness-reconciliation-r1`) — DO NOT MERGE INTO MAIN DIRECTLY.
