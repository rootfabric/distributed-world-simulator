# MVP4 — coordinator validation-scope correction R1

Основание: пользователь явно поручил реализовать/продолжить MVP4. Fresh Reviewer на `6a4f9cde...`, review `5191157550`, finding `4000014122` верно обнаружил, что локальный implementation brief не расширяет центральный Work Order: `.github/workflows/mvp4-shared-dig-validation.yml` отсутствовал в его write fence. Дополнительно буквальный glob `RUN_V0_MVP_*` не покрывает `RUN_V0_MVP4_SHARED_DIG.ps1`.

В роли coordinator исправляется dispatch/validation scope центрального `V0-MVP-R1-WO-001`: добавить **ровно два конкретных пути**, не `.github/**`, не новые owner-файлы. Остальные allowed paths, forbidden paths, required predicates, issued timestamp, parent state и правила review/verification/merge остаются прежними. Это не Reviewer/Verifier verdict и не выдача независимости самому Implementer.

Workflow выполняет только exact checkout, тесты, сбор логов/PNG и upload artifacts с read-only repository permissions. Никаких commit/push/merge через CI и никакого нового canonical owner. Launcher использует тот же existing native process path. Интеграционные тесты и validation runner уже находились в разрешённых местах.

Предшествующие runs сохраняются неизменными как диагностические данные. Они не превращаются задним числом в разрешённую независимую приёмку. После amendment требуется новый exact run, fresh review и самостоятельная verification. MVP4_PREDICATE_VERIFIED=false; parent=IN_PROGRESS; main_merge=false; whole_mvp_acceptance=false.
