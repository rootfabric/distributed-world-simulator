# EVO ARCH2 A7 — интеграция принятого Observatory в current main, R1

Дата: 2026-09-13. Work Order: `EVO-ARCH2-A7-MAIN-INTEGRATION-20260913-R1`. Risk: HIGH.

## Цель

Research A7 уже принят на `acceptance/eco-evo-arch2-a7-r1` (`8eccf6304078bec3a3ccaa5860c5aab6ee311209`, tree `24e876b7377cb3e1e521f08ff9766331fe4e895a`). Это не означает, что длинная research lineage должна быть слита в `main`.

Текущий canonical `main` на открытии интеграции: `7dfc68ab5a1e90254a1b7039807f275b5da04eef`. Эта ветка создана прямо от него. Используется правило Project Control:

```text
accepted evidence + current main
        -> fresh convergence frontier
        -> minimal capability transfer
        -> integrated-head validation/review
        -> human merge gate
```

## Что переносится

Main не содержит `scripts/research/ecology/v2`. A7 зависит от A6/A5/A4/A0–A3 контрактов этого namespace. Поэтому минимальная самодостаточная единица переноса — **целиком принятый `scripts/research/ecology/v2/**` subtree**, а не выборочная копия нескольких A7 файлов с хрупкими preload-зависимостями.

Кроме него переносятся только:

- A7 protocol JSON;
- A7 scene и два presentation scripts с UID;
- принятый `tests/research/ecology/v2` subtree для exact проверок A0–A7;
- A5 repair oracles из `validation/ecology/evo_arch2_a5`, если main не содержит этот namespace;
- новые integration-only verifier/evidence файлы.

Все переносимые accepted bytes должны совпадать с `8eccf630...`. Research commits не становятся родителями integration commit: история остаётся current-main based.

## Жёсткий no-overwrite контракт

До переноса проверено: current main не содержит `scripts/research/ecology/v2`, `tests/research/ecology/v2` и `validation/ecology/evo_arch2_a5`. Любое неожиданное пересечение с уже существующим main path — FAIL до commit.

Запрещено менять existing main files вне Work Order/control docs, особенно production ecology, simulation, network, architecture/control и `project.godot`. Интеграция не переименовывает research code в production authority и не подключает его к server/world tick автоматически.

## Проверка integrated HEAD

Research A7 PASS переносится только как provenance, но не заменяет новый integrated-head verifier. На новом HEAD обязательны:

1. exact current-main ancestry и scope/no-overwrite fence;
2. cold Godot import точной double-сборкой;
3. A0–A7 v2 regression на перенесённых tests;
4. A5 repair oracles;
5. A7 mandatory graphical capture и UI handlers;
6. A7/A6 separate-process restart;
7. проверка сохранения current-main runtime — минимум Project Control/Harness regression и текущие main-owned smoke/regression gates, которые не требуют добавления research authority;
8. final HEAD/TREE clean seal;
9. fresh independent review именно integrated HEAD;
10. Project Control + directional audit.

Нельзя использовать старый `34701231448` как integrated-head PASS. Он остаётся доказательством принятого transfer source.

## Merge / authority

Integration PR должен иметь base `main`, head `integration/eco-evo-arch2-a7-main-r1` и оставаться DRAFT до завершения exact verifier/review/audit. Merge — отдельный human gate. Эта работа не создаёт main-owned `ECO_ARCH2_A7_OBSERVATORY` execution и не заявляет `MISSION_COMPLETE`, пока main/control policy этого не объявили.

После merge отдельным шагом потребуется post-merge exact Project Control; A8 не стартует автоматически.
