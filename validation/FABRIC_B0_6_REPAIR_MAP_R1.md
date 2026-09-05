# B0.6 bounded repair map

## A: typed envelope integrity

Canonical owner: existing FABRIC safety evaluator. Entry compile/validate; callers B/C/D.
Root cause: report dictionaries only checked keys, not witnessed values; direct Variant
String-vs-float comparison in first new negative test emitted SCRIPT ERROR even though
Godot exited 0 and the old acceptance printed PASS. Fix: typed value comparison,
shared witnessed safety algorithm, runner rejects fatal markers and missing sentinel.
No expected safety threshold was weakened. A focused reruns: 114/114, no fatal markers.

## D: serialization continuity

Entry: capture → canonical JSON → fresh decoder → recover → controller.
Caller: restart and disk-process acceptance; sibling: all controller integer counters.
Root cause: Dictionary equality treats JSON integral floats differently from native
integers. Valid same-configuration capsules were being discarded after disk roundtrip.
Fix location: compare configuration canonical identities and normalize validated
integer state fields at sealing. Source revisions/epochs keep their numeric values;
no source revision is minted. Test remains unchanged and requires identical recovery.
Regression: C plus D including writer/reader in separate Godot processes.

## Inherited closure packaging

BRIDGE-2 closure runner references missing RUN_FABRIC_SYNC4_TESTS.sh and acceptance.
Restore exact historical blobs from commit 07b3bf9d, then rerun the closure. Preserve
all historical reports; do not replace regression with an invented green stub.

## E: correct predecessor boundary

Initial adapter wiring used a nonexistent `Registry.compile` and assumed a one-region
MixedRuntime. Inspection proves BRIDGE-2 R1 registry deliberately accepts exactly five
representation kinds and four interfaces. Do not weaken that closed falsifier and do
not add a solver to B0.6. The corrected lifecycle slot reuses the existing single-region
RegionAdapter, certified identity reconstruction, BakeExecutionGate and mixed ownership
contract. E measures actual adapter preparation/reconstruction/dispatch work, not numeric
integration of 2000 COMPLEX2 machines. Numerical physics remains in predecessor runners.

## E: recovery replay boundary and fixture identity

Runtime recovery must not rewind a live authoritative evaluation tick or accept a
foreign/regressing canonical source. The recovery operation is bound to canonical
source, policy, tick and physical inputs, not to a disposable capsule. Exact repeats
perform no reconstruction; changed canonical physical inputs require a changed source
binding. Local smoke additionally proves descriptor copies cannot mutate the slot.
The workload obtains source keys from the existing Utils.source_key function; an
initial fixture guessed the delimiter and was corrected, not the canonical utility.
