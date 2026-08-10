# T1A.6 — Acceptance reopened by PC0

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a6-runtime-presentation-multiplayer-binding`  
**Control plane:** `PC0-2026-08-10-R1`  
**Статус:** `REOPENED / FIX1 VALIDATION PENDING`

Предыдущий Windows focused gate и полный world regression действительно прошли, однако после сверки с main-owned PC0 обнаружен ранее зарегистрированный blocker:

```text
T1A5_TRANSACTIONAL_RUNTIME_EFFECTS_FIX1_REQUIRED_BEFORE_T1A6_ACCEPTANCE
```

Поэтому прежняя попытка отметить T1A.6 как `ACCEPTED` считается superseded этим checkpoint и актуальным machine-readable validation:

```text
validation/t1a6-runtime-presentation-multiplayer-validation.json
```

Причина blocker и реализованный FIX1 подробно описаны в:

```text
docs/checkpoints/2026-08-10_T1A5_TRANSACTIONAL_RUNTIME_EFFECTS_FIX1_RU.md
```

После runtime FIX1 старые focused/full-regression evidence остаются исторически корректными, но больше не являются fresh evidence для нового runtime HEAD.

Для повторного acceptance обязательны:

```text
RUN_T1A5_TRANSACTIONAL_RUNTIME_EFFECTS_TESTS.ps1       PASS
RUN_T1A6_RUNTIME_PRESENTATION_MULTIPLAYER_TESTS.ps1   PASS
RUN_WORLD_REGRESSION_TESTS.ps1                       PASS
```

До этого:

```text
SOURCE_ACCEPTED       false
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  false
PRODUCTION_READY      false
```

Переход в `T1A.7 Runtime Recovery / Interest / Scale` запрещён PC0 stop rule до закрытия перечисленных gate.
