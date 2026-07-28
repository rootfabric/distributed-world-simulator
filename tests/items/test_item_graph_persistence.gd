extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const GraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")

const STORE_ROOT := "user://planet_simulator/test_item_graph_r14"
const STATE_KEY := "full-graph"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store = Factory.create_json_state_store(STORE_ROOT)
	store.delete_state(STATE_KEY)
	var domain := _fixture()
	var persistence = GraphPersistence.new()
	persistence.setup(domain, store, STATE_KEY)
	var before: Dictionary = persistence.create_snapshot({"checkpoint": "r1.4", "selected_hotbar_index": 3})
	_assert(String(before.schema) == GraphPersistence.SCHEMA, "Graph snapshot schema must be current")
	_assert(int(before.schema_version) == 2, "Graph snapshot version must be 2")
	_assert(_capacity_marker(before, "backpack", "maximum_mass_kg") == -1.0, "Infinite mass capacity must serialize as finite -1 marker")
	_assert(_capacity_marker(before, "backpack", "maximum_volume_l") == -1.0, "Infinite volume capacity must serialize as finite -1 marker")
	_assert_success(domain.validator.validate_graph(), "Fixture graph must be valid")

	var save_result: Dictionary = persistence.save({"checkpoint": "r1.4", "selected_hotbar_index": 3})
	_assert_success(save_result, "Complete item graph must save")
	_assert(store.has_state(STATE_KEY), "Saved graph must exist in state store")

	var restored := Factory.create(32)
	var restored_persistence = GraphPersistence.new()
	restored_persistence.setup(restored, store, STATE_KEY)
	var generation_before_load := int(restored.operations.get_content_generation())
	var load_result: Dictionary = restored_persistence.load()
	_assert_success(load_result, "Complete item graph must load")
	_assert(int(load_result.item_count) == domain.items.items.size(), "Load must restore every item")
	_assert(int(load_result.container_count) == domain.containers.containers.size(), "Load must restore every container")
	_assert(int(load_result.socket_count) == 1, "Load must restore attachment sockets")
	_assert(int(load_result.operation_count) == domain.operations.size(), "Load must restore operation ledger")
	_assert(int(restored.operations.get_content_generation()) > generation_before_load, "Graph persistence commit must invalidate transient operation-ledger consumers")
	_assert(not restored_persistence.create_snapshot().operations.has("content_generation"), "Transient operation-ledger generation must not enter graph snapshots")
	_assert(int(load_result.metadata.selected_hotbar_index) == 3, "Load must restore graph metadata")
	_assert_success(restored.validator.validate_graph(), "Restored graph must pass all invariants")
	var after_snapshot: Dictionary = restored_persistence.create_snapshot()
	var exact_match := JSON.stringify(after_snapshot, "", true, true) == JSON.stringify(before, "", true, true)
	if not exact_match:
		print("GRAPH_DIFF=" + JSON.stringify(_first_difference(before, after_snapshot), "", true, true))
	_assert(exact_match, "Save/load must preserve the full item graph exactly")

	var rack = restored.containers.get_container("battery_rack")
	_assert(rack != null and rack.get_item_at_slot(0) != "", "Slot assignment must survive restart")
	var socket: Dictionary = restored.attachments.get_socket_state("mount-a", "beacon")
	_assert(not String(socket.get("item_id", "")).is_empty(), "Mounted item must survive restart")

	var stable_before := JSON.stringify(restored_persistence.create_snapshot(), "", true, true)
	var missing_item := restored_persistence.create_snapshot()
	var backpack_row: Dictionary = _container_row(missing_item, "backpack")
	var referenced_id := String(backpack_row.get("item_ids", [""])[0])
	_remove_item_row(missing_item, referenced_id)
	var invalid_result: Dictionary = restored_persistence.load_snapshot(missing_item)
	_assert(not bool(invalid_result.get("success", false)), "Missing referenced item must fail closed")
	_assert(JSON.stringify(restored_persistence.create_snapshot(), "", true, true) == stable_before, "Failed graph load must not mutate live state")

	var cyclic := restored_persistence.create_snapshot()
	var hotbar_row: Dictionary = _container_row(cyclic, "hotbar")
	hotbar_row["parent_container_id"] = "hotbar"
	var cycle_result: Dictionary = restored_persistence.load_snapshot(cyclic)
	_assert(not bool(cycle_result.get("success", false)), "Container parent cycle must fail closed")
	_assert(String(cycle_result.get("error_code", "")) == "CONTAINER_PARENT_CYCLE", "Cycle failure must preserve precise error code")
	_assert(JSON.stringify(restored_persistence.create_snapshot(), "", true, true) == stable_before, "Cycle rejection must remain transactional")

	store.delete_state(STATE_KEY)
	_finish()


