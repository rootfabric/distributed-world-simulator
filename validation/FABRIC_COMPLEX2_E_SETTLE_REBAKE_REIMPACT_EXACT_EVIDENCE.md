# FABRIC COMPLEX2-E — Settle → Rebake → Re-impact — Exact Evidence

## Verdict

```text
COMPLEX2-E PHYSICAL EXACT: PASS
ASSERTIONS:                47 / 47
INDEPENDENT REPLAY:        PASS
SETTLE:                    PASS
REBAKE:                    PASS
RE-IMPACT:                 PASS
MIXED vs FULL:             PASS
GLOBAL PROJECT CONTROL:    RED — unrelated pre-existing ownership/passport drift
DEDICATED SELF-HOSTED E:   QUEUED when evidence recorded
```

## Exact executable identity

```text
branch: feature/fabric-complex2-modular-machine-r1
HEAD:   b618c449b6dae5a25a14d24bfed87dbc2832d125
TREE:   ed5450dc71f4b0fb707b18af5c6b1584f73199ef
```

Source carrier:

```text
workflow: FABRIC BRIDGE-2 Exact Source Carrier
run:      33886574243
artifact: 9942087276
digest:   sha256:e1c5a6402f7f5f4d08ea431f4e5cc491857bf9c17d54d55ff9621a6c6e8b8a0b
bundle:   sha256:00b13fff4a5f57a1eacc478a70a917ba7930fe87d6a7f567a37f3230870a864d
```

Bundle checksum passed and detached checkout resolved exactly to the E HEAD/TREE.

## Canonical Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Two independent exact bundle checkouts both returned code 0 and the same integrated hash:

```text
77c3c1e792d082391c8901d9c61946b0655c4abd332f71dc4554ef479fc9a5f8
```

Exact marker:

```text
FABRIC COMPLEX2-E Settle Rebake Re-impact Acceptance: PASS (47 assertions) settle=PASS rebake=DYNAMIC_ROM reimpact=PASS mixed=FULL_REFERENCE scene=PASS
```

## Lifecycle proved

E starts from the COMPLEX2-D continuation after the independent brace failure. It separates three states that must not be conflated:

```text
transient physical state
        ↓
SETTLED physical state
        ↓
REBAKED derived DYNAMIC_ROM artifact
        ↓
new RE-IMPACT event
```

Premature transitions fail closed:

```text
COMPLEX2E_REBAKE_REQUIRES_SETTLED
COMPLEX2E_REIMPACT_REQUIRES_REBAKED
```

## Settle gate

First impact excites the existing COMPLEX2-C four-DOF coupled machine. The active DYNAMIC evaluator and FULL reference are stepped together until both certified settle conditions are met:

```text
total energy <= 0.0025 J
max path speed <= 0.020 m/s
```

Exact result:

```text
settle step    = 549
settled energy = 0.0024826531871402274 J
```

The transient loses more than 100× energy before settling. Release energy is monotonic, damping remains passive, energy identity closes, and ACTIVE/FULL trajectory delta remains within `1e-12`.

The full q/v state is encoded and decoded with zero handoff error before rebake.

## Rebake semantics

Rebake targets the existing `region/complex2-dynamic` only and preserves:

```text
region owner
representation kind = DYNAMIC_ROM
state id
source slice
canonical source revision
```

It changes only the derived artifact/backend identity. Exact generation:

```text
build_generation = 6
```

The new backend hash binds:

- previous COMPLEX2-C DYNAMIC backend identity;
- settled q/v state hash;
- the already-failed COMPLEX2-D structural topology hash;
- rebake generation and lifecycle kind.

Critically:

```text
old source slice hash == rebaked source slice hash
old backend hash       != rebaked backend hash
old registry hash      != rebaked registry hash
runtime state handoff error = 0
```

Thus settling is not misrepresented as a canonical source mutation.

## Re-impact

After rebake, a new exactly-once event is committed:

```text
event/complex2e-reimpact-after-settled-rebake
```

Duplicate event is rejected with:

```text
COMPLEX2E_REIMPACT_ALREADY_APPLIED
```

The re-impact excites the coupled physical system again:

```text
peak energy = 0.612677432 J
```

This is more than 100× the settled energy. Motion propagates through shoulder, elbow, shaft and carriage while remaining inside the C certified envelope. Compiled DYNAMIC and FULL physical trajectories remain equal within `1e-12`; energy identity and passive damping remain valid.

At the mixed BRIDGE-2 level, the re-impact also drives CONTACT + DYNAMIC external flows. Exact CONTACT state change:

```text
0.008322890093712065
```

Mixed runtime remains equal to FULL reference.

## No hidden topology mutation

Between D completion, settle, rebake and re-impact:

```text
D structural topology hash before rebake == topology hash after re-impact
B compliant HYBRID backend hash           == final HYBRID backend hash
five representation kinds                 == preserved
```

Functional topology identity is retained. E therefore proves a derived-state lifecycle rather than silently creating a second canonical mutation.

## Project Control caveat

Project Control run `33886574047` failed in the same repository-wide architecture/ownership passport compatibility step seen on D. Exact logs report RED drift for G/ECO/V0 due Matter/P7/control dependencies outside the D/E implementation set. Checkout identity, syntax/generation checks and checkpoint-session regression passed before that global compatibility step.

This evidence does not relabel Project Control as green. It records E as **exact-verified at the physical FABRIC research boundary** while preserving the separate global control-plane RED signal.

## Conclusion

`COMPLEX2-E Settle → Rebake → Re-impact` is physically exact-verified. The existing machine can settle, derive a new DYNAMIC_ROM artifact from the settled q/v state without forging a source mutation, and then accept a new exactly-once impact whose coupled response remains equivalent to FULL reference.