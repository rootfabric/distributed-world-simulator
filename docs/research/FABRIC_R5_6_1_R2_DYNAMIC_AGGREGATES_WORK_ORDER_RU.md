# FABRIC R5.6.1 R2 — Dynamic Aggregates & bounded part successors

**Scope:** research-only derived execution, not activation in `main`.
**R1 base:** PR #774 independently accepted, research merge commit
`4f301fae461567362d408a51802cc3dde6730999`.
**Target:** `research/fabric-r5-2-t14-observation-refinement-r1`.
**Delivery:** separate R2 feature PR, draft until independent Reviewer/Verifier.

## Motivation

R5.1 uses static prefix-moment arrays. Any change to a part near the beginning
changes all later prefix sums; a cheap range query does not imply a cheap update.
R5.6.1 R1 introduced a real ConstructionConstructStore read-only delta bridge,
but every future part change still needs authenticated owner data and a dynamic
mass/center-of-mass/inertia aggregate. R2 implements this narrow part of the
research problem without creating a second authoritative owner.

## Physical floor and equations

ConstructionPartRecord.v1 has **mass_kg** and **local_position_m**, but contains
no typed intrinsic per-part inertia tensor, orientation or deformable geometry.
R2 therefore explicitly uses a **point mass at each part's local position**.
The aggregate for interval [lo,hi) is:

```
M    = Σ m_i
S    = Σ m_i r_i
J    = Σ m_i (|r_i|² I₃ - r_i r_iᵀ)       about construct origin
C    = S / M
I_C  = J - M (|C|² I₃ - C Cᵀ)           about its center of mass
```

Ten independent moments [M,Sx,Sy,Sz,Jxx,Jxy,Jxz,Jyy,Jyz,Jzz] are stored
in ten deterministic Float64 **Fenwick/BIT arrays**.

- Compile/build: O(N), including canonical Snapshot.validate (outside BIT
  complexity), 10 moment fields stored per part.
- Owner-validated update of k changed part records: *index work* O(10 k log N),
  with a two-phase prospective node check before any mutation.
- Query [first,end): *index work* O(10 log N), using two prefix queries.
- No full scan of moment arrays on the update path; no deep clone of the
  entire tree for each small update. Changed nodes are staged in O(k log N)
  scratch before publication.
- This **does not** promise O(local) for the entire authoritative operation:
  ConstructionSnapshot.create/validate, full checksum, BRIDGE-4 compile,
  source-fencing Store.get_snapshot/hash, and detached DTO copies still cost
  O(N) or O(N+B). Counters distinguish this from BIT-only work.

The index does NOT claim to calculate connected-component rigid-body inertia
for a broken graph, per-part intrinsic inertia, momentum, collisions,
rotational orientation, thermal/electrical coupling, or an arbitrary material
transfer. A physical damage split must get its own connected-component and
full material ownership contract later.

## External authority / two supported canonical changes

R2 uses a brand-new read-only `R2PartDeltaSession` behind an authentic exact
ConstructionConstructStore instance and the existing BRIDGE-4 compiler.
No mutation of that Store occurs inside the new FABRIC code. Only an external
owner calling ConstructionConstructStore.apply_mutation can advance it.

Supported bounded operations (canonical part IDs are DATA, not hardcoded):

1. `MOVE_PART`: change one part's `local_position_m` (finite 3-vector).
2. `TRANSFER_MASS`: transfer finite positive `delta_mass_kg` from one
   pre-existing part to another, leaving both positive and total mass
   unchanged. MatterBatch remains read-only and must still match total mass.

These do not change the part set, role, metadata, bonds, graph connectivity,
materials, or authority. Mass creation/destruction requires a real Matter
mutation + fresh owner and is not in R2.

The proposal contains a detached exact canonical Construction OP_UPDATE DTO.
A lexical prepare-intent witness captures the original proposal hash, source
checksum, event ID and Store instance ID. Before any publication:

- check exact Store script identity plus instance ID;
- reject modified `_pending` even if its mutable hash is updated;
- check Matter and authority are unchanged;
- read the actual external Store successor once;
- require an exact valid re-prepared canonical proposal and successor hash;
- require BRIDGE-4 graph/binding parity;
- stage and validate all changed BIT nodes and total mass before applying;
- only then atomically publish the new derived source/context/index.

After owner mutation, stale prior queries fail closed until observe or an
explicitly new session from the real Store succeeds. Failed observe never
restores a canonical owner event and never exposes stale physical outputs.
The in-process session does not persist event receipts through process restart.

## Test campaigns

**Exact acceptance (two different layouts, 24/39 parts):** 626 assertions,
2 layouts, 8 externally committed sequential changes, 32 independent FULL
point-mass range oracles (all 9 tensor elements), bounded indexed node visits,
no source writes by FABRIC, pending tamper rejected, invalid mass/motion,
unknown Store/aliased Store, external conflicting successor, stale fencing,
explicit new-session rebind and replay refusal.

**100k scale campaign:** 5,000 / 20,000 / 100,000 canonical part records,
three distant 1-part pose updates per size. Strict tests: 255 assertions,
independent full double-sum mass/COM/inertia diagonal reference, bounded
Fenwick node count, no full index scan after build. This scale harness uses
synthetic checksums ONLY for **numerical index benchmarking**, not for proof
of canonical Store authorization; the latter belongs to exact acceptance.

**Inherited regressions:** R5.6.1 R1 canonical-delta 203 checks, R1 narrow
admission 26 checks, BRIDGE-4 canonical 49 assertions. Closed R5.1–R5.5
kernels, Construction/Matter schemas and old native runners are unchanged.

Strict `collect_r5_6_1_r2_evidence.py` verifies required counters,
no errors/duplicate result markers, 3× byte-identical acceptance, full 100k
scale cases, inherited R1 result/hash, canonical engine SHA256, exact Git
HEAD/TREE before and after, and evidence manifests. Separate Windows/Linux
exact execution and independent review/verification remain mandatory.

## Explicit nonclaims / next work

- Not a new physical solver, dynamic body integrator, world writer, authoritative
  multiplayer scheduler or production physics owner.
- Not an O(log N) end-to-end canonical mutation; only aggregate BIT math is
  bounded. No new typed geometry/orientation/intrinsic inertia is introduced.
- No combination of R1 bond-break and R2 part-edit event ledgers inside one
  session yet. This composition and real split/recovery are R5.6.2+.
- No cryptographic remote owner attestation; local exact Store type/instance
  and trusted-process lexical witness remain the security scope.
- No durable event receipts, cold restart exactly-once, concurrent writes,
  or arbitrary part insertion/removal.
- Preserve R5 CLOSE → INTEGRATION-R6; do not merge R2 into `main`.

## Acceptance / merge policy

R2 implementer Linux/Windows exact on the SAME frozen HEAD/TREE, fresh
independent adversarial Reviewer and Verifier (including new falsifiers),
zero blocking defects, documented numerical error envelope, source identity
unchanged, research-only human merge authorization. Do not mark MERGE_READY on
implementer evidence alone.
