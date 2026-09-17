# FABRIC R4.1 — FRESH INDEPENDENT VERIFIER R1

```text
ROLE         = VERIFIER
SUBJECT_HEAD = 3afd12e9296b6533b25e7466cec6b4e2151daceb
SUBJECT_TREE = dc8d9c8c9bf0e6905ad3c581f75893ccd195078e
STATUS       = PENDING_EXACT_CI
```

Verifier-owned oracle не является product acceptance test. Он добавляет отдельный аналитический branched-graph reference (`279/469`, `265/469`, bridge current `2/469`), рекурсивно запрещает non-finite значения в successful details и независимо проверяет несколько overflow stages: RHS assembly, voltage/current, power и reciprocal conductance.

Diagnostic check отдельно доказывает, что failed PERF matrix имеет пустой hash и сохраняет вложенный primary error.

После primary oracle verifier обязан переиграть exact frozen R4.1 product runner в detached worktree на canonical Linux double. До успешного self-hosted run этот документ не является PASS и не разрешает R4.2 freeze.
