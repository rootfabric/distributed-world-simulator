# PROJECT-FOCUS — FRESH INDEPENDENT WINDOWS VERIFIER R3

Вердикт: **PASS** (machine-evidence вердикт для frozen subject; не merge, не P7 ACCEPTED, не MVP ACTIVATED, не MISSION COMPLETE).

- Subject HEAD: `697de1fe6bb6bf934575f4280975d190b9fa948a`
- Subject TREE: `5ffbf66eb5a42a8731f13880adc93fff3bf7be02` (подтверждён `git rev-parse 'HEAD^{tree}'`)
- Live origin/main: `c9e3b9d311818c5c55f16861d6c298aba5458990` — main drift **NO**
- Live control tip: `697de1fe…` — control drift после subject **NO**
- Fresh checkout: `C:\Godot\dws-project-focus-verifier-697de1fe`, detached на exact subject, clean before/after.

## Окружение

pwsh 7.6.5, Python 3.11.8, git 2.53.0.windows.1, jsonschema 4.22.0 (pinned). Godot не использовался; runtime не запускался.

## Результаты

| Проверка | Результат |
|---|---|
| py_compile (8 модулей) | все exit 0 |
| focused provenance (`test_harness_evidence_provenance`) | 24 tests, OK (1 Windows symlink-privilege skip, компенсирован независимо) |
| focused autonomy runtime | 4 tests, OK |
| focused autonomy policy (`test_harness_autonomous_execution_policy`) | 5 tests, OK |
| session stall guard | 3 tests, OK |
| large-scale campaign guard | 3 tests, OK |
| FULL harness (clean venv, `discover -s tests/harness -p "test_*.py"`) | **238 tests / 0 failures / 0 errors / 3 skips** |
| `harness.control_candidate_validation` | exit 0, base `c9e3b9d3…`, generation 81, duplicate-key/schema/lease PASS |
| `harness.cli overview --candidate` | exit 0, candidate_preview=true, authority=CANDIDATE_NON_AUTHORIZING, runtime_authorized=false, primary_lane=MVP |
| `harness.cli check-consistency --candidate` | exit 0, non-authorizing |
| pwsh `-Overview` | 0 |
| pwsh `-CheckConsistency` | 3 / PROJECT_CONSISTENCY_ERRORS (ожидаемый fail-closed) |
| pwsh `-Drive` | 3 / EPOCH_REGISTRY_GENERATION_MISMATCH (ожидаемый fail-closed) |
| pwsh `-CloseMission` | 3 / EPOCH_REGISTRY_GENERATION_MISMATCH (ожидаемый fail-closed) |
| pwsh `-Overview -Candidate` / `-CheckConsistency -Candidate` | 0 / 0, CANDIDATE_NON_AUTHORIZING, runtime_authorized=false |

## P1-классы дефектов

- **P1-A hard-block provenance — PASS.** `load_hard_block_proof`/`committed_bytes` читают только committed blob через `git ls-tree HEAD`, отвергают non-regular mode (symlink 120000), модифицированное рабочее дерево (`hash-object --path`), rewritten history (append-only add-commit check), path traversal/`.git`/absolute/backslash — проверено независимо прямым вызовом `_path`. Отрицательные сценарии (несуществующий path, untracked, modified, wrong WO/event/TREE) покрыты реально выполняющимися тестами, обращающимися к production-функциям.
- **P1-B production build_state → Drive — PASS.** `state_builder` вызывает `load_hard_block_proof` на последнем authoritative BLOCKED event и кладёт `hard_block_proof` в state; `continuation.build_continuation` допускает terminal HARD_BLOCKED только при `hard_block_matches_state` (повторное чтение immutable event+proof из Git) и полных policy-clauses. Тест `test_real_drive_and_close_mission_accept_committed_proof` прогоняет реальный Git fixture через CLI Drive/CloseMission; fake proof mission не закрывает.
- **P1-C reused machine evidence — PASS.** `validate_review_machine_evidence` требует committed manifest с SHA-256, binding по head/tree/runner/run/artifacts, exit-code equality и log-артефакты. Используется обоими production-потребителями: review loader (`state_builder`) и event guard (`event_reducer`). Отрицательные случаи (нет manifest, wrong digest/tree/run/runner, artifact из другого run, modified artifact, FRESH_EXECUTION label без evidence, untracked review, digest-free PASS → INSUFFICIENT_EVIDENCE) выполняются в focused suite.
- **P1-D committed generation bypass — PASS.** `committed_enforcement_generation` пиннит generation из HEAD blob registry, требует byte-identity committed epoch и committed текущих политик; локальный downgrade 81→80 (dirty registry/epoch, forged guard context, dirty continuation policy без autonomous_execution) fail-closed. Реальный committed generation-80 historical snapshot сохраняет legacy replay (`test_historical_review_contract_is_preserved`, gen80 safety guards), но не становится live authority (EPOCH_REGISTRY_GENERATION_MISMATCH).

## CI / PC0 provenance

Run `34011494430` (workflow Project Control, conclusion success) имеет headSha `697de1fe…` — exact subject. Артефакт `9982599288` привязан к этому run; digest GitHub `sha256:9fe1ab…e1927` совпал с локально пересчитанным SHA-256 скачанного архива. Standard PC0 = **YELLOW** (G, ECO RED — ADVISORY frozen research, вне V0 critical path, не введены кандидатом). Directional PC0 = **YELLOW** (два RED critical-watch V0→G и V0→ECO, оба `global_blocking=false`). Новых product-blocking RED кандидатом не введено.

## Historical immutability

`git diff --name-only c9e3b9d3...697de1fe` и `696bd6b7...697de1fe`: нет изменений `runtime/`, `scenes/`, `config/control/harness/executions/`, `config/control/harness/acceptance/`, historical reviews/verifications/evidence. Единственный workflow diff (`.github/workflows/project-control.yml`) — validation/evidence plane (compile/tests/consistency), не Git transport механизм.

## Findings

1. `ENV_SITE_PACKAGES_TESTS_SHADOW` (INFO): первый full-harness прогон в системном интерпретаторе упал на импорте `tests.harness` из-за постороннего пакета `tests` в site-packages; идентичная команда в чистом venv даёт 238/0/0. Артефакт окружения верификатора, не дефект subject.
2. `INSTRUCTION_TEST_FILENAME_MISMATCH` (INFO): указанного в задании `test_harness_autonomy_policy.py` не существует; фактический suites `test_harness_autonomous_execution_policy.py` (5 tests, OK).
3. `SKIP_COUNT_REFERENCE_DELTA` (INFO): 3 skips вместо 2 у Implementer — Windows symlink-privilege skip; все три оценены индивидуально.

## Не запускалось

`-Drive -Candidate`, `-CloseMission -Candidate`, `-Plan -Candidate`, `-Resume -Candidate` (запрещены); Godot/runtime (не требуется).

## Следующий шаг

Fresh exact-head Reviewer result + fresh main check + exact CI + human MERGE/HOLD решение по PR #547.
