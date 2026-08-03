extends SceneTree

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const PlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const PortScript = preload("res://scripts/construction/item_graph/construction_item_graph_transaction_port.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")

var failures: Array[String] = []
var assertions: int = 0

func _init() -> void:
	_test_item_projection_contract()
	_test_item_mutation_contracts()
	_test_construct_mutation_and_plan_contracts()
	_test_adapter_port_contract()
	_test_delivery_contract()
	_finish()

func _test_item_projection_contract() -> void:
	var source_item: Dictionary = {
		"schema": "planet_simulator.item_instance.v2",
		"schema_version": 2,
		"instance_id": "item/table/top",
		"definition_id": "wood_panel",
		"display_name": "Table top",
		"quantity": 1,
		"relation": ProjectionScript.container_relation("container/backpack", 0),
		"components": {"quality": "standard"},
		"revision": 4,
	}
	var projected: Dictionary = ProjectionScript.from_item_instance_dict(source_item)
	_assert_ok(projected, "Canonical item instance did not project into C2A boundary")
	var projection: Dictionary = projected.get("projection", {})
	_assert_ok(ProjectionScript.validate(projection), "Valid construction item projection rejected")
	var restored: Dictionary = ProjectionScript.to_item_instance_dict(projection)
	_assert_ok(restored, "Projection did not convert back to canonical item dictionary")
	_assert(restored.get("item", {}) == source_item, "Projection round-trip changed canonical item fields")
	_assert(ProjectionScript.fingerprint(projection).length() == 64, "Projection fingerprint is not SHA-256")

	var attachment: Dictionary = projection.duplicate(true)
	attachment["relation"] = ProjectionScript.attachment_relation(
		"construct/table/demo",
		"item/construct/table-demo",
		"part/table/top"
	)
	_assert_ok(ProjectionScript.validate(attachment), "Canonical ATTACHMENT relation rejected")
	var invalid_attachment: Dictionary = attachment.duplicate(true)
	invalid_attachment["relation"]["socket_id"] = "socket/top"
	_assert_error(ProjectionScript.validate(invalid_attachment), "INVALID_CONSTRUCTION_ATTACHMENT_SOCKET", "Non-part attachment socket accepted")
	var runtime_value: Dictionary = projection.duplicate(true)
	runtime_value["components"] = {"node": RefCounted.new()}
	_assert_error(ProjectionScript.validate(runtime_value), "CONSTRUCTION_ITEM_COMPONENTS_NOT_JSON_SAFE", "Runtime object accepted in item projection")
	var zero_quantity: Dictionary = projection.duplicate(true)
	zero_quantity["quantity"] = 0
	_assert_error(ProjectionScript.validate(zero_quantity), "INVALID_CONSTRUCTION_ITEM_QUANTITY", "Zero quantity projection accepted")
	var extra_field: Dictionary = projection.duplicate(true)
	extra_field["owner"] = "player/test"
	_assert_error(ProjectionScript.validate(extra_field), "UNEXPECTED_FIELD", "Unexpected projection field accepted")

