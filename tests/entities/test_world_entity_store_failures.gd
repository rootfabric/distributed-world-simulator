extends SceneTree

const Store = preload("res://scripts/simulation/entities/world_entity_store.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")
const Factory = preload("res://scripts/items/services/item_domain_factory.gd")

const STATE_KEY: String = "world-entity-store-failures"
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var spatial: Dictionary = SpatialRef.create(
		"scenario/test/local",
		Vector3(2.0, 3.0, 4.0),
		Basis.from_euler(Vector3(0.2, 0.3, 0.4)),
		Vector3(1.0, 0.0, -1.0),
		Vector3.ZERO,
		4.5,
		"main",
		"scenario",
		"store-failure-test"
	)
	var store = Store.new()
	store.setup({"authority_owner_id": "server-a", "authority_epoch": 2})
	var aggregate = store.create_for_item(
		"item/00000000-0000-4000-8000-000000000011",
		spatial,
		{
			"physics_state": {"sleeping": false},
			"domain_components": {"definition_id": "beacon", "quantity": 1},
		}
	)
	_assert(aggregate != null, "Fixture aggregate must be created")
	var baseline: Dictionary = store.to_dict()
	_assert_success(store.load_dict(baseline), "Valid store snapshot must load")
	_assert(store.to_dict() == baseline, "Valid store round-trip must be exact")

	var missing: Dictionary = baseline.duplicate(true)
	missing.erase("entity_count")
	_assert_failed_transactionally(store, baseline, missing, "MISSING_WORLD_ENTITY_STORE_FIELD", "Missing store field")

	var extra: Dictionary = baseline.duplicate(true)
	extra["unexpected"] = true
	_assert_failed_transactionally(store, baseline, extra, "UNEXPECTED_WORLD_ENTITY_STORE_FIELD", "Unknown store field")

	var wrong_owner: Dictionary = baseline.duplicate(true)
	wrong_owner["authority_owner_id"] = 5
	_assert_failed_transactionally(store, baseline, wrong_owner, "INVALID_WORLD_ENTITY_STORE_AUTHORITY", "Numeric authority owner")

	var unsafe_epoch: Dictionary = baseline.duplicate(true)
	unsafe_epoch["authority_epoch"] = MAX_SAFE_JSON_INTEGER + 1
	_assert_failed_transactionally(store, baseline, unsafe_epoch, "INVALID_WORLD_ENTITY_STORE_AUTHORITY", "Unsafe authority epoch")

	var wrong_count_type: Dictionary = baseline.duplicate(true)
	wrong_count_type["entity_count"] = "1"
	_assert_failed_transactionally(store, baseline, wrong_count_type, "INVALID_WORLD_ENTITY_COUNT", "String entity count")

	var count_mismatch: Dictionary = baseline.duplicate(true)
	count_mismatch["entity_count"] = 2
	_assert_failed_transactionally(store, baseline, count_mismatch, "WORLD_ENTITY_COUNT_MISMATCH", "Entity count mismatch")

	var duplicate_entity: Dictionary = baseline.duplicate(true)
	duplicate_entity["entities"].append(Dictionary(duplicate_entity["entities"][0]).duplicate(true))
	duplicate_entity["entity_count"] = 2
	_assert_failed_transactionally(store, baseline, duplicate_entity, "DUPLICATE_ENTITY_ID", "Duplicate entity ID")

	var duplicate_item: Dictionary = baseline.duplicate(true)
	var duplicate_item_row: Dictionary = Dictionary(duplicate_item["entities"][0]).duplicate(true)
	duplicate_item_row["entity_id"] = "entity/item/00000000-0000-4000-8000-000000000012"
	duplicate_item["entities"].append(duplicate_item_row)
	duplicate_item["entity_count"] = 2
	_assert_failed_transactionally(store, baseline, duplicate_item, "DUPLICATE_ITEM_BINDING", "Duplicate item binding")

	var malformed_id: Dictionary = baseline.duplicate(true)
	malformed_id["entities"][0]["entity_id"] = 7
	_assert_invalid_entity_transactionally(store, baseline, malformed_id, "Numeric entity ID")

	var extra_entity_field: Dictionary = baseline.duplicate(true)
	extra_entity_field["entities"][0]["unknown"] = "value"
	_assert_invalid_entity_transactionally(store, baseline, extra_entity_field, "Unknown aggregate field")

	var unsafe_component: Dictionary = baseline.duplicate(true)
	unsafe_component["entities"][0]["domain_components"]["unsafe"] = MAX_SAFE_JSON_INTEGER + 1
	_assert_invalid_entity_transactionally(store, baseline, unsafe_component, "Unsafe nested component integer")

	var malformed_quaternion: Dictionary = baseline.duplicate(true)
	malformed_quaternion["entities"][0]["spatial_ref"]["rotation_xyzw"] = [0.0, 0.0, 0.0, 2.0]
	_assert_invalid_entity_transactionally(store, baseline, malformed_quaternion, "Non-unit aggregate quaternion")

	var missing_spatial_field: Dictionary = baseline.duplicate(true)
	missing_spatial_field["entities"][0]["spatial_ref"].erase("sample_time_s")
	_assert_invalid_entity_transactionally(store, baseline, missing_spatial_field, "Missing nested spatial field")

	var state_store = Factory.create_json_state_store("user://planet_simulator/world_entity_failure_test")
	state_store.delete_state(STATE_KEY)
	var forbidden_node := Node.new()
	var node_result: Dictionary = state_store.save_state(STATE_KEY, {"node": forbidden_node})
	forbidden_node.free()
	_assert_failure(node_result, "NON_CANONICAL_STATE_PAYLOAD", "Persistence port must reject Node before writing")
	_assert(not state_store.has_state(STATE_KEY), "Rejected Node payload must not create a file")
	var unsafe_result: Dictionary = state_store.save_state(STATE_KEY, {"unsafe": MAX_SAFE_JSON_INTEGER + 1})
	_assert_failure(unsafe_result, "NON_CANONICAL_STATE_PAYLOAD", "Persistence port must reject unsafe integer")
	_assert(not state_store.has_state(STATE_KEY), "Rejected unsafe integer must not create a file")
	_assert_success(state_store.save_state(STATE_KEY, baseline), "Canonical store snapshot must save")
	var loaded: Dictionary = state_store.load_state(STATE_KEY)
	_assert_success(loaded, "Canonical store snapshot must load")
	var canonical_baseline = JSON.parse_string(JSON.stringify(baseline, "", true, true))
	_assert(canonical_baseline is Dictionary and Dictionary(loaded.get("state", {})) == Dictionary(canonical_baseline), "Canonical state port round-trip must match JSON representation")
	state_store.delete_state(STATE_KEY)

	_finish()


func _assert_invalid_entity_transactionally(store, baseline: Dictionary, candidate: Dictionary, message: String) -> void:
	var result: Dictionary = store.load_dict(candidate)
	_assert_failure(result, "INVALID_WORLD_ENTITY_SNAPSHOT", message)
	_assert(store.to_dict() == baseline, "%s must not mutate live store" % message)
	var cause = result.get("details", {}).get("cause", {})
	_assert(cause is Dictionary and not bool(cause.get("success", true)), "%s must expose validation cause" % message)


func _assert_failed_transactionally(store, baseline: Dictionary, candidate: Dictionary, code: String, message: String) -> void:
	var result: Dictionary = store.load_dict(candidate)
	_assert_failure(result, code, message)
	_assert(store.to_dict() == baseline, "%s must not mutate live store" % message)


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_failure(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)), "%s: expected failure, got %s" % [message, result])
	_assert(String(result.get("error_code", "")) == code, "%s: expected %s, got %s" % [message, code, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("World entity store failure paths: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("World entity store failure paths: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
