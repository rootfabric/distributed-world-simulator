# Каноническое принятие V0 P7 — подготовленный проект (не принято)

Статус: **DRAFT — ОЖИДАЕТ ЧЕЛОВЕЧЕСКОГО РЕШЕНИЯ**.

Этот branch (`control/v0-p7-canonical-acceptance-r1`) подготовлен внутри
активной P7 checkpoint mission после исчерпания всех автоматических gates.
Ни одна запись здесь не является принятием; canonical acceptance появляется
только после human gate на `main`.

## Что уже доказано (автоматически, на frozen head)

```text
FINAL HEAD:            dca12cec28107042f07dcfe1b9d4d8ccd82fb8eb
FINAL TREE:            bdb1bc0398a2b76b7d34dc3b9d9bb892dd158366
runtime-tested head:   a52faf8c44434818775225be3f71c30a0fd86ef3
runtime-tested tree:   4ff3adbaeecdd64a68bb3c1f11817aa72918231f
base main:             c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f (чистый предок)

FULL_WORLD_CORE_REGRESSION_PASS: local (330 стадий) + CI exact-validation (world) success
P7_29_LEAF_2032_ASSERTION_PASS:  local + CI exact-validation (p7) success
PC0 standard: YELLOW non-RED; directional: 0 critical hits; overlaps: []
Independent Reviewer: PASS (R1 b06499b7 + R2 exact-head dca12cec)
Independent Verifier: PASS (R2 exact-head dca12cec, с machine re-execution)
Post-build critique:  NO_MATERIAL_REFACTOR_REQUIRED
```

## Что требуется от человека (два решения)

1. **RUNTIME MERGE** — пометить PR #580 готовым и смержить
   (`repair/v0-p7-eg1-world-core-r1` @ `dca12cec` → `main`).
   Ожидаемое дерево merged main: `bdb1bc03…` (чистый потомок c14c37c;
   tree-эквивалентность проверяется сразу после merge).
2. **CANONICAL ACCEPTANCE** — зафиксировать owner-директиву о принятии
   checkpoint `V0_P7_BOUNDED_TERRAIN_MUTATION` (комментарий/аппрув на PR
   #580 или на acceptance PR из этого branch), после чего заполнить
   финальные поля записи
   `config/control/harness/acceptance/V0-P7-R1-CHECKPOINT-ACCEPTED-001.v1.json`
   (merge commit SHA, human authorization provenance, accepted_at_utc),
   смержить её в `main` и прогнать
   `CONTROL_DEVELOPMENT.ps1 -Drive` / `-CloseMission`.

## После acceptance (внутри той же mission, без MVP)

Контроллер обязан показать:

```text
checkpoint_acceptance: ACCEPTED
mission_complete: true
next product route:   ACTIVATE_MVP_FROM_ACCEPTED_P7
```

Открытие MVP (`V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`)
требует отдельной main-owned активации и свежего Work Order и в этой
mission НЕ выполняется.

## Отслеживание stale-проверки

Если `origin/main` сдвинулся после `c14c37c` до merge — сначала
`git merge-base` / PC0 dependency audit и при необходимости rebase без
force-push + повторная валидация затронутых gates. Runtime commit после
review делает review stale; этот branch не содержит runtime изменений.
