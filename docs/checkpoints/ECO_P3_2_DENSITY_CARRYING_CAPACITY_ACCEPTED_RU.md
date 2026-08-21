# ECO / P3.2 — Density & Carrying Capacity — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

## Accepted identity

```text
checkpoint = ECO.P3.2
aggregate_hash = 172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
parent_p3_1 = f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
```

P3.1 parent status:

```text
ACCEPTED_EXACT_WINDOWS_CANONICAL
```

## Exact Windows canonical evidence

Collector head:

```text
4ade178fc394cb5b220d206465310f06f63e4cfb
```

Collector tree:

```text
b15abc86feb1d672340279568e61ad4e9eea19ab
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Canonical chain:

```text
RUN_ECO_P3_WINDOWS_CANONICAL_EVIDENCE.ps1
-> RUN_ECO_P3_2_TESTS.ps1
-> RUN_ECO_P3_1_TESTS.ps1
-> accepted P2.8/EVO1 parent regression chain
```

P3.2 process A and fresh process B both returned:

```text
ECO.P3.2 Density & Carrying Capacity: PASS (79 assertions)
aggregate_hash=172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
under_capacity_hash=8f08ce09fe5d6db5e34d1109e0899b680fb5b877ec790d3c39cc376b5c0f56b8
over_capacity_hash=b93d073f06c878fb3ea52b98b898ff7fce8bf97e6f1cf4e28c6af7e0d4cb721f
resource_limited_hash=8711ee9d04f20489eff580ff798d3ee799c9c02a12d4dc0c8ac0fa9801fdaca4
parent_p3_1=f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
```

Collector result:

```text
ECO.P3 Windows canonical evidence: PASS
stage=P3.2
raw_log_sha256=a60db1644a45917c73d2eedaee9e244e33acd4fcbdcfd385a964e6798a4035eb
evidence_sha256=6619064b6770438c5d63661aff65c5a92dddc7740655f67b13644daa7ee98a26
```

Collector explicitly performed no validation-status mutation; this document and the associated validation update are the separate lifecycle acceptance record.

## Accepted semantic boundary

P3.2 accepts the following research semantics:

- resource-coupled effective carrying capacity;
- bounded positive recovery below `K`;
- stationary density response at `K`;
- bounded decline above `K`;
- no instantaneous hard clipping;
- preservation of composition under shared over-capacity decline;
- deterministic soft convergence toward `K`;
- fail-closed malformed/tampered input handling;
- deterministic fresh-process result identity.

It does not claim production ecology authority, spatial ownership, persistence, networking or rendering ownership.

## Next checkpoint

P3.2 acceptance removes the final gate preventing P3.3 from opening.

```text
P3.3 Spatial Dispersal = ALLOWED TO OPEN
```

P3.3 must add explicit deterministic neighbourhood topology and cross-patch/cell dispersal without modifying this accepted P3.2 aggregate.
