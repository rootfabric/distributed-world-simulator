# ECO EVO7 PERF1 — варианты parallel execution / multiprocessing

## Короткий вывод

Параллелизм имеет смысл, но **не надо начинать с quadratic geometry loop**: текущий профиль показывает всего ~10–16 ms geometry при ~1.5–2.1 s generation. Главные цели — LS3.3 recruitment/candidate work и LS3.5 classification.

Рекомендуемая последовательность:

```text
PERF1 profiling
  ↓
cheap serial wins
  ↓
PERF1-PAR0 persistent-process shadow prototype
  ↓ exact serial/parallel hash parity
WorkerThreadPool migration where safe
  ↓
production-quality parallel kernels
```

## Godot 4.7 возможности

### WorkerThreadPool

Godot имеет глобальный `WorkerThreadPool`, который заранее выделяет worker threads и поддерживает group tasks. Это лучше, чем создавать `Thread` непосредственно перед каждым generation step.

Official docs:

- https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html
- https://docs.godotengine.org/en/4.7/tutorials/performance/using_multiple_threads.html
- https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html

Ограничения для нашей модели:

- SceneTree нельзя трогать из worker path;
- shared Array/Dictionary size changes требуют синхронизации;
- shared mutable resources надо исключить;
- deterministic merge order должен быть каноническим независимо от scheduler order.

Наш ecology kernel уже в основном `RefCounted + Dictionary/Array`, а не Nodes, поэтому после выделения pure immutable kernels WorkerThreadPool выглядит технически подходящим.

### Отдельные процессы

`OS.create_process()` запускает независимый OS process. `OS.execute_with_pipe()` умеет создавать независимый process с redirected stdin/stdout/stderr и возвращает pid + FileAccess pipes.

Official OS docs:

- https://docs.godotengine.org/en/stable/classes/class_os.html

Для первого isolation prototype процессы интересны тем, что worker не разделяет память и не может случайно мутировать canonical Workbench state.

Но процесс-на-каждую-особь или процесс-на-каждый-generation запрещён по design: startup + serialization overhead уничтожит выигрыш. Нужен **persistent worker pool**, созданный один раз при запуске ecology session.

Отдельно: у `execute_with_pipe` исторически были проблемы/краевые случаи вокруг pipe lifecycle; поэтому transport нельзя считать готовым без Windows+Linux probe. См. Godot issue #102340 и последующие fixes. В локальном PERF1 эксперименте простой pipe prototype не был принят в checkpoint из-за blocking/hang поведения, поэтому process transport вынесен в отдельный PAR0 gate.

## Что можно распараллелить

### 1. LS3.3 candidate reproduction — хороший target

Каждый parent порождает фиксированное число offspring. Mutation seed уже выводится из deterministic identity:

```text
parent identity + generation + offspring ordinal -> mutation seed
```

Можно partition parents на chunks, независимо построить candidates, затем объединить и **canonical sort by candidate_hash**.

Требование: child bundle/reproduction code не должен иметь global mutable RNG/state.

### 2. LS3.3 recruitment evaluation — лучший ранний target

PERF1 показывает ~630 ms уже на generation 12 / population 96 и ~433 ms average в 12-generation campaign.

Каждый candidate/route имеет immutable destination environment cell и deterministic establishment gate. Это почти embarrassingly parallel.

Partition key: sorted candidate_hash range.

Merge: sorted `candidate_hash`.

### 3. LS3.5 classification — хороший target после serial cleanup

1024 cells можно рассчитывать параллельно после построения immutable lookup maps `eval_by_id`, `water_by_cell`, population-by-cell.

Но сначала надо убрать очевидный serial duplicate work: текущий `validate_classification()` повторно вызывает `_classify_unchecked()` целиком как oracle. PERF1 показывает ~186 ms average только на этот recompute.

### 4. Water fields — хороший cell-parallel target

В LS3.4 water field вычисляется независимо для occupied cells после prepare phase. Можно partition по sorted cell index.

### 5. Geometry overlap — позже

`_geometry_pressures()` содержит nested pair loop и теоретически O(N²), однако PERF1 сейчас показывает ~10–16 ms. До роста population это не приоритет.

Если станет bottleneck, сначала лучше spatial bucketing / neighbor cell lists, а потом threads/processes.

## PERF1-PAR0 process protocol

Предлагаемый request:

```text
protocol_version
job_id
generation
phase
worker_index / worker_count
input_hash
immutable seeds
canonical chunk records/candidates
required environment cells
```

Response:

```text
job_id
phase
input_hash
result_count
canonical sorted results
result_hash
worker_time_us
```

Coordinator обязан:

1. partition только канонически;
2. не передавать worker global RNG;
3. объединять ответы только canonical sort;
4. заново вычислять aggregate hashes в coordinator;
5. при worker failure делать fail-closed или serial fallback;
6. в shadow phase запускать serial oracle рядом и сравнивать exact hashes.

## Mandatory parity gate

До включения parallel result как authoritative research state:

```text
worker_count = 1 / 2 / 4 / N
same initial seed + same environment
100+ generations / multiple recipes

candidate_pool_hash     EXACT
recruitment_hash        EXACT
population_hash         EXACT
competition_hash        EXACT
classification_hash     EXACT
workbench_hash          EXACT
```

Любое различие = PAR0 FAIL.

## Что делать сначала

1. PERF1 принять и снять Windows breakdown на populations ~300/450/650.
2. Убрать duplicated classifier recompute из hot path через cheaper validation strategy, сохранив independent oracle в tests/debug mode.
3. Убрать repeated ecology validation в одном generation path либо перевести второй validation в debug/profile gate.
4. Сделать PAR0 prototype именно для LS3.3 recruitment evaluation.
5. Сравнить serial vs 2/4 workers, включая serialization cost.
6. Если process transport overhead приемлем — временно использовать persistent processes.
7. Затем перенести pure kernel на `WorkerThreadPool`, где это даёт лучший latency и меньше IPC overhead.