func _test_item_mutation_contracts() -> void:
	var root: Dictionary = PlannerScript.create_root_projection(
		"item/construct/table-demo",
		"construct/table/demo",
		"Composite table"
	)
	var create_root: Dictionary = ItemMutationScript.create(
		ItemMutationScript.OP_CREATE,
		ItemMutationScript.PURPOSE_CREATE_ROOT,
		"item/construct/table-demo",
		{},
		root
	)
	_assert_ok(ItemMutationScript.validate(create_root), "Valid construct root creation rejected")
	var invalid_root: Dictionary = create_root.duplicate(true)
	invalid_root["after_projection"]["components"] = {}
	_assert_error(ItemMutationScript.validate(invalid_root), "CREATED_ROOT_ITEM_LACKS_CONSTRUCTION_COMPONENT", "Root creation without component accepted")

	var before: Dictionary = _item("item/table/top", "wood_panel", "Table top", 1, ProjectionScript.container_relation("container/backpack", 0), 2)
	var attached: Dictionary = before.duplicate(true)
	attached["relation"] = ProjectionScript.attachment_relation("construct/table/demo", root["item_instance_id"], "part/table/top")
	attached["revision"] = 3
	var attach_mutation: Dictionary = ItemMutationScript.create(
		ItemMutationScript.OP_UPDATE,
		ItemMutationScript.PURPOSE_ATTACH_PART,
		"item/table/top",
		before,
		attached
	)
	_assert_ok(ItemMutationScript.validate(attach_mutation), "Valid attach mutation rejected")
	var wrong_revision: Dictionary = attach_mutation.duplicate(true)
	wrong_revision["after_projection"]["revision"] = 4
	_assert_error(ItemMutationScript.validate(wrong_revision), "ITEM_MUTATION_REVISION_CHAIN_MISMATCH", "Revision jump accepted")
	var changed_definition: Dictionary = attach_mutation.duplicate(true)
	changed_definition["after_projection"]["definition_id"] = "steel_panel"
	_assert_error(ItemMutationScript.validate(changed_definition), "ITEM_MUTATION_IMMUTABLE_IDENTITY_CHANGED", "Attach mutation changed item definition")

	var fasteners_before: Dictionary = _item("item/material/fasteners", "fastener", "Fasteners", 8, ProjectionScript.container_relation("container/tools", 0), 0)
	var fasteners_after: Dictionary = fasteners_before.duplicate(true)
	fasteners_after["quantity"] = 4
	fasteners_after["revision"] = 1
	var consume: Dictionary = ItemMutationScript.create(
		ItemMutationScript.OP_UPDATE,
		ItemMutationScript.PURPOSE_CONSUME_MATERIAL,
		"item/material/fasteners",
		fasteners_before,
		fasteners_after
	)
	_assert_ok(ItemMutationScript.validate(consume), "Valid material consumption rejected")
	var moved_consumable: Dictionary = consume.duplicate(true)
	moved_consumable["after_projection"]["relation"] = ProjectionScript.world_relation()
	_assert_error(ItemMutationScript.validate(moved_consumable), "CONSUME_MATERIAL_CHANGED_LOCATION_OR_COMPONENTS", "Consumption moved material item")

	var delete_root: Dictionary = ItemMutationScript.create(
		ItemMutationScript.OP_DELETE,
		ItemMutationScript.PURPOSE_DESTROY_ROOT,
		String(root["item_instance_id"]),
		root,
		{}
	)
	_assert_ok(ItemMutationScript.validate(delete_root), "Valid construct root deletion rejected")

func _test_construct_mutation_and_plan_contracts() -> void:
	var snapshot: Dictionary = _table_snapshot()
	var construct_create: Dictionary = ConstructMutationScript.create(
		ConstructMutationScript.OP_CREATE,
		String(snapshot["construct_id"]),
		{},
		snapshot
	)
	_assert_ok(ConstructMutationScript.validate(construct_create), "Valid construct create mutation rejected")
	var create_with_before: Dictionary = construct_create.duplicate(true)
	create_with_before["before_snapshot"] = snapshot
	_assert_error(ConstructMutationScript.validate(create_with_before), "CREATE_CONSTRUCT_MUTATION_HAS_BEFORE_STATE", "Construct create accepted before state")

	var root: Dictionary = PlannerScript.create_root_projection("item/construct/table-demo", "construct/table/demo", "Composite table")
	var part_items: Array = _source_items()
	var built: Dictionary = PlannerScript.build_assembly_plan(
		"plan/table/assemble",
		"operation/table/assemble",
		snapshot,
		root,
		part_items,
		{"item/material/fasteners": 4}
	)
	_assert_ok(built, "Assembly planner rejected valid table fixture")
	var plan: Dictionary = built.get("plan", {})
	_assert_ok(PlanScript.validate(plan), "Valid assembly transaction plan rejected")
	_assert(String(plan.get("checksum", "")).length() == 64, "Plan checksum is not SHA-256")
	_assert(plan.get("invariants", []) == PlanScript.REQUIRED_INVARIANTS, "Plan invariant set is not canonical")
	var item_ids: Array = []
	for mutation in plan["item_mutations"]:
		item_ids.append(String(mutation["item_instance_id"]))
	var sorted_item_ids: Array = item_ids.duplicate()
	sorted_item_ids.sort()
	_assert(item_ids == sorted_item_ids, "Plan item mutations are not sorted")
	var changed: Dictionary = plan.duplicate(true)
	changed["command_type"] = PlanScript.COMMAND_DECONSTRUCT
	_assert_error(PlanScript.validate(changed), "CONSTRUCTION_TRANSACTION_PLAN_CHECKSUM_MISMATCH", "Mutated plan accepted stale checksum")
	var duplicate: Dictionary = plan.duplicate(true)
	duplicate["item_mutations"].append(duplicate["item_mutations"][0].duplicate(true))
	duplicate["item_mutations"].sort_custom(func(a, b): return String(a["item_instance_id"]) < String(b["item_instance_id"]))
	duplicate["checksum"] = PlanScript.compute_checksum(duplicate)
	_assert_error(PlanScript.validate(duplicate), "DUPLICATE_CONSTRUCTION_TRANSACTION_ITEM_MUTATION", "Duplicate item mutation accepted")

