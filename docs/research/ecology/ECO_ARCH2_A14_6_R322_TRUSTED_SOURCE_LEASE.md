# ECO ARCH2 A14.6 R3.2.2 — Full worker validation + exclusive Controller lease

Status: DRAFT, unverified until native Exact and independent verifier. Research LAB-only, explicit opt-in, no WORLD_COMPAT/Earth, no merge.

Parent: PR #813 `a08cc16884f9b7b7449d7e7710053940439146d5`, TREE `94d6cf819b1c044833a834e9b287dcb4504e39a6`. Original R3.2: PR #805, R3.1: PR #798; main frozen `aac301b9a9a89e027f6d99864437eb750a4202ca`.

## Root cause, from Windows report

[Windows Exact #813](https://github.com/rootfabric/distributed-world-simulator/pull/813#issuecomment-6337678504) validated all 4 scales (256 isolated process 6/6), 16 regressions and parity; 256 main-thread final source admission median 759.3 ms / max 895.2 ms, ~99.99% of final poll. Background poll <= 0.2 ms, join 6–15 µs. Single process 256 native crash did not reproduce, exact original cause unknown. Those are R3.2.1 results, not proof of R3.2.2 performance.

## Strict source ownership contract

Godot nested `Dictionary`/`Array` are mutable. No O(1) inspection of a hash/tick can detect an arbitrary unmediated nested mutation. Thus there are **two distinct admission paths**.

1. Untrusted direct OffMain callers (including direct scale fixtures): full `Runtime.validate(state)` still runs on the main thread at the instant of publication. Worker additionally fully validates source and candidate before returning a validation receipt. Late nested tampering rejects even when hash and tick headers are unchanged.
2. LAB Controller-owned frontier only: `ExperimentController` owns `_runtime` and does not hand out mutable aliases through public APIs (`debug_state` returns deep copies). Controller passes an opaque `RefCounted` token, a monotonically increasing generation, option digest and the **identity** of its current runtime to the OffMain worker. Every supported writer and PAUSE/restore/reconfigure invalidates the token. After the worker validates *both* source and candidate and seals a receipt on the exact generation, the main thread performs only an O(1) lease/source-identity/epoch/header/options check. There is no duplication of full `Runtime.validate` on the main thread for this trusted path.
3. The Controller cannot protect arbitrary external code that directly reaches into its private `_runtime` and edits nested members. Such unsupported reflection violates the exclusive lease contract. Never describe the identity check as cryptographic proof against rogue nested aliases. A future lock/immutable-native-structure would be required for protection against arbitrary memory access and shared mutable alias injection.

## Falsifiers and scope

- New LAB tests assert direct-service strict main validation, post-completion untrusted nested tampering reject, forged lease owner reject, exclusive trusted Controller fast admission, worker full source/candidate validation, PAUSE generation revocation, one atomic commit.
- New 4/32/96/256 **test-only injected** controller-owned fixture profiles exercise the real Controller/Workbench `_process` and compare full original Runtime/hash/A8 checkpoint; inject a deep isolated exact fixture *before issuing any lease*. This is not a normal 256-founder UI manifest, not production-scale acceptance.
- Each size runs in a fresh Godot process; all exit codes, stderr and checkpoint profiles mandatory. Old A14.5/R3.1 and default OFF paths are untouched.
- No biological/A4/A5/A6/accounting/checkpoint changes; time/lease token not canonical.
- Need Windows/Linux exact, repeat 256 framed soak/p50/p95/p99 and independent fresh verifier before merge or smoothness claim. Main/PR #805/#813 stay untouched. Measure full GUI rebuild separately.

## Source gates

New workflow: `.github/workflows/eco-arch2-a14-6-r322-trusted-lease-exact.yml`.
Pass all canonical parity and cancellation/security assertions on pinned Linux and Windows Godot Double. Investigate regressions, do not relax invariants to turn CI green. Project Control and A14.5–A13 regressions required before final acceptance.

Verdict at publication: IMPLEMENTED_CANDIDATE / NOT YET VERIFIED / NO MERGE.
