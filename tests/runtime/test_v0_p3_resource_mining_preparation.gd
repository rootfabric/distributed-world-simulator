extends SceneTree

const FIXTURE_PATH := "res://tests/fixtures/v0_p3/resource_mining_contract.v1.json"
const EXPECTED_SCHEMA := "distributed_world_simulator.v0_p3_resource_mining_preparation.v1"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	_assert(FileAccess.file_exists(FIXTURE_PATH), "P3 resource/mining fixture exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH)) if FileAccess.file_exists(FIXTURE_PATH) else null
	_assert(parsed is Dictionary, "P3 resource/mining fixture parses as a dictionary")
	if not parsed is Dictionary:
		_finish()
		return
	var fixture: Dictionary = parsed
	_assert(String(fixture.get("schema", "")) == EXPECTED_SCHEMA, "fixture schema is exact")
	_assert(bool(fixture.get("preparation_only", false)), "fixture is preparation-only")
	_assert(not bool(fixture.get("production_runtime_mutation_allowed", true)), "preparation forbids production runtime mutation")
	_assert(String(fixture.get("activation_blocker", "")) == "P2_REVIEW_VERIFIER_DIRECTOR_AND_RUNTIME_FRONTIER_GATE", "P3 runtime activation is blocked on the declared P2/frontier gate")

	var authority: Dictionary = fixture.get("authority", {})
	_assert(String(authority.get("resource_state_owner", "")) == "dedicated-server", "resource depletion truth is dedicated-server authoritative")
	_assert(String(authority.get("item_output_owner", "")) == "canonical-m4-item-graph", "mining output stays in the canonical M4 Item Graph")
	_assert(String(authority.get("construction_role", "")) == "downstream-consumer", "Construction is a downstream consumer, not resource authority")
	_assert(Array(authority.get("client_authoritative_fields", [])).is_empty(), "client has no canonical resource authority fields")

	var resource: Dictionary = fixture.get("resource_node", {})
	_assert(String(resource.get("resource_node_id", "")).begins_with("resource/earth/"), "resource identity is an explicit Earth canonical id")
	_assert(String(resource.get("resource_definition_id", "")) == "resource/ore", "first resource definition is explicit")
	_assert(String(resource.get("output_definition_id", "")) == "item/ore", "resource output reuses existing item/ore definition")
	_assert(int(resource.get("remaining_units", -1)) == 8, "fixture starts with eight canonical resource units")
	_assert(int(resource.get("unit_item_quantity", -1)) == 1, "one mined unit maps to one output item quantity")
	var spatial: Dictionary = resource.get("spatial", {})
	_assert(String(spatial.get("frame", "")) == "earth-fixed", "resource canonical position uses Earth-fixed frame")
	_assert(_is_number(spatial.get("latitude_deg")) and _is_number(spatial.get("longitude_deg")) and _is_number(spatial.get("altitude_m")), "resource fixture carries numeric canonical Earth coordinates")

	var command: Dictionary = fixture.get("command", {})
	_assert(String(command.get("command_type", "")) == "resource.mine", "first mining command is resource.mine")
	_assert(Array(command.get("request_fields", [])) == ["resource_node_id", "requested_units"], "client request carries intent fields only")
	_assert(_contains_all(Array(command.get("forbidden_client_authority_fields", [])), ["remaining_units", "new_remaining_units", "output_item_id", "output_quantity", "revision", "generation", "checksum", "canonical_position"]), "client payload cannot declare authoritative mining results")

	var success: Dictionary = fixture.get("success", {})
	var output: Dictionary = success.get("output", {})
	_assert(int(success.get("decrement_per_unit", -1)) == 1, "success decrements one resource unit per requested unit")
	_assert(String(output.get("definition_id", "")) == "item/ore", "success output definition remains item/ore")
	_assert(int(output.get("quantity_per_unit", -1)) == 1, "success publishes one ore quantity per mined unit")
	_assert(String(output.get("canonical_owner", "")) == "canonical-m4-item-graph", "success output owner remains M4")
	_assert(bool(success.get("atomic_resource_and_item_publication_required", false)), "resource decrement and Item Graph output must publish atomically")

	var rejections: Array = fixture.get("rejections", [])
	var rejection_codes: Array[String] = _rejection_codes(rejections)
	var expected_rejection_codes: Array[String] = ["INVALID_MINING_QUANTITY", "RESOURCE_DEPLETED", "RESOURCE_NOT_FOUND", "RESOURCE_OUT_OF_RANGE", "RESOURCE_OUTPUT_REJECTED"]
	_assert(rejection_codes.size() == expected_rejection_codes.size() and _contains_all(Array(rejection_codes), expected_rejection_codes), "minimum P3 rejection taxonomy is frozen")
	_assert(_all_rejections_mutation_free(rejections), "all frozen preflight rejections are mutation-free")

	var seams: Dictionary = fixture.get("source_seams", {})
	var item_path := String(seams.get("item_graph", ""))
	var item_source := FileAccess.get_file_as_string(item_path) if FileAccess.file_exists(item_path) else ""
	_assert(FileAccess.file_exists(item_path) and item_source.contains("\"item/shared/ore/1\"") and item_source.contains("\"item/ore\""), "fixture is anchored to the existing canonical ore Item Graph seam")
	var construction_path := String(seams.get("construction_bundle", ""))
	var construction_source := FileAccess.get_file_as_string(construction_path) if FileAccess.file_exists(construction_path) else ""
	_assert(FileAccess.file_exists(construction_path) and construction_source.contains("server_generation") and construction_source.contains("checksum"), "fixture is anchored to existing authoritative Construction generation/checksum")
	var projection_path := String(seams.get("construction_projection", ""))
	var projection_source := FileAccess.get_file_as_string(projection_path) if FileAccess.file_exists(projection_path) else ""
	_assert(FileAccess.file_exists(projection_path) and projection_source.contains("ITEM_INSTANCE_SCHEMA") and projection_source.contains("definition_id"), "fixture is anchored to existing Construction read-only item projection")

	_finish()


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _contains_all(values: Array, expected: Array[String]) -> bool:
	for value in expected:
		if value not in values:
			return false
	return true


func _rejection_codes(rejections: Array) -> Array[String]:
	var result: Array[String] = []
	for value in rejections:
		if value is Dictionary:
			result.append(String(value.get("error_code", "")))
	result.sort()
	return result


func _all_rejections_mutation_free(rejections: Array) -> bool:
	if rejections.is_empty():
		return false
	for value in rejections:
		if not value is Dictionary or not bool(value.get("mutation_free", false)):
			return false
	return true


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % label)
		return
	failures.append(label)
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V0-P3 resource/mining preparation: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
