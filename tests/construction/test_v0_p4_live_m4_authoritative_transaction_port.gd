extends SceneTree

const P4ItemGraphScript = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p4.gd")
const AllocatorScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_construction_material_allocator.gd")
const LivePortScript = preload("res://scripts/runtime/networked_gameplay/m4/v0_p4_live_m4_construction_transaction_port.gd")
const AdapterScript = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const BridgeScript = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const FactoryScript = preload("res://scripts/items/services/item_domain_factory.gd")
const DefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemScript = preload("res://scripts/items/domain/item_instance.gd")
const ContainerScript = preload("res://scripts/containers/container_state.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const StagePlannerScript = preload("res://scripts/construction/build/construction_stage_transaction_planner.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const CONSTRUCT_ID := "construct/table/p4-auth"
const ROOT_ID := "item/00000000-0000-4000-8000-0000000000ff"
const TOP_ID := "item/00000000-0000-4000-8000-000000000001"
const LEG_A_ID := "item/00000000-0000-4000-8000-000000000002"
const LEG_B_ID := "item/00000000-0000-4000-8000-000000000003"
const LEG_C_ID := "item/00000000-0000-4000-8000-000000000004"
const LEG_D_ID := "item/00000000-0000-4000-8000-000000000005"
const PART_IDS: Array[String] = [TOP_ID, LEG_A_ID, LEG_B_ID, LEG_C_ID, LEG_D_ID]

var assertions := 0
var failures: Array[String] = []
var _sequence := 0


func _init() -> void:
	_test_authoritative_m0_success_and_replay()
	_test_authoritative_before_commit_rolls_back_both_domains()
	_test_unsafe_post_m0_failure_mode_is_rejected_before_mutation()
	_finish()


func _test_authoritative_m0_success_and_replay() -> void:
	var env: Dictionary = _environment("success")
	_assert_ok(env, "Authoritative environment setup failed")
	if not bool(env.get("success", false)):
		return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var bridge = env["bridge"]
	var port = env["port"]
	_assert(port.is_bound_to_item_graph(item_graph), "Authoritative P4 port must retain exact M4 object identity")
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 3)
	_assert_ok(allocation, "Authoritative P4 allocation failed")
	var planned: Dictionary = _planned_stage(port, allocation, "operation/v0-p4/live/auth-success")
	_assert_ok(planned, "Authoritative P4 stage planning failed")
	if not bool(allocation.get("success", false)) or not bool(planned.get("success", false)):
		return
	var before_m0: Dictionary = bridge.get_state_report()
	_assert_ok(before_m0, "M0 state report missing before P4 transaction")
	var result: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "alpha")
	_assert_ok(result, "Authoritative live-M4 P4 transaction failed")
	if not bool(result.get("success", false)):
		return
	var after_m0: Dictionary = bridge.get_state_report()
	_assert_ok(after_m0, "M0 state report missing after P4 transaction")
	_assert(
		int(after_m0["details"]["generation"]) == int(before_m0["details"]["generation"]) + 1,
		"Accepted P4 Construction transaction must commit exactly one M0 generation"
	)
	_assert(not adapter.get_construct_snapshot(CONSTRUCT_ID).is_empty(), "Authoritative Construction store missing accepted construct")
	var selected: Array = allocation["details"]["allocations"]
	_assert(selected.size() == 2, "Authoritative 3-ore transaction must use two M4 stacks")
	for row_value in selected:
		var row: Dictionary = row_value
		_assert(
			adapter.get_item_projection(String(row["item_id"])).is_empty(),
			"Canonical M4 ore must never be copied into authoritative Construction ItemRegistry"
		)
	var after_item: Dictionary = item_graph.create_snapshot()
	_assert(_snapshot_item(after_item, String(selected[0]["item_id"])).is_empty(), "Exact exhausted canonical M4 stack must be deleted")
	_assert(
		int(_snapshot_item(after_item, String(selected[1]["item_id"])).get("quantity", -1)) == 2,
		"Partially consumed canonical M4 stack must retain quantity 2"
	)
	var before_replay_m0: Dictionary = bridge.get_state_report()
	var before_replay_item: String = UtilsScript.canonical_json(item_graph.create_snapshot())
	var before_replay_construction: String = UtilsScript.canonical_json(adapter.export_state())
	var replay: Dictionary = port.apply_live_plan(planned["transaction_plan"], allocation, "alpha")
	_assert_ok(replay, "Exact accepted P4 replay failed")
	if bool(replay.get("success", false)):
		_assert(bool(replay["details"].get("replay", false)), "Exact accepted P4 replay must report replay=true")
	_assert(UtilsScript.canonical_json(item_graph.create_snapshot()) == before_replay_item, "Exact replay mutated canonical M4")
	_assert(UtilsScript.canonical_json(adapter.export_state()) == before_replay_construction, "Exact replay mutated authoritative Construction state")
	var after_replay_m0: Dictionary = bridge.get_state_report()
	_assert(
		int(after_replay_m0["details"]["generation"]) == int(before_replay_m0["details"]["generation"]),
		"Exact replay must not advance M0 generation"
	)


