extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture = preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const HistoryScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_history_store.gd")
const ProcessScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_process.gd")
const RequestScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_request.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/parametric/construction_parametric_capability_compiler.gd")
const FabricationCompilerScript = preload("res://scripts/construction/parametric/construction_parametric_fabrication_compiler.gd")
const PersistenceScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_persistence.gd")
const StateScript = preload("res://scripts/construction/geometry_edit/construction_local_geometry_state.gd")

class MemoryStore:
	extends RefCounted
	var states := {}
	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func load_state(key: String) -> Dictionary:
		if not states.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": Dictionary(states[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_authoritative_edit_and_replay()
	_test_constraints_and_multi_step_editing()
	_test_failure_atomicity_and_preconditions()
	_test_crash_reconcile_history()
	_test_downstream_recompilation_and_persistence()
	_finish()

func _environment(key: String) -> Dictionary:
	var graph := Fixture.graph(key)
	var adapter = AdapterScript.new()
	var setup := adapter.setup([graph["root"], graph["projection"]], [graph["snapshot"]])
	var catalog = Fixture.catalog()
	var history = HistoryScript.new()
	var process = ProcessScript.new()
	var process_setup := process.setup(adapter, catalog, history)
	return {"graph": graph, "adapter": adapter, "catalog": catalog, "history": history, "process": process, "setup": setup, "process_setup": process_setup}

func _test_authoritative_edit_and_replay() -> void:
	var env := _environment("authoritative")
	_assert_ok(env["setup"], "Adapter setup failed")
	_assert_ok(env["process_setup"], "Process setup failed")
	var graph: Dictionary = env["graph"]
	var request := Fixture.request("authoritative", graph, [Fixture.move_end(0, [6.0, 0.0, 0.0]), Fixture.set_parameter(1, "height_m", 0.25)], [Fixture.grid(0.5), Fixture.min_segment(0.5), Fixture.max_length(10.0), Fixture.lock_end_yz()])
	var result: Dictionary = env["process"].apply_edit("plan/geometry-edit/authoritative/1", request)
	_assert_ok(result, "Authoritative edit failed")
	_assert(not bool(result["replay"]), "First edit marked replay")
	_assert(env["adapter"].get_generation() == 1, "Edit did not advance adapter generation")
	_assert(env["history"].get_generation() == 1, "Edit did not enter history")
	var projection: Dictionary = env["adapter"].get_item_projection(String(request["item_instance_id"]))
	var snapshot: Dictionary = env["adapter"].get_construct_snapshot(String(request["construct_id"]))
	var instance: Dictionary = projection["components"]["parametric_member"]
	_assert(int(projection["revision"]) == 1, "Edited projection revision mismatch")
	_assert(int(snapshot["state_revision"]) == 1, "Edited construct revision mismatch")
	_assert_close(float(instance["parameter_values"]["length_m"]), 6.0, "Edited instance length mismatch")
	_assert_close(float(instance["parameter_values"]["height_m"]), 0.25, "Edited instance height mismatch")
	_assert_close(float(snapshot["parts"][0]["mass_kg"]), float(instance["mass_kg"]), "Construct part mass not synchronized")
	_assert(String(snapshot["parts"][0]["metadata"]["parametric_member_checksum"]) == String(instance["checksum"]), "Construct part checksum not synchronized")
	_assert(String(snapshot["parts"][0]["metadata"]["local_geometry_edit_state"]["checksum"]) == String(result["geometry_state"]["checksum"]), "Construct part local geometry state missing")
	_assert(snapshot["compiled_facets"]["geometry_edits"].has(String(request["operation_id"])), "Construct replay record missing")
	_assert(String(snapshot["compiled_facets"]["geometry_edits"][request["operation_id"]]["request_checksum"]) == String(request["checksum"]), "Replay record request checksum mismatch")
	_assert(String(result["record"]["after_member_checksum"]) == String(instance["checksum"]), "Result record after checksum mismatch")
	var generation_before: int = int(env["adapter"].get_generation())
	var history_before: int = int(env["history"].get_generation())
	var replay: Dictionary = env["process"].apply_edit("plan/geometry-edit/authoritative/1", request)
	_assert_ok(replay, "Exact edit replay failed")
	_assert(bool(replay["replay"]), "Exact edit replay not marked")
	_assert(env["adapter"].get_generation() == generation_before, "Exact replay changed adapter generation")
	_assert(env["history"].get_generation() == history_before, "Exact replay changed history generation")
	_assert(UtilsScript.canonical_json(replay["record"]) == UtilsScript.canonical_json(result["record"]), "Replay record changed")
	_assert(String(replay["updated_instance"]["checksum"]) == String(instance["checksum"]), "Replay returned wrong instance")
	var conflict := request.duplicate(true)
	conflict["metadata"]["conflict"] = true
	conflict["checksum"] = RequestScript.compute_checksum(conflict)
	var conflict_result: Dictionary = env["process"].apply_edit("plan/geometry-edit/authoritative/conflict", conflict)
	_assert_error(conflict_result, "CONSTRUCTION_GEOMETRY_EDIT_OPERATION_ID_CONFLICT", "Process accepted same operation ID with different request")
	_assert(env["adapter"].get_generation() == generation_before, "Conflict changed adapter generation")

