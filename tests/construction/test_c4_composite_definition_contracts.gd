extends SceneTree

const FixtureScript = preload("res://tests/construction/fixtures/c4_reusable_table_fixture.gd")
const PartSlotScript = preload("res://scripts/construction/composites/composite_part_slot.gd")
const BondTemplateScript = preload("res://scripts/construction/composites/composite_bond_template.gd")
const StageTemplateScript = preload("res://scripts/construction/composites/composite_stage_template.gd")
const ParameterScript = preload("res://scripts/construction/composites/composite_parameter_definition.gd")
const ExposedPortScript = preload("res://scripts/construction/composites/composite_exposed_port.gd")
const DefinitionScript = preload("res://scripts/construction/composites/construction_composite_definition.gd")
const ExtractorScript = preload("res://scripts/construction/composites/construction_composite_definition_extractor.gd")
const CompilerScript = preload("res://scripts/construction/composites/construction_composite_build_plan_compiler.gd")
const InstantiationScript = preload("res://scripts/construction/composites/construction_composite_instantiation.gd")
const RegistryScript = preload("res://scripts/construction/composites/construction_composite_registry.gd")
const PersistenceScript = preload("res://scripts/construction/composites/construction_composite_persistence.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

class MemoryStateStore:
	extends RefCounted
	var states: Dictionary = {}

	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true)
		return {"success": true}

	func load_state(key: String) -> Dictionary:
		if not states.has(key):
			return {"success": false, "error_code": "STATE_NOT_FOUND"}
		return {"success": true, "state": Dictionary(states[key]).duplicate(true)}

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_primitive_templates()
	_test_definition_extraction_and_contract()
	_test_definition_topology_rejections()
	_test_compiler_and_instantiation_contracts()
	_test_compiler_rejections()
	_test_registry_versioning_and_persistence()
	_test_runner_contracts()
	_finish()


func _test_primitive_templates() -> void:
	var definition: Dictionary = FixtureScript.definition()
	var slot: Dictionary = definition["part_slots"][0]
	_assert_ok(PartSlotScript.validate(slot), "Valid composite part slot rejected")
	var wrong_slot: Dictionary = slot.duplicate(true)
	wrong_slot["slot_id"] = "part/not-a-slot"
	_assert_error(PartSlotScript.validate(wrong_slot), "INVALID_COMPOSITE_PART_SLOT_ID", "Non-slot identifier accepted")
	var bad_mass: Dictionary = slot.duplicate(true)
	bad_mass["mass_kg"] = 0.0
	_assert_error(PartSlotScript.validate(bad_mass), "INVALID_COMPOSITE_PART_MASS", "Zero part mass accepted")
	var cosmetic_projection: Dictionary = FixtureScript.source_projections("primitive")[0]
	_assert(not PartSlotScript.matches_projection(slot, cosmetic_projection), "Component constraint accepted cosmetic beam")
	var structural_projection: Dictionary = FixtureScript.source_projections("primitive")[2]
	_assert(PartSlotScript.matches_projection(slot, structural_projection), "Component subset rejected structural beam")

	var bond: Dictionary = definition["bond_templates"][0]
	_assert_ok(BondTemplateScript.validate(bond), "Valid composite bond template rejected")
	var self_bond: Dictionary = bond.duplicate(true)
	self_bond["part_b_slot_id"] = self_bond["part_a_slot_id"]
	_assert_error(BondTemplateScript.validate(self_bond), "COMPOSITE_SELF_BOND_FORBIDDEN", "Self bond accepted")

	var stage: Dictionary = definition["stage_templates"][0]
	_assert_ok(StageTemplateScript.validate(stage), "Valid composite stage template rejected")
	var duplicate_requirement: Dictionary = stage.duplicate(true)
	duplicate_requirement["material_requirements"] = [stage["material_requirements"][0], stage["material_requirements"][0]]
	_assert_error(StageTemplateScript.validate(duplicate_requirement), "DUPLICATE_COMPOSITE_STAGE_MATERIAL_DEFINITION", "Duplicate material definition accepted")
	var unsorted_capabilities: Dictionary = stage.duplicate(true)
	unsorted_capabilities["required_capabilities"] = ["WELD", "FASTEN"]
	_assert_error(StageTemplateScript.validate(unsorted_capabilities), "COMPOSITE_STAGE_REQUIRED_CAPABILITIES_NOT_SORTED", "Unsorted stage capabilities accepted")

	var parameter: Dictionary = definition["parameters"][0]
	_assert_ok(ParameterScript.validate(parameter), "Valid composite parameter rejected")
	_assert_ok(ParameterScript.validate_value(parameter, "painted"), "Valid parameter override rejected")
	_assert_error(ParameterScript.validate_value(parameter, 3), "COMPOSITE_PARAMETER_STRING_REQUIRED", "Wrong parameter value type accepted")
	var port: Dictionary = definition["exposed_ports"][0]
	_assert_ok(ExposedPortScript.validate(port), "Valid exposed port rejected")
	var invalid_port: Dictionary = port.duplicate(true)
	invalid_port["port_kind"] = "support-surface"
	_assert_error(ExposedPortScript.validate(invalid_port), "INVALID_COMPOSITE_EXPOSED_PORT_KIND", "Lowercase port kind accepted")


