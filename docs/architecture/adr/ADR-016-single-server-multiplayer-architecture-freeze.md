# ADR-016: Single-server multiplayer architecture freeze

## Status

Candidate for acceptance in `v16.10.6-architecture-a3-single-server-multiplayer`.

## Context

M1-M6 proved unified gameplay semantics, ordinary graphical clients, canonical Item Graph contention, reconnect/replay and crash-safe dedicated recovery. Introducing a server-to-server broker without a freeze would risk a second gameplay path and topology-specific authority rules.

## Decision

`NetworkedGameplayService` is the only production gameplay semantic service. Listen-host, ENet, compatibility and recovery layers are adapters. Graphical clients are replica-only. ENet remains the graphical realtime transport.

B1 may implement NATS Core only behind B0 server-to-server semantic ports. B1 cannot introduce gameplay DTOs, direct broker calls from gameplay/domain code, subject names in canonical state, broker-owned authority, or a replacement for ENet.

Production multi-authority remains blocked until A3, B1 and B2 are accepted.

## Consequences

- topology adapters are replaceable without changing canonical gameplay state;
- wire-contract evolution requires an explicit versioned checkpoint;
- B1 can focus on service discovery and request/reply equivalence;
- N3 cannot begin as production integration before durable server-to-server delivery exists;
- production authentication remains tracked separately as A2-D05.
