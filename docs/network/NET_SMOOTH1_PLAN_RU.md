# NET-SMOOTH1 — плавность CHAR2 и воспроизводимая диагностика

## Субъект и границы

- База продукта: `f861de654b5cc6aa281f150259bf55d4a42f042b`.
- Базовое дерево: `3bf642cf75775cc041d9f2027be491c84b731515`.
- Ветка repair: `repair/net-smooth1-char2-r1`; родитель — CHAR2, не main.
- Наблюдавшийся main: `5460354b06f62cb48caa1c1e4f8156129ac5f9d4`.
- Основание: пользовательская Windows GUI-проверка и
  `char2-network-diagnostics-r1:docs/reports/CHAR2-WINDOWS-ACCEPTANCE-2026-10-10.md`.
- Risk: HIGH (persistence). Это branch-local repair/work order, не main-owned
  активация нового checkpoint и не объявление ACCEPTED.
- Независимые Reviewer, Verifier и Windows GUI/soak ещё обязательны. Merge запрещён
  до их результатов и явного решения владельца проекта.

## Design brief / Repair map

Симптом: плавная локальная картинка перемежается сетевыми откатами и паузами;
сервер после длительной сессии теряет частоту тиков. Главный подтверждённый путь:
`m3_dedicated_server_runtime_p2._process -> _maybe_persist_movement_checkpoint
-> _persist_checkpoint -> coordinator -> repository.save_atomic`.
NX3 с bounded catch-up отбрасывает излишек времени после длинной блокировки.
Дополнительный воспроизводимый дефект: NX5 на границе EXTRAPOLATE/HOLD возвращает
последнюю авторитетную позицию вместо достигнутой ограниченной экстраполяцией.

Владельцы неизменны: NX3 — authoritative movement, NX4 — prediction, NX5 —
presentation, M6 — recovery/replay, USER1 — quiescent seam persistence,
CHAR2 — visual provider. Никакого второго physical/network/persistence owner.

`sequence` глобален для peer, принимается отдельно по stream. Разность номеров
внутри stream не равна packet loss: её создают другие каналы и coalescing.
Сохраняем wire contract; исправляем наблюдаемость, а не маскируем пакеты.

Полный ledger нельзя обрезать по размеру/TTL: старый повтор операции не должен
повторно списывать материал. Outbox уже имеет предел 2048; это не доказательство
ограниченности service/ownership replay. R1 не объявляет ledger-compaction готовой.

Выбранный первый slice: исправить NX5; отделить тяжёлую сборку/проверку/запись
периодического checkpoint от игрового цикла; сохранить sync durability barrier
для команд и остановки; добавить bounded tracing и настоящий двухклиентский стенд.
Альтернативы «интервал 10 секунд», unlimited catch-up, увеличение interpolation
buffer и удаление replay отвергнуты как маскировка или ослабление контракта.

## План исполнения и критерии выхода

| Шаг | Работа | Проверка / условие выхода |
|---|---|---|
| 0 | Exact baseline, происхождение исходников, RED-repro NX5 | HEAD/TREE + отрицательный тест до исправления |
| 1 | Непрерывный bounded HOLD в NX5, честные gap counters | focused + NX2/NX5, reset/teleport не изменены |
| 2 | Один background writer для periodic movement checkpoint | изоляция снимка, bounded queue, progression, command barrier, shutdown/failure |
| 3 | Телеметрия реальных кадров/тиков, snapshot/reconcile/visual | отдельные монотонные часы процессов; нет записи файла в кадре; dropped telemetry != PASS |
| 4 | Оркестратор: server + A/B, LOCAL движение, повороты, reconnect | отдельные user roots/порты, readiness, реальные Quaternius для GUI, machine verdict |
| 5 | Exact Windows GUI baseline/fixed и длительный прогон | >3.5 ч, fresh join/reconnect; frame/tick percentiles, все аномалии в evidence |
| 6 | По traces: ограниченная подготовка snapshot и исторического replay | отдельный HIGH-risk repair; повторы после compaction/restart, без потери ACKed операций |
| 7 | По traces: неблокирующий durable command path | упорядоченный commit/ACK; fault injection до/после commit, crash recovery |
| 8 | NETWORK jitter/loss/spike, seam, rollover, construction load | явная матрица покрытия; отдельные критерии LOCAL/WAN |
| 9 | Fresh review, independent Windows verification, интеграция | exact HEAD/TREE, no self-accept, main/CHAR2 не двигать автоматически |

R1 не заменяет шаги 5–9. Асинхронная периодическая запись не доказывает отсутствие
пауз при durable-командах. Захват экспортов на main thread измеряется отдельно;
его стоимость всё ещё может зависеть от размера мира и replay.

## Инварианты writer

1. Только один writer на repository, без конкурирующих generations.
2. Передача отдельных Dictionary-снимков; worker не обращается к живой service,
   SceneTree, authority adapter или outbox.
3. Только завершённый успешный commit продвигает persisted generation.
4. Изменения во время записи остаются dirty; нельзя сбрасывать их на completion.
5. Пока writer занят, новый periodic checkpoint не копируется и не ставится
   в бесконечную очередь: dirty state объединяет запросы.
6. Sync command/recovery/shutdown сначала закрывают предыдущую async generation.
   Ошибка не превращается в успешный ACK.
7. Recovery JSON format/checksums, atomic replace, предыдущая generation сохранены.
8. USER1 quiescence проверяется на захвате. Никакой конкурентной mutation мира.

## Телеметрия и достоверность

Захватывать wall interval каждого кадра/серверного вызова, duration стадий server,
server_tick, snapshot arrival, reconciliation duration/error/replayed ticks,
визуальные planar position/yaw и режим NX5. Каждый процесс имеет собственный
монотонный clock; не вычитать `Time.get_ticks_usec` разных процессов. Для связи
использовать server_tick, sequence и session. Точный one-way latency без clock
synchronization не заявлять.

Writer логов отделён от игрового цикла, очередь и объём файлов ограничены.
Нет START/END, пропуски event sequence, dropped записи, ранний выход процесса,
отсутствие движения/подключений — INCONCLUSIVE/FAIL, никогда пустой PASS.
Стенд проверяется искусственными плохими traces и реальным отрицательным NX5-repro.

Начальные цели для прогретого LOCAL/60 FPS: p99 кадра <=25 ms, p99.9 <=50 ms,
нет пауз >100 ms, нет регулярных checkpoint пауз >50 ms, server tick rate >=59 Hz,
без роста dropped simulation time. Это инженерные стартовые бюджеты, не результат.
Cold start, grace/reconnect и измеряемые фазы маркируются отдельно. Нельзя снижать
пороги после прогона, чтобы получить зелёный verdict.

## Evidence / публикация

Временные логи — только `artifacts/net-smooth1/`. Фиксировать HEAD/TREE, version и
SHA256 Godot, команды, длительность, конфигурацию, sha256 отчётов, exit codes,
реальный GPU/renderer/RDP. Headless PASS не является GUI/performance PASS.

В текущем executor normal GitHub transport недоступен (DNS route failure),
подключённый GitHub предоставляет read actions, но не write/dispatch actions.
Точный source artifact `11628742010`, run `37957655037` восстановлен локально;
базовые tree и commit проверяются побайтово. Ветка передаётся Git-bundle с exact
parent SHA, не новым synthetic root. Remote push выполняет Windows-агент обычным
Git; это транспортный перенос, не запрос merge. Не объявлять remote publication
до успешного push и проверки remote SHA.
