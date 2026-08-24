# V0 P6 R3 — локальная тестовая сессия (focused suite GREEN)

Дата: 2026-08-24 (UTC+10)

Ветка: `repair/v0-p6-persistence-exactly-once-r1`

Тестируемый HEAD: `5d45cf354b6ba9778a8ff5742493b13e854da01b` (до коммитов этой сессии)

Runtime: double-precision Godot `4.7.1.stable.double.custom_build.a13da4feb`,
SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

## Что сделано

### 1. Godot import (canonic preflight)

`--headless --editor --import` на основном checkout ветки — exit 0.
Шесть `Parse Error: Expected '['` в `scenes/labs/ecology/eco_evo4*/eco_evo5*.tscn`
наследованы от `main` (BOM в первой строке; repair-коммиты `.tscn` не трогали).
Не относится к P6 R3; отдельный дефект для ecology-веток.

### 2. Инвентаризация P6-набора до этой сессии

10 из 14 focused P6-тестов уже были GREEN со literal stage-маркерами
(`OPERATION_ID_RETIREMENT_CANNOT_REEXECUTE_PASS`, `PENDING_RETRY_FAIL_CLOSED_PASS`,
`CANONICAL_OWNER_COMPOSITION_PASS`, `PRIVATE_PERSISTENCE_REMOVED_PASS`,
`NO_DUPLICATE_CANONICAL_OUTPOST_TRUTH_PASS`,
`SHADOW_READ_ONLY_CANONICAL_TRANSFER_REQUIRED_PASS`, `ZERO_PRIVATE_P6_WRITE_PASS`,
`ROUTE_PENDING_NO_DOUBLE_EXECUTION_PASS`, `AUTHORITY_DOMAIN_READY_CLOSURE_PASS`,
`TOPOLOGY_NEUTRAL_IDENTITY_PASS`).

4 legacy R2-теста были сломаны об удалённую private-архитектуру:

- `test_v0_p6_shared_outpost.gd` — runtime: `set_world_seed` больше не существует;
- `test_v0_p6_restart_recovery.gd` — runtime: то же + каскад;
- `test_v0_p6_fault_race_matrix.gd` — parse: `configure(owner, path)` / `persist_state(path)`;
- `test_v0_p6_repeat_soak.gd` — parse: `position_key()` static больше не существует.

### 3. Перепривязка 4 legacy-тестов (handoff step 4)

Все четыре переписаны на R3-границу «composition, а не private state»:

- `test_v0_p6_shared_outpost.gd` → SHARED_OUTPOST_CANONICAL_COMPOSITION_PASS
  (44 assertions). Два игрока через gateway route; канонические owners-fixture
  (M4/P4/P5 stand-in) — единственная мутация; проекция read-only;
  персистентность ТОЛЬКО через реальные `AuthoritativeRecoveryCoordinator` +
  `AuthoritativeRecoveryRepository`; exactly-once после recovery обеспечивает
  canonical replay owner, не память P6.
- `test_v0_p6_restart_recovery.gd` → DELEGATED_RECOVERY_EXACTLY_ONCE_PASS
  (42 assertions). Через границу бута переходят только checkpoint-байты;
  generation B восстанавливает sources/replay/projection из байтов; PENDING
  не дюрабелен; незачекпоинченный эффект повторно приземляется идемпотентно.
- `test_v0_p6_fault_race_matrix.gd` → FAULT_RACE_MATRIX_PASS
  (115 assertions, 6 сценариев: reconnect, same-block race, shadow read-only,
  concurrent sessions, persistence-during-writes, pending crash windows).
- `test_v0_p6_repeat_soak.gd` → REPEAT_IDEMPOTENCE_PASS
  (508 assertions: 200 операций + полный replay + capacity fence
  `LEDGER_CAPACITY_EXCEEDED` без eviction).

Каждый файл несёт явный `[scope]`-маркер о том, что он НЕ заявляет.

### 4. Новый раннер

`RUN_V0_P6_R3_TESTS.sh` — канонический Ubuntu-раннер полного P6-набора:
editor-preflight + 14 тестов, изолированные HOME, timeout 300s/тест,
проверка exit code + literal `[stage]`-маркера + absence of FAIL/SCRIPT ERROR.

