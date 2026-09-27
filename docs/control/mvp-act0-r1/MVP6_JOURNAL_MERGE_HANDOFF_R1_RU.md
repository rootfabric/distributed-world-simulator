# Journal baseline repair: точный HUMAN merge gate

Требуется одно действие: разрешить merge PR #646
https://github.com/rootfabric/distributed-world-simulator/pull/646
с HEAD `d9706b157e84c653a753cc54243ce6651d53319c`, tree
`4925ea293c15d88153278437976a3b69f8985ccf` в canonical main.
Последний fetch подтвердил main `6982a563dd0c88c81449566131852c601ae89868`,
tree `97c61acc96f507d71b6883fbdeef486c08b1113d`.

Это merge причинного baseline repair, не acceptance V0→NX clearance.
Согласованные четыре строки journal исправляют stale optimistic projection
после same-revision rejection. Journal blob `abdf0c0a335f4e2c968933156fb17f94a7b45bd1`.
ACT0 control guard сохраняет историческую неизменность, разрешает только этот
точный old/new blob по immutable resolved HA/patch и отклоняет посторонние
runtime/evidence/scene изменения. Временные Git fixtures не запускают detached
maintenance; строгая очистка и 23 негативных сценария сохранены.

## Exact evidence map

| Предмет | Результат и граница |
|---|---|
| Feature73b88181, journal runtime | Native408/security48, MVP3 232/MVP5 270, MVP4 45+57, journal77, NX6 940, bridge66 PASS |
| Main runtime3b82145a | Windows/Linux77/940/66 PASS; полный world327 scripts/332 steps PASS |
| Literal world soak | 1 800 002 мс, 29 checkpoints, 51 assertions; composition-level, не MVP6 five-process |
| World diagnostics | 9 ERROR/8 WARNING сохранены; cleanup errors воспроизведены на exact main, остальные ERROR — explicit negative assertions |
| NX composition73b88181 | Windows/Linux baseline+approved repair и candidate1077/1077 PASS; dependency_revalidated=false до canonical repair |
| Construction fixture84ab0c0f | Windows/Linux223/64/77 PASS; canonical resources8→6→2→0; physics/five-process не подтверждены |
| Controld9706b15 | Windows18/18, 23 негативных Git cases; Linux все18 ACT0 PASS |
| Full Linux Harnessd9706b15 | 330 tests, 1 failure только live directional PC0 RED, 0 errors/skips; raw suite остаётся FAIL |
| Fresh независимые роли | Journal, Construction, world/core и финальный control получили отдельные bounded Reviewer/Verifier PASS |

Полные raw пакеты и hashes:

- `journal-resolution-exact-r1/machine-manifest.json` — исходные Windows/Linux/NX результаты.
- `journal-resolution-roles-r1/` — независимые journal verdicts.
- `construction-fixture-evidence-r1/manifest.json` — focused Construction и роли.
- `journal-world-control-evidence-r1/manifest.json` и `world-core-review/`,
  `world-core-verifier/` внутри этого каталога — world и диагностика.
- `act0-control-evidence-r1/d9706b15/` — финальный exact control, Linux, PC0,
  Reviewer и Verifier. Старый a7c711c4 Linux329/1failure/10cleanuperrors сохранён
  отдельно как rejected; его Windows PASS не был выдан за Linux PASS.

CI: runtime35097654348, Construction35100372324, control35103955408.
Их downloaded ZIP SHA256 соответственно:

```
afd5aeac91fd73e893fb569cc11a46a49c15673244c79c0a1dcd2e661160c1cd
cfae9802f9e13e2314763ca3ec926a8a1bc65057fb68774ef3e59ed11d50d63a
1a29620992c1d6cf280a68ed82075f34e1f79a465f598f781e62a7965a696fc4
```

PR Project Control35104510588 также FAIL ровно на live directional assertion
(65 tests/1failure). Свежий `CONTROL_PROJECT.ps1 -NoFetch` вернул exit2:
base YELLOW, directional RED. Assertion и clearance registry не изменялись.
Нельзя получить canonical baseline PASS из main6982 с известным journal defect,
нельзя назвать temporary approved-repair composition неизменённым main и нельзя
самостоятельно выдать ACCEPTED clearance, чтобы скрыть этот gate.

## Продолжение после решения

HUMAN gate основан на `AGENTS.md`: `HUMAN GATE: merge`, и parent Work Order
`human_approval_required_for: RUNTIME_FEATURE_MERGE`. Предыдущее «разрешаю»
закрыло только one-file scope HA и явно оставило main merge отдельным gate.
Новая запись — `HA-V0-MVP6-JOURNAL-BASELINE-MERGE-R1`.

После разрешённого merge: fetch exact main, проверить journal blob, повторить
default NX baseline/candidate probe без repair override, получить реальные PC0
и epoch audit, подготовить main-owned clearance через его schema и независимые
роли. Лишь после clearance продолжать MVP6 live five-process/physics и полный
feature acceptance. PR643 — альтернативный более широкий patch; оба не merge.

MVP6 IN_PROGRESS; parent IN_PROGRESS; whole MVP acceptance=false;
main runtime merge=false до решения. Указанные bounded PASS не означают MVP6 VERIFIED.
