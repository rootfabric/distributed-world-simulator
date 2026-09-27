Продолжай текущую реализацию MVP6. Не останавливай, не перезапускай и не переоткрывай уже выполненные части MVP1–MVP5.

Нужно усилить MVP6 дополнительным обязательным acceptance sub-gate для строительства, физически пересекающего границу двух authority/server regions.

## Цель

Доказать, что seamless world работает не только для player/carrying state, но и для крупной Construction, части которой принадлежат разным authority.

Добавь bounded strengthening gate:

`MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM`

Это усиление текущего `MVP_ITEM_CONSTRUCTION_PERSISTENCE_CONVERGENCE`, а не новый отдельный MVP и не новый параллельный Work Order.

## Обязательный сценарий

Создать реальную Construction размером ориентировочно 100 блоков/элементов так, чтобы seam между двумя authority проходил непосредственно через конструкцию.

Пример:

```text
AUTHORITY A                  AUTHORITY B
───────────────── SEAM ─────────────────

████████████████████████████████████████
████████████████████████████████████████
    ~50 элементов            ~50 элементов

          ONE CONSTRUCTION
```

Точное число может немного отличаться, если canonical Construction API имеет естественные ограничения, но тест должен быть достаточно крупным, чтобы это не было проверкой двух соседних блоков.

## Acceptance requirements

Проверить все следующие свойства.

### 1. Одна логическая Construction

Конструкция, пересекающая seam, не должна превращаться в две независимые локальные постройки.

Должна сохраняться canonical identity/relationship model, соответствующая существующей архитектуре проекта.

Не создавать второй Construction store, seam-specific shadow object или demo-only representation.

### 2. Два клиента видят одну и ту же конструкцию

Запустить настоящую live-композицию:

* client A;
* client B;
* authority A;
* authority B;
* gateway/существующий routing layer.

Оба клиента должны получить согласованное состояние всей cross-seam Construction.

Проверить не только количество элементов, но как минимум:

* canonical IDs;
* transforms/positions;
* membership;
* resource-derived state;
* revision/version либо существующий canonical equivalent.

### 3. Seam traversal внутри постройки

Игрок должен пройти по поверхности/полу/внутри построенной базы из области A в область B.

При переходе:

* reconnect = 0;
* respawn = 0;
* Construction не исчезает;
* Construction не создаётся заново визуально;
* нет duplicate elements;
* collision остаётся непрерывной;
* carrying state, если активен в сценарии, не теряется.

### 4. Collision через seam

Физическая/производная collision должна существовать по обе стороны seam.

Обязательно проверить участок непосредственно возле границы authority.

Не засчитывать тест, если визуальная геометрия есть, но collision на одной из сторон отсутствует или временно исчезает при handoff.

### 5. Modification непосредственно на seam

Выполнить минимум две реальные операции через canonical Construction API:

```text
ADD block/element near or across seam
REMOVE block/element near or across seam
```

Операция должна:

* пройти через canonical authority/routing;
* примениться ровно один раз;
* появиться у обоих клиентов;
* не создавать duplicate;
* не теряться при replay;
* не требовать клиенту знать конечный canonical result заранее.

Если существующий API поддерживает replay/idempotency key, обязательно проверить повтор доставки команды.

### 6. Связь между элементами разных authority

Если Construction model имеет graph/connectivity/support/attachment relationships, создать минимум одну связь вида:

```text
element owned/resolved by A
        │
        └──── canonical relation ──── element owned/resolved by B
```

После seam traversal и replication связь должна сохраниться.

Если у текущей Construction-модели нет подобного relationship primitive, явно зафиксировать это в evidence и не придумывать новый фундаментальный graph только ради теста.

### 7. Persistence roundtrip

Cross-seam Construction должна пройти существующий persistence payload / serialization / rehydration path.

После roundtrip проверить:

* количество элементов;
* canonical identities;
* transforms;
* cross-seam membership/ownership mapping;
* relationships;
* collision derivation;
* отсутствие duplicate/loss.

Полный restart authority здесь можно не добавлять, если он уже зарезервирован за MVP7.

MVP6 достаточно persistence roundtrip/rehydration в границах существующего predicate.

### 8. Negative controls

Добавить отрицательные проверки минимум для:

* duplicate construction mutation/replay;
* stale revision или canonical equivalent;
* unauthorized client attempting canonical mutation;
* invalid/non-owner authority mutation route;
* partial/one-sided construction state;
* duplicate element identity.

Негативные проверки должны доказывать, что тест нельзя пройти простой клиентской визуализацией или локальным mirror state.

## Архитектурные ограничения

Строго переиспользовать существующие owners:

* canonical Item Graph;
* Construction;
* NetworkedGameplayService;
* existing seam/authority routing;
* existing persistence codecs;
* existing collision derivation.

Запрещено:

* создавать второй Construction database/store;
* делать отдельную seam-only модель постройки;
* копировать половину базы на оба сервера как независимые truth copies;
* использовать test-only snapshots вместо live операций;
* напрямую вставлять Construction state в тест в обход canonical API;
* объявлять PASS только по UI;
* ослаблять MVP3–MVP5 regressions.

Клиенты передают intent. Canonical truth остаётся server/authority-owned.

## Если текущая архитектура не поддерживает cross-authority Construction

Не маскировать проблему тестовым адаптером.

Если выяснится, что существующий Construction owner принципиально предполагает одного region owner для всей конструкции и не способен корректно представить объект, пересекающий seam:

1. зафиксировать точный root cause;
2. указать конкретный owner/API/data model, который блокирует сценарий;
3. показать минимальный failing reproduction;
4. сформировать bounded scope amendment;
5. продолжить реализацию минимального правильного решения в рамках архитектуры, если оно не нарушает frozen ownership;
6. если требуется foundation change — поднять Human Attention вместо скрытого архитектурного расширения.

Такой root cause считается полезным результатом проверки, но сам predicate до исправления не закрывать.

## Evidence

В итоговом evidence должны быть отдельно видны как минимум:

```text
MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM
construction_elements ~= 100

authority_A_elements = ...
authority_B_elements = ...

client_A_visible_elements = ...
client_B_visible_elements = ...

logical_construction_identity = ...
duplicate_elements = 0

seam_traversal_reconnect = 0
seam_traversal_respawn = 0

cross_seam_collision = PASS

seam_add_exactly_once = PASS
seam_remove_exactly_once = PASS

cross_authority_relation = PASS / NOT_APPLICABLE_WITH_REASON

persistence_roundtrip = PASS

negative_controls = PASS
```

Также сохранить HEAD/TREE, platform/Godot identity и обычный exact evidence согласно текущему Harness.

## Regression / closure

После реализации:

1. focused test нового cross-authority Construction gate;
2. существующие MVP6 tests;
3. MVP5 regression;
4. MVP4 regression;
5. MVP3 seamless regression;
6. full world/core;
7. Project Control / PC0;
8. fresh independent Reviewer;
9. independent Verifier.

Не объявлять весь MVP6 закрытым только потому, что новый focused test зелёный.

MVP6 можно закрывать только когда исходные MVP6 requirements и новый:

`MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM`

проходят на одном допустимом frozen candidate согласно текущему Harness.

## Важно

Это изменение должно быть внесено как strengthening текущего MVP6 Work Order/acceptance, без создания второго active Work Order.

Не останавливай текущую реализацию ради отдельной фазы проектирования. Сначала интегрируй этот gate в текущий маршрут MVP6, затем реализуй и доведи его до той же степени evidence/review/verification, что и остальные обязательные MVP6 sub-gates.
