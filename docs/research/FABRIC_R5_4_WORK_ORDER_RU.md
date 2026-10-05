# FABRIC R5.4 — Work Order

Base: merge commit `044eab40803acf51ffc8bc8ff59ae7e8727947de`.
Branch: `research/fabric-r5-4-mixed-complexity-100k-machine-r1`.

1. Reuse R5.1 100k canonical structural source/range-index/lifecycle unchanged.
2. Reuse R5.3 recursive compiler/runtime unchanged.
3. Add only mixed-machine causal orchestration and acceptance/evidence files.
4. Prove local event = structural 20 + recursive 4-node workset, no O(N) residual scan.
5. Prove explicit global causal event = structural 100k + all 15 recursive nodes.
6. Prove root execution remains 4 equations / zero hidden source traversal.
7. Run canonical Linux exact + R5.3/R5.1 regressions; then Windows exact and fresh independent review/verifier before merge.
