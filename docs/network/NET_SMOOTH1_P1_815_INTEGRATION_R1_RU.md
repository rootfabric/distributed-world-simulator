# NET-SMOOTH1 P1 + #815 integration R1 — no merge

Exact parent is Draft PR #852 repair head d34b8166d596ca3485e673dad6be2086e2d2c804; direct ancestor frozen Draft #840 R2.2 HEAD fb513173df4c73c607fd8cb6680ad108c76f41ac.

This separate integration branch adds native #815 negative tests from Draft #854 latest 4da61be25365e0f7c77ab98595bb5b32e4ef8611 to the already reviewed/repaired P1 real batching source. It uses the R2.2-aware strict reducer from Draft #853, already present in #852, plus strict P1 batch accounting. Product authoritative runtime code unchanged relative to #852; only tests/CI/docs/focused registry added.

Both pinned native double Windows and Linux CI must pass on the SAME HEAD; source-only checks never substitute for native tests. Source/native toolchains and Quaternius provenance remain exact, no FPS threshold changes.

Known blockers remain: P1 GUI 3x120s on THIS integration HEAD not executed; older P1 GUI matrix PERF_FAIL, true historical checksum #815 ROOT_CAUSE_UNKNOWN (10x fresh JOIN without incidents), Project Control candidate-main-drift and SEAM-E2E independently unaccepted. No human merge approval, no change main.

READY_FOR_MERGE=false.
