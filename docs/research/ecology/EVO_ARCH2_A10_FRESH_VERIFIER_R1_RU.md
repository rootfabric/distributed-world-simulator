# ECO ARCH2 A10 — Fresh Independent Verifier R1

Статус: DISPATCHED / EVIDENCE-ONLY / NO PRODUCT MUTATION.

## Exact subject

```text
SUBJECT_HEAD = a33a9056a9d7b6c77f25c8f9dd79470554d7545d
SUBJECT_TREE = 6a5aec11734b262f36db83f569f2e3a500057d98
BASE_MAIN    = 471210d781e521bc7897a8fe859636a07d7a3ab3
R1 = 06f7ee1774ce2b847ace9422a42f3928c3dff3e9
R2 = 9aec7c80cd5255d5fc82e856502e6221ff2bd578
R3 = 1872fe20437a525c5982266d0fc09bfd4af49fcc
R4 = ef5a9ecccdc403631d11c2cebe0b95d8971243bf
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

The prior pinned subject `57d274de196e...` is historical after canonical Windows double Godot exposed R2/R4 typed-array failures and R3/R5 parser inference failures. This verifier now admits only `a33a9056a9d7b6c77f25c8f9dd79470554d7545d / 6a5aec11734b262f36db83f569f2e3a500057d98`, containing the fixes at their owning layers.

## R4 negative-control rebind

The prior Windows subject `2d32212914de...` is historical after R4 revealed a no-op forged-event negative control. Current product `a33a9056a9d7b6c77f25c8f9dd79470554d7545d / 6a5aec11734b262f36db83f569f2e3a500057d98` carries the non-noop, re-sealed part/module mismatch control and no runtime semantic change.