func _test_definition_extraction_and_contract() -> void:
	var extracted: Dictionary = FixtureScript.extracted_definition()
	_assert_ok(DefinitionScript.validate(extracted), "Extracted composite definition rejected")
	_assert(String(extracted["composite_definition_id"]) == FixtureScript.DEFINITION_ID, "Extracted definition identity mismatch")
	_assert(int(extracted["definition_version"]) == 1, "Extracted definition version mismatch")
	_assert(extracted["part_slots"].size() == 5, "Extracted definition lost part slots")
	_assert(extracted["bond_templates"].size() == 4, "Extracted definition lost bonds")
	_assert(extracted["stage_templates"].size() == 3, "Extracted definition lost stages")
	_assert(extracted["parameters"].is_empty(), "Extractor invented parameters")
	_assert(extracted["exposed_ports"].is_empty(), "Extractor invented exposed ports")
	_assert(String(extracted["provenance"]["source_kind"]) == DefinitionScript.SOURCE_BUILD_PLAN_COMPLETION, "Definition provenance kind mismatch")
	var encoded: String = UtilsScript.canonical_json(extracted)
	_assert(not encoded.contains("item/c3-"), "Definition leaked source item identity")
	_assert(not encoded.contains("construct/table/c3"), "Definition leaked source construct identity")
	_assert(not encoded.contains("build-plan/table/c3"), "Definition leaked source build plan identity")
	_assert(String(extracted["part_slots"][0]["slot_id"]).begins_with("slot/"), "Definition did not replace part IDs with slots")
	_assert(String(extracted["bond_templates"][0]["bond_template_id"]).begins_with("bond-template/"), "Definition did not replace bond IDs with templates")
	_assert(String(extracted["stage_templates"][0]["stage_template_id"]).begins_with("stage-template/"), "Definition did not replace stage IDs with templates")
	var curated: Dictionary = FixtureScript.definition()
	_assert_ok(DefinitionScript.validate(curated), "Curated composite definition rejected")
	_assert(curated["parameters"].size() == 2, "Curated definition parameter count mismatch")
	_assert(curated["exposed_ports"].size() == 2, "Curated definition exposed port count mismatch")
	var changed: Dictionary = curated.duplicate(true)
	changed["display_name"] = "Changed without checksum"
	_assert_error(DefinitionScript.validate(changed), "CONSTRUCTION_COMPOSITE_DEFINITION_CHECKSUM_MISMATCH", "Definition mutation accepted stale checksum")
	var leaked: Dictionary = curated.duplicate(true)
	leaked["part_slots"][0]["metadata"] = {"source": "item/leaked"}
	leaked["checksum"] = DefinitionScript.compute_checksum(leaked)
	_assert_error(DefinitionScript.validate(leaked), "CONSTRUCTION_COMPOSITE_DEFINITION_LEAKS_INSTANCE_ID", "Definition accepted concrete item identity")

	var incomplete_result: Dictionary = ExtractorScript.extract_from_completed_build(
		"composite-definition/furniture/incomplete",
		1,
		"Incomplete",
		"Incomplete",
		preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd").build_for_stage(
			preload("res://tests/construction/fixtures/c3_table_build_fixture.gd").build_plan(), 1
		)["snapshot"],
		preload("res://tests/construction/fixtures/c3_table_build_fixture.gd").build_plan(),
		"actor/c4-designer"
	)
	_assert_error(incomplete_result, "COMPOSITE_DEFINITION_SOURCE_BUILD_NOT_COMPLETE", "Incomplete construct extracted as reusable definition")


