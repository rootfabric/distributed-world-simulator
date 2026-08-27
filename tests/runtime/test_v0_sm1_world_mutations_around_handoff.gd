extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const Item = preload("res://scripts/items/domain/item_instance.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const ItemGraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")
const Aggregate = preload("res://scripts/construction/domain/construct_aggregate.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const ConstructStore = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const ConstructMutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const ConstructionProjection = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ConstructionPlanner = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const M0Bridge = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const ConstructionAuthority = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P6Projection = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const P6Shadow = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const P6PersistenceOwner = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const TransferCoordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const WorldContinuity = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_world_state_continuity.gd")
const MutationGate = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_canonical_mutation_gate.gd")

const AUTHORITY_A := "authority/a"
const AUTHORITY_B := "authority/b"
const PLAYER := "player/sm1-7-11"
const CONTAINER_ID := "container/sm1-7-11/backpack"
const PRIMARY_CONSTRUCT := "construct/sm1-7-11/primary"
const PRIMARY_ROOT := "item/00000000-0000-4000-8000-000000007111"
const PRIMARY_PANEL := "item/00000000-0000-4000-8000-000000007112"
const SECONDARY_CONSTRUCT := "construct/sm1-7-11/secondary"
const SECONDARY_ROOT := "item/00000000-0000-4000-8000-000000007113"
const SECONDARY_PANEL := "item/00000000-0000-4000-8000-000000007114"
const ORE_A := "item/00000000-0000-4000-8000-000000007115"
const ORE_B := "item/00000000-0000-4000-8000-000000007116"
const ORE_C := "item/00000000-0000-4000-8000-000000007117"

const DOMAIN_ITEM := "p6-domain/item-inventory"
const DOMAIN_CONSTRUCTION := "p6-domain/construction-builds"
const DOMAIN_OUTPOST := "p6-domain/outpost-world-state"

var assertions := 0
var failures: Array[String] = []
var gameplay := {
	"schema": "sm1.7.11.canonical_gameplay.v1",
	"revision": 1,
	"outpost_id": "outpost/sm1-7-11",
	"phase": "BOOTSTRAP",
	"mutations": [],
}


class ExistingRecoveryCoordinator:
	extends RefCounted

	func persist_checkpoint(_checkpoint_id: String, _generation: int, _previous_generation: int, _committed_operation_id: String = "") -> Dictionary:
		return {"success": true, "details": {"checkpoint": {}, "repository": {}}}

	func recover_latest() -> Dictionary:
		return {"success": true, "details": {"checkpoint": {}, "repository": {}}}


