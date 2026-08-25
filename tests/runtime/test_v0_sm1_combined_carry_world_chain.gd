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
const IdentityRegistry = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const OperationLedger = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const ClosureAdapter = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const P6Projection = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const P6Shadow = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const P6PersistenceOwner = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const TransferCoordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const PlayerCarryingDomain = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd")
const WorldContinuity = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_world_state_continuity.gd")

const ROOT_ID := "item/00000000-0000-4000-8000-00000000ca01"
const PANEL_ID := "item/00000000-0000-4000-8000-00000000ca02"
const ORE_ID := "item/00000000-0000-4000-8000-00000000ca03"
const CONSTRUCT_ID := "construct/sm1/combined-outpost"
const CONTAINER_ID := "container/sm1/combined-backpack"
const SESSION := "client-session/sm1/combined"
const PLAYER := "player/sm1-combined"
const ENTITY := "entity/sm1-combined"
const AUTHORITY_A := "authority/a"
const AUTHORITY_B := "authority/b"
const OP100 := "operation/sm1/combined/100"
const OP101 := "operation/sm1/combined/101"

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
		print("[sm1-combined][FAIL] %s" % message)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _init() -> void:
	var runtime := _make_canonical_runtime()
	var domain: Dictionary = runtime.domain
	var item_persistence = runtime.item_persistence
	var construction = runtime.construction

	var item_snapshot := _canonical_item_snapshot(item_persistence)
	var construction_snapshot: Dictionary = construction.export_state()
	var projection = P6Projection.new()
	_assert(_ok(projection.configure_from_canonical_sources({
		"gameplay": {"revision": 1, "outpost_id": "outpost/sm1/combined"},
		"item_graph": item_snapshot,
		"construction": construction_snapshot,
	})), "P6 projection setup failed")
	var shadow = P6Shadow.new()
	_assert(_ok(shadow.configure(projection)), "P6 shadow setup failed")

	var persistence = P6PersistenceOwner.new()
	_assert(_ok(persistence.configure(ExistingRecoveryCoordinator.new())), "P6 persistence adapter setup failed")

	var registry = IdentityRegistry.new()
	_assert(_ok(registry.bind(SESSION, PLAYER, ENTITY)), "identity binding failed")
	var ledger = OperationLedger.new()
	_assert(_ok(ledger.configure(128)), "operation ledger configure failed")
	_assert(_ok(ledger.record_applied(PLAYER, OP100)), "initial applied operation missing")
	var closure = ClosureAdapter.new()
	_assert(_ok(closure.configure(registry, ledger)), "closure adapter configure failed")

	var coordinator = TransferCoordinator.new()
	var carrying = PlayerCarryingDomain.new()
	_assert(_ok(carrying.configure(registry, ledger, closure, coordinator)), "player carrying configure failed")
	var initial_capture: Dictionary = carrying.capture_manifest(SESSION, 100, OP100)
	_assert(_ok(initial_capture), "initial player manifest capture failed")
	var initial_manifest: Dictionary = Dictionary(initial_capture.get("details", {}).get("manifest", {}))
	_assert(_ok(coordinator.configure(AUTHORITY_A, 1, initial_manifest)), "transfer coordinator configure failed")

	var world = WorldContinuity.new()
	_assert(_ok(world.configure(item_persistence, construction, persistence, projection, coordinator)), "world continuity configure failed")

	var transfer_ab := "transfer/sm1/combined/a-b/1"
	_assert(_ok(coordinator.begin_transfer(transfer_ab, AUTHORITY_A, AUTHORITY_B, 1)), "A->B begin failed")
	_assert(_ok(carrying.prepare_transfer(transfer_ab, SESSION, 100, OP100)), "A->B player prepare failed")
	_assert(_ok(world.prepare_transfer(transfer_ab)), "A->B world prepare failed")

	var player_warm_ab: Dictionary = carrying.build_composite_warm_report(transfer_ab, shadow.get_report())
	_assert(_ok(player_warm_ab), "A->B player WARM layer failed")
	var player_report_ab: Dictionary = Dictionary(player_warm_ab.get("details", {}).get("warm_report", {}))
	var player_checksum_ab := String(player_report_ab.get("checksum", ""))
	_assert(not player_checksum_ab.is_empty(), "A->B player checksum missing")

	var world_warm_ab: Dictionary = world.bind_to_warm(transfer_ab, player_report_ab)
	_assert(_ok(world_warm_ab), "A->B world WARM layer failed")
	var final_report_ab: Dictionary = Dictionary(world_warm_ab.get("details", {}).get("warm_report", {}))
	var final_checksum_ab := String(final_report_ab.get("checksum", ""))
	_assert(not final_checksum_ab.is_empty() and final_checksum_ab != player_checksum_ab, "A->B final WARM checksum did not add world layer")
	_assert(String(final_report_ab.get("previous_warm_checksum", "")) == player_checksum_ab, "A->B world layer is not chained to player layer")
	_assert(not String(final_report_ab.get("carrying_manifest_checksum", "")).is_empty(), "A->B final report lost player manifest checksum")
	_assert(not String(final_report_ab.get("world_manifest_checksum", "")).is_empty(), "A->B final report lost world manifest checksum")
	_assert(_ok(coordinator.validate_warm_target(transfer_ab, AUTHORITY_B, final_report_ab)), "A->B final WARM validation failed")
	var commit_ab: Dictionary = coordinator.commit_ownership(transfer_ab, AUTHORITY_A, AUTHORITY_B, 1, 2)
	_assert(_ok(commit_ab), "A->B ownership commit failed")
	var token_ab := String(commit_ab.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source(transfer_ab, AUTHORITY_A, token_ab)), "A->B source retire failed")
	_assert(_ok(coordinator.activate_target(transfer_ab, AUTHORITY_B, 2, token_ab)), "A->B target activation failed")

	var completed_transfer_ab: Dictionary = coordinator.get_completed_transfer(transfer_ab)
	_assert(String(completed_transfer_ab.get("warm_checksum", "")) == final_checksum_ab, "A->B coordinator did not commit final WARM checksum")
	_assert(String(Dictionary(completed_transfer_ab.get("warm_report", {})).get("previous_warm_checksum", "")) == player_checksum_ab, "A->B coordinator lost WARM chain evidence")
	var world_continuity_ab: Dictionary = world.validate_after_activation(transfer_ab, coordinator)
	_assert(_ok(world_continuity_ab), "A->B world continuity failed")
	var carry_continuity_ab: Dictionary = carrying.validate_after_activation(transfer_ab, SESSION, 100, OP100, coordinator)
	_assert(_ok(carry_continuity_ab), "A->B player continuity failed through world WARM layer: %s" % carry_continuity_ab)
	_assert(String(carry_continuity_ab.get("details", {}).get("warm_chain_mode", "")) == "DOWNSTREAM_LAYER_BOUND", "A->B player continuity did not prove downstream WARM binding")

	# Evolve both canonical world state and durable player operation closure while
	# B is ACTIVE, then prove the same combined chain on the return transfer.
	_add_ore_item(domain)
	_assert(_ok(domain.validator.validate_graph()), "B-era Item Graph mutation invalid")
	_assert(_ok(ledger.record_applied(PLAYER, OP101)), "B-era player operation record failed")
	item_snapshot = _canonical_item_snapshot(item_persistence)
	construction_snapshot = construction.export_state()
	_assert(_ok(projection.configure_from_canonical_sources({
		"gameplay": {"revision": 2, "outpost_id": "outpost/sm1/combined"},
		"item_graph": item_snapshot,
		"construction": construction_snapshot,
	})), "B-era P6 projection refresh failed")
	_assert(_ok(shadow.configure(projection)), "B-era shadow refresh failed")

	var transfer_ba := "transfer/sm1/combined/b-a/2"
	_assert(_ok(coordinator.begin_transfer(transfer_ba, AUTHORITY_B, AUTHORITY_A, 2)), "B->A begin failed")
	_assert(_ok(carrying.prepare_transfer(transfer_ba, SESSION, 101, OP101)), "B->A player prepare failed")
	_assert(_ok(world.prepare_transfer(transfer_ba)), "B->A world prepare failed")

	var player_warm_ba: Dictionary = carrying.build_composite_warm_report(transfer_ba, shadow.get_report())
	_assert(_ok(player_warm_ba), "B->A player WARM layer failed")
	var player_report_ba: Dictionary = Dictionary(player_warm_ba.get("details", {}).get("warm_report", {}))
	var player_checksum_ba := String(player_report_ba.get("checksum", ""))
	var world_warm_ba: Dictionary = world.bind_to_warm(transfer_ba, player_report_ba)
	_assert(_ok(world_warm_ba), "B->A world WARM layer failed")
	var final_report_ba: Dictionary = Dictionary(world_warm_ba.get("details", {}).get("warm_report", {}))
	_assert(String(final_report_ba.get("previous_warm_checksum", "")) == player_checksum_ba, "B->A world layer is not chained to player layer")
	_assert(_ok(coordinator.validate_warm_target(transfer_ba, AUTHORITY_A, final_report_ba)), "B->A final WARM validation failed")
	var commit_ba: Dictionary = coordinator.commit_ownership(transfer_ba, AUTHORITY_B, AUTHORITY_A, 2, 3)
	_assert(_ok(commit_ba), "B->A ownership commit failed")
	var token_ba := String(commit_ba.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source(transfer_ba, AUTHORITY_B, token_ba)), "B->A source retire failed")
	_assert(_ok(coordinator.activate_target(transfer_ba, AUTHORITY_A, 3, token_ba)), "B->A target activation failed")
	_assert(_ok(world.validate_after_activation(transfer_ba, coordinator)), "B->A world continuity failed")
	var carry_continuity_ba: Dictionary = carrying.validate_after_activation(transfer_ba, SESSION, 101, OP101, coordinator)
	_assert(_ok(carry_continuity_ba), "B->A player continuity failed through world WARM layer: %s" % carry_continuity_ba)
	_assert(String(carry_continuity_ba.get("details", {}).get("warm_chain_mode", "")) == "DOWNSTREAM_LAYER_BOUND", "B->A player continuity did not prove downstream WARM binding")

	_assert(domain.items.get_item(ORE_ID) != null, "B-era Item Graph mutation disappeared after return")
	_assert(ledger.is_applied(PLAYER, OP100) and ledger.is_applied(PLAYER, OP101), "player operation closure did not survive A->B->A")
	_assert(int(coordinator.snapshot().get("authority_epoch", 0)) == 3, "authority epoch did not reach 3")
	_assert(int(carrying.get_report().get("completed_count", 0)) == 2, "player carrying did not complete both combined transfers")
	_assert(int(world.get_report().get("completed_count", 0)) == 2, "world continuity did not complete both combined transfers")

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
		"owner_id": PLAYER,
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
	var part := Part.create("part/sm1/combined-panel", PANEL_ID, "PANEL", "wall", 5.0, [0.0, 0.0, 0.0])
	_assert(_ok(aggregate.add_part("operation/sm1/combined/construct-part", 0, part)), "construct part add failed")
	var construct_snapshot: Dictionary = aggregate.export_snapshot()
	var constructs = ConstructStore.new()
	var create_mutation := ConstructMutation.create(ConstructMutation.OP_CREATE, CONSTRUCT_ID, {}, construct_snapshot)
	_assert(_ok(constructs.apply_mutation(create_mutation)), "canonical ConstructStore create failed")

	var bridge = M0Bridge.new()
	_assert(_ok(bridge.setup("user://sm1-combined-%d" % Time.get_ticks_usec())), "construction M0 bridge setup failed")
	var construction = ConstructionAuthority.new()
	_assert(_ok(construction.setup(
		domain.items,
		domain.containers,
		domain.validator,
		domain.mass,
		domain.operations,
		constructs,
		bridge,
		"authority/construction-sm1-combined",
		7,
		0,
		0,
		0,
		{CONSTRUCT_ID: 1}
	)), "canonical Construction authority setup failed")

	var item_persistence = ItemGraphPersistence.new()
	item_persistence.setup(domain, null, "sm1-combined-item-graph")
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
		print("[sm1-combined] all %d assertions passed" % assertions)
		print("[sm1-combined][stage] PLAYER_WORLD_WARM_CHAIN_COMPOSITION_PASS")
		print("[sm1-combined][stage] SM1_3_SM1_5_COMBINED_CONTINUITY_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("[sm1-combined] FAIL %d/%d" % [failures.size(), assertions])
	quit(1)