func _test_authoritative_before_commit_rolls_back_both_domains() -> void:
	var env: Dictionary = _environment("rollback")
	_assert_ok(env, "Rollback environment setup failed")
	if not bool(env.get("success", false)):
		return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var bridge = env["bridge"]
	var port = env["port"]
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 2)
	var planned: Dictionary = _planned_stage(port, allocation, "operation/v0-p4/live/auth-rollback")
	_assert_ok(allocation, "Rollback allocation failed")
	_assert_ok(planned, "Rollback stage planning failed")
	if not bool(allocation.get("success", false)) or not bool(planned.get("success", false)):
		return
	var before_item: String = UtilsScript.canonical_json(item_graph.create_snapshot())
	var before_replay: String = UtilsScript.canonical_json(item_graph.export_replay_state())
	var before_construction: String = UtilsScript.canonical_json(adapter.export_state())
	var before_m0: Dictionary = bridge.get_state_report()
	var failed: Dictionary = port.apply_live_plan(
		planned["transaction_plan"],
		allocation,
		"alpha",
		{"construction_failure_mode": AdapterScript.FAILURE_BEFORE_COMMIT}
	)
	_assert(not bool(failed.get("success", false)), "Injected authoritative BEFORE_COMMIT must reject")
	_assert(
		String(failed.get("error_code", "")) == "INJECTED_AUTHORITATIVE_CONSTRUCTION_COMMIT_FAILURE",
		"Authoritative BEFORE_COMMIT failure code mismatch"
	)
	_assert(bool(failed.get("details", {}).get("rolled_back", false)), "Authoritative BEFORE_COMMIT must report rolled_back=true")
	_assert(UtilsScript.canonical_json(item_graph.create_snapshot()) == before_item, "Authoritative BEFORE_COMMIT must restore canonical M4")
	_assert(UtilsScript.canonical_json(item_graph.export_replay_state()) == before_replay, "Authoritative BEFORE_COMMIT must restore canonical M4 replay ledger")
	_assert(UtilsScript.canonical_json(adapter.export_state()) == before_construction, "Authoritative BEFORE_COMMIT must restore Construction state")
	var after_m0: Dictionary = bridge.get_state_report()
	_assert(
		int(after_m0["details"]["generation"]) == int(before_m0["details"]["generation"]),
		"Authoritative BEFORE_COMMIT must not advance M0 generation"
	)


func _test_unsafe_post_m0_failure_mode_is_rejected_before_mutation() -> void:
	var env: Dictionary = _environment("unsafe-fault")
	_assert_ok(env, "Unsafe-fault environment setup failed")
	if not bool(env.get("success", false)):
		return
	var item_graph = env["item_graph"]
	var adapter = env["adapter"]
	var bridge = env["bridge"]
	var port = env["port"]
	var allocation: Dictionary = AllocatorScript.allocate_r1(item_graph, "alpha", 1)
	var planned: Dictionary = _planned_stage(port, allocation, "operation/v0-p4/live/auth-unsafe")
	_assert_ok(allocation, "Unsafe-fault allocation failed")
	_assert_ok(planned, "Unsafe-fault stage planning failed")
	if not bool(allocation.get("success", false)) or not bool(planned.get("success", false)):
		return
	var before_item: String = UtilsScript.canonical_json(item_graph.create_snapshot())
	var before_construction: String = UtilsScript.canonical_json(adapter.export_state())
	var before_m0: Dictionary = bridge.get_state_report()
	var failed: Dictionary = port.apply_live_plan(
		planned["transaction_plan"],
		allocation,
		"alpha",
		{"construction_failure_mode": AdapterScript.FAILURE_AFTER_M0}
	)
	_assert(not bool(failed.get("success", false)), "Unsafe post-M0 fault mode must be rejected")
	_assert(String(failed.get("error_code", "")) == "P4_UNSAFE_CONSTRUCTION_FAILURE_MODE", "Unsafe fault-mode rejection code mismatch")
	_assert(UtilsScript.canonical_json(item_graph.create_snapshot()) == before_item, "Unsafe fault-mode probe mutated M4")
	_assert(UtilsScript.canonical_json(adapter.export_state()) == before_construction, "Unsafe fault-mode probe mutated Construction")
	var after_m0: Dictionary = bridge.get_state_report()
	_assert(
		int(after_m0["details"]["generation"]) == int(before_m0["details"]["generation"]),
		"Unsafe fault-mode probe must not advance M0 generation"
	)


