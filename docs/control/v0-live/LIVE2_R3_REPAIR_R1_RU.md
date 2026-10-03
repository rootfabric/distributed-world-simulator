# LIVE.2 R3 — bounded quality repair

## Основание

R2 subject: `a61e0bb6104b54214cea464a14ca79243b6dd7ea` / `fb8c19eb98cb92961f5c4fadab467260152694b7`.
Ручной результат: PARTIAL_PLAYABLE. Пользователь разрешил фиксацию отчёта и реализацию R3.
Переданная сводка сохранена отдельно: `control/v0-live2-r2-human-evidence-r1` @ `974e9ccff6b1c3015785c839c8660de70d872171`, `docs/control/v0-live/evidence/LIVE2_R2_HUMAN_SMOKE_REPORTED_R1_RU.md`.
Полные Windows-логи и восемь исходных наблюдений ещё не загружены; не выдавать эту сводку за их независимый аудит.

## Изменения

### P0: inventory visibility/input ownership

M5 R5 shell публикует `inventory_visibility_changed` из единого setter. Earth modern inventory adapter подписывается до изменения состояния и при повторном JOIN; подписка не дублируется. Унаследованный `_mvp_inventory_visible` теперь синхронная проекция состояния shell, а не самостоятельное решение.
Esc, Tab, программное закрытие и toggle освобождают одну и ту же блокировку. При закрытии не захватывается мышь у console/system UI. Spectator сохраняет своего владельца ввода. Добавлен реальный handler-регрессионный тест: 30 циклов Tab/Esc/G, повторное подключение shell, idempotent close, key-repeat/release, external UI и spectator.

### P1: remote presentation

Логическая выборка NX5 отделена от Node3D-позиции визуального delegate. Earth wrapper больше не читает смещение капсулы `(0,-0.85,0)` как сетевую позицию, если новый sample отсутствует. Только этот визуальный subtree исключён из автоматической physics interpolation: NX5 уже обновляет его по render-frame. Параметры NX4/NX5 smoothing, authoritative movement и clock/replay rules не менялись.

Метрики: max_snapshot_interval_ms, long_render_frames, max_render_delta_ms плюс прежний отчёт NX5 (mode/render tick/buffer/extrapolation). Это причинное исправление разделения координат, а не доказательство устранения всех жалоб на jitter. Local prediction rollback и секунда паузы после placement должны быть повторно измерены человеком; не маркировать их как закрытые по одному unit-тесту.

Справка по ручной interpolation: https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html

### P2: bounded input pressure

Live Earth server выбирает специализацию существующего NX3 buffer. Ёмкость 64, sequence-window, fixed tick, hold timeout и jump rules не увеличены. Обычный NX3 buffer остаётся неизменным для остальных compositions.
При глубине >=16 сжимаются только соседние одинаковые level-input states; учитываются направление, look, sprint, неизвестные intent fields. Jump edges, start/stop/direction transitions не сжимаются. Сохраняются порядок и самая новая sequence/operation; возраст существующего backlog не продлевается. Invalid/out-of-window/duplicate packets не вызывают compaction.
Действительно заполненная очередь различных переходов по-прежнему возвращает INPUT_QUEUE_FULL с depth/capacity/age. Это защита от накопления повторов, не обещание принимать бесконечный поток различных команд без backpressure. Item/Construction commands не проходят через это сжатие.

### P3: диагностика

Фактический server `_send_result` записывает причины отказов, player/peer/operation/type/stage и scalar queue context. Канонический result и его публикация не меняются. Ring=32, reason buckets<=32, log budget=8/сек.; полные payload/session tokens не сохраняются. Handler duration показывает, блокирует ли server main thread обработка placement/construction. Максимумы и счётчики доступны в `get_report().live2_r3_diagnostics`.

## Не менять и не утверждать лишнего

ENet mapping, R2 rotation limit/state machine, protocol framing и client reconnect files должны быть byte-identical R2. Ротация остаётся контролируемым reconnect, не seamless/no-reconnect acceptance.
R3 не добавляет новый Item Graph/Construction owner, launcher, public networking или новую экономику.

## Верификация

Новые тесты:
- tests/runtime/test_v0_live2_r3_inventory_ownership.gd
- tests/runtime/test_v0_live2_r3_reliability.gd

Обязательная машинная проверка: canonical Windows double Godot, cold import, оба R3 теста, R2 human bridge и rotation guard, NX2 physical/realtime, существующие NX3/NX4/NX5/UI регрессии в полном world/core. Отдельно Project Control и tracked-clean. Старый R2 PASS не переносится на R3 автоматически.

Повторный human smoke: server+2 GUI; 30 открытий/закрытий inventory через Esc/Tab/G без F3; mining/placement/construction; reconnect; быстрое движение A/B; записать local/remote jitter раздельно, queue pressure и причины отказов. Проверить, что HUD/UI не крадут мышь. Полноценный PLAYABLE_BASELINE и merge требуют человеческого подтверждения.

Статус на момент записи: IMPLEMENTED_PENDING_MACHINE_VALIDATION. Ни REVIEW_PASS, ни VERIFIED, ни HUMAN_ACCEPTED не выдаются этим документом.
