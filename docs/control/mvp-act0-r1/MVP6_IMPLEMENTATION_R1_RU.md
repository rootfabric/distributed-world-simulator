# MVP6 R1 — предметы, строительство и согласованность persistence

## Устойчивая точка продолжения

- Поручение владельца: «отлично, реализуй MVP6».
- Parent: `V0-MVP-R1-WO-001`; epoch: `E2026-09-09-V0-MVP-R1`.
- Predicate: `MVP_ITEM_CONSTRUCTION_PERSISTENCE_CONVERGENCE`.
- Ветка: `feature/v0-mvp-playable-seamless-planet-r1`; parent PR: #597.
- Начальный HEAD: `bc360383b78f0778cac136fe1d9c3a7d656c687b`.
- Закрытый runtime MVP5: `b78de4980328bb7b4d19e030bb7f0fa5d9976cd8`, TREE `0bfdd7595e10f007815bb666e62e7c5575172173`.
- Наблюдаемый canonical main: `675c04bb213bbb68b8cdb500d540d57ce1490318`.
- MVP1–MVP5 не переоткрываются. MVP6 пока НЕ реализован и НЕ верифицирован; parent остаётся IN_PROGRESS.
- Следующее действие: получить свежий Project Control/epoch audit, завершить карту существующих owner API, затем реализовать bounded composition и проверить exact candidate.

Этот документ — предварительный design brief и recovery anchor, а не independent verdict, acceptance или разрешение менять foundations.

## Обязательная продуктовая граница

Применяется уже принятый `V0-MVP-LIVE-SIMULATOR-BASELINE-R1` и полный список MVP6 sub-gates из parent Work Order:

1. Живые pickup/drop/shared item и сохранение identity/quantity.
2. Два клиента претендуют на один предмет: ровно один победитель.
3. Общий container, а не отдельный клиентский inventory.
4. Непустой canonical carrying state проходит seam без reconnect/respawn.
5. Реальная экипировка canonical tool.
6. Construction commit расходует реальные canonical resources атомарно.
7. Оба клиента получают одну Construction и производную collision.
8. Item/Construction state совместим с существующими persistence payload/rehydration semantics.
9. Никакого private/duplicate Item Graph, Construction, persistence или authority.

Полный reconnect/world restart/late join остаётся MVP7. Длительный повторяемый игровой цикл остаётся MVP8. Их нельзя объявлять выполненными из MVP6 focused tests.

## Проблема и текущая реализация

MVP5 выдаёт материал в существующий canonical Item Graph и публикует read-only material projection. Он ещё не связывает общий item lifecycle и Construction в одну live two-client композицию. Успех отдельного backend-теста не закрывает MVP6.

## Выбранное направление

Переиспользовать native entrypoints существующего NetworkedGameplayService, Item Graph, Construction, SM1 carrying и persistence codecs. Добавлять только ограниченные routing/composition adapters и производное отображение под `scripts/runtime/networked_gameplay/mvp/**` и `scenes/labs/mvp/**`.

Авторизация actor/session/authority должна происходить перед записью и replay. Клиент передаёт намерение, а не итоговый баланс, allocation, item identity или Construction truth. Ответы и видимые объекты выводятся из canonical snapshots. Любой replay получает native owner result; transport success не заменяет semantic success.

Для seam использовать существующий native carrying transfer. Если фактический owner API не умеет переносить непустое состояние в текущих разрешённых границах, зафиксировать точный root cause и bounded scope amendment/Human Attention вместо тестового копирования inventory либо скрытого расширения четырёх M3 hooks.

## Альтернативы, которые не принимаются

- Demo-only inventory, второй replay ledger или тестовое прямое создание Construction.
- Тестовые snapshots вместо live-client операций.
- Списание ресурсов отдельным неатомарным шагом перед Construction commit.
- Перенос только player position с потерей либо дублированием предметов.
- Ослабление уже закрытых MVP3–MVP5 gates или замена полного world/core кратким тестом.

## Риск, scope и проверка

