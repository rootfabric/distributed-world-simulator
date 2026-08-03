# Checkpoint v17.4.0 — MW4 Matter Mutations fix1

## Статус

```text
checkpoint: v17.4.0-simulation-mw4-matter-mutations
delivery:   fix1
build_id:   mw4-matter-mutations-fix1
base:       v17.3.0-simulation-mw3-local-meshing / fix2
branch:     feature/mw4-matter-mutations
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Блокирующий результат initial delivery

Independent review исходного MW4 подтвердила корректность ZIP, JSON и MW2/MW3 regression, но focused-процесс не завершился за 600 секунд. Процесс непрерывно использовал CPU и не сообщил ни `PASS`, ни parser/runtime failure.

Это является блокирующим дефектом тестового и runtime hot path: checkpoint не может быть принят, пока focused gate не завершается воспроизводимо.

## Причина

`MatterBrickSnapshot.sample_at()` выполнял полную `MatterBrickSnapshot.validate()` при каждом чтении sample. Snapshot MW2 содержит 1331 samples. Excavation kernel читал каждый sample этим методом, поэтому один brick выполнял примерно квадратичный объём работы:

```text
1331 reads × validation of 1331 samples
```

`MatterSnapshotSampler` вызывал тот же путь для восьми углов каждого trilinear sample, а raycast повторял его на каждом шаге.

Проблема не связана с числом физических операций или бесконечным циклом; это повторная криптографическая и структурная валидация неизменяемого DTO внутри горячих циклов.

## Исправление

### Validation boundary

Добавлены два accessor-а:

```text
MatterBrickSnapshot.sample_at_validated()
MatterBrickSnapshot.sample_payload_at_validated()
```

Их контракт:

1. вызывающая сторона один раз выполняет полную `MatterBrickSnapshot.validate()`;
2. accessor читает уже проверенные columnar channels без повторной проверки всего snapshot;
3. публичный `sample_at()` остаётся полностью fail-closed;
4. любой новый snapshot после изменения снова проходит полную валидацию и checksum.

Columnar snapshot validator больше не создаёт и не SHA-проверяет временный `MatterSample` на каждой lattice-точке. Он напрямую проверяет те же инварианты:

- finite values;
- ratio ranges;
- non-negative density/temperature;
- valid composition palette;
- flags channel type и прежнюю нормализацию через canonical `MatterSample` output;
- vacuum/occupied SDF semantics;
- итоговую JSON safety и snapshot checksum.

### Excavation kernel

Kernel:

- валидирует snapshot, grid и swept shape один раз;
- вычисляет cell bounds один раз;
- обходит lattice линейным `z/y/x` циклом;
- использует `signed_distance_validated()` для уже проверенной swept shape;
- создаёт canonical `MatterSample` только для реально изменённых точек;
- сохраняет narrow-band, mass integration и revision semantics без изменений.

### Continuous query

Raycast хранит cache по `MatterBrickAddress.address_id`. Каждый stored snapshot:

- извлекается один раз;
- полностью валидируется один раз;
- затем используется `sample_continuous_validated()` для всех последующих шагов raycast и bisection.

### Focused workload

Полнота focused-профиля сохранена, но устранено дублирование:

- cross-brick fixture планирует ровно четыре target bricks;
- single-cell fixture вычисляется один раз;
- streamer использует уже committed cross-brick tunnel;
- streamer materializes только одну desired cell;
- stored/procedural mesh сравниваются для центрального изменённого brick;
- fault-injected rollback, replay, stale revision, energy и capacity сценарии остаются.

### Bounded runner

Focused script печатает:

```text
MW4 matter mutations: START
MW4 stage <name>: START
MW4 stage <name>: DONE (<seconds> s)
```

PowerShell и Bash runners имеют watchdog 300 секунд по умолчанию. При timeout Godot завершается, runner возвращает exit code `124`, а последний stage-маркер показывает горячую область.

PowerShell override:

```powershell
.\RUN_MW4_MATTER_MUTATIONS_TESTS.ps1 -GodotPath $godot -TimeoutSeconds 600
```

Linux override:

```bash
MW4_TIMEOUT_SECONDS=600 ./RUN_MW4_MATTER_MUTATIONS_TESTS.sh
```

## Неизменившиеся семантические гарантии

Fix1 не меняет:

- swept-capsule target planning;
- one-sample narrow-band SDF difference;
- expected-revision fences;
- atomic multi-brick commit;
- exact replay/fingerprint conflict;
- per-material mass ledger;
- energy и receiver capacity policy;
- compensating rollback;
- session-local persistence;
- selective MW3 presenter invalidation.

## Обязательная independent review

1. MW4 focused завершается до runner timeout и печатает финальный `PASS`.
2. Все stage-маркеры завершаются; длительности фиксируются в логе.
3. Cross-brick target set равен четырём, не менее двух bricks реально изменяются.
4. Tunnel center является vacuum, raycast находит стену.
5. Replay, stale revision, low energy, full receiver и journal fault не оставляют побочных изменений.
6. MW3 — `7519/7519 PASS`.
7. MW2 — `7470/7470 PASS`.
8. MW1 — `3685/3685 PASS`.
9. MW0 — `2011/2011 PASS`.
10. A3 — `12/12 PASS`.
11. M6 — `10/10 PASS`.
12. `git diff --check` — PASS.
