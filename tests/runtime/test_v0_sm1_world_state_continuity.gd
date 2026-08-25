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
const M0Bridge = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const ConstructionAuthority = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const P6Projection = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const P6Shadow = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const P6PersistenceOwner = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const TransferCoordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const WorldContinuity = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_world_state_continuity.gd")

const ROOT_ID := "item/00000000-0000-4000-8000-00000000aa01"
const PANEL_ID := "item/00000000-0000-4000-8000-00000000aa02"
const ORE_ID := "item/00000000-0000-4000-8000-00000000aa03"
const CONSTRUCT_ID := "construct/sm1/outpost"
const CONTAINER_ID := "container/sm1/backpack"
const AUTHORITY_A := "authority/a"
const AUTHORITY_B := "authority/b"

var assertions: int = 0
var failures: Array[String] = []


class ExistingRecoveryCoordinator:
	extends RefCounted

	func persist_checkpoint(_checkpoint_id: String, _generation: int, _previous_generation: int, _committed_operation_id: String = "") -> Dictionary:
		return {"success": true, "details": {"checkpoint": {}, "repository": {}}}

	func recover_latest() -> Dictionary:
		return {"success": true, "details": {"checkpoint": {}, "repository": {}}}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[sm1-world][FAIL] %s" % message)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _init() -> void:
	var runtime := _make_canonical_runtime()
	var domain: Dictionary = runtime.domain
	var item_persistence = runtime.item_persistence
	var construction = runtime.construction

	var item_snapshot := _canonical_item_snapshot(item_persistence)
	var construction_snapshot: Dictionary = construction.export_state()
	_assert(not item_snapshot.is_empty(), "canonical Item Graph snapshot missing")
	_assert(not construction_snapshot.is_empty(), "canonical Construction snapshot missing")
	_assert(int(Dictionary(item_snapshot.get("items", {})).get("items", []).size()) >= 2, "Item Graph fixture is not non-empty")
	_assert(int(Dictionary(construction_snapshot.get("construct_store", {})).get("constructs", []).size()) == 1, "Construction fixture is not non-empty")

	var projection = P6Projection.new()
	_assert(_ok(projection.configure_from_canonical_sources({
		"gameplay": {"revision": 1, "outpost_id": "outpost/sm1"},
		"item_graph": item_snapshot,
		"construction": construction_snapshot,
	})), "P6 outpost projection did not compose canonical owners")
	var shadow = P6Shadow.new()
	_assert(_ok(shadow.configure(projection)), "P6 WARM shadow setup failed")

	var persistence = P6PersistenceOwner.new()
	_assert(_ok(persistence.configure(ExistingRecoveryCoordinator.new())), "existing P6 persistence-owner adapter setup failed")
	var persistence_report: Dictionary = persistence.get_report()
	_assert(String(persistence_report.get("persistence_owner", "")) == "persistence/authoritative-recovery", "wrong persistence owner in fixture")
	_assert(not bool(persistence_report.get("private_filesystem", true)), "P6 adapter claims private filesystem")

	var coordinator = TransferCoordinator.new()
	_assert(_ok(coordinator.configure(AUTHORITY_A, 1, {
		"logical_player_id": "player/sm1-world",
		"player_entity_id": "entity/sm1-world",
		"last_input_sequence": 100,
		"last_operation_id": "operation/sm1/world-bootstrap",
	})), "SM1.2 coordinator setup failed")

	var world = WorldContinuity.new()
	var configured: Dictionary = world.configure(item_persistence, construction, persistence, projection, coordinator)
	_assert(_ok(configured), "SM1.5 world continuity configure failed: %s" % configured)

	var transfer_ab := "transfer/sm1/world-a-b/1"
	var unsafe_prepare_ab: Dictionary = world.prepare_transfer(transfer_ab)
	_assert(not _ok(unsafe_prepare_ab) and _err(unsafe_prepare_ab) == "SM1_WORLD_SOURCE_NOT_FROZEN", "world snapshot was allowed before A source freeze")
	_assert(_ok(coordinator.begin_transfer(transfer_ab, AUTHORITY_A, AUTHORITY_B, 1)), "A->B transfer begin failed")

	var prepared_ab: Dictionary = world.prepare_transfer(transfer_ab)
	_assert(_ok(prepared_ab), "A->B world manifest prepare failed: %s" % prepared_ab)
	var manifest_ab: Dictionary = Dictionary(prepared_ab.get("details", {}).get("manifest", {}))
	_assert(int(manifest_ab.get("item_count", 0)) >= 2, "A->B manifest did not observe real Item Graph")
	_assert(int(manifest_ab.get("construct_count", 0)) == 1, "A->B manifest did not observe real Construction")
	_assert(String(manifest_ab.get("canonical_item_owner", "")) == "item/m4-canonical-item-graph", "A->B changed Item Graph owner")
	_assert(String(manifest_ab.get("canonical_construction_owner", "")) == "construction/p4-authority", "A->B changed Construction owner")
	_assert(String(manifest_ab.get("canonical_persistence_owner", "")) == "persistence/authoritative-recovery", "A->B changed persistence owner")
	_assert(not bool(manifest_ab.get("private_canonical_truth", true)), "A->B world manifest claims canonical truth")
	_assert(bool(manifest_ab.get("captured_after_source_freeze", false)), "A->B world manifest lacks source-freeze marker")
	_assert(String(manifest_ab.get("source_authority_id", "")) == AUTHORITY_A and String(manifest_ab.get("target_authority_id", "")) == AUTHORITY_B, "A->B world manifest authority tuple mismatch")
	_assert(int(manifest_ab.get("source_epoch", 0)) == 1 and int(manifest_ab.get("target_epoch", 0)) == 2, "A->B world manifest epoch tuple mismatch")

	var world_warm_ab: Dictionary = world.bind_to_warm(transfer_ab, shadow.get_report())
	_assert(_ok(world_warm_ab), "A->B world WARM binding failed: %s" % world_warm_ab)
	var warm_report_ab: Dictionary = Dictionary(world_warm_ab.get("details", {}).get("warm_report", {}))
	_assert(not String(warm_report_ab.get("world_manifest_checksum", "")).is_empty(), "A->B world manifest checksum missing from WARM")
	_assert(String(warm_report_ab.get("transfer_id", "")) == transfer_ab, "A->B WARM report lost transfer binding")
	_assert(_ok(coordinator.validate_warm_target(transfer_ab, AUTHORITY_B, warm_report_ab)), "A->B WARM validation failed")
	var commit_ab: Dictionary = coordinator.commit_ownership(transfer_ab, AUTHORITY_A, AUTHORITY_B, 1, 2)
	_assert(_ok(commit_ab), "A->B ownership commit failed")
	var token_ab := String(commit_ab.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source(transfer_ab, AUTHORITY_A, token_ab)), "A->B source retire failed")
	_assert(_ok(coordinator.activate_target(transfer_ab, AUTHORITY_B, 2, token_ab)), "A->B target activation failed")
	var continuity_ab: Dictionary = world.validate_after_activation(transfer_ab, coordinator)
	_assert(_ok(continuity_ab), "A->B canonical world continuity failed: %s" % continuity_ab)
	_assert(String(continuity_ab.get("details", {}).get("result", "")) == "SM1_5_CANONICAL_WORLD_STATE_CONTINUITY_PASS", "A->B stage marker mismatch")
	var result_ab: Dictionary = Dictionary(continuity_ab.get("details", {}).get("details", {}))
	_assert(String(result_ab.get("item_graph_result", "")) == "ITEM_GRAPH_CANONICAL_CONTINUITY_PASS", "Item Graph continuity marker missing")
	_assert(String(result_ab.get("construction_result", "")) == "CONSTRUCTION_CANONICAL_CONTINUITY_PASS", "Construction continuity marker missing")
	_assert(String(result_ab.get("outpost_result", "")) == "OUTPOST_PERSISTENCE_COMPOSITION_CONTINUITY_PASS", "outpost/persistence continuity marker missing")
	_assert(not _ok(coordinator.authorize_write(AUTHORITY_A, 1)), "stale A still writable after A->B")

	# While B is ACTIVE, mutate the real M4 Item Graph through its canonical
	# registry. Construction authority references the same ItemRegistry, so its
	# full authoritative composite snapshot must evolve consistently too.
	_add_ore_item(domain)
	_assert(_ok(domain.validator.validate_graph()), "Item Graph invalid after B-era canonical mutation")
	item_snapshot = _canonical_item_snapshot(item_persistence)
	construction_snapshot = construction.export_state()
	_assert(_ok(projection.configure_from_canonical_sources({
		"gameplay": {"revision": 2, "outpost_id": "outpost/sm1"},
		"item_graph": item_snapshot,
		"construction": construction_snapshot,
	})), "P6 projection refresh after B-era mutation failed")
	_assert(_ok(shadow.configure(projection)), "P6 shadow refresh after B-era mutation failed")

	var transfer_ba := "transfer/sm1/world-b-a/2"
	var unsafe_prepare_ba: Dictionary = world.prepare_transfer(transfer_ba)
	_assert(not _ok(unsafe_prepare_ba) and _err(unsafe_prepare_ba) == "SM1_WORLD_SOURCE_NOT_FROZEN", "world snapshot was allowed before B source freeze")
	_assert(_ok(coordinator.begin_transfer(transfer_ba, AUTHORITY_B, AUTHORITY_A, 2)), "B->A transfer begin failed")

	var prepared_ba: Dictionary = world.prepare_transfer(transfer_ba)
	_assert(_ok(prepared_ba), "B->A world manifest prepare failed: %s" % prepared_ba)
	var manifest_ba: Dictionary = Dictionary(prepared_ba.get("details", {}).get("manifest", {}))
	_assert(int(manifest_ba.get("item_count", 0)) == int(manifest_ab.get("item_count", 0)) + 1, "B-era Item Graph state not captured for return transfer")
	_assert(String(manifest_ba.get("item_graph_fingerprint", "")) != String(manifest_ab.get("item_graph_fingerprint", "")), "B-era Item Graph mutation did not change canonical fingerprint")
	_assert(String(manifest_ba.get("construction_fingerprint", "")) != String(manifest_ab.get("construction_fingerprint", "")), "Construction composite did not observe B-era Item Graph mutation")
	_assert(int(manifest_ba.get("construct_count", 0)) == 1, "B-era mutation changed canonical construct count")
	_assert(bool(manifest_ba.get("captured_after_source_freeze", false)), "B->A world manifest lacks source-freeze marker")
	_assert(String(manifest_ba.get("source_authority_id", "")) == AUTHORITY_B and String(manifest_ba.get("target_authority_id", "")) == AUTHORITY_A, "B->A world manifest authority tuple mismatch")
	_assert(int(manifest_ba.get("source_epoch", 0)) == 2 and int(manifest_ba.get("target_epoch", 0)) == 3, "B->A world manifest epoch tuple mismatch")

	var world_warm_ba: Dictionary = world.bind_to_warm(transfer_ba, shadow.get_report())
	_assert(_ok(world_warm_ba), "B->A world WARM binding failed")
	var warm_report_ba: Dictionary = Dictionary(world_warm_ba.get("details", {}).get("warm_report", {}))
	_assert(_ok(coordinator.validate_warm_target(transfer_ba, AUTHORITY_A, warm_report_ba)), "B->A WARM validation failed")
	var commit_ba: Dictionary = coordinator.commit_ownership(transfer_ba, AUTHORITY_B, AUTHORITY_A, 2, 3)
	_assert(_ok(commit_ba), "B->A ownership commit failed")
	var token_ba := String(commit_ba.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source(transfer_ba, AUTHORITY_B, token_ba)), "B->A source retire failed")
	_assert(_ok(coordinator.activate_target(transfer_ba, AUTHORITY_A, 3, token_ba)), "B->A target activation failed")
	var continuity_ba: Dictionary = world.validate_after_activation(transfer_ba, coordinator)
	_assert(_ok(continuity_ba), "B->A canonical world continuity failed: %s" % continuity_ba)
	_assert(domain.items.get_item(ORE_ID) != null, "B-era canonical Item Graph mutation disappeared after return to A")
	_assert(int(coordinator.snapshot().get("authority_epoch", 0)) == 3, "authority epoch did not remain monotonic")
	_assert(not _ok(coordinator.authorize_write(AUTHORITY_B, 2)), "stale B still writable after B->A")

	var report: Dictionary = world.get_report()
	_assert(bool(report.get("derived_only", false)), "SM1.5 adapter is not derived-only")
	_assert(not bool(report.get("private_item_graph", true)), "SM1.5 claims private Item Graph")
	_assert(not bool(report.get("private_construction_truth", true)), "SM1.5 claims private Construction truth")
	_assert(not bool(report.get("private_persistence_owner", true)), "SM1.5 claims private persistence owner")
	_assert(int(report.get("completed_count", 0)) == 2, "SM1.5 did not retain both continuity proofs")

	_finish()


