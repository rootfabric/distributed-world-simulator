# PlanetSimulator — укреплённая distributed runtime roadmap

Текущий candidate: `v16.9.0-simulation-s1-distributed-compute-fix1`.
Принятая база: `v16.8.5-domain-m0-aggregate-transactions`.

```text
N0–N2 accepted
R3.1 accepted
A0 accepted
H0 accepted
A1 accepted
S0 accepted
T1 accepted
B0 accepted
M0 accepted
S1 current candidate
→ B1
```

S1 закрепляет immutable simulation jobs, projected read-state, declared read/write sets, worker capabilities, deterministic fingerprints и authority-side conversion в M0 atomic commit. Worker не получает authoritative write access. NATS Core, JetStream, Directory и production Population Field остаются последующими этапами.