func _init() -> void:
	var rt := _make_runtime()
	var domain: Dictionary = rt.domain
	var construction = rt.construction
	var item_persistence = rt.item_persistence

	var projection = P6Projection.new()
	var shadow = P6Shadow.new()
	var persistence = P6PersistenceOwner.new()
	_assert(_ok(persistence.configure(ExistingRecoveryCoordinator.new())), "7.11 persistence adapter configured")

	var coordinator = TransferCoordinator.new()
	_assert(_ok(coordinator.configure(AUTHORITY_A, 1, {
		"logical_player_id": PLAYER,
		"player_entity_id": "entity/sm1-7-11",
		"last_input_sequence": 0,
		"last_operation_id": "operation/sm1-7-11/bootstrap",
	})), "7.11 transfer coordinator configured")
	var gate = MutationGate.new()
	_assert(_ok(gate.configure(coordinator)), "7.11 canonical mutation gate configured")
	var world = WorldContinuity.new()

	_refresh_projection(projection, shadow, item_persistence, construction)
	_assert(_ok(world.configure(item_persistence, construction, persistence, projection, coordinator)), "7.11 world continuity configured")
	var projection_before_private := projection.compute_checksum()
	_assert(not projection.apply_delta({"attempt": "private-outpost-write"}), "7.11 P6 projection rejects private canonical mutation")
	_assert(projection.compute_checksum() == projection_before_private, "7.11 rejected projection mutation changes no state")

	# ACTIVE A/1: all three domain classes may mutate, but only after the SM1
	# tuple gate admits the current writer.
	_authorized_item_add(gate, coordinator, domain, AUTHORITY_A, 1, ORE_A, 2, "operation/sm1-7-11/a/item")
	_authorized_construct_assemble(gate, coordinator, domain, construction, AUTHORITY_A, 1, "operation/sm1-7-11/a/build")
	_authorized_outpost_mutation(gate, coordinator, AUTHORITY_A, 1, "A_ACTIVE", "operation/sm1-7-11/a/outpost")
	_refresh_projection(projection, shadow, item_persistence, construction)
	var a_active := _fingerprints(item_persistence, construction, projection)
	_assert(int(gameplay.revision) == 2, "7.11 A-era outpost revision advanced once")
	_assert(not construction.get_construct_snapshot(SECONDARY_CONSTRUCT).is_empty(), "7.11 A-era construction assembly is canonical")
	_assert(domain.items.get_item(ORE_A) != null, "7.11 A-era Item Graph mutation is canonical")

	# Freeze A -> B and capture the world. Both source and target domain writes
	# must be blocked until the transfer reaches ACTIVE B/2.
	var transfer_ab := "transfer/sm1-7-11/a-b"
	_assert(_ok(coordinator.begin_transfer(transfer_ab, AUTHORITY_A, AUTHORITY_B, 1)), "7.11 A->B begin")
	var prepared_ab := world.prepare_transfer(transfer_ab)
	_assert(_ok(prepared_ab), "7.11 A->B world capture")
	var manifest_ab: Dictionary = Dictionary(prepared_ab.get("details", {}).get("manifest", {}))
	_assert(String(manifest_ab.get("item_graph_fingerprint", "")) == String(a_active.item), "7.11 A->B capture includes A-era Item Graph mutation")
	_assert(String(manifest_ab.get("construction_fingerprint", "")) == String(a_active.construction), "7.11 A->B capture includes A-era Construction mutation")
	_assert(String(manifest_ab.get("outpost_projection_checksum", "")) == String(a_active.outpost), "7.11 A->B capture includes A-era outpost mutation")
	_assert(int(manifest_ab.get("construct_count", 0)) == 2, "7.11 A->B manifest sees both canonical constructs")
	var frozen_ab := _fingerprints(item_persistence, construction, projection)
	_assert(_fenced(gate.authorize(AUTHORITY_A, 1, DOMAIN_ITEM, "operation/sm1-7-11/frozen/a/item")), "7.11 frozen source Item mutation rejected")
	_assert(_fenced(gate.authorize(AUTHORITY_B, 2, DOMAIN_CONSTRUCTION, "operation/sm1-7-11/frozen/b/build")), "7.11 warm target Construction mutation rejected")
	_assert(_fenced(gate.authorize(AUTHORITY_A, 1, DOMAIN_OUTPOST, "operation/sm1-7-11/frozen/a/outpost")), "7.11 frozen source outpost mutation rejected")
	_assert(_fingerprints(item_persistence, construction, projection) == frozen_ab, "7.11 A->B zero-writer gap changes no canonical world state")
	_complete_transfer(world, shadow, coordinator, transfer_ab, AUTHORITY_A, AUTHORITY_B, 1, 2)
	_assert(_ok(world.validate_after_activation(transfer_ab, coordinator)), "7.11 A->B world continuity after mutations")

	# ACTIVE B/2: evolve all three canonical domains again. Construction
	# deconstruction atomically changes both P4 Construction and the shared M4
	# Item Graph, while the explicit Item mutation exercises inventory alone.
	_authorized_item_add(gate, coordinator, domain, AUTHORITY_B, 2, ORE_B, 3, "operation/sm1-7-11/b/item")
	_authorized_construct_deconstruct(gate, coordinator, domain, construction, AUTHORITY_B, 2, "operation/sm1-7-11/b/deconstruct")
	_authorized_outpost_mutation(gate, coordinator, AUTHORITY_B, 2, "B_ACTIVE", "operation/sm1-7-11/b/outpost")
	_refresh_projection(projection, shadow, item_persistence, construction)
	var b_active := _fingerprints(item_persistence, construction, projection)
	_assert(String(b_active.item) != String(a_active.item), "7.11 B-era Item Graph fingerprint evolves")
	_assert(String(b_active.construction) != String(a_active.construction), "7.11 B-era Construction fingerprint evolves")
	_assert(String(b_active.outpost) != String(a_active.outpost), "7.11 B-era outpost projection checksum evolves")
	_assert(construction.get_construct_snapshot(SECONDARY_CONSTRUCT).is_empty(), "7.11 B-era deconstruction committed")
	_assert(domain.items.get_item(ORE_A) != null and domain.items.get_item(ORE_B) != null, "7.11 A/B inventory mutations coexist")

	var transfer_ba := "transfer/sm1-7-11/b-a"
	_assert(_ok(coordinator.begin_transfer(transfer_ba, AUTHORITY_B, AUTHORITY_A, 2)), "7.11 B->A begin")
	var prepared_ba := world.prepare_transfer(transfer_ba)
	_assert(_ok(prepared_ba), "7.11 B->A world capture")
	var manifest_ba: Dictionary = Dictionary(prepared_ba.get("details", {}).get("manifest", {}))
	_assert(String(manifest_ba.get("item_graph_fingerprint", "")) == String(b_active.item), "7.11 B->A capture includes B-era Item Graph mutation")
	_assert(String(manifest_ba.get("construction_fingerprint", "")) == String(b_active.construction), "7.11 B->A capture includes B-era Construction mutation")
	_assert(String(manifest_ba.get("outpost_projection_checksum", "")) == String(b_active.outpost), "7.11 B->A capture includes B-era outpost mutation")
	var frozen_ba := _fingerprints(item_persistence, construction, projection)
	_assert(_fenced(gate.authorize(AUTHORITY_B, 2, DOMAIN_ITEM, "operation/sm1-7-11/frozen/b/item")), "7.11 frozen B Item mutation rejected")
	_assert(_fenced(gate.authorize(AUTHORITY_A, 3, DOMAIN_CONSTRUCTION, "operation/sm1-7-11/frozen/a/build")), "7.11 warm A Construction mutation rejected")
	_assert(_fenced(gate.authorize(AUTHORITY_A, 3, DOMAIN_OUTPOST, "operation/sm1-7-11/frozen/a/outpost")), "7.11 warm A outpost mutation rejected")
	_assert(_fingerprints(item_persistence, construction, projection) == frozen_ba, "7.11 B->A zero-writer gap changes no canonical world state")
	_complete_transfer(world, shadow, coordinator, transfer_ba, AUTHORITY_B, AUTHORITY_A, 2, 3)
	_assert(_ok(world.validate_after_activation(transfer_ba, coordinator)), "7.11 B->A world continuity after mutations")

	# ACTIVE A/3 after return: prove the canonical owners remain usable and that
	# the same construct can be reassembled from the B-era deconstruction state.
	_authorized_item_add(gate, coordinator, domain, AUTHORITY_A, 3, ORE_C, 4, "operation/sm1-7-11/a3/item")
	_authorized_construct_assemble(gate, coordinator, domain, construction, AUTHORITY_A, 3, "operation/sm1-7-11/a3/build")
	_authorized_outpost_mutation(gate, coordinator, AUTHORITY_A, 3, "A_RETURN", "operation/sm1-7-11/a3/outpost")
	_refresh_projection(projection, shadow, item_persistence, construction)
	var final_state := _fingerprints(item_persistence, construction, projection)
	_assert(String(final_state.item) != String(b_active.item), "7.11 return-era Item Graph fingerprint evolves")
	_assert(String(final_state.construction) != String(b_active.construction), "7.11 return-era Construction fingerprint evolves")
	_assert(String(final_state.outpost) != String(b_active.outpost), "7.11 return-era outpost checksum evolves")
	_assert(int(gameplay.revision) == 4 and String(gameplay.phase) == "A_RETURN", "7.11 outpost canonical source reaches final A-return revision")
	_assert(domain.items.get_item(ORE_A) != null and domain.items.get_item(ORE_B) != null and domain.items.get_item(ORE_C) != null, "7.11 all cross-authority inventory mutations survive")
	_assert(not construction.get_construct_snapshot(SECONDARY_CONSTRUCT).is_empty(), "7.11 construction remains mutable after A->B->A")
	_assert(_ok(domain.validator.validate_graph()), "7.11 final canonical Item Graph validates")
	var final_item_snapshot := _canonical_item_snapshot(item_persistence)
	var final_construction_snapshot: Dictionary = construction.export_state()
	_assert(NetworkUtils.payload_hash(projection.get_source("item_graph")) == NetworkUtils.payload_hash(final_item_snapshot), "7.11 outpost projection reads final canonical Item Graph exactly")
	_assert(NetworkUtils.payload_hash(projection.get_source("construction")) == NetworkUtils.payload_hash(final_construction_snapshot), "7.11 outpost projection reads final canonical Construction exactly")
	_assert(NetworkUtils.payload_hash(projection.get_source("gameplay")) == NetworkUtils.payload_hash(gameplay), "7.11 outpost projection reads final canonical gameplay exactly")

	var gate_report: Dictionary = gate.get_report()
	var gate_counters: Dictionary = Dictionary(gate_report.get("counters", {}))
	_assert(int(gate_counters.get("authorized", 0)) == 9, "7.11 exactly nine active-tuple domain mutations authorized")
	_assert(int(gate_counters.get("fenced", 0)) == 6, "7.11 exactly six transfer-gap mutation attempts fenced")
	_assert(int(gate_counters.get("world_entity_reconciliations", 0)) == 3, "7.11 three Construction mutations reconcile through canonical M4 world entities")
	_assert(not bool(gate_report.get("private_item_graph", true)), "7.11 mutation gate owns no Item Graph")
	_assert(not bool(gate_report.get("private_construction_truth", true)), "7.11 mutation gate owns no Construction truth")
	_assert(not bool(gate_report.get("private_outpost_truth", true)), "7.11 mutation gate owns no outpost truth")
	_assert(not bool(gate_report.get("private_persistence_owner", true)), "7.11 mutation gate owns no persistence")
	_assert(int(world.get_report().get("completed_count", 0)) == 2, "7.11 world continuity completed both mutated transfers")
	_assert(int(coordinator.snapshot().get("authority_epoch", 0)) == 3 and String(coordinator.snapshot().get("active_authority_id", "")) == AUTHORITY_A, "7.11 final authority tuple remains A/3")
	_finish()


