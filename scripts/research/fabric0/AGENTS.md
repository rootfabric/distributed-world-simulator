# FABRIC research scoped instructions

Scope: `scripts/research/fabric0/**`.

Before modifying any FABRIC code, read:

1. root `AGENTS.md`;
2. `docs/research/FABRIC0_READ_FIRST_RU.md`;
3. `docs/research/FABRIC0_IDEOLOGY_RU.md`;
4. `docs/research/FABRIC0_RESEARCH_HISTORY_RU.md`;
5. `docs/research/FABRIC0_PROGRESS_RU.md`;
6. current checkpoint design/evidence.

Hard local rules:

```text
RESEARCH ONLY
DO NOT CLAIM PRODUCTION OWNERSHIP
CONSTRUCTION REMAINS CANONICAL SEMANTIC OWNER
NO DEVICE-SPECIFIC KERNEL CLASSES AS A SHORTCUT
PHYSICAL DIMENSION ERRORS FAIL CLOSED
IMPOSSIBLE / UNDERDETERMINED PHYSICS FAIL CLOSED
NUMERICAL ARTEFACTS MUST BE OBSERVABLE
PRESERVE HISTORICAL SOLVERS AS EVIDENCE; ADD SUCCESSORS
EVERY FUNDAMENTAL STEP NEEDS DESIGN + TEST + PLAYGROUND + VALIDATION + PROGRESS
GIT MUST BE SUFFICIENT TO RECOVER RESEARCH INTENT WITHOUT CHAT
```

When a new universal primitive is proposed, ask:

1. Is it truly lower-level than the devices it expresses?
2. Can it be reused across unrelated physical domains?
3. Does it preserve power/conservation/dimension contracts?
4. Does it reduce special cases instead of hiding them?
5. Does invalid physics remain observable?
6. Can an unknown-machine experiment falsify it?
7. Does it preserve Construction ownership?

Do not silently overwrite predecessor semantics to make a new test pass. If the conceptual model changes, create a new successor file and keep historical evidence intact.
