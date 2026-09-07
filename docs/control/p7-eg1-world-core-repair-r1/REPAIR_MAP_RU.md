# P7 / EG1 — ENet listener bandwidth compatibility repair R1

Статус: **IMPLEMENTED CANDIDATE; NOT ACCEPTED**.
Work Order: `V0-P7-EG1-ENET-BANDWIDTH-R1`; единственный Implementer продолжает
`repair/v0-p7-eg1-world-core-r1` от `79b02b8bf137ea652ff94700833631f810db299d`.
Канонический product baseline: `c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f`,
TREE `04679a6e67fc86ec156d4341140fd5b0225d6085`.
Это не новый feature dispatch, не активация MVP и не самостоятельная приёмка P7.

## Причина и владелец

В Godot `a13da4feb8d8aefc283c3763d33a2f170a18d541`,
`modules/enet/enet_multiplayer_peer.cpp:65–81`, `create_server()` передаёт
`p_max_channels + SYSCH_MAX` в пятый аргумент `ENetConnection::create_host_bound`,
то есть incoming bandwidth. `p_in_bandwidth` не используется. DWS просит шесть
каналов и unlimited bandwidth по умолчанию, но listener объявляет 8 bytes/s.
Источник: https://github.com/godotengine/godot/blob/a13da4feb8d8aefc283c3763d33a2f170a18d541/modules/enet/enet_multiplayer_peer.cpp

`thirdparty/enet/host.c::enet_host_bandwidth_throttle()` после первого 1000 ms
окна ограничивает peer packetThrottleLimit, минимум 1 из шкалы 32. Поэтому OK
на enqueue не доказывает отправку ненадёжного пакета. Пересчёт bandwidth receiver-ом
может позже убрать ограничение, что объясняет зависимость результата от polling.
Источник: https://github.com/godotengine/godot/blob/a13da4feb8d8aefc283c3763d33a2f170a18d541/thirdparty/enet/host.c

Владелец адаптации DWS — `EnetMultiPeerTransportPort.start_server()`, а не
EG1 worker и не gateway forwarding. `NetworkEndpoint` не предлагает bandwidth
опций. После успешного `create_server`, до readiness/handshake, выполняется
`_peer.host.bandwidth_limit(0, 0)`. Исправление совместимо и с движком, где
исходный вызов уже исправлен: повторно задаёт тот же исходный контракт.

## Причинный эксперимент

Приложенный Linux double binary реально выполнен и проверен SHA-256:
`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
`native-causal-evidence.tar.xz` содержит полный исходник, журналы, JSON и manifest;
внешний digest и member digests находятся в `native-evidence-manifest.v1.json`.

Одинаковое расписание во всех трёх вариантах: real ENet handshake; три reliable
ITEM-like пакета; только client polling 1200 ms; один INPUT-like unreliable
пакет; client servicing до возобновления receiver; чтение результата.

| Вариант | Опытов | Limit до INPUT | Reliable получены | INPUT получен |
| --- | ---: | ---: | ---: | ---: |
| Исходный listener | 3 | 1/32 | 3 в каждом | 0/3 |
| bandwidth_limit(0, 0) до handshake | 3 | 32/32 | 3 в каждом | 3/3 |
| Только отключение RTT deceleration | 3 | 1/32 | 3 в каждом | 0/3 |

Во всех опытах INPUT enqueue вернул OK. Исправленный listener сохраняет штатный
RTT deceleration=2. Два предварительных недискриминирующих опыта сохранены как
отрицательные результаты диагностики, не скрыты и не считаются PASS продукта.
Пакеты здесь не являются игровыми командами: это доказательство механизма на
бинарнике, не доказательство исходного EG1, P7 или полной world/core-регрессии.

## Изменения и coverage

Production diff: **одна исполняемая строка**, без изменения client path, encoding,
каналов INPUT=1/ITEM=3, transfer modes, authority, deduplication или RTT policy.
Исходный adapter blob `55e547376b19e842df3c9d42c78e5c9dbe11e4ba` восстановлен
побайтно; удаление четырёх добавленных строк возвращает точный исходник.

В `test_eg1_gateway_processes.gd` добавлены три проверки после исходного `_cleanup()`.
Удаление добавочного блока возвращает исходный blob
`80fc6db44ccd1c1a683292b51e142113ebe0d703`. Все прежние assertions, worker commands,
тайм-ауты и их порядок неизменны; измерительный probe не запускается одновременно
с исходным EG1. Проверяются оба реальных ненадёжных transfer modes на listener,
созданном production adapter-ом. Внутренний ENet host используется только для
black-box проверки конфигурации, не для имитации ProtocolFrame или gameplay.

Смежные поверхности: T1 multi-peer contracts/processes, NX2 traffic separation,
все существующие EG network tests, полный неизменённый world/core runner.
Каноническая 29-stage P7.7+P7.5 train выполняется заново на кандидате: прежние
2032 проверки на c14 не распространяются автоматически на новый общий transport.

## Исполнение и доказательства

`p7-eg1-world-core-repair.yml` запускается только owner-ом в этом репозитории.
Self-hosted runner отдаёт только заранее разрешённый engine binary с digest;
репозиторий/`.git` через artifacts не передаётся. Полный runtime исполняется на
отдельных GitHub-hosted Ubuntu checkout-ах: предыдущее server evidence показало
отсутствие Xvfb/sudo на self-hosted. Это разрешённый executor fallback, не skip.

Validator проверяет scope и побайтную неизменность старого EG1; запускает один и
тот же probe на чистом c14 (обязательный конкретный negative result limit=1) и
кандидате (limit=32); выполняет фиксированные 5/5 EG1 попыток, siblings, unchanged
full-world и отдельную неизменённую P7 train. Повтора «до первого PASS» нет.
PowerShell Get-Item:Force — только Linux provider adaptation из предыдущего
валидатора; основной runner не редактируется. Raw logs, commands, exits, child
reports, HEAD/TREE и clean before/after сохраняются даже при failure. Manifest
связывает SHA256 файлов с workflow/run/job/runner и фактическим subject.

Локально выполнены native A/B, проверка измерительного helper в обоих режимах,
проверка Python/YAML syntax и 29-stage accounting. **Production exact CI,
полная регрессия, свежая independent Reviewer/Verifier и PC0 ещё должны быть
подтверждены реальными результатами.** Workflow success не является их verdict.

## Post-build critique

`NO_MATERIAL_REFACTOR_REQUIRED` для production patch: применяется существующий
API в существующем owner; новых truth/manager/protocol/config surfaces нет.
Диагностическое scheduling ограничено отдельным тестом. Нормальная потеря UDP
не объявляется невозможной, throttling не отключается. Инфраструктура проверки
входит в review scope; проверяются не только зелёные Actions badges.

После machine validation — frozen exact Reviewer и отдельный Verifier;
после их реальных PASS — Director proposal и человеческое решение о merge/acceptance.
Не создавать canonical ACCEPTED, не менять registry/scheduler и не начинать MVP
при незакрытом обязательном predicate. Новая несвязанная ошибка требует отдельного
bounded Work Order; исторические FAIL и evidence c14 не переписываются.
