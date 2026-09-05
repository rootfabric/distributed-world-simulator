# FABRIC BRIDGE-3 — FULL / BAKE / LOCAL UNBAKE / FULL

## Статус и границы

IMPLEMENTATION IN PROGRESS. Исследовательская линия, не production acceptance.
База B0.6: b34f4cc24616f26dfcc6dcbdada2d664b478b64f.
Main policy: fa2b6024481ea5a796ec9c7b0e2f9885f1a82c91.
Ветка: research/fabric-bridge3-full-bake-unbake-full-r1.
Риск HIGH: lifecycle, recovery и смена физического исполнителя.

## Design brief / bounded work order

Цель: реальный round-trip состояния через существующие structural aggregation,
refinement guard, reconstruction и topology rebake contracts. Construction/Matter
остаются единственными владельцами identity, topology, damage и source revisions.
Новый код управляет derived execution slots; не создаёт solver или canonical source.

A: binding, единственный physical writer, prepare/commit и receipt.
B: FULL -> STRUCTURAL_BAKE после B0.6 safety/hysteresis; detailed state освобождается.
C: certified guard -> bounded local FULL без реконструкции остальных деталей.
D: continuity позы/скорости/импульса/энергии и boundary anchors; stale writer запрещён.
E: внешняя canonical mutation -> immediate invalidation -> settle -> fresh rebake.
F: restart из canonical inputs; disposable capsule; идемпотентность и crash boundaries.
G: FULL-reference parity, 500/1000/2000 canonical parts, fresh-process replay и regressions.

## Предварительно найденная причина глобальной работы

structural_local_unbake_runtime_v1.execute сначала реконструирует весь parent.
BRIDGE-3 вместо этого индексирует неизменяемые mapping constants при подготовке,
материализует только target parts и переносит COM/twist residual aggregates
аналитическим rigid transform. Metadata compilation и полный внешний snapshot
считаются отдельно от горячего physical reconstruction; их O(N) не скрывается.
Closed predecessor APIs и evidence не переписываются.

## Проверяемый scope

Сначала используются уже существующие COMPLEX0 structural source и COMPLEX2
numerical full/compiled reference. Нет обещания произвольного fracture solver,
произвольной contact геометрии или 100k полноценных numerical machines.
Полная эталонная реконструкция допускается в oracle, но не в local transition.
Cost не разрешает unsafe mode; visual LOD/FPS не участвуют в решениях.

Валидация: attached Godot 4.7.1.stable.double.custom_build.a13da4feb,
SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.
Реальные logs, exit codes, negative cases, two fresh replay и predecessor regression.
Не объявлять CLOSED по одному summary или queued CI. Не приписывать независимый
agent review собственным тестам; exact runtime closure и formal acceptance различаются.

## Git discipline и следующая линия

Каждый завершённый этап публикуется прямым Git/GitHub API, затем ref проверяется.
Actions не используется для переноса исходников. Shell clone: DNS failure,
исходный checkout восстановлен из уже приложенных архивов с exact Git TREE.
Без force-push, без merge main, без изменения закрытых B0.6/predecessor evidence.
COMPLEX3 (5k -> 20k -> 100k) открыть отдельной линией только после BRIDGE-3 closure.
