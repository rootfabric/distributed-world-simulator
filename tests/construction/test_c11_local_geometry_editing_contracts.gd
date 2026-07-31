extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Fixture = preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")
const C10Fixture = preload("res://tests/construction/fixtures/c10_parametric_members_fixture.gd")
const PointScript = preload("res://scripts/construction/geometry_edit/construction_geometry_control_point.gd")
const ConstraintScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_constraint.gd")
const OperationScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_operation.gd")
const StateScript = preload("res://scripts/construction/geometry_edit/construction_local_geometry_state.gd")
const RequestScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_request.gd")
const RecordScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_record.gd")
const CompilerScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_compiler.gd")
const PlannerScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_transaction_planner.gd")
const HistoryScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_history_store.gd")
const PersistenceScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_persistence.gd")
const TransactionScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")

class MemoryStore:
	extends RefCounted
	var states := {}
	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true)
		return {"success": true, "error_code": "", "message": ""}
	func load_state(key: String) -> Dictionary:
		if not states.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": Dictionary(states[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_control_point_and_state_contracts()
	_test_constraint_contracts()
	_test_operation_and_request_contracts()
	_test_edit_compiler_contracts()
	_test_transaction_and_history_contracts()
	_finish()

func _test_control_point_and_state_contracts() -> void:
	var start := Fixture.point("geometry-point/start", 0, [0, 0.0, 0])
	var end := Fixture.point("geometry-point/end", 1, [4.0, 0.0, 0.0])
	_assert_ok(PointScript.validate(start), "Valid start point rejected")
	_assert_ok(PointScript.validate(end), "Valid end point rejected")
	_assert(UtilsScript.canonical_json(start["position_m"]) == UtilsScript.canonical_json([0, 0, 0]), "Point coordinates not canonical")
	var bad_point := start.duplicate(true); bad_point["position_m"] = [0.0, 0.0]
	_assert_error(PointScript.validate(bad_point), "INVALID_CONSTRUCTION_GEOMETRY_CONTROL_POINT_POSITION", "Point accepted wrong vector size")
	var state := StateScript.create("parametric-member/test/state", "item/test/state", 0, [start, end], [Fixture.grid(0.5)], "geometry-edit/bootstrap", "a".repeat(64))
	_assert_ok(StateScript.validate(state), "Valid geometry state rejected")
	_assert_close(float(state["path_length_m"]), 4.0, "State path length mismatch")
	_assert(UtilsScript.canonical_json(state["bounding_box_m"]) == UtilsScript.canonical_json([4, 0, 0]), "State bounding box mismatch")
	_assert(state["control_points"][0]["ordinal"] == 0 and state["control_points"][1]["ordinal"] == 1, "State point ordinals changed")
	_assert(state["constraints"].size() == 1, "State constraints missing")
	var duplicate := state.duplicate(true); duplicate["control_points"][1]["point_id"] = "geometry-point/start"; duplicate["checksum"] = StateScript.compute_checksum(duplicate)
	_assert_error(StateScript.validate(duplicate), "DUPLICATE_CONSTRUCTION_LOCAL_GEOMETRY_CONTROL_POINT", "State accepted duplicate points")
	var wrong_length := state.duplicate(true); wrong_length["path_length_m"] = 5.0; wrong_length["checksum"] = StateScript.compute_checksum(wrong_length)
	_assert_error(StateScript.validate(wrong_length), "CONSTRUCTION_LOCAL_GEOMETRY_PATH_LENGTH_MISMATCH", "State accepted wrong path length")
	var wrong_bounds := state.duplicate(true); wrong_bounds["bounding_box_m"] = [5.0, 0.0, 0.0]; wrong_bounds["checksum"] = StateScript.compute_checksum(wrong_bounds)
	_assert_error(StateScript.validate(wrong_bounds), "CONSTRUCTION_LOCAL_GEOMETRY_BOUNDING_BOX_MISMATCH", "State accepted wrong bounds")
	var bootstrap := StateScript.bootstrap(Fixture.beam_instance("bootstrap", 7.0))
	_assert_ok(StateScript.validate(bootstrap), "Bootstrap state rejected")
	_assert_close(float(bootstrap["path_length_m"]), 7.0, "Bootstrap lost member length")
	_assert(String(bootstrap["source_member_checksum"]).length() == 64, "Bootstrap source checksum missing")