func _authorized_item_add(gate, _coordinator, domain: Dictionary, authority_id: String, epoch: int, item_id: String, slot: int, operation_id: String) -> void:
	var admitted: Dictionary = gate.authorize(authority_id, epoch, DOMAIN_ITEM, operation_id)
	_assert(_ok(admitted), "7.11 Item mutation admitted for %s/%d" % [authority_id, epoch])
	_assert(String(admitted.get("details", {}).get("canonical_owner", "")) == "item/m4-canonical-item-graph", "7.11 Item mutation stays on M4 owner")
	if not _ok(admitted):
		return
	_add_item_to_container(domain, item_id, "ore", "SM1.7.11 ore", 1, slot)
	_assert(_ok(domain.validator.validate_graph()), "7.11 Item mutation leaves canonical graph valid")


func _authorized_construct_assemble(gate, _coordinator, domain: Dictionary, construction, authority_id: String, epoch: int, operation_id: String) -> void:
	var admitted: Dictionary = gate.authorize(authority_id, epoch, DOMAIN_CONSTRUCTION, operation_id)
	_assert(_ok(admitted), "7.11 Construction assembly admitted for %s/%d" % [authority_id, epoch])
	_assert(String(admitted.get("details", {}).get("canonical_owner", "")) == "construction/p4-authority", "7.11 Construction mutation stays on P4 owner")
	if not _ok(admitted):
		return
	var aggregate = _secondary_aggregate()
	var root := ConstructionPlanner.create_root_projection(SECONDARY_ROOT, SECONDARY_CONSTRUCT, "SM1.7.11 secondary outpost", Relations.world())
	var source := ConstructionProjection.from_item_instance_dict(domain.items.get_item(SECONDARY_PANEL).to_dict())
	_assert(_ok(source), "7.11 secondary panel projection built")
	if not _ok(source):
		return
	var planned := ConstructionPlanner.build_assembly_plan(
		"plan/%s" % operation_id.replace("/", "-"), operation_id,
		aggregate.export_snapshot(), root, [source.projection], {}
	)
	_assert(_ok(planned), "7.11 Construction assembly plan built")
	if _ok(planned):
		var applied: Dictionary = construction.apply_plan(planned.plan)
		_assert(_ok(applied), "7.11 canonical Construction assembly committed: %s" % applied)
		if _ok(applied):
			_assert(_ok(gate.reconcile_item_world_entities(domain)), "7.11 Construction assembly reconciles canonical world entities")


