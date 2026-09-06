# FABRIC BRIDGE-3 — FULL / BAKE / LOCAL UNBAKE / FULL

## Статус и границы

**RESEARCH EXACT CLOSED.** Исследовательская линия; production acceptance и merge в `main` не заявляются.
База B0.6: `b34f4cc24616f26dfcc6dcbdada2d664b478b64f`.
Exact runtime subject: `cf6730c48f6147243a5c99ebb48c19e09fb3093f`, TREE `13e38426a84d55ac7faac06c4eec05ae15a84139`.
Main policy observed: `fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91`.
Ветка: `research/fabric-bridge3-full-bake-unbake-full-r1`.
Риск HIGH: lifecycle, recovery и смена физического исполнителя.

## Design brief / bounded work order

Цель: реальный round-trip состояния через существующие structural aggregation,
refinement guard, reconstruction и topology rebake contracts. Construction/Matter
остаются единственными владельцами identity, topology, damage и source revisions.
Новый код управляет derived execution slots; не создаёт solver или canonical source.

A: binding, единственный physical writer, prepare/commit и receipt. ✅
B: FULL → STRUCTURAL_BAKE после B0.6 safety/hysteresis; detailed state освобождается. ✅
C: certified guard → bounded local FULL без реконструкции остальных деталей. ✅
D: continuity позы/скорости/импульса/энергии и boundary anchors; stale writer запрещён. ✅
E: внешняя canonical mutation → immediate invalidation → settle → fresh rebake. ✅
F: restart из canonical inputs; disposable capsule; идемпотентность и crash boundaries. ✅
G: FULL-reference parity, 500/1000/2000 canonical parts, two exact replays. ✅

## Почему local unbake действительно bounded

Closed `structural_local_unbake_runtime_v1.execute` сначала реконструирует весь parent.
BRIDGE-3 индексирует неизменяемые mapping constants при подготовке, материализует только
20 target parts и переносит два residual aggregate через аналитический rigid transform.
Metadata compilation остаётся явной O(N) работой и не маскируется как hot physical work.

## Exact closure

Canonical Godot: `4.7.1.stable.double.custom_build.a13da4feb`, SHA-256
`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
Final fresh import: exit 0, fatal 0.

Два независимых набора новых Godot-процессов дали одинаковые hashes:

- A `36d2da80dc6adda6f4ad998c2fd011add99dc8f718c9b1678f994d4f3cc72c30`
- B `f65fcb1550c9853693776a2c700e0acc3bd4706555e4b679139b314ae0727daf`
- C `813418ac63009b3e31bdc9a7e52b086557ddb96e962444c2e4e36bdf3c45a478`
- D `f1ab405d6c4829633d7934e456b2ecc37b5a4cff48d7b0184b759e6f46371f87`
- E `20acdd3b7789a21ab4699f9de1613b62aea0d06255bd498c5032e443ec7135c4`
- F `7eda96e277ef650f1f773630439502f095e666521378c0e740b577687d67aadb`
- F capsule `8f51c2eab36564a4f6060709fe582fc09ad7c1f09306063899454d9234e307fb`
- G `66eebb542071bc5e3786c5029ba75d96e6492a117b89585ed8e8ae15b8136984`

`BRIDGE3_CLOSURE_HASH=4f9ec661e99775d0afc85995d51a4d614158414fc760141daffe0dab1b25f4a4`.
BRIDGE-3 assertions per replay: 1253.

Scale invariant: 500/1000/2000 canonical parts all reveal exactly 20 FULL parts, keep 2 residual bodies,
finish as 2 rebaked bodies, perform 20 local rebake validations, `global_physical_rebuilds=0`,
`duplicate_ownership_count=0`. 500 additionally passes FULL/reference parity with max error
`2.1316282072803e-14 < 1e-8`.

## Predecessors

Fresh: B0.6 A-D PASS (including separate disk writer/reader), BRIDGE-2 122+125 PASS,
COMPLEX2-CLOSE 44 PASS with PERF hash `698486abd097e6ee12731b0afb1c6e28ed24bf72b52d8d940c9f5b7336498607`,
B0.5-P0 63 PASS. B0.6-E current smoke + 500-scale passed; 1000/2000 and B0.5-A retain their
previous exact-closed evidence because compare B0.6→BRIDGE-3 changes only new BRIDGE-3 paths.

Full machine evidence: `validation/fabric_bridge3/exact-closure.v1.json`.
Human-readable closure: `validation/FABRIC_BRIDGE3_CLOSURE.md`.

## Следующая линия

BRIDGE-3 CLOSED открывает COMPLEX3 research: **5k → 20k → 100k canonical parts** with sparse local physics.
