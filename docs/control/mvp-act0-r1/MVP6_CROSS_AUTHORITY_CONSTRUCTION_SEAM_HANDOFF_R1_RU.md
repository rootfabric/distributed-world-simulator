# MVP6 cross-authority Construction — точка продолжения R1

Дата фиксации: 2026-09-17.

Этот документ сохраняет в Git незавершённый этап усиления текущего MVP6. Он не
является evidence PASS, не закрывает predicate и не создаёт новый Work Order.

## Канонический контекст

- Project Epoch: `E2026-09-09-V0-MVP-R1`.
- Work Order: `V0-MVP-R1-WO-001`, состояние `IN_PROGRESS`.
- Checkpoint: `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`.
- Ветка: `feature/v0-mvp-playable-seamless-planet-r1`.
- Последний содержательный parent перед этим handoff:
  `438e23e9dd70faa253dafbfde55bee2737448063`, tree
  `8023f9bb81a2bace634224a1c0a2ac2905d2128c`.
- Upstream на момент фиксации:
  `origin/feature/v0-mvp-playable-seamless-planet-r1` =
  `f9eae93faa8075a1d16f90fd6918e5ca366c1872`. Следовательно, локальный
  strengthening commit ещё не был опубликован.

После checkout продолжение начинать с текущего tip этой ветки, а точный SHA этого
handoff получить через `git log -1 --format=%H`.

## Что сделано

В коммите `438e23e9` новый обязательный predicate
`MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM` включён в существующий
`MVP_ITEM_CONSTRUCTION_PERSISTENCE_CONVERGENCE` и тот же Work Order. Второй
active Work Order не создавался.

Добавлены и синхронизированы:

- predicate в `config/control/harness/checkpoint-catalog.v1.json`;
- `required_predicates`, `required_outputs`, scope, desired behavior и validation
  plan в существующем `V0-MVP-R1-WO-001.v1.json`;
- machine-readable контракт
  `MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM_R1.json` со статусом `PENDING`;
- полная русская спецификация
  `MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM_REQUIREMENTS_RU.md`.

При проверке после изменения Work Order schema прошла, порядок ранее обязательных
predicates и прежние allowed/forbidden paths сохранены. Runtime-код этим коммитом
не менялся.

Выполнен read-only owner/API audit существующей Construction-архитектуры. Его
важный итог: foundation для требуемой модели уже существует. C17 задаёт один
canonical `ConstructAggregate` writer и read-only spatial sections на соседних
servers. Поэтому правильная интерпретация `authority_A_elements` и
`authority_B_elements` — пространственное разрешение частей одной конструкции,
а не два независимых canonical writer или два store.

Также подтверждено, что у модели есть canonical bond между part IDs. В focused
сценарии обязательна хотя бы одна связь, чьи концы пространственно разрешаются в
разные authority; вариант `NOT_APPLICABLE` здесь недопустим.

## Что обнаружено, но ещё не реализовано

1. Текущий P4 MVP factory строит фиксированный outpost из шести частей. Для gate
   нужен server-owned build plan примерно на 100 item-backed connected parts,
   пересекающих реальный seam.
2. `construction_authority_server_endpoint.gd::submit()` вызывает gateway без
   trusted actor context. P4 real-resource build требует
   `logical_player_id`; существующий M3 bridge передаёт его правильно. Нужна
   production C17/M3 связка, сохраняющая authenticated actor context и route
   fencing.
3. В текущем factory `GeometryProcess` и `DamageProcess` не настроены. Поэтому
   canonical REMOVE через `APPLY_DAMAGE` ожидаемо заканчивается
   `CONSTRUCTION_DAMAGE_PROCESS_NOT_CONFIGURED`. Нужна настройка существующего C9
   transaction path, а не прямое редактирование snapshot.
4. `earth_construction_presentation.gd` создаёт производные C22/C24 collision
   proxies, но существующий MVP6 test проверяет только их количество. Это не
   доказывает фактический контакт игрока с поверхностью около seam.
5. `player_movement_service.gd` симулирует плоскую землю `y = 0` и не опрашивает
   Construction collision. Для acceptance требуется подключить существующую
   производную collision к canonical server movement либо другой существующий
   owner-preserving physics route. Простого raycast-проба без влияния на реальное
   движение игрока недостаточно.
6. Canonical persistence и C17 distributed persistence существуют раздельно;
   focused scenario должен roundtrip-нуть оба применимых payload, заново вывести
   A/B membership из canonical transforms и заново получить collision.

