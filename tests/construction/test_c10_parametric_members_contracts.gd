extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c10_parametric_members_fixture.gd")
const MaterialScript = preload("res://scripts/construction/parametric/construction_parametric_material.gd")
const LayerScript = preload("res://scripts/construction/parametric/construction_parametric_layer.gd")
const DefinitionScript = preload("res://scripts/construction/parametric/construction_parametric_member_definition.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const CompilerScript = preload("res://scripts/construction/parametric/construction_parametric_compiler.gd")
const CatalogScript = preload("res://scripts/construction/parametric/construction_parametric_catalog.gd")
const ProjectionFactoryScript = preload("res://scripts/construction/parametric/construction_parametric_projection_factory.gd")
const FabricationCompilerScript = preload("res://scripts/construction/parametric/construction_parametric_fabrication_compiler.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/parametric/construction_parametric_capability_compiler.gd")
const SegmenterScript = preload("res://scripts/construction/parametric/construction_parametric_segmenter.gd")
const SegmentationPlanScript = preload("res://scripts/construction/parametric/construction_parametric_segmentation_plan.gd")
const RepairPlanScript = preload("res://scripts/construction/parametric/construction_parametric_repair_plan.gd")
const StoreScript = preload("res://scripts/construction/parametric/construction_parametric_member_store.gd")
const PersistenceScript = preload("res://scripts/construction/parametric/construction_parametric_persistence.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")

class MemoryStore:
	extends RefCounted
	var states: Dictionary = {}
	func save_state(key: String, state: Dictionary) -> Dictionary:
		states[key] = state.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func load_state(key: String) -> Dictionary:
		if not states.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": Dictionary(states[key]).duplicate(true)}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_material_and_layer_contracts()
	_test_definition_contracts()
	_test_compiled_instance_contracts()
	_test_catalog_and_persistence()
	_test_projection_fabrication_and_capability_contracts()
	_test_segmentation_repair_and_store_contracts()
	_finish()

func _test_material_and_layer_contracts() -> void:
	var materials := FixtureScript.materials()
	_assert(materials.size() == 6, "Fixture material count mismatch")
	for material in materials:
		_assert_ok(MaterialScript.validate(material), "Valid material rejected")
		_assert(String(material["checksum"]).length() == 64, "Material checksum invalid")
		_assert(float(material["density_kg_m3"]) > 0.0, "Material density missing")
	var steel: Dictionary = FixtureScript.material_map()["material/steel-s355"]
	var roundtrip = JSON.parse_string(JSON.stringify(steel, "", true, true))
	_assert(roundtrip is Dictionary, "Material JSON roundtrip failed")
	_assert_ok(MaterialScript.validate(roundtrip), "Material roundtrip rejected")
	_assert(UtilsScript.canonical_json(roundtrip) == UtilsScript.canonical_json(steel), "Material roundtrip changed")
	var unexpected := steel.duplicate(true); unexpected["unexpected_field"] = true
	_assert_error(MaterialScript.validate(unexpected), "UNEXPECTED_FIELD", "Material accepted unexpected field")
	var bad_density := steel.duplicate(true); bad_density["density_kg_m3"] = 0.0; bad_density["checksum"] = MaterialScript.compute_checksum(bad_density)
	_assert_error(MaterialScript.validate(bad_density), "INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL_DENSITY", "Material accepted zero density")
	var tampered := steel.duplicate(true); tampered["stock_unit_mass_kg"] = 11.0
	_assert_error(MaterialScript.validate(tampered), "CONSTRUCTION_PARAMETRIC_MATERIAL_CHECKSUM_MISMATCH", "Material accepted tamper")
	var layer := LayerScript.create("layer/test/steel", "material/steel-s355", 0.02, "structure", {"ordinal": 1})
	_assert_ok(LayerScript.validate(layer), "Valid layer rejected")
	_assert(float(layer["thickness_m"]) == 0.02, "Layer thickness mismatch")
	var bad_layer := layer.duplicate(true); bad_layer["thickness_m"] = -0.1; bad_layer["checksum"] = LayerScript.compute_checksum(bad_layer)
	_assert_error(LayerScript.validate(bad_layer), "INVALID_CONSTRUCTION_PARAMETRIC_LAYER_THICKNESS", "Layer accepted negative thickness")

func _test_definition_contracts() -> void:
	var definitions := FixtureScript.all_definitions()
	_assert(definitions.size() == 5, "Definition count mismatch")
	var expected_kinds := ["BEAM", "CABLE", "PANEL", "PIPE", "LAYERED_WALL"]
	var actual_kinds: Array = []
	for definition in definitions:
		_assert_ok(DefinitionScript.validate(definition), "Valid definition rejected")
		_assert(String(definition["checksum"]).length() == 64, "Definition checksum invalid")
		_assert(int(definition["definition_version"]) == 1, "Definition version mismatch")
		actual_kinds.append(String(definition["member_kind"]))
	actual_kinds.sort(); expected_kinds.sort()
	_assert(actual_kinds == expected_kinds, "Definition kinds mismatch")
	var beam := FixtureScript.beam_definition()
	_assert(DefinitionScript.expected_parameters("BEAM") == ["height_m", "length_m", "width_m"], "Beam parameter schema mismatch")
	var unknown := beam.duplicate(true); unknown["parameter_defaults"]["depth_m"] = 1.0; unknown["checksum"] = DefinitionScript.compute_checksum(unknown)
	_assert_error(DefinitionScript.validate(unknown), "CONSTRUCTION_PARAMETRIC_PARAMETER_SET_MISMATCH", "Definition accepted unknown parameter")
	var out_of_range := beam.duplicate(true); out_of_range["parameter_defaults"]["length_m"] = 200.0; out_of_range["checksum"] = DefinitionScript.compute_checksum(out_of_range)
	_assert_error(DefinitionScript.validate(out_of_range), "CONSTRUCTION_PARAMETRIC_PARAMETER_DEFAULT_OUT_OF_RANGE", "Definition accepted out-of-range default")
	var layered_primary := FixtureScript.wall_definition().duplicate(true); layered_primary["primary_material_id"] = "material/steel-s355"; layered_primary["checksum"] = DefinitionScript.compute_checksum(layered_primary)
	_assert_error(DefinitionScript.validate(layered_primary), "LAYERED_WALL_PRIMARY_MATERIAL_FORBIDDEN", "Wall accepted primary material")
	var no_layers := FixtureScript.wall_definition().duplicate(true); no_layers["layers"] = []; no_layers["checksum"] = DefinitionScript.compute_checksum(no_layers)
	_assert_error(DefinitionScript.validate(no_layers), "LAYERED_WALL_LAYERS_REQUIRED", "Wall accepted no layers")
	var pipe := FixtureScript.pipe_definition().duplicate(true); pipe["parameter_defaults"]["wall_thickness_m"] = 0.05; pipe["checksum"] = DefinitionScript.compute_checksum(pipe)
	_assert_error(DefinitionScript.validate(pipe), "CONSTRUCTION_PARAMETRIC_PIPE_WALL_TOO_THICK", "Pipe accepted solid wall")
	var version2 := FixtureScript.beam_definition(2)
	_assert_ok(DefinitionScript.validate(version2), "Definition v2 rejected")
	_assert(String(version2["member_definition_id"]) == String(beam["member_definition_id"]), "Version changed definition identity")

func _test_compiled_instance_contracts() -> void:
	var instances := [FixtureScript.beam_instance(), FixtureScript.panel_instance(), FixtureScript.pipe_instance(), FixtureScript.cable_instance(), FixtureScript.wall_instance()]
	for instance in instances:
		_assert_ok(InstanceScript.validate(instance), "Compiled instance rejected")
		_assert(float(instance["mass_kg"]) > 0.0, "Compiled mass missing")
		_assert(float(instance["geometry"]["volume_m3"]) > 0.0, "Compiled volume missing")
		_assert(Array(instance["geometry"]["bounding_box_m"]).size() == 3, "Bounding box missing")
		_assert(String(instance["checksum"]).length() == 64, "Instance checksum invalid")
	var beam := FixtureScript.beam_instance("contract", 5.0)
	_assert(float(beam["parameter_values"]["length_m"]) == 5.0, "Beam override lost")
	_assert(float(beam["geometry"]["length_m"]) == 5.0, "Beam geometry length mismatch")
	_assert(float(beam["mass_kg"]) == 785.0, "Beam mass calculation mismatch")
	_assert(int(beam["material_usage"][0]["stock_units"]) == 79, "Beam stock unit calculation mismatch")
	var unknown := CompilerScript.compile(FixtureScript.beam_definition(), FixtureScript.materials(), {"depth_m": 1.0}, "parametric-member/bad/unknown", "item/parametric/bad/unknown")
	_assert_error(unknown, "UNKNOWN_CONSTRUCTION_PARAMETRIC_PARAMETER", "Compiler accepted unknown override")
	var outside := CompilerScript.compile(FixtureScript.beam_definition(), FixtureScript.materials(), {"length_m": 101.0}, "parametric-member/bad/range", "item/parametric/bad/range")
	_assert_error(outside, "CONSTRUCTION_PARAMETRIC_PARAMETER_OUT_OF_RANGE", "Compiler accepted out-of-range parameter")
	var missing_materials := CompilerScript.compile(FixtureScript.beam_definition(), [], {}, "parametric-member/bad/material", "item/parametric/bad/material")
	_assert_error(missing_materials, "CONSTRUCTION_PARAMETRIC_MATERIAL_NOT_FOUND", "Compiler accepted missing material")
	var tampered := beam.duplicate(true); tampered["mass_kg"] = float(tampered["mass_kg"]) + 1.0; tampered["checksum"] = InstanceScript.compute_checksum(tampered)
	_assert_error(InstanceScript.validate(tampered), "CONSTRUCTION_PARAMETRIC_MASS_NOT_CONSERVED", "Instance accepted non-conserved mass")
	var raw_tamper := beam.duplicate(true); raw_tamper["mass_kg"] = 1.0
	_assert_error(InstanceScript.validate(raw_tamper), "CONSTRUCTION_PARAMETRIC_MASS_NOT_CONSERVED", "Instance did not reject tamper before checksum")

func _test_catalog_and_persistence() -> void:
	var catalog = CatalogScript.new()
	for material in FixtureScript.materials(): _assert_ok(catalog.publish_material(material), "Material publish failed")
	_assert(int(catalog.get_generation()) == 6, "Catalog material generation mismatch")
	for definition in FixtureScript.all_definitions(): _assert_ok(catalog.publish_definition(definition), "Definition publish failed")
	_assert(int(catalog.get_generation()) == 11, "Catalog definition generation mismatch")
	var replay := catalog.publish_definition(FixtureScript.beam_definition())
	_assert_ok(replay, "Definition replay failed")
	_assert(bool(replay.get("replay", false)), "Definition replay not marked")
	_assert(int(catalog.get_generation()) == 11, "Definition replay advanced generation")
	var gap := FixtureScript.beam_definition(3)
	_assert_error(catalog.publish_definition(gap), "CONSTRUCTION_PARAMETRIC_DEFINITION_VERSION_GAP", "Catalog accepted version gap")
	_assert_ok(catalog.publish_definition(FixtureScript.beam_definition(2)), "Definition v2 publish failed")
	_assert(int(catalog.get_definition("parametric-definition/beam/rectangular-s355")["definition_version"]) == 2, "Catalog latest version mismatch")
	_assert(catalog.get_materials_for_definition(FixtureScript.wall_definition()).size() == 3, "Catalog wall material resolution mismatch")
	var state := catalog.export_state()
	_assert_ok(CatalogScript.validate_state(state), "Catalog state rejected")
	var restored = CatalogScript.new(); _assert_ok(restored.load_state(state), "Catalog state load failed")
	_assert(UtilsScript.canonical_json(restored.export_state()) == UtilsScript.canonical_json(state), "Catalog state roundtrip changed")
	var storage = MemoryStore.new(); _assert_ok(PersistenceScript.save_catalog(storage, catalog), "Catalog persistence save failed")
	var restored2 = CatalogScript.new(); _assert_ok(PersistenceScript.load_catalog(storage, restored2), "Catalog persistence load failed")
	_assert(int(restored2.get_generation()) == int(catalog.get_generation()), "Catalog persistence generation mismatch")
	var tampered := state.duplicate(true); tampered["generation"] = int(tampered["generation"]) + 1
	_assert_error(CatalogScript.validate_state(tampered), "CONSTRUCTION_PARAMETRIC_CATALOG_STATE_CHECKSUM_MISMATCH", "Catalog state accepted tamper")

func _test_projection_fabrication_and_capability_contracts() -> void:
	var beam := FixtureScript.beam_instance("contracts", 2.0)
	var projection_result := ProjectionFactoryScript.create_projection(beam, "Parametric beam", ProjectionScript.container_relation("container/parametric"))
	_assert_ok(projection_result, "Projection creation failed")
	var projection: Dictionary = projection_result["projection"]
	_assert_ok(ProjectionFactoryScript.validate_projection(projection), "Parametric projection rejected")
	_assert(String(projection["components"]["parametric_member"]["checksum"]) == String(beam["checksum"]), "Projection lost member checksum")
	var part_result := ProjectionFactoryScript.create_part_record(beam, "part/parametric/beam/contracts", "frame", [0.0, 1.0, 0.0])
	_assert_ok(part_result, "Parametric part creation failed")
	_assert(float(part_result["part"]["mass_kg"]) == float(beam["mass_kg"]), "Part mass mismatch")
	_assert(String(part_result["part"]["metadata"]["parametric_member_checksum"]) == String(beam["checksum"]), "Part metadata checksum mismatch")
	var recipe_result := FabricationCompilerScript.compile_recipe("fabrication-recipe/parametric/contracts", 1, "Parametric beam", beam)
	_assert_ok(recipe_result, "Parametric recipe compile failed")
	var recipe: Dictionary = recipe_result["recipe"]
	_assert_ok(RecipeScript.validate(recipe), "Parametric recipe rejected")
	_assert(recipe["input_requirements"].size() == 1, "Parametric recipe input count mismatch")
	_assert(int(recipe["input_requirements"][0]["quantity"]) == int(beam["material_usage"][0]["stock_units"]), "Recipe stock quantity mismatch")
	_assert(String(recipe["output_products"][0]["components"]["parametric_member"]["checksum"]) == String(beam["checksum"]), "Recipe output lost member")
	var capability_result := CapabilityCompilerScript.compile(beam, "part/parametric/beam/contracts")
	_assert_ok(capability_result, "Parametric capability compile failed")
	_assert_ok(CapabilityScript.validate(capability_result["capability"]), "Parametric capability rejected")
	_assert(String(capability_result["capability"]["capability_kind"]) == "LOAD_BEARING_MEMBER", "Beam capability kind mismatch")
	_assert(float(capability_result["capability"]["properties"]["mass_kg"]) == float(beam["mass_kg"]), "Capability mass mismatch")

func _test_segmentation_repair_and_store_contracts() -> void:
	var beam := FixtureScript.beam_instance("segment", 6.0)
	var split := SegmenterScript.split("parametric-segmentation/beam/segment", "parametric-repair/beam/segment", beam, [2.0, 4.5], ["parametric-member/beam/segment-a", "parametric-member/beam/segment-b", "parametric-member/beam/segment-c"], ["item/parametric/beam/segment-a", "item/parametric/beam/segment-b", "item/parametric/beam/segment-c"])
	_assert_ok(split, "Parametric split failed")
	_assert_ok(SegmentationPlanScript.validate(split["plan"]), "Segmentation plan rejected")
	_assert_ok(RepairPlanScript.validate(split["repair_plan"]), "Repair plan rejected")
	_assert(split["segments"].size() == 3, "Segment count mismatch")
	_assert(float(split["segments"][0]["geometry"]["length_m"]) == 2.0, "First segment length mismatch")
	_assert(float(split["segments"][1]["geometry"]["length_m"]) == 2.5, "Second segment length mismatch")
	_assert(float(split["segments"][2]["geometry"]["length_m"]) == 1.5, "Third segment length mismatch")
	var total_mass := 0.0
	for segment in split["segments"]: total_mass += float(segment["mass_kg"])
	_assert(is_equal_approx(total_mass, float(beam["mass_kg"])), "Segment mass not conserved")
	var resolved := RepairPlanScript.resolve(split["repair_plan"], split["segments"])
	_assert_ok(resolved, "Parametric repair resolve failed")
	_assert(String(resolved["restored_instance"]["checksum"]) == String(beam["checksum"]), "Repair did not restore parent checksum")
	var missing: Array = Array(split["segments"]).duplicate(true); missing.pop_back()
	_assert_error(RepairPlanScript.resolve(split["repair_plan"], missing), "CONSTRUCTION_PARAMETRIC_REPAIR_SEGMENT_MISSING", "Repair accepted missing segment")
	var bad_cuts := SegmenterScript.split("parametric-segmentation/bad/cuts", "parametric-repair/bad/cuts", beam, [4.0, 2.0], ["parametric-member/bad/a", "parametric-member/bad/b", "parametric-member/bad/c"], ["item/parametric/bad/a", "item/parametric/bad/b", "item/parametric/bad/c"])
	_assert_error(bad_cuts, "INVALID_CONSTRUCTION_PARAMETRIC_CUT_OFFSET", "Segmenter accepted unsorted cuts")
	var store = StoreScript.new(); _assert_ok(store.publish(beam), "Member publish failed")
	var replay := store.publish(beam); _assert_ok(replay, "Member replay failed")
	_assert(bool(replay.get("replay", false)), "Member replay not marked")
	_assert(int(store.get_generation()) == 1, "Member replay advanced generation")
	var conflict := InstanceScript.with_updates(beam, {"provenance": {"source": "conflict"}})
	_assert_error(store.publish(conflict), "CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_CONFLICT", "Store accepted member ID conflict")
	var state := store.export_state(); _assert_ok(StoreScript.validate_state(state), "Member store state rejected")
	var restored = StoreScript.new(); _assert_ok(restored.load_state(state), "Member store load failed")
	_assert(UtilsScript.canonical_json(restored.export_state()) == UtilsScript.canonical_json(state), "Member store roundtrip changed")
	var storage = MemoryStore.new(); _assert_ok(PersistenceScript.save_member_store(storage, store), "Member store persistence save failed")
	var restored2 = StoreScript.new(); _assert_ok(PersistenceScript.load_member_store(storage, restored2), "Member store persistence load failed")
	_assert(String(restored2.get_instance(String(beam["member_instance_id"]))["checksum"]) == String(beam["checksum"]), "Member persistence lost instance")
	_assert_error(store.remove(String(beam["member_instance_id"]), "0".repeat(64)), "CONSTRUCTION_PARAMETRIC_MEMBER_REMOVE_PRECONDITION_MISMATCH", "Store accepted wrong remove checksum")
	_assert_ok(store.remove(String(beam["member_instance_id"]), String(beam["checksum"])), "Member remove failed")
	_assert(int(store.get_generation()) == 2, "Member remove generation mismatch")

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty():
		print("C10 parametric members contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C10 parametric members contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
