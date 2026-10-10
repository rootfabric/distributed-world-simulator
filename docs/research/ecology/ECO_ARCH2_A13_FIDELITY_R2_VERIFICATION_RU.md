# ECO ARCH2 A13 — Fidelity Scheduling R2: верификация и независимое ревью

Статус: R2-кандидат проверен. PR #744. Слияние не выполнялось.

## Субъект

- PRODUCT_HEAD: `f74770b9b765ce2dcb20c4378ed54146f9a77d34`
- PRODUCT_TREE: `bb6c2289865d9ddfe7da952834dc43c54c41dbcb`
- BASE_MAIN (merge-base == origin/main на момент R2): `53567c0b98d032260dfe81df4bd43a131e32da54`
- Drift: 0 позади / 17 впереди base; ветка `feature/eco-arch2-a13-fidelity-scheduling-r1`.

## Семантическое ревью

Собственное ревью и свежее независимое ревью (fresh reviewer, read-only, тот же
HEAD) сошлись: BLOCKER/MAJOR/MINOR дефектов нет. Проверено:

- FULL/REDUCED/PATCH унаследованы от A9; PATCH→FULL/REDUCED только через новый
  план после внешнего уточнения (неявного восстановления истории PATCH нет);
- избыточный явный FULL канонизируется (байты плана не зависят от ввода);
- debt_ticks = target − committed, жёсткая граница 64, catch_up_ticks всегда
  равен полному долгу при готовности (частичная публикация структурно
  невозможна, runtime-постусловие replayed == debt && tick == target);
- глобальная связность: любой PATCH тайл блокирует глобальный коммит; один
  глобальный аллокатор A5, вторго биологического ядра и per-tile аллокаторов
  нет; replay идёт исключительно через верифицированный
  `step_spatial_parallel_advance`;
- atomic rollback: replay мутирует только локальную копию; все пути отказа не
  возвращают состояние; вход байт-точен после отказа (покрыто тестом);
- stale plans: validate() полностью перестраивает план и сравнивает байты;
  frontier-проверка `committed_scheduler_tick == state.tick`; неизвестные
  адреса/режимы/подделки закрываются отказом;
- checkpoint integrity: схема/байты планировщика не входят в Runtime/checkpoint
  (проверено равенством сериализации чекпоинтов);
- детерминизм: порядок overrides и перестановка population не меняют байты.

NOTE-уровень (без изменений кода, вне R1-скоупа):

1. План у потолка тиков (`committed + cadence > MAX_TICK`) отвергается целиком,
   включая безобидный no-op у MAX_TICK — fail-closed, в поддерживаемых
   фиксстурах недостижимо.
2. Атомарность mid-replay отказа гарантирована структурно, но форсирующий
   фиксстур (отказ после ≥1 успешного тика) не создан.
3. validate() перестраивает Spatial.create на каждый вызов — стоимость O(N),
   performance-заявления отложены work order-ом.

Все 13 критериев приёмки work order-а покрыты конкретными проверками.

## Exact-прогоны (оба — фактические, exit 0, tracked-дерево чисто)

Engine: `4.7.1.stable.double.custom_build.a13da4feb`.
Linux SHA-256 `bfa7ce63…7d7` (Ubuntu 24.04 WSL2, канонический архив
`godot-4.7.1-linux-double-x86_64-a13da4f.tar.gz`); Windows SHA-256
`3633c3e6…a7a5` (`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`).

| Suite | Linux | Windows | checks |
|---|---|---|---|
| A13 Fidelity (focused) | PASS | PASS | 117 |
| A13 Parallel Advance | PASS | PASS | 140 |
| A13 Activity | PASS | PASS | 122 |
| A13 Parallel Prepare | PASS | PASS | 93 |
| A13 Spatial | PASS | PASS | 108 |
| A13 Exact Worksets | PASS | PASS | 58 |
| A12 Population Scale | PASS | PASS | 38 |
| A11 Persistent Session | PASS | PASS | 171 |
| A9 fidelity contract (32 теста) | PASS | PASS | — |

Evidence SHA-256 (первые 16), HEAD `f74770b9b` в каждой записи:

- Linux: fidelity `029b5d2b2d6946d2`, parallel-advance `6ebc40553abd7135`,
  activity `4c595f8b71bdb40a`, parallel-prepare `bf20e0d561f0460f`,
  spatial `171db9a63437bb3d`, a13 `6b732b231feaa32c`, a12 `1ea3a53a0d3c7997`,
  a11 `f6ba94861453d4e5`.
- Windows: fidelity `4e930ce5e5ef7f11`, parallel-advance `99659fdafa080be2`,
  activity `111fa80883c9fb00`, parallel-prepare `c140f2d48867fa64`,
  spatial `21c10e73194549a2`, a13 `142706bb1d1bf71d`, a12 `45b8fe29d41a8a69`,
  a11 `0b4e374dc62b235b`.

CI на HEAD: все Linux exact джобы success; Windows exact джобы self-hosted
матрицы — cancelled (как и в предшествующих A13-прогонов), восполнено
фактическим локальным Windows exact выше.

## Воспроизведение Windows exact

Свежий worktree на `f74770b9b` + канонический binary, затем та же
последовательность, что в `eco-arch2-a13-fidelity-exact.yml`:

```powershell
$repo = '<worktree>\distributed-world-simulator'   # HEAD f74770b9b, чистый
$godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
Set-Location $repo
& $godot --headless --editor --path $repo --import
python -m py_compile validation/ecology/evo_arch2_a13_fidelity/run_exact.py
python validation/ecology/evo_arch2_a13_fidelity/run_exact.py --godot $godot
python -S validation/ecology/evo_arch2_a13_fidelity/run_a9_contract.py
python validation/ecology/evo_arch2_a13_parallel_advance/run_exact.py --godot $godot
python validation/ecology/evo_arch2_a13_activity/run_exact.py --godot $godot
python validation/ecology/evo_arch2_a13_parallel_prepare/run_exact.py --godot $godot
python validation/ecology/evo_arch2_a13_spatial/run_exact.py --godot $godot
python validation/ecology/evo_arch2_a13/run_exact.py --godot $godot
python validation/ecology/evo_arch2_a12/run_exact.py --godot $godot
python validation/ecology/evo_arch2_a11/run_exact.py --godot $godot
git diff --exit-code; git diff --cached --exit-code
```

## Итог

READY_FOR_MERGE: да — с открытыми NOTE-замечаниями выше (ни одно не требует
изменения кода для R1-скоупа). Repair не потребовался: новых продуктовых
коммитов в ветке нет, HEAD `f74770b9b` не менялся. Merge — только по
отдельному человеческому решению.
