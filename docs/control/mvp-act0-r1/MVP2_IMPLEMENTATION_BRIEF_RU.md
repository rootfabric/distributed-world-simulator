# MVP2 — два клиента в одном authoritative world

## Предмет и полномочия

Запрос владельца: реализовать `MVP_TWO_CLIENT_SHARED_WORLD` в действующем `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`.

Исходный HEAD: `6fd80b8dbc0cfc422c2ef9a05d2e60a4e7342b57`; TREE: `e84e657be06d3237fc55c47526f11a97b76bc980`. Проверенный canonical main: `127c732a56cc5c25d5712f24a7627ed4bb877374`.

MVP1 уже закрыт событием 6. Freeze refs, события 1–6, его runtime-сцена, Windows review и native evidence неизменяемы. Parent остаётся IN_PROGRESS. Этот документ не является новым dispatch authority, независимым вердиктом, acceptance или разрешением merge в main.

## Design brief

Проблема: запуск P7.7 playground в каждом клиенте создаёт независимые локальные Matter/Item services и не доказывает общий мир. Существующий M3/NX стек уже содержит ENet transport, единственного server owner, проверку совместимости, player ownership, canonical Item Graph, fixed tick, prediction/reconciliation и remote interpolation.

Выбранное решение: новый тонкий composition root в `scripts/runtime/networked_gameplay/mvp/`, единая сцена `scenes/labs/mvp/v0_mvp_two_client_shared_world.tscn` для dedicated-server и game-client. Сервер создаёт только существующий M3DedicatedServerRuntime. Клиент создаёт только существующий M3GraphicalClientRuntime, отправляет intent через его публичный prediction API и отображает принятую реплику. RemotePlayerPresenter остаётся существующим read-only presenter. Ни новый протокол, ни новые правила движения, ни второй Item Graph не вводятся.

Визуальная поверхность: детерминированная неизменяемая начальная проекция P7 LunarMatterBubble с теми же параметрами базового участка. Временный materialization builder освобождается после создания mesh/cache; клиент не хранит изменяемое Matter-состояние и не имеет локального dig writer. Bootstrap digest сверяется между сервером и обоими клиентами. Это доказывает только общий начальный участок: не сетевую мутацию terrain, не копание и не persistence. Движение остаётся существующим bounded SERVER_PREDICTED sandbox kernel; контакт с произвольной геометрией и соединение с mutation route не объявляются готовыми.

Альтернативы отклонены: два локальных P7.7 playground (дублирование истины); новый multiplayer service/protocol (новый foundation); выдача старого Earth MVP smoke за новый exact subject (нет доказательства композиции).

## Граница реализации

Product: только новые MVP composition/presentation файлы, новая MVP scene, `RUN_V0_MVP_*`, `tests/runtime/test_v0_mvp_*`, `tests/integration/test_v0_mvp_*`, `tests/fixtures/v0_mvp/**`, evidence/progress текущего execution и документы этой директории. Принятые network, M3/M4, SM1, P7 и Matter исходники — read-only donors. `project.godot`, main.tscn, глобальные registry/policies/acceptance не меняются.

Bounded validation support: `.github/workflows/mvp2-exact-validation.yml` — отдельный validation-only workflow, разрешён только для owner-triggered push данной feature-ветки с `[mvp2-evidence]` либо явного dispatch. Только exact checkout, тесты и evidence; запрещены source export, Git writes и runtime dispatch другого агента. Python producer находится в этой docs-директории. Исторические workflows не меняются. Изменение подлежит fresh review.

Bounded R15 fixture repair: единственный существующий изменяемый тест `tests/harness/test_v0_mvp_nonterminal_predicate_r13.py`. Исторический тест обязан читать реальные committed events 1–6, а не ошибочно считать последний live event closure-событием. Продолжение синтетическим 7 проверяется только на этом историческом prefix; отдельный тест сводит весь live ledger. Ни события, ни production reducer, ни transition table не изменяются. Это устраняет воспроизведённый класс post-progress fixture collision без ослабления terminal negative controls.

## Обязательные проверки

1. Exact pinned Godot double, fresh import, исходный MVP1 smoke, scope/append-only integrity, full Harness, standard/directional PC0 с проверкой содержимого отчётов, а не только exit code.
2. Три разных процесса: server + A + B, разные user-data directories, transport sessions и player identities. Один scene path, одинаковая прошедшая handshake network fingerprint и одна authority tuple. Сервер действительно имеет два peer mapping, оба клиента — обе связанные player records.
3. Поочерёдный ввод A и B через обычный input/prediction path; ненулевое подтверждённое сервером перемещение соответствующего игрока наблюдается обоими клиентами. Остановка ввода и сравнение содержимого snapshots; исключаются только явно несемантические верхнеуровневые server_tick/checksum, остальные поля сохраняются. Отдельно совпадает полный canonical Item Graph snapshot/checksum.
4. Реальные graphical процессы, активная камера, локальный и удалённый видимые mesh nodes, remote без input authority, viewport captures после обмена. Headless pass не заменяет graphical pass.
5. Negative controls: единственный клиент не удовлетворяет двум клиентам; несовместимый session token отвергается до JOIN; скрытый remote presenter не удовлетворяет визуальному условию; испорченные identity/state evidence отвергаются consumer-тестами.
6. Управляемая остановка всех дочерних процессов, ненулевой exit/timeout/ошибка Godot запрещают PASS. Никаких kill-all и скрытых повторов до удачи.

## Публикация и завершение

После реализации — append-only IMPLEMENTATION_COMMITTED / IN_PROGRESS / IMPLEMENTER, реальный code HEAD и честный provenance (independent_context=false). После exact проверок — отдельный digest-bound native evidence carrier, frozen runtime ref и запрос fresh independent review. Сам Implementer не создаёт PREDICATE_VERIFIED и не объявляет независимую verification.

MVP3–MVP8, whole-MVP acceptance, runtime merge в main и P8 остаются незакрытыми. Две пользовательские игровые сессии не являются вторым implementation worker.
