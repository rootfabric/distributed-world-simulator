# Distributed World Simulator — Directional Watch Report

Generated: `2026-09-16T13:49:02Z`  
Overall health: **RED**

This is the PC0 directional dependency supplement:

```text
producer branch changed files
            ∩
consumer watched_paths / critical_watched_paths
            ↓
consumer YELLOW / RED
```

- **YELLOW** `CH → NX` (WATCH_HIT, BLOCKING): `scripts/characters/equipment/network_character_equipment_gameplay_controller.gd`, `scripts/characters/lab/quaternius_playable_network_equipment_lab.gd`, `scripts/runtime/networked_gameplay/ch9/ch9_3_item_graph_replica_adapter.gd`, `scripts/runtime/networked_gameplay/ch9/ch9_3_network_item_command_bridge.gd`
- **YELLOW** `NX → ECO` (WATCH_HIT, ADVISORY_RESEARCH): `scripts/network/authority/movement_authority_profile.gd`
- **YELLOW** `NX → T` (WATCH_HIT, BLOCKING): `scripts/network/authority/movement_authority_profile.gd`
- **YELLOW** `V0 → ECO` (WATCH_HIT, ADVISORY_RESEARCH): `scripts/network/prediction/predicted_item_interaction_journal.gd`
- **YELLOW** `V0 → T` (WATCH_HIT, BLOCKING): `scripts/network/prediction/predicted_item_interaction_journal.gd`
- **RED** `V0 → NX` (CRITICAL_WATCH_HIT, BLOCKING): `scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd`
- **YELLOW** `V0 → NX` (WATCH_HIT, BLOCKING): `scripts/network/prediction/predicted_item_interaction_journal.gd`

Accepted critical-watch clearance never deletes a dependency finding. It downgrades only the exact reviewed hit to the ordinary watched health while the reviewed producer head remains an ancestor, the consumer head/passport remain exact, the complete observed watched hit-set remains exact, and every fenced watched blob remains byte-identical at both the reviewed head and current producer branch. Any drift fails closed back to the raw critical level.

Accepted handoff/evidence stages listed in `directional_watch_policy.producer_suppression_stage_statuses` remain consumers but no longer act as active producers. RESEARCH_DESIGN_FRONTIER consumers remain fully visible but are advisory to global health.
