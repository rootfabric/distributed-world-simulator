# PROJECT-FOCUS WINDOWS DELTA VERIFIER R3.6 — ОТЧЁТ

```text
decision: PASS

HEAD:  36c1091b2406717010e6e9b4585a230e45881545
TREE:  9f8eaee081b4373de0bca9377fc87191aad0cd4f
```

## 1. Live preflight

```text
live main:    c9e3b9d311818c5c55f16861d6c298aba5458990   (main drift: NO)
live control: 36c1091b2406717010e6e9b4585a230e45881545   (control drift: NO)
delta:        5 commits / 5 files (2d418733 → 36c1091), без runtime/, scenes/,
              executions/, acceptance/, historical evidence.
checkout:     clean before / clean after (tracked).
```

## 2. Автовыбор execution (§4)

`tests/harness/test_execution_selector_provenance.py` — 5/5 OK. Проверены
реальные assertions (не только названия):

- explicit canonical execution → allowed (`test_explicit_canonical_execution_path_is_allowed`);
- explicit copied arbitrary execution → `EXECUTION_PATH_NOT_CANONICAL`
  (копия с изменённой transition-table под scratch/);
- relative copied execution → `EXECUTION_PATH_NOT_CANONICAL`;
- automatic canonical execution → allowed;
- future-dated copied execution (`FORGED-COPY`, issued_at 2099) →
  `EXECUTION_PATH_NOT_CANONICAL`: `_require_canonical_execution_path`
  привязывает каталог к `config/control/harness/executions/<epoch_id>` из
  committed project-epoch — копия под чужим именем каталога отвергается и в
  explicit, и в automatic ветке `resolve_execution`.

## 3. Execution authority fence (§5)

Производственная цепочка подтверждена по коду:
`resolve_execution` → canonical identity (`_require_canonical_execution_path`) →
`load_guard_context` (event_reducer) → `committed_enforcement_generation` →
ContractBundle provenance (`_current_bundle_contract_paths`) →
`_current_execution_authority_json_paths` (strict set: work-orders/, events/,
repairs/, audits/, human-attention/ + 5 корневых файлов) →
`committed_bytes` (exact-byte, `hash-object --path`, ловит assume-unchanged).
Ни transition table, ни Work Order/event/repair/audit/human-attention authority
не читаются как trusted из dirty worktree — до reducer'а срабатывает
`PROVENANCE_WORKTREE_MODIFIED`.

## 4. Evidence Map provenance (§6)

- dirty committed Evidence Map → `PROVENANCE_WORKTREE_MODIFIED`;
- untracked Evidence Map → `EVIDENCE_MAP_JSON_SET_MISMATCH`;
- assume-unchanged + modified Evidence Map → `PROVENANCE_WORKTREE_MODIFIED`;
- регрессий нет: untracked review и non-map evidence сохраняют специальную
  семантику (`test_review_and_non_map_evidence_keep_dedicated_provenance_semantics`
  возвращает generation 81); hard-block proof идёт собственным контрактом
  (suite `test_harness_evidence_provenance.py`, 24/24 OK).

## 5. External event JSON и uppercase .JSON (§7–8)

- dirty external .json → `PROVENANCE_WORKTREE_MODIFIED`;
- assume-unchanged external .json → `PROVENANCE_WORKTREE_MODIFIED`;
- `external-authority.v1.JSON` (dirty) → `PROVENANCE_WORKTREE_MODIFIED`.
  Consumer `_safe_repository_json` использует `suffix.lower() != ".json"`;
  fence использует ту же семантику (`PurePosixPath(...).suffix.lower()`),
  т.е. обход через регистр закрыт той же проверкой.

## 6. Предыдущие гарантии (§9–10)

- `test_harness_evidence_provenance.py` — 24 OK (skip=1: symlink privilege);
- `test_harness_autonomy_runtime.py` — 4 OK;
- `test_scheduler_policy_provenance.py` — 18 OK, включая 14-file ContractBundle
  mutation matrix, strict execution-authority matrix, dirty scheduler /
  repair-doctrine / transition table, assume-unchanged concealment;
- `test_harness_checkpoint_session` — 22 OK; fixture repair (E-old/E-new теперь
  несут корректный `epoch_id`) усиливает, а не ослабляет production guard;
- historical generation80/81: canonical pre-merge состояние остаётся fail-closed.

## 7. Full Harness (§11)

```text
Ran 261 tests — 0 failures / 0 errors / 3 skips
skips (оценены): 1x symlink privilege (Windows), 2x live proposed-R3
projection (требуют GitHub Actions окружение; выполнены в CI 34029090295).
```

См. full-harness.log. ВНИМАНИЕ: тестовые фикстуры с парой
`external-authority.v1.json`/`.JSON` требуют case-sensitive ФС; на default NTFS
эти тесты падают fail-closed с `PROVENANCE_COMMITTED_FILE_REQUIRED`. Верификатор
перенаправил TMP/TEMP на case-sensitive WSL ext4 share (см. environment.txt) —
repo-код не менялся. Это Windows environment limitation, не source defect.

## 8. Candidate validation (§12)

```text
comparison base = c9e3b9d311818c5c55f16861d6c298aba5458990
registry generation = 81
authority = CANDIDATE_NON_AUTHORIZING
runtime_authorized = false
primary_lane = MVP
overview --candidate: exit 0; check-consistency --candidate: exit 0
```

## 9. PowerShell 7 wrapper (§13)

```text
Overview:             exit 0
CheckConsistency:     exit 3 PROJECT_CONSISTENCY_ERRORS
Drive:                exit 3 EPOCH_REGISTRY_GENERATION_MISMATCH
CloseMission:         exit 3 EPOCH_REGISTRY_GENERATION_MISMATCH
Candidate Overview:   exit 0
Candidate CheckConsistency: exit 0 (CANDIDATE_NON_AUTHORIZING, runtime_authorized=false)
-Drive -Candidate / -CloseMission -Candidate: НЕ запускались (по инструкции)
```

## 10. Exact CI (§14) и PC0 (§15)

```text
run 34029090295: SUCCESS @ 36c1091b (exact HEAD), Harness 261/0/0
artifact 9988020059 SHA-256 = 6aed64b884f97bac8ebb9b63b2a854f5ec7774df432893381d073b65f4d36df3
standard PC0 = YELLOW; directional PC0 = YELLOW
G/ECO RED — advisory (blocks_global_progress=false подтверждён)
```

## 11. Итог

```text
runtime tested:                NO
Godot used:                    NO
source modified by verifier:   NO
findings:                      нет blocker'ов; одна environment note
                               (case-sensitive fixtures vs default NTFS)
remaining blockers:            нет со стороны Verifier
```

PASS не разрешает merge, P7 acceptance или MVP activation. Следующий шаг —
HUMAN MERGE / HOLD в PR #547.

Полная машинная запись: VERIFICATION.v1.json.