func _make_canonical_runtime() -> Dictionary:
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
		"owner_id": "player/sm1-world",
		"storage_mode": ContainerState.STORAGE_SLOTS,
		"slot_count": 8,
		"maximum_mass_kg": 1000.0,
		"maximum_volume_l": 1000.0,
	})
	_assert(domain.containers.add_container(backpack), "canonical backpack creation failed")
	_add_item_to_container(domain, ROOT_ID, "construct_root", "Outpost root", 1, 0)
	_add_item_to_container(domain, PANEL_ID, "panel", "Outpost panel", 1, 1)
	_assert(_ok(domain.validator.validate_graph()), "initial canonical Item Graph invalid")

	var aggregate = Aggregate.new()
	_assert(_ok(aggregate.setup(CONSTRUCT_ID, ROOT_ID)), "construct aggregate setup failed")
	var part := Part.create("part/sm1/panel", PANEL_ID, "PANEL", "wall", 5.0, [0.0, 0.0, 0.0])
	_assert(_ok(aggregate.add_part("operation/sm1/construct-part", 0, part)), "construct part add failed")
	var construct_snapshot: Dictionary = aggregate.export_snapshot()
	var constructs = ConstructStore.new()
	var create_mutation := ConstructMutation.create(ConstructMutation.OP_CREATE, CONSTRUCT_ID, {}, construct_snapshot)
	_assert(_ok(constructs.apply_mutation(create_mutation)), "canonical ConstructStore create failed")

	var bridge = M0Bridge.new()
	_assert(_ok(bridge.setup("user://sm1-world-continuity-%d" % Time.get_ticks_usec())), "construction M0 bridge setup failed")
	var construction = ConstructionAuthority.new()
	_assert(_ok(construction.setup(
		domain.items,
		domain.containers,
		domain.validator,
		domain.mass,
		domain.operations,
		constructs,
		bridge,
		"authority/construction-sm1",
		7,
		0,
		0,
		0,
		{CONSTRUCT_ID: 1}
	)), "canonical Construction authority setup failed")

	var item_persistence = ItemGraphPersistence.new()
	item_persistence.setup(domain, null, "sm1-world-item-graph")
	return {"domain": domain, "construction": construction, "item_persistence": item_persistence}


