# FABRIC — аудит конструктора сложности

Дата: 6 сентября 2026. Вердикт: **REPLAN_REQUIRED / ISSUES_REPRODUCED**.

Исследованный source HEAD: `43f60d2cd8e295227af983ed2c0d82f558ba1ec0`, ветка `feature/fabric-complex4-vis1-playable-physical-lab-r1`.
Прочитанный main: `ce782cfff4293b4b6d88bdb237e7bdf99cf9688c`, registry generation 81.

Это корректирующий research audit, а не новое независимое принятие, production merge или main-owned activation. Исторические closure/evidence сохраняются. Runtime в этом изменении не исправляется.

## Вывод

Направление правильное: канонический мир отделён от представлений, редукция автоматизирована, инвалидация и восстановление проверяются. Однако последние заголовки CLOSED слишком широко описывают результат. Текущий интегрированный путь демонстрирует прежде всего пассивную стационарную сеть, обработку ревизий и сценарный наблюдатель; он пока не доказывает общий конструктор физически сложных динамических машин.

Формулировки прежних отчётов следует сузить: «конкретный лабораторный контракт прошёл» не означает «вся заявленная capability полностью интегрирована». Совпадение FULL/BAKE подтверждает редукцию заданной модели, но не физическую правильность модели.

## Что сохранить

Сохранить B0.1 exact boundary reduction, B0.4/B0.5 исследовательские механизмы, B0.6 safety/policy separation, BRIDGE-3 lifecycle, COMPLEX3 streaming experiment, канонические Construction/Matter contracts и VIS1 как наблюдатель. Переписывать всё с нуля не требуется.

В исходной идеологии `FABRIC0_READ_FIRST_RU.md` уже присутствуют геометрия, локальные законы, stored state, conservation и hybrid time. Новые generic wrappers должны соединить эти возможности в одном опыте, а не подменять их новым статическим графом.

## Проверенный путь исполнения

```text
VIS1 session
  -> COMPLEX4 runtime
  -> BRIDGE-4 runtime
  -> FABRIC1 generalized runtime
  -> B0.7 generic compiler
  -> B0.1 exact boundary reducer

COMPLEX4 functional projection
  -> FABRIC0 conservation network
```

На этом пути FABRIC1 имеет только `BAKED` и `FULL` для стационарной линейной сети. B0.6 controller, B0.4 ROM, B0.5 hybrid и BRIDGE-3 local unbake не становятся частью этого опыта от одного наличия в Git ancestry. Смена представления не равна смене физического гибридного режима.

## Дважды выполненные диагностические опыты

Новый probe: `tests/research/fabric1/fabric_complexity_audit_probe.gd`.
Два процесса canonical Godot завершили сбор наблюдений с exit 0, fatal markers 0. Это **успешный сбор свидетельств дефектов**, не зелёный acceptance.

| Воздействие | Наблюдение |
|---|---|
| Геометрические расстояния увеличены в 10 раз | Canonical checksum изменился, физический graph hash не изменился |
| Материал steel заменён на rubber при той же массе | Внешний binding изменился, физический graph hash не изменился |
| Прочность всех связей увеличена вдвое | Boundary flow увеличился ровно вдвое |
| Валидная каноническая конструкция из 6 деталей | Отклонена: `BRIDGE4_REDUCTION_BOUNDARY_OUT_OF_SCOPE` |
| Внешний execution owner / epoch | `server/audit-authority` / 7 |
| Владелец/epoch внутреннего bake context | `server/b0-7-unseen` / 1 |
| Readonly Matter внешнего binding | Внутренний компилятор заменяет synthetic mutable source |
| FULL -> capsule -> restore -> корректная failure mutation | Restore успешен, mutation запрещена: `FABRIC1_OLD_BAKE_MISSING` |
| Та же mutation без restart | Успешна — контроль воспроизведения |
| Старый event удалён и заменён посторонним при добавлении нового | `Protocol.validate_successor` ошибочно принимает историю |

Полные журналы и manifest: `validation/fabric_complexity_audit/`.

### Метод и ограничение воспроизведения

Использован exact transitive source slice: 39 production dependencies и новый probe. Пять новых runtime blobs сверены с live GitHub; остальные 34 совпали с Git-объектами архивной базы `949b089ed35750abf9e237f063af21490291d187`. GitHub compare от этой базы до исследованного HEAD не меняет соответствующие dependency paths.

Это НЕ чистый checkout всего current HEAD. Полный fresh import, вся regression chain и отдельный независимый agent-verdict здесь не заявляются.

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.
SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

## Findings

### F01 — P1: восстановленный FULL не продолжает lifecycle

В `fabric1_generalized_runtime_v1.gd`, `restore` для FULL очищает `_compiled`. Следующая `apply_canonical_failure` требует старый BAKE_READY и возвращает `FABRIC1_OLD_BAKE_MISSING`. Тот же successor без restart принимается. Исправлять нужно привязку и переходы lifecycle, а не принуждать систему запекаться перед каждым событием. Проверить также два последовательных отказа без промежуточного rebake.

### F02 — P1: проверка истории событий не сохраняет прежний ledger

В `unseen_machine_challenge_protocol_v1.gd` проверяются наличие нового события и увеличение длины, но не равенство `successor_events = previous_events union {new_event}`. Probe заменяет `event/audit-old` на `event/audit-forged`, и validator принимает результат. Это дефект проверяющего контракта; факт обхода защищённого production server этим опытом не заявляется.