func _test_constraint_contracts() -> void:
	var constraints := [Fixture.grid(), Fixture.min_segment(), Fixture.max_length(), Fixture.orthogonal(), Fixture.lock_width(), Fixture.lock_start(), Fixture.lock_end_yz()]
	_assert(constraints.size() == 7, "Constraint fixture count mismatch")
	for constraint in constraints:
		_assert_ok(ConstraintScript.validate(constraint), "Valid constraint rejected")
		_assert(String(constraint["checksum"]).length() == 64, "Constraint checksum missing")
		_assert(ConstraintScript.KINDS.has(String(constraint["constraint_kind"])), "Constraint kind not registered")
	var bad_grid := Fixture.grid(); bad_grid["parameters"]["step_m"] = 0.0; bad_grid["checksum"] = ConstraintScript.compute_checksum(bad_grid)
	_assert_error(ConstraintScript.validate(bad_grid), "INVALID_CONSTRUCTION_GEOMETRY_GRID_STEP", "Grid accepted zero step")
	var bad_target := Fixture.lock_width(); bad_target["target"] = "width_m"; bad_target["checksum"] = ConstraintScript.compute_checksum(bad_target)
	_assert_error(ConstraintScript.validate(bad_target), "INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_TARGET", "Parameter lock accepted bad target")
	var bad_axes := Fixture.lock_end_yz(); bad_axes["parameters"]["axes"] = ["Z", "Y"]; bad_axes["checksum"] = ConstraintScript.compute_checksum(bad_axes)
	_assert_error(ConstraintScript.validate(bad_axes), "NON_CANONICAL_CONSTRUCTION_GEOMETRY_LOCK_AXES", "Axis lock accepted unsorted axes")
	var duplicate_axes := Fixture.lock_end_yz(); duplicate_axes["parameters"]["axes"] = ["Y", "Y"]; duplicate_axes["checksum"] = ConstraintScript.compute_checksum(duplicate_axes)
	_assert_error(ConstraintScript.validate(duplicate_axes), "INVALID_CONSTRUCTION_GEOMETRY_LOCK_AXES", "Axis lock accepted duplicate axis")
	var unexpected := Fixture.grid(); unexpected["unexpected_field"] = true
	_assert_error(ConstraintScript.validate(unexpected), "UNEXPECTED_FIELD", "Constraint accepted unexpected field")
	var tampered := Fixture.max_length(); tampered["parameters"]["maximum_m"] = 100.0
	_assert_error(ConstraintScript.validate(tampered), "CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT_CHECKSUM_MISMATCH", "Constraint accepted tamper")

