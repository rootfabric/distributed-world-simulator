extends SceneTree

const FixtureScript = preload("res://tests/construction/fixtures/c4_reusable_table_fixture.gd")
const CompilerScript = preload("res://scripts/construction/composites/construction_composite_build_plan_compiler.gd")
const DefinitionScript = preload("res://scripts/construction/composites/construction_composite_definition.gd")
const InstantiationScript = preload("res://scripts/construction/composites/construction_composite_instantiation.gd")
const RegistryScript = preload("res://scripts/construction/composites/construction_composite_registry.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const StoreScript = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const ProcessScript = preload("res://scripts/construction/build/construction_build_process.gd")
const BuilderAgentScript = preload("res://scripts/construction/build/construction_builder_agent.gd")
const GhostScript = preload("res://scripts/construction/build/construction_ghost_state.gd")
const SnapshotBuilderScript = preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_canonical_provenance_equivalence()
	_test_two_instances_from_one_definition()
	_test_partial_provenance_and_stage_execution()
	_test_authoritative_recovery_for_compiled_plan()
	_test_definition_version_pinning()
	_test_catalog_replay_with_multiple_instances()
	_finish()


func _compile(instance_key: String, definition: Dictionary = {}, parameter_values: Dictionary = {}) -> Dictionary:
	var resolved_definition: Dictionary = FixtureScript.definition() if definition.is_empty() else definition
	var ids: Dictionary = FixtureScript.compile_ids(instance_key)
	return CompilerScript.compile(
		resolved_definition,
		ids.instantiation_id,
		ids.build_plan_id,
		ids.construct_id,
		ids.root_item_instance_id,
		ProjectionScript.world_relation(),
		FixtureScript.source_projections(instance_key),
		parameter_values
	)


func _test_canonical_provenance_equivalence() -> void:
	var float_parameters: Dictionary = {
		"parameter/finish": "natural",
		"parameter/load-rating-kg": 100.0,
	}
	var integer_parameters: Dictionary = {
		"parameter/finish": "natural",
		"parameter/load-rating-kg": 100,
	}
	_assert(float_parameters != integer_parameters, "Parameter fixture did not preserve raw int/float distinction")
	_assert(_canonical_equal(float_parameters, integer_parameters), "Canonical parameter comparison rejected int/float equivalence")

	var float_ports: Array = [{
		"port_id": "port/work-surface",
		"part_id": "part/table/top",
		"port_kind": "SUPPORT_SURFACE",
		"local_position_m": [0.0, 1.0, 0.0],
	}]
	var integer_ports: Array = [{
		"port_id": "port/work-surface",
		"part_id": "part/table/top",
		"port_kind": "SUPPORT_SURFACE",
		"local_position_m": [0, 1, 0],
	}]
	_assert(float_ports != integer_ports, "Exposed-port fixture did not preserve raw int/float distinction")
	_assert(_canonical_equal(float_ports, integer_ports), "Canonical exposed-port comparison rejected int/float equivalence")


func _test_two_instances_from_one_definition() -> void:
	var definition: Dictionary = FixtureScript.definition()
	var first: Dictionary = _compile("first", definition)
	var second: Dictionary = _compile("second", definition, {
		"parameter/finish": "painted",
		"parameter/load-rating-kg": 125.0,
	})
	_assert_ok(first, "First reusable table compilation failed")
	_assert_ok(second, "Second reusable table compilation failed")
	_assert(String(first.build_plan.checksum) != String(second.build_plan.checksum), "Distinct instances produced same BuildPlan checksum")
	_assert(String(first.instantiation.definition_checksum) == String(second.instantiation.definition_checksum), "Instances do not pin the same definition")
	_assert(String(first.instantiation.construct_id) != String(second.instantiation.construct_id), "Instances reused construct identity")
	_assert(String(first.instantiation.root_item_instance_id) != String(second.instantiation.root_item_instance_id), "Instances reused root identity")
	_assert(String(first.instantiation.parameter_values["parameter/finish"]) == "natural", "First instance lost default finish")
	_assert(String(second.instantiation.parameter_values["parameter/finish"]) == "painted", "Second instance lost finish override")
	_assert(float(second.instantiation.parameter_values["parameter/load-rating-kg"]) == 125.0, "Second instance lost numeric override")
	_assert(first.build_plan.target_snapshot.compiled_facets.composite_parameters != second.build_plan.target_snapshot.compiled_facets.composite_parameters, "Parameter overrides did not differentiate compiled instances")
	var first_items: Dictionary = {}
	for binding in first.instantiation.part_bindings:
		first_items[String(binding.item_instance_id)] = true
	for binding in second.instantiation.part_bindings:
		_assert(not first_items.has(String(binding.item_instance_id)), "Reusable instances share concrete part item")
	for index in range(first.build_plan.target_snapshot.parts.size()):
		var first_part: Dictionary = first.build_plan.target_snapshot.parts[index]
		var second_part: Dictionary = second.build_plan.target_snapshot.parts[index]
		_assert(String(first_part.part_id) != String(second_part.part_id), "Concrete part IDs were reused")
		_assert(first_part.local_position_m == second_part.local_position_m, "Definition geometry changed between instances")
		_assert(String(first_part.part_kind) == String(second_part.part_kind), "Definition part kind changed between instances")
		_assert(String(first_part.role) == String(second_part.role), "Definition role changed between instances")
	_assert(first.build_plan.target_snapshot.compiled_facets.composite_exposed_ports.size() == 2, "First instance lost exposed ports")
	_assert(second.build_plan.target_snapshot.compiled_facets.composite_exposed_ports.size() == 2, "Second instance lost exposed ports")
	_assert(String(first.build_plan.target_snapshot.compiled_facets.composite_exposed_ports[0].part_id) != String(second.build_plan.target_snapshot.compiled_facets.composite_exposed_ports[0].part_id), "Exposed port reused concrete part identity")

	var first_adapter = AdapterScript.new()
	_assert_ok(first_adapter.setup(FixtureScript.source_projections("first")), "First adapter setup failed")
	var first_store = StoreScript.new()
	_assert_ok(first_store.setup(), "First BuildPlan store setup failed")
	var first_process = ProcessScript.new()
	_assert_ok(first_process.setup(first_adapter, first_store), "First BuildProcess setup failed")
	_assert_ok(first_process.register_plan(first.build_plan), "First compiled BuildPlan registration failed")
	var first_builder = BuilderAgentScript.new()
	_assert_ok(first_builder.setup(first_process, "actor/c4-builder-first", ["FASTEN", "INSPECT"]), "First builder setup failed")
	var first_completed: Dictionary = first_builder.run_until_complete(String(first.build_plan.build_plan_id))
	_assert_ok(first_completed, "First definition-backed build failed")
	_assert(bool(first_completed.complete), "First build did not complete")
	_assert(first_completed.stage_results.size() == 3, "First build executed wrong stage count")

	var second_adapter = AdapterScript.new()
	_assert_ok(second_adapter.setup(FixtureScript.source_projections("second")), "Second adapter setup failed")
	var second_store = StoreScript.new()
	_assert_ok(second_store.setup(), "Second BuildPlan store setup failed")
	var second_process = ProcessScript.new()
	_assert_ok(second_process.setup(second_adapter, second_store), "Second BuildProcess setup failed")
	_assert_ok(second_process.register_plan(second.build_plan), "Second compiled BuildPlan registration failed")
	var second_builder = BuilderAgentScript.new()
	_assert_ok(second_builder.setup(second_process, "actor/c4-builder-second", ["INSPECT", "FASTEN"]), "Second builder setup failed")
	var second_completed: Dictionary = second_builder.run_until_complete(String(second.build_plan.build_plan_id))
	_assert_ok(second_completed, "Second definition-backed build failed")
	_assert(bool(second_completed.complete), "Second build did not complete")

	for pair in [[first_adapter, first], [second_adapter, second]]:
		var adapter = pair[0]
		var compiled: Dictionary = pair[1]
		var snapshot: Dictionary = adapter.get_construct_snapshot(String(compiled.build_plan.construct_id))
		_assert_ok(SnapshotScript.validate(snapshot), "Completed definition-backed construct invalid")
		_assert(String(snapshot.build_state) == "OPERATIONAL", "Definition-backed construct not operational")
		_assert(snapshot.compiled_facets.capabilities == ["PLACE_ITEMS", "SUPPORT_SURFACE", "WORK_SURFACE"], "Definition-backed capabilities mismatch")
		_assert(String(snapshot.compiled_facets.composite_definition_id) == FixtureScript.DEFINITION_ID, "Completed construct lost definition ID")
		_assert(int(snapshot.compiled_facets.composite_definition_version) == 1, "Completed construct lost definition version")
		_assert(String(snapshot.compiled_facets.composite_definition_checksum) == String(definition.checksum), "Completed construct lost pinned definition checksum")
		_assert(String(snapshot.compiled_facets.composite_instantiation_id) == String(compiled.instantiation.instantiation_id), "Completed construct lost instantiation ID")
		_assert(_canonical_equal(snapshot.compiled_facets.composite_parameters, compiled.instantiation.parameter_values), "Completed construct lost parameter values")
		_assert(_canonical_equal(snapshot.compiled_facets.composite_exposed_ports, compiled.build_plan.target_snapshot.compiled_facets.composite_exposed_ports), "Completed construct lost exposed ports")
		var key: String = "first" if adapter == first_adapter else "second"
		_assert(int(adapter.get_item_projection("item/c4-%s-fasteners-a" % key).quantity) == 1, "First fastener stack consumption mismatch")
		_assert(int(adapter.get_item_projection("item/c4-%s-fasteners-b" % key).quantity) == 2, "Second fastener stack consumption mismatch")
		_assert(int(adapter.get_item_projection("item/c4-%s-sealant" % key).quantity) == 1, "Sealant consumption mismatch")
		_assert(int(adapter.get_item_projection("item/c4-%s-unused-paint" % key).quantity) == 5, "Unused source item was mutated")
		_assert(String(adapter.get_item_projection("item/c4-%s-cosmetic-beam" % key).relation.kind) == ProjectionScript.CONTAINER, "Rejected cosmetic beam was moved")


func _test_partial_provenance_and_stage_execution() -> void:
	var compiled: Dictionary = _compile("partial")
	_assert_ok(compiled, "Partial fixture compilation failed")
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(FixtureScript.source_projections("partial")), "Partial adapter setup failed")
	var store = StoreScript.new()
	_assert_ok(store.setup(), "Partial store setup failed")
	var process = ProcessScript.new()
	_assert_ok(process.setup(adapter, store), "Partial process setup failed")
	_assert_ok(process.register_plan(compiled.build_plan), "Partial compiled plan registration failed")
	var stage_zero: Dictionary = process.advance_stage(String(compiled.build_plan.build_plan_id), 0, "operation/c4/partial/foundation", ["FASTEN"])
	_assert_ok(stage_zero, "Definition-backed foundation failed")
	var partial_snapshot: Dictionary = adapter.get_construct_snapshot(String(compiled.build_plan.construct_id))
	_assert(String(partial_snapshot.build_state) == "PARTIAL", "Foundation did not create partial construct")
	_assert(partial_snapshot.compiled_facets.capabilities.is_empty(), "Partial definition-backed construct exposed capabilities")
	_assert(String(partial_snapshot.compiled_facets.composite_definition_id) == FixtureScript.DEFINITION_ID, "Partial construct lost definition provenance")
	_assert(String(partial_snapshot.compiled_facets.composite_instantiation_id) == String(compiled.instantiation.instantiation_id), "Partial construct lost instantiation provenance")
	_assert(_canonical_equal(partial_snapshot.compiled_facets.composite_parameters, compiled.instantiation.parameter_values), "Partial construct lost parameter provenance")
	_assert(partial_snapshot.compiled_facets.composite_exposed_ports.size() == 1, "Partial construct exposed port for absent part")
	_assert(String(partial_snapshot.compiled_facets.composite_exposed_ports[0].port_id) == "port/work-surface", "Partial construct exposed wrong available port")
	_assert(int(store.get_ghost(String(compiled.build_plan.build_plan_id)).next_stage_index) == 1, "Ghost did not advance after foundation")
	var missing_capability: Dictionary = process.advance_stage(String(compiled.build_plan.build_plan_id), 1, "operation/c4/partial/frame-missing", [])
	_assert_error(missing_capability, "CONSTRUCTION_BUILD_STAGE_CAPABILITY_MISSING", "Frame accepted missing FASTEN capability")
	_assert(int(store.get_ghost(String(compiled.build_plan.build_plan_id)).next_stage_index) == 1, "Capability rejection changed ghost progress")
	_assert_ok(process.advance_stage(String(compiled.build_plan.build_plan_id), 1, "operation/c4/partial/frame", ["FASTEN"]), "Definition-backed frame failed")
	_assert_ok(process.advance_stage(String(compiled.build_plan.build_plan_id), 2, "operation/c4/partial/commission", ["INSPECT"]), "Definition-backed commissioning failed")
	_assert(String(store.get_ghost(String(compiled.build_plan.build_plan_id)).status) == GhostScript.STATUS_COMPLETE, "Definition-backed ghost not completed")
	var expected_final: Dictionary = SnapshotBuilderScript.build_for_stage(compiled.build_plan, 2)
	_assert_ok(expected_final, "Expected final stage snapshot failed")
	_assert(String(adapter.get_construct_snapshot(String(compiled.build_plan.construct_id)).checksum) == String(expected_final.snapshot.checksum), "Authoritative construct differs from compiled stage snapshot")


