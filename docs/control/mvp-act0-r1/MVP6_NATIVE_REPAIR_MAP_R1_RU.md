# MVP6 Native Repair Map R1 — предложение, не runtime-разрешение

## Статус и точка восстановления

Поручение пользователя: «отлично, реализуй MVP6». Parent `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`, feature `feature/v0-mvp-playable-seamless-planet-r1`, PR #597.

MVP6 НЕ реализован и НЕ принят. Эта карта описывает минимальное расширение существующих owner API и порядок последующей реализации. Разрешение на M4 сейчас отсутствует: `HA-V0-MVP6-NATIVE-ITEM-CARRY-R1` имеет статус OPEN. Запрет родительского Work Order на `m4/**` сохраняется. Наличие этого документа не снимает запрет и не переоткрывает MVP1–MVP5.

Начальная граница: `bc360383b78f0778cac136fe1d9c3a7d656c687b`; первый диагностический subject `60e4e7588a48b58897fe577fd1ab9660e89030df`; повторный subject после исправления диагностического сравнения/вызова controller `bd5a919ac527f8d54c518fb9c04050044a12a972`, TREE `ecb76e3a230b03c84fe308e6cfc28a02709b0326`.

## 1. Причина, а не симптом

Live player export в `v0_mvp3_live_player_transfer_port.gd` намеренно принимает только пустой carrying state, маркирует `MVP3_EMPTY_CARRY_ONLY` и отвергает непустой inventory через `MVP3_ITEM_CARRY_REQUIRES_MVP4`. Это не отсутствие кнопки в интерфейсе: native Item Graph ещё не имеет ограниченной транзакции передачи item closure конкретного игрока между этими live owners.

Целиковый `restore_durable_state` заменяет все items/inventories/containers/mounts и очищает ledger перед отдельным restore replay. Использовать его для переноса одного игрока в живой target нельзя: это может затронуть другого игрока и независимые world objects.

Обычный NetworkedGameplayService export/restore намеренно закрыт при live bindings. Не снимать `LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED`, чтобы изобразить перенос через старый restart API.

Дополнительные выявленные стыки: базовая native spatial validation связана с sandbox-флагом; обычный bootstrap двух authorities создаёт одинаковые fixture world identities. Для общей сцены нужны доверенная геометрическая проверка и единственное размещение каждого world item, а не UI-фильтрация дублей.

## 2. Запрашиваемые существующие owner-файлы

| Точный путь | Ограниченная цель |
|---|---|
| `scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd` | Actor-scoped freeze/export/stage/discard/retire/activate и fencing native item/replay/output/consume entrypoints в существующем M4 owner |
| `scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd` | Разделить trusted spatial validation и sandbox content bootstrap; исключить повторную генерацию world fixture identities; необходимые общие native guard points |
| `scripts/runtime/networked_gameplay/networked_gameplay_service_p2.gd` | Согласовать существующие player и item owners при live handoff; сохранять auth-before-replay и существующие restart guards |

MVP transfer port, authority/gateway/client adapters, сцены, новые тесты и документация остаются в ранее разрешённых MVP-путях. Изменение M3 p2 за пределами старых player hooks требует принятия именно нового bounded решения. Если реализация потребует ещё один owner-файл, остановить такое расширение и предъявить конкретное основание; три файла — граница, а не wildcard-разрешение.

Не менять Matter, P7, SM1, architecture ownership, `project.godot`, исторические execution events, старые acceptance/verdict records. Не создавать второй Item Graph, отдельный inventory, новый decision owner или приватный persistence/replay truth.

## 3. Native carrying slice после разрешения

Сначала новый bounded Work Order и точная матрица требований. Переносить существующие item identities, количества, location slots, hotbar и canonical equipment relation; закрывать все входящие в допустимый actor closure связи. Не перетаскивать общий container, world item либо чужую inventory только потому, что они присутствуют в source snapshot.

Существующий SM1 остаётся владельцем freeze/commit/activation решения. Item Graph владеет собственным staged state и защитой записей. Порядок:

```text
SM1 freeze -> source native item/player export
-> authenticated source attestation -> target native stage
-> проверка связности и WARM без active publication
-> SM1 commit -> source native retire + receipt
-> SM1 activation -> target native activate
-> gateway pivot -> следующий реальный input на target
```

На этапе stage target нельзя сделать вторым активным владельцем items. Нельзя сначала активировать target, а потом надеяться удалить source. Source retire и target activate должны координироваться с уже существующими player hooks без наблюдаемого частичного owner install. До commit abort возвращает source к разрешённым операциям и удаляет target stage; после commit нельзя самовольно оживить source.

Защита требуется не только на gateway: native item commands, выдача server output и Construction consume должны соблюдать freeze/retire. Неверная session/actor/epoch не получает успешный replay. Передаваемые dedup entries остаются частью существующего native ledger; перенос не создаёт новый ledger и не затирает target entries другого игрока. Конфликт operation fingerprint отвергается. Исторический replay не должен заново создавать уже перенесённый либо израсходованный item.

