# ECO P4.4 — Production Persistence — ACCEPTED

Статус: `ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN`.

Parent P4.3 aggregate: `4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62`.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.

## Exact committed identities

- kernel: `2f4d7809a84d4f6d23a3f113c23b359f0803d564`
- acceptance test: `2385b035082834aaae1eb91e25aa798c26ca40dc`
- hardened runner: `88d02dfcf6cf63b065a35eec6202dd5b0a04dee9`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`

## Windows full-chain evidence

The committed runner passed its bounded parser/preload preflight, the direct committed P4.3 parent regression (`67 assertions`), and P4.4 production persistence in two fresh processes (`52 assertions` each).

```text
aggregate_hash=4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2
snapshot_hash=c6ee61dc4250fcd22b762902ff35354957c884c8b1818aed8209fe4f6c829006
file_sha256=b600642b817aec7c6afdb8f10d85ba15d660f569dedf30d4b9d91ecc1b214fd8
resumed_catchup_hash=cc2a4815e1eae75b879ea52d8ba404880c69344928f953e8aaa38bd062b1ce3a
parent_p4_3=4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62
```

Both P4.4 process outputs were identical and the runner ended with `ECO.P4.4 candidate automated gates: PASS`.

## Decision

P4.4 is accepted as the production ecology persistence boundary. P4.5 committed full-chain gate is now authorized. This acceptance does not authorize P4.5 itself, P4.6 client authority, network transport, or distributed consensus.
