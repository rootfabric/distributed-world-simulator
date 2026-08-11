# H0.0 — Restart-Safe Harness Scaffold

**Project Epoch:** `E2026-08-11-H0-0-R1`  
**Work Order:** `H0-0-WO-001`  
**Base:** `790fd79f8055fefa19cf9d7263441fc9f4326ebd`  
**Branch:** `control/h0-closed-loop-development`  
**Risk:** `MEDIUM`  
**Target:** `H0_0_SCAFFOLD_READY`

## Решение Director

H0.0 реализует только исполняемый control scaffold поверх уже канонических контрактов `H0-2026-08-11-R1` и `H0-REVIEW-2026-08-11-R1`.

```text
CONTROL_DEVELOPMENT.ps1
  ├─ Status
  ├─ Plan
  └─ Resume
        ↓
canonical contract loader
event reducer / state builder
epoch validator
checkpoint planner
review/evidence/human-attention state
```

До `H0_0_SCAFFOLD_READY` нельзя создавать автономные runtime-ветки C22/NX и нельзя менять gameplay/runtime paths.

## Design Brief

### Проблема

`main` уже хранит цели, checkpoints, risk/review/evidence policies и schemas, но после потери сессии агент всё ещё вынужден вручную интерпретировать их. Единой исполняемой команды восстановления нет.

### Выбранный дизайн

Тонкий PowerShell entrypoint вызывает небольшие Python modules. Derived state всегда перестраивается из Git и canonical JSON. `artifacts/harness/**` остаётся удаляемым кешем.

### Почему не монолитный PowerShell

Reducer, schema validation, epoch comparison и planner требуют независимых negative/replay tests. Отдельные Python modules дают более узкие ownership boundaries и позволяют проверять их без запуска runtime.

### Non-goals

- `-Execute` и autonomous dispatch;
- C22/NX runtime implementation;
- изменение canonical harness schemas/policies;
- architecture promotion или ownership transfer;
- gameplay/runtime files.

### Главные риски

- неправильный порядок/переходы событий;
- ложная свежесть epoch после движения `main`;
- скрытая зависимость Resume от artifacts или истории чата;
- потеря Reviewer/Evidence Map/Human Attention state;
- обход pilot override и преждевременный выбор C22.

### Проверка

Нужны schema/semantic negative tests, reducer replay, moved-main fixtures, dry-run C22 block, clean-checkout `Resume`, post-build critique, Evidence Map, независимые Reviewer и Verifier, затем PC0.

## Stop rules

При необходимости изменить canonical contract, runtime path, ownership или расширить риск до `HIGH/CRITICAL` работа останавливается для Director replan. Любой `FIX_REQUIRED` сначала требует Repair Map.
