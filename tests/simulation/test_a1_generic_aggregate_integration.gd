extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const WorldEntityAggregateScript = preload("res://scripts/simulation/entities/world_entity_aggregate.gd")
const WorldItemAdapterScript = preload("res://scripts/simulation/aggregates/adapters/world_item_aggregate_adapter.gd")
const RegistryScript = preload("res://scripts/simulation/aggregates/aggregate_adapter_registry.gd")
const StoreScript = preload("res://scripts/simulation/aggregates/generic_aggregate_store.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/aggregate_delta_envelope.gd")
const EntitySnapshotScript = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const PartitionAddressScript = preload("res://scripts/simulation/partition/partition_address.gd")
const EnvironmentAggregateScript = preload("res://tests/simulation/fixtures/test_environment_cell_aggregate.gd")
const EnvironmentAdapterScript = preload("res://tests/simulation/fixtures/test_environment_cell_adapter.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_world_item_adapter_vertical()
	_test_non_item_aggregate_vertical()
	_finish()


func _test_world_item_adapter_vertical() -> void:
	var aggregate = WorldEntityAggregateScript.new()
	var spatial_ref: Dictionary = SpatialRefScript.create("body/moon/fixed", Vector3(1.0, 2.0, 3.0))
	var partition: Dictionary = PartitionAddressScript.create_cube_sphere(0, 1, 1, 2, 3)
	var configured: bool = aggregate.setup(
		"entity/item/a1-terminal",
		"item/a1-terminal",
		spatial_ref,
		{
			"partition_address": partition,
			"physics_state": {"mass_kg": 12.0, "sleeping": true},
			"domain_components": {"inventory": {"item_ids": ["item/a1-cargo"], "count": 1}},
			"authority_owner_id": "region-authority/a1",
			"authority_epoch": 4,
			"state_revision": 12,
			"last_simulation_tick": 500,
			"created_at_utc": "2026-07-29T00:00:00Z",
			"updated_at_utc": "2026-07-29T00:00:00Z",
		}
	)
	_assert(configured, "World item aggregate setup failed")
	var adapter = WorldItemAdapterScript.new()
	_assert(adapter.supports_aggregate(aggregate), "World item adapter rejected WorldEntityAggregate")
	_assert(not adapter.supports_aggregate(RefCounted.new()), "World item adapter accepted unrelated object")
	var registry = RegistryScript.new()
	_assert_ok(registry.setup(), "Adapter registry setup failed")
	_assert_ok(registry.register_adapter(adapter), "World item adapter registration failed")
	var export_result: Dictionary = registry.export_snapshot("WORLD_ITEM", aggregate, "aggregate-snapshot/a1/item/1")
	_assert_ok(export_result, "World item generic snapshot export failed")
	var generic_snapshot: Dictionary = export_result.get("details", {}).get("snapshot", {})
	_assert_ok(SnapshotScript.validate(generic_snapshot), "Exported world item generic snapshot invalid")
	var identity: Dictionary = generic_snapshot["descriptor"]["identity"]
	var authority: Dictionary = generic_snapshot["descriptor"]["authority"]
	var scope: Dictionary = generic_snapshot["descriptor"]["spatial_scope"]
	_assert(String(identity["aggregate_id"]) == String(aggregate.entity_id), "Generic aggregate ID differs from entity ID")
	_assert(String(identity["aggregate_kind"]) == "WORLD_ITEM", "World item aggregate kind is wrong")
	_assert(String(scope["scope_kind"]) == "POINT", "World item scope is not POINT")
	_assert(scope["scope_data"]["spatial_ref"] == aggregate.spatial_ref, "World item spatial scope differs")
	_assert(_json_equal(generic_snapshot["descriptor"]["partition_address"], aggregate.partition_address), "World item partition differs")
	_assert(String(authority["authority_owner_id"]) == String(aggregate.authority_owner_id), "Authority owner differs")
	_assert(int(authority["authority_epoch"]) == int(aggregate.authority_epoch), "Authority epoch differs")
	_assert(int(authority["state_revision"]) == int(aggregate.state_revision), "State revision differs")
	_assert(int(authority["server_tick"]) == int(aggregate.last_simulation_tick), "Server tick differs")
	_assert(String(generic_snapshot["state"]["item_instance_id"]) == String(aggregate.item_instance_id), "Item instance identity lost")
	_assert(_json_equal(generic_snapshot["state"]["physics_state"], aggregate.physics_state), "Physics state differs")
	_assert(_json_equal(generic_snapshot["state"]["domain_components"], aggregate.domain_components), "Domain components differ")
	var entity_snapshot: Dictionary = EntitySnapshotScript.create(
		"entity-snapshot/a1/item/1",
		aggregate.entity_id,
		aggregate.entity_type,
		aggregate.state_revision,
		aggregate.authority_owner_id,
		aggregate.authority_epoch,
		aggregate.last_simulation_tick,
		aggregate.spatial_ref,
		aggregate.partition_address,
		aggregate.physics_state,
		aggregate.domain_components
	)
	_assert_ok(EntitySnapshotScript.validate(entity_snapshot), "Compatibility entity snapshot invalid")
	_assert(String(entity_snapshot["authority_owner_id"]) == String(authority["authority_owner_id"]), "Entity/generic owner mismatch")
	_assert(int(entity_snapshot["authority_epoch"]) == int(authority["authority_epoch"]), "Entity/generic epoch mismatch")
	_assert(int(entity_snapshot["state_revision"]) == int(authority["state_revision"]), "Entity/generic revision mismatch")
	_assert(int(entity_snapshot["server_tick"]) == int(authority["server_tick"]), "Entity/generic tick mismatch")
	_assert(_json_equal(entity_snapshot["domain_components"], generic_snapshot["state"]["domain_components"]), "Entity/generic domain mismatch")
	var store = StoreScript.new()
	_assert_fail(store.accept_snapshot(generic_snapshot), "Unconfigured generic store accepted snapshot")
	_assert_fail(store.setup(), "Generic store accepted missing adapter registry")
	_assert_ok(store.setup(registry), "Generic aggregate store setup failed")
	var unknown_snapshot: Dictionary = generic_snapshot.duplicate(true)
	unknown_snapshot["descriptor"]["identity"]["aggregate_kind"] = "UNKNOWN_KIND"
	unknown_snapshot["checksum"] = SnapshotScript.compute_checksum(unknown_snapshot)
	_assert_fail(store.accept_snapshot(unknown_snapshot), "Unknown aggregate kind accepted by generic store")
	var invalid_item_snapshot: Dictionary = generic_snapshot.duplicate(true)
	invalid_item_snapshot["state"]["unexpected_field"] = true
	invalid_item_snapshot["checksum"] = SnapshotScript.compute_checksum(invalid_item_snapshot)
	_assert_fail(store.accept_snapshot(invalid_item_snapshot), "WORLD_ITEM adapter accepted an unknown state field")
	var accepted: Dictionary = store.accept_snapshot(generic_snapshot)
	_assert_ok(accepted, "Generic store rejected world item snapshot")
	var handoff_store = StoreScript.new()
	_assert_ok(handoff_store.setup(registry), "Handoff replica store setup failed")
	_assert_ok(handoff_store.accept_snapshot(generic_snapshot), "Handoff store rejected initial item snapshot")
	var authority_transfer: Dictionary = generic_snapshot.duplicate(true)
	authority_transfer["descriptor"]["authority"]["authority_owner_id"] = "region-authority/a1-next"
	authority_transfer["descriptor"]["authority"]["authority_epoch"] = 5
	authority_transfer["descriptor"]["authority"]["server_tick"] = 501
	authority_transfer["checksum"] = SnapshotScript.compute_checksum(authority_transfer)
	var transfer_result: Dictionary = handoff_store.accept_snapshot(authority_transfer)
	_assert_ok(transfer_result, "Higher-epoch authority-only snapshot transfer rejected")
	_assert(bool(transfer_result.get("details", {}).get("authority_transfer", false)), "Authority-only snapshot transfer not marked")
	var hidden_transfer_mutation: Dictionary = authority_transfer.duplicate(true)
	hidden_transfer_mutation["descriptor"]["authority"]["authority_epoch"] = 6
	hidden_transfer_mutation["state"]["domain_components"] = {"hidden": true}
	hidden_transfer_mutation["checksum"] = SnapshotScript.compute_checksum(hidden_transfer_mutation)
	_assert_fail(handoff_store.accept_snapshot(hidden_transfer_mutation), "Higher-epoch same-revision hidden state mutation accepted")
	var replay_snapshot: Dictionary = store.accept_snapshot(generic_snapshot)
	_assert_ok(replay_snapshot, "Generic store rejected exact snapshot replay")
	_assert(bool(replay_snapshot.get("details", {}).get("replay", false)), "Snapshot replay not marked")
	var accessor: Dictionary = store.get_snapshot(aggregate.entity_id)
	_assert_ok(accessor, "Generic store could not return item snapshot")
	accessor["details"]["snapshot"]["state"]["domain_components"]["alias"] = true
	_assert(not store.get_snapshot(aggregate.entity_id).get("details", {}).get("snapshot", {}).get("state", {}).get("domain_components", {}).has("alias"), "Generic store leaked mutable snapshot reference")
	var invalid_result_delta: Dictionary = DeltaScript.create(
		"aggregate-delta/a1/item/invalid-result",
		aggregate.entity_id,
		"WORLD_ITEM",
		"planet_simulator.world_item_aggregate_state.v1",
		aggregate.authority_owner_id,
		aggregate.authority_epoch,
		aggregate.state_revision,
		aggregate.state_revision + 1,
		aggregate.last_simulation_tick + 1,
		{"item_instance_id": ""},
		[]
	)
	_assert_ok(DeltaScript.validate(invalid_result_delta), "Invalid-result fixture delta is not envelope-valid")
	_assert_fail(store.accept_delta(invalid_result_delta), "Delta producing kind-invalid result snapshot was committed")
	_assert(int(store.get_snapshot(aggregate.entity_id).get("details", {}).get("snapshot", {}).get("descriptor", {}).get("authority", {}).get("state_revision", -1)) == 12, "Rejected result delta changed stored revision")
	var mutation: Dictionary = aggregate.apply_domain_components(
		{"inventory": {"item_ids": [], "count": 0}, "network": {"moved": true}},
		12,
		4,
		501
	)
	_assert_ok(mutation, "World item domain mutation failed")
	var delta_result: Dictionary = registry.export_delta("WORLD_ITEM", generic_snapshot, aggregate, "aggregate-delta/a1/item/1")
	_assert_ok(delta_result, "World item generic delta export failed")
	var delta: Dictionary = delta_result.get("details", {}).get("delta", {})
	_assert_ok(DeltaScript.validate(delta), "World item generic delta invalid")
	var applied: Dictionary = store.accept_delta(delta)
	_assert_ok(applied, "Generic store rejected world item delta")
	_assert(not bool(applied.get("details", {}).get("replay", true)), "First world item delta marked replay")
	var final_snapshot: Dictionary = applied.get("details", {}).get("snapshot", {})
	_assert(_json_equal(final_snapshot["state"]["domain_components"], aggregate.domain_components), "Generic item replica does not match authority domain")
	_assert(int(final_snapshot["descriptor"]["authority"]["state_revision"]) == aggregate.state_revision, "Generic item replica revision differs")
	_assert(int(final_snapshot["descriptor"]["authority"]["server_tick"]) == aggregate.last_simulation_tick, "Generic item replica tick differs")
	var replay_delta: Dictionary = store.accept_delta(delta)
	_assert_ok(replay_delta, "Exact world item delta replay rejected")
	_assert(bool(replay_delta.get("details", {}).get("replay", false)), "World item delta replay not marked")
	var conflicting_delta: Dictionary = delta.duplicate(true)
	conflicting_delta["changed_fields"] = {"domain_components": {"conflict": true}}
	conflicting_delta["checksum"] = DeltaScript.compute_checksum(conflicting_delta)
	_assert_fail(store.accept_delta(conflicting_delta), "Conflicting delta ID accepted")
	var report: Dictionary = store.get_report()
	_assert(int(report["snapshot_count"]) == 1, "Generic item store snapshot count wrong")
	_assert(int(report["mutation_count"]) == 1, "Generic item store mutation count wrong")
	_assert(int(report["delta_replays"]) == 1, "Generic item store replay count wrong")
	_assert(int(report["direct_authority_references"]) == 0, "Generic store reports authority reference")
	_assert(int(report["direct_domain_references"]) == 0, "Generic store reports domain reference")


func _test_non_item_aggregate_vertical() -> void:
	var aggregate = EnvironmentAggregateScript.new()
	_assert(aggregate.setup({
		"aggregate_id": "environment-cell/main/18/42",
		"cell_id": "cell/main/18/42",
		"authority_owner_id": "region-authority/environment",
		"authority_epoch": 3,
		"state_revision": 20,
		"server_tick": 900,
		"state": {
			"temperature_k": 278.4,
			"soil_moisture": 0.42,
			"nutrients_by_id": {"nitrogen": 0.28},
		},
	}), "Environment aggregate setup failed")
	var adapter = EnvironmentAdapterScript.new()
	var registry = RegistryScript.new()
	_assert_ok(registry.setup(), "Environment adapter registry setup failed")
	_assert_ok(registry.register_adapter(adapter), "Environment adapter registration failed")
	var exported: Dictionary = registry.export_snapshot("ENVIRONMENT_CELL", aggregate, "aggregate-snapshot/a1/environment/1")
	_assert_ok(exported, "Environment aggregate snapshot export failed")
	var snapshot: Dictionary = exported.get("details", {}).get("snapshot", {})
	_assert_ok(SnapshotScript.validate(snapshot), "Environment aggregate snapshot invalid")
	_assert(String(snapshot["descriptor"]["spatial_scope"]["scope_kind"]) == "CELL", "Environment aggregate scope is not CELL")
	_assert(String(snapshot["descriptor"]["spatial_scope"]["scope_data"]["cell_id"]) == aggregate.cell_id, "Environment cell ID lost")
	_assert(snapshot["descriptor"]["partition_address"].is_empty(), "Environment test aggregate unexpectedly requires partition")
	_assert(not snapshot["state"].has("item_instance_id"), "Non-item aggregate requires item_instance_id")
	_assert(not snapshot["state"].has("physics_state"), "Non-item aggregate requires physics_state")
	_assert(not snapshot["state"].has("spatial_ref"), "Non-item aggregate requires point spatial_ref")
	var store = StoreScript.new()
	_assert_ok(store.setup(registry), "Environment generic store setup failed")
	var invalid_environment_snapshot: Dictionary = snapshot.duplicate(true)
	invalid_environment_snapshot["state"]["physics_state"] = {"mass_kg": 1.0}
	invalid_environment_snapshot["checksum"] = SnapshotScript.compute_checksum(invalid_environment_snapshot)
	_assert_fail(store.accept_snapshot(invalid_environment_snapshot), "Environment adapter accepted item-only physics state")
	_assert_ok(store.accept_snapshot(snapshot), "Environment snapshot rejected by generic store")
	var before_checksum: String = String(snapshot["checksum"])
	var mutation: Dictionary = aggregate.apply_state_patch({"temperature_k": 281.2, "soil_moisture": 0.48}, 20, 901)
	_assert_ok(mutation, "Environment aggregate mutation failed")
	var delta_result: Dictionary = registry.export_delta("ENVIRONMENT_CELL", snapshot, aggregate, "aggregate-delta/a1/environment/1")
	_assert_ok(delta_result, "Environment aggregate delta export failed")
	var delta: Dictionary = delta_result.get("details", {}).get("delta", {})
	_assert_ok(store.accept_delta(delta), "Environment aggregate delta rejected")
	var final_result: Dictionary = store.get_snapshot(aggregate.aggregate_id)
	_assert_ok(final_result, "Environment aggregate replica missing")
	var final_snapshot: Dictionary = final_result.get("details", {}).get("snapshot", {})
	_assert(String(final_snapshot["checksum"]) != before_checksum, "Environment aggregate checksum did not change")
	_assert(float(final_snapshot["state"]["temperature_k"]) == 281.2, "Environment temperature did not replicate")
	_assert(float(final_snapshot["state"]["soil_moisture"]) == 0.48, "Environment moisture did not replicate")
	_assert(int(final_snapshot["descriptor"]["authority"]["state_revision"]) == 21, "Environment revision did not replicate")
	_assert(int(final_snapshot["descriptor"]["authority"]["server_tick"]) == 901, "Environment tick did not replicate")
	_assert(store.get_snapshot_count() == 1, "Environment store count wrong")


func _json_equal(first, second) -> bool:
	return UtilsScript.canonical_json(first) == UtilsScript.canonical_json(second)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("A1 generic aggregate integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("A1 generic aggregate integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
