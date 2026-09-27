# MVP4 — implementation progress R1

Parent `V0-MVP-R1-WO-001` remains IN_PROGRESS. MVP1/2/3 closure events and frozen MVP3 are not changed. No main merge and no PREDICATE_VERIFIED for MVP4.

## Implemented

- `v0_mvp4_shared_dig_authority.gd`: bounded single-region integration of existing native M3, LunarBubble/MW4, actual SM1/MW8/P7 authorization, canonical tool/output ports and MW6. A dig is a server raycast-derived request, authenticated to actor/session with a per-run HMAC; replay stays in the accepted MW4 journal.
- `v0_mvp4_replica_surface.gd`: exact revision-zero procedural bootstrap, existing MW6 replica, read-only projection and accepted mesher. Geometry digest is computed from actual vertices/indices, not copied source metadata. No mutable client excavation service remains.
- New authority/gateway/client scripts extend the existing MVP3 process route. One live client triggers the canonical dig; both clients independently apply MW6 and capture before/after rendered viewports.
- Real five-process launcher, eight evidence-negative controls, focused owner/replica tests and transport corruption/foreign-peer/gap/duplicate controls.
- Windows automatic launcher `RUN_V0_MVP4_SHARED_DIG.ps1`; it is explicitly NOT physical keyboard/manual evidence.

## Evidence already observed

`4ab5b80f...` run `34764856985` reproduced initial empty-replica vs procedural-source conflict. Raw artifact `10319704752` remains unchanged.

`3bb87c317777d2689837435e8735af14914bd9a0` focused exact run `34765155507`: 45 assertions, zero failures; native Matter hash changed once, both replica stores equal source, both meshes physically changed identically, unauthorized/tampered/replayed/frozen inputs handled without a second carve. Raw artifact `10320013803`, ZIP SHA256 `8f331318d5446f0e91d522f3a1ee81dfdbb841a923ad927179f1621855ce9aa1`, independently rehashed members match. Overall run red because of a preexisting R13 shutdown-resource diagnostic, not the MVP4 focused test; no overall PASS claimed.

First five-process candidate `6a4f9cdee23c3133336cafc11ee2b3eb5e1f3e23`, tree `629d02b0ecdac1707f8436a108fcbed47b01cbff`, exact run `34765463024`; terminal outcome must be read before claiming PASS. Fresh read-only reviewer requested in PR #597 comment `5654182022`. Its review is not independent runtime verification.

## Remaining gates

Finish actual graphical five-process validation and inspect raw before/after PNGs, strengthen any real failing controls, run affected regression/full Harness/whole world-core, then fresh exact Reviewer and distinct Verifier. The implementation currently provides an automatic bounded shared-dig workload, not a completed manual/playable interaction acceptance. Neither MVP5 exactly-once material output nor item-bearing handoff is accepted here.
