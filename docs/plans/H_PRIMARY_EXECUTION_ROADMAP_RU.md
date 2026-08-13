# H — Primary Execution Roadmap

**Status:** canonical execution route  
**Architecture:** `GLOBAL-P0-2026-08-10-R2` until explicit R3 promotion  
**Progress unit:** accepted checkpoint or removed gate, never commit count.

## Control rule

```text
BRANCHES REPORT FACTS
MAIN DECLARES PROJECT STATE
AUDITOR CHECKS CONSISTENCY
GLOBAL ARCHITECTURE DEFINES WHAT IS ALLOWED
HARNESS MOVES ONLY BETWEEN DECLARED CHECKPOINTS
```

## Current critical path

```text
H0.1 R8 / C22                         PASS
        ↓
C22 SOURCE_ACCEPTED_MERGE_READY       PASS
        ↓
HUMAN C22_RUNTIME_MERGE               DONE
        ↓
post-C22 PC0                          NON_RED
        ↓
C22 MAIN_INTEGRATED                   DONE
        ↓
GLOBAL-P0 R3 exact-current-main refresh
        ↓
final R3 Evidence Map / exact-target Project Control
        ↓
standard + directional PC0 NON_RED
        ↓
Independent Reviewer PASS
        ↓
Independent Verifier PASS
        ↓
Director final gate PASS
        ↓
R3_REFRESHED_CANDIDATE_READY
        ↓
HUMAN GLOBAL_ARCHITECTURE_PROMOTION   STOP GATE
        ↓
mandatory post-R3 PC0
        ↓
H0.2 / fresh NX.C1 high-risk pilot
        ↓
H0_2_PASS + NX SOURCE_ACCEPTED
        ↓
H0.3 DEVELOPMENT multi-worker scheduler
        ↓
H0_3_SCHEDULER_ACCEPTED
        ↓
controlled V0 / GEO-min / ITEM-min / NET-min composition work
```

No primary runtime frontier bypasses this order.

## C22 canonical anchor

```text
merge commit:       eefd75fa3badec10c6e7db959e2a3992dba30f0e
implementation:     4c69de50c8374112d82efee2fd6917c770b3eae0
accepted PR head:   ab674669b9a293d898e5ca5983b4918cc685d990
accepted tree:      10c92456537efca220a0d9ae242a58f5dbfd2b74
post-merge PC0:     run 31558679306 / SUCCESS / NON_RED
H0.1 runtime slot:  RELEASED
```

The normal merge preserved the accepted tree byte-for-byte and retained implementation provenance. C22 is now canonical main truth, not source-branch authorization.

## R3 boundary

R3 is architecture/control work, not runtime feature implementation. The existing PR #85 preparation must be repinned to the exact main that exists after this control synchronization. Historical R3 SHA/generation values are provenance only.

Required finalization:

```text
fresh main SHA + registry generation
→ repin/freeze candidate
→ refresh frontier/main guards
→ R2→R3 transition audit
→ ownership/intersection PASS
→ exact-target Project Control
→ standard PC0 NON_RED
→ directional PC0 NON_RED
→ exact-target Evidence Map
→ independent Reviewer PASS
→ independent Verifier PASS
→ Director final gate PASS
→ R3_REFRESHED_CANDIDATE_READY
→ HUMAN GLOBAL_ARCHITECTURE_PROMOTION
→ mandatory post-R3 PC0
```

Required invariants:

```text
ITEM = stable canonical foundation
V0 = composition consumer
V0 != canonical truth owner
H0.3 = DEVELOPMENT Work-Order scheduler/control layer
H0.3 != game runtime scheduler
H0.3 != gameplay authority
H0.3 != simulation/game-time owner
ECO = advisory/research
ECO != economy
ECO != production scheduler
ECON = reserved future economy program
```

## H0.2 / NX.C1

H0.2 starts only after R3 becomes canonical and mandatory post-R3 PC0 is NON_RED. Create a fresh NX.C1 from then-current main; do not revive legacy FIX ancestry.

Minimum acceptance intent:

```text
owner-predicted local player
server-authoritative simulation
prediction/reconciliation
remote interpolation
optimistic item pickup/drop presentation
rollback on rejection
authority epoch correctness
reconnect identity preservation
2-client + impaired-network validation
CH→NX directional dependency revalidation
Evidence Map / Reviewer / Verifier
```

Result:

```text
H0_2_PASS
NX SOURCE_ACCEPTED
```

`NX SOURCE_ACCEPTED != NX MAIN_INTEGRATED`.

## H0.3

H0.3 controls development workers and Work Orders. It never schedules game-runtime processes.

Before H0.3 acceptance:

```text
primary autonomous runtime workers <= 1
```

H0.3 must prove compatible work can run in parallel and conflicting ownership/path claims are blocked before mutation.

## First composition wave

```text
H0.3 accepted
    ↓
V0.0 / V0-S0
    ├─ GEO-min → V0-S1
    └─ ITEM-min → V0-S2

NX MAIN_INTEGRATED + NET-min → V0-S3
                              → V0-S4
                              → V0-S5
```

V0 remains a consumer. It must not introduce private terrain, Item, Network, Persistence, authority or scheduler truth.

## Secondary lanes

`CH9.6` is accepted/frozen. Do not repeat its graphical gate. `CH→NX` remains a required future dependency check.

`ECO.PH` research is complete through PH5-S4. `ECO.CONV0-A` design-only research may continue because it is advisory and owns no production runtime lane. CAL1 follows; production convergence remains gated.

## Stop rules

```text
NO GLOBAL-P0 R3 promotion without explicit human authorization
NO H0.2 / NX.C1 runtime before canonical R3 + post-R3 PC0
NO H0.3 implementation before H0_2_PASS + NX SOURCE_ACCEPTED
NO V0 runtime before H0.3 acceptance
NO V0-S3 before NX MAIN_INTEGRATED + NET-min
NO G9 before R3 + MAT0
NO T1B.5
NO TS0.4 runtime on this critical path before canonical R3 + post-R3 PC0
NO T2.0 before C22 MAIN_INTEGRATED + TS0.4 + PC0 convergence
NO independent Item truth fork
```

After every main movement, checkpoint or promotion, recompute Project Control and resolve CURRENT again from Git, not from this document's historical SHA examples.
