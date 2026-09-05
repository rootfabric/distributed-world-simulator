# FABRIC B0.6 ADAPTIVE PHYSICAL FIDELITY — RESEARCH EXACT CLOSED

**STATUS: CLOSED — research exact scope.** Production integration, main-owned
checkpoint acceptance и BRIDGE-3 не объявлены и не выполнялись.

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

## Восстановление

Recovered payload: `f50d19e4bdf54a4b89a4e7018314c6ee63e4578c`.
Его настоящий Git TREE: `5d33ff8f630f60d788330471144fcb14f1c93500`.
Bundle: 40331 bytes; SHA-256 `07183299d7d2f42f2f3a9127b244deedc30517b641c1e644299ac246358af458`.
Ошибка прежнего transport workflow — неверно переписанный expected TREE,
а не доказанная порча payload. Шесть implementation commits восстановлены
поверх новой ветки и опубликованы fast-forward; история не переписана.

Транспортная публикация и runtime evidence различаются. Ошибка Actions push
не была объявлена отсутствием Git authority: доступный GitHub API обновил
research ref без force. `main` не изменялся.

## Exact closure

Два новых checkout, два fresh import, 26 последовательных suites в каждом.
**47084 опубликованных assertion executions на один полный replay**;
это сумма PASS counts с повторными predecessor executions, не число уникальных тестов.
Общие exit codes: **0 / 0**. Import fatal count: **0 / 0**.