func _fixture() -> Dictionary:
	var domain: Dictionary = Factory.create(32)
	for data in [
		{"id": "beacon", "display_name": "Beacon", "max_stack": 5, "unit_mass_kg": 2.5, "external_volume_l": 3.0, "tags": ["beacon", "mountable"]},
		{"id": "battery", "display_name": "Battery", "max_stack": 4, "unit_mass_kg": 8.0, "external_volume_l": 6.0, "tags": ["battery"]},
		{"id": "rock", "display_name": "Rock", "max_stack": 50, "unit_mass_kg": 2.0, "external_volume_l": 0.8, "tags": ["resource"]},
		{"id": "crate", "display_name": "Crate", "max_stack": 1, "unit_mass_kg": 4.0, "external_volume_l": 30.0, "tags": ["container"]},
		{"id": "mount", "display_name": "Mount", "max_stack": 1, "unit_mass_kg": 40.0, "external_volume_l": 100.0, "tags": ["assembly_root"], "metadata": {"presentation_mode": "EXTERNAL"}},
	]:
		domain.items.register_definition(Definition.new(data))

	var backpack = ContainerState.new({"container_id": "backpack", "owner_kind": "ACTOR", "owner_id": "player", "storage_mode": ContainerState.STORAGE_BULK, "slot_count": 16, "maximum_mass_kg": INF, "maximum_volume_l": INF, "allow_nested_containers": true})
	var hotbar = ContainerState.new({"container_id": "hotbar", "owner_kind": "ACTOR", "owner_id": "player", "parent_container_id": "backpack", "storage_mode": ContainerState.STORAGE_SLOTS, "slot_count": 10, "slot_rules": [{}, {}, {}, {}, {}, {}, {}, {}, {}, {}]})
	var rack = ContainerState.new({"container_id": "battery_rack", "owner_kind": "SYSTEM", "owner_id": "rack", "storage_mode": ContainerState.STORAGE_SLOTS, "slot_count": 2, "slot_rules": [{"accepted_tags": ["battery"]}, {"accepted_tags": ["battery"]}], "allow_nested_containers": false})
	_assert(domain.containers.add_container(backpack), "Backpack must register")
	_assert(domain.containers.add_container(hotbar), "Hotbar must register")
	_assert(domain.containers.add_container(rack), "Battery rack must register")

	var crate = domain.items.create_item("crate", 1, {"container": {"container_id": "crate_contents"}}, Relations.world(Transform3D(Basis.IDENTITY, Vector3(2, 1, 0))))
	var crate_contents = ContainerState.new({"container_id": "crate_contents", "owner_kind": "ITEM_INSTANCE", "owner_id": crate.instance_id, "storage_mode": ContainerState.STORAGE_BULK, "slot_count": 8, "allow_nested_containers": true})
	_assert(domain.containers.add_container(crate_contents), "Owned crate container must register")
	var rocks = domain.items.create_item("rock", 6, {}, Relations.container("crate_contents"))
	crate_contents.assign_item(rocks.instance_id)

	var carried = domain.items.create_item("beacon", 2, {}, Relations.container("backpack"))
	backpack.assign_item(carried.instance_id)
	var battery = domain.items.create_item("battery", 1, {}, Relations.container("battery_rack", 0))
	rack.assign_item(battery.instance_id, 0)
	var mount = domain.items.create_item("mount", 1, {}, Relations.world(Transform3D.IDENTITY))
	domain.attachments.register_socket("mount-a", mount.instance_id, "beacon", ["beacon"])
	var mounted = domain.items.create_item("beacon", 1, {}, Relations.container("backpack"))
	backpack.assign_item(mounted.instance_id)
	_assert_success(domain.attachments.attach(mounted.instance_id, "mount-a", "beacon", "attach-1", mounted.revision), "Beacon must mount before snapshot")
	_assert(domain.operations.size() == 1, "Terminal operation must enter persisted ledger")
	return domain


func _first_difference(left, right, path: String = "graph") -> Dictionary:
	if typeof(left) != typeof(right):
		return {"path": path, "left_type": type_string(typeof(left)), "right_type": type_string(typeof(right)), "left": left, "right": right}
	if left is Dictionary:
		var keys: Array = left.keys()
		for key in right.keys():
			if not keys.has(key):
				keys.append(key)
		keys.sort()
		for key in keys:
			if not left.has(key) or not right.has(key):
				return {"path": path + "." + String(key), "left": left.get(key), "right": right.get(key)}
			var diff := _first_difference(left[key], right[key], path + "." + String(key))
			if not diff.is_empty():
				return diff
	elif left is Array:
		if left.size() != right.size():
			return {"path": path, "left_size": left.size(), "right_size": right.size()}
		for index in range(left.size()):
			var diff := _first_difference(left[index], right[index], "%s[%d]" % [path, index])
			if not diff.is_empty():
				return diff
	elif left != right:
		return {"path": path, "left": left, "right": right, "left_type": type_string(typeof(left)), "right_type": type_string(typeof(right))}
	return {}


func _capacity_marker(snapshot: Dictionary, container_id: String, key: String) -> float:
	return float(_container_row(snapshot, container_id).get(key, 0.0))


func _container_row(snapshot: Dictionary, container_id: String) -> Dictionary:
	for row_value in snapshot.get("containers", {}).get("containers", []):
		if row_value is Dictionary and String(row_value.get("container_id", "")) == container_id:
			return row_value
	return {}


func _remove_item_row(snapshot: Dictionary, item_id: String) -> void:
	var rows: Array = snapshot.get("items", {}).get("items", [])
	for index in range(rows.size() - 1, -1, -1):
		if String(rows[index].get("instance_id", "")) == item_id:
			rows.remove_at(index)


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Item graph persistence: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Item graph persistence: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
