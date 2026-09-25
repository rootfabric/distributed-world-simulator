# FABRIC R5.2 / T12 — Ship Matryoshka

Статус: **T12-CLOSE ACCEPTANCE PASS / MERGE-READY**. Research-only; canonical owners — Construction/Matter.
База: T11 merge `70979aaab49bd6413c628f9e98532944a4bd7c74`, tree `467e2dee02bdb2f95b1c85efce32223ef81ed07a`.

## Design Brief / bounded work order

Цель: батарея T3 питает банк из независимых вложенных модулей. Каждый модуль
композирует существующие T10 Cannon, T11 Servo и отдельный T6 servo drive.
Ship → Bank → Turret → Cannon/Servo → существующие дочерние capsules.
Не менять T1–T11, production runtime, main-owned registry или authority contracts.
Новые файлы ограничены T12 research scripts/tests/docs/validation и отдельным workflow.

Выбран safeguarded scalar solve общей DC-шины, а не разряд батареи по заранее
заданной мощности. Все trial evaluations используют исходный caller-owned snapshot;
результат публикуется только после сходимости и проверки всех детей. Ошибка не
возвращает частичный next_state. Canonical mutation в этом исследовании не выполняется.

Вложенные capsules проверяются по внешнему trusted root checksum, каждому child
binding и существующим SourceRevision/Authority/Dependency contracts. Live records
для всего dependency tree поступают от caller; STALE child запрещает старую сборку.
Refinement receipt указывает только изменённый child и зависимые ancestors, а не
принудительное разворачивание sibling modules. Состояния несовместимой схемы не
проецируются автоматически; требуется специализированный canonical projector.

Насос оплачивается батареей через явно идеальный электрогидравлический адаптер
(eta=1). Потери обмотки servo и его T6 drive экспортируются как внешний тепловой
поток, не исчезают и не добавляются повторно в T10 cooling. Батарея сохраняет
собственный thermal state. Замкнутый баланс включает chemistry, stored heat,
servo kinetic energy, ambient/exported heat, optical output и внешнюю работу вала.

Не заявлены: корпус/полёт корабля, damage targets, новая оптическая физика,
CFD, реалистичный pump motor, battery BMS, production integration или новый owner.
Риск: HIGH composition/energy/persistence; независимые Reviewer/Verifier остаются
отдельными ролями. Implementer не объявляет собственную работу принятой.

## Реализованная иерархия

```text
Ship capsule
├─ Battery T3
└─ Bank capsule
   ├─ Turret #1 capsule
   ├─ Turret #2 capsule
   └─ Turret #3 capsule
      ├─ Cannon T10 → T6 + T9 + T8
      ├─ Servo T11 → T5 + T7
      └─ отдельный T6 servo drive
```

4275 source components представлены компактными дочерними программами. Полное
состояние содержит 31 scalar: 12 зарядов + температура батареи, затем по четыре
температуры и два состояния servo на каждый из трёх модулей. Проверен также банк
из двух модулей (25 scalars); поддерживаемый контракт ограничен четырьмя.

## Фактически выполненная проверка — 25 сентября 2026

PRODUCT_HEAD: `c4a7e706f04355585fa4101365a9db4915f84f6e`.
PRODUCT_TREE: `03d7448c908a8feb3bc8521c4761a1d64e957859`.

Точный Git bundle из source-carrier run `36124929437`, artifact `10859242569`,
развёрнут в новый checkout. HEAD/TREE совпали с опубликованными. После холодного
импорта запущены три отдельных процесса канонического Linux double Godot:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

sample 1 = PASS, 8386 assertions
sample 2 = PASS, 8386 assertions
sample 3 = PASS, 8386 assertions

