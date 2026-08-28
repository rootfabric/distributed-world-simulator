# ECO EVO7 / PERF1 — Generation Profiling R1

## Predecessor

Accepted ECO-VIS3 R1:

`c3d72da0268e196c8d5f3b1eb65631e76ae7d1e5`

PERF1 — только observability/performance checkpoint. Он не должен менять biology, deterministic identities или ecology/workbench hashes.

## Что измеряется

Один live generation разбит на уровни:

```text
Workbench total
├─ ecology.step_generation
│  ├─ LS3.3 dispersal/recruitment
│  │  ├─ candidate reproduction/build
│  │  ├─ route build
│  │  ├─ recruitment evaluation
│  │  ├─ materialize recruits
│  │  ├─ commit/hash
│  │  └─ validation/snapshot
│  └─ LS3.4 competition
│     ├─ phenotype/environment prepare
│     ├─ light field
│     ├─ water fields
│     ├─ geometry overlap
│     ├─ competition evaluation
│     └─ finalize/validate
├─ ecology validation
└─ observability
   ├─ repeated ecology validation
   ├─ LS3.5 classification
   │  ├─ primary classify
   │  ├─ validation
   │  └─ deterministic recompute oracle
   └─ spatial Observatory
```

Все значения времени получаются через `Time.get_ticks_usec()` и хранятся только в side-channel profiling dictionaries. Эти поля не добавлены в canonical ecology/workbench snapshots и не участвуют в state hashes.

## Runtime API

Workbench:

- `get_last_generation_profile()`;
- `get_generation_profile_history()` — максимум 64 generation profiles.

LS3.3 / LS3.4 / LS3.5 имеют read-only `get_last_profile()`.

VIS3 Performance HUD теперь показывает detailed PERF1 breakdown, включая `parents / candidates / precompetition / postcompetition` counts.

## Exact local evidence

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Focused checks:

```text
LS3.3 Dispersal Recruitment       PASS 44/44
LS3.4 Local Competition           PASS 42/42
PERF1 Generation Profiler         PASS 69/69
VIS3 Planet Patch / Biome Viewer  PASS 107/107
```

Long LS3.6 historical acceptance locally не использован как PERF1 gate из-за уже известной длительной lifecycle/runtime особенности старого test path; PERF1 acceptance отдельно создаёт два одинаковых Workbench и доказывает exact identity parity при включённой telemetry.

## 12-generation local campaign

Default seeds / exact double Linux run:

```text
gen 1   pop 61   parents 64   candidates 128   precompetition 69
gen 12  pop 96   parents 103  candidates 206   precompetition 101
```

Среднее за 12 generations:

| Stage | avg ms |
|---|---:|
| total generation | 1566.33 |
| LS3.3 total | 781.98 |
| recruitment evaluation | 432.99 |
| candidate build/reproduction | 279.42 |
| LS3.5 classification total | 451.75 |
| classification primary compute | 199.78 |
| classification validation | 251.94 |
| classification recompute oracle | 185.91 |
| LS3.4 competition pass | 178.44 |
| geometry overlap | 9.85 |
| ecology validation | 43.47 |
| repeated ecology validation | 38.60 |
| spatial Observatory | 2.93 |

Generation 12 snapshot:

```text
total                ~2095 ms
LS3.3 total           ~1164 ms
  candidate build      ~429 ms
  recruitment eval     ~630 ms
classification         ~468 ms
competition            ~249 ms
geometry                ~15 ms
```

## Что это доказывает

1. На текущем масштабе `geometry overlap` не является главным bottleneck, несмотря на quadratic pair loop.
2. Главный scaling target — LS3.3: reproduction/candidate construction + recruitment evaluation.
3. LS3.5 classification — второй крупный постоянный cost.
4. Classification validation сейчас специально пересчитывает `_classify_unchecked()` как deterministic oracle; это видно отдельно и стоит оптимизировать до распараллеливания.
5. Workbench дважды валидирует ecology: после `step_generation()` и ещё раз внутри observability refresh. PERF1 теперь показывает обе стоимости отдельно.
6. VIS3 rendering/history по предыдущему Windows evidence значительно дешевле evolution step; оптимизацию надо начинать с simulation path.

## Acceptance

PERF1 R1 считается готовым к acceptance, если:

- existing deterministic hashes не изменились;
- profile API side-channel only;
- profiler acceptance green;
- campaign формирует finite/nonnegative stage timings;
- detailed VIS3 HUD показывает те же стадии;
- parallel execution не включается в PERF1 R1.

Следующий отдельный checkpoint после PERF1: `PERF1-PAR0` — deterministic parallel execution feasibility.
