# FABRIC COMPLEX1B — Visual Mixed-Representation Powered E2E

**Статус:** IMPLEMENTED / LOCAL ATTACHED CANONICAL DOUBLE EXACT VERIFIED  
**Ветка:** feature/fabric-complex1b-visual-mixed-e2e-r1  
**Exact code subject:** 6eeba52b550f2d9e8fff8c4fd3c571fa88fbcfb8  
**Exact TREE:** 92b4548f4cf70bd86087a47d949d2753a79ed08d  
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

## Atomic multi-region invalidation / rebuild

Exact integration falsifier показал, что последовательный single-region rebuild некорректен для одного canonical event, который одновременно меняет два projection slice.

Fail-closed probe:

canonical BOND_BREAK  
→ impact + stable projection sources change  
→ Runtime.apply_master_update()  
→ both regions become affected  
→ mixed step blocked  
→ rebuild only FULL impact  
→ BRIDGE2_REBUILD_REGISTRY_FAILED

Это ожидаемый результат: Registry.create() не должен временно принимать registry, где один affected slice уже fresh, а другой всё ещё stale относительно нового master frontier.

Correct COMPLEX1B ordering:

canonical BOND_BREAK  
→ projection source update  
→ impact + stable affected together  
→ mixed step blocked fail-closed  
→ build fresh FULL impact adapter  
→ build fresh STRUCTURAL_BAKE stable adapter  
→ one atomic Registry.create() over complete affected set  
→ switch registry hash once  
→ clear both invalidation buckets  
→ FULL state handoff error = 0  
→ STRUCTURAL_BAKE state handoff error = 0  
→ all five regions executable  
→ mixed flow resumes

Closed BRIDGE-2 runtime не менялся; atomic multi-region orchestration находится только в COMPLEX1B integration layer.

## FULL reference equality

BRIDGE-2 mixed runtime и FULL reference проходят одинаковые FLOW steps до и после event/rebuild.

Required bound: max |mixed_state - full_reference_state| <= 1e-12.

Exact acceptance подтвердил bound.

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

## Exact verification

Canonical attached Godot:

4.7.1.stable.double.custom_build.a13da4feb  
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

Exact source carrier:
- run 33852110819
- artifact 9928724471
- artifact digest sha256:788abb3ca1b6c0ff9d7de1561a0547a5e2faf85a3abecd7040ee1829a7aefcc2
- artifact head 6eeba52b550f2d9e8fff8c4fd3c571fa88fbcfb8

Results:

FABRIC COMPLEX1B Mixed Powered E2E Acceptance: PASS (57 assertions)  
atomic_rebuild=impact+stable  
mixed=FULL_REFERENCE

FABRIC BRIDGE-2 Mixed Generic Machine R1 Acceptance: PASS (125 assertions)  
initial mixed-flow max FULL delta=0

Project Control на exact code subject: SUCCESS. Dedicated self-hosted Linux-double workflow может оставаться queued; он не подменяется этим локальным exact evidence.

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
