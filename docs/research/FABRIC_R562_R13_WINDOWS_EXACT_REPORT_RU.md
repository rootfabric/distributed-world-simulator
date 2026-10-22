# FABRIC R5.6.2 R1.3 — Windows exact verification (PR #818)

**Вердикт: PASS — FABRIC_R562_R13_WINDOWS_EXACT_PASS**

- Subject: branch epair/fabric-r562-r13-genesis-admission-r1, HEAD d8e8361419b1fbcf0138c4deea18d19accc297f6, TREE 7c5c0a4e6546b4f3f444c8a17582518c099b951e
- Host: Windows, PowerShell 7.6.7, canonical Godot 4.7.1 double 4.7.1.stable.double.custom_build.a13da4feb, SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
- Метод: свежий detached worktree worktrees/fabric-r562-r13-exact-d8e83614, без изменений RUN_FABRIC_R5_6_2_R1_TESTS.ps1 (Windows Work Order PR #818, comment 6340130066), отдельный EvidenceDir.

## Критерии
- Lifecycle 3×628/0 (идентичные логи, 76 negative rejections, 10 commits, 30 cold restarts, 42 disk roundtrips, 14 FULL oracles) — PASS
- Genesis budget: 17-событийный начальный журнал отклонён; bootstrap/recover при 16 событиях успешен (genesis_budget, официальный lifecycle) — PASS
- R2 626/0, COM Recovery 18/0, R1 203/0, BRIDGE-4 49 assertions PASS — PASS
- Импорты: import=PASS, import-recovery=PASS; parse-lifecycle=PASS
- Windows process receipts: 10/10 exit_code=0, argv/process provenance сохранён
- Isolation: RECEIPTS_IN_SANDBOX=42, LIVE_WORLD_LOGS=0 (нет worlds), identity-before == identity-after
- HEAD/TREE после прогона неизменны; SHA256SUMS: 0 расхождений
- Collector: FABRIC_R562_R1_COLLECTOR=PASS

## Результат
- deterministic_result_sha256 = 0804d1dbd4b0c6f0111ed964e5c0a5ceb6d054b699ae9dd2580964742fc587a5 (совпал с ожидаемым, кроссплатформенный дрейф отсутствует)
- EvidenceDir: rtifacts/fabric-r562-r13-5fc86d24557e46668893f6185a429d90
- Evidence ZIP: abric-r562-r13-5fc86d24557e46668893f6185a429d90.zip
- ZIP SHA256: 50edb57a5e9b64647305eb578b7b47a130f3cd7c81be6f51f21891cd021af9e2

Это независимая Windows-верификация. MERGE_READY не изменялся; main, PR #784, PR #800 не затронуты.
