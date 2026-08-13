# ECO / P3.1 — Deterministic Resource Competition — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

Accepted aggregate:

```text
f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
```

Accepted parent P2.8 aggregate:

```text
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
```

## Evidence boundary

Exact Windows canonical collector was executed on:

```text
head=882fadfbce1808ba1ee52eae0cfdf0caa0b6b079
tree=447fd147237bcc3c688315593838488791230d0a
godot=4.7.1.stable.double.custom_build.a13da4feb
stage=P3.1
```

Evidence file:

```text
P31-20260813T061230Z-882fadfbce18.json
```

Collector result:

```text
ECO.P3 Windows canonical evidence: PASS
stage=P3.1
aggregate_hash=f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
parent_hash=ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
raw_log_sha256=cc757900ca483f6942ba5488acc262f2df7145acc70c9e718feaab2a20bf3dc8
evidence_sha256=4999281a070e2043f8eb56823fcacbc35a94f73eed679524dcddf7cd4356d03b
```

The collector explicitly reported that it performed no validation-status or acceptance mutation. This document and the corresponding validation update are the separate lifecycle acceptance step.

## Canonical gate that passed

`RUN_ECO_P3_1_TESTS.ps1` completed:

1. P3.1 parser/preload preflight;
2. full accepted `RUN_ECO_EVO1_P2_8_TESTS.ps1` regression chain;
3. P3.1 process A;
4. independent fresh P3.1 process B;
5. aggregate equality check;
6. exact parent P2.8 identity check.

Both P3.1 processes reported:

```text
ECO.P3.1 Resource Competition: PASS (47 assertions)
aggregate_hash=f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
constrained_hash=5d082433bff9cf5b29707da53657bb02e4575ba018544ebbe86cbfde5fd58dec
abundant_hash=bcd82bb49edbf159c31d8fb15c8aef243d63619e12868b3cfd3d0c06003a7c60
water_limited_hash=d22c326115f880562ed1858ebeeee805d54240d663fbee87a8eb8b7ceec95e84
parent_p2_8=ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
```

The accepted P2.8 regression also reproduced its canonical aggregate and deterministic save/restart proof on the same Windows Godot build.

## Accepted contract

P3.1 accepts exactly the already-reviewed deterministic resource competition semantics:

```text
resources = light / water / nutrients
allocation = deterministic weighted water-filling with demand caps
plant order = canonical lexical ID order
conservation = supply == uptake + remaining within tolerance
growth response = minimum demanded-resource uptake ratio
input permutation = no result/hash change
malformed/tampered state = fail closed
```

No runtime/network/persistence/rendering authority is added by this acceptance.

## Lifecycle decision

```text
P3.1 = ACCEPTED_EXACT_WINDOWS_CANONICAL
P3.2 parent-status gate = SATISFIED
P3.2 = still CANDIDATE
P3.3 = NOT OPENED
```

Next legal action:

```text
run exact Windows canonical P3.2 gate
-> review exact evidence
-> separate P3.2 acceptance lifecycle commit
-> only then open P3.3 Spatial Dispersal
```

OBS1 remains non-gating read-only visualization and has no effect on this acceptance.