func _authorized_construct_deconstruct(gate, _coordinator, domain: Dictionary, construction, authority_id: String, epoch: int, operation_id: String) -> void:
	var admitted: Dictionary = gate.authorize(authority_id, epoch, DOMAIN_CONSTRUCTION, operation_id)
	_assert(_ok(admitted), "7.11 Construction deconstruction admitted for %s/%d" % [authority_id, epoch])
	if not _ok(admitted):
		return
	var snapshot: Dictionary = construction.get_construct_snapshot(SECONDARY_CONSTRUCT)
	var root_source := ConstructionProjection.from_item_instance_dict(domain.items.get_item(SECONDARY_ROOT).to_dict())
	var part_source := ConstructionProjection.from_item_instance_dict(domain.items.get_item(SECONDARY_PANEL).to_dict())
	_assert(_ok(root_source) and _ok(part_source), "7.11 deconstruction projections built")
	if not _ok(root_source) or not _ok(part_source):
		return
	var planned := ConstructionPlanner.build_deconstruction_plan(
		"plan/%s" % operation_id.replace("/", "-"), operation_id,
		snapshot, root_source.projection, [part_source.projection],
		ConstructionProjection.container_relation(CONTAINER_ID, 1)
	)
	_assert(_ok(planned), "7.11 Construction deconstruction plan built")
	if _ok(planned):
		var applied: Dictionary = construction.apply_plan(planned.plan)
		_assert(_ok(applied), "7.11 canonical Construction deconstruction committed: %s" % applied)
		if _ok(applied):
			_assert(_ok(gate.reconcile_item_world_entities(domain)), "7.11 Construction deconstruction reconciles canonical world entities")


