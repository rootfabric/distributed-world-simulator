# WORLD FILL — Noncanonical World Enrichment Train

Status: **parallel / noncritical / consumer-only**  
Branch: `feature/world-fill0-noncanonical-world-enrichment-r1`

## Why this train exists

Distributed World Simulator already invests heavily in correctness: authoritative state, matter, digging, persistence, handoff, ECO, WORLDGEN, FABRIC and networking. WORLD FILL exists for a different reason: make those correct systems read as a place rather than as a laboratory.

WORLD FILL is the presentation and environmental-enrichment layer between canonical simulation outputs and what a player sees, hears and remembers.

```text
CANON / FOUNDATION
P7 + MW + NETWORK + WORLDGEN + ECO + FABRIC
        |
        | read-only or derived outputs
        v
WORLD FILL
        |
        +-- dressing
        +-- props
        +-- decals / scars
        +-- ambience
        +-- audio / VFX feedback
        +-- landmarks
        +-- local place memory
        +-- labels
        +-- showcase tooling
```

## Constitutional rule

WORLD FILL MUST remain removable.

Deleting `world_fill/`, its lab scenes and its optional assets must not break:
- authoritative simulation;
- matter/digging execution;
- Item Graph;
- construction truth;
- persistence;
- region ownership / handoff;
- network protocol;
- ECO truth;
- WORLDGEN truth;
- FABRIC truth.

If a WORLD FILL item requires a new authoritative writer, a mandatory wire field, a new persistence owner, a new matter store, or a gameplay rule that changes canonical outcome, it is no longer WORLD FILL. Stop and promote it through the canonical design process.

## Allowed dependencies

WORLD FILL may consume:
- simulation tick and read-only clock projections;
- replicated command results;
- read-only terrain/surface descriptors;
- read-only ECO opportunity / ground-cover descriptors;
- read-only region / authority diagnostics;
- existing object transforms and presentation metadata;
- deterministic seeds already available to the client.

WORLD FILL must not become a prerequisite for those producers.

## Merge policy

Items are expected to mature in this branch or child lab branches first. Production merge is optional and item-by-item. A WORLD FILL feature can remain a lab indefinitely without blocking any product milestone.

## First integrated demo target

`scenes/labs/world_fill/world_fill_demo.tscn`

This scene is deliberately self-contained and asset-free at baseline. It gives plugin/content agents a stable target that boots even before external assets are accepted.

See:
- `WORLD_FILL_ROADMAP.md`
- `AGENT_PLUGIN_CONTENT_SCOUT.md`