## 4. Bootstrap и spatial slice

Trusted scene configuration задаётся сервером до подключения клиентов. Разместить общие world items/container ровно у одного authority; второй не генерирует те же identities. Read-only client view может объединять owner snapshots, но не исправлять конфликт канонического владения произвольным выбором одного дубля.

Реальные pickup/drop/container действия проверяются по canonical position и поддерживаемой системе координат поверхности. Не включать sandbox только ради range checks, если он одновременно добавит тестовые предметы. Клиент не диктует transform, баланс или успешность операции. Отдалённый объект, чужой region и неподдерживаемая spatial binding должны приводить к явному отказу без мутации.

## 5. Product composition slice

После native focused PASS собрать одну композицию `authority/a + authority/b + gateway + client/a + client/b`, продолжая MVP5 dig/material path.

Живой сценарий: canonical tool -> dig -> фактический material output -> drop -> два независимых клиента запрашивают pickup -> ровно один победитель -> общий container -> перенос непустого inventory/equipment A→B→A -> Construction из реальных canonical resources -> оба клиента видят одинаковую постройку и производную collision.

Все операции проходят продуктовый input/intent path. Автосценарий маркируется автоматическим, не выдаётся за физическую клавиатуру. Server response должен содержать native semantic result, а не только успешную доставку RPC. UI и mesh/collision — производные от канонического состояния, не источники истины.

Construction использует действующие preflight/commit и atomic resource-consume contract. Подготовка не списывает resources. Недостаток ресурсов, stale expected revision или конфликтующий replay не оставляют полупостройку и не теряют материалы. Проверить фактическое столкновение с восстановленной из canonical Construction геометрией, а не только наличие CollisionShape3D в дереве сцены.

## 6. Negative/positive controls

Native: пустой roundtrip остаётся положительным контролем; непустой roundtrip сохраняет IDs/qty/slots/equipment и допускает настоящее действие на target. Wrong actor/session/source/target/epoch, modified payload с пересчитанным checksum, stale attestation, чужая item closure, duplicate stage/activate, partial native install, конфликт ledger и post-retire writes должны отвергаться без повреждения состояния другого игрока.

Live: одновременная конкуренция клиентов за один item; exact retry после потерянного ACK; отказ target до/после commit; другой клиент продолжает input. После каждого переноса проверять отсутствие второго active item и сохранность player/session/body/camera identity.

Persistence в MVP6: соответствие существующим payload contracts для item/equipment/container/Construction и dedup; полный reconnect/world restart/resync — MVP7. При сравнении JSON использовать существующий `network_contract_utils.canonical_json` целиком, включая checksum, clocks и slots. Нельзя исключать неугодные поля. Факт JSON float/int normalization не является потерей ресурса; реальная slot migration либо изменение revision должны быть обнаружены и объяснены отдельно.

Falsifiers evidence: подмена количества, другого item ID, Construction ID, второго active owner, client disagreement, fake collision, чужого HEAD/TREE и fake PASS должны приводить к отклонению evidence.

## 7. Exact evidence и конечный критерий

После каждой runtime correction — новый exact subject и свежие проверки. До продуктовой приёмки необходимы неизменённые MVP3/MVP4/MVP5 regressions, native adversarial gate, пяти-процессная графическая композиция, полный world/core, standard/directional PC0, post-build critique, Evidence Map и отдельные Reviewer/Verifier. Наличие ожидаемого отказа в prerequisite diagnostic — не реализация MVP6.

MVP6 остаётся открытым, пока не доказаны все его live baseline sub-gates. Human approval изменения scope не означает разрешение runtime/main merge или whole-MVP acceptance. Следующие обязательные этапы MVP7 и MVP8 не закрываются автоматически.

## 8. Сохранённый первый неуспешный diagnostic

Run `35077271093`, job `104732558432`: import PASS; unchanged MVP3 232 assertions PASS; unchanged MVP5 270 assertions PASS; новый diagnostic 135 assertions/1 failure на прямом Dictionary equality после JSON restore. Nonempty carry case в этой версии ещё не выполнялся. Дополнительно Drive/CloseMission получили INVALID_INVOCATION из-за неподдерживаемого `-Candidate` вне overview.

Raw artifact `10438587889`, ZIP SHA-256 `bfbf46c50eae2a2dce2bf02afdabc1944b55303205f0d99991fd03a097a40324`, сохранён без перезаписи. Повторный diagnostic сохраняет raw comparison/types и полные до/после payload, проверяет canonical JSON без исключения полей, отдельно проверяет отсутствие slot migration и выполняет carry case независимо от результата payload case. Controller вызывается без `-Candidate`; некорректный controller exit больше не проходит workflow незаметно. Окончательный результат повторного run фиксируется отдельным evidence record после чтения артефакта.
