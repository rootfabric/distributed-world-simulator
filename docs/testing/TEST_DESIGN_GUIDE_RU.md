# Правила проектирования новых тестов

Этот документ задаёт единый стиль будущих тестов PlanetSimulator. Он не требует
немедленной переработки существующих файлов.

## 1. Именование

Файл:

```text
test_<module_or_contract>.gd
```

Название теста или локального шага должно описывать поведение:

```text
world switch removes commands owned by previous runtime
```

а не внутреннее имя функции:

```text
test_unregister_owner
```

если контракт шире конкретного метода.

## 2. Один файл — один контракт

Допустимо несколько сценариев одного aggregate/component. Не следует помещать в
один тестовый файл unrelated проверки terrain, UI и persistence только ради
уменьшения количества процессов.

## 3. Структура сценария

Каждый сценарий должен явно разделять:

```text
Arrange — подготовка исходного состояния
Act     — одно проверяемое действие
Assert  — состояние, события и отсутствие побочных мутаций
Cleanup — освобождение ресурсов
```

При проверке отказа Assert включает сравнение snapshot до и после операции.

## 4. Что проверять при success

Минимально:

- результат сообщает success;
- целевое состояние изменилось;
- revision изменилась ожидаемо;
- обязательные signals отправлены один раз;
- связанные registries согласованы;
- serialized snapshot валиден;
- повторная синхронизация не создаёт дубликаты.

## 5. Что проверять при failure

Недостаточно проверить только `error_code`. Проверять:

- relation/transform/quantity не изменились;
- revision не увеличилась;
- membership/socket/registry не изменились;
- success signals не были отправлены;
- временные nodes/files не остались;
- следующая корректная операция всё ещё работает.

## 6. Числа с плавающей точкой

Не использовать точное равенство для рассчитанных Vector/Transform/physics
values. Использовать допуск, соответствующий смыслу данных:

- координатные round-trip — малый абсолютный/относительный допуск;
- physics — диапазон и направление;
- quaternion/basis — проверка нормализации и эквивалентности ориентации;
- большие планетарные координаты — учитывать scale значения.

Допуск должен быть объяснён константой:

```text
POSITION_EPSILON_M
ROTATION_EPSILON_RAD
VELOCITY_EPSILON_MPS
```

## 7. Physics tests

Обязательные правила:

- использовать настоящие collision shapes;
- ждать physics frames;
- не вызывать `_physics_process()` вручную как единственную проверку;
- не сравнивать точную траекторию после большого числа тиков;
- ограничивать максимальное число кадров;
- при timeout печатать transform, velocity, sleeping/contact state;
- очищать physics nodes и ждать deferred cleanup.

Для проверки падения достаточно доказать:

- `y` или radial distance меняется в ожидаемом направлении;
- velocity направлена по gravity;
- body не проходит сквозь floor;
- результат достигнут за разумное число physics frames.

## 8. Input tests

- отправлять реальные `InputEvent`/action events;
- после press дать движку обработать кадр;
- явно отправлять release;
- после теста очищать все удерживаемые actions;
- не запускать параллельно тесты, использующие global Input;
- hardware input пользователя не должен влиять на CI.

Если позже подключается GUT InputSender, `release_all()` и `clear()` обязательны
между тестами.

## 9. Async и background tests

Каждая асинхронная проверка должна иметь:

- timeout;
- условие завершения;
- cancellation в cleanup;
- ожидание idle после cancellation;
- snapshot request/revision/state;
- проверку, что stale result не был применён.

Не использовать только фиксированный `wait_seconds()` без проверки состояния.

## 10. Signals

Проверять:

- signal отправлен;
- отправлен ровно один раз;
- аргументы правильные;
- failure path не отправляет success signal;
- повторная no-op операция не создаёт duplicate signal;
- listener отключается при cleanup, если это требуется контрактом.

## 11. Persistence

Для каждой schema нужны четыре группы:

1. current round-trip;
2. migration из поддерживаемых старых форматов;
3. unsupported future/old version;
4. corruption и atomicity.

Corruption matrix включает:

- пустой файл;
- invalid JSON;
- неверный root type;
- отсутствующее обязательное поле;
- duplicate ID;
- невалидный SpatialRef;
- оборванную последнюю journal line;
- несовпадающий universe/instance/revision.

Загрузка должна быть транзакционной: valid in-memory state не меняется до полной
валидации нового snapshot.

## 12. Procedural/property tests

- использовать локальный RNG;
- явно задавать seed;
- тестировать много входов, включая poles/seams/boundaries;
- при failure печатать seed и минимальный контекст;
- проверять invariants, а не конкретный декоративный результат;
- для golden data использовать только стабильные канонические значения.

## 13. Fixtures

Fixtures должны быть минимальными и собираться из реальных production-компонентов,
если mock не нужен для конкретного отказа.

Предлагаемые fixtures:

```text
minimal item domain
physical floor and wall
minimal world runtime
fake terrain result source
temporary state store
fixed simulation clock
deterministic RNG
mock repository only for explicit repository failure
```

Fixture не должна скрывать проверяемое поведение. Например, raycast test не
должен заранее назначать `current_target`.

## 14. Diagnostic snapshot

При failure engine-теста выводить:

- test ID;
- текущий world/runtime;
- process/physics frame count;
- simulation time;
- component state/revision;
- active/pending request;
- node path и instance validity;
- последние ошибки;
- seed, если использовалась случайность.

Snapshot должен быть JSON-safe, чтобы runner мог добавить его в общий отчёт.

## 15. Cleanup checklist

После каждого engine test:

```text
[ ] Все созданные nodes освобождены
[ ] Deferred queue получила кадр
[ ] Input actions отпущены
[ ] Mouse mode восстановлен
[ ] Time scale и pause восстановлены
[ ] Временные ProjectSettings восстановлены
[ ] Temp files/directories удалены
[ ] Commands/tests владельца удалены
[ ] Worker cancellation завершена
[ ] Custom monitors удалены
[ ] Orphan node count вернулся к baseline
```

## 16. Flaky tests

Тест не следует просто перезапускать до PASS и скрывать проблему. При
нестабильности сначала определить причину:

- неправильный тип ожидаемого кадра;
- отсутствие timeout/condition;
- протёкший Input;
- физическое exact equality;
- случайный seed;
- worker race;
- cleanup предыдущего теста;
- зависимость от GPU или wall-clock.

Retry допустим только как диагностический сигнал для отдельного nightly job, а
не как способ сделать обязательный regression зелёным.

## 17. Размещение по наборам

| Тип теста | Набор |
|---|---|
| чистая логика, schema, config | fast |
| SceneTree component | engine |
| physics/input/raycast | engine |
| полный мир/save/reload | world regression |
| тысячи операций/длинный runtime | stress |
| GPU screenshots | visual |
| экспорт и запуск build | export smoke |

## 18. Review checklist для нового теста

Перед включением в regression reviewer проверяет:

1. Проверяет ли тест публичный контракт?
2. Может ли он дать ложный PASS?
3. Есть ли timeout у каждого await?
4. Проверяется ли rollback при отказе?
5. Изолировано ли global state?
6. Воспроизводима ли случайность?
7. Не зависит ли тест от точной physics trajectory?
8. Выводит ли он полезную диагностику?
9. Освобождает ли ресурсы при FAIL?
10. Находится ли он в правильном наборе по времени выполнения?