## Результат полного прогона

```text
[p6-r3-suite] PASS editor-preflight -> EDITOR_PREFLIGHT_OK
[p6-r3-suite] PASS test_v0_p6_identity_registry -> TOPOLOGY_NEUTRAL_IDENTITY_PASS
[p6-r3-suite] PASS test_v0_p6_closure_adapter -> AUTHORITY_DOMAIN_READY_CLOSURE_PASS
[p6-r3-suite] PASS test_v0_p6_operation_ledger -> OPERATION_ID_RETIREMENT_CANNOT_REEXECUTE_PASS
[p6-r3-suite] PASS test_v0_p6_mutation_admission -> PENDING_RETRY_FAIL_CLOSED_PASS
[p6-r3-suite] PASS test_v0_p6_ownership_map -> CANONICAL_OWNER_COMPOSITION_PASS
[p6-r3-suite] PASS test_v0_p6_persistence_owner -> PRIVATE_PERSISTENCE_REMOVED_PASS
[p6-r3-suite] PASS test_v0_p6_outpost_state -> NO_DUPLICATE_CANONICAL_OUTPOST_TRUTH_PASS
[p6-r3-suite] PASS test_v0_p6_shadow_authority -> SHADOW_READ_ONLY_CANONICAL_TRANSFER_REQUIRED_PASS
[p6-r3-suite] PASS test_v0_p6_zero_write_fence -> ZERO_PRIVATE_P6_WRITE_PASS
[p6-r3-suite] PASS test_v0_p6_gateway_command_route -> ROUTE_PENDING_NO_DOUBLE_EXECUTION_PASS
[p6-r3-suite] PASS test_v0_p6_shared_outpost -> SHARED_OUTPOST_CANONICAL_COMPOSITION_PASS
[p6-r3-suite] PASS test_v0_p6_restart_recovery -> DELEGATED_RECOVERY_EXACTLY_ONCE_PASS
[p6-r3-suite] PASS test_v0_p6_fault_race_matrix -> FAULT_RACE_MATRIX_PASS
[p6-r3-suite] PASS test_v0_p6_repeat_soak -> REPEAT_IDEMPOTENCE_PASS
[p6-r3-suite][stage] V0_P6_R3_FOCUSED_SUITE_PASS
```

15/15 PASS, exit 0. Логи:
`artifacts/test-results/p6-r3-focused-suite-<pid>/` (gitignored, по правилу
«временные результаты только в artifacts/»).

Команда воспроизведения:

```bash
godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
project_dir="$HOME/distributed-world-simulator/distributed-world-simulator"
export GODOT_BIN="$godot_bin"
"$project_dir/RUN_V0_P6_R3_TESTS.sh"
```

## Что НЕ заявлено этой сессией

В соответствии с WO `V0-P6-R3-WO-001` stop-conditions, следующие предикаты
остаются открытыми и не считаются PASS:

- `V0_P6_R3_REAL_PROCESS_RESTART_RECOVERY_PASS` — OS-process рестарт-гейт
  нужно перепривязать к существующему M6 process recovery runner
  (паттерн `test_m6_dedicated_recovery_processes.gd`); текущие P6-тесты
  честно помечены как «delegation level, in-process»;
- `V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME` — литеральный soak
  не ускорять; `repeat_soak` теперь честно называется repeat/idempotence;
- `V0_P6_P7_P11_MCP_VISUAL_EVIDENCE_PASS` — MCP visual proof не проводился;
- canonical composition proof по РЕАЛЬНЫМ public surfaces M4/P4/P5/M6
  (в тестах — fixtures с контрактной формой, не live-сервисы);
- `FULL_WORLD_CORE_REGRESSION_PASS` — полный world/core regression не гонялся;
- fresh Reviewer/Verifier PASS, Evidence Map, checkpoint proposal — не выполнялись.

## Статус

`P6 R3 REPAIR — WIP / NOT VERIFIED / NOT MERGE READY`

Handoff-шаги 2–4 закрыты; следующий шаг — шаг 5 (M6-bound restart gate) и
затем полный world/core regression.