func _test_operation_and_request_contracts() -> void:
	var operations := [
		Fixture.move_end(0, [6.0, 0.0, 0.0]),
		Fixture.set_parameter(1, "width_m", 0.2),
		Fixture.insert_mid(2, "geometry-point/mid", "geometry-point/start", [3.0, 0.0, 0.0]),
		Fixture.remove_point(3, "geometry-point/mid"),
	]
	for operation in operations:
		_assert_ok(OperationScript.validate(operation), "Valid operation rejected")
		_assert(String(operation["checksum"]).length() == 64, "Operation checksum missing")
	var bad_move: Dictionary = Dictionary(operations[0]).duplicate(true); bad_move["payload"]["position_m"] = [1.0, 2.0]; bad_move["checksum"] = OperationScript.compute_checksum(bad_move)
	_assert_error(OperationScript.validate(bad_move), "INVALID_CONSTRUCTION_GEOMETRY_EDIT_POINT_POSITION", "Move accepted invalid point")
	var bad_remove: Dictionary = Dictionary(operations[3]).duplicate(true); bad_remove["payload"]["extra"] = true; bad_remove["checksum"] = OperationScript.compute_checksum(bad_remove)
	_assert_error(OperationScript.validate(bad_remove), "UNEXPECTED_FIELD", "Remove accepted payload")
	var graph := Fixture.graph("request")
	var request := Fixture.request("request", graph, operations, [Fixture.grid(), Fixture.min_segment()])
	_assert_ok(RequestScript.validate(request), "Valid edit request rejected")
	_assert(request["operations"].size() == 4, "Request operations missing")
	_assert(request["operations"][0]["sequence"] == 0 and request["operations"][3]["sequence"] == 3, "Request operation order changed")
	_assert(request["constraints"][0]["constraint_id"] < request["constraints"][1]["constraint_id"], "Request constraints not canonical")
	var sequence_gap := request.duplicate(true); sequence_gap["operations"][2]["sequence"] = 3; sequence_gap["operations"][2]["checksum"] = OperationScript.compute_checksum(sequence_gap["operations"][2]); sequence_gap["operations"][3]["sequence"] = 4; sequence_gap["operations"][3]["checksum"] = OperationScript.compute_checksum(sequence_gap["operations"][3]); sequence_gap["checksum"] = RequestScript.compute_checksum(sequence_gap)
	_assert_error(RequestScript.validate(sequence_gap), "NON_CONTIGUOUS_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_SEQUENCE", "Request accepted sequence gap")
	var stale_checksum := request.duplicate(true); stale_checksum["expected_member_checksum"] = "b".repeat(64)
	_assert_error(RequestScript.validate(stale_checksum), "CONSTRUCTION_GEOMETRY_EDIT_REQUEST_CHECKSUM_MISMATCH", "Request accepted raw tamper")
	var canonical_request := Fixture.request("request-canonical", Fixture.graph("request-canonical"), [Fixture.move_end(0, [6, 0, 0])])
	var float_request := Fixture.request("request-canonical", Fixture.graph("request-canonical"), [Fixture.move_end(0, [6.0, 0.0, 0.0])])
	_assert(UtilsScript.canonical_json(canonical_request["operations"]) == UtilsScript.canonical_json(float_request["operations"]), "Operation int/float canonicalization mismatch")