func _environment(suffix: String) -> Dictionary:
	_sequence += 1
	var item_graph = P4ItemGraphScript.new()
	var result: Dictionary = item_graph.setup("authority/v0-p4-auth/%s" % suffix, 1, {"playable_sandbox": false})
	if not bool(result.get("success", false)):
		return result
	result = item_graph.ensure_player_for_join("alpha")
	if not bool(result.get("success", false)):
		return result
	for row in [["a", 2], ["b", 3]]:
		result = item_graph.apply_server_output(
			"operation/v0-p4/auth/%s/%s" % [suffix, row[0]],
			"alpha",
			"item/ore",
			int(row[1]),
			"test/auth/%s/%s" % [suffix, row[0]]
		)
		if not bool(result.get("success", false)):
			return result

	var domain: Dictionary = FactoryScript.create()
	for definition in [
		{"id": "construct_root", "display_name": "Construct root", "max_stack": 1, "unit_mass_kg": 0.1, "external_volume_l": 0.1, "tags": ["construction"]},
		{"id": "wood_panel", "display_name": "Wood panel", "max_stack": 1, "unit_mass_kg": 12.0, "external_volume_l": 40.0, "tags": ["construction_part"]},
		{"id": "wood_beam", "display_name": "Wood beam", "max_stack": 1, "unit_mass_kg": 2.0, "external_volume_l": 8.0, "tags": ["construction_part"]},
	]:
		domain.items.register_definition(DefinitionScript.new(definition))
	var backpack = ContainerScript.new({
		"container_id": "container/backpack",
		"owner_kind": "ACTOR",
		"owner_id": "player",
		"storage_mode": ContainerScript.STORAGE_SLOTS,
		"slot_count": 8,
		"maximum_mass_kg": 1000.0,
		"maximum_volume_l": 1000.0,
	})
	if not domain.containers.add_container(backpack):
		return {"success": false, "error_code": "P4_AUTH_BACKPACK_SETUP_FAILED"}
	for row in [
		[TOP_ID, "wood_panel", "Top", 0],
		[LEG_A_ID, "wood_beam", "Leg A", 1],
		[LEG_B_ID, "wood_beam", "Leg B", 2],
		[LEG_C_ID, "wood_beam", "Leg C", 3],
		[LEG_D_ID, "wood_beam", "Leg D", 4],
	]:
		var item = ItemScript.new({
			"instance_id": row[0],
			"definition_id": row[1],
			"display_name": row[2],
			"quantity": 1,
			"relation": RelationsScript.container("container/backpack", int(row[3])),
			"components": {},
			"revision": 0,
		})
		if not domain.items.add_item(item):
			return {"success": false, "error_code": "P4_AUTH_ITEM_SETUP_FAILED", "item_id": row[0]}
		backpack.item_ids.append(row[0])
		backpack.slot_assignments[int(row[3])] = row[0]
	result = domain.validator.validate_graph()
	if not bool(result.get("success", false)):
		return result

	var constructs = ConstructStoreScript.new()
	var bridge = BridgeScript.new()
	result = bridge.setup("user://p4-auth-%s-%d-%d" % [suffix, Time.get_ticks_usec(), _sequence])
	if not bool(result.get("success", false)):
		return result
	var adapter = AdapterScript.new()
	result = adapter.setup(
		domain.items,
		domain.containers,
		domain.validator,
		domain.mass,
		domain.operations,
		constructs,
		bridge,
		"authority/v0-p4-auth-construction/%s" % suffix,
		1,
		0,
		0,
		0,
		{}
	)
	if not bool(result.get("success", false)):
		return result
	var port = LivePortScript.new()
	result = port.setup(item_graph, adapter)
	if not bool(result.get("success", false)):
		return result
	return {"success": true, "error_code": "", "item_graph": item_graph, "adapter": adapter, "bridge": bridge, "port": port}