func _test_adapter_port_contract() -> void:
	_assert_error(PortScript.validate_adapter(null), "CONSTRUCTION_ITEM_GRAPH_ADAPTER_REQUIRED", "Null adapter accepted")
	_assert_error(PortScript.validate_adapter(RefCounted.new()), "CONSTRUCTION_ITEM_GRAPH_ADAPTER_METHOD_MISSING", "Incomplete adapter accepted")
	_assert_ok(PortScript.validate_adapter(AdapterScript.new()), "C2A in-memory adapter rejected by port")

func _test_delivery_contract() -> void:
	var powershell_runner: String = FileAccess.get_file_as_string("res://RUN_C2A_CONSTRUCTION_ITEM_GRAPH_TESTS.ps1")
	var shell_runner: String = FileAccess.get_file_as_string("res://RUN_C2A_CONSTRUCTION_ITEM_GRAPH_TESTS.sh")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	var map_document: String = FileAccess.get_file_as_string("res://docs/plans/CONSTRUCTION_MAP_RU.md")
	var progress_log: String = FileAccess.get_file_as_string("res://docs/plans/CONSTRUCTION_PROGRESS_LOG_RU.md")
	_assert(powershell_runner.contains("test_c2a_item_graph_contracts.gd") and powershell_runner.contains("test_c2a_item_graph_transactions.gd"), "C2A PowerShell runner omits tests")
	_assert(shell_runner.contains("test_c2a_item_graph_contracts.gd") and shell_runner.contains("test_c2a_item_graph_transactions.gd"), "C2A shell runner omits tests")
	_assert(world_runner.contains("test_c2a_item_graph_contracts.gd") and world_runner.contains("test_c2a_item_graph_transactions.gd"), "World regression omits C2A tests")
	_assert(map_document.contains("C2A — Item Graph Contracts") and map_document.contains("C2B — Authoritative Item Graph Integration"), "Construction map does not show C2A/C2B gate")
	_assert(progress_log.contains("C1: Semantic Construction Kernel") and progress_log.contains("C2A: Item Graph Contracts"), "Construction progress log omits accepted foundation or current movement")

func _table_snapshot() -> Dictionary:
	var aggregate = AggregateScript.new()
	_assert_ok(aggregate.setup("construct/table/demo", "item/construct/table-demo"), "Table snapshot aggregate setup failed")
	var revision: int = 0
	for part in _parts():
		_assert_ok(aggregate.add_part("op/c2a/part/%s" % part["part_id"], revision, part), "Table snapshot part add failed")
		revision += 1
	for bond in _bonds():
		_assert_ok(aggregate.add_bond("op/c2a/bond/%s" % bond["bond_id"], revision, bond), "Table snapshot bond add failed")
		revision += 1
	_assert_ok(aggregate.set_build_state("op/c2a/operational", revision, "OPERATIONAL"), "Table snapshot did not become operational")
	return aggregate.export_snapshot()

func _source_items() -> Array:
	return [
		_item("item/table/top", "wood_panel", "Table top", 1, ProjectionScript.container_relation("container/backpack", 0), 0),
		_item("item/table/leg-a", "wood_beam", "Table leg A", 1, ProjectionScript.container_relation("container/backpack", 1), 0),
		_item("item/table/leg-b", "wood_beam", "Table leg B", 1, ProjectionScript.container_relation("container/backpack", 2), 0),
		_item("item/table/leg-c", "wood_beam", "Table leg C", 1, ProjectionScript.container_relation("container/backpack", 3), 0),
		_item("item/table/leg-d", "wood_beam", "Table leg D", 1, ProjectionScript.container_relation("container/backpack", 4), 0),
		_item("item/material/fasteners", "fastener", "Fasteners", 8, ProjectionScript.container_relation("container/tools", 0), 0),
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

func _item(item_id: String, definition_id: String, display_name: String, quantity: int, relation: Dictionary, revision: int) -> Dictionary:
	return ProjectionScript.create(item_id, definition_id, display_name, quantity, relation, {}, revision)

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
		print("C2A Item Graph contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C2A Item Graph contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
