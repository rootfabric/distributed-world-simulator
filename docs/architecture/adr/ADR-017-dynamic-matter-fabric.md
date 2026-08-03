# ADR-017: Procedural volume with sparse persistent matter mutations

## Status

Accepted as target architecture for the mutable-worlds implementation plan.

This ADR supersedes `ADR-004-heightfield-plus-voxel.md`.

## Context

The current Moon implementation is a spherical heightfield rendered through GLOBAL, REGIONAL, LOCAL and ULTRA meshes. It scales to a real-size Moon, but cannot express caves, tunnels, overhangs, detached asteroid fragments or complete body destruction.

A full uniform voxel representation of a real-size body is not practical. A simple conversion of the current local mesh into voxels is also unsafe because the current near-surface generator contains observer-window-dependent detail and therefore is not a stable persistent source.

The project already has body-fixed reference frames, generic hierarchical simulation cells, aggregate shards, authority fencing, atomic multi-aggregate transactions, distributed-compute contracts and isolated world runtimes.

## Decision

Canonical solid matter is represented as a deterministic procedural volumetric field plus sparse persistent mutations.

```text
MatterState = procedural body and geology
            - procedural void features
            + compacted persistent mutations
            + active transient matter
```

Meshes, collision shapes, heightfields and far-surface summaries are derived representations.

The existing cube-sphere partition remains the surface/render/interest grid. Volumetric matter uses separate hierarchical 3D simulation cells in the same body-fixed frame.

Small bodies and planetary crust use one matter domain with different policies:

- small bodies permit global connectivity, fragmentation and terminal destruction;
- planetary bodies materialize only active crust regions and do not split globally after local excavation.

All excavation and deposition operations are authoritative mass-conserving transactions. Presentation and compute workers cannot commit canonical state.

The first implementation target is an isolated fixed-seed asteroid laboratory with radius 1000 m. Moon integration begins only after domain, persistence, meshing and destruction gates pass in the laboratory.

## Consequences

Positive:

- caves and tunnels are first-class volumes;
- untouched worlds remain cheap and reproducible;
- mining connects directly to Item Graph and containers;
- the same domain can model asteroids and planetary crust;
- existing surface LOD and network foundations remain reusable;
- local edits can later be distributed by authority shards.

Cost:

- a new canonical sampler and 3D addressing resolver are required;
- seams between far heightfield and local volume must be proven;
- global split detection for asteroids requires hierarchical connectivity;
- matter operations require explicit mass ledgers and compaction;
- the current Moon terrain monolith must be decomposed gradually.

## Rejected alternatives

### Uniform voxel Moon

Rejected because storage, generation, networking and persistence scale with the full planetary volume.

### Mesh as canonical state

Rejected because topology edits, deterministic sampling, persistence, geology and mass accounting become unreliable.

### Voxelize the local render mesh on first contact

Rejected because the current near mesh includes observer-local detail and because reconstruction from triangles loses the stable procedural identity of the body.

### Height displacement deltas only

Rejected because one radial height cannot represent caves, overhangs or multiple surfaces.

### Neural field as authoritative state

Rejected for the first implementation because exact replay, mass conservation, bounded local mutation and cross-version determinism are not sufficiently controllable.

## Required follow-up

Implementation order is defined in `docs/plans/MUTABLE_WORLDS_ROADMAP_RU.md`. The full paradigm and migration rules are defined in `docs/architecture/DYNAMIC_MATTER_FABRIC_RU.md`.
