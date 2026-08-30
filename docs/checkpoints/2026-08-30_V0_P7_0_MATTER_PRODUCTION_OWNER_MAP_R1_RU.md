# V0 P7.0 — Matter Production Owner Map / Convergence Gate

**Status:** REVIEW READY  
**Date:** 2026-08-30  
**Reviewed source base:** `07d71da1d301a65d36f56ff8c7a42795becab88d`  
**Runtime mutation:** NONE

## 1. Verdict

P7 must be implemented as a thin product-composition layer over already accepted owners.

```text
V0/P7 does not own Matter
V0/P7 does not own Item Graph
V0/P7 does not own persistence
V0/P7 does not own authority
V0/P7 does not own replication
V0/P7 does not own representation truth
```

The exact-source audit found **zero need for a new terrain contract or second canonical store**.

## 2. Product write path selected for P7.1

```text
accepted Gateway
    ↓
MW6 MatterAuthoritativeServer
    ├── validates envelope/session/epoch/body/operation/actor
    ↓
P7 stateless authorize_mutation gate
    ├── SM1 exact ACTIVE authority tuple
    ├── canonical V0 player read port
    ├── canonical P5 Item Graph equipment
    ├── bounded reach
    ├── MW8 regional lease
    └── MW9 durable fence when enabled
    ↓
existing MatterMutationRequest
    ↓
existing MW4 MatterExcavationService.execute()
    ↓
existing MW5 persistence
    ↓
existing MW6/MW7 replication
    ↓
RL2/RL3 derived presentation
```

The future P7 gate is an adapter only. It owns **zero durable state**.

## 3. Exact identities

### Actor

`MatterMutationRequest.actor_id` is the stable V0 `logical_player_id`.

This matches the existing MW6 peer actor binding and lets P7 read the canonical player state through:

`NetworkedGameplayService.get_player(logical_player_id)`.

### Tool

`MatterMutationRequest.tool_id` is the actual canonical Item Graph `item_id` of the equipped tool.

It is **not** `item/tool/mining`; that value is the definition.

Validation is:

```text
get_equipped_item(actor_id, "tool/main")
item.item_id       == request.tool_id
item.definition_id == "item/tool/mining"
item.quantity      == 1
```

No second equipment truth is created.

## 4. Why SM1CanonicalMutationGate is not reused directly

`sm1_canonical_mutation_gate.gd` deliberately authorizes domains declared by the P6 ownership map.

P6 declares player, Item Graph, equipment, Construction, outpost and replay domains. It does **not** declare Matter.

Therefore P7 must not:
- add Matter as a fake P6-owned domain;
- teach P6 admission to own Matter;
- create a second SM1 authority system.

P7 instead composes the lower-level canonical SM1 one-writer primitive:

`SM1AuthorityTransferCoordinator.authorize_write(authority_id, authority_epoch)`.

Then MW8/MW9 remain the Matter-region authority/fencing owners.

## 5. Existing Matter contract is sufficient

The accepted `MatterMutationRequest` already contains:
- operation identity;
- body identity;
- actor identity;
- tool identity;
- operation type;
- exact target bricks;
- expected revisions;
- swept shape;
- source/destination container identity;
- energy budget;
- client tick.

MW4 recomputes affected bricks from the swept shape and rejects any target-set mismatch.

Therefore:

```text
TerrainMutationRequest = FORBIDDEN DUPLICATE
TerrainMutationResult  = FORBIDDEN DUPLICATE
```

## 6. Single-region vs multi-region

MW8 already returns:

`MATTER_CROSS_REGION_MUTATION_REQUIRES_COORDINATION`

when one request resolves to more than one Matter authority region.

MW10 transaction plans require at least two participants.

Canonical rule:

```text
player crosses A → B
+
dig entirely inside B
=
SM1 handoff + ordinary MW4/MW8 mutation

one swept Matter mutation touches A + B
=
MW10
```

Actor seam crossing by itself never selects MW10.

## 7. Material output and Item Graph

MW4 already creates deterministic `MatterMaterialBatch` objects and persists them with the Matter receiver through MW5.

The canonical Item Graph already exposes a trusted server output seam:

```text
preflight_server_output(...)
apply_server_output(...)
```

Therefore P7.3 must **reuse** that seam.

The Matter batch is extraction provenance/staging, not gameplay inventory. The Item Graph is the spendable gameplay inventory truth.

No new delivery ledger is allowed. Item delivery idempotency must use the existing Item Graph replay ledger with a deterministic operation id derived from the Matter source operation/batch.

P7.0 intentionally does **not** invent a kg-per-item conversion. P7.3 must explicitly define and test:
- material/composition → item definition;
- mass per item or other deterministic quantization;
- rounding/residual accounting;
- conservation.

This unresolved conversion policy is bounded P7.3 implementation work, not an ownership ambiguity.

## 8. Persistence

MW5 already checkpoints atomically:
- Matter sparse store;
- material receiver;
- mutation journal.

P7 creates no persistence owner.

For the later product aggregate, Item Graph durability remains the existing authoritative recovery pipeline. Cross-domain restart acceptance in P7.4 must prove both worlds reconstruct to the same operation outcome without duplicate material delivery.

## 9. Representation

RL2 meshing and RL3 streaming are derived/disposable:

```text
Matter mutation
→ representation invalidation
→ RL2 mesh rebuild
→ RL3 source-revision-fenced streaming
```

Neither layer may become canonical Matter truth.

## 10. P7.1 concrete implementation boundary

P7.1 is now narrowly defined:

`scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd`

It implements only the interface already expected by MW6:

`authorize_mutation(request)`.

It is configured with existing owners/read ports and stores no canonical or durable state.

## 11. Stop conditions

Stop if P7.1 attempts any of:
- new terrain mutation request/result;
- new operation/replay ledger;
- new item/resource inventory;
- new persistence store;
- new authority directory;
- new replication protocol;
- new InterestManager;
- client-supplied authority/fencing state;
- mutation of MW4–MW10 semantics instead of consumption.

## 12. P7.0 acceptance decision

P7.0 owner-map content is frozen for fresh exact-source review.

The owner map is machine-readable at:

`config/control/harness/v0-p7-matter-production-owner-map.v1.json`.