func _test_constraints_and_multi_step_editing() -> void:
	var env := _environment("multi")
	_assert_ok(env["setup"], "Multi adapter setup failed")
	_assert_ok(env["process_setup"], "Multi process setup failed")
	var graph: Dictionary = env["graph"]
	var first := Fixture.request("multi", graph, [Fixture.insert_mid(0, "geometry-point/corner", "geometry-point/start", [2.0, 0.0, 0.0]), Fixture.move_end(1, [2.0, 3.0, 0.0])], [Fixture.grid(0.5), Fixture.min_segment(0.5), Fixture.max_length(10.0), Fixture.orthogonal()])
	var first_result: Dictionary = env["process"].apply_edit("plan/geometry-edit/multi/1", first)
	_assert_ok(first_result, "First polyline edit failed")
	_assert(first_result["geometry_state"]["control_points"].size() == 3, "Polyline point count mismatch")
	_assert_close(float(first_result["geometry_state"]["path_length_m"]), 5.0, "Polyline path length mismatch")
	_assert(UtilsScript.canonical_json(first_result["geometry_state"]["bounding_box_m"]) == UtilsScript.canonical_json([2, 3, 0]), "Polyline bounds mismatch")
	_assert_close(float(first_result["updated_instance"]["mass_kg"]), 785.0, "Polyline mass should use path length")
	var current_projection: Dictionary = env["adapter"].get_item_projection(String(first["item_instance_id"]))
	var current_snapshot: Dictionary = env["adapter"].get_construct_snapshot(String(first["construct_id"]))
	var current_instance: Dictionary = current_projection["components"]["parametric_member"]
	var second := RequestScript.create(
		"geometry-edit/multi/2",
		"operation/geometry-edit/multi/2",
		String(current_instance["member_instance_id"]),
		String(current_instance["item_instance_id"]),
		String(current_snapshot["construct_id"]),
		String(first["part_id"]),
		String(current_instance["checksum"]),
		int(current_projection["revision"]),
		String(current_snapshot["checksum"]),
		1,
		[Fixture.move_end(0, [2.0, 4.0, 0.0]), Fixture.set_parameter(1, "width_m", 0.15)],
		[],
		{"step": 2}
	)
	var second_result: Dictionary = env["process"].apply_edit("plan/geometry-edit/multi/2", second)
	_assert_ok(second_result, "Second edit failed")
	_assert(int(second_result["geometry_state"]["edit_revision"]) == 2, "Second edit revision mismatch")
	_assert(second_result["geometry_state"]["constraints"].size() == 4, "Second edit did not preserve constraints")
	_assert_close(float(second_result["geometry_state"]["path_length_m"]), 6.0, "Second path length mismatch")
	_assert_close(float(second_result["updated_instance"]["parameter_values"]["width_m"]), 0.15, "Second profile width mismatch")
	_assert_close(float(second_result["updated_instance"]["mass_kg"]), 1413.0, "Second edit mass mismatch")
	_assert(env["adapter"].get_generation() == 2, "Two edits did not produce two commits")
	_assert(env["history"].get_generation() == 2, "Two edits did not produce two history records")
	var after_projection: Dictionary = env["adapter"].get_item_projection(String(second["item_instance_id"]))
	var after_snapshot: Dictionary = env["adapter"].get_construct_snapshot(String(second["construct_id"]))
	_assert(int(after_projection["revision"]) == 2, "Second projection revision mismatch")
	_assert(int(after_snapshot["state_revision"]) == 2, "Second construct revision mismatch")
	_assert(after_snapshot["compiled_facets"]["geometry_edits"].size() == 2, "Geometry edit audit trail size mismatch")
	var locked_request := RequestScript.create(
		"geometry-edit/multi/3", "operation/geometry-edit/multi/3",
		String(second_result["updated_instance"]["member_instance_id"]), String(second_result["updated_instance"]["item_instance_id"]),
		String(after_snapshot["construct_id"]), String(second["part_id"]), String(second_result["updated_instance"]["checksum"]), int(after_projection["revision"]), String(after_snapshot["checksum"]), 2,
		[Fixture.move_end(0, [2.0, 4.0, 1.0])], [Fixture.lock_end_yz()], {}
	)
	_assert_error(env["process"].apply_edit("plan/geometry-edit/multi/3", locked_request), "CONSTRUCTION_GEOMETRY_EDIT_LOCKED_AXIS_CHANGED", "Process changed locked endpoint axis")
	_assert(env["adapter"].get_generation() == 2, "Rejected constraint edit changed state")

