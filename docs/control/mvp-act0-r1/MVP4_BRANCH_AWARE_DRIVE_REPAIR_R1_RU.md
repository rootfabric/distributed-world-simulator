# MVP4 — branch-aware CONTROL_DEVELOPMENT repair R1

## Durable resume anchor / bounded Repair Map

Parent: `V0-MVP-R1-WO-001`, epoch `E2026-09-09-V0-MVP-R1`, `IN_PROGRESS`.

Frozen product: `e37f81821e98a4d00b04ea414722e550b328cd47`, tree `bcbde9961e701f1e2c728f6f7a74f9df2d334aed`, branch `feature/v0-mvp-playable-seamless-planet-r1`.

Validation-only carrier: `control/v0-mvp4-branch-aware-drive-r1`. Этот carrier не является новым runtime subject и не двигает feature/main. Следующий агент должен сверить live refs и результаты CI; не полагаться на статус из чата.

Подтверждённый дефект: run `34808149795`, job `103869473611`, `CONTROL_DEVELOPMENT -Status` вернул `GIT_STATE_INVALID / GIT_BRANCH_UNAVAILABLE`, exit 4. `actions/checkout` по SHA оставляет detached HEAD. Производственный Harness правильно требует имя зарегистрированной branch. Исправление принадлежит CI orchestration, не `state_builder` и не runtime. Предыдущий HA identity repair уже в exact product; его здесь не меняем.

Разрешённая поверхность: только `.github/workflows/mvp4-shared-dig-validation.yml` и этот документ. Runtime, тестовые критерии, Work Order, HA и события 0001–0013 не меняются. Risk parent остаётся CRITICAL; этот bounded infrastructure repair не понижает требования independent review/verification.

## Исправление

- Сначала checkout immutable exact SHA; проверка HEAD, TREE, clean tracked state и совпадения live feature ref.
- Carrier исполняет public CONTROL_DEVELOPMENT именно на frozen `e37f8182`, а не на своём новом commit; manifest отдельно записывает carrier и subject.
- После pinned dependencies отрицательный production control воспроизводит detached HEAD: ожидается только exit 4 / GIT_BRANCH_UNAVAILABLE, raw stdout/stderr сохраняются.
- Имя local branch сверяется с существующим Work Order. В disposable runner выполняется `git checkout -B` на ТОМ ЖЕ exact SHA. До/после HEAD/TREE и tracked state должны совпадать. Никаких remote writes, новых runtime-коммитов или поддельного branch override в Harness.
- Затем реальные `-Status`, `-Resume`, `-Drive`: требуются exit 0 и output ok=true для каждого. Новый FAIL не маскируется и не называется PASS.
- SHA-256 manifest связывает raw control logs, actual branch, subject HEAD/TREE, canonical main, workflow carrier SHA/ref и run/attempt. Это machine evidence, не независимый verdict.

## World/core — не перезапускать без причины

Текущий exact run `34808149795`, world/core job `103869473878`, уже исполняет неизменённый `RUN_WORLD_REGRESSION_TESTS.ps1` на `e37f8182`. Carrier не запускает дубликат и не отменяет этот run. Runtime `exact` job `103869473720` и Project Control `34808152633` были SUCCESS при старте ремонта.

Перед заявлением WORLD_CORE PASS независимо проверить terminal job result и raw artifact:

1. `world-regression-summary.json`: passed=true, отсутствуют failed/nonzero steps, совпадает coverage/discovery.
2. `test_v0_p6_thirty_minute_soak`: exit 0, passed=true, duration_seconds >= 1800; никакой замены smoke.
3. `main_scene_cli_all`: exit 0, passed=true.
4. Manifest subject HEAD/TREE = frozen product, pinned Godot SHA `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`, tracked_after пуст; все файлы повторно перехешированы.

Старый combined workflow останется FAILURE из-за исторического control-drive job даже при SUCCESS world/core. Его не перекрашивать: ссылаться отдельно на world/core job и исправленный control-only carrier.

Следующий шаг после обоих machine PASS: fresh independent review/verification по exact evidence и bounded workflow diff. Не создавать PREDICATE_VERIFIED, не объявлять MVP4 CLOSED, не merge. Parent/whole-MVP/main acceptance остаются незавершёнными.