2048 последовательных шага в каждом запуске
max shared-bus residual     = 5.9382e-10 J
max whole-energy residual   = 1.1417e-9 J
max secant/bisection error  = 1.3995e-8 A
source-leaf traversals      = 0
max solver evaluations     = 9 (лимит 48)
```

Deterministic hash всех трёх запусков:
`f29401ce869faab44996420cddb983ec97c85032e04fd6febe2d565731c46cbd`.
Исходные stdout и identity сохранены в
`validation/fabric-r5-2-t12-runtime-transcript.txt`; подробный evidence record —
`validation/fabric-r5-2-t12-ship-matryoshka-exact-evidence.v1.json`.

Повторно выполнены неизменённые тесты T3/T6/T8/T9/T10/T11: все PASS. Отдельные
четыре Python-теста collector и негативных логов: PASS. Полная world/core
регрессия здесь не заявляется. Новый source-workflow `36124902746` прошёл, но он
проверяет исходники и формирует архив — это не Godot runtime evidence.

## Что доказано по поведению

Выстрел увеличивает ток батареи и вызывает просадку общей шины; servo получает
энергию из той же батареи. Насос потребляет её даже без выстрела. При торможении
servo проверен обратный поток энергии: ток батареи около -4.206 A, заряд растёт.
Суммарная перегрузка трёх допустимых по отдельности нагрузок отвергается как
`T12_SHARED_POWER_LIMIT`. Пустая батарея, отсутствие запаса для рекуперации,
недостаточное напряжение, некорректные числа и устаревший child блокируют шаг.
Ни один отказ не возвращает частично изменённый `next_state`.

Повтор состояния после snapshot побитно совпадает. Для этого применяется
фиксированная раскладка binary64 в base64 JSON envelope, а не округляющий
decimal-JSON roundtrip. Внешний SHA-256 и capsule checksum обязательны.

При STALE emitter третьего модуля возвращается путь
`root/bank/unit03/cannon/emitter` и его ancestors. Проверка заменяет только этот
emitter и перекомпилирует зависимые Cannon/Module/Bank/Ship. Два соседних модуля и
батарея остаются byte-identical. Весь шаг старого Ship при этом запрещён: это
не обещание продолжать timestep повреждённой сборки. Совместимый новый Ship
получает старое состояние без потерь; изменение storage laws требует отдельного
canonical projector и не маскируется копированием чисел.

## Ограничения доказательства и стоимость

Альтернативная бисекция независимо решает уравнение общей шины, но использует
те же принятые child laws. Это не независимая реализация всей leaf physics.
Нулевые leaf traversals не означают нулевую работу: за основную последовательность
выполнено 13137 bus evaluations, 249603 вызова дочерних границ и 157644 обхода
компактных battery groups. Символическое сокращение операций не объявляется
измеренным ускорением. Время полного acceptance-процесса составило 25.66–26.20 s;
это наблюдение данного хоста, не лимит производительности.

При подготовке найден и исправлен String/StringName slot mismatch. Snapshot
переведён на binary64 после обнаруженной потери точности decimal roundtrip.
Проба общей перегрузки выбрана внутри индивидуального current envelope T6,
чтобы проверять именно общий предел батареи. Пороги тестов не ослаблялись.

## T12-CLOSE — закрытые acceptance gates

Fresh Reviewer на frozen head `5b317445ab5c43dd0d7370cf9c3d0e7f95969ef6` завершён:
`PASS / 0 blocking findings` (review id `5318515714`).

Fresh Independent Verifier использовал отдельную ветку
`verify/fabric-r5-2-t12-fresh-independent-verifier-r1`. Единственное отличие от
frozen subject — verifier workflow; product diff равен нулю. GitHub-hosted source
proof run `36144125759`, artifact `10869196607`, затем exact verifier bundle
был развёрнут отдельно и выполнен тремя процессами canonical Linux-double Godot:

```text
sample 1 = PASS, 8386 assertions
sample 2 = PASS, 8386 assertions
sample 3 = PASS, 8386 assertions

deterministic hash =
f29401ce869faab44996420cddb983ec97c85032e04fd6febe2d565731c46cbd

all verifier raw logs sha256 =
2a063f9ed36521998ac16d17319abcb6817c272a8687eb1a4f305affd2efd49f
```

### Project Control

Первоначальный RED оказался не дефектом T12. Live proposed-R3 compatibility test
брал registry/policy из `origin/main`, но clearance registry — из старого
research checkout. Так смешивались разные control-plane generations и уже
принятый main-owned V0→NX clearance не был виден.

Исправление вынесено в отдельный main-based PR #691: production directional-watch
`load_clearances()` теперь используется и test oracle. Ни policy, ни clearance,
ни health threshold не менялись. Project Control repair run `36144323392`
полностью SUCCESS и repair merged в main как
`cf217747e1d277eabc9c4b477299192f1cb8653d`.

Тот же test-only fix синхронизирован в research base, поэтому T12 PR сохраняет
строго T12-only diff. Собственный Project Control T12 run `36144903889`:

```text
architecture/ownership compatibility = PASS
H0.2 regression                     = PASS
V0 regression                       = PASS
generation safety                   = PASS
PC0 standard                        = PASS
PC0 directional                     = PASS
overall Project Control             = SUCCESS
```

T12 product/runtime после exact verification не менялся. Финальный closure-коммит
меняет только эту документацию и durable evidence. **T12-CLOSE = PASS / MERGE-READY.**