Риск остаётся CRITICAL. Границы определяет parent Work Order; этот brief не расширяет разрешения. Matter, M4, P7, SM1, project.godot и architecture ownership не меняются. Четыре разрешённых M3 файла остаются разрешёнными только для уже согласованных live-player hooks.

Новый именованный read-only CI workflow можно добавить лишь после явного bounded validation-scope amendment parent Work Order. CI выполняет checkout/tests/evidence, не служит обходом Git transport.

План проверки: focused native positive/negative/replay controls; live gateway + две authority + два клиента; каноническое списание и одинаковые snapshots; non-empty seam; реальная производная collision; persistence payload roundtrip; неизменённые MVP5/MVP4/MVP3 regressions; full world/core; exact HEAD/TREE и SHA-256 evidence; post-build critique; fresh independent Reviewer/Verifier и PC0. Implementer не принимает собственную работу.

## Исполнительный маршрут и восстановление

GitHub connector подтверждён для чтения и публикации. В текущем контейнере нет готового checkout, Godot и PowerShell; не повторять прежний неработающий ad-hoc GitHub clone/download route. Для выполнения использовать repository-owned CI с canonical double Godot. После сбоя перечитать live ref и этот anchor, не использовать истёкшие resource IDs и не пересоздавать закрытые predicates.

Известные исторические route failures: `Could not resolve host: github.com`, download security rejection и переполнение длинного инструментального вывода. Читать код и логи ограниченными фрагментами; сохранять существенные результаты отдельными commits. Очередь CI или запрос review не означает автоматическое фоновое продолжение этой сессии.

## Continuation 2026-09-16: реальный NX rollback gate

Native-carry HA выше в истории уже RESOLVED; native carry не реализуется заново.
Текущий diagnostic subject: `970b4293ae303cda03cd99c5c77ddd54e0f41496`, tree
`6a86c84e57ef313ad841c6cb906bc7fd1daafb06`. Main остаётся
`6982a563dd0c88c81449566131852c601ae89868`.

Проверка сырых логов отменила пригодность прежнего NX positive summary:
[false-green repair](MVP6_NX_FALSE_GREEN_REPAIR_R1_RU.md). Исправленный probe и
точные Windows/Linux A/B выявили одинаковые 3 failures из 1077 assertions в
каждой композиции. Это существующий same-revision prediction rollback defect,
не установленная регрессия MVP6. Raw PC0: standard YELLOW, directional RED.

[Repair Map и конкретный неприменённый diff](MVP6_NX_ROLLBACK_REPAIR_MAP_R1_RU.md)
задают один дополнительный journal-файл. Новый blocking decision:
`HA-V0-MVP6-NX-SAME-REVISION-ROLLBACK-R1`. Parent запрещает `scripts/network/**`;
старое разрешение native carry его не покрывает. Production `Drive` и
`CloseMission` на `6bd1ddefbd23b30636aff137cdb26e0102157bca` подтвердили
`HUMAN_DECISION_REQUIRED`, `mission_exit_allowed=true`, `mission_complete=false`.
Exact controller logs и scoped независимые роли сохраняются в `nx-scope-gate-r1/`.

Следующее действие — durable HUMAN resolution этого одного scope decision,
после него bounded repair/retest, принятый canonical dependency input и только
затем main-owned V0→NX clearance, exact PC0/epoch audit и MVP6 construction.
Clearance registry, journal runtime, main и MVP1–MVP5 этой continuation не изменены.
MVP6 не VERIFIED; construction/five-process/world-core в этом slice не запускались.

При последнем fetch обнаружена внешняя незамерженная validation-ветка
`validation/nx-prediction-rollback-r1` (наблюдаемый head
`3b02b4d71ebabca865f55a4a7f79b9c4db0a9e3c`). Это не работа данной continuation и
не canonical permission/evidence. Перед возобновлением проверить её live state,
возможный PR и current main; не дублировать уже принятый repair и не считать
само наличие внешней ветки разрешением обходить write fence.
