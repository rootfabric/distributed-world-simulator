# M7 Legacy N Lineage Handoff — 2026-08-11

## Status

`feature/m7-sequence-aware-reconciliation-fix10-fix6-semantic-baseline` is **SUPERSEDED AS THE ACTIVE NETWORK FRONTIER**.

It remains available as research history, diagnostics, regression fixtures and source evidence. It must not be merged or rebased wholesale into `main`.

Canonical active network convergence now lives on:

`feature/nx-m7-owner-authority-convergence`

created from current main lineage and registered by PC0.

## Accepted evidence retained from this branch

- owner-authoritative validated locomotion visual behavior;
- two-client LOCAL diagnostic with zero local corrections and no owner send failures;
- remote interpolation without moving holds/underruns in the accepted manual run;
- server-authoritative item ownership and drop;
- same-authority-revision optimistic item rollback;
- Godot `Basis(-Z) <-> yaw` orientation correction;
- focused FIX10/FIX9/FIX8/NX4 regression evidence;
- `docs/validation/M7_OWNER_AUTHORITY_ACCEPTANCE_2026-08-11.md`.

Validated runtime evidence head: `464e1b8dd27fad8b4d477f6e76ca52a449893353`.
Acceptance/status record head: `538674d1f3f991c9e04d77b0ce0a4dfea24d9ce6`.

## Explicitly not accepted for production convergence

Legacy `scripts/world/testing/playground_view_relative_runtime_fix7.gd` writes the physics player transform/velocity from `_process()`. That render/physics second-writer pattern is blocked from transfer.

The accumulated FIX6/FIX7/FIX8/FIX9/FIX10 inheritance ladder is also not itself a production architecture. Capabilities must be reimplemented/minimized on the fresh NX convergence branch.

## Branch discipline

No new feature development should continue here. New network production work belongs to the registered NX convergence frontier. This branch may receive only evidence/documentation corrections that do not change the accepted runtime evidence head.
