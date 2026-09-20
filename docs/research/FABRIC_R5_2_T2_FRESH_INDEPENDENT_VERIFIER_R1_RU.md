# FABRIC R5.2 / T2 — Fresh Independent Verifier R1

```text
ROLE = VERIFIER
SUBJECT_HEAD = e12ace397517110b2aaeb7deeb9f865183db600f
SUBJECT_TREE = 3590f5fc67a12011e1a25f4f002469e1c155e926
EXPECTED_DETERMINISTIC_HASH = a7bb61c19ddda61527155d3ed405b22b6260cce807a3e958558a13b1a50b8d05
STATUS = PENDING_EXACT_CI
```

Verifier-owned branch. T2 subject bytes are read-only.

R1 independently re-runs three fresh T2 processes and requires:

- 8-bit adder: 131072/131072 exhaustive cases;
- 8-bit counter: 1024/1024 state/input cases;
- 2048-tick deterministic counter sequence;
- zero source-component traversals per lookup execute;
- one-gate mutation changes compiled lookup;
- combinational cycle fail-closed;
- >17 address-bit state space fail-closed;
- exact deterministic hash above.

Timing, memory and speedup remain observational only.
