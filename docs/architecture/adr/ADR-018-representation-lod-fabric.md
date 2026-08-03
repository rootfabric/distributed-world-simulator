# ADR-018: Unified Representation LOD Fabric

- **Status:** Proposed by RL0 candidate
- **Date:** 2026-08-02
- **Base:** accepted MW8 regional authority handoff

## Context

Dynamic Matter Fabric can already produce detailed local meshes from sparse bricks, and Construction C18 can choose logical LOD/activity tiers. Neither path yet provides a shared identity, provenance, invalidation, cache and selection model for real coarse meshes and impostors.

Separate ad-hoc LOD systems would duplicate network budgets, cache lifecycle and authority fences while still requiring different geometry algorithms.

## Decision

Introduce a shared Representation LOD Fabric with:

- exact source revision and dependency hashes;
- versioned representation keys;
- content-addressed artifact manifests;
- screen/geometric error selection;
- collision/interior capability fences;
- bandwidth budgets;
- hierarchical invalidation;
- derived cache lifecycle.

Matter and Construction share these contracts but do not share a mesher.

Canonical state never contains mesh, image, collision shape, RID or SceneTree object. Authority handoff transfers canonical state; representation cache is optional.

## Consequences

Positive:

- distant mutations can be visible without detailed brick replication;
- large constructs can use HLOD without changing Item Graph/Construct semantics;
- artifacts can be cached and reused by hash;
- dirty rebuild is bounded to ancestor chains;
- MW8 handoff remains correct without cache transfer.

Costs:

- summary pyramid and artifact scheduler become explicit subsystems;
- cross-level seams require a dedicated Matter solution;
- stale-while-rebuild needs strict close-collision fences;
- network streaming gains manifests, bulk delivery and cancellation in RL3.

## Rejected alternatives

1. Store generated meshes as world state — rejected because presentation format would become authoritative.
2. Use only distance thresholds — rejected because object scale, camera zoom and geometric error differ.
3. Use one common mesher for Matter and Construction — rejected because SDF isosurface extraction and semantic part clustering are different problems.
4. Rebuild one whole-body mesh after every edit — rejected because mutation cost would scale with the entire body or construct.
