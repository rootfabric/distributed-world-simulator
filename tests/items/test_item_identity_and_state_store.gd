extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const IdGenerator = preload("res://scripts/items/services/item_id_generator.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const Presenter = preload("res://scripts/items/presentation/item_representation_system.gd")

var failures: Array[String] = []
var assertions: int = 0
var temporary_root: String = ""


func _init() -> void:
	temporary_root = "user://planet_simulator/tests/r11_%d_%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	_test_global_item_identity()
	_test_versioned_registry_roundtrip()
	_test_legacy_registry_compatibility()
	_test_transactional_load_failure()
	_test_spatial_ref_json_roundtrip()
	await _test_capture_preserves_spatial_context()
	_test_json_state_store()
	_finish()


func _test_global_item_identity() -> void:
	var fixture = _fixture()
	var ids: Dictionary = {}
	for index in range(256):
		var item = fixture.items.create_item("rock", 1, {}, Relations.world())
		_assert(item != null, "Global ID generation must create an item")
		if item == null:
			continue
		_assert(
			IdGenerator.is_global_id(item.instance_id),
			"Generated item ID must be a canonical item/UUID-v4: %s" % item.instance_id
		)
		_assert(not ids.has(item.instance_id), "Generated item IDs must be unique")
		_assert(item.display_name == "Rock", "Instance display name must default to definition display name")
		ids[item.instance_id] = true
	var named = fixture.items.create_item(
		"rock",
		1,
		{},
		Relations.world(),
		"Apollo sample 17"
	)
	_assert(named != null and named.display_name == "Apollo sample 17", "Explicit instance display name must be preserved")
	_assert(not String(named.instance_id).contains("rock_"), "Definition ID must not be encoded as a local sequence")


func _test_versioned_registry_roundtrip() -> void:
	var fixture = _fixture()
	var spatial_relation: Dictionary = Relations.world(
		Transform3D(Basis(Vector3.UP, 0.25), Vector3(10.0, 20.0, 30.0)),
		Vector3(1.0, 2.0, 3.0),
		"moon.fixed/site-alpha",
		1234.5,
		"main",
		"luna",
		"persistent",
		Vector3(0.1, 0.2, 0.3)
	)
	# Reproduce the original failure explicitly: feed typed arrays into the
	# aggregate boundary and require ItemInstance to strip metadata that JSON
	# cannot preserve.
	var typed_relation: Dictionary = spatial_relation.duplicate(true)
	var typed_spatial_ref: Dictionary = Dictionary(typed_relation.get("spatial_ref", {}))
	for field_name in [
		"position_m",
		"rotation_xyzw",
		"linear_velocity_mps",
		"angular_velocity_rps",
	]:
		typed_spatial_ref[field_name] = _as_typed_float_array(
			typed_spatial_ref.get(field_name, [])
		)
	typed_relation["spatial_ref"] = typed_spatial_ref
	for field_name in ["transform", "linear_velocity", "angular_velocity"]:
		typed_relation[field_name] = _as_typed_float_array(
			typed_relation.get(field_name, [])
		)
	var original = fixture.items.create_item(
		"rock",
		3,
		{"quality": "science"},
		typed_relation,
		"Sample A"
	)
	original.revision = 7
	var snapshot: Dictionary = fixture.items.to_dict()
	var spatial_payload: Dictionary = Dictionary(original.relation.get("spatial_ref", {}))
	for field_name in [
		"position_m",
		"rotation_xyzw",
		"linear_velocity_mps",
		"angular_velocity_rps",
	]:
		_assert_untyped_array(
			spatial_payload.get(field_name, null),
			"relation.spatial_ref.%s" % field_name
		)
	for field_name in ["transform", "linear_velocity", "angular_velocity"]:
		_assert_untyped_array(
			original.relation.get(field_name, null),
			"relation.%s" % field_name
		)
	_assert(
		original.relation == Relations.canonicalize(original.relation),
		"New WORLD relation must already be JSON-canonical"
	)
	_assert(String(snapshot.get("schema", "")) == "planet_simulator.item_registry.v2", "Registry snapshot must declare its schema")
	_assert(int(snapshot.get("schema_version", 0)) == 2, "Registry snapshot must declare schema version 2")
	_assert(not snapshot.has("sequence"), "Registry snapshot must not persist a local ID sequence")

	var encoded: String = JSON.stringify(snapshot, "", true, true)
	var decoded = JSON.parse_string(encoded)
	_assert(decoded is Dictionary, "Registry snapshot must survive JSON encoding")
	if not decoded is Dictionary:
		return
	var restored = Factory.create()
	var load_result: Dictionary = restored.items.load_dict(Dictionary(decoded))
	_assert_success(load_result, "Versioned registry snapshot must load")
	var restored_item = restored.items.get_item(original.instance_id)
	_assert(restored_item != null, "Registry roundtrip must preserve global item identity")
	if restored_item == null:
		return
	_assert(restored_item.display_name == "Sample A", "Registry roundtrip must preserve display name")
	_assert(restored_item.revision == 7, "Registry roundtrip must preserve revision")
	_assert(restored_item.components == {"quality": "science"}, "Registry roundtrip must preserve components")
	var relation_differences: Array[String] = []
	_collect_variant_differences(
		original.relation,
		restored_item.relation,
		"relation",
		relation_differences
	)
	_assert(
		relation_differences.is_empty(),
		"Registry roundtrip must preserve complete relation payload; differences=%s"
		% str(relation_differences)
	)


func _test_legacy_registry_compatibility() -> void:
	var fixture = _fixture()
	var legacy_snapshot: Dictionary = {
		"sequence": 2,
		"definitions": [fixture.items.get_definition("rock").to_dict()],
		"items": [{
			"instance_id": "rock_000001",
			"definition_id": "rock",
			"quantity": 1,
			"relation": Relations.world(),
			"components": {},
			"revision": 4,
		}],
	}
	var restored = Factory.create()
	var result: Dictionary = restored.items.load_dict(legacy_snapshot)
	_assert_success(result, "Legacy registry without schema must remain readable")
	_assert(int(result.get("source_schema_version", 0)) == 1, "Legacy registry must be reported as schema version 1")
	_assert(int(result.get("legacy_item_count", 0)) == 1, "Legacy item IDs must be reported explicitly")
	var legacy_item = restored.items.get_item("rock_000001")
	_assert(legacy_item != null, "Legacy item identity must not be silently rewritten")
	_assert(legacy_item != null and legacy_item.display_name == "Rock", "Legacy item must receive definition display name")
	var new_item = restored.items.create_item("rock", 1, {}, Relations.world())
	_assert(new_item != null and IdGenerator.is_global_id(new_item.instance_id), "Items created after legacy load must use global IDs")


func _test_transactional_load_failure() -> void:
	var fixture = _fixture()
	var existing = fixture.items.create_item("rock", 1, {}, Relations.world())
	var invalid_snapshot: Dictionary = fixture.items.to_dict()
	invalid_snapshot["schema_version"] = 999
	var result: Dictionary = fixture.items.load_dict(invalid_snapshot)
	_assert_error(result, "UNSUPPORTED_REGISTRY_VERSION", "Future registry schema must be rejected")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Rejected load must not mutate the active registry")

	var invalid_old_version: Dictionary = fixture.items.to_dict()
	invalid_old_version["schema_version"] = 1
	var invalid_old_version_result: Dictionary = fixture.items.load_dict(invalid_old_version)
	_assert_error(invalid_old_version_result, "UNSUPPORTED_REGISTRY_VERSION", "Versioned v2 envelope must not masquerade as a legacy snapshot")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Invalid old version must not mutate the active registry")

	var invalid_item_version: Dictionary = fixture.items.to_dict()
	invalid_item_version["items"][0]["schema_version"] = 999
	var invalid_item_version_result: Dictionary = fixture.items.load_dict(invalid_item_version)
	_assert_error(invalid_item_version_result, "UNSUPPORTED_ITEM_VERSION", "Future item schema must be rejected")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Invalid item schema must not mutate active state")

	var invalid_id_snapshot: Dictionary = fixture.items.to_dict()
	invalid_id_snapshot["items"][0]["instance_id"] = "rock_000001"
	var invalid_id_result: Dictionary = fixture.items.load_dict(invalid_id_snapshot)
	_assert_error(invalid_id_result, "INVALID_GLOBAL_ITEM_ID", "Schema v2 must reject local sequential IDs")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Invalid v2 ID must not partially replace registry state")

	var invalid_quantity_snapshot: Dictionary = fixture.items.to_dict()
	invalid_quantity_snapshot["items"][0]["quantity"] = 0
	var invalid_quantity_result: Dictionary = fixture.items.load_dict(invalid_quantity_snapshot)
	_assert_error(invalid_quantity_result, "INVALID_ITEM_QUANTITY", "Zero quantity must be rejected before ItemInstance normalization")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Invalid quantity must not partially replace registry state")

	var invalid_revision_snapshot: Dictionary = fixture.items.to_dict()
	invalid_revision_snapshot["items"][0]["revision"] = -1
	var invalid_revision_result: Dictionary = fixture.items.load_dict(invalid_revision_snapshot)
	_assert_error(invalid_revision_result, "INVALID_ITEM_REVISION", "Negative revision must be rejected")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Invalid revision must not partially replace registry state")

	var invalid_spatial_snapshot: Dictionary = fixture.items.to_dict()
	invalid_spatial_snapshot["items"][0]["relation"]["spatial_ref"]["frame_id"] = ""
	var invalid_spatial_result: Dictionary = fixture.items.load_dict(invalid_spatial_snapshot)
	_assert_error(invalid_spatial_result, "INVALID_ITEM_SPATIAL_REF", "Versioned WORLD relation must contain a valid SpatialRef")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Invalid SpatialRef must not partially replace registry state")

	var invalid_definition_snapshot: Dictionary = fixture.items.to_dict()
	invalid_definition_snapshot["definitions"][0]["max_stack"] = 0
	var invalid_definition_result: Dictionary = fixture.items.load_dict(invalid_definition_snapshot)
	_assert_error(invalid_definition_result, "INVALID_DEFINITION_MAX_STACK", "Invalid definition values must fail closed instead of being clamped")
	_assert(fixture.items.get_item(existing.instance_id) == existing, "Invalid definition must not partially replace registry state")


func _test_spatial_ref_json_roundtrip() -> void:
	var original_relation: Dictionary = Relations.world(
		Transform3D(Basis(Vector3(0.2, 1.0, 0.3).normalized(), 0.71), Vector3(1000.25, -42.5, 999999.125)),
		Vector3(12.5, -1.25, 3.75),
		"earth.fixed/site-athens",
		98765.4321,
		"main",
		"earth",
		"scenario-a",
		Vector3(0.001, 0.002, -0.003)
	)
	var encoded: String = JSON.stringify(original_relation, "", true, true)
	var decoded = JSON.parse_string(encoded)
	_assert(decoded is Dictionary, "WORLD relation must survive JSON encoding")
	if not decoded is Dictionary:
		return
	var relation: Dictionary = Dictionary(decoded)
	var spatial_ref: Dictionary = Relations.spatial_ref_from_relation(relation)
	_assert(SpatialRef.is_valid(spatial_ref), "Decoded SpatialRef must remain valid")
	_assert(String(spatial_ref.get("frame_id", "")) == "earth.fixed/site-athens", "SpatialRef frame_id must survive JSON")
	_assert(String(spatial_ref.get("universe_id", "")) == "main", "SpatialRef universe_id must survive JSON")
	_assert(String(spatial_ref.get("space_id", "")) == "earth", "SpatialRef space_id must survive JSON")
	_assert(String(spatial_ref.get("instance_id", "")) == "scenario-a", "SpatialRef instance_id must survive JSON")
	_assert(is_equal_approx(float(spatial_ref.get("sample_time_s", 0.0)), 98765.4321), "SpatialRef sample time must survive JSON")
	_assert(SpatialRef.get_position(spatial_ref).is_equal_approx(Vector3(1000.25, -42.5, 999999.125)), "SpatialRef position must survive JSON")
	_assert(SpatialRef.get_linear_velocity(spatial_ref).is_equal_approx(Vector3(12.5, -1.25, 3.75)), "SpatialRef linear velocity must survive JSON")
	_assert(SpatialRef.get_angular_velocity(spatial_ref).is_equal_approx(Vector3(0.001, 0.002, -0.003)), "SpatialRef angular velocity must survive JSON")


func _test_capture_preserves_spatial_context() -> void:
	var fixture = _fixture()
	var relation: Dictionary = Relations.world(
		Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0)),
		Vector3.ZERO,
		"moon.fixed/base-one",
		444.25,
		"universe-a",
		"moon",
		"persistent",
		Vector3.ZERO
	)
	var item = fixture.items.create_item("rock", 1, {}, relation)
	var world_root := Node3D.new()
	var attachment_root := Node3D.new()
	var presenter := Presenter.new()
	get_root().add_child(world_root)
	get_root().add_child(attachment_root)
	get_root().add_child(presenter)
	presenter.setup(fixture.items, world_root, attachment_root)
	presenter.synchronize_item(item.instance_id)
	var body: RigidBody3D = presenter.get_world_node(item.instance_id)
	_assert(body != null, "Presenter must create a world body for capture test")
	if body != null:
		body.transform = Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(7.0, 8.0, 9.0))
		body.linear_velocity = Vector3(4.0, 5.0, 6.0)
		body.angular_velocity = Vector3(0.4, 0.5, 0.6)
		_assert(presenter.capture_world_state(item.instance_id), "Presenter must capture world body state")
		var captured: Dictionary = Relations.spatial_ref_from_relation(item.relation)
		_assert(String(captured.get("frame_id", "")) == "moon.fixed/base-one", "Capture must preserve frame_id")
		_assert(String(captured.get("universe_id", "")) == "universe-a", "Capture must preserve universe_id")
		_assert(String(captured.get("space_id", "")) == "moon", "Capture must preserve space_id")
		_assert(String(captured.get("instance_id", "")) == "persistent", "Capture must preserve instance_id")
		_assert(is_equal_approx(float(captured.get("sample_time_s", 0.0)), 444.25), "Capture must preserve sample time when no new clock sample is supplied")
		_assert(SpatialRef.get_position(captured).is_equal_approx(Vector3(7.0, 8.0, 9.0)), "Capture must update position")
		_assert(SpatialRef.get_linear_velocity(captured).is_equal_approx(Vector3(4.0, 5.0, 6.0)), "Capture must update linear velocity")
		_assert(SpatialRef.get_angular_velocity(captured).is_equal_approx(Vector3(0.4, 0.5, 0.6)), "Capture must update angular velocity")
		_assert(not String(body.name).contains("/"), "Global item ID must be sanitized before use as Node name")
	presenter.queue_free()
	world_root.queue_free()
	attachment_root.queue_free()
	await process_frame


