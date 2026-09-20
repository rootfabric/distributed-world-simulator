# FABRIC R5.1 — Fresh Independent Verifier R1

```text
ROLE = VERIFIER
SUBJECT_HEAD = 4f116b70b9ea7767fe33dbe350afa89ce8ac92e9
SUBJECT_TREE = 67bc6024596a63e02b16dadec690f458db190156
EXPECTED_SCALE_HASH = dfbb3aeea6b9c121b3fb46d032cddfdce7a15015ae0dd250157fc82f6758decc
STATUS = PENDING_EXACT_CI
```

Verifier-owned branch. R5.1 subject bytes are read-only.

R1 independently re-runs:

```text
5k × 3 fresh processes
20k × 3 fresh processes
100k × 3 fresh processes
aggregate collector
```

Required predicates at every N:

- FULL peak = 20;
- local reconstructed = 20;
- local rebake validations = 20;
- online residual full scans = 0;
- range queries = 4;
- prefix reads = 80;
- global physical rebuilds = 0;
- duplicate ownership = 0.

It also requires the exact R5.1 scale hash and canonical Linux-double Godot identity.
