# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P9: DEVELOPMENT_BIAS canonical extension proposal (RU)

Статус: **STOP-условие по брифу §18, оформленное как формальное предложение canonical extension.**
Дата: P9 (A10.5). Владелец контекста: workbench P1–P10 (`scripts/ecology/workbench/`).

## 1. Постановка проблемы

OrganizationProfile (P9) разделяет три класса правил (§18–19 брифа):

1. **VISUAL_ONLY** — реализован: применяется только к `visual_profile` generic-реализатора (палитра, детализация), каноническое состояние не затрагивает.
2. **DEVELOPMENT_BIAS** — «мягкая» организация онтогенеза (перевзвешивание допустимых переходов развития). **Не может быть реализован в workbench**: требуемый канонический hook отсутствует.
3. **BIOLOGICAL/WORLD CONSTRAINT** — канонический закон (сохранение вещества, стоимость ресурсов, физика мира, ownership), по определению вне OrganizationProfile; в коде workbench не представлен никак (константа-заглушка не нужна).

В соответствии с §18 брифа полигональный (workbench) движок мутаций **не создаётся**. Профили класса DEVELOPMENT_BIAS (`SOFT`, `EARTH_LIKE`, `NMS_LIKE`) возвращают `status: "BLOCKED_CANONICAL_EXTENSION_REQUIRED"` (см. `organization_profile_v1.gd → apply_development_bias`), каноническое состояние не меняется в принципе (функция чистая).

## 2. Почему hook отсутствует (факты из P2/P9)

- `genome_mutation_v1.mutate(parent, seed, operator)` (A3): оператор — элемент **закрытого** канонического списка `OPERATORS`; параметра bias нет; добавить «polygon-only» оператор = расширение канона, запрещённое брифом.
- `resource_lifecycle_runtime_v1.materialize_propagule` (A5): parent-transfer witness привязывает hash генома потомка к геному родителя. Мутированный геном через witness **не проходит** — контроллер (P2) документированно откатывается на точный геном родителя (`PARENT_TRANSFER_WITNESS_FALLBACK`).
- `development_program_v1` (A1/A2): правила ограничены каноническим словарём действий; workbench не имеет права создавать новые семантики.

## 3. Предлагаемое каноническое расширение (A3 + A5)

### 3.1. A3: точка входа bias в mutate

```
genome_mutation_v1.mutate(parent, seed, operator, bias = null)
  bias := {
    "schema": "dws.ecology.genome-mutation-bias.v1",
    "name": String,            # именованный, версиированный bias
    "version": int,
    "operator_weights": { operator -> weight >= 0 }   # только УЖЕ разрешённые операторы
    "parameter_weights": { param -> weight >= 0 }     # только существующие параметры
  }
```

Инварианты (сохранение канона):
- bias **только перевзвешивает** уже допустимые операторы/переходы (`OPERATORS` остаётся закрытым списком; неизвестный оператор в `operator_weights` — ошибка валидации);
- без bias поведение побитово идентично текущему (обратная совместимость: все существующие тесты A3/A5 проходят без изменений);
- детерминизм: `mutate(parent, seed, operator, bias)` — чистая функция от аргументов;
- bias не добавляет новых семантик, правил, ролей или действий — только вероятностный вес.

### 3.2. A5: ослабление witness для mut-вариантов

```
materialize_propagule(propagule, child_blueprint, parent_state, mutation_receipt = null)
  mutation_receipt := {
    "schema": "dws.ecology.mutation-receipt.v1",
    "parent_genome_hash": String,
    "operator": String,              # из закрытого OPERATORS
    "seed": int,
    "event_hash": String             # из genome_mutation_v1 event
  }
```

Witness принимает геном потомка, если `Genome.biological_hash(child) == parent_genome_hash` (как сейчас) **или** предъявлен валидный mutation_receipt, доказуемо полученный из родительского генома через `mutate(..., bias)` (проверка: replay `mutate(parent, seed, operator, bias)` воспроизводит genome — work не превышает существующих бюджетов A5).

### 3.3. Канальный канал распространения

Мутации с bias проходят в потомков только через репродуктивный путь A5 (propagule). Через manifest founders — без изменений (P7 правило: новые геномы входят только founders-ом).

## 4. Канонические тесты (план приёмки расширения)

1. **A3 backward-compat:** все существующие тесты `mutate` без bias — побитовая идентичность результатов до/после расширения.
2. **A3 bias closure:** bias с оператором вне `OPERATORS` → ошибка `MUTATION_BIAS_OPERATOR`; веса < 0 → `MUTATION_BIAS_WEIGHT`.
3. **A3 bias determinism:** `mutate(p, seed, op, bias)` дважды → идентичный event/genome hash; разные seed → (статистически проверяемо) различное распределение выбранных операторов.
4. **A3 bias no-new-semantics:** для всех bias из фикстур множество достижимых геномов ⊆ множества, достижимого перебором разрешённых операторов без bias.
5. **A5 witness admission:** mut-вариант с валидным receipt проходит witness; с битым/чужим receipt → отказ (fail-closed); replay budget превышен → отказ.
6. **A5 witness fallback preserved:** текущее поведение контроллера (fallback на геном родителя) сохраняется, когда receipt не предъявлен.
7. **Conservation:** расширенные прогоны с bias проходят существующие балансы A6 (сохранение вещества/энергии не зависит от bias).
8. **Non-causality of presentation (§14/§27):** 16-тик прогоны с VISUAL_ONLY-профилями и без них → идентичный `canonical_state_hash` (уже покрыто `test_organization_profile.gd`).

## 5. Что реализовано в P9 без расширения

- `organization_profile_v1.gd`: preset/validate/visual_profile/resolve_weights; `apply_development_bias` → `BLOCKED_CANONICAL_EXTENSION_REQUIRED` + `required_hook` (текст настоящего предложения).
- FREE = режим приёмки по умолчанию (без organization constraint, стандартная палитра); CUSTOM = VISUAL_ONLY с переопределяемыми визуальными параметрами.
- Метрики/P10 фиксируют mutation-события с `applied: false, reason: PARENT_TRANSFER_WITNESS_FALLBACK` как read-only свидетельство отклонённых попыток.

До принятия расширения A3/A5 любые DEVELOPMENT_BIAS-профили остаются заблокированными; это задокументированное STOP-условие, а не дефект.
