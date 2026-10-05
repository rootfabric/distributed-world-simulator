# FABRIC R5.3 Work Order R1 / R2 hardening

Implement Recursive Hierarchical Execution after verified/merged T16.

- Base: `604192f07070d0f0e38a94445611d09d92cb7f7f`.
- Additive research branch only; do not change T1–T16 kernels/contracts.
- Prove component/leaf → module ROM → assembly ROM → machine ROM. Parent admission is fail-closed on exact level adjacency (`child.level == parent.level - 1`); recursive levels may not be skipped or mislabeled.
- Preserve T1 >=100 hidden-variable gate; R5.3 leaf admission must also prove that the accepted T1 capsule/artifact/reduction is bound to the exact supplied source graph. Cross-graph ROM rebinding is fail-closed, including descriptor/system rebinding after otherwise-valid capsule/artifact checksum repair. Leaf admission must canonical-recompile T1 from the exact supplied graph/request and require the complete linear-system / graph-compile / reduction / artifact / capsule bundle to match; a rewritten `source_system_hash` alone is not sufficient proof. Parent recursive composition may use existing exact reducer directly on child-ROM composition graphs.
- Parent compilation may read child boundary descriptors/checksums, never hidden child source graphs. Child descriptor admission is fail-closed: exact four-port semantics, certified passive Laplacian, zero affine source and actual Schur row-sum consistency are required before converting the child ROM into parent composition components. Every non-leaf node must also prove its stored graph/reduction/topology is exactly the canonical recomposition of its child ROMs and topology revision; checksum-repaired parent ROM content drift is fail-closed.
- Prove executable ROM at every level; root steady source traversal zero.
- Prove local rebuild at leaf/module/assembly/machine with exact ancestor-only changed path and prepared-session reuse. Refresh is transactional: validation/prepare of every changed node completes in staging before any live registry commit; rejected refresh leaves sessions, bundles, hashes and prepare/reuse counters unchanged.
- Prove leaf hidden complexity growth does not grow machine steady executable/parent compile graph.
- Use R5.0 measurement harness; compile/rebuild and steady stages remain distinct.
- Exact Linux/Windows + T16/T15/T14/T13.5/T13/T12 regressions, strict evidence collector.
- Fresh independent Reviewer and Verifier, then explicit human merge. No self-acceptance.
