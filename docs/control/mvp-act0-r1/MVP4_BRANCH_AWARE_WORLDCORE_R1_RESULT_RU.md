# MVP4 — branch-aware control и terminal world/core: machine PASS

Выполнен запрос на два machine gate. Это не независимый Verifier PASS и не закрытие MVP4.

## Неизменённый продукт

- HEAD `e37f81821e98a4d00b04ea414722e550b328cd47`.
- TREE `bcbde9961e701f1e2c728f6f7a74f9df2d334aed`.
- Ветка продукта `feature/v0-mvp-playable-seamless-planet-r1` не двигалась.
- Workflow-only repair `f862491323e3d2c28769b2d8c341c3e0d5895b3d` на `control/v0-mvp4-branch-aware-drive-r1`; изменены только именованный workflow и Repair Map. Runtime, тесты, HA, Work Order и event ledger не менялись.

## Результаты

`CONTROL_DEVELOPMENT`: run `34813946764`, job `103880629301` — SUCCESS. Production negative control на detached HEAD воспроизвёл exit 4 / GIT_BRANCH_UNAVAILABLE. После создания локальной ветки с именем из Work Order на том же HEAD/TREE `Status`, `Resume`, `Drive` вернули exit 0 / ok=true. Никаких remote branch writes из CI. Artifact `10335682497`: 6/6 raw-файлов независимо перехешированы, совпадают размеры и SHA-256, лишних/отсутствующих файлов нет.

Full world/core: существующий run `34808149795`, job `103869473878` — terminal SUCCESS. Неизменённый runner выполнил 335 обнаруженных test scripts / 340 этапов, 0 failures, 0 nonzero exits. Literal `test_v0_p6_thirty_minute_soak`: 1804.199 s, exit 0; в raw log есть `V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME`. `main_scene_cli_all`: PASS, exit 0. Завершение suite: `2026-09-14T06:31:05.9177100Z`. Artifact `10335936790`: 1761/1761 raw-файлов независимо перехешированы, совпадают размеры и SHA-256; manifest связывает точный HEAD/TREE, Godot и чистый tracked checkout.

Проверка архива выполнена локальным Python zipfile/hashlib/json без исполнения проектного кода из артефактов. Уникальность test step проверяется по (kind, target, name): два `test_controller_profiles` — разные scripts в core/ и integration/, а не повтор одного этапа.

## Не скрывать исторический FAIL

Исходный combined run `34808149795` остаётся FAILURE из-за старого control-drive job `103869473611`. Его не нужно перекрашивать или перезапускать весь долгий suite: terminal world/core PASS и corrected control PASS имеют один product HEAD/TREE и отдельные durable artifacts. Runtime job `103869473720` на том же subject также SUCCESS.

## Граница завершения

Старый Verifier FAIL на `f7dc8000` не переписан. Новый независимый verdict на `e37f8182` ещё требуется, включая оценку workflow diff и evidence. Не выпускался `PREDICATE_VERIFIED`, MVP4 не объявлен CLOSED, merge не выполнялся. `Drive` возвращает `INTEGRATOR / CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED`; parent остаётся IN_PROGRESS.

Полные SHA-256, raw locators и точные результаты: соседний `MVP4_BRANCH_AWARE_WORLDCORE_R1_RESULT.json`. Evidence-only ветка не должна менять frozen repair или продукт. Следующее действие — fresh independent review/verification, затем отдельный coordinator closure только при корректном verdict.
