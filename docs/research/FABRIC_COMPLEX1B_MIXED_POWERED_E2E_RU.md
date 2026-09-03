# FABRIC COMPLEX1B — Visual Mixed-Representation Powered E2E

**Статус:** IMPLEMENTED / exact Linux-double verification pending  
**Ветка:** feature/fabric-complex1b-visual-mixed-e2e-r1  
**Parents:** CX2-VIS + closed BRIDGE-2 @ c9dec386ea21....

## Цель

COMPLEX1B связывает четыре доказанные линии:

COMPLEX0 @ 2000 → real guard / local FULL / canonical BOND_BREAK / split / rebake  
COMPLEX1A → battery → supported wire → lamp  
BRIDGE-2-A → one active event evaluator / exactly-once ownership  
BRIDGE-2 CLOSED → simultaneous executable mixed representations

Главный acceptance: FULL powered baseline == MIXED powered subject по same event ID, same broken bond, same Construction revision, same split/rebake, same functional support loss, same lamp state и exactly-once semantics.

## Canonical ownership

Construction / Matter остаётся единственной truth. FULL, STRUCTURAL_BAKE, CONTACT_BAKE, DYNAMIC_ROM и HYBRID_BAKE являются derived executable representations.

Impact region:
- FULL = ACTIVE_EXECUTION
- STRUCTURAL_BAKE = OBSERVER
- CONTACT_BAKE = OBSERVER

Structural break вычисляет только FULL evaluator, а canonical commit остаётся внешнему canonical authority owner. Derived representations не имеют canonical write authority.

## Почему пять режимов

Target требует одновременно FULL + STRUCTURAL_BAKE + DYNAMIC_ROM + HYBRID_BAKE. Closed BRIDGE-2 R1 дополнительно требует CONTACT_BAKE, поэтому COMPLEX1B сохраняет все пять:

impact → FULL  
stable → STRUCTURAL_BAKE  
contact → CONTACT_BAKE  
dynamic → DYNAMIC_ROM  
hybrid → HYBRID_BAKE

## Read-only executable projection master

Closed BRIDGE-2 использует per-region source slices. COMPLEX1B создаёт только derived executable projection sources:
- domain CONSTRUCTION из-за ограничения representation contract;
- source hashes производны от exact canonical frontier;
- mutable_source_ids = [];
- readonly_source_ids = 5;
- canonical write невозможен.

После canonical mutation меняются только region/impact и region/stable-structure projection dependencies.

## Invalidation / rebuild

canonical BOND_BREAK  
→ projection source update  
→ FULL impact slice refresh required  
→ STRUCTURAL_BAKE STALE  
→ mixed step blocked fail-closed  
→ FULL projection refresh  
→ still blocked by structural STALE  
→ STRUCTURAL_BAKE rebuild  
→ all five regions executable  
→ mixed flow resumes

State handoff errors должны быть exactly zero.

## FULL reference equality

BRIDGE-2 mixed runtime и FULL reference проходят одинаковые FLOW steps до и после event/rebuild.

Required bound: max |mixed_state - full_reference_state| <= 1e-12.

## Powered chain

BATTERY → wire/path-a → LAMP, где wire/path-a поддерживается exact COMPLEX0 break_bond_id.

До break: lamp ON.  
После same event ID: SUPPORT_TOPOLOGY_LOST → wire removed → Fabric.solve() → voltage/current/power = 0 → lamp OFF.

CX2-VIS остаётся отдельным redundant-path falsifier: A broken → ON, B broken → ON, A+B broken → OFF. Он не подменяет single-path FULL baseline COMPLEX1A.

## Visual scene

res://scenes/labs/fabric/complex1b_mixed_powered_e2e.tscn

2000 parts делятся на MultiMesh batches:
- 20-part impact → FULL;
- adjacent contact → CONTACT_BAKE;
- bounded early region → DYNAMIC_ROM;
- bounded late region → HYBRID_BAKE;
- остальные → STRUCTURAL_BAKE.

Stages:
MIXED_BASELINE → IMPACT_FULL_OWNS_EVENT → CANONICAL_BREAK → STRUCTURAL_STALE → MIXED_REBUILT → FULL_REFERENCE_EQUAL.

Controls: Space next, R reset, 1 world, 2 physics, 3 causal.

## Files

scripts/research/fabric_bake0/complex1b_mixed_powered_observation_v1.gd  
scripts/labs/fabric/complex1b_mixed_powered_e2e.gd  
scenes/labs/fabric/complex1b_mixed_powered_e2e.tscn  
tests/research/fabric_bake0/fabric_bake_complex1b_mixed_powered_e2e_acceptance.gd  
RUN_FABRIC_COMPLEX1B_TESTS.sh  
.github/workflows/fabric-complex1b-linux-double.yml

CX observation получает только provenance fields: canonical_frontier_hash_before/after, construction_revision_before/after, canonical_execution_owner. Existing checksum semantics не меняются.

## Non-claims

COMPLEX1B не заявляет secondary debris collisions, post-split ballistic fragment simulation, B0.6 adaptive fidelity или production acceptance. Read-only projection sources не являются canonical Construction.
