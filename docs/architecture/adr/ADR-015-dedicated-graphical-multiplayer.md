# ADR-015: Replica-only remote player presentation for two graphical clients

- Status: Accepted as M3 candidate decision
- Date: 2026-07-30
- Checkpoint: `v16.10.2-runtime-m3-dedicated-graphical-multiplayer`

## Decision

A single headless dedicated server owns the unified `NetworkedGameplayService`. Two ordinary graphical Godot clients connect through ENet and receive the same authoritative player snapshot/delta stream.

Each client composes its local logical player as the real `LunarPlayer` and every other connected logical player as a `RemotePlayerPresenter`. A remote presenter has no input, command, authority or domain references. It interpolates render position toward the authoritative target and applies replicated orientation and flashlight state.

Spawn and despawn are derived from replicated connected state. Reconnect preserves logical/player entity identity, creates a new transport session, advances ownership epoch and respawns remote presentation.

Automated acceptance uses explicit presentation and checksum convergence barriers. Graceful leave occurs only after the peer observed presentation state and after all active processes captured the same canonical checksum.

## Consequences

- The local and remote presentation paths are explicit and testable.
- Render interpolation cannot mutate canonical gameplay state.
- ENet remains the realtime client transport.
- Full canonical Item Graph gameplay and contention remain M4 work.
- Graphical end-to-end shared gameplay acceptance remains M5 work.