func _test_definition_topology_rejections() -> void:
	var definition: Dictionary = FixtureScript.definition()
	var unknown_bond_slot: Dictionary = definition.duplicate(true)
	unknown_bond_slot["bond_templates"][0]["part_a_slot_id"] = "slot/missing"
	unknown_bond_slot["checksum"] = DefinitionScript.compute_checksum(unknown_bond_slot)
	_assert_error(DefinitionScript.validate(unknown_bond_slot), "CONSTRUCTION_COMPOSITE_BOND_REFERENCES_UNKNOWN_SLOT", "Bond with unknown slot accepted")
	var unknown_port_slot: Dictionary = definition.duplicate(true)
	unknown_port_slot["exposed_ports"][0]["slot_id"] = "slot/missing"
	unknown_port_slot["checksum"] = DefinitionScript.compute_checksum(unknown_port_slot)
	_assert_error(DefinitionScript.validate(unknown_port_slot), "CONSTRUCTION_COMPOSITE_EXPOSED_PORT_REFERENCES_UNKNOWN_SLOT", "Port with unknown slot accepted")
	var regressed: Dictionary = definition.duplicate(true)
	regressed["stage_templates"][1]["included_part_slot_ids"] = ["slot/top"]
	regressed["checksum"] = DefinitionScript.compute_checksum(regressed)
	_assert_error(DefinitionScript.validate(regressed), "CONSTRUCTION_COMPOSITE_STAGE_CONTENT_REGRESSED", "Regressing composite stage accepted")
	var incomplete: Dictionary = definition.duplicate(true)
	incomplete["stage_templates"][-1]["included_part_slot_ids"].erase("slot/leg-d")
	incomplete["checksum"] = DefinitionScript.compute_checksum(incomplete)
	_assert_error(DefinitionScript.validate(incomplete), "CONSTRUCTION_COMPOSITE_STAGE_CONTENT_REGRESSED", "Incomplete final stage accepted")
	var wrong_root: Dictionary = definition.duplicate(true)
	wrong_root["root_definition_id"] = "custom_root"
	wrong_root["checksum"] = DefinitionScript.compute_checksum(wrong_root)
	_assert_error(DefinitionScript.validate(wrong_root), "UNSUPPORTED_CONSTRUCTION_COMPOSITE_ROOT_DEFINITION", "Unsupported root definition accepted")
	var manual_bad_provenance: Dictionary = definition.duplicate(true)
	manual_bad_provenance["provenance"]["source_kind"] = DefinitionScript.SOURCE_MANUAL
	manual_bad_provenance["checksum"] = DefinitionScript.compute_checksum(manual_bad_provenance)
	_assert_error(DefinitionScript.validate(manual_bad_provenance), "MANUAL_COMPOSITE_SOURCE_CHECKSUM_MUST_BE_EMPTY", "Manual definition retained source checksums")


