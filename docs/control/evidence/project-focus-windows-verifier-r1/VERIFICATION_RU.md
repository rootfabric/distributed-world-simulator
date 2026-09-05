# PROJECT-FOCUS — независимая Windows verification R1

Verification ID: `PROJECT-FOCUS-CONTROL-WINDOWS-VERIFY-R1`
Роль: `FRESH_INDEPENDENT_VERIFIER`. Платформа: Windows 10 19045, x64.

## Решение

```text
PASS
```

Решение относится только к замороженному subject:

```text
HEAD: cc89d80599eb24ab4efd55b38332ead4b16468bf
TREE: 1f51c4a7c0d2e4892d635d6ce830c053f0799ef4
```

Это exact-head verification. PASS не переносится автоматически на другие HEAD,
включая более поздние commits самой control-ветки.

## Live refs и drift

- `origin/main` = `5b4152958624be4e9cc40f2369ce32c4964f65c3` — совпадает с ожидаемым
  canonical main, drift main отсутствует.
- `origin/control/project-focus-harness-reconciliation-r1` = `447b06e4e572eea4b9a03b2fa0a27427b6b4a868` —
  **живая ветка продвинулась дальше subject** (drift зафиксирован, PVW-R1-F2).
  Проверка осталась на замороженном `cc89d805`; commits после него этим PASS не покрыты.

## Выполненная проверка (собственные команды, логи в этом каталоге)

| Гейт | Результат |
| --- | --- |
| Preflight (clone, fetch, rev-parse, detach) | HEAD/TREE совпадают; checkout чист до проверок |
| `python -m pip install -r scripts/harness/requirements.txt` | exit 0; jsonschema **4.22.0** (pinned) |
| `py_compile` 15 control/harness модулей | 15/15 exit 0 |
| `python -m harness.control_candidate_validation` | exit 0; duplicate-key OK ×14; comparison base `5b415295`; generation 81 OK |
| `python -m harness.cli check-consistency --candidate` | exit 0; `runtime_authorized=false`; `CANDIDATE_NON_AUTHORIZING`; observed_main = pinned main |
| Named suites 1–6 (35/22/65/8/25/19 tests) | все exit 0; failures 0; errors 0; skips 2 (live-GitHub, suite 3) |
| Full discovery `tests/harness` | **196 tests, failures 0, errors 0, skips 2**, exit 0 |
| Standard PC0 (`--no-fetch --no-fail-on-red`) | exit 0; отчёт прочитан: overall **YELLOW**; G/ECO RED advisory (`blocks_global_progress=false`); V0 YELLOW без blocking RED |
| Directional PC0 | exit 0; отчёт прочитан: overall **YELLOW**; global_blocking=true только у pre-existing baseline WATCH_HIT CH→NX и NX→T (main gen 80); V0→G/ECO critical hits advisory |
| `CONTROL_DEVELOPMENT.ps1 -Overview` (pwsh 7.6.5) | exit 0 |
| `-CheckConsistency` | exit 3 `PROJECT_CONSISTENCY_ERRORS` — ожидаемый fail-closed до merge |
| `-Drive` | exit 3 `EPOCH_REGISTRY_GENERATION_MISMATCH` — ожидаемый fail-closed |
| `-CloseMission` | exit 3 `EPOCH_REGISTRY_GENERATION_MISMATCH` — ожидаемый fail-closed |
| `-Overview -Candidate` | exit 0; `runtime_authorized=false`; `candidate_preview=true`; `CANDIDATE_NON_AUTHORIZING` |
| `-CheckConsistency -Candidate` | exit 0; то же non-authorizing |
| Historical immutability diff | 39 путей (24 M, 15 A); **нет** изменений `runtime/**`, `scenes/**`, `executions/**`, `acceptance/**` |
| Postflight | HEAD/TREE неизменны; `git status --short` пуст |

Запрещённые candidate-режимы (`-Drive -Candidate`, `-CloseMission -Candidate`,
`-Plan -Candidate`, `-Resume -Candidate`) не запускались.

## P7/MVP routing (из candidate state)

```text
primary_lane = MVP
P7.7 = MERGED_PENDING_CANONICAL_CLOSURE
runtime_mutation_allowed_now = false
current_phase = P7_MERGED_CLOSURE_RECONCILIATION
next_runtime_checkpoint = V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE
next_runtime_checkpoint_eligible = false
next_actor = DIRECTOR
ECO/FABRIC/PRESENTATION blocks_mvp = false
```

Второго владельца Matter/ItemGraph/persistence/network в diff не появилось
(включая проходящий guard `test_p7_0_rejects_duplicate_terrain_and_resource_owners`).

## Findings (не блокируют)

- **PVW-R1-F1 (LOW)** — на Windows без `PYTHONUTF8=1` python CLI падает
  `UnicodeEncodeError` → `INTERNAL_ERROR` exit 6 (наблюдалось на
  `check-consistency --candidate`). Удобство окружения, не дефект control-логики;
  все зачтённые запуски шли с `PYTHONUTF8=1`; CI на Linux не затронут.
- **PVW-R1-F2 (INFO)** — живая control-ветка продвинулась до `447b06e4`;
  проверка осталась на замороженном subject.
- **PVW-R1-F3 (INFO)** — локальное загрязнение машины верификатора (сторонний
  `tests` в site-packages, WindowsApps python-stub в pwsh7); нейтрализовано
  вне репозитория, subject не изменялся.

## checks_not_run

- Godot / P7 графический runtime gate — вне scope этой control verification.
- Live proposed-R3 GitHub-metadata тесты — skip самого suite (офлайн), задокументировано.
- Merge PR #547, P7 acceptance, MVP activation — human gates, не полномочия Verifier.

## Ограничения решения

Этот PASS:

- не является P7 ACCEPTED;
- не является merge/acceptance PROJECT-FOCUS;
- не активирует MVP и не создаёт epoch/Work Order/lease;
- не переносится на HEAD ≠ `cc89d805`.

Следующие шаги (merge PR #547 и далее) — отдельные роли и human gates.