| Runner | Assertions per replay | Exit A/B |
|---|---:|---|
| `RUN_FABRIC_B0_6_HARNESS_TESTS.sh` | 7 | 0 / 0 |
| `RUN_FABRIC_B0_6_IMPORT_TESTS.sh` | 6 | 0 / 0 |
| `RUN_FABRIC_B0_6_A_TESTS.sh` | 114 | 0 / 0 |
| `RUN_FABRIC_B0_6_B_TESTS.sh` | 44 | 0 / 0 |
| `RUN_FABRIC_B0_6_C_TESTS.sh` | 679 | 0 / 0 |
| `RUN_FABRIC_B0_6_D_TESTS.sh` | 84 | 0 / 0 |
| `RUN_FABRIC_B0_6_E_TESTS.sh` | 17397 | 0 / 0 |
| `RUN_FABRIC_BAKE_BRIDGE2_A_TESTS.sh` | 71 | 0 / 0 |
| `RUN_FABRIC_BRIDGE2_CLOSURE_TESTS.sh` | 247 | 0 / 0 |
| `RUN_FABRIC_COMPLEX1B_TESTS.sh` | 182 | 0 / 0 |
| `RUN_FABRIC_COMPLEX2_TESTS.sh` | 4233 | 0 / 0 |
| `RUN_FABRIC_COMPLEX2B_TESTS.sh` | 65 | 0 / 0 |
| `RUN_FABRIC_COMPLEX2C_TESTS.sh` | 66 | 0 / 0 |
| `RUN_FABRIC_COMPLEX2D_TESTS.sh` | 50 | 0 / 0 |
| `RUN_FABRIC_COMPLEX2E_TESTS.sh` | 47 | 0 / 0 |
| `RUN_FABRIC_COMPLEX2_PERF_TESTS.sh` | 62 | 0 / 0 |
| `RUN_FABRIC_COMPLEX2_CLOSE_TESTS.sh` | 44 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_5_A_CLOSURE_TESTS.sh` | 130 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_4_D_CLOSURE_TESTS.sh` | 14956 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_2_E_TESTS.sh` | 3480 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_2_D_TESTS.sh` | 900 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_2_C_TESTS.sh` | 291 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_2_AB_TESTS.sh` | 173 | 0 / 0 |
| `RUN_FABRIC_BAKE_BRIDGE1_TESTS.sh` | 3626 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_1_TESTS.sh` | 97 | 0 / 0 |
| `RUN_FABRIC_BAKE_B0_0_TESTS.sh` | 33 | 0 / 0 |

## Replay hashes

Все нижеприведённые значения одинаковы в A и B; wall time и raw-log digests
не входят в deterministic closure hash.

```text
B06A_ENVELOPE_CHECKSUM=f1976723cf8afd0c2e831740373143ad3303c5ff48d18238c49039ed86304b30
B06A_SAFETY_HASH=9a152000bf636f5977034947b73431cdf7393a5201c63b06c5ebb15e20e1f627
B06B_SELECTION_HASH=d6c9c6aa07e0bd741a0fa50bb9d7ca9a10291043c680675f06fd58beb3818939
B06C_TRANSITION_HASH=e93dadfc821fb8299fc6a75d140a493be790860dcd294cd687403717d237f0aa
B06D_DISK_RECOVERY_HASH=ab2287a06a5427e5d73f15b5c7a6ad11267f5f3c9aad1e519a4cdc5cc13fc1f9
B06D_RECOVERY_HASH=f9613fe30c97322cfd1f81d6f74608a0bc58e51f6dbb8be6af37dff177ba8bba
B06E_FINAL_STATE_HASH=c751ffdbe8eff08629ec2b7a7a12eb1f388de158d721d8bdb4d60cafc6280889
B06E_TRANSITION_HASH=9ebdbc3537fcd67175bb4d007da185f6a33745a9730b50dcf9144f83a0839622
B06E_WORK_HASH=9b4865017e9e959fda0fb8472b6684fd0f18ea4bd71f508936dee873fdd75942
B06_CLOSURE_HASH=892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584
```

## Проверенные инварианты

A–E PASS; scale 500/1000/2000 PASS; нет unsafe selections, duplicate ownership
или global rebuilds в scale campaigns; immediate promotion и causal wake локальны;
consecutive-safe demotion ограничена одним уровнем; noisy stimulus не вызывает
thrash, но sustained-safe всё же приводит к demotion; stale/corrupt derived capsule
не меняет canonical source и не восстанавливает unsafe execution; replay recovery
идемпотентен. Действительные work counters находятся в E evidence и machine JSON.

## Исправления prerequisite/harness, без изменения physics semantics

SYNC4 runner и acceptance восстановлены exact из historical commit `07b3bf9d`.
Шесть старых ECO-сцен получены byte-exact из existing repair
`8758f3ede130e953461b27fff1df1aee27cd7e06`; изменение каждого файла — только удаление
трёх bytes UTF-8 BOM. Godot load/instantiate/free smoke: 6 PASS.
Strict import validator больше не имеет исключений для исторических Parse Error.
Runner проверяет Godot exit, PASS sentinel, fatal markers и exit самого tee.
Семь executable negative/positive harness checks входят в оба полных replay.

## Project Control и область принятия

Canonical main после refresh: `fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91`, registry generation 80.
Existing standard/directional Python auditors: exit 0, YELLOW/NON_RED.
Unrelated advisory findings не скрыты и не названы GREEN. Actual B0.6 changed-path
intersection с registered consumer watched/critical paths: 0, critical 0.

В main-owned catalog нет FABRIC/B0.6 product checkpoint; research closure не создаёт
новый product lease, source authority или main acceptance record. Два fresh-checkout
runtime verification выполнены. Отдельный независимый agent-review verdict не
приписывается этой работе; production promotion сохраняет отдельные normal review,
verification, dependency и human merge gates. См. scope/critique и machine applicability.

CI workflows A–E/CLOSE опубликованы, проверяют exact Linux double version/hash и
не скачивают Godot. На проверенном runtime HEAD все шесть runs были QUEUED;
historical run 33890908585 тоже QUEUED. Это не CI PASS. Основание research exact
closure — завершённые локальные процессы на приложенном canonical binary.

## Refresh новых Git transport правил

Во время exact verification main перешёл с `5b4152958624be4e9cc40f2369ce32c4964f65c3`
на `fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91` (merge 2026-09-05 14:10:58 UTC).
Изменились только harness policy, её loader и три новых policy tests; physical runtime,
registry, checkpoint catalog и review policy не менялись. Все три Git blobs, full tree,
parent commit и signed merge были сверены с GitHub SHA при прямом API чтении.
После refresh PC0 и directional audit повторно NON_RED; критических пересечений нет.
Новые policy tests из exact-main checkout: 3/3 PASS, exit 0.

Реконструкция потерянного payload состоялась ранее (run 33970134210, 13:52:02 UTC).
Она сохранена как historical recovery, не как разрешённый будущий transport path.
После новой политики Actions больше не используется для передачи исходников.
Оба старых transport/source-package workflows переведены в retired: нет push trigger,
нет write permissions, нет запуска source recovery, job всегда disabled. Шесть обычных
canonical double runtime CI workflows не изменены. Публикация evidence — только прямой
authenticated GitHub API с non-force ref update. Main не изменяется этой работой.
Machine proof: `validation/fabric_b0_6/main-policy-refresh.v1.json`.

## Source HEAD и evidence carrier

Runtime subject HEAD/TREE указаны выше и проверены до записи evidence. Итоговый
commit добавляет evidence/docs и отключает два obsolete transport-workflows;
он не выдаётся за новый runtime run.
Все Godot executable/test/runner blobs и шесть обычных runtime CI workflows тождественны
проверенному subject. Итоговые carrier HEAD/TREE фиксируются публикационным receipt.

**NEXT FOUNDATION STEP: BRIDGE-3 — FULL → BAKE → UNBAKE → FULL. Не начат.**
