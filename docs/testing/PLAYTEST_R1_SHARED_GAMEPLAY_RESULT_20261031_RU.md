# Два игрока: результат испытания Playtest R1, 31 октября 2026

**Сетевое взаимодействие и ремонт добычи: PASS. Полный игровой цикл: FAIL.**
Строительство в persistence-enabled runtime отвергается с
`M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED`. Постройка не появилась, материалы
не потрачены. Это действующая защита отсутствующего контракта долговечности;
runner её не отключает. Восстановление и продолжение строительства остаются
BLOCKED. Следующая работа — связать существующие Construction/M4 владельцы с
общим durable checkpoint/ACK и повторить этот же сценарий.

## Зафиксированный источник

- Ветка: `test/playtest-r1-shared-gameplay-20261031`, draft PR #881 после #880.
- Проверенный implementation HEAD: `17042849bb57af863f9534b2f540dafebe7cd4cf`.
- TREE: `f38753c9dc36ad9ce57f243545c51b5b471d6e69`.
- Профиль: `PLAYTEST_R1_SAFE60`; double Godot 4.7.1 custom a13da4feb.
- SHA256 движка: `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`.
- Независимый прогон: `C:/distributed-world-simulator/artifacts/shared-gameplay-20261031/verification/20261031-151321-28036`.
- Команда: `python -O tools/live2/shared_gameplay_check.py --expected-head 17042849bb57af863f9534b2f540dafebe7cd4cf --output C:/distributed-world-simulator/artifacts/shared-gameplay-20261031/verification`.

Runner подтвердил `source_unchanged=true`. Последующая публикация этого документа
не меняет проверенные исполняемые входы; результат относится к указанному SHA.

## Что произошло в настоящих процессах

Два headless M3 клиента работали через ENet со штатным dedicated server Earth.
Перемещения, mining, inventory и construction использовали публичные игровые
команды; прямого изменения canonical state/реплик со стороны driver не было.

| Этап | Наблюдаемый результат |
|---|---|
| Добыча A | В узле 8 → 5 единиц, в инвентаре A — 3 |
| Повтор operation_id | Ни расход, ни выход не удвоились |
| Общий ящик | A положил 3, B забрал те же предметы; оба клиента согласны |
| Строительство B | Защитный отказ; 3 единицы у B сохранились, стадий 0 |
| Граница | Каждый игрок A→B→A: суммарно 4 пересечения, entity/ownership сохранены |
| Reconnect B | Новый transport session и ownership epoch; entity и предметы сохранены |
| Restart | Сервер PID 26852 штатно завершён с exit 0; восстановлен PID 29896 из того же root |
| Действия после recovery | A добыл ещё 4, B ещё 1; ресурсный узел пуст, инвентари A=4/B=4 |

Исходные 8 единиц свободно лежащей sandbox-руды остались нетронутыми. Проверены
материальный баланс, item/resource checksums и состояние обоих клиентов на
13 сохранённых этапах. Независимый аудит: **217 predicates PASS**.

Общая длительность **142.593 с**, включая **89.375 с** ожидания запланированной
остановки. Ожидание готовности нового сервера — **10.891 с**; reconnect B после
ответа на запрос — **0.719 с**. Это длительности данного прогона, не p99 SLA.
В JSON сохранены 60 записей этапов/ответов и отдельные времена команд.

Первый сервер завершился штатно. При cleanup клиент B и второй сервер были
остановлены runner с exit 1; B до этого подтвердил quit, A завершился с exit 0.
Поэтому graceful shutdown всех клиентов не заявляется. Сценарий проверяет
штатный restart сервера, не crash recovery; localhost seam, не multi-host N3–N5;
визуальная оболочка и плавность кадров этим прогоном не проверялись.

## Исправления и независимые проверки

В RESOURCE handler обнаружены два отсутствовавших шага существующего M6 gate:
передача peer/session/ownership в durable escrow и preflight/completion после
отправки ACK. До ремонта: `DURABLE_GATE_IDENTITY_REQUIRED`, затем зависший escrow
и `DURABLE_GATE_BACKPRESSURE`. Теперь используется тот же порядок, что в ITEM;
проверка долговечности не ослаблена.

Независимый повтор также обнаружил ошибку driver: открытие ящика до подтверждения
остановки приводило к взгляду мимо цели. Исправлены торможение, подтверждённый stop
и направление взгляда; arrival требует нулевой скорости и facing dot >0.95.
Ранние неуспешные прогоны сохранены, успешными задним числом не обозначены.

- Focused mining ACK: 57 проверок — real disk, replay, failed enqueue/quarantine,
  fresh-session replay, stale session/epoch, disk failure без success/publication.
- FIFO/disconnect regression: 39; resource JOIN: 41; repeated seam: 43;
  durable gate: 66; mining tool gate: 36. Итого **282 GDScript assertions PASS**.
- **11 Python tests PASS под -O**: недостача/дублирование руды, пустая постройка,
  расход seed-руды, расхождение реплик, disconnect, bounded retry и сохранение ID.
- Reviewer PASS на 17042849; отдельный Verifier PASS для ремонта и выполненного
  сетевого сценария, FAIL полного цикла. `review.md`,
  `reviewer-manifest-17042849.json`, `verification/verification.md` и
  `verification/evidence-manifest.json` находятся в корневом каталоге evidence.

Focused 57+39 и регрессии 186 исполнены на 47b67f5a8; соответствующие runtime/test
blobs неизменны в 17042849. Headless сценарий и Python tests повторены на 17042849.

## Контроль целостности и формальная приёмка

Каталог evidence: `C:/distributed-world-simulator/artifacts/shared-gameplay-20261031`.

| Артефакт | SHA256 |
|---|---|
| Итоговый report.json | `3f92c34b49857a794ea9abed4e673760bc9e3ecf82ee008ec16e8794b05f5710` |
| commands.json | `8cf8bd053ec87b739dd029d9b87e5cadc3d3cd4515cc3a96657c2e09562398c8` |
| Независимый manifest | `d0e8bf6d6da50b032a67924954bdd2114a98cab9ec8c71a20a6a18e05324d8d5` |
| Независимый verification.md | `01559dc6b001c356ae0fcb38a1076763abf6358f030a73698f20f0b0bd3b8c82` |

Harness Drive/CloseRole/Close возвращают exit 3 из-за прежней схемы evidence MVP8
(`PENDING`, `PASS_TWO_EXACT_RUNS`). Логи сохранены отдельно. Это не каноническая
приёмка checkpoint, не подтверждение полного MVP и не разрешение merge в main.