func _test_edit_compiler_contracts() -> void:
	var catalog = Fixture.catalog()
	var graph := Fixture.graph("compiler")
	var request := Fixture.request("compiler", graph, [Fixture.move_end(0, [6.0, 0.0, 0.0]), Fixture.set_parameter(1, "width_m", 0.2)], [Fixture.grid(0.5), Fixture.min_segment(0.25), Fixture.max_length(10.0), Fixture.lock_end_yz()])
	var definition: Dictionary = catalog.get_definition(String(graph["instance"]["member_definition_id"]), int(graph["instance"]["definition_version"]))
	var compiled := CompilerScript.compile(graph["instance"], definition, catalog.get_materials_for_definition(definition), request)
	_assert_ok(compiled, "Beam geometry edit compile failed")
	var updated: Dictionary = compiled["updated_instance"]
	_assert_close(float(updated["parameter_values"]["length_m"]), 6.0, "Moved endpoint did not update length")
	_assert_close(float(updated["parameter_values"]["width_m"]), 0.2, "Profile edit did not update width")
	_assert_close(float(updated["mass_kg"]), 1884.0, "Edited beam mass mismatch")
	_assert_close(float(updated["geometry"]["volume_m3"]), 0.24, "Edited beam volume mismatch")
	_assert(int(compiled["after_state"]["edit_revision"]) == 1, "Edit revision did not advance")
	_assert(String(compiled["after_state"]["last_edit_id"]) == String(request["edit_id"]), "Edit state lost edit ID")
	_assert(String(updated["provenance"]["local_geometry_edit_state"]["checksum"]) == String(compiled["after_state"]["checksum"]), "Updated member lost geometry state")
	_assert_close(float(compiled["material_deltas"][0]["delta_mass_kg"]), 1256.0, "Material delta mismatch")
	var grid_request := Fixture.request("grid", Fixture.graph("grid"), [Fixture.move_end(0, [5.74, 0.21, 0.0])], [Fixture.grid(0.5)])
	var grid_graph := Fixture.graph("grid")
	definition = catalog.get_definition(String(grid_graph["instance"]["member_definition_id"]), 1)
	var snapped := CompilerScript.compile(grid_graph["instance"], definition, catalog.get_materials_for_definition(definition), grid_request)
	_assert_ok(snapped, "Grid edit failed")
	_assert(UtilsScript.canonical_json(snapped["after_state"]["control_points"][1]["position_m"]) == UtilsScript.canonical_json([5.5, 0, 0]), "Grid snap mismatch")
	_assert_close(float(snapped["updated_instance"]["parameter_values"]["length_m"]), 5.5, "Grid path length mismatch")
	var locked_parameter := Fixture.request("locked-param", Fixture.graph("locked-param"), [Fixture.set_parameter(0, "width_m", 0.2)], [Fixture.lock_width()])
	var locked_graph := Fixture.graph("locked-param"); definition = catalog.get_definition(String(locked_graph["instance"]["member_definition_id"]), 1)
	_assert_error(CompilerScript.compile(locked_graph["instance"], definition, catalog.get_materials_for_definition(definition), locked_parameter), "CONSTRUCTION_GEOMETRY_EDIT_PARAMETER_LOCKED", "Compiler changed locked parameter")
	var locked_axis := Fixture.request("locked-axis", Fixture.graph("locked-axis"), [Fixture.move_end(0, [4.0, 1.0, 0.0])], [Fixture.lock_end_yz()])
	var axis_graph := Fixture.graph("locked-axis"); definition = catalog.get_definition(String(axis_graph["instance"]["member_definition_id"]), 1)
	_assert_error(CompilerScript.compile(axis_graph["instance"], definition, catalog.get_materials_for_definition(definition), locked_axis), "CONSTRUCTION_GEOMETRY_EDIT_LOCKED_AXIS_CHANGED", "Compiler changed locked axis")
	var orthogonal := Fixture.request("orthogonal", Fixture.graph("orthogonal"), [Fixture.move_end(0, [4.0, 1.0, 0.0])], [Fixture.orthogonal()])
	var orth_graph := Fixture.graph("orthogonal"); definition = catalog.get_definition(String(orth_graph["instance"]["member_definition_id"]), 1)
	_assert_error(CompilerScript.compile(orth_graph["instance"], definition, catalog.get_materials_for_definition(definition), orthogonal), "CONSTRUCTION_GEOMETRY_EDIT_ORTHOGONAL_PATH_VIOLATED", "Compiler accepted diagonal orthogonal path")
	var inserted := Fixture.request("insert", Fixture.graph("insert"), [Fixture.insert_mid(0, "geometry-point/corner", "geometry-point/start", [2.0, 0.0, 0.0]), Fixture.move_end(1, [2.0, 3.0, 0.0])], [Fixture.orthogonal(), Fixture.min_segment(0.5)])
	var insert_graph := Fixture.graph("insert"); definition = catalog.get_definition(String(insert_graph["instance"]["member_definition_id"]), 1)
	var insert_result := CompilerScript.compile(insert_graph["instance"], definition, catalog.get_materials_for_definition(definition), inserted)
	_assert_ok(insert_result, "Orthogonal insert edit failed")
	_assert(insert_result["after_state"]["control_points"].size() == 3, "Inserted point missing")
	_assert_close(float(insert_result["after_state"]["path_length_m"]), 5.0, "Inserted path length mismatch")
	var removed_request_graph := {"instance": insert_result["updated_instance"], "projection": Fixture.graph("insert")["projection"], "snapshot": Fixture.graph("insert")["snapshot"], "part_id": Fixture.graph("insert")["part_id"]}
	var remove_request := RequestScript.create("geometry-edit/insert/2", "operation/geometry-edit/insert/2", String(insert_result["updated_instance"]["member_instance_id"]), String(insert_result["updated_instance"]["item_instance_id"]), String(inserted["construct_id"]), String(inserted["part_id"]), String(insert_result["updated_instance"]["checksum"]), 1, String(inserted["expected_construct_checksum"]), 1, [Fixture.remove_point(0, "geometry-point/corner")], [Fixture.min_segment(0.5)], {})
	_assert_ok(RequestScript.validate(remove_request), "Remove request contract rejected")
	var remove_result := CompilerScript.compile(insert_result["updated_instance"], definition, catalog.get_materials_for_definition(definition), remove_request)
	_assert_ok(remove_result, "Interior point removal failed")
	_assert(remove_result["after_state"]["control_points"].size() == 2, "Removed point remained")
	_assert_close(float(remove_result["after_state"]["path_length_m"]), sqrt(13.0), "Removed path length mismatch")

