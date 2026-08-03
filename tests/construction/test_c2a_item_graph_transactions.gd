extends SceneTree

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const PlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")

var failures: Array[String] = []
var assertions: int = 0

func _init() -> void:
	_test_atomic_table_assembly_and_deconstruction()
	_finish()

func _test_atomic_table_assembly_and_deconstruction() -> void:
	var source_items: Array = _source_items()
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(source_items), "C2A adapter setup failed")
	var table_snapshot: Dictionary = _table_snapshot()
	var root: Dictionary = PlannerScript.create_root_projection(
		"item/construct/table-demo",
		"construct/table/demo",
		"Composite table"
	)
	var assembly_result: Dictionary = PlannerScript.build_assembly_plan(
		"plan/table/assemble",
		"operation/table/assemble",
		table_snapshot,
		root,
		source_items,
		{"item/material/fasteners": 4}
	)
	_assert_ok(assembly_result, "Table assembly plan creation failed")
	var assembly_plan: Dictionary = assembly_result.get("plan", {})
	var applied: Dictionary = adapter.apply_plan(assembly_plan)
	_assert_ok(applied, "Table assembly transaction failed")
	_assert(String(applied.get("status", "")) == AdapterScript.STATUS_SUCCEEDED, "Assembly did not report SUCCEEDED")
	_assert(adapter.get_generation() == 1, "Assembly did not advance adapter generation once")
	_assert(not adapter.get_construct_snapshot("construct/table/demo").is_empty(), "Assembly did not create construct snapshot")
	_assert(not adapter.get_item_projection("item/construct/table-demo").is_empty(), "Assembly did not create construct root item")
	var compiled: Dictionary = adapter.get_construct_snapshot("construct/table/demo").get("compiled_facets", {})
	_assert(compiled.get("capabilities", []) == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Assembled table lost C1 capabilities")
	for part in table_snapshot["parts"]:
		var item: Dictionary = adapter.get_item_projection(String(part["item_instance_id"]))
		var relation: Dictionary = item.get("relation", {})
		_assert(String(relation.get("kind", "")) == ProjectionScript.ATTACHMENT, "Part was not attached")
		_assert(String(relation.get("assembly_id", "")) == "construct/table/demo", "Part attachment construct mismatch")
		_assert(String(relation.get("parent_item_id", "")) == "item/construct/table-demo", "Part attachment root mismatch")
		_assert(String(relation.get("socket_id", "")) == String(part["part_id"]), "Part attachment socket mismatch")
		_assert(int(item.get("revision", -1)) == 1, "Attached part revision did not advance exactly once")
	var fasteners: Dictionary = adapter.get_item_projection("item/material/fasteners")
	_assert(int(fasteners.get("quantity", 0)) == 4, "Assembly consumed wrong fastener quantity")
	_assert(int(fasteners.get("revision", -1)) == 1, "Fastener revision did not advance")

	var state_after_assembly: Dictionary = adapter.export_state()
	var replay: Dictionary = adapter.apply_plan(assembly_plan)
	_assert(replay == applied, "Exact assembly replay did not return stored result")
	_assert(adapter.export_state() == state_after_assembly, "Exact assembly replay mutated state")
	var conflicting_plan: Dictionary = assembly_plan.duplicate(true)
	conflicting_plan["plan_id"] = "plan/table/assemble-conflict"
	conflicting_plan["checksum"] = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd").compute_checksum(conflicting_plan)
	var conflict: Dictionary = adapter.apply_plan(conflicting_plan)
	_assert_error(conflict, "CONSTRUCTION_OPERATION_ID_CONFLICT", "Same operation ID accepted another plan")
	_assert(adapter.export_state() == state_after_assembly, "Operation conflict mutated state")

	var stale_result: Dictionary = PlannerScript.build_assembly_plan(
		"plan/table/stale",
		"operation/table/stale",
		table_snapshot,
		root,
		source_items,
		{"item/material/fasteners": 4}
	)
	_assert_ok(stale_result, "Stale fixture plan did not build")
	var stale_apply: Dictionary = adapter.apply_plan(stale_result["plan"])
	_assert_error(stale_apply, "CONSTRUCT_PRECONDITION_EXPECTED_ABSENT", "Stale assembly plan was accepted")
	_assert(String(stale_apply.get("status", "")) == AdapterScript.STATUS_REJECTED, "Stale plan was not a terminal rejection")
	_assert(adapter.get_generation() == 1, "Terminal rejection changed state generation")
	_assert(adapter.has_terminal_operation("operation/table/stale"), "Terminal stale rejection was not remembered")
	_assert(adapter.get_construct_snapshot("construct/table/demo") == state_after_assembly["constructs"][0], "Stale plan changed construct state")
	var state_after_stale: Dictionary = adapter.export_state()

	var encoded: String = JSON.stringify(state_after_stale, "", true, true)
	var decoded = JSON.parse_string(encoded)
	_assert(decoded is Dictionary, "C2A adapter state did not survive JSON encoding")
	var restored = AdapterScript.new()
	_assert_ok(restored.load_state(Dictionary(decoded)), "C2A adapter state load failed")
	_assert(restored.export_state() == state_after_stale, "C2A adapter JSON round-trip changed state")
	_assert(restored.apply_plan(assembly_plan) == applied, "Persistent exact replay changed after adapter restart")
	_assert(restored.apply_plan(stale_result["plan"]) == stale_apply, "Persistent terminal rejection replay changed after adapter restart")

	var tampered_state: Dictionary = state_after_stale.duplicate(true)
	tampered_state["generation"] = 9
	var before_invalid_load: Dictionary = restored.export_state()
	_assert_error(restored.load_state(tampered_state), "CONSTRUCTION_ITEM_GRAPH_STATE_CHECKSUM_MISMATCH", "Tampered C2A state checksum accepted")
	_assert(restored.export_state() == before_invalid_load, "Rejected C2A state load mutated adapter")

	var current_table_snapshot: Dictionary = adapter.get_construct_snapshot("construct/table/demo")
	var attached_parts: Array = []
	for part in current_table_snapshot["parts"]:
		attached_parts.append(adapter.get_item_projection(String(part["item_instance_id"])))
	var deconstruction_result: Dictionary = PlannerScript.build_deconstruction_plan(
		"plan/table/deconstruct",
		"operation/table/deconstruct",
		current_table_snapshot,
		adapter.get_item_projection("item/construct/table-demo"),
		attached_parts,
		ProjectionScript.container_relation("container/salvage", -1)
	)
	_assert_ok(deconstruction_result, "Table deconstruction plan creation failed")
	var deconstruction_plan: Dictionary = deconstruction_result.get("plan", {})
	var before_failure: Dictionary = adapter.export_state()
	var retryable: Dictionary = adapter.apply_plan(deconstruction_plan, "BEFORE_COMMIT")
	_assert_error(retryable, "INJECTED_CONSTRUCTION_COMMIT_FAILURE", "Injected pre-commit failure did not fail")
	_assert(String(retryable.get("status", "")) == AdapterScript.STATUS_RETRYABLE, "Injected failure was not retryable")
	_assert(not adapter.has_terminal_operation("operation/table/deconstruct"), "Retryable failure poisoned operation ledger")
	_assert(adapter.export_state() == before_failure, "Injected failure partially committed transaction")

	var deconstructed: Dictionary = adapter.apply_plan(deconstruction_plan)
	_assert_ok(deconstructed, "Retry with same deconstruction operation ID failed")
	_assert(adapter.get_generation() == 2, "Deconstruction did not advance generation once")
	_assert(adapter.get_construct_snapshot("construct/table/demo").is_empty(), "Deconstruction retained construct")
	_assert(adapter.get_item_projection("item/construct/table-demo").is_empty(), "Deconstruction retained construct root item")
	for part in table_snapshot["parts"]:
		var item: Dictionary = adapter.get_item_projection(String(part["item_instance_id"]))
		var relation: Dictionary = item.get("relation", {})
		_assert(String(relation.get("kind", "")) == ProjectionScript.CONTAINER, "Deconstructed part did not return to container relation")
		_assert(String(relation.get("container_id", "")) == "container/salvage", "Deconstructed part returned to wrong container")
		_assert(int(item.get("revision", -1)) == 2, "Detached part revision chain is wrong")
	fasteners = adapter.get_item_projection("item/material/fasteners")
	_assert(int(fasteners.get("quantity", 0)) == 4, "Deconstruction incorrectly refunded consumed fasteners")
	_assert(adapter.apply_plan(deconstruction_plan) == deconstructed, "Exact deconstruction replay changed result")
	_assert(adapter.get_generation() == 2, "Deconstruction replay changed generation")
	_assert(adapter.apply_plan(stale_result["plan"]) == stale_apply, "Terminal stale rejection changed after successful deconstruction")

func _table_snapshot() -> Dictionary:
	var aggregate = AggregateScript.new()
	_assert_ok(aggregate.setup("construct/table/demo", "item/construct/table-demo"), "Table aggregate setup failed")
	var revision: int = 0
	for part in _parts():
		_assert_ok(aggregate.add_part("op/c2a/part/%s" % part["part_id"], revision, part), "Table part add failed")
		revision += 1
	for bond in _bonds():
		_assert_ok(aggregate.add_bond("op/c2a/bond/%s" % bond["bond_id"], revision, bond), "Table bond add failed")
		revision += 1
	_assert_ok(aggregate.set_build_state("op/c2a/operational", revision, "OPERATIONAL"), "Table did not become operational")
	return aggregate.export_snapshot()

func _source_items() -> Array:
	return [
		_item("item/table/top", "wood_panel", "Table top", 1, ProjectionScript.container_relation("container/backpack", 0)),
		_item("item/table/leg-a", "wood_beam", "Table leg A", 1, ProjectionScript.container_relation("container/backpack", 1)),
		_item("item/table/leg-b", "wood_beam", "Table leg B", 1, ProjectionScript.container_relation("container/backpack", 2)),
		_item("item/table/leg-c", "wood_beam", "Table leg C", 1, ProjectionScript.container_relation("container/backpack", 3)),
		_item("item/table/leg-d", "wood_beam", "Table leg D", 1, ProjectionScript.container_relation("container/backpack", 4)),
		_item("item/material/fasteners", "fastener", "Fasteners", 8, ProjectionScript.container_relation("container/tools", 0)),
	]

func _parts() -> Array:
	return [
		PartScript.create("part/table/top", "item/table/top", "PANEL", "surface", 12.0, [0.0, 0.75, 0.0]),
		PartScript.create("part/table/leg-a", "item/table/leg-a", "BEAM", "support", 2.0, [-0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-b", "item/table/leg-b", "BEAM", "support", 2.0, [0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-c", "item/table/leg-c", "BEAM", "support", 2.0, [0.5, 0.375, 0.3]),
		PartScript.create("part/table/leg-d", "item/table/leg-d", "BEAM", "support", 2.0, [-0.5, 0.375, 0.3]),
	]

func _bonds() -> Array:
	return [
		BondScript.create("bond/table/leg-a", "part/table/top", "part/table/leg-a", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-b", "part/table/top", "part/table/leg-b", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-c", "part/table/top", "part/table/leg-c", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-d", "part/table/top", "part/table/leg-d", "BOLT", 2500.0),
	]

func _item(item_id: String, definition_id: String, display_name: String, quantity: int, relation: Dictionary) -> Dictionary:
	return ProjectionScript.create(item_id, definition_id, display_name, quantity, relation, {}, 0)

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])

func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("C2A Item Graph transactions: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C2A Item Graph transactions: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
