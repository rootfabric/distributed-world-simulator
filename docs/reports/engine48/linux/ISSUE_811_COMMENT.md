ENGINE48_LINUX_R2_WORKER_REPORT

BUNDLE_PATH = /home/rdpuser/DWS-Transfers/engine48-linux-r1.bundle
BUNDLE_SHA256 = 2ae4652b8bcca9477b5fe17d7a9534b26e37de4967f190f4a2ad7f3a9684eff9 (49 972 bytes, git bundle verify OK)
EVIDENCE_ARCHIVE = /home/rdpuser/DWS-Transfers/engine48-linux-r2-evidence.tar.gz
EVIDENCE_ARCHIVE_SHA256 = в sidecar /home/rdpuser/DWS-Transfers/engine48-linux-r2-evidence.tar.gz.sha256 (4 658 276 bytes, финальная сборка, 207 файлов, redaction-скан чист; sidecar публикуется рядом с архивом)

REMOTE_BRANCH = feature/engine48-linux-r1 — **ОПУБЛИКОВАНА** (не force, создана с этой машины
через существующий SSH-ключ GitHub-аккаунта rootfabric; HTTPS PAT read-only → 403).
Подтверждение GitHub: `git ls-remote` и свежий клон дают HEAD 7aaa7fa9ebcabeeca33f15696002ff3907c22ffb,
TREE 0d49082be99b0bb125d26c28f45ac19840426f0d, ровно 7 коммитов поверх a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9
(BASE_TREE 3c0a04c78eca918717e8e836b1c1bf2836cb5596), ancestry OK, tracked-clean.
Workflow #810 (run 39869252376, queued) больше не нужен для публикации: при запуске получит
«Everything up-to-date» (тот же SHA), конфликтов нет.

DRAFT_PR_URL = EXTERNAL_TOOL_AUTH_REQUIRED (создание PR требует PAT со scope pull-requests;
готовое тело — docs/reports/engine48/linux/DRAFT_PR_BODY.md в evidence-ветке diag/engine48-linux-r2-report;
маршрут: feature/engine48-linux-r1 → feature/engine48-beta1-double-migration-r1, НЕ main)
EVIDENCE_URLS = ветка diag/engine48-linux-r2-report (текстовые отчёты+логи, коммит поверх изданного tip);
полный архив /home/rdpuser/DWS-Transfers/engine48-linux-r2-evidence.tar.gz + SHA256 выше
GODOT_EDITOR_SHA256 = 4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f
  (значение 25047b82… из текста задания на машине не найдено; все durable-артефакты R1 согласованно указывают на 4d72a93e…, см. ENGINE48_UBUNTU_R2_PUBLICATION_ADDENDUM.md §2)
LINUX_TEST_VERDICT = UBUNTU_EXECUTOR_PASS (R1) + независимый перезапуск R2: 7/7 headless PASS на свежем worktree
  изданного tip, cold import PASS, parity MW10 = 201/53 assertions подтверждена прямыми прогонами на ОБОИХ
  движках, M7 live = PASS substance (2 peers, 0 script errors, acceptance 55/0 на retry), REGRESSIONS_48 = NONE_FOUND
INDEPENDENT_REVIEW_STATE = FINDINGS_REPORTED (полный отчёт verification/INDEPENDENT_VERIFIER_REPORT_R2.md в evidence-ветке;
  findings не блокируют миграцию: B8 — SHA 25047b82… из work order на машине не найден (реальный 4d72a93e…);
  F-1 — M7 result=PASS недостижим через STOP (SIGTERM/SIGKILL обходит runtime stop(), m3_dedicated_server_runtime_p2.gd:1656-1658);
  F-2 — M7 тест-скрипт возвращает exit 0 при failures; F-3 — разовый флак конвергенса, retry 55/0)
REAL_GPU = INSUFFICIENT_EVIDENCE (llvmpipe software GL / Xvfb :99; GUI-доказательство техническое только)
M3_CLIENT_CONNECT_TIMEOUT = PRE_EXISTING_REPORTED / ISSUE_804 (paired 4.7.1 = идентично; вне ENGINE48-миграции)
PUBLICATION_VERDICT = EXTERNAL_TOOL_AUTH_REQUIRED
  (ветка опубликована и подтверждена GitHub — PASS; Draft PR + комментарий в #811 требуют
   PAT со scope pull-requests/issues: локальный PAT read-only → 403; SSH-ключ даёт только
   git-транспорт. Готовые тексты: DRAFT_PR_BODY.md, ISSUE_811_COMMENT.md — вставить API-исполнителем.)
NEXT_ACTION =
1. API-авторизованный executor: открыть Draft PR feature/engine48-linux-r1 → feature/engine48-beta1-double-migration-r1 (тело в DRAFT_PR_BODY.md), вставить этот отчёт в #811, cross-link в #794/#804/#810.
2. Windows-маршрут #810 более не требуется для публикации Linux-ветки (push выполнен напрямую; workflow publication при запуске получит «Everything up-to-date», конфликтов нет).
3. Интегратор: свести Linux PR с Windows #806/#810; merge — human gate.
4. Findings B8/F-1/F-2/F-3 независимого Verifier — в repair/документацию harness (механика M7 STOP/result и exit-код тест-скрипта; не миграция движка).
5. M3_CLIENT_CONNECT_TIMEOUT (#804): PRE_EXISTING paired на обоих движках; ремонт отдельно от ENGINE48-миграции.
