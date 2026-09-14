# MVP4 — visible-terrain repair R2

Original exact candidate `6a4f9cdee23c3133336cafc11ee2b3eb5e1f3e23`, run `34765463024`, artifact `10320516382`, ZIP SHA256 `eb6e5cf86c32058cd5f7672b12be04b825c1e732da6a1cafd26c5b3852a727bc`, independently rehashed 54/54 files.

Machine checks passed: five processes, actual MW4 commit, matching A/B Matter hashes and changed vertex/index hashes, separate fixed input and stable identities. The old R13 cleanup diagnostic was reproduced identically on immutable `f1d453fb` and retained as historical, not hidden. MVP3 native/graphical regressions passed.

However independent inspection of all four real PNGs found **zero changed terrain pixels below row160 in both clients**. Only HUD text changed. Therefore that green workflow is insufficient for the MVP4 visible-dig predicate and is not accepted.

Root boundary: configured brush stroke 0.75m did not intersect the first solid lattice layer of the bounded 2m sample spacing. MW4 only changes occupied samples; near-surface vacuum samples remain unchanged, so subsurface negative SDF perturbations altered mesh hash but not visible surface. Repair: canonical brush stroke 2m, still using the same real server raycast, existing MW4 kernel and unchanged 4.5m P7 reach. No renderer carve or foundation changes.

Stronger gate `test_v0_mvp_4_visible_graphical_shared_dig.py` consumes the unchanged raw process evidence, decodes and CRC-checks actual before/after RGBA/RGB PNGs, excludes HUD, requires at least32 changed terrain pixels in EACH client, and rejects identical viewports or player motion used as a substitute. Additional real-MW6 rejection tests cover other peer, gap, corrupted checksum and duplicate frame without changing replica geometry/state.

MVP4 still NOT VERIFIED. New exact runtime/graphical result and fresh review are required.