func _test_authoritative_recovery_for_compiled_plan() -> void:
	var compiled: Dictionary = _compile("recovery")
	_assert_ok(compiled, "Recovery fixture compilation failed")
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(FixtureScript.source_projections("recovery")), "Recovery adapter setup failed")
	var original_store = StoreScript.new()
	_assert_ok(original_store.setup(), "Recovery original store setup failed")
	var original_process = ProcessScript.new()
	_assert_ok(original_process.setup(adapter, original_store), "Recovery original process setup failed")
	_assert_ok(original_process.register_plan(compiled.build_plan), "Recovery plan registration failed")
	var interrupted: Dictionary = original_process.advance_stage(
		String(compiled.build_plan.build_plan_id),
		0,
		"operation/c4/recovery/foundation",
		["FASTEN"],
		{"failure_point": ProcessScript.FAILURE_AFTER_AUTHORITATIVE_COMMIT}
	)
	_assert_error(interrupted, "INJECTED_FAILURE_AFTER_AUTHORITATIVE_STAGE_COMMIT", "Recovery fault was not injected")
	_assert(int(original_store.get_ghost(String(compiled.build_plan.build_plan_id)).next_stage_index) == 0, "Interrupted ghost advanced before reconciliation")
	_assert(adapter.get_generation() == 1, "Authoritative foundation did not commit before interruption")
	_assert(int(adapter.get_item_projection("item/c4-recovery-fasteners-a").quantity) == 1, "Interrupted foundation consumed wrong fastener quantity")

	var restarted_store = StoreScript.new()
	_assert_ok(restarted_store.setup(), "Restarted store setup failed")
	var restarted_process = ProcessScript.new()
	_assert_ok(restarted_process.setup(adapter, restarted_store), "Restarted process setup failed")
	_assert_ok(restarted_process.register_plan(compiled.build_plan), "Restarted plan registration failed")
	var reconciled: Dictionary = restarted_process.reconcile_plan(String(compiled.build_plan.build_plan_id))
	_assert_ok(reconciled, "Definition-backed recovery reconciliation failed")
	_assert(int(reconciled.completed_stage_count) == 1, "Recovery did not infer committed foundation")
	_assert(int(restarted_store.get_ghost(String(compiled.build_plan.build_plan_id)).next_stage_index) == 1, "Recovery ghost progress mismatch")
	var builder = BuilderAgentScript.new()
	_assert_ok(builder.setup(restarted_process, "actor/c4-recovery-builder", ["FASTEN", "INSPECT"]), "Recovery builder setup failed")
	var completed: Dictionary = builder.run_until_complete(String(compiled.build_plan.build_plan_id))
	_assert_ok(completed, "Recovery builder did not complete plan")
	_assert(completed.stage_results.size() == 2, "Recovery builder repeated committed foundation")
	_assert(adapter.get_generation() == 3, "Recovery path committed wrong number of stages")
	_assert(int(adapter.get_item_projection("item/c4-recovery-fasteners-a").quantity) == 1, "Recovery consumed foundation fasteners twice")
	_assert(String(adapter.get_construct_snapshot(String(compiled.build_plan.construct_id)).build_state) == "OPERATIONAL", "Recovered definition-backed construct not operational")


