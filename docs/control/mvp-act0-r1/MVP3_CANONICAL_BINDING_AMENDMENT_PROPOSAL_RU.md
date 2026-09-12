# MVP3 — недостающий live handoff binding: предложение amendment

Статус: **PROPOSAL / НЕ РАЗРЕШАЕТ ИЗМЕНЕНИЕ FOUNDATION**.
Родитель: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`.
Проверяемый runtime: `6dca13bfc91698551544271a0245246e6d2ead12`, tree `9bb56d31bb1a384a6b2e581d6797c0d142639443`.
Последний пройденный seam-subgate остаётся оператором с наблюдателем; он не принимается как MVP3.

## Контракт пользователя, который нельзя подменять

В одной сцене два независимо управляемых игрока. Пересекающий шов игрок проходит A→B→A через существующий gateway, не пересоздаёт персонажа и не выполняет обычный reconnect. Другой игрок не превращается в наблюдателя. Перенос всего общего мира/Item Graph из-за движения одного игрока не считается доказательством per-player/regional crossing. Канонические владельцы сохраняются; не добавляется новая истина в demo, gateway или subclass.

## Проверяемая проблема

`NetworkedGameplayService` (P5→P3→P2) предоставляет M6 `export_durable_state` / `restore_durable_state`. Это restart API:

- live transport bindings очищаются в PlayerRegistry и PlayerOwnershipService;
- восстановление в настроенном другом owner/epoch отклоняется;
- обычный rejoin сохраняет EntityId и позицию, но увеличивает ownership_epoch — это не live переназначение владельца;
- payload содержит оба player registry, весь Item Graph и доменные состояния, а не выделенный carrying domain;
- отдельный `SM1.begin_transfer` без привязки к реальному mutation entry point не блокирует прямой вызов M3 Service.

Исполняемый preflight использует реальные классы, показывает успешную штатную инициализацию/движение/restart и точные отрицательные случаи. Он не доказывает отсутствие любой мыслимой композиции и не называет корректное restart-поведение багом. Его результат — доказательство, что проверенные существующие пути не реализуют необходимый binding. Список методов цепочек Service/M3 сохраняется для независимого поиска scope-preserving альтернативы.

## Почему нельзя «исправить только тест»

Нельзя снимать checksum/owner/epoch guards recovery, сохранять активные transport sessions в restart DTO, переписывать `_players`/`_ownership` снаружи, копировать whole Item Graph на B или оставлять M3 реальным владельцем и рисовать чужую authority в HUD. Также нельзя объявить весь агрегат одним игроком. Такой патч скрывает отсутствие продуктовой интеграции.

## Минимальный следующий bounded repair — после согласования scope

### A. Live-player transfer port у существующего canonical owner

Проектирование/реализация отдельного live handoff API рядом с имеющимися player/input/replay owner-компонентами. Restart API остаётся побайтно и семантически независимым. Frozen transfer-пакет содержит строго определённый player carrying domain, identity/session bindings, input watermark и относящийся к нему replay-срез. Каноническая истина остаётся в существующих владельцах, не в DTO.

Нужны явные source freeze, read-only target staging/validation, привязка warm-checksum к SM1 ownership commit, source retirement/fencing, target activation и fail-closed abort/retry semantics. Caller не может объявить себя владельцем присланным SHA/epoch. Не допускается перенос несвязанного игрока, глобального Item Graph или чужого replay.

### B. Binding существующих M3 runtime и SM1

Все реальные mutation/tick admission routes должны проверять текущую выдачу authority; snapshot-only fence недостаточен. Gateway сохраняет внешние transport session/endpoint и переключает backend route по проверенному commit. Ввод, накопленный около границы, имеет bounded queue, однозначный watermark и не исполняется одновременно на обоих владельцах. M3 replica/prediction обрабатывает переход корректно, а визуальные Node/Camera не заменяются.

### C. Приёмочный сценарий

Пять процессов или документированная существующая топология, один общий scene path. A проходит A→B→A, B независимо двигается до/во время/после переходов; затем роли меняются. Snapshot/position/input/replay доказательства снимаются с обоих canonical owners и обоих клиентов. Проверки: отсутствие reconnect/respawn; no-write на frozen/retired source; no-write на warm target; corrupt/missing warm receipt; stale epoch; replay/conflicting replay; чужой игрок/предмет не мигрирует; два независимых управления; неизменные камеры/тела.

### D. Нерегрессия и роли

MVP1/MVP2, SM1/P7.6, затронутые player/Item/replay/fixed-tick tests; full Harness/PC0 и требуемая world/core регрессия. Exact-head evidence и свежие независимые Reviewer/Verifier. Только потом leaf `MVP_SEAM_NO_RECONNECT_OR_RESPAWN`; whole MVP остаётся отдельной приёмкой.

## Запрашиваемая граница разрешения

Текущий WO разрешает composition paths, но содержит stop condition `New canonical owner or foundation change required`. Нужен отдельно утверждённый bounded amendment, разрешающий минимально необходимый **live transfer API и M3/SM1 binding внутри существующих owners**, с заранее согласованным списком файлов. Это не разрешение создавать нового canonical owner, менять ownership registry, отключать проверки, делать merge в main, менять MVP4–MVP8 или переводить весь MVP в ACCEPTED.

После независимого рассмотрения preflight следует либо найти доказанную scope-preserving композицию и продолжить прежний WO, либо оформить этот конкретный human scope gate. До этого runtime не меняется и MVP3 не отмечается VERIFIED.
