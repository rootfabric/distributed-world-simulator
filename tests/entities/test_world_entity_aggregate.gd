extends SceneTree

const Aggregate = preload("res://scripts/simulation/entities/world_entity_aggregate.gd")
const Store = preload("res://scripts/simulation/entities/world_entity_store.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const EntityLifecycle = preload("res://scripts/simulation/lifecycle/entity_lifecycle.gd")
const ChunkLifecycle = preload("res://scripts/simulation/lifecycle/chunk_lifecycle.gd")
const ChunkRuntime = preload("res://scripts/world/chunks/lunar_chunk_runtime.gd")
const ZoneRuntime = preload("res://scripts/world/zones/lunar_zone_runtime.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var spatial := SpatialRef.create(
		"scenario/test/local",
		Vector3(10.0, 20.0, 30.0),
		Basis.from_euler(Vector3(0.1, 0.2, 0.3)),
		Vector3(1.0, 2.0, 3.0),
		Vector3(0.1, 0.2, 0.3),
		12.5,
		"main",
		"scenario",
		"aggregate-test"
	)
	var aggregate = Aggregate.new()
	_assert(aggregate.setup(
		"entity/item/00000000-0000-4000-8000-000000000001",
		"item/00000000-0000-4000-8000-000000000001",
		spatial,
		{
			"authority_owner_id": "server-a",
			"authority_epoch": 3,
			"state_revision": 7,
			"physics_state": {"sleeping": false, "mass_kg": 4.5},
			"domain_components": {"definition_id": "beacon", "quantity": 1},
		}
	), "Aggregate setup must succeed")
	_assert_success(aggregate.validate(), "Aggregate must validate")
	_assert(aggregate.state_revision == 7, "Setup revision must be preserved")
	_assert(aggregate.authority_epoch == 3, "Authority epoch must be preserved")
	_assert(aggregate.lifecycle_state == EntityLifecycle.ACTIVE, "World aggregate must start ACTIVE")
	_assert(SpatialRef.get_position(aggregate.spatial_ref).is_equal_approx(Vector3(10, 20, 30)), "Spatial position must be canonical")

	var unchanged := aggregate.apply_spatial_state(
		spatial,
		{"sleeping": false, "mass_kg": 4.5},
		{},
		7,
		3,
		20
	)
	_assert_success(unchanged, "Equal spatial update must be accepted")
	_assert(not bool(unchanged.get("changed", true)), "Equal spatial update must be a no-op")
	_assert(aggregate.state_revision == 7, "No-op must not increment revision")

	var moved_ref := SpatialRef.create(
		"scenario/test/local",
		Vector3(11.0, 22.0, 33.0),
		Basis.IDENTITY,
		Vector3(4.0, 5.0, 6.0),
		Vector3.ZERO,
		13.0,
		"main",
		"scenario",
		"aggregate-test"
	)
	var moved := aggregate.apply_spatial_state(
		moved_ref,
		{"sleeping": true, "mass_kg": 4.5},
		{},
		7,
		3,
		21
	)
	_assert_success(moved, "Changed spatial state must apply")
	_assert(bool(moved.get("changed", false)), "Changed spatial state must report changed")
	_assert(aggregate.state_revision == 8, "Spatial update must increment revision once")
	_assert(aggregate.last_simulation_tick == 21, "Simulation tick must update")
	_assert(bool(aggregate.physics_state.get("sleeping", false)), "Physics state must update")
	_assert(SpatialRef.get_position(aggregate.spatial_ref).is_equal_approx(Vector3(11, 22, 33)), "Aggregate must own moved position")

	_assert_error(
		aggregate.apply_spatial_state(moved_ref, {}, {}, 7, 3),
		"REVISION_CONFLICT",
		"Stale expected revision must be rejected"
	)
	_assert_error(
		aggregate.apply_spatial_state(moved_ref, {}, {}, -1, 2),
		"STALE_AUTHORITY_EPOCH",
		"Stale authority epoch must be rejected"
	)

	var unloading := aggregate.transition_lifecycle(EntityLifecycle.UNLOADING)
	_assert_success(unloading, "ACTIVE -> UNLOADING must be legal")
	_assert(aggregate.lifecycle_state == EntityLifecycle.UNLOADING, "Aggregate must enter UNLOADING")
	_assert_error(
		aggregate.apply_spatial_state(moved_ref, {}, {}, -1, 3),
		"ENTITY_NOT_ACTIVE",
		"UNLOADING entity must reject simulation writes"
	)
	_assert_success(aggregate.transition_lifecycle(EntityLifecycle.DORMANT), "UNLOADING -> DORMANT must be legal")
	_assert_error(
		aggregate.transition_lifecycle(EntityLifecycle.ACTIVE),
		"ILLEGAL_LIFECYCLE_TRANSITION",
		"DORMANT -> ACTIVE must require WARM"
	)
	_assert_success(aggregate.transition_lifecycle(EntityLifecycle.WARM), "DORMANT -> WARM must be legal")
	_assert_success(aggregate.transition_lifecycle(EntityLifecycle.ACTIVE), "WARM -> ACTIVE must be legal")

	var before_authority_revision: int = aggregate.state_revision
	var authority := aggregate.transfer_authority("server-b", 4)
	_assert_success(authority, "Authority transfer must succeed")
	_assert(aggregate.authority_owner_id == "server-b", "Authority owner must change")
	_assert(aggregate.authority_epoch == 4, "Authority epoch must increase")
	_assert(aggregate.state_revision == before_authority_revision + 1, "Authority transfer must keep revision monotonic")
	_assert_error(aggregate.transfer_authority("server-c", 4), "STALE_AUTHORITY_EPOCH", "Equal epoch transfer must fail")

	var component_revision: int = aggregate.state_revision
	_assert_success(aggregate.apply_domain_components({"quantity": 2}, component_revision, 4), "Domain component patch must apply")
	_assert(int(aggregate.domain_components.get("quantity", 0)) == 2, "Domain component must update")
	_assert(aggregate.state_revision == component_revision + 1, "Domain patch must increment revision")

	var snapshot: Dictionary = aggregate.to_snapshot()
	var restored = Aggregate.new()
	_assert(restored.setup_from_snapshot(snapshot), "Aggregate snapshot must restore")
	_assert(restored.to_snapshot() == snapshot, "Aggregate snapshot round-trip must be exact")
	var negative_quaternion: Dictionary = snapshot.duplicate(true)
	for index in range(4):
		negative_quaternion["spatial_ref"]["rotation_xyzw"][index] = -float(negative_quaternion["spatial_ref"]["rotation_xyzw"][index])
	var sign_restored = Aggregate.new()
	_assert(sign_restored.setup_from_snapshot(negative_quaternion), "Equivalent negative quaternion must load")
	_assert(sign_restored.to_snapshot()["spatial_ref"]["rotation_xyzw"] == snapshot["spatial_ref"]["rotation_xyzw"], "Quaternion sign must canonicalize deterministically")
	var malformed_snapshot: Dictionary = snapshot.duplicate(true)
	malformed_snapshot["unexpected"] = true
	_assert(not Aggregate.new().setup_from_snapshot(malformed_snapshot), "Unknown aggregate field must fail strict schema")
	var nonunit_snapshot: Dictionary = snapshot.duplicate(true)
	nonunit_snapshot["spatial_ref"]["rotation_xyzw"] = [0.0, 0.0, 0.0, 2.0]
	_assert(not Aggregate.new().setup_from_snapshot(nonunit_snapshot), "Non-unit quaternion must fail strict persistence boundary")
	_assert(not Aggregate.new().setup_from_snapshot({"schema": "bad"}), "Unknown aggregate schema must fail")

	var store = Store.new()
	store.setup({"authority_owner_id": "server-a", "authority_epoch": 1})
	var store_aggregate = store.create_for_item(
		"item/00000000-0000-4000-8000-000000000002",
		spatial,
		{"physics_state": {"sleeping": false}}
	)
	_assert(store_aggregate != null, "Store must create deterministic aggregate")
	_assert(String(store_aggregate.entity_id).begins_with("entity/item/"), "Store entity ID must be deterministic")
	_assert(store.get_for_item(store_aggregate.item_instance_id) == store_aggregate, "Store item index must resolve aggregate")
	_assert(store.create_for_item(store_aggregate.item_instance_id, spatial) == null, "Duplicate item binding must fail")
	var store_snapshot: Dictionary = store.to_dict()
	var restored_store = Store.new()
	_assert_success(restored_store.load_dict(store_snapshot), "World entity store must load")
	_assert(restored_store.to_dict() == store_snapshot, "World entity store round-trip must be exact")
	_assert(restored_store.remove_for_item(store_aggregate.item_instance_id), "Store must remove item binding")
	_assert(restored_store.size() == 0, "Store removal must remove aggregate")

	_assert(ChunkLifecycle.can_transition(ChunkLifecycle.DORMANT, ChunkLifecycle.WARM), "Chunk DORMANT -> WARM must be legal")
	_assert(not ChunkLifecycle.can_transition(ChunkLifecycle.DORMANT, ChunkLifecycle.ACTIVE), "Chunk DORMANT -> ACTIVE must be illegal")
	var chunk = ChunkRuntime.new()
	chunk.setup("chunk/test", Vector3.UP)
	_assert(chunk.lifecycle_state == ChunkLifecycle.WARM, "Chunk runtime must start WARM")
	_assert_success(chunk.activate(10), "Chunk WARM -> ACTIVE must succeed")
	_assert(chunk.is_active(), "Chunk must report ACTIVE")
	_assert_success(chunk.begin_unload(11), "Chunk ACTIVE -> UNLOADING must succeed")
	_assert_success(chunk.mark_dormant(12), "Chunk UNLOADING -> DORMANT must succeed")
	_assert_error(chunk.activate(13), "ILLEGAL_CHUNK_TRANSITION", "Dormant chunk cannot activate directly")
	_assert_success(chunk.warm(14), "Dormant chunk must warm")
	_assert_success(chunk.activate(15), "Warm chunk must activate")
	_assert(int(chunk.create_snapshot().get("lifecycle_revision", 0)) >= 5, "Chunk snapshot must expose lifecycle revision")

	var zone = ZoneRuntime.new()
	zone.setup("zone/test", Vector3.UP)
	zone.chunks["chunk/test"] = chunk
	_assert_success(zone.activate(20), "Zone WARM -> ACTIVE must succeed")
	_assert(zone.active_chunk_count() == 1, "Zone must count active chunks")
	_assert_success(zone.begin_unload(21), "Zone unload must propagate")
	_assert(chunk.lifecycle_state == ChunkLifecycle.UNLOADING, "Zone unload must move child chunk to UNLOADING")
	_assert_success(zone.mark_dormant(22), "Zone must become DORMANT")
	_assert(chunk.lifecycle_state == ChunkLifecycle.DORMANT, "Zone dormancy must propagate to chunks")
	var blocked_zone = ZoneRuntime.new()
	blocked_zone.setup("zone/blocked", Vector3.UP)
	var dormant_child = ChunkRuntime.new()
	dormant_child.setup("chunk/dormant", Vector3.UP)
	_assert_success(dormant_child.mark_dormant(23), "Failure fixture child must become DORMANT")
	blocked_zone.chunks[dormant_child.chunk_id] = dormant_child
	_assert_success(blocked_zone.activate(24), "Failure fixture zone must become ACTIVE")
	var blocked_unload: Dictionary = blocked_zone.begin_unload(25)
	_assert_error(blocked_unload, "CHILD_CHUNK_TRANSITION_FAILED", "Zone unload must fail closed when a child cannot unload")
	_assert(blocked_zone.lifecycle_state == ChunkLifecycle.ACTIVE, "Failed child preflight must keep zone ACTIVE")
	_assert(dormant_child.lifecycle_state == ChunkLifecycle.DORMANT, "Failed child preflight must not mutate child")

	_finish()


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)), "%s: expected failure, got %s" % [message, result])
	_assert(String(result.get("error_code", "")) == code, "%s: expected %s, got %s" % [message, code, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("World entity aggregate: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("World entity aggregate: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