func _authorized_outpost_mutation(gate, _coordinator, authority_id: String, epoch: int, phase: String, operation_id: String) -> void:
	var admitted: Dictionary = gate.authorize(authority_id, epoch, DOMAIN_OUTPOST, operation_id)
	_assert(_ok(admitted), "7.11 outpost mutation admitted for %s/%d" % [authority_id, epoch])
	_assert(String(admitted.get("details", {}).get("canonical_owner", "")) == "v0/p4-p5-product-composition", "7.11 outpost mutation stays on product composition owner")
	if not _ok(admitted):
		return
	gameplay["revision"] = int(gameplay.revision) + 1
	gameplay["phase"] = phase
	var history: Array = Array(gameplay.mutations)
	history.append(operation_id)
	gameplay["mutations"] = history


func _complete_transfer(world, shadow, coordinator, transfer_id: String, source: String, target: String, source_epoch: int, target_epoch: int) -> void:
	var warm: Dictionary = world.bind_to_warm(transfer_id, shadow.get_report())
	_assert(_ok(warm), "7.11 world WARM binding %s" % transfer_id)
	if not _ok(warm):
		return
	var report: Dictionary = Dictionary(warm.get("details", {}).get("warm_report", {}))
	_assert(_ok(coordinator.validate_warm_target(transfer_id, target, report)), "7.11 target WARM validation %s" % transfer_id)
	var commit: Dictionary = coordinator.commit_ownership(transfer_id, source, target, source_epoch, target_epoch)
	_assert(_ok(commit), "7.11 ownership commit %s" % transfer_id)
	if not _ok(commit):
		return
	var token := String(commit.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source(transfer_id, source, token)), "7.11 source retire %s" % transfer_id)
	_assert(_ok(coordinator.activate_target(transfer_id, target, target_epoch, token)), "7.11 target activate %s" % transfer_id)


