# NET-SMOOTH1 #815 — реальная Full/COMPACT/Frame-цепочка и изолированный F64-v2

## Предмет и границы этапа

База — неизменённый PR #863: `d5d2f0042b1cb8e8e395301f21d9016218836d01`, TREE `46de81af25965c86fb059863c615e1cce31e2fe1`. Новая ветка: `feature/net-smooth1-815-real-snapshot-f64-v2-r1`. Никакого merge, force-push или изменения main.

Добавлен отдельный кандидат `compact_gameplay_snapshot_v2.gd`. Старые FullSnapshot, COMPACT v1, ProtocolFrame v2, JSON/checksum utils, ENet, M6 и runtime не изменены. Семь исходных Git blob SHA проверяются source-тестом и включены в нативный отчёт. Новый codec НЕ импортируется игровым runtime и НЕ активирован у сетевых клиентов. Переход версии требует отдельной согласованной активации/проверки совместимости.

Этот этап заменяет псевдо-JOIN с произвольным payload настоящими production-контрактами:

`FullSnapshot.create/validate -> CompactGameplaySnapshot.encode/validate -> ProtocolFrameV2.create/encode -> ProtocolFrameV2.decode -> CompactGameplaySnapshot.decode -> FullSnapshot.validate`.

Два разных доказательства не смешиваются:

1. Детерминированный корпус из 2 048 допустимых двухпользовательских Earth-local DTO: позиции, скорости, ориентация, session/ownership/authority, inventory, shared item. Это СГЕНЕРИРОВАННЫЕ тестовые состояния, не исторические Windows-пакеты.
2. Отдельный native integration-test запускает настоящий `User1ProductSeamGameplayService`, две авторитетные записи игроков, fixed movement, реальный A→B→A, reconnect и durable validation. Снимки забираются через `service.create_snapshot()`, без подмены службы или её состояния. Это не GUI и не multi-host/ENet performance acceptance.

## Что воспроизведено локально

На предоставленном Linux Godot `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`, с побайтно идентичными семью исходными файлами базы:

- 2 048 состояний через настоящий старый v1-путь: 14 checksum-сбоев.
- Те же 2 048 состояний через изолированный COMPACT v2: 0 сбоев.
- `NS1_815_REAL_CHAIN PASS assertions=22569 failures=0 legacy_red=14 v2_green=2048/2048`.
- Python source/isolation suite: 5/5 PASS; независимая проверка native JSON-отчёта PASS.
- Локальный запуск был exact **contract slice**, не полным игровым репозиторием: тест настоящей службы USER1 здесь не запускался. Он выполняется отдельной pinned Win/Linux CI-матрицей на полном checkout; её результат проверять по конкретному HEAD, не объявлять заранее.

### Первый нарушенный слой

Фиксированный sample 84 хранится точными IEEE754-битами, без повторного JSON-преобразования исходного witness.

| Момент | `c` полного состояния | `h` compact | `payload_checksum` frame |
|---|---|---|---|
| После FullSnapshot.create и Compact.encode | valid | valid | ещё не создана |
| После JSON-roundtrip внутри Frame.create | **invalid** | **invalid** | valid: вычислена уже по изменённому payload |
| После JSON.parse у получателя | valid снова | valid снова | **invalid** |

Первое изменённое поле: `$.payload.snapshot.p[0].v[1]`, вертикальная скорость игрока A.

- До Frame.create: `381e0df76695bebc`, JSON `-4.244327441156037e-16`.
- После Frame.create: `391e0df76695bebc`, JSON `-4.2443274411560372e-16`.
- После следующего разбора число возвращается к первому варианту, тогда внешняя checksum уже не совпадает.

Это доказанная двухтактная нестабильность конкретной числовой сериализации на реальной цепочке контрактов, а не порча байтов ENet. Но это НЕ доказательство, что исторические Windows-инциденты #815 произошли на том же поле/значении.

## Изолированный кандидат исправления COMPACT v2

Schema: `planet_simulator.compact_gameplay_snapshot.v2`.
Обязательное поле `nf`: `IEEE754_BINARY64_LE_HEX_V1`.

Числа `position`, `velocity`, `orientation_yaw` кодируются в 16 шестнадцатеричных ASCII-символов, описывающих точные 8 байт IEEE754 binary64. Проверяется endian-canary `1.0 -> 000000000000f03f`. Декодер проверяет длину, алфавит, конечность и обратное соответствие битов. Нет decimal parse, округления, допуска, циклического «стабилизирования» или пересчёта принятой `c`.

