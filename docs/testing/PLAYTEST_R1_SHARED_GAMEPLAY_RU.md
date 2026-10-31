# Playtest R1: два игрока изменяют общий мир

Основание: поручение владельца выполнить автоматический сценарий взаимодействия,
в том числе без графики. База e6afdaab324e3bdb6450d3e71fb65115f034439c,
продолжение принятого Playtest R1 с ремонтами reconnect и визуальной проверкой.

## Ограниченный Work Order

Добавить только repository-owned headless driver и Python orchestrator в tools,
проверки runner и этот документ. Runtime authority, wire и persistence не менять.
Два отдельных процесса используют публичный M3 client runtime и реальные ENet
команды; dedicated server запускается через штатный product entrypoint SAFE60.
Mailbox управляет тестовыми клиентами, не пишет состояние сервера или реплик.

Сценарий: A добывает руду, кладёт в общий ящик; B забирает и строит фундамент.
Оба клиента должны увидеть расход ресурса, смену владельца предмета и постройку.
Затем A и B пересекают границу туда/обратно, B переподключается; сервер штатно
завершается и поднимается новым процессом с тем же persistence root. Проверить
сохранность предметов/постройки и возможность продолжить добычу/строительство.
Повтор mining operation_id до reconnect должен не дублировать выход.

Критерии: реальные изменившиеся количества и непустая construction checksum,
согласие двух клиентских реплик, стабильные entity IDs при seam/reconnect,
новый PID сервера, восстановление изменённого мира, строгий exit code/report.
Сохранять команды, длительности, состояния этапов, HEAD/TREE и hashes входов.
Проверки выполняются также с Python -O. Ошибка или timeout означает FAIL.

Риск MEDIUM для тестовой композиции без изменения authority; независимый разбор
кода и evidence обязателен. При ремонте runtime переоценить риск и роли.
Этапы фиксируются отдельными коммитами и non-force push; merge не разрешён.
Сырые результаты только C:/distributed-world-simulator/artifacts/shared-gameplay-20261031.
Localhost seam не доказывает multi-host N3–N5, штатный restart не доказывает crash
durability. Историческая SCHEMA_INVALID MVP8 не переименовывается в acceptance.

## Ремонт по первому исполнению

Прогон f462b5663: resource.mine не передавал peer/session/ownership в существующий
M6 ACK gate, получен PERSISTENCE_FATAL DURABLE_GATE_IDENTITY_REQUIRED. Разрешённый
ремонт ограничен передачей уже проверенной identity в _persist_command_result;
контракт durable-before-ACK не ослабляется. Риск повышен до HIGH: отдельные
независимые Reviewer и Verifier, live повтор и негативные проверки runner.
Повтор 95d1874c6 обнаружил второй пропуск того же пути: успешный mining ACK не
освобождал escrow, следующая команда получала DURABLE_GATE_BACKPRESSURE. Добавлены
те же preflight/enqueue-completion hooks, которые уже применяет ITEM handler.

Обнаружен также явный защитный запрет строительства с persistence:
M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED. Обход этого запрета и создание нового
cross-domain persistence owner не входят в ремонт. Сценарий обязан сохранить FAIL
полного цикла, но после такого конкретного отказа продолжить независимые проверки
передачи/границы/reconnect/restart с добытой рудой. В таком прогоне строительство
и продолжение строительства обозначаются BLOCKED, никогда PASS.

## Запуск и фактический результат

Из корня этого checkout на Windows, с установленным double Godot:

```powershell
python -O tools/live2/shared_gameplay_check.py
```

Для воспроизведения конкретного исходного состояния добавьте
`--expected-head <полный SHA>`. Runner требует clean tracked checkout, создаёт
отдельный каталог прогона внутри workspace artifacts, запускает только свои
процессы и сохраняет команды, снимки обоих клиентов, времена этапов, логи и hashes.
Флаг `--output` принимает путь внутри C:/distributed-world-simulator/artifacts.
Время штатной остановки первого сервера задаётся `--restart-after-seconds` (110
по умолчанию); общий runtime включает ожидание этой остановки.

Итог и точное происхождение: [результат 31 октября](PLAYTEST_R1_SHARED_GAMEPLAY_RESULT_20261031_RU.md).
Полный сценарий сейчас возвращает **exit 1 / FAIL**, потому что строительство с
persistence ещё не подключено. Пройденные сетевые действия выделены в отчёте;
наличие этого отказа не скрывает иной timeout или ошибку.