func _test_failure_atomicity_and_preconditions() -> void:
	var env := _environment("failure")
	_assert_ok(env["setup"], "Failure adapter setup failed")
	_assert_ok(env["process_setup"], "Failure process setup failed")
	var graph: Dictionary = env["graph"]
	var request := Fixture.request("failure", graph, [Fixture.move_end(0, [8.0, 0.0, 0.0])], [Fixture.max_length(10.0)])
	var before_projection: Dictionary = env["adapter"].get_item_projection(String(request["item_instance_id"]))
	var before_snapshot: Dictionary = env["adapter"].get_construct_snapshot(String(request["construct_id"]))
	var failed: Dictionary = env["process"].apply_edit("plan/geometry-edit/failure/1", request, "BEFORE_COMMIT")
	_assert_error(failed, "INJECTED_CONSTRUCTION_COMMIT_FAILURE", "Injected failure did not fail")
	_assert(env["adapter"].get_generation() == 0, "Injected failure changed generation")
	_assert(env["history"].get_generation() == 0, "Injected failure wrote history")
	_assert(UtilsScript.canonical_json(env["adapter"].get_item_projection(String(request["item_instance_id"]))) == UtilsScript.canonical_json(before_projection), "Injected failure changed item")
	_assert(UtilsScript.canonical_json(env["adapter"].get_construct_snapshot(String(request["construct_id"]))) == UtilsScript.canonical_json(before_snapshot), "Injected failure changed construct")
	var stale_member := request.duplicate(true); stale_member["expected_member_checksum"] = "f".repeat(64); stale_member["operation_id"] = "operation/geometry-edit/failure/stale-member"; stale_member["edit_id"] = "geometry-edit/failure/stale-member"; stale_member["checksum"] = RequestScript.compute_checksum(stale_member)
	_assert_error(env["process"].apply_edit("plan/geometry-edit/failure/stale-member", stale_member), "CONSTRUCTION_GEOMETRY_EDIT_MEMBER_PRECONDITION_MISMATCH", "Process accepted stale member checksum")
	var stale_item := request.duplicate(true); stale_item["expected_item_revision"] = 1; stale_item["operation_id"] = "operation/geometry-edit/failure/stale-item"; stale_item["edit_id"] = "geometry-edit/failure/stale-item"; stale_item["checksum"] = RequestScript.compute_checksum(stale_item)
	_assert_error(env["process"].apply_edit("plan/geometry-edit/failure/stale-item", stale_item), "CONSTRUCTION_GEOMETRY_EDIT_ITEM_PRECONDITION_MISMATCH", "Process accepted stale item revision")
	var stale_construct := request.duplicate(true); stale_construct["expected_construct_checksum"] = "e".repeat(64); stale_construct["operation_id"] = "operation/geometry-edit/failure/stale-construct"; stale_construct["edit_id"] = "geometry-edit/failure/stale-construct"; stale_construct["checksum"] = RequestScript.compute_checksum(stale_construct)
	_assert_error(env["process"].apply_edit("plan/geometry-edit/failure/stale-construct", stale_construct), "CONSTRUCTION_GEOMETRY_EDIT_CONSTRUCT_PRECONDITION_MISMATCH", "Process accepted stale construct checksum")
	var too_long := Fixture.request("failure-too-long", Fixture.graph("failure-too-long"), [Fixture.move_end(0, [12.0, 0.0, 0.0])], [Fixture.max_length(10.0)])
	var env_long := _environment("failure-too-long")
	_assert_error(env_long["process"].apply_edit("plan/geometry-edit/failure-too-long/1", too_long), "CONSTRUCTION_GEOMETRY_EDIT_MAX_TOTAL_LENGTH_VIOLATED", "Process accepted excessive path")
	_assert(env_long["adapter"].get_generation() == 0, "Constraint rejection changed long environment")
	var short_segment_graph := Fixture.graph("failure-short")
	var short_request := Fixture.request("failure-short", short_segment_graph, [Fixture.insert_mid(0, "geometry-point/short", "geometry-point/start", [0.1, 0.0, 0.0])], [Fixture.min_segment(0.5)])
	var env_short := _environment("failure-short")
	_assert_error(env_short["process"].apply_edit("plan/geometry-edit/failure-short/1", short_request), "CONSTRUCTION_GEOMETRY_EDIT_MIN_SEGMENT_LENGTH_VIOLATED", "Process accepted short segment")
	_assert(env_short["adapter"].get_generation() == 0, "Short segment rejection changed state")