func _test_json_state_store() -> void:
	var fixture = _fixture()
	var item = fixture.items.create_item(
		"rock",
		2,
		{"origin": "test"},
		Relations.world(
			Transform3D(Basis.IDENTITY, Vector3(11.0, 12.0, 13.0)),
			Vector3(1.0, 0.0, 0.0),
			"moon.fixed/store-test",
			12.0,
			"main",
			"moon",
			"persistent",
			Vector3(0.0, 0.1, 0.0)
		),
		"Stored rock"
	)
	var root_store = Factory.create_json_state_store("user://")
	_assert(root_store.root_path == "user://", "State store must preserve the user:// scheme root")
	_assert(root_store.state_path("root-state") == "user://root-state.json", "State path must not introduce a third slash after user://")

	var store = Factory.create_json_state_store(temporary_root)
	var missing: Dictionary = store.load_state("missing")
	_assert_error(missing, "STATE_NOT_FOUND", "Loading absent state must return a stable error")
	var invalid_key: Dictionary = store.save_state("../escape", fixture.items.to_dict())
	_assert_error(invalid_key, "INVALID_STATE_KEY", "State store must reject path traversal keys")
	var hidden_key: Dictionary = store.save_state(".hidden", fixture.items.to_dict())
	_assert_error(hidden_key, "INVALID_STATE_KEY", "State store must reject hidden or dot-prefixed file keys")

	var save_result: Dictionary = store.save_state("registry-main", fixture.items.to_dict())
	_assert_success(save_result, "JSON ItemStateStore must save registry snapshot")
	_assert(store.has_state("registry-main"), "Saved state must become discoverable")
	var load_result: Dictionary = store.load_state("registry-main")
	_assert_success(load_result, "JSON ItemStateStore must load registry snapshot")
	var restored = Factory.create()
	var registry_load: Dictionary = restored.items.load_dict(Dictionary(load_result.get("state", {})))
	_assert_success(registry_load, "Registry loaded from ItemStateStore must validate")
	var restored_item = restored.items.get_item(item.instance_id)
	_assert(restored_item != null, "ItemStateStore roundtrip must preserve item ID")
	_assert(restored_item != null and restored_item.display_name == "Stored rock", "ItemStateStore roundtrip must preserve display name")
	_assert(restored_item != null and restored_item.relation == item.relation, "ItemStateStore roundtrip must preserve SpatialRef relation")

	item.revision = 9
	var overwrite_result: Dictionary = store.save_state("registry-main", fixture.items.to_dict())
	_assert_success(overwrite_result, "ItemStateStore must atomically replace an existing state")
	var overwritten_load: Dictionary = store.load_state("registry-main")
	_assert_success(overwritten_load, "Overwritten state must remain readable")
	var overwritten_registry = Factory.create()
	_assert_success(
		overwritten_registry.items.load_dict(Dictionary(overwritten_load.get("state", {}))),
		"Overwritten registry snapshot must validate"
	)
	var overwritten_item = overwritten_registry.items.get_item(item.instance_id)
	_assert(overwritten_item != null and overwritten_item.revision == 9, "Overwrite must expose the newest registry revision")

	var corrupt_path: String = store.state_path("corrupt")
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	_assert(corrupt_file != null, "Test must be able to create a corrupted state file")
	if corrupt_file != null:
		corrupt_file.store_string("{not valid json")
		corrupt_file.close()
		var corrupt_result: Dictionary = store.load_state("corrupt")
		_assert_error(corrupt_result, "INVALID_JSON", "Corrupted JSON must fail closed")

	var delete_result: Dictionary = store.delete_state("registry-main")
	_assert_success(delete_result, "Saved state must be deletable")
	_assert(not store.has_state("registry-main"), "Deleted state must no longer exist")
	store.delete_state("corrupt")


