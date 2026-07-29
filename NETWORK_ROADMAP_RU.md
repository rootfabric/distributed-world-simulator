# PlanetSimulator — укреплённая distributed runtime roadmap

Текущий candidate: `v16.8.5-domain-m0-aggregate-transactions`.
Принятая база: `v16.8.4-data-plane-b0-message-bus-contracts`.

```text
N0–N2 accepted
R3.1 accepted
A0 accepted
H0 accepted
A1 accepted
S0 accepted
T1 accepted
B0 accepted
M0 current candidate
→ S1
```

M0 объединяет staged multi-aggregate mutations, cross-aggregate invariants, stable replay result и durable outbox в одном atomic commit. NATS Core, JetStream, Directory, Population Field и workers остаются после принятия M0 и S1.
