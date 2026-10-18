# FABRIC R5.6.1 R1 — Ubuntu final-acceptance campaign (2026-10-18)

## Identity / reproducibility

- PR: https://github.com/rootfabric/distributed-world-simulator/pull/774 (OPEN / DRAFT at start of acceptance).
- PRODUCT_HEAD: `fd83b61f87d27ba812fe058c6d3a728c4d54588e`.
- PRODUCT_TREE: `000f15d373b396520042b663b59fc84c734180c9`.
- RED_PARENT: `ee1fa655981bba4c7adadd3e7d1d64b3635dfae1`.
- R5.5 research merge BASE: `e74c20725a760e56cac01ffd9eaf39a5e9ad5a90`.
- Canonical Linux Godot: `4.7.1.stable.double.custom_build.a13da4feb`, SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
- Source reconstructed in a new Git repository from verified SHA256 Git bundles (R5.4, R5.5 R3/R4, R5.6.1 R1 and Narrow Repair). Separate detached reviewer/verifier worktrees at exact HEAD and TREE; tracked trees clean. Exactly six R1 Narrow Repair paths versus RED_PARENT; closed R5.1–R5.5 and Construction/Matter kernels unchanged.

## Fresh Linux exact verifier — PASS

Ran unmodified `RUN_FABRIC_R5_6_1_TESTS.sh` from dedicated `work/verifier` checkout. Exit code **0**; all import/parse/fatal checks pass:

| Gate | Result |
|---|---|
| R5.6.1 sample | `3 × 203/0` |
| Byte-for-byte sample result | MATCH |
| Source-admission narrow | `26/0` |
| BRIDGE-4 | `49/0` |
| Strict collector v2 | `FABRIC_R5_6_1_EVIDENCE=PASS` |
| HEAD/TREE/engine before vs after | MATCH |
| SHA256SUMS | `11/11` files verified |

Deterministic result hash: `29defdc33cb1192b9e1577517561c6fcc0f5693daa889deebe585ab8816e043b`.

## Adversarial code review and independently executed falsifiers

Used **a separate fresh reviewer worktree**, exact same source identity and binary. No product edits; all reviewer falsifier scripts untracked. These two tracks are independently executed, but orchestrated within **one assistant session**; do not misrepresent them as two independently appointed reviewers.

1. Original reviewer F1/F2, exact original test bytes (SHA256 `718da76f25a17abfeb9f98d904a4377f0bc1261c3ca6a952611d1ee30ea9bfb0`): original R1 `ee1fa655...` **RED** (exit 1, `checks=9`, exactly 3 expected assertion failures: spoof Store, spoof observation, forged pending observation). Repaired R1 `fd83b61f...` **GREEN** (exit 0, `checks=7`, `failures=[]`, `duck_store_start_accepted=false`, `forged_pending_observed=false`, `R56_PENDING_PROVENANCE_MISMATCH`).
2. **New independent falsifier**, authored for this acceptance, previously absent from product tests: `review_r56_1_novel_canonical_admission_falsifier.gd`, **27/27 PASS**, exit 0. Attack cases:
   - malicious mutation of the *returned* caller-owned `read_binding()` DTO (`binding.checksum`, nested graph edge conductance and event list): **no alias** to live source or derived graph;
   - genuine Store applies a different valid `SET_BOND_STRENGTH` mutation under **the same event ID** as pending `BREAK_BOND` (without changing `_pending`): rejected `R56_AUTHORITATIVE_SUCCESSOR_MISMATCH`, no derived publication; old representation fenced stale, and explicit new Session can correctly rebind to actual authoritative successor;
   - after a correct external commit, an observation with changed Matter returns `R56_MATTER_CHANGED_REBIND_REQUIRED`, without publication; unchanged Matter retries succeed exactly once and match an independently compiled BRIDGE-4 oracle;
   - a subsequent external owner event without session prepare invalidates the old derived binding, preserving prior event count.

## Reviewer assessment

- **SOUND within the explicitly trusted in-process R1 scope**: exact Godot script identity (not duck type), captured Store instance ID, lexical capture of original pending proposal hash/event/source/store at prepare, guard before external source acceptance, explicit canonical successor comparison, rollback/no intermediate publication, stale/read fencing, exact-once observation under live session.
- **CONCERN (non-blocking for R1):** a genuine Store object is not a cryptographically authenticated remote owner; owner-signed durable event receipts and cold-restart exactly-once belong to R5.6.2. The `_prepared_admission` Callable and executable session internals are trusted and can be replaced by arbitrary privileged code in the same process (not a security boundary). Cost remains O(N) for graph recompilation / source hashing and not O(local). Matter/authority changes require explicit caller rebinding; no automatic remote change subscription. Concurrent mutation races are not in this tested R1 scenario.
- **DEFECT/BLOCKER discovered in this Ubuntu acceptance: 0**, under those bounds.

## Gate interpretation and decision

- `UBUNTU_EXACT_VERIFIER = PASS`.
- `UBUNTU_SEMANTIC_REVIEW = PASS_WITH_NONBLOCKING_FINDINGS`.
- `WINDOWS_IMPLEMENTER_EXACT = PASS` (reported separately in PR comment 6218176111, not reverified from Windows ZIP in this Ubuntu runtime).
- `FRESH_SEPARATE_ACTOR_WINDOWS_REVIEWER/VERIFIER = PENDING`.
- **FINAL MERGE_READY = false** until the independent Windows acceptance process closes these gates and a distinct human merge authorization is provided. No merge and no changes to `main` or PRODUCT_HEAD.

## Evidence

Archive: `FABRIC_R5_6_1_R1_UBUNTU_FINAL_ACCEPTANCE_EVIDENCE.zip` includes the exact Linux verifier raw logs and SHA256SUMS, reviewer RED/GREEN and novel falsifier raw logs, reviewer-owned source scripts, and acceptance report. Paths inside archive are relative. Complete SHA256SUMS verified before publication.
