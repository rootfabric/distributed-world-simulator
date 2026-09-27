# MVP7 — reconnect, restart и восстановление canonical state

## Dispatch и границы

Пользователь: «реализуй MVP7». Единственный действующий Work Order — `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`, состояние `IN_PROGRESS`. Работа выполняется напрямую, без запуска Codex-агентов.

Вход: feature `8d10bcf896547476d6f9a1db8769fa8c41110291`; закрытый MVP6 product `1d51b410925407ad1f83dc4ffa37b8a909bb6811`, tree `fb51a7cab464404fc843cb1da2fac5419a1c6ee3`. Событие `0021` закрывает только MVP6. Ни runtime/main merge, ни whole-MVP acceptance этим dispatch не разрешены.

## Проблема и выбранная композиция

MVP6 доказал native carrying и in-process rehydration. Это не доказывает реальную потерю transport-соединения, завершение процесса authority, запуск нового процесса и восстановление продолжающегося gameplay.

Переиспользуются существующие владельцы: M6 AuthoritativeRecoveryRepository/Coordinator для gameplay и replay, canonical M4 Item Graph для identities/inventory/equipment/container, MW5 MatterStateCoordinator для terrain/material receiver/journal, M0 Construction adapter и C17 для Construction/ownership/terminal commands. MVP7 добавляет orchestration и recovery admission, а не второй Item Graph, новую terrain truth или альтернативный storage engine.

Сначала проверяется native recovery surface с fail-closed preflight и exact replay, затем эта поверхность включается в живой сценарий на MVP6-наследнике. Reconnect и restart — разные проверки. После restart transport-сессии и открытые container leases не считаются durable; новый клиент получает текущий authoritative snapshot и новую session/ownership binding. Исторический operation ID не разрешает обход аутентификации.

Для проверяемого restart используется подтверждённый quiescent checkpoint. Нельзя называть проверку восстановлением всех ещё не checkpointed операций или произвольного power-loss. Частичный/несогласованный recovery не должен открывать admission. Доказательство server/world restart требует разных PID и сохранённых на диске данных, а не переименования in-process теста.

## Сохраняемые условия

- Все семь recovery sub-predicates родительского Work Order обязательны.
- Предметы и Construction не создаются заново из тестовых ожиданий при восстановлении.
- Сначала восстановление и проверка identity/checksums/replay, затем новые команды.
- Повтор material output и Construction ADD/REMOVE не создаёт новых identities и не расходует ресурс повторно.
- Производные terrain/Construction collision восстанавливаются из canonical state на обоих клиентах.
- Late join или resync получает актуальный snapshot, включая изменения после первого восстановления.
- MVP3–MVP6 baseline и frozen owner contracts не ослабляются.

## Изменения и validation scope

Runtime/test/docs располагаются внутри существующих разрешённых MVP paths. Для exact проверки разрешён отдельный job `mvp7-recovery` в уже именованном `.github/workflows/mvp6-native-prerequisite-diagnostic.yml`: только checkout, read-only control, pinned engine, tests и evidence upload. Исторический MVP6 diagnostic job сохраняется без изменения; его PASS не является MVP7 PASS. Новые write permissions, agents, main mutation или изменение owner scopes не разрешаются.

Validation: exact HEAD/TREE и чистый tracked checkout; pinned double Godot `a13da4feb` с проверкой SHA-256; import; focused positive/negative controls; независимые процессы и live graphical baseline; regression на том же candidate. Артефакты содержат команды, exit codes, source hashes, отчёты и SHA-256 manifest. Статус `PREDICATE_VERIFIED` возможен только после живого полного набора и fresh независимых ролей.

## Риски и отвергнутые варианты

Главные риски: смешанный cut между owners, stale session replay, потеря terminal операций, возврат удалённой детали, повторный bootstrap fixtures, устаревшая client projection и clock rollback. Отвергнуты отдельный demo-save, копирование whole graph при seam, mint/top-up после restart, подмена process proof новым RefCounted и самоприёмка по одному зелёному CI.

## Текущее состояние

`IMPLEMENTATION_IN_PROGRESS`. Этот brief не является evidence, verdict или закрытием предиката. MVP8 остаётся следующим отдельным этапом.