### F03 — P1 integration gate: canonical binding теряется внутри компиляции

BRIDGE-4 создаёт реальные frontier/authority, но в FABRIC1 передаёт только graph spec. `unseen_machine_generic_compiler_v1.gd` заново создаёт synthetic Construction/Matter, фиксированного owner и epoch. `live_context(artifact)` копирует текущую authority из самого artifact. Внешняя проверка checksum полезна, но не заменяет сквозную передачу доверенного live context. Restore BRIDGE-4 также получает owner/epoch из capsule вместо независимо переданного текущего authoritative context. Нужны отрицательные тесты смены owner/epoch при неизменной геометрии.

### F04 — физические величины подменены параметрами surrogate graph

В `bridge4_canonical_world_adapter_v1.gd` записано `conductance = bond.strength_n`. Прочность в N не является жёсткостью N/m или электрической проводимостью S. Геометрия и material laws не участвуют в этом graph assembly. Нельзя выдавать измеренный generic flow за доказанную физику балки. Это допустимый тестовый surrogate только с явной маркировкой.

Внешние ориентиры: Modelica Standard Library, `Mechanics.Translational.Components.Spring` (N/m), `Electrical.Analog.Basic.Conductor` (S, i=vG). Это примеры размерностно осмысленных примитивов, не предложение заменить solver DWS библиотекой Modelica.

### F05 — guard ошибочно сближен с доказательством разрушения

Refinement при 0.8 от capacity консервативно допустим. Но 90 N при strength 100 N не доказывает overload failure без отдельного материального критерия. VIS1 передаёт constant 90 N, а `Fixture.successor_with_broken_support` заранее выбирает разрушение. Store mutation реальна; решение о разрушении не выведено из расчёта напряжений. Разделить early refinement, физический failure criterion и авторизованную canonical command.

### F06 — COMPLEX4 пока не универсальная многокомпонентная физическая сеть

Projection требует ровно один source и один load; каждый POWER_LINK напрямую связывает их. Доступность пути зависит от явно заданных `support_bond_ids`. Идеальная резервная схема 36W -> 36W -> 0W корректна для выбранных допущений, но не доказывает сопротивление проводов, обратное влияние нагрузки на механику, накопление энергии или общий multidomain solve.

### F07 — unseen означает новые данные одного семейства

Alpha/beta/gamma создаются одним backbone/chord generator после freeze. Это полезная проверка неизменности compiler после новых данных. Это не независимый holdout неизвестного семейства машин. Кроме того, ограничение минимум 100 hidden nodes переносит benchmark prerequisite в generic eligibility. Малый объект должен допускать FULL, даже когда BAKE невыгоден.

### F08 — local physical work не равно local total work

COMPLEX3 задаёт `REGION_SIZE=20`, заранее выбирает break index и целевой регион. Metadata scanned в кампании растёт до 199980 на 100k; aggregate_span проходит диапазоны дважды. Это не опровержение опыта, но 100k -> 20 FULL нельзя превращать в утверждение O(1) полной обработки произвольного события. Нужны неизвестный заранее impact, изменяемый размер острова, учёт scans/hash/rebuild и случай реального глобального распространения.

### F09 — work ratio не измеренное CPU acceleration

В `exact_boundary_reducer_v1.gd` units заданы формулой `2*n*n + 4*n*b + 2*b*b` против `2*b*b`. Отношение равно `((n+b)/b)^2`. Числа 1225x и 3136x — стоимость по этой модели. Wall observations в B0.7 существуют, но FULL reference заново факторизует dense matrix; нужен также cached-LU/sparse baseline и end-to-end стоимость validation, hashing, compile, invalidation и restart. Размер списка algebraic unknowns не следует называть числом dynamic states.

### F10 — VIS1 полезен как storyboard, не как физический sandbox

Сцена рисует mesh, меняет цвета и размер опоры и выполняет keyboard proof steps. Session использует test fixture; visual positions вычисляются из индекса. Restart создаёт новый runtime в том же процессе при сохранённом authoritative snapshot. Это не доказательство cold restart полного canonical мира или падения обломков. Сам наблюдатель нужно сохранить и подключить к физическим snapshots/events.

### F11 — сила evidence и принятия должна соответствовать claim

В просмотренных шести latest JSON manifests B0.7/FABRIC1/SYNC1/BRIDGE4/COMPLEX4/VIS1 отсутствует полный набор ссылок на raw runtime logs с их SHA-256. Есть полезные summaries, hashes и tested subjects; этого недостаточно для самостоятельной проверки происхождения каждого старого PASS. Это не доказательство, что старые тесты не выполнялись.

Новый fixture и fresh process не равны независимому Reviewer. Hash freeze доказывает тождество bytes, не правильность архитектуры. Текущий main требует отдельный verdict и запрещает reuse без digest/provenance. В этом аудите независимый внешний verdict не приписывается.

## Решение по плану

Не продолжать немедленно расширение до четырёх доменов. Сначала исправить F01/F02/F03, затем отделить material/geometry/constitutive law от topology, после чего собрать один динамический причинный опыт на существующих ядрах. Подробные критерии и опыты находятся в `FABRIC_COMPLEXITY_CORRECTION_PLAN_RU.md`.

Исторические CLOSED сохраняются как история выбранных fixture contracts. Для broader capability следует считать открытыми physical validity, unified integration, adversarial robustness и independent acceptance. Family-local findings не превращаются автоматически в MVP blockers; main-owned routing и human gates не меняются этим документом.