func _test_compiler_and_instantiation_contracts() -> void:
	var definition: Dictionary = FixtureScript.definition()
	var ids: Dictionary = FixtureScript.compile_ids("alpha")
	var sources: Array = FixtureScript.source_projections("alpha")
	var compiled: Dictionary = CompilerScript.compile(
		definition,
		ids.instantiation_id,
		ids.build_plan_id,
		ids.construct_id,
		ids.root_item_instance_id,
		ProjectionScript.world_relation(),
		sources
	)
	_assert_ok(compiled, "Composite definition did not compile")
	var plan: Dictionary = compiled["build_plan"]
	var instantiation: Dictionary = compiled["instantiation"]
	_assert_ok(BuildPlanScript.validate(plan), "Compiled C3 BuildPlan rejected")
	_assert_ok(InstantiationScript.validate_against(instantiation, definition, plan), "Instantiation record rejected")
	_assert(plan["source_item_projections"].size() == 8, "Compiler retained unused or incompatible source items")
	_assert(not UtilsScript.canonical_json(plan).contains("unused-paint"), "Compiler retained unused paint")
	_assert(not UtilsScript.canonical_json(plan).contains("cosmetic-beam"), "Compiler bound incompatible cosmetic beam")
	_assert(instantiation["part_bindings"].size() == 5, "Part binding count mismatch")
	_assert(instantiation["material_bindings"].size() == 3, "Material binding count mismatch")
	_assert(String(plan["target_snapshot"]["compiled_facets"]["composite_definition_id"]) == FixtureScript.DEFINITION_ID, "Target snapshot lost definition identity")
	_assert(int(plan["target_snapshot"]["compiled_facets"]["composite_definition_version"]) == 1, "Target snapshot lost definition version")
	_assert(String(plan["target_snapshot"]["compiled_facets"]["composite_instantiation_id"]) == String(ids.instantiation_id), "Target snapshot lost instantiation identity")
	_assert(String(instantiation["parameter_values"]["parameter/finish"]) == "natural", "Default string parameter not pinned")
	_assert(float(instantiation["parameter_values"]["parameter/load-rating-kg"]) == 100.0, "Default float parameter not pinned")
	_assert(UtilsScript.canonical_json(plan["target_snapshot"]["compiled_facets"]["composite_parameters"]) == UtilsScript.canonical_json(instantiation["parameter_values"]), "Target snapshot parameter provenance mismatch")
	_assert(plan["target_snapshot"]["compiled_facets"]["composite_exposed_ports"].size() == 2, "Exposed ports not compiled")
	var top_binding: Dictionary = {}
	for binding in instantiation["part_bindings"]:
		if String(binding["slot_id"]) == "slot/top":
			top_binding = binding
	_assert(not top_binding.is_empty(), "Top slot binding missing")
	var work_surface_port: Dictionary = {}
	for port_row in plan["target_snapshot"]["compiled_facets"]["composite_exposed_ports"]:
		if String(port_row["port_id"]) == "port/work-surface":
			work_surface_port = port_row
	_assert(not work_surface_port.is_empty(), "Compiled work-surface port missing")
	_assert(String(work_surface_port["part_id"]) == String(top_binding["part_id"]), "Exposed port did not bind to concrete top part")
	_assert(String(plan["stages"][0]["material_allocations"][0]["item_instance_id"]).ends_with("fasteners-a"), "Foundation did not choose deterministic first fastener stack")
	_assert(String(plan["stages"][1]["material_allocations"][0]["item_instance_id"]).ends_with("fasteners-b"), "Frame did not advance to second fastener stack")
	_assert(int(plan["stages"][0]["material_allocations"][0]["quantity"]) == 2, "Foundation material quantity mismatch")
	var reversed_sources: Array = sources.duplicate(true)
	reversed_sources.reverse()
	var repeated: Dictionary = CompilerScript.compile(
		definition,
		ids.instantiation_id,
		ids.build_plan_id,
		ids.construct_id,
		ids.root_item_instance_id,
		ProjectionScript.world_relation(),
		reversed_sources
	)
	_assert_ok(repeated, "Reordered source projections failed compilation")
	_assert(String(repeated["build_plan"]["checksum"]) == String(plan["checksum"]), "Source ordering changed BuildPlan checksum")
	_assert(String(repeated["instantiation"]["checksum"]) == String(instantiation["checksum"]), "Source ordering changed instantiation checksum")
	var mutated_record: Dictionary = instantiation.duplicate(true)
	mutated_record["material_bindings"][0]["quantity"] += 1
	mutated_record["checksum"] = InstantiationScript.compute_checksum(mutated_record)
	_assert_error(InstantiationScript.validate_against(mutated_record, definition, plan), "COMPOSITE_INSTANTIATION_MATERIAL_BINDING_PLAN_MISMATCH", "Instantiation material mismatch accepted")
	var rebound_material: Dictionary = instantiation.duplicate(true)
	rebound_material["material_bindings"][0]["item_instance_id"] = String(instantiation["material_bindings"][1]["item_instance_id"])
	rebound_material["checksum"] = InstantiationScript.compute_checksum(rebound_material)
	_assert_error(InstantiationScript.validate_against(rebound_material, definition, plan), "COMPOSITE_INSTANTIATION_MATERIAL_BINDING_PLAN_MISMATCH", "Instantiation accepted material item not used by BuildPlan stage")
	var changed_parameter: Dictionary = instantiation.duplicate(true)
	changed_parameter["parameter_values"]["parameter/finish"] = "painted"
	changed_parameter["checksum"] = InstantiationScript.compute_checksum(changed_parameter)
	_assert_error(InstantiationScript.validate_against(changed_parameter, definition, plan), "COMPOSITE_INSTANTIATION_PARAMETER_PROVENANCE_MISMATCH", "Instantiation parameter changed without BuildPlan provenance")


