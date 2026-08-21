# ECO P4.7 — Production Integration Soak — CANONICAL CANDIDATE

Статус: `BOUNDED_ROTATING_ISOLATED_HEADLESS_CANONICAL_RUNNER_READY / EXACT_COMMITTED_A_B_PENDING`.

Parent P4.6 принят как `ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION`. P4.7 не вводит scheduler, authority или network transport: это bounded deterministic integration harness для уже принятых P4.1–P4.6 контрактов.

## Текущий R9 scenario

```text
8 authoritative regions
12 deterministic cycles
1 rotating active region per cycle
8 real deep ecology generations total
12 P4.4 serialize/deserialize round-trips
12 P4.5 CAS snapshot commits
4 P4.5 ownership handoffs
3 persistence restart -> ownership reconstructions
12 P4.6 monotonic client-cache updates
12 active-region interest projections
2 full 8-region fanout projections
```

Exact bounds:

```text
region_count                 = 8
cycles                       = 12
ecology_generation_steps     = 8
handoff_count                = 4
save_load_count              = 12
client_update_count          = 12
interest_projection_count    = 14
restart_count                = 3
max_remaining_due_steps     <= 1
```

Fresh-process A/B logs должны быть byte-identical. Hard timeout остаётся 600 секунд; timeout не увеличивался.

## Repair history

### R5 — GDScript type inference

Exact Windows parser на Godot `4.7.1.stable.double.custom_build.a13da4feb` обнаружил untyped `SERVERS`/`target_server`. Исправлено только в acceptance test явной типизацией.

### R6/R7 — performance amplification

Первый и второй exact Windows runs достигли 600-second timeout. После code-path inspection выяснилось, что стоимость определялась не только deep ecology stepping, но и повторной recursive validation/deep duplicate/serialization через P4.4/P4.5/P4.6. Текущий bounded rotating scenario сохраняет восемь authoritative regions и все cross-layer boundaries, но выполняет один полный expensive mutation path на цикл вместо 96 повторов нижележащих acceptance checks.

### R8 — phase heartbeat

`ECO_P4_7_PROGRESS_FILE` даёт non-canonical progress channel (`initialize region`, `cycle`, `full fanout`). Он не входит в canonical hashes и не влияет на stdout determinism.

### R9 — isolated headless project

Exact Windows run на HEAD `6e7c6e47186ac5dbccb18ec17997d34f7cf06524` завершил сам P4.7 scenario успешно:

```text
PASS (242 assertions)
soak_hash=d7cee96abd82c09afab50873bb07271d112684ccad3be4127a995ff8501cd2fe
final_interest_hash=62d28c383697a01c5b96ec6e9c72b3e71a8fbf5e51a76ddeccacae3885decd2e
handoff_count=4
ecology_generation_steps=8
save_load_count=12
client_update_count=12
interest_projection_count=14
restart_count=3
max_remaining_due_steps=0
region_count=8
cycles=12
```

Эти hashes пока **не frozen acceptance evidence**, потому что fresh-process B не был запущен: runner отклонил A после `quit(0)` из-за unrelated project-level autoload errors.

Repository `project.godot` содержит:

```text
BreakpointRuntimeBridge="*uid://cpjc0o64cgs1"
```

а UID sidecar действительно принадлежит `addons/breakpoint_mcp/runtime_bridge.gd`. На clean validation clone project startup после ecology script дал:

```text
Resource file not found: res://
Failed to instantiate an autoload, can't load from path: .
```

Это не разрешено allowlist'ом. R9 вместо этого создаёт временный minimal Godot project без gameplay/MCP autoloads и подключает exact committed `scripts/` и `tests/` validation checkout через NTFS junctions. Поэтому:

```text
project.godot не изменяется
production runtime не изменяется
accepted P4.1-P4.6 не изменяются
unexpected Godot ERROR всё ещё = FAIL
```

## Candidate pins R9

```text
soak test blob = 49821079787479212feb78a10a4703bc52ba89b3
runner blob    = 2bd6e1da8951238ff36b61e9ca5813a125e0dcd4
validation     = 8e4c2fdf3da60eb662a91456392620fb10ffb3e9
```

## Lifecycle boundary

P4.7 нельзя принять до нового exact committed Windows isolated-project A/B PASS с byte-identical logs. Только тогда `soak_hash` и `final_interest_hash` становятся frozen evidence.

P4.8 control preparation перепинована на R9, но финальный P4 acceptance остаётся fail-closed до P4.7 lifecycle acceptance.
