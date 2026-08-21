# ECO.EVO1 / P2.2 — Establishment / Recruitment / Seed Bank — ACCEPTED

Статус: `ACCEPTED_EXACT_WINDOWS_CANONICAL / RESEARCH_ONLY`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `d09857528adee1010f2177095f2afb04bf651532`.

Accepted parent: `ECO.EVO1/P2.1`, aggregate `cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6`.

Canonical P2.2 aggregate:

`633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86`.

## Exact Windows evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

```text
favourable recruitment      46
dry recruitment             21
flooded recruitment         26
low dormancy recruitment    71
high dormancy recruitment   14
low dormancy bank            8
high dormancy bank          66
short half-life bank         4
long half-life bank         61
bank reactivation           33
boundary exported           80
```

Acceptance suite: `PASS (59 assertions)`.

Fresh-process replay A/B reproduced the exact aggregate `633c7975...`.

## Accepted findings

- every packet/cohort conserves integer seed counts;
- favourable recruitment exceeds dry and flooded controls;
- lower dormancy shifts viable propagules toward immediate recruitment;
- higher dormancy shifts them toward persistent seed-bank memory;
- longer seed-bank half-life preserves more viable propagules after two years;
- dormant seed bank can reactivate after environmental improvement;
- outside-domain seeds remain explicit export and never become local recruits;
- lineage/genome/event identity remains cohort truth;
- no biome/species placement table is involved;
- no P2.3 adult turnover/succession semantics were smuggled into P2.2.

## Decision

`ECO_EVO1_P2_2_ACCEPTED_EXACT_WINDOWS_CANONICAL`

Next executable checkpoint:

`ECO.EVO1 / P2.3 Local Population Turnover + Succession`.
