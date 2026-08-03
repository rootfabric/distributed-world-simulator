# Checkpoint v17.4.0 — MW4 Matter Mutations fix3

## Статус

```text
checkpoint: v17.4.0-simulation-mw4-matter-mutations
delivery:   fix3
build_id:   mw4-matter-mutations-fix3
base:       v17.3.0-simulation-mw3-local-meshing / fix2 + MW4 initial + fix1 + fix2
branch:     feature/mw4-matter-mutations
status:     CANDIDATE FOR METADATA REVIEW
```

## Результат independent review fix2

Функциональный focused-профиль полностью прошёл:

```text
MW4 focused: 187 assertions PASS, 10.843 s
MW3:         7519 assertions PASS
MW2:         7470 assertions PASS
MW1:         3685 assertions PASS
MW0:         2011 assertions PASS
A3:          PASS
M6:          10/10 PASS
git diff --check: PASS
```

SHA-256 проверенного fix2:

```text
00872874C709A65EEE7E6FD11D062F0BBC81FCE5E3F5E55C8C245277D4135EC2
```

## Причина fix3

В metadata fix2 было ошибочно указано:

```text
prior recorded value: 103
```

Число `100` относилось к аварийно завершившемуся частичному прогону fix1.
Добавление трёх negative assertions не определяет полную topology успешного
focused-профиля. Реальный завершившийся запуск содержит:

```text
187 assertions
```

## Исправление

- `PROJECT_MANIFEST.txt`: прежнее значение `103` заменено на `187 assertions`;
- checkpoint fix2 исправлен на фактическую topology `187/187 PASS`;
- validation fix2 исправлен на `expected_focused_assertions = 187`;
- добавлены отдельные checkpoint и validation fix3;
- production GDScript, сцены, конфигурация и тестовая логика не изменялись.

## Граница поставки

Fix3 является metadata-only delivery. Он не изменяет:

- транзакционную семантику MW4;
- narrow-band excavation;
- revision fences;
- mass/energy/capacity accounting;
- rollback;
- focused assertions;
- runtime Moon и world catalog;
- MW0–MW3 canonical contracts.

## Критерии приёмки

1. Во всех актуальных manifest/checkpoint/validation-артефактах указано `187 assertions`.
2. Устаревшие topology-утверждения с прежним значением отсутствуют.
3. Список файлов fix3 соответствует архиву.
4. JSON validation и `git diff --check` проходят.
5. Код и тестовая логика отсутствуют в changed-file set.
