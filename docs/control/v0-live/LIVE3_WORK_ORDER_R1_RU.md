# LIVE.3 R1 — штатное восстановление клиент-серверного продукта

## Исполнение и точная база

- Запрос владельца: реализовать LIVE.3 после ручной приёмки и merge LIVE.2.
- BASE_MAIN: `894f7033b16cefcf78e40d660bdbaf0c9b061afe`.
- BASE_TREE: `3b571e318d563907876181e73aa21e196586841f`.
- Ветка: `feature/v0-live3-product-recovery-r1`.
- План-владелец: `docs/control/v0-live/V0_LIVE_CLIENT_SERVER_ROADMAP_R1_RU.md`, LIVE.3.
- Риск: HIGH (persistence/recovery/product lifecycle).
- Статус: IN_PROGRESS; независимая приёмка и merge не заявлены.
- Исторический Harness registry generation 82 всё ещё маршрутизирует MVP_ACT0. Эта работа не переписывает исторический epoch, catalog, lease или main-owned acceptance; LIVE.3 — явно заказанное продолжение main-owned V0-LIVE roadmap. Диагностика control сохраняется отдельно, не выдаётся за новый main-owned dispatch.

## Design brief

LIVE.2 доказал живое управление, но ручной launcher создавал временную сессию без явного persistence root и пропускал import свежего checkout. M3 уже имеет M6 repository/coordinator, durable gameplay adapter и существующие Construction/Matter recovery donors. LIVE.3 должен подключить именно эти owners к штатному entry point, а не создать новый save-game store.

Наблюдаемый результат: A и B играют; A закрывается и запускается с той же logical identity; получает текущие предметы и постройки. Затем сервер штатно сохраняется и останавливается, запускается с тем же слотом; клиенты восстанавливают связь и продолжают с прежним каноническим состоянием. Отказ записи/повреждённый save не должен молча превращаться в новый пустой мир или успешное сохранение.

Выбранный подход: минимальный product composition/lifecycle adapter над существующим M3/M6/P4/P5/P6, стабильный именованный save slot, operator-owned graceful shutdown, один Windows launcher с обязательным import и раздельными профилями. Подключение нового store, переписывание transport и перенос исследовательской физики исключены.

## Допустимые поверхности

- `scripts/app/v0_simulator_app.gd` и новые bounded LIVE3 product adapters;
- `scripts/runtime/networked_gameplay/m3/`, `m6/`, `p5/`, `p6/` только подтверждённые recovery composition gaps;
- существующий Construction recovery consumer seam, без нового canonical owner;
- `tools/live3/`, `tests/runtime/test_v0_live3_*.gd`, `tests/integration/test_v0_live3_*.py`;
- scoped CI `.github/workflows/v0-live3-*.yml`;
- `docs/control/v0-live/LIVE3_*`, `docs/testing/LIVE3_*`.

Не изменять: canonical main напрямую; исторические evidence/acceptance; ECO/FABRIC; глобальные identity, transport protocol, ownership, budgets; существующие тесты ради зелёного результата. До существенного расширения scope — отдельный repair/design addendum.

## Обязательные проверки

1. Чистая точная база, import, отсутствие SCRIPT/PARSE/COMPILE errors.
2. Старые LIVE2 focused, P2 и native recovery regressions.
3. Закрытие/новый процесс A, пока B меняет мир; A получает current canonical state.
4. Штатный restart сервера: player identity/position, inventory/equipment, world items/container, resource state и Construction/replay восстанавливаются без дублирования.
5. Повторная операция не выдаёт второй материал и не строит второй объект.
6. Слот повторно открывается; другой слот изолирован; неверная identity/save/error записи fail closed.
7. Recovery проходит через обычный `main.tscn --network-mvp`, не только тестовый альтернативный runtime.
8. Windows operator launcher: обязательный import, не использует runner checkout, не убивает чужие процессы; сохраняет логи и только собственные PID; restart без принудительного убийства сервера.
9. Full world/core на frozen implementation, затем отдельные fresh review/verifier и human manual recovery gate.

## Границы утверждений

R1 — planned/quiescent restart, не arbitrary power-loss во время междоменного commit. Поддержка terrain заявляется только для реально подключённого canonical terrain/resource owner; mesh и client snapshot не становятся сохранением мира. `async accepted` не равен завершённой добыче/стройке. Любая недоказанная поверхность остаётся явным gap, а не PASS.

## Durable resume anchor

Последний завершённый predicate: MAIN_BASE_AND_RECOVERY_ENTRYPOINT_INSPECTED.
Известный недоступный маршрут: локальный `git clone` в контейнере — DNS route failure; GitHub connector работает. Не повторять этот маршрут и не использовать CI как замену Git transport.
Следующее действие: baseline/control + recovery composition audit, затем реализация и repository-owned exact Windows tests. Все записи — только в этой feature/control ветке, без self-accept/self-merge.