func _test_transaction_and_history_contracts() -> void:
	var catalog = Fixture.catalog(); var graph := Fixture.graph("transaction")
	var request := Fixture.request("transaction", graph, [Fixture.move_end(0, [5.0, 0.0, 0.0])], [Fixture.min_segment()])
	var definition: Dictionary = catalog.get_definition(String(graph["instance"]["member_definition_id"]), 1)
	var compiled := CompilerScript.compile(graph["instance"], definition, catalog.get_materials_for_definition(definition), request)
	_assert_ok(compiled, "Transaction compiler failed")
	var planned := PlannerScript.plan("plan/geometry-edit/transaction/1", request, graph["projection"], graph["snapshot"], compiled)
	_assert_ok(planned, "Geometry edit transaction planning failed")
	_assert_ok(TransactionScript.validate(planned["plan"]), "Geometry edit transaction rejected")
	_assert(String(planned["plan"]["command_type"]) == TransactionScript.COMMAND_EDIT_PARAMETRIC_MEMBER, "Wrong geometry transaction command")
	_assert(planned["plan"]["item_mutations"].size() == 1, "Geometry edit item mutation count mismatch")
	_assert(String(planned["plan"]["item_mutations"][0]["purpose"]) == ItemMutationScript.PURPOSE_EDIT_PARAMETRIC_MEMBER, "Wrong geometry mutation purpose")
	_assert(int(planned["after_projection"]["revision"]) == 1, "Projection revision did not advance")
	_assert(int(planned["after_snapshot"]["state_revision"]) == 1, "Construct revision did not advance")
	_assert_close(float(planned["after_snapshot"]["parts"][0]["mass_kg"]), float(compiled["updated_instance"]["mass_kg"]), "Part mass not updated")
	_assert(String(planned["after_snapshot"]["parts"][0]["metadata"]["parametric_member_checksum"]) == String(compiled["updated_instance"]["checksum"]), "Part provenance not updated")
	_assert_ok(RecordScript.validate(planned["record"]), "Edit record rejected")
	_assert(String(planned["record"]["request_checksum"]) == String(request["checksum"]), "Edit record lost request checksum")
	_assert(int(planned["record"]["after_construct_revision"]) == 1, "Edit record lost construct revision")
	var illegal_mutation: Dictionary = Dictionary(planned["plan"]["item_mutations"][0]).duplicate(true); illegal_mutation["after_projection"]["relation"] = {"kind": "WORLD"}
	_assert_error(ItemMutationScript.validate(illegal_mutation), "PARAMETRIC_EDIT_CHANGED_IDENTITY_OR_LOCATION", "Parametric edit moved item")
	var history = HistoryScript.new()
	_assert_ok(history.publish(planned["record"]), "History publish failed")
	_assert(history.get_generation() == 1, "History generation mismatch")
	var replay := history.publish(planned["record"])
	_assert_ok(replay, "History exact replay failed")
	_assert(bool(replay["replay"]), "History replay not marked")
	_assert(history.get_generation() == 1, "History replay changed generation")
	var conflict: Dictionary = Dictionary(planned["record"]).duplicate(true); conflict["metadata"]["different"] = true; conflict["checksum"] = RecordScript.compute_checksum(conflict)
	_assert_error(history.publish(conflict), "CONSTRUCTION_GEOMETRY_EDIT_HISTORY_CONFLICT", "History accepted conflict")
	var state := history.export_state()
	_assert_ok(HistoryScript.validate_state(state), "History state rejected")
	var storage = MemoryStore.new(); _assert_ok(PersistenceScript.save(storage, history), "History save failed")
	var restored = HistoryScript.new(); _assert_ok(PersistenceScript.load(storage, restored), "History load failed")
	_assert(restored.get_generation() == 1, "Restored history generation mismatch")
	_assert(UtilsScript.canonical_json(restored.get_record(String(request["operation_id"]))) == UtilsScript.canonical_json(planned["record"]), "Restored history record changed")
	var tampered := state.duplicate(true); tampered["records"][0]["mass_delta_kg"] = 999.0
	storage.states[PersistenceScript.STORAGE_KEY] = tampered
	var untouched_generation := restored.get_generation()
	_assert(not bool(PersistenceScript.load(storage, restored).get("success", false)), "Persistence accepted tamper")
	_assert(restored.get_generation() == untouched_generation, "Failed persistence load mutated history")

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
		print("C11 local geometry editing contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C11 local geometry editing contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