func _test_definition_version_pinning() -> void:
	var version_one: Dictionary = FixtureScript.definition()
	var version_two: Dictionary = version_one.duplicate(true)
	version_two.definition_version = 2
	version_two.display_name = "Reusable work table reinforced edition"
	for bond in version_two.bond_templates:
		bond.strength_n = float(bond.strength_n) * 1.2
	version_two.checksum = DefinitionScript.compute_checksum(version_two)
	_assert_ok(DefinitionScript.validate(version_two), "Composite definition v2 rejected")
	var first: Dictionary = _compile("version-one", version_one)
	var second: Dictionary = _compile("version-two", version_two)
	_assert_ok(first, "Pinned v1 compilation failed")
	_assert_ok(second, "Pinned v2 compilation failed")
	_assert(int(first.instantiation.definition_version) == 1, "v1 instantiation version changed")
	_assert(int(second.instantiation.definition_version) == 2, "v2 instantiation version mismatch")
	_assert(String(first.instantiation.definition_checksum) == String(version_one.checksum), "v1 instantiation checksum not pinned")
	_assert(String(second.instantiation.definition_checksum) == String(version_two.checksum), "v2 instantiation checksum not pinned")
	_assert(first.instantiation.parameter_values == second.instantiation.parameter_values, "Definition version changed unchanged parameter defaults")
	_assert(float(second.build_plan.target_snapshot.bonds[0].strength_n) > float(first.build_plan.target_snapshot.bonds[0].strength_n), "v2 bond strength was not compiled")
	_assert(String(first.build_plan.target_snapshot.compiled_facets.composite_definition_checksum) != String(second.build_plan.target_snapshot.compiled_facets.composite_definition_checksum), "Different definition versions share provenance checksum")