func _planned_stage(port, allocation: Dictionary, operation_id: String) -> Dictionary:
	if not bool(allocation.get("success", false)):
		return allocation
	var sources: Array = []
	for item_id in PART_IDS:
		var projection: Dictionary = port.get_item_projection(item_id)
		if projection.is_empty():
			return {"success": false, "error_code": "P4_AUTH_STRUCTURAL_PROJECTION_MISSING", "item_id": item_id}
		sources.append(projection)
	var materials: Array = []
	for row_value in allocation["details"]["allocations"]:
		var row: Dictionary = row_value
		var projected: Dictionary = port.get_item_projection(String(row["item_id"]))
		if projected.is_empty():
			return {"success": false, "error_code": "P4_AUTH_M4_PROJECTION_MISSING"}
		sources.append(projected)
		materials.append({
			"item_instance_id": String(row["item_id"]),
			"definition_id": LivePortScript.R1_CONSTRUCTION_DEFINITION_ID,
			"quantity": int(row["quantity"]),
		})
	var stages: Array = [
		StageScript.create(
			"stage/v0-p4/auth/foundation", 0, "Authoritative foundation", StageScript.SEMANTIC_FOUNDATION,
			["part/table/top", "part/table/leg-a", "part/table/leg-b"],
			["bond/table/leg-a", "bond/table/leg-b"], materials, ["FASTEN"]
		),
		StageScript.create(
			"stage/v0-p4/auth/frame", 1, "Authoritative frame", StageScript.SEMANTIC_FRAME,
			["part/table/top", "part/table/leg-a", "part/table/leg-b", "part/table/leg-c"],
			["bond/table/leg-a", "bond/table/leg-b", "bond/table/leg-c"], [], ["FASTEN"]
		),
		StageScript.create(
			"stage/v0-p4/auth/operational", 2, "Authoritative operational", StageScript.SEMANTIC_OPERATIONAL,
			["part/table/top", "part/table/leg-a", "part/table/leg-b", "part/table/leg-c", "part/table/leg-d"],
			["bond/table/leg-a", "bond/table/leg-b", "bond/table/leg-c", "bond/table/leg-d"], [], ["INSPECT"]
		),
	]
	var build_plan := BuildPlanScript.create(
		"build-plan/v0-p4/auth",
		"V0 P4 authoritative live M4",
		ProjectionScript.world_relation(),
		_target_snapshot(),
		sources,
		stages
	)
	var validation: Dictionary = BuildPlanScript.validate(build_plan)
	if not bool(validation.get("success", false)):
		return validation
	return StagePlannerScript.build_stage_transaction_plan(build_plan, 0, operation_id)


func _target_snapshot() -> Dictionary:
	var aggregate = AggregateScript.new()
	var setup: Dictionary = aggregate.setup(CONSTRUCT_ID, ROOT_ID)
	if not bool(setup.get("success", false)):
		return {}
	var revision := 0
	for part in [
		PartScript.create("part/table/top", TOP_ID, "PANEL", "surface", 12.0, [0.0, 0.75, 0.0]),
		PartScript.create("part/table/leg-a", LEG_A_ID, "BEAM", "support", 2.0, [-0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-b", LEG_B_ID, "BEAM", "support", 2.0, [0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-c", LEG_C_ID, "BEAM", "support", 2.0, [0.5, 0.375, 0.3]),
		PartScript.create("part/table/leg-d", LEG_D_ID, "BEAM", "support", 2.0, [-0.5, 0.375, 0.3]),
	]:
		aggregate.add_part("operation/p4/auth/part/%d" % revision, revision, part)
		revision += 1
	for bond in [
		BondScript.create("bond/table/leg-a", "part/table/top", "part/table/leg-a", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-b", "part/table/top", "part/table/leg-b", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-c", "part/table/top", "part/table/leg-c", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-d", "part/table/top", "part/table/leg-d", "BOLT", 2500.0),
	]:
		aggregate.add_bond("operation/p4/auth/bond/%d" % revision, revision, bond)
		revision += 1
	aggregate.set_build_state("operation/p4/auth/operational", revision, "OPERATIONAL")
	return aggregate.export_snapshot()


func _snapshot_item(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P4 authoritative live M4 transaction port: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"V0-P4 authoritative live M4 transaction port: FAIL (%d failures, %d assertions)"
		% [failures.size(), assertions]
	)
	quit(1)