func _test_compiler_rejections() -> void:
	var definition: Dictionary = FixtureScript.definition()
	var ids: Dictionary = FixtureScript.compile_ids("reject")
	var missing_part_sources: Array = FixtureScript.source_projections("reject")
	missing_part_sources = missing_part_sources.filter(func(item): return not String(item["item_instance_id"]).ends_with("leg-d"))
	var missing_part: Dictionary = CompilerScript.compile(definition, ids.instantiation_id, ids.build_plan_id, ids.construct_id, ids.root_item_instance_id, ProjectionScript.world_relation(), missing_part_sources)
	_assert_error(missing_part, "COMPOSITE_PART_SLOT_UNSATISFIED", "Compiler accepted missing structural part")
	var insufficient_material: Array = FixtureScript.source_projections("reject")
	for item in insufficient_material:
		if String(item["definition_id"]) == "fastener":
			item["quantity"] = 2
	var missing_material: Dictionary = CompilerScript.compile(definition, ids.instantiation_id, ids.build_plan_id, ids.construct_id, ids.root_item_instance_id, ProjectionScript.world_relation(), insufficient_material)
	_assert_error(missing_material, "COMPOSITE_MATERIAL_REQUIREMENT_UNSATISFIED", "Compiler accepted insufficient non-exhaustible material")
	var unsafe_namespace: Dictionary = CompilerScript.compile(definition, ids.instantiation_id, ids.build_plan_id, "construct/table:unsafe", ids.root_item_instance_id, ProjectionScript.world_relation(), FixtureScript.source_projections("reject"))
	_assert_error(unsafe_namespace, "COMPOSITE_INSTANCE_NAMESPACE_NOT_PATH_SAFE", "Compiler accepted part-ID-unsafe construct namespace")
	var attached_sources: Array = FixtureScript.source_projections("reject")
	attached_sources[2]["relation"] = ProjectionScript.attachment_relation("construct/other", "item/other-root", "part/other")
	var attached_missing: Dictionary = CompilerScript.compile(definition, ids.instantiation_id, ids.build_plan_id, ids.construct_id, ids.root_item_instance_id, ProjectionScript.world_relation(), attached_sources)
	_assert_error(attached_missing, "COMPOSITE_PART_SLOT_UNSATISFIED", "Compiler reused attached source part")
	var unknown_parameter: Dictionary = CompilerScript.compile(definition, ids.instantiation_id, ids.build_plan_id, ids.construct_id, ids.root_item_instance_id, ProjectionScript.world_relation(), FixtureScript.source_projections("reject"), {"parameter/unknown": true})
	_assert_error(unknown_parameter, "UNKNOWN_COMPOSITE_PARAMETER_OVERRIDE", "Compiler accepted unknown parameter")
	var wrong_parameter_type: Dictionary = CompilerScript.compile(definition, ids.instantiation_id, ids.build_plan_id, ids.construct_id, ids.root_item_instance_id, ProjectionScript.world_relation(), FixtureScript.source_projections("reject"), {"parameter/finish": 7})
	_assert_error(wrong_parameter_type, "COMPOSITE_PARAMETER_STRING_REQUIRED", "Compiler accepted wrong parameter type")


