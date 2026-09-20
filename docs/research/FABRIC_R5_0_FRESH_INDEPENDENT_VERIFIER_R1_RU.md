# FABRIC R5.0 — Fresh Independent Verifier R1

```text
ROLE = VERIFIER
SUBJECT_HEAD = 5e4f2edfd48be643493d0abbd50b063980326901
SUBJECT_TREE = ae153088da30456cbcdb1dfc0f585d6a946b7d60
EXPECTED_DETERMINISTIC_HASH = 1c549d536b4077c686dea9e25ca5e08935afd240f3b070ca49da153b7bee883b
STATUS = PENDING_EXACT_CI
```

Verifier scope is read-only with respect to the R5.0 subject. This branch may add only this note and its verifier workflow.

The verifier independently:
- binds exact subject/tree;
- verifies only verifier-owned files differ;
- downloads and verifies canonical Linux-double Godot;
- performs a fresh import;
- runs three fresh-process 5k samples;
- aggregates them with the subject collector;
- requires 5000 canonical parts, FULL peak 20, local reconstruction/rebake validation 20, zero global rebuilds, zero duplicate ownership;
- requires the exact deterministic hash;
- stores its own evidence artifact.

Timings/RSS remain observational only.
