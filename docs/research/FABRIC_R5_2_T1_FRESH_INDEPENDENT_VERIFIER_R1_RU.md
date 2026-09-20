# FABRIC R5.2A / T1 — Fresh Independent Verifier R1

```text
ROLE = VERIFIER
SUBJECT_HEAD = 9b2bf8db9e7f8e8d2629e76e724ad1b9270ca9cb
SUBJECT_TREE = 4f7e7e6fcd57de1ebe0d323cf86bf3e355d14b1d
EXPECTED_DETERMINISTIC_HASH = 3236785de6f45e34c7f380edb5cad6286bf650c7d963c907708afe936b97de0f
STATUS = PENDING_EXACT_CI
```

Verifier-owned branch. Subject bytes are read-only.

R1 independently re-runs three fresh T1 processes and requires:

- canonical graph binding to Construction source;
- 543 source components;
- 128 hidden nodes / 4 boundary ports;
- 132 full equations → 4 executable equations;
- zero source-component traversals during prepared execute;
- exact full↔capsule boundary equivalence;
- mutation / STALE / invalidation / authority / dependency / graph fail-closed;
- singular graph → NO_SAFE_BAKE / RANK_DEFICIENCY;
- exact deterministic hash above.

Timing remains observational only.