func _test_crash_reconcile_history() -> void:
	var graph := Fixture.graph("crash")
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup([graph["root"], graph["projection"]], [graph["snapshot"]]), "Crash adapter setup failed")
	var catalog = Fixture.catalog()
	var process_without_history = ProcessScript.new()
	_assert_ok(process_without_history.setup(adapter, catalog, null), "Crash process setup failed")
	var request := Fixture.request("crash", graph, [Fixture.move_end(0, [7.0, 0.0, 0.0])], [Fixture.min_segment(0.5)])
	var committed: Dictionary = process_without_history.apply_edit("plan/geometry-edit/crash/1", request)
	_assert_ok(committed, "Crash precondition commit failed")
	_assert(adapter.get_generation() == 1, "Crash commit generation mismatch")
	var history = HistoryScript.new()
	_assert(history.get_generation() == 0, "Fresh crash history not empty")
	var recovered_process = ProcessScript.new()
	_assert_ok(recovered_process.setup(adapter, catalog, history), "Recovered process setup failed")
	var recovered: Dictionary = recovered_process.apply_edit("plan/geometry-edit/crash/1", request)
	_assert_ok(recovered, "Committed edit replay recovery failed")
	_assert(bool(recovered["replay"]), "Recovered edit not marked replay")
	_assert(adapter.get_generation() == 1, "Recovery replay duplicated authoritative commit")
	_assert(history.get_generation() == 1, "Recovery replay did not reconstruct history")
	_assert(String(history.get_record(String(request["operation_id"]))["request_checksum"]) == String(request["checksum"]), "Recovered history request checksum mismatch")

