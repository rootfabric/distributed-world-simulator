# ECO ARCH2 A7 — MAIN INTEGRATION REPAIR R4

## Subject

Интеграционный кандидат PR #617 переносит формально принятый A7 research closure в ветку, созданную от current `main`. Repair R4 закрывает два разных класса дефектов, обнаруженных после R3.

## R4-1 — Harness environment

Hosted static-preflight запускал Harness с `jsonschema 4.10.3`, тогда как canonical Harness fail-closed требует `jsonschema 4.25.1`. Массовые ошибки `PINNED_DEPENDENCY_VERSION_REQUIRED:jsonschema=4.10.3` являются дефектом validation environment, а не ECO runtime. R4 validation использует job-local Python с exact `jsonschema==4.25.1` (или подтверждённый already-exact interpreter) и проверяет версию до запуска Harness.

## R4-2 — P7 scene immutability guard

`tests/harness/test_v0_mvp_act0.py` исторически запрещал любой diff всего каталога `scenes` после P7 base. Это не различало изменение P7-owned scene bytes и добавление независимой принятой research-lab сцены.

Repair не снимает P7 guard. Вместо blanket `scenes` equality вводится более точный fail-closed контракт:

- P7 execution/acceptance остаются byte-immutable;
- `scripts/runtime`, `scripts/network`, `scripts/simulation`, `project.godot` остаются без изменений;
- в `scenes` разрешён ровно один post-P7 delta: `A scenes/labs/ecology/arch2_a7_observatory.tscn`;
- любое изменение, удаление, rename старой scene или любое второе добавление снова делает Harness красным.

## R4-3 — accepted transfer provenance

Final verifier обязан:

1. fetch durable `acceptance/eco-evo-arch2-a7-r1`;
2. подтвердить exact accepted HEAD и exact tree как для ref, так и непосредственно для accepted commit;
3. перечислить фактический diff от integration base;
4. разрешить единственную main-owned modification `tests/harness/test_v0_mvp_act0.py` с exact repaired blob;
5. для каждого остальных transfer-addition проверить `HEAD:path == accepted-A7:path`;
6. отдельно разрешить только точный набор integration-local metadata files;
7. выполнить полный `python -m unittest discover -s tests/harness -p 'test_*.py' -v` без skip-on-import-error логики.

## Truth boundary

Repair R4 не меняет ECO research semantics, A7 protocol, production ecology, simulation, networking, Project Control или `project.godot`. Он исправляет интеграционный guard и validation provenance. Merge в `main` остаётся отдельным human gate.