func _refresh_projection(projection, shadow, item_persistence, construction) -> void:
	var item_snapshot := _canonical_item_snapshot(item_persistence)
	var construction_snapshot: Dictionary = construction.export_state()
	_assert(_ok(projection.configure_from_canonical_sources({
		"gameplay": gameplay.duplicate(true),
		"item_graph": item_snapshot,
		"construction": construction_snapshot,
	})), "7.11 P6 projection refreshed from canonical owners")
	_assert(_ok(shadow.configure(projection)), "7.11 P6 shadow refreshed")


func _fingerprints(item_persistence, construction, projection) -> Dictionary:
	return {
		"item": NetworkUtils.payload_hash(_canonical_item_snapshot(item_persistence)),
		"construction": NetworkUtils.payload_hash(construction.export_state()),
		"outpost": projection.compute_checksum(),
	}


func _fenced(result: Dictionary) -> bool:
	return not _ok(result) and String(result.get("error_code", "")) == "SM1_CANONICAL_MUTATION_AUTHORITY_FENCED"


func _make_runtime() -> Dictionary:
	var domain: Dictionary = Factory.create()
	for row in [
		{"id": "construct_root", "display_name": "Construct root", "max_stack": 1, "unit_mass_kg": 0.1, "external_volume_l": 0.1, "tags": ["construction"]},
		{"id": "panel", "display_name": "Panel", "max_stack": 1, "unit_mass_kg": 5.0, "external_volume_l": 4.0, "tags": ["construction_part"]},
		{"id": "ore", "display_name": "Ore", "max_stack": 64, "unit_mass_kg": 1.0, "external_volume_l": 1.0, "tags": ["resource"]},
	]:
		domain.items.register_definition(Definition.new(row))
	var backpack = ContainerState.new({
		"container_id": CONTAINER_ID,
		"owner_kind": "ACTOR",
		"owner_id": PLAYER,
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": 12,
		"maximum_mass_kg": 1000.0,
		"maximum_volume_l": 1000.0,
	})
	_assert(domain.containers.add_container(backpack), "7.11 canonical backpack created")
	_add_primary_construct_items(domain)
	_add_item_to_container(domain, SECONDARY_PANEL, "panel", "Secondary panel", 1, 1)
	_assert(_ok(domain.validator.validate_graph()), "7.11 initial Item Graph valid")

	var aggregate = Aggregate.new()
	_assert(_ok(aggregate.setup(PRIMARY_CONSTRUCT, PRIMARY_ROOT)), "7.11 primary aggregate setup")
	var part := Part.create("part/sm1-7-11/primary-panel", PRIMARY_PANEL, "PANEL", "wall", 5.0, [0.0, 0.0, 0.0])
	_assert(_ok(aggregate.add_part("operation/sm1-7-11/primary-part", 0, part)), "7.11 primary part added")
	var constructs = ConstructStore.new()
	_assert(_ok(constructs.apply_mutation(ConstructMutation.create(ConstructMutation.OP_CREATE, PRIMARY_CONSTRUCT, {}, aggregate.export_snapshot()))), "7.11 primary ConstructStore created")
	var bridge = M0Bridge.new()
	_assert(_ok(bridge.setup("user://sm1-7-11-%d" % Time.get_ticks_usec())), "7.11 M0 bridge setup")
	var construction = ConstructionAuthority.new()
	_assert(_ok(construction.setup(
		domain.items, domain.containers, domain.validator, domain.mass, domain.operations,
		constructs, bridge, "authority/construction-sm1-7-11", 7, 0, 0, 0,
		{PRIMARY_CONSTRUCT: 1}
	)), "7.11 canonical Construction authority setup")
	var item_persistence = ItemGraphPersistence.new()
	item_persistence.setup(domain, null, "sm1-7-11-item-graph")
	return {"domain": domain, "construction": construction, "item_persistence": item_persistence}


