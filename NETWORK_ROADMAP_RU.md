# PlanetSimulator — укреплённая distributed runtime roadmap

Текущий candidate: `v16.8.4-data-plane-b0-message-bus-contracts`.
Принятая база: `v16.8.3-network-t1-multi-peer`.

```text
N0–N2 accepted
R3.1 accepted
A0 accepted
H0 accepted
A1 accepted
S0 accepted
T1 accepted
B0 current candidate
→ M0
→ S1
```

B0 разделяет request/reply, event stream, job queue, replication и bulk semantics. NATS Core, JetStream, Directory, Population Field и workers остаются после обязательных transaction/compute foundations.
