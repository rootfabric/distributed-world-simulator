# MVP6 → NX: bounded запрос исправления существующего prediction journal

## Точное состояние

Parent `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`, PR #597.
Диагностический subject `970b4293ae303cda03cd99c5c77ddd54e0f41496`,
tree `6a86c84e57ef313ad841c6cb906bc7fd1daafb06`.
Main `6982a563dd0c88c81449566131852c601ae89868`, NX
`1a56fe0e845c941f14ce7b9296ee939e9d0ca8bc`.

После устранения ложного PASS точные Windows и Linux A/B воспроизводят
одинаковые 3 failures из 37 assertions в owner item rollback; остальные тесты
выполняют 44/31/25/940 assertions без ошибок. Всего 1077 assertions и 3 failures
на каждую композицию. Это baseline defect, не доказанная регрессия MVP6 M4.
Оба прогона используют явно описанную parser-normalized NX композицию.

Linux run `35093369957`, artifact `10445650486`, ZIP SHA256
`003e768759fb18227926d3b6fc6ec8a854ff26dc532e343f38ec2e3a4f8c59ab`.
ZIP скачан через GitHub API и его фактический digest совпал с Actions metadata.
Windows: canonical engine `4.7.1.stable.double.custom_build.a13da4feb`, SHA256
`3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`.
Raw logs, summaries, команды, provenance и hashes — `nx-rollback-evidence-r1/`.

## Root cause, owner и shipped путь

Единственный repair target:
`scripts/network/prediction/predicted_item_interaction_journal.gd`.
Точный blob на main, NX и feature одинаков:
`ed23f0d2b7a9e6cfb3f13b78de70c7f552035b69`.

`resolve_prediction()` удаляет `_pending[index]`, записывает resolution в
существующий ledger и вызывает `adopt_authoritative()` при непустом snapshot.
При одинаковых revision/checksum adoption возвращает duplicate. Projection
перестраивается лишь если истекла другая prediction; обычно старый optimistic
pickup/drop остаётся видимым, несмотря на rollback и пустой pending.

Shipped callers: `scripts/runtime/networked_gameplay/m7/m7_network_item_command_bridge.gd`
передаёт canonical snapshot как при completion (:350), так и stop cancellation
(:181). Existing NX6 тест использует `{}` при rollback и проверяет иной путь.
Bridge тесты проверяют counters/pending, но не все фактические presentation values.

Независимый fresh read-only Reviewer `/root/rollback_root_review` подтвердил
root cause, identical blob, caller/sibling gap и необходимость отдельного scope
approval. Три исходных failures: pickup не возвращается в WORLD, drop не
восстанавливает quantity, predicted spawn не удаляется.

## Предлагаемый bounded fix — ещё не применён

Reviewable diff: `mvp6_nx_same_revision_rollback_proposed.patch`.
Только после успешного duplicate adoption в `resolve_prediction()` вызвать
существующий `_rebuild_projection(false)` и вернуть его failure при отказе.
`false` сохраняет семантику оставшихся pending predictions и не превращает их
в CONFIRMED_BY_SNAPSHOT. Существующие canonical snapshot, ledger, IDs и owners
сохраняются. Bridge/runtime NX leaf не изменяются этим предложением.

Альтернативы: rebuild на любом duplicate adoption шире необходимого; новый
snapshot revision, очистка клиента или обход через MVP glue маскируют дефект.
Ослаблять три failing assertions, менять их payloads или засчитывать одинаковый
FAIL как baseline/candidate PASS запрещено.

## Граница полномочий

Parent Work Order прямо запрещает `scripts/network/**`. Его stop condition:
`Mandatory sub-gate requires an additional owner-native change outside allowed paths without separate bounded scope amendment and required Harness/Human gate`.
Resolved native-carry HA разрешает только прежние три файла. Поэтому новая запись
`HA-V0-MVP6-NX-SAME-REVISION-ROLLBACK-R1` запрашивает один точный journal-файл.
Runtime patch до решения человека не применён, в том числе к temporary runtime.
Это explicit scope gate, не отсутствие исполнителя и не готовый clearance merge.

## Проверка после разрешения

1. Director фиксирует resolution и точный write-fence amendment одного файла.
2. Применяет bounded patch; добавляет MVP-prefixed regressions в уже разрешённые
   test paths. Проверяет одинаковый snapshot при pickup/drop/place/transfer,
   сохранение другой pending операции ровно один раз, duplicate response,
   timeout/newer snapshot и реальные bridge completion/stop values.
3. Повторяет NX A/B и неизменённые NX6/bridge tests; требует 5/5 PASS и отсутствие
   fatal logs. Assertions старых тестов остаются неизменными.
4. Значимый runtime repair требует MVP3/MVP4/MVP5, MVP6 native/security/construction
   и дальнейшие full world/core, fresh Reviewer/Verifier согласно parent.
5. Готовит main-owned integration/clearance в правильном порядке: journal repair
   должен войти в canonical baseline через отдельный HUMAN merge, либо main-owned
   process должен явно принять его dependency input. Нельзя скрыто подмешать repair
   в baseline и назвать его неизменённым current main. После нового canonical main
   — exact PC0, epoch audit и продолжение MVP6 construction/five-process.

MVP6 не VERIFIED; whole MVP не принят; parent IN_PROGRESS. PC0 остаётся
standard YELLOW / directional RED. Clearance registry и canonical main не изменены.