`c` переносится из исходного валидного FullSnapshot без изменения. `h` проверяется над новым compact body. После восстановления чисел вызывается ORIGINAL FullSnapshot.validate со старой `c`. Внешний Frame.encode/decode также оригинальный. Порча реального байта по-прежнему вызывает `PAYLOAD_CHECKSUM_MISMATCH`. Отдельно проверены `h`, вложенная `c`, чужая версия, неправильный `nf`, поля/session/epoch, NaN/Inf, signed zero/subnormal, пакетный лимит.

На данном корпусе общий размер v2-пакетов вырос на **7.897%** (максимальный пакет 1 354 байта). Это наблюдение конкретного корпуса, не прогноз всего трафика. Производительность/задержки ещё не измерялись. Старая v1-сторона намеренно не принимает v2; скрытого протокольного upgrade нет.

## Windows Independent Verification — без случайной 6×120-серии

Цель — независимо подтвердить тот же first-failure и GREEN на новой версии, затем реальную службу USER1. Не запускать GUI performance под видом испытания v2: он ещё НЕ подключён к игровому runtime.

1. Заморозить HEAD/TREE этой ветки; базовый `d5d2f004…` должен быть предком. Проверить tracked-clean. Не изменять main и предыдущие PR.
2. Закрепить Godot `4.7.1.stable.double.custom_build.a13da4feb`: console SHA `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`, настоящий main EXE SHA `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`. Этот этап headless: не требует нового GPU-перфоманс-окна.
3. Выполнить clean import, новую source-suite и оба новых native-теста. Любая ошибка скрипта/компиляции/ненулевой exit — FAIL. Сохранять stdout/stderr/SHA каждого запуска. Не считать простое наличие слова PASS достаточным.
4. Выполнить оригинальные native #815 guard/safety, R2.2 attestation, M6 recovery и USER1 seam регрессии — список закреплён в `.github/workflows/net-smooth-815-real-snapshot-f64-v2-exact.yml`.
5. Проверить отчёт независимым Python-проверяющим, затем сверить source/Windows/Linux CI на ТОЧНОМ новом HEAD.

Основные команды из замороженного checkout (каждый exit code проверить):

```powershell
$G = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
$Out = Join-Path (Get-Location) 'artifacts\815-real-chain-independent'
New-Item -ItemType Directory -Force $Out | Out-Null
$env:DWS_815_CHAIN_REPORT_PATH = Join-Path $Out 'real-chain.json'

python -m unittest discover -s tests/tools -p 'test_net_smooth1_815_real_chain_source.py' -v
& $G --headless --editor --path . --import --quit
& $G --headless --path . --script res://tests/runtime/test_net_smooth1_815_real_snapshot_chain.gd
& $G --headless --path . --script res://tests/runtime/test_net_smooth1_815_user1_snapshot_v2.gd
python tools/net_smooth1/verify_815_real_chain_report.py "$Out\real-chain.json" --source-root .
```

Первый тест должен воспроизвести старый RED и новый GREEN на одной и той же коллекции состояний. Он также проверяет неизменность source, точные числа, старые error codes и невозможность незаметной активации v2. Второй тест должен реально пройти A→B→A и reconnect; print-out содержит число принятых реальных USER1-снапшотов. Не заменять его mock'ом при ошибке.

Отчёт: полный HEAD/TREE, две SHA Godot, blob SHA исходных v1-файлов, число assertions, old RED/new GREEN, первый изменившийся scalar/биты, первый нарушенный checksum, реальная USER1-матрица, original regressions, SHA256 исходного native JSON, source/Win/Linux exact IDs. Объявлять только подтверждённые результаты.

## Что НЕ закрывает этот этап

- Историческая причина live-инцидентов #815 остаётся unproven до сопоставления реального повреждённого кадра.
- Новый codec покрывает COMPACT. Full/Join JSON-контракты и общий числовой протокол ещё отдельно проверяются.
- Runtime v2-negotiation/активация, fallback со старым клиентом, полноразмерный ENet/GUI A/B и производительность — следующий отдельный этап.
- Project Control, полная бесшовность на разных физических серверах и release-merge не принимаются этим тестом.

`READY_FOR_MERGE=false`. Старые checksum/fail-closed нормы не ослаблены, guard не заменяется, 120 FPS по умолчанию не включён.
