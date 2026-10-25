# CONTROL MVP8 R3 — повторное review и verifier evidence, 2026-10-25

**Проверенный продукт:** PR [#855](https://github.com/rootfabric/distributed-world-simulator/pull/855), HEAD `7510aa4ff81e6d3a13bbfa0872b6f60bfb547621`, TREE `5003355e504c620c7f4bb0413bda6d4f36b9fd8d`.
**Канонический main:** `aac301b9a9a89e027f6d99864437eb750a4202ca` (без изменений). Стек PR #834 → #839 → #845 → #855 остаётся Draft и не слит.
**Общий вердикт:** `SCOPED_TECHNICAL_REVIEW_PASS_WITH_FINDINGS / EXACT_MACHINE_EVIDENCE_VERIFIED / FORMAL_DISTINCT_ACTOR_SIGNATURES_PENDING / MERGE_READY=false`.

## Проверка источника

Сверен настоящий HEAD/TREE #855, unchanged parent и внешний reviewer-only/verify-only diff. Все проверки выполнялись в GitHub Actions на отдельном именованном checkout продукта либо в новых одноразовых worktree. Ни одна ветка проверки не меняет продуктовый HEAD. Исторические Event/Reviewer receipt/witness Git blob: `b27cc80072fcb66cb217004ddad35aeb381d37a0` / `3759b7caf84ef1e49a894ae2d6b5934e676c15b5` / `a2c07a8d7b24346abafa46513ed614b792126a97` сохранены.

## Review — НОВЫЕ adversarial проверки

[GitHub Actions run 40175382790](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40175382790), reviewer-only branch `review/control-mvp8-r3-novel-byte-integrity-r1`, tip `1514336412703d4887ab0c23dce6d82678ebafc1`: **3/3 jobs SUCCESS** (scope, Ubuntu, Windows). Четыре новых теста (4/4 на обеих ОС), не входивших в прежние 402:

- Подлинные event+receipt успешно допускаются.
- `git update-index --skip-worktree`: видимое только в памяти/локальном файле изменение event #0050 отклоняется `EXTERNAL_REVIEW_WITNESS_EVENT_LOCAL_BLOB_MISMATCH`.
- Такое же скрытое изменение Reviewer receipt отклоняется `EXTERNAL_REVIEW_WITNESS_RECEIPT_LOCAL_BLOB_MISMATCH`.
- Изменение только дополнительного переноса строки в Reviewer receipt (JSON семантически тот же, SHA другой) также отклоняется, что подтверждает именно побайтовый, а не семантический Git-контроль.

Новые falsifier-кейсы код PR #855 проходят. Не обнаружено нового **блокирующего** дефекта в узкой границе R3. Это не утверждение об отсутствии дефектов в общем Harness вне этой границы.

[Reviewer raw artifact 12592066521](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40175382790/artifacts/12592066521): внешний SHA256 `f98f66c92a60b1421082c634b3aa1fa1aa60178d0091c629d0af70fc7207246e`, **2/2** внутренних SHA256SUMS MATCH; IDENTITY совпадает с точным продуктом. Windows raw job log подтверждает аналогичные 4/4 PASS.

## Current-refs verifier — СЕГОДНЯ

[GitHub Actions run 40175732931](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40175732931), verifier-only branch `verify/control-mvp8-r3-current-refs-20261025-r1`, tip `fae7021973f5cbda513b49a21eaddc8b2fcef302`: **3/3 SUCCESS**.

- На новых именованных checkout Windows и Linux из exact HEAD/TREE пройдены 20/20 targeted: R3 5, R2 4, R1 6, Evidence Map 5.
- На обеих ОС `-Status` возвращает exit0/ok=true; `-CheckConsistency -Candidate` exit0/ok=true.
- Стандартный PC0 и directional PC0 `overall_health=YELLOW` / `YELLOW`. Это non-RED, **не GREEN**. Остались три WARNING `BRANCH_ADVANCED_SINCE_SNAPSHOT`: `ECO/integration`, `ECO/visual_repair`, `FABRIC/bake`.
- Верификация не подменяет полный Harness suite: полный **402/402** на exact R3 HEAD отдельно подтверждён [Implementer exact CI 40091670412](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40091670412) и [fresh two-worktree CI 40091993517](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40091993517) (оба 3/3 SUCCESS). Код продукта не изменялся между прогонами.

[Current-refs raw artifact 12591534523](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40175732931/artifacts/12591534523): ZIP SHA256 `070a1316365910cd54307fe91d1f766692a2c68f5c0ca8abae0fe19cb47829df`, внутренний SHA256SUMS **10/10** MATCH; raw IDENTITY product HEAD/TREE плюс `MAIN_REF=aac301b9a9a89e027f6d99864437eb750a4202ca`, exact Status/Consistency `ok=true`.

## Ограничения и дальнейшие ворота

1. Настоящие новая reviewer-only и verifier-only автоматические проверки исполнялись на отдельных GitHub-hosted машинах, но управлялись **одной текущей ChatGPT-сессией**. Они НЕ являются двумя отдельно аутентифицированными подписью независимых Reviewer и Verifier в Harness.
2. Scope PASS ограничен PR #855/R3: существующий общий `_validate_event_git_provenance` для других событий вне этого exact Reviewer witness требует отдельного аудита и не должен объявляться всемирно закрытым R3.
3. Все четыре контролирующих PR #834/#839/#845/#855 всё ещё Draft. Для merge — fresh separate-actor role verdict(s), согласование стековых зависимостей, PC0/directional после интеграции и **явное Human merge approval**.
4. На Windows 10 локальный интерактивный Godot/GPU запуск не требуется для R3 (это Python/PowerShell/Git control-plane). Hosted Windows test достаточно для machine regression; локальный независимый агент полезен для отдельного actor signoff, если нужно закрыть формальные Harness-гейты.

**Director/Integrator:** `R3_MACHINE_PASS / TECHNICAL_REVIEW_PASS_WITH_FINDINGS / HUMAN_MERGE_NOT_AUTHORIZED / MERGE_READY=false`. Без merge и без изменения main.