# ECO ARCH2 A10 — Fresh Independent Verifier R1

Статус: DISPATCHED / EVIDENCE-ONLY / NO PRODUCT MUTATION.

## Exact subject

```text
SUBJECT_HEAD = 0ecec3ef88508b24e526bf7efe4e67f4a14666ec
SUBJECT_TREE = b0507338e17b4125479344ff9d706169a3600c9b
BASE_MAIN    = 471210d781e521bc7897a8fe859636a07d7a3ab3
R1 = a0df8f550e32c6fb4f38553509878e5abcdd63c3
R2 = 03913b5c2992739f435819880896cbaee0ecbc1d
R3 = 19466340ad236a54b32797094b1ca86f2f1c6fa2
R4 = 0169ad98b6a8f7179a60a1c50c5226050709f7c7
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

The prior pinned subject `57d274de196e...` is historical after canonical Windows double Godot exposed R2/R4 typed-array failures and R3/R5 parser inference failures. This verifier now admits only `0ecec3ef88508b24e526bf7efe4e67f4a14666ec / b0507338e17b4125479344ff9d706169a3600c9b`, containing the fixes at their owning layers.

## R4 negative-control rebind

The prior Windows subject `2d32212914de...` is historical after R4 revealed a no-op forged-event negative control. Current product `0ecec3ef88508b24e526bf7efe4e67f4a14666ec / b0507338e17b4125479344ff9d706169a3600c9b` carries the non-noop, re-sealed part/module mismatch control and no runtime semantic change.

## Fresh whole-stack authority review rebind

The previous subject `a33a9056a9d7...` remains historical PASS evidence but cannot satisfy current acceptance after review found that R1 admitted WARM as executable. Current product `0ecec3ef88508b24e526bf7efe4e67f4a14666ec / b0507338e17b4125479344ff9d706169a3600c9b` requires ACTIVE for ECO cursor/site execution and retains WARM only as R3 handoff preparation state. Verifier must run the new subject on both canonical platforms.
