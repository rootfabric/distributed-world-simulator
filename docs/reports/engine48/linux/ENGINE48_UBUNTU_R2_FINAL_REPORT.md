# ENGINE48_UBUNTU_R2_FINAL_REPORT

Дата: 2026-10-23 (UTC) · Executor: standalone Ubuntu 22.04.5 (`outenemy`), та же машина, что выполнила R1.
Миссия: восстановить и опубликовать выполненную Linux-работу по миграции Godot 4.8 Beta 1, передать в PR #794, подготовить независимую верификацию (durable Work Order: GitHub Issue #811).

```text
ENGINE48_UBUNTU_R2_FINAL_REPORT

BASE_HEAD = a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9
BASE_TREE = 3c0a04c78eca918717e8e836b1c1bf2836cb5596

LOCAL_BRANCH = repair/engine48-linux-runner-guards-r1
LOCAL_TIP_HEAD = 7aaa7fa9ebcabeeca33f15696002ff3907c22ffb
LOCAL_TIP_TREE = 0d49082be99b0bb125d26c28f45ac19840426f0d
SEVEN_COMMITS =
  29d2e4af4678745d59e2dbc7a4f8902121851702 fix(engine48): pin Linux runner guards to Godot 4.8 beta1 double build
  231b3e9b2b7f7d7810c6729dd59b4a1db3ed075d chore(engine48): adopt Godot 4.8 generated import metadata and script UIDs
  24fc10ee1dedfe5b49d8b819fe7ef6591f5c0750 fix(engine48): pin Linux graphical integration engine to 4.8 beta1 double
  c1d3070fec0cd2cb87d002bb8bd3205bd0d7a4ca fix(engine48): allow Xvfb location override in Linux SM1 graphical gates
  5f71900ff2668f32b42588581b80eaa89e1c876e fix(engine48): resolve Xvfb via XVFB_BIN in Linux graphical process gates
  841cf13e2c3435a04da30a65062a722ed6f704c2 fix(engine48): align P7.1 gate summary pins with 88-assertion current test
  7aaa7fa9ebcabeeca33f15696002ff3907c22ffb fix(engine48): align MW10 suite marker pins with current assertion counts

GODOT_VERSION = 4.8.beta1.double.custom_build.4d10419ca (x86_64, precision=double; upstream 4d10419cacd6…, tarball SHA256 6d49c02e…)
GODOT_EDITOR_SHA256 = 4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f
GODOT_TEMPLATE_DEBUG_SHA256 = af1e29d1c53688786e0551c54b1d1105300955302180b02a7fdf5711d46ff897
GODOT_TEMPLATE_RELEASE_SHA256 = fffb8f53f85bda1757572638d88386e80f90a7e0abf1be61638544197f4506e7
  (примечание: значение 25047b82ab92… из текста задания на машине не воспроизводится; все durable-артефакты R1 и фактический бинарник согласованно равны 4d72a93e… — см. ENGINE48_UBUNTU_R2_PUBLICATION_ADDENDUM.md §2; независимая перепроверка R2 подтверждает)

BUNDLE_PATH = /home/rdpuser/DWS-Transfers/engine48-linux-r1.bundle
BUNDLE_SHA256 = 2ae4652b8bcca9477b5fe17d7a9534b26e37de4967f190f4a2ad7f3a9684eff9 (49 972 bytes; git bundle verify OK; требует BASE a936412c)
EVIDENCE_ARCHIVE = /home/rdpuser/DWS-Transfers/engine48-linux-r2-evidence.tar.gz
EVIDENCE_SHA256 = см. sidecar /home/rdpuser/DWS-Transfers/engine48-linux-r2-evidence.tar.gz.sha256 (архив содержит 207 файлов, redaction-скан чист, включает копию bundle; собственный SHA не вносится внутрь архива во избежание циклической ссылки)

PUSH_VERDICT = PASS
REMOTE_BRANCH = feature/engine48-linux-r1 (создана без force; проверена свежим клоном: HEAD/TREE/7 коммитов/ancestry совпадают)
REMOTE_TIP_HEAD = 7aaa7fa9ebcabeeca33f15696002ff3907c22ffb (подтверждён `git ls-remote` и клоном с GitHub)
DRAFT_PR_URL = EXTERNAL_TOOL_AUTH_REQUIRED — ветка опубликована, но создать Draft PR с этой машины нельзя:
  REST API требует PAT со scope pull-requests (локальный PAT read-only → 403), gh не авторизован,
  SSH-ключ даёт только git-транспорт. Готовое тело PR: docs/reports/engine48/linux/DRAFT_PR_BODY.md
  (evidence-ветка diag/engine48-linux-r2-report). Маршрут: API-авторизованный executor открывает PR
  feature/engine48-linux-r1 → feature/engine48-beta1-double-migration-r1 (НЕ main).

HEADLESS_TESTS = PASS (R1: матрица 8 suites, MW0 2011 / MW4 187 / MW10 201+53, SM1 L0/fault-matrix/graphical/authority-recovery/gateway-restart, P7.2–P7.5, PLAYABLE_SEAMLESS, C22; строгие пины сохранены; независимый перезапуск R2 — см. INDEPENDENT_VERIFICATION)
M7_MULTIPLAYER = PASS (R1: dedicated server + 2 клиента, LOCAL и BAD_MOBILE, reconnect без дублирования identity, server-restart с восстановлением; артефакты runtime/m7-network-playground/20261021-030410, -030653)
PERF_PAIRED = NO 4.8 REGRESSION (3+3 paired vs локальный 4.7.1: worst server stage −7.7%, CPU parity, RSS +2.9% стабильно, FPS p50 16/16 llvmpipe-bound; таблицы perf/PERF_PAIRED_RESULTS.md)
REAL_GPU_EVIDENCE = INSUFFICIENT_EVIDENCE (llvmpipe software GL под Xvfb :99; GUI-доказательство техническое только; аппаратная GPU-верификация — отдельный шаг)

INDEPENDENT_VERIFICATION = FINDINGS_REPORTED (свежий независимый Verifier, отдельная сессия, без доступа к контексту имплементера; полный отчёт verification/INDEPENDENT_VERIFIER_REPORT_R2.md + 16 сырых логов)
  - GIT_IDENTITY = PASS; GUARDS_INTEGRITY = PASS (ослаблений нет); ENGINE_STRICT_CHECKS = PASS (4/4 sha256, версии точные);
  - COLD_IMPORT_FRESH_TIP = PASS (свежий worktree изданного tip: exit 0, 0 ошибок);
  - HEADLESS_RERUNS 4.8 = PASS 7/7 (MW0 2011, MW4 187, C22 29+52+35+75, P7.2 GREEN, P7.3 GREEN c 88-пином живьём, PLAYABLE_SEAMLESS, SM1_L0);
  - PARITY 4.7.1 = подтверждена прямыми прогонами: MW10 = 201/53 assertions на ОБОИХ движках (exit 0);
  - M7_MULTIPLAYER_LIVE = PASS substance (READY, 2 peers, 0 script errors, acceptance 55/0 на retry);
  - REGRESSIONS_ATTRIBUTABLE_TO_48 = NONE_FOUND; REAL_GPU_EVIDENCE = INSUFFICIENT_EVIDENCE;
  - Findings (не блокеры миграции, в repair-канал): B8 — SHA `25047b82…` из текста задания не найден на машине (реальный editor `4d72a93e…`);
    F-1 — терминальный `result=PASS` M7 недостижим через STOP-механику (SIGTERM/SIGKILL обходит runtime `stop()`, m3_dedicated_server_runtime_p2.gd:1656-1658);
    F-2 — M7 тест-скрипт возвращает exit 0 даже при failures; F-3 — разовый флак конвергенса (не воспроизведён, retry 55/0).
PUBLICATION_VERDICT = EXTERNAL_TOOL_AUTH_REQUIRED
  (Git-публикация ветки — PASS, подтверждена GitHub; недоступны с этой машины: создание Draft PR,
   комментарии в #811/#804/#794 — PAT read-only, 403; SSH-ключ даёт только git-транспорт.
   Все тексты для вставки подготовлены: DRAFT_PR_BODY.md, ISSUE_811_COMMENT.md — в evidence-ветке.)

NEXT_ACTION =
  1. API-авторизованный executor (Windows-host или любой PAT с pull-requests:write): открыть Draft PR
     feature/engine48-linux-r1 → feature/engine48-beta1-double-migration-r1 (тело готово), вставить
     ISSUE_811_COMMENT.md в #811, cross-link в #794/#804/#810.
  2. Workflow #810 (engine48-linux-wsl-branch-publication, run 39869252376 queued) более не требуется
     для публикации Linux-ветки: push выполнен; при запуске workflow получит «Everything up-to-date»
     (тот же SHA), конфликтов и force нет.
  3. Интегратор: свести Linux Draft PR с Windows #806/#810; Linux engine pins уже 4.8.beta1.double;
     merge — human gate (не выполняется этим executor'ом).
  4. Дефект #804 M3_CLIENT_CONNECT_TIMEOUT: paired 4.7.1 = идентично; PRE_EXISTING_REPORTED; ремонт
     ведётся отдельно от ENGINE48-миграции.
  5. Findings независимого Verifier (B8, F-1, F-2, F-3) — в repair/документацию harness: F-1/F-2
     касаются M7 STOP/result-механики и exit-кода тест-скрипта (не миграции движка).
```

