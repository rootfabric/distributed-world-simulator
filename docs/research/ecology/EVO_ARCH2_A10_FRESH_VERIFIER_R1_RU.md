# ECO ARCH2 A10 — Fresh Independent Verifier R1

Статус: DISPATCHED / EVIDENCE-ONLY / NO PRODUCT MUTATION.

## Exact subject

```text
SUBJECT_HEAD = 8cc0f6ec26c7b8f80c67788cf076b7023a2f4130
SUBJECT_TREE = fbca791248c42fd55f274ec980b304d464584059
BASE_MAIN    = 471210d781e521bc7897a8fe859636a07d7a3ab3
R1 = 9ff2d13e31318bd0f323d29a3efd03f0850d8c7b
R2 = 46983be7370c1fd8eaf652b7672023d4bc1f6f80
R3 = 5df721877758b77ae4b944737eb5c57f705898a4
R4 = 9ab7bdf396fc0ecffc847397c4f2e3685f5ef92b
```

Verifier branch MUST NOT modify product files. Workflow checks out the exact subject into a separate checkout and runs the subject-owned R5 whole-stack verifier there.

## Required checks

1. exact HEAD/TREE match;
2. canonical Linux double Godot:
   - version `4.7.1.stable.double.custom_build.a13da4feb`;
   - SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`;
3. R5 verifier validates additive R5 scope over exact R4;
4. current R1, R2, R3, R4 and R5 Godot runtime scripts all PASS on the same exact subject;
5. no parse/script errors and no tracked source mutation;
6. evidence artifact contains the exact summary and raw logs.

## Trust boundary

A successful verifier run is independent runtime evidence for the pinned product subject only. It does not authorize merge, A10 acceptance, A11 activation, production ECO authority, or bypass the fresh reviewer/main-epoch gates.

If the self-hosted Linux runner is unavailable, state must remain BLOCKED_RUNNER; queued is not PASS.

## Windows Repair R2 rebind

The prior pinned subject `57d274de196e...` is historical after canonical Windows double Godot exposed R2/R4 typed-array failures and R3/R5 parser inference failures. This verifier now admits only `8cc0f6ec26c7b8f80c67788cf076b7023a2f4130 / fbca791248c42fd55f274ec980b304d464584059`, containing the fixes at their owning layers.

## R4 negative-control rebind

The prior Windows subject `2d32212914de...` is historical after R4 revealed a no-op forged-event negative control. Current product `8cc0f6ec26c7b8f80c67788cf076b7023a2f4130 / fbca791248c42fd55f274ec980b304d464584059` carries the non-noop, re-sealed part/module mismatch control and no runtime semantic change.

## Fresh whole-stack authority review rebind

The previous subject `a33a9056a9d7...` remains historical PASS evidence but cannot satisfy current acceptance after review found that R1 admitted WARM as executable. Current product `8cc0f6ec26c7b8f80c67788cf076b7023a2f4130 / fbca791248c42fd55f274ec980b304d464584059` requires ACTIVE for ECO cursor/site execution and retains WARM only as R3 handoff preparation state. Verifier must run the new subject on both canonical platforms.

## Fresh trust review R2 rebind

Current subject `8cc0f6ec26c7b8f80c67788cf076b7023a2f4130 / fbca791248c42fd55f274ec980b304d464584059` additionally requires WARM-only handoff preparation, caller-owned R4 event binding-hash authority, and valid-rehash falsifiers for the R1 damage record and R2 Matter batch anchors. All earlier subjects are historical after these trust-boundary repairs.