func _test_catalog_replay_with_multiple_instances() -> void:
	var registry = RegistryScript.new()
	_assert_ok(registry.setup(), "Catalog registry setup failed")
	var definition: Dictionary = FixtureScript.definition()
	_assert_ok(registry.register_definition(definition), "Catalog definition registration failed")
	var first: Dictionary = _compile("catalog-a", definition)
	var second: Dictionary = _compile("catalog-b", definition)
	_assert_ok(first, "Catalog first compilation failed")
	_assert_ok(second, "Catalog second compilation failed")
	_assert_ok(registry.register_instantiation(first.instantiation), "Catalog first instantiation registration failed")
	_assert_ok(registry.register_instantiation(second.instantiation), "Catalog second instantiation registration failed")
	var generation_after_two: int = registry.get_generation()
	var first_replay: Dictionary = registry.register_instantiation(first.instantiation)
	_assert_ok(first_replay, "Catalog instantiation replay failed")
	_assert(bool(first_replay.replay), "Catalog instantiation replay not marked")
	_assert(registry.get_generation() == generation_after_two, "Catalog replay advanced generation")
	var state: Dictionary = registry.to_dict()
	_assert(state.definitions.size() == 1, "Catalog duplicated reusable definition")
	_assert(state.instantiations.size() == 2, "Catalog lost concrete instantiations")
	_assert(String(state.instantiations[0].definition_checksum) == String(state.instantiations[1].definition_checksum), "Catalog instances do not pin same definition")
	_assert(state.instantiations[0].parameter_values == state.instantiations[1].parameter_values, "Catalog changed default parameters between instances")
	_assert(String(state.instantiations[0].build_plan_checksum) != String(state.instantiations[1].build_plan_checksum), "Catalog instances reused concrete BuildPlan")
	var restored = RegistryScript.new()
	_assert_ok(restored.setup(), "Catalog restored registry setup failed")
	_assert_ok(restored.load_dict(state), "Catalog state restore failed")
	_assert(String(restored.get_instantiation(String(first.instantiation.instantiation_id)).checksum) == String(first.instantiation.checksum), "Catalog first instantiation changed after restore")
	_assert(String(restored.get_instantiation(String(second.instantiation.instantiation_id)).checksum) == String(second.instantiation.checksum), "Catalog second instantiation changed after restore")
	_assert(String(restored.get_definition(FixtureScript.DEFINITION_ID, 1).checksum) == String(definition.checksum), "Catalog reusable definition changed after restore")


func _canonical_equal(left, right) -> bool:
	var left_json: String = UtilsScript.canonical_json(left)
	if left_json.is_empty():
		return false
	var right_json: String = UtilsScript.canonical_json(right)
	return not right_json.is_empty() and left_json == right_json


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
		print("C4 CompositeDefinition integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C4 CompositeDefinition integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