func _add_primary_construct_items(domain: Dictionary) -> void:
	var root = Item.new({
		"instance_id": PRIMARY_ROOT, "definition_id": "construct_root", "display_name": "Primary root", "quantity": 1,
		"relation": Relations.world(), "components": {"construction_root": {"schema": "planet_simulator.construction_root_component.v1", "construct_id": PRIMARY_CONSTRUCT}}, "revision": 0,
	})
	_assert(domain.items.add_item(root), "7.11 primary root added")
	var panel = Item.new({
		"instance_id": PRIMARY_PANEL, "definition_id": "panel", "display_name": "Primary panel", "quantity": 1,
		"relation": Relations.attachment(PRIMARY_CONSTRUCT, PRIMARY_ROOT, "part/sm1-7-11/primary-panel"), "components": {}, "revision": 0,
	})
	_assert(domain.items.add_item(panel), "7.11 primary panel added")


func _secondary_aggregate():
	var aggregate = Aggregate.new()
	_assert(_ok(aggregate.setup(SECONDARY_CONSTRUCT, SECONDARY_ROOT)), "7.11 secondary aggregate setup")
	var part := Part.create("part/sm1-7-11/secondary-panel", SECONDARY_PANEL, "PANEL", "wall", 5.0, [2.0, 0.0, 0.0])
	_assert(_ok(aggregate.add_part("operation/sm1-7-11/secondary-part", 0, part)), "7.11 secondary aggregate part")
	return aggregate


func _add_item_to_container(domain: Dictionary, item_id: String, definition_id: String, display_name: String, quantity: int, slot: int) -> void:
	var item = Item.new({
		"instance_id": item_id, "definition_id": definition_id, "display_name": display_name, "quantity": quantity,
		"relation": Relations.container(CONTAINER_ID, slot), "components": {}, "revision": 0,
	})
	_assert(domain.items.add_item(item), "7.11 canonical item add %s" % item_id)
	var container = domain.containers.get_container(CONTAINER_ID)
	container.item_ids.append(item_id)
	container.slot_assignments[slot] = item_id


func _canonical_item_snapshot(item_persistence) -> Dictionary:
	var result: Dictionary = item_persistence.create_snapshot_result({})
	_assert(_ok(result), "7.11 Item Graph snapshot created")
	var snapshot: Dictionary = Dictionary(result.get("snapshot", {})).duplicate(true)
	snapshot["metadata"] = {}
	var validation: Dictionary = item_persistence.validate_snapshot(snapshot)
	_assert(_ok(validation), "7.11 Item Graph snapshot validates: %s" % validation)
	return snapshot


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("[sm1.7.11] PASS: %s" % message)
	else:
		failures.append(message)
		print("[sm1.7.11][FAIL] %s" % message)


func _finish() -> void:
	print("SM1.7.11 Item/Construction/outpost mutations: %d assertions, %d failures" % [assertions, failures.size()])
	if failures.is_empty():
		print("SM1_7_11_WORLD_MUTATIONS_AROUND_HANDOFF_PASS")
	quit(0 if failures.is_empty() else 1)