func _test_downstream_recompilation_and_persistence() -> void:
	var env := _environment("downstream")
	_assert_ok(env["setup"], "Downstream adapter setup failed")
	_assert_ok(env["process_setup"], "Downstream process setup failed")
	var request := Fixture.request("downstream", env["graph"], [Fixture.move_end(0, [10.0, 0.0, 0.0]), Fixture.set_parameter(1, "width_m", 0.25)], [Fixture.grid(0.5), Fixture.min_segment(0.5)])
	var edited: Dictionary = env["process"].apply_edit("plan/geometry-edit/downstream/1", request)
	_assert_ok(edited, "Downstream edit failed")
	var instance: Dictionary = edited["updated_instance"]
	var capability := CapabilityCompilerScript.compile(instance, String(request["part_id"]))
	_assert_ok(capability, "Edited capability compile failed")
	_assert(String(capability["capability"]["capability_kind"]) == "LOAD_BEARING_MEMBER", "Edited capability kind changed")
	_assert_close(float(capability["capability"]["properties"]["mass_kg"]), float(instance["mass_kg"]), "Capability mass stale")
	_assert_close(float(capability["capability"]["properties"]["geometry"]["length_m"]), 10.0, "Capability geometry stale")
	_assert(String(capability["capability"]["properties"]["local_geometry"]["checksum"]) == String(edited["geometry_state"]["checksum"]), "Capability local geometry stale")
	var recipe := FabricationCompilerScript.compile_recipe("fabrication-recipe/c11/downstream", 1, "Edited beam", instance, 0.01)
	_assert_ok(recipe, "Edited fabrication recipe failed")
	_assert(String(recipe["recipe"]["metadata"]["member_checksum"]) == String(instance["checksum"]), "Fabrication recipe pinned stale member")
	_assert(int(recipe["recipe"]["input_requirements"][0]["quantity"]) == int(instance["material_usage"][0]["stock_units"]), "Fabrication recipe stock units stale")
	_assert(int(recipe["recipe"]["work_units"]) == maxi(1, int(ceil(float(instance["mass_kg"]) * 0.01))), "Fabrication recipe work units stale")
	var adapter_state: Dictionary = env["adapter"].export_state()
	var restored_adapter = AdapterScript.new()
	_assert_ok(restored_adapter.load_state(adapter_state), "Adapter state restore failed")
	var restored_projection: Dictionary = restored_adapter.get_item_projection(String(request["item_instance_id"]))
	var restored_instance: Dictionary = restored_projection["components"]["parametric_member"]
	_assert(String(restored_instance["checksum"]) == String(instance["checksum"]), "Restored adapter changed edited member")
	_assert_ok(StateScript.validate(restored_instance["provenance"]["local_geometry_edit_state"]), "Restored local geometry state invalid")
	var storage = MemoryStore.new()
	_assert_ok(PersistenceScript.save(storage, env["history"]), "History persistence save failed")
	var restored_history = HistoryScript.new()
	_assert_ok(PersistenceScript.load(storage, restored_history), "History persistence load failed")
	_assert(restored_history.get_generation() == 1, "Restored history generation mismatch")
	var restored_record := restored_history.get_record(String(request["operation_id"]))
	_assert(String(restored_record["after_member_checksum"]) == String(instance["checksum"]), "Restored history member checksum mismatch")
	_assert_close(float(restored_record["mass_delta_kg"]), float(instance["mass_kg"]) - float(env["graph"]["instance"]["mass_kg"]), "Restored history mass delta mismatch")
	_assert(String(restored_record["after_state"]["checksum"]) == String(edited["geometry_state"]["checksum"]), "Restored history geometry state mismatch")

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, expected: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == expected, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _assert_close(actual: float, expected: float, message: String) -> void:
	_assert(is_equal_approx(actual, expected) or absf(actual - expected) <= 0.0000001 * maxf(1.0, absf(expected)), "%s: actual=%s expected=%s" % [message, actual, expected])
func _finish() -> void:
	if failures.is_empty():
		print("C11 local geometry editing integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C11 local geometry editing integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
