# ADR-014: Dedicated authority with replica-only graphical client

- Status: Accepted as M2 candidate decision
- Date: 2026-07-30
- Checkpoint: `v16.10.1-runtime-m2-dedicated-graphical-client`

## Decision

An ordinary graphical Godot client connects to a headless dedicated server through ENet. The dedicated process owns `NetworkedGameplayService`; the graphical process owns presentation, input, command transport and replica state only.

The local `LunarPlayer` is a replica-driven presentation object. It does not integrate an independent authoritative `CharacterBody3D` state. Client input is emitted as bounded versioned commands relative to the last authoritative snapshot, and corrections are applied from the replica store.

Reconnect creates a new transport session and ownership epoch while preserving logical player identity, stable player entity identity and committed canonical state. Client operation IDs are process-scoped to prevent false replay collisions across reconnect processes.

## Consequences

- Dedicated and listen-host continue to use the same M1 gameplay service.
- Graphical clients cannot access authority or domain objects directly.
- ENet remains the realtime graphical transport.
- One graphical client is production-proven; simultaneous graphical clients and remote presentation remain M3 work.