func _as_typed_float_array(value) -> Array[float]:
	var result: Array[float] = []
	if value is Array:
		for entry in value:
			result.append(float(entry))
	return result


func _assert_untyped_array(value, path: String) -> void:
	if not value is Array:
		_assert(false, "Persistence field must be an Array: %s; type=%s" % [
			path,
			type_string(typeof(value)),
		])
		return
	var array_value: Array = value
	_assert(
		not array_value.is_typed(),
		"Persistence field must use an untyped JSON-safe Array: %s" % path
	)


func _collect_variant_differences(
	expected,
	actual,
	path: String,
	output: Array[String],
	limit: int = 16
) -> void:
	if output.size() >= limit:
		return
	if typeof(expected) != typeof(actual):
		output.append("%s type %s != %s; expected=%s actual=%s" % [
			path,
			type_string(typeof(expected)),
			type_string(typeof(actual)),
			str(expected),
			str(actual),
		])
		return
	if expected is Dictionary:
		var expected_dictionary: Dictionary = expected
		var actual_dictionary: Dictionary = actual
		var expected_keys: Array = expected_dictionary.keys()
		expected_keys.sort()
		for key in expected_keys:
			if not actual_dictionary.has(key):
				output.append("%s.%s missing from actual" % [path, str(key)])
				if output.size() >= limit:
					return
				continue
			_collect_variant_differences(
				expected_dictionary[key],
				actual_dictionary[key],
				"%s.%s" % [path, str(key)],
				output,
				limit
			)
		for key in actual_dictionary.keys():
			if not expected_dictionary.has(key):
				output.append("%s.%s missing from expected" % [path, str(key)])
				if output.size() >= limit:
					return
		return
	if expected is Array:
		var expected_array: Array = expected
		var actual_array: Array = actual
		if expected_array.is_typed() != actual_array.is_typed():
			output.append("%s typed=%s != %s" % [
				path,
				str(expected_array.is_typed()),
				str(actual_array.is_typed()),
			])
		if expected_array.size() != actual_array.size():
			output.append("%s size %d != %d" % [
				path,
				expected_array.size(),
				actual_array.size(),
			])
			return
		for index in range(expected_array.size()):
			_collect_variant_differences(
				expected_array[index],
				actual_array[index],
				"%s[%d]" % [path, index],
				output,
				limit
			)
		return
	if expected != actual:
		output.append("%s expected=%s actual=%s" % [
			path,
			str(expected),
			str(actual),
		])


func _fixture() -> Dictionary:
	var fixture = Factory.create()
	fixture.items.register_definition(Definition.new({
		"id": "rock",
		"display_name": "Rock",
		"max_stack": 50,
		"unit_mass_kg": 2.0,
		"external_volume_l": 0.8,
		"tags": ["rock", "resource"],
	}))
	return fixture


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s; result=%s" % [message, str(result)])


func _assert_error(result: Dictionary, expected_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false))
		and String(result.get("error_code", "")) == expected_code,
		"%s; expected=%s result=%s" % [message, expected_code, str(result)]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Item identity and state store: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Item identity and state store: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
