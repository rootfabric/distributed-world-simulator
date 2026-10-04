# FABRIC R5.3 Work Order R1

Implement Recursive Hierarchical Execution after verified/merged T16.

- Base: `604192f07070d0f0e38a94445611d09d92cb7f7f`.
- Additive research branch only; do not change T1–T16 kernels/contracts.
- Prove component/leaf → module ROM → assembly ROM → machine ROM.
- Preserve T1 >=100 hidden-variable gate; parent recursive composition may use existing exact reducer directly on child-ROM composition graphs.
- Parent compilation may read child boundary descriptors/checksums, never hidden child source graphs.
- Prove executable ROM at every level; root steady source traversal zero.
- Prove local rebuild at leaf/module/assembly/machine with exact ancestor-only changed path and prepared-session reuse.
- Prove leaf hidden complexity growth does not grow machine steady executable/parent compile graph.
- Use R5.0 measurement harness; compile/rebuild and steady stages remain distinct.
- Exact Linux/Windows + T16/T15/T14/T13.5/T13/T12 regressions, strict evidence collector.
- Fresh independent Reviewer and Verifier, then explicit human merge. No self-acceptance.
