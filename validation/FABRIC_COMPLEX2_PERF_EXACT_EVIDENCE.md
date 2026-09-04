# FABRIC COMPLEX2-PERF — Exact Evidence

Status: **EXACT VERIFIED**

## Exact executable subject

```text
HEAD 4cf6d45f35b16db0cead220768b399f0ea5c75ef
TREE 923f9f59730da43f8be6d738b7e1dc4a23ec7764
```

GitHub exact-source carrier:

```text
workflow run 33889807380
artifact id  9943356404
artifact     fabric-bridge2-exact-source
artifact digest sha256:8cce468fd3a1865a1e21b1d71369eed217e6672ca64c4cf457dc9862ff77b055
bundle sha256 verification: OK
```

Canonical attached Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
sha256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Exact matrix

The acceptance materializes actual canonical parts at all three target scales and executes D structural failure, E settle/re-impact physics, mixed-vs-FULL runtime stepping, and a local DYNAMIC_ROM rebake.

```text
500 parts:
  total 6026692 us
  build 138340 us
  scan 1315 us
  D 3113 us
  E settle+reimpact 612576 us
  mixed runtime 5089135 us
  local rebake 86552 us

1000 parts:
  total 6130391 us
  build 141193 us
  scan 2503 us
  D 2957 us
  E settle+reimpact 606986 us
  mixed runtime 5152676 us
  local rebake 88082 us

2000 parts:
  total 5993020 us
  build 153975 us
  scan 4952 us
  D 3179 us
  E settle+reimpact 637731 us
  mixed runtime 5011114 us
  local rebake 85493 us
```

Budgets:

```text
case total <= 12,000,000 us
local DYNAMIC rebake <= 250,000 us
```

All three cases remain within budget. The observed full-case duration is dominated by the fixed physical/mixed lifecycle rather than canonical part scanning. Canonical scan work grows with part count, while the local DYNAMIC rebake remains bounded and does not scale with the full object size in this matrix.

## Correctness gates

For 500 / 1000 / 2000 independently:

- 25 modules and 29 supports;
- exact scaled region-part counts;
- D changes structural topology while retaining one connected component;
- E reaches the settled envelope and re-impact excites the machine;
- mixed runtime equals FULL reference within `1e-12`;
- local rebake touches exactly `region/complex2-dynamic`;
- local rebake handoff error is zero;
- rebake generation is 7;
- timing is excluded from deterministic identity.

Exact result:

```text
FABRIC COMPLEX2-PERF Scaling Acceptance: PASS (62 assertions) 500/1000/2000
COMPLEX2PERF_MATRIX_HASH=698486abd097e6ee12731b0afb1c6e28ed24bf72b52d8d940c9f5b7336498607
```

The same matrix hash was reproduced in independent preflight runs and again inside two exact-source COMPLEX2-CLOSE invocations.
