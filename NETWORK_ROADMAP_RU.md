# PlanetSimulator — укреплённая distributed runtime roadmap

Текущий candidate: `v16.8.1-architecture-a1-generic-aggregate`.
Принятый runtime: `v16.8.0-runtime-h0-listen-host`.

```text
N0–N2 accepted
R3.1 accepted
A0 accepted
H0 accepted
A1 current candidate
→ S0 next
→ T1
→ B0
→ M0
→ S1
```

A1 создаёт generic identity/authority/spatial/snapshot/delta/adapter/store слой, не изменяя EntitySnapshotEnvelope v1 и item-backed WorldEntityAggregate. Directory, NATS, Population Field и workers остаются после обязательных foundation prerequisites.