func _test_registry_versioning_and_persistence() -> void:
	var registry = RegistryScript.new()
	_assert_ok(registry.setup(), "Composite registry setup failed")
	var definition: Dictionary = FixtureScript.definition()
	var first: Dictionary = registry.register_definition(definition)
	_assert_ok(first, "Definition registration failed")
	_assert(not bool(first.get("replay", true)), "First definition registration marked replay")
	var replay: Dictionary = registry.register_definition(definition)
	_assert_ok(replay, "Exact definition replay failed")
	_assert(bool(replay.get("replay", false)), "Exact definition replay not marked")
	var conflicting: Dictionary = definition.duplicate(true)
	conflicting["display_name"] = "Conflicting v1"
	conflicting["checksum"] = DefinitionScript.compute_checksum(conflicting)
	_assert_error(registry.register_definition(conflicting), "COMPOSITE_DEFINITION_VERSION_CONFLICT", "Changed definition reused version")
	var gap: Dictionary = definition.duplicate(true)
	gap["definition_version"] = 3
	gap["checksum"] = DefinitionScript.compute_checksum(gap)
	_assert_error(registry.register_definition(gap), "COMPOSITE_DEFINITION_VERSION_SEQUENCE_GAP", "Definition version gap accepted")
	var version_two: Dictionary = definition.duplicate(true)
	version_two["definition_version"] = 2
	version_two["display_name"] = "Reusable work table v2"
	version_two["checksum"] = DefinitionScript.compute_checksum(version_two)
	_assert_ok(registry.register_definition(version_two), "Sequential definition version rejected")
	_assert(registry.get_latest_version(FixtureScript.DEFINITION_ID) == 2, "Latest definition version mismatch")
	_assert(String(registry.get_definition(FixtureScript.DEFINITION_ID, 1)["checksum"]) == String(definition["checksum"]), "Pinned v1 definition changed after v2")

	var ids: Dictionary = FixtureScript.compile_ids("registry")
	var compiled: Dictionary = CompilerScript.compile(definition, ids.instantiation_id, ids.build_plan_id, ids.construct_id, ids.root_item_instance_id, ProjectionScript.world_relation(), FixtureScript.source_projections("registry"))
	_assert_ok(compiled, "Registry instantiation fixture compilation failed")
	var registered_instance: Dictionary = registry.register_instantiation(compiled["instantiation"])
	_assert_ok(registered_instance, "Instantiation registration failed")
	_assert_ok(registry.register_instantiation(compiled["instantiation"]), "Instantiation exact replay failed")
	var missing_parameter_instance: Dictionary = compiled["instantiation"].duplicate(true)
	missing_parameter_instance["parameter_values"].erase("parameter/finish")
	missing_parameter_instance["checksum"] = InstantiationScript.compute_checksum(missing_parameter_instance)
	_assert_error(registry.register_instantiation(missing_parameter_instance), "COMPOSITE_INSTANTIATION_PARAMETER_SET_MISMATCH", "Registry accepted instantiation missing definition parameter")
	var conflicting_instance: Dictionary = compiled["instantiation"].duplicate(true)
	conflicting_instance["build_plan_checksum"] = "f".repeat(64)
	conflicting_instance["checksum"] = InstantiationScript.compute_checksum(conflicting_instance)
	_assert_error(registry.register_instantiation(conflicting_instance), "COMPOSITE_INSTANTIATION_ID_CONFLICT", "Changed instantiation reused ID")

	var state: Dictionary = registry.to_dict()
	_assert_ok(RegistryScript.validate_state(state), "Composite registry state rejected")
	var bad_generation: Dictionary = state.duplicate(true)
	bad_generation["generation"] += 1
	bad_generation["checksum"] = RegistryScript.compute_checksum(bad_generation)
	_assert_error(RegistryScript.validate_state(bad_generation), "CONSTRUCTION_COMPOSITE_REGISTRY_GENERATION_MISMATCH", "Registry accepted unrelated generation")
	var json_state = JSON.parse_string(JSON.stringify(state, "", true, true))
	_assert(json_state is Dictionary, "Composite registry did not survive JSON")
	var restored = RegistryScript.new()
	_assert_ok(restored.setup(), "Restored registry setup failed")
	_assert_ok(restored.load_dict(Dictionary(json_state)), "Composite registry JSON load failed")
	_assert(restored.to_dict() == state, "Composite registry JSON round-trip changed state")
	var stable_before: Dictionary = restored.to_dict()
	var tampered: Dictionary = stable_before.duplicate(true)
	tampered["definitions"][0]["display_name"] = "Tampered"
	_assert_error(restored.load_dict(tampered), "CONSTRUCTION_COMPOSITE_DEFINITION_CHECKSUM_MISMATCH", "Tampered nested definition loaded")
	_assert(restored.to_dict() == stable_before, "Failed registry load mutated active state")

	var memory = MemoryStateStore.new()
	var persistence = PersistenceScript.new()
	_assert_ok(persistence.setup(registry, memory, "c4-registry"), "Composite persistence setup failed")
	_assert_ok(persistence.save(), "Composite registry save failed")
	var persisted = RegistryScript.new()
	_assert_ok(persisted.setup(), "Persisted registry setup failed")
	var loader = PersistenceScript.new()
	_assert_ok(loader.setup(persisted, memory, "c4-registry"), "Composite loader setup failed")
	_assert_ok(loader.load(), "Composite registry persistence load failed")
	_assert(persisted.to_dict() == registry.to_dict(), "Composite persistence round-trip changed registry")


func _test_runner_contracts() -> void:
	var ps_runner: String = FileAccess.get_file_as_string("res://RUN_C4_COMPOSITE_DEFINITION_TESTS.ps1")
	var sh_runner: String = FileAccess.get_file_as_string("res://RUN_C4_COMPOSITE_DEFINITION_TESTS.sh")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(not ps_runner.is_empty(), "C4 PowerShell runner missing")
	_assert(not sh_runner.is_empty(), "C4 shell runner missing")
	_assert(ps_runner.contains("test_c4_composite_definition_contracts.gd"), "C4 PowerShell runner omits contracts")
	_assert(ps_runner.contains("test_c4_composite_definition_integration.gd"), "C4 PowerShell runner omits integration")
	_assert(sh_runner.contains("test_c4_composite_definition_contracts.gd"), "C4 shell runner omits contracts")
	_assert(sh_runner.contains("test_c4_composite_definition_integration.gd"), "C4 shell runner omits integration")
	_assert(world_runner.contains("test_c4_composite_definition_contracts.gd"), "World regression omits C4 contracts")
	_assert(world_runner.contains("test_c4_composite_definition_integration.gd"), "World regression omits C4 integration")


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
		print("C4 CompositeDefinition contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C4 CompositeDefinition contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
