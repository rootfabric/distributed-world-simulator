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