func _add_item_to_container(domain: Dictionary, item_id: String, definition_id: String, display_name: String, quantity: int, slot: int) -> void:
	var item = Item.new({
		"instance_id": item_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"quantity": quantity,
		"relation": Relations.container(CONTAINER_ID, slot),
		"components": {},
		"revision": 0,
	})
	_assert(domain.items.add_item(item), "canonical item add failed: %s" % item_id)
	var container = domain.containers.get_container(CONTAINER_ID)
	container.item_ids.append(item_id)
	container.slot_assignments[slot] = item_id


func _add_ore_item(domain: Dictionary) -> void:
	_add_item_to_container(domain, ORE_ID, "ore", "B-era ore", 3, 2)


func _canonical_item_snapshot(item_persistence) -> Dictionary:
	var result: Dictionary = item_persistence.create_snapshot_result({})
	_assert(_ok(result), "canonical Item Graph snapshot creation failed")
	var snapshot: Dictionary = Dictionary(result.get("snapshot", {})).duplicate(true)
	snapshot["metadata"] = {}
	_assert(_ok(item_persistence.validate_snapshot(snapshot)), "canonical Item Graph snapshot validation failed")
	return snapshot


func _finish() -> void:
	if failures.is_empty():
		print("[sm1-world] all %d assertions passed" % assertions)
		print("[sm1-world][stage] SOURCE_FREEZE_BEFORE_WORLD_CAPTURE_PASS")
		print("[sm1-world][stage] ITEM_GRAPH_CANONICAL_CONTINUITY_PASS")
		print("[sm1-world][stage] CONSTRUCTION_CANONICAL_CONTINUITY_PASS")
		print("[sm1-world][stage] OUTPOST_PERSISTENCE_COMPOSITION_CONTINUITY_PASS")
		print("[sm1-world][stage] SM1_5_CANONICAL_WORLD_STATE_CONTINUITY_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("[sm1-world] FAIL %d/%d" % [failures.size(), assertions])
	quit(1)
