# FABRIC B0.6-E — Scale / Anti-thrash: EXACT PASS

## Exact subject и runtime

Branch: `research/fabric-bake0-6-adaptive-physical-fidelity-r1`.
Runtime HEAD: `2254b450b4d31832a6c143fc85096372679c6bc6`.
Runtime TREE: `82532abb755b6b652b84a96ff5d92a8225cd8dba`.
Godot: `4.7.1.stable.double.custom_build.a13da4feb`.
Binary SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Два завершённых запуска из разных новых Git checkout: `exact-a` и `exact-b`.
В обоих fresh import: exit 0, fatal 0; runtime runner: exit 0. Это измеренные
результаты, не перенос прежних PASS и не GitHub Actions, остающийся в очереди.
Machine evidence: `validation/fabric_b0_6/exact-replay.v1.json`.
Raw archive: `DWS_B0_6_EXACT_RUNTIME_EVIDENCE.zip`, SHA-256 `f0fe97043abd8b1bc774a9e6c471b46c6f74b72d999bd836f1368b6fd3f2faaf`.

## Реализация и acceptance

Implementation: `scripts/research/fabric_bake0/adaptive_physical_fidelity_runtime_v1.gd`.
Runner: `RUN_FABRIC_B0_6_E_TESTS.sh`.
Assertions на каждый replay: **17397 = 17397**.
Результат обоих запусков: **PASS**, exit **0**.

500/1000/2000 independently addressed subjects, все пять fidelity levels, локальные danger/source/causal stimuli, 80 шумовых ticks, затем sustained-safe demotion. Реальный single-owner slot использует существующие BRIDGE-2 adapter/reconstruction/execution-gate contracts. Это масштабирование управления representation, не заявление о 2000 полноценных численных COMPLEX2 машинах. Численные свойства проверяются отдельной predecessor chain.

## Fresh-process equality

Оба запуска дали одинаковые значения:

```text
B06E_FINAL_STATE_HASH=c751ffdbe8eff08629ec2b7a7a12eb1f388de158d721d8bdb4d60cafc6280889
B06E_TRANSITION_HASH=9ebdbc3537fcd67175bb4d007da185f6a33745a9730b50dcf9144f83a0839622
B06E_WORK_HASH=9b4865017e9e959fda0fb8472b6684fd0f18ea4bd71f508936dee873fdd75942
```

## Детерминированная работа

| Counter | 500 | 1000 | 2000 |
|---|---:|---:|---:|
| `actual_transitions` | 25 | 50 | 100 |
| `blocked_demotions` | 220 | 440 | 880 |
| `demotions` | 10 | 20 | 40 |
| `duplicate_ownership_count` | 0 | 0 | 0 |
| `envelopes_compiled` | 1445 | 2890 | 5780 |
| `failed_closed` | 0 | 0 | 0 |
| `global_rebuilds` | 0 | 0 | 0 |
| `local_rebuilds` | 525 | 1050 | 2100 |
| `promotions` | 15 | 30 | 60 |
| `reconstructions` | 525 | 1050 | 2100 |
| `selector_decisions` | 1445 | 2890 | 5780 |
| `subjects_evaluated` | 1445 | 2890 | 5780 |
| `transition_requests` | 245 | 490 | 980 |
| `unsafe_selection_count` | 0 | 0 | 0 |

Счётчики включают первоначальную подготовку N владельцев. Обычный контрольный проход после регистрации не создаёт переходов; суммарные subjects/envelopes/selectors равны 2N. При N→2N все deterministic work counters растут ровно вдвое. Все snapshot/state/transition/counter данные побитово-логически совпали между свежими процессами.