## Сводка проверки lineage (раздел 3 задания)

| проверка | результат |
|---|---|
| `git rev-parse $BASE` | `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9` — совпадает |
| `git rev-parse $BASE^{tree}` | `3c0a04c78eca918717e8e836b1c1bf2836cb5596` — совпадает |
| tip начинается с `7aaa7fa9e` | да: `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb` |
| коммитов поверх BASE | ровно 7 |
| `merge-base --is-ancestor` | OK |
| tracked-clean (`--porcelain --untracked-files=no`) | 0 строк |
| ослабление тестов / продуктовый код | не обнаружено: пины версии→4.8 (строгие), XVFB_BIN override с fallback, счётчики assertions только увеличены (201/53/88), `scripts/` не менялся (только новые `.uid`), ни один порог/таймаут не ослаблен |

## Окружение и ограничения

- `/mnt/c` отсутствует (standalone Linux, не WSL) → transfer-каталог `/home/rdpuser/DWS-Transfers`.
- `pwsh` не установлен → `CONTROL_DEVELOPMENT.ps1` (Windows-контрольная поверхность) на этой машине неисполним; миссия ведётся по durable Work Order GitHub #811.
- Публикация выполнена существующим SSH-ключом GitHub-аккаунта `rootfabric` этой машины; токены/ключи с Windows не копировались.
- Raw GUI/perf evidence остаётся локальным архивом (upload в GitHub Actions недоступен с этой машины); в Git закоммичены только текстовые отчёты/логи (evidence-ветка), большие бинарные архивы в репозиторий не вносятся.
