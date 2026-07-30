# ADR-013: Unified Networked Gameplay Core

## Status

Accepted as M1 candidate decision.

## Context

A2 accepted one semantic gameplay pipeline but recorded separate H1, H2 and H3 implementations and authority-coupled validators as `A2-D01` and `A2-D02`.

## Decision

All accepted topologies use `NetworkedGameplayService`. H1/H2/H3 public classes remain compatibility adapters. Canonical wire DTO validation lives under `scripts/runtime/networked_gameplay/contracts` and must not preload an authority implementation.

Topology is an adapter choice (`LOOPBACK` or `ENET`), not a domain fork. The service exposes the same identity, ownership, replay, movement, command-result and replication semantics in every topology.

## Consequences

- `A2-D01` and `A2-D02` are closed by M1.
- H1/H2/H3 regression suites remain valid through adapters.
- M2 may add a graphical dedicated client without adding another gameplay authority.
- M4 must route the full canonical Item Graph through the same service rather than extending the H3 fixture.
- Direct client/UI access to authority objects remains forbidden.