Предварительные minimal RED reproductions были только сформулированы, но ещё не
созданы и не запущены:

- `C17_P4_TRUSTED_ACTOR_ROUTE`: тот же valid BUILD intent проходит через M3 с
  authenticated actor и должен отказать через текущий C17 endpoint из-за
  отсутствующего `logical_player_id`;
- `P4_SEAM_REMOVE`: после canonical build granted `APPLY_DAMAGE` для
  не-корневого leaf должен показать текущий
  `CONSTRUCTION_DAMAGE_PROCESS_NOT_CONFIGURED`.

## Что не успели

- runtime implementation нового gate;
- focused automated test и five-process composition: client A, client B,
  authority A, authority B, gateway;
- конструкция примерно из 100 частей и разделение spatial membership около
  50/50;
- настоящие ADD и REMOVE у seam, exactly-once replay и stale/unauthorized/
  wrong-owner/partial-state/duplicate-identity controls;
- непрерывный traversal по физической поверхности с `reconnect = 0`,
  `respawn = 0`, без исчезновения, recreation и duplicates;
- проверка двух client views по IDs, transforms, membership, resource-derived
  state и revision;
- persistence/rehydration roundtrip нового сценария;
- focused PASS, прежние MVP6 tests, MVP5/MVP4/MVP3 regressions, full world/core,
  PC0, fresh Reviewer и independent Verifier на одном frozen candidate.

Ни один новый runtime test после `438e23e9` не запускался. Предыдущий
Construction223 проверяет шесть частей, presentation counts и backend fixture;
он не считается evidence нового predicate.

## Следующий минимальный маршрут

1. Сначала добавить исполняемые RED reproductions двух найденных integration
   gaps через production APIs и сохранить точные error codes.
2. Оформить bounded amendment того же `V0-MVP-R1-WO-001`, если для исправления
   нужны owner-native пути вне текущего `allowed_paths`. Новый Work Order не
   создавать.
3. Собрать server-planned примерно 100-part Construction через существующие
   Item Graph, P4 build plan/material allocator и Construction adapter.
4. Подключить существующие C17 registry/epoch routing/read-only sections и M3
   authentication к реальным process boundaries, сохранив одного canonical
   writer.
5. Настроить существующий C9 damage transaction для REMOVE и доказать ADD/REMOVE
   + replay через canonical commands.
6. Подключить реальную derived collision к canonical traversal и проверить A,
   seam epsilon и B физическими контактами в течение handoff.
7. Выполнить roundtrip canonical Construction + C17 state, затем все negative
   controls и полный regression/closure порядок из требований.

Запрещено решать эти пробелы второй Construction database, seam-only truth,
двумя writable половинами, прямой вставкой final snapshot или UI/count-only
утверждениями. Если окажется, что нужен настоящий per-part multi-writer вместо
описанной C17 single-writer section model, это foundation change и требует Human
Attention.

## Независимые и внешние состояния

Read-only audit был сохранён вне Git в
`C:/distributed-world-simulator/artifacts/mvp6-cross-authority-construction/reviewer-owner-audit/`.
Его verdict — `INSUFFICIENT_EVIDENCE`, scope — архитектурный аудит, runtime tests
не исполнялись. Существенные выводы перенесены в этот документ, поэтому другая
сессия не зависит от наличия `artifacts/`.

Отдельный ранее открытый merge gate остаётся без изменений: draft PR #646 для
journal repair указывает на `d9706b157e84c653a753cc54243ce6651d53319c`.
Запрос на strengthening и этот handoff не являются разрешением merge. До merge
продолжает действовать открытый
`HA-V0-MVP6-JOURNAL-BASELINE-MERGE-R1`; это не разрешает подменить новый gate
старым evidence.

## Среда воспроизведения

- Windows PowerShell.
- Godot:
  `C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe`.
- Версия: `4.7.1.stable.double.custom_build.a13da4feb`.
- Перед тестами в свежем worktree выполнить одиночный `--import`; не запускать
  параллельные editor imports из-за конфликта MCP port 9080.
- Использовать `PYTHONUTF8=1`, `PYTHONDONTWRITEBYTECODE=1`,
  `BREAKPOINT_RUNTIME_DISABLED=1` и
  `PLANET_SIMULATOR_INVENTORY_PROFILE=planet_default`.

Коммиты продолжения сохранять с trailers:

```text
Project-Epoch: E2026-09-09-V0-MVP-R1
Work-Order: V0-MVP-R1-WO-001
Checkpoint: V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE
Work-State: IN_PROGRESS
```
