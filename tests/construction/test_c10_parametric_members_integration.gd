extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c10_parametric_members_fixture.gd")
const C8FixtureScript = preload("res://tests/construction/fixtures/c8_fabrication_cell_fixture.gd")
const C9FixtureScript = preload("res://tests/construction/fixtures/c9_damage_split_repair_fixture.gd")
const CompilerScript = preload("res://scripts/construction/parametric/construction_parametric_compiler.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const ProjectionFactoryScript = preload("res://scripts/construction/parametric/construction_parametric_projection_factory.gd")
const FabricationCompilerScript = preload("res://scripts/construction/parametric/construction_parametric_fabrication_compiler.gd")
const CapabilityCompilerScript = preload("res://scripts/construction/parametric/construction_parametric_capability_compiler.gd")
const SegmenterScript = preload("res://scripts/construction/parametric/construction_parametric_segmenter.gd")
const RepairPlanScript = preload("res://scripts/construction/parametric/construction_parametric_repair_plan.gd")
const AdapterScript = preload("res://scripts/construction/item_graph/in_memory_construction_item_graph_adapter.gd")
const FabricationCatalogScript = preload("res://scripts/construction/fabrication/construction_fabrication_catalog.gd")
const FabricationQueueScript = preload("res://scripts/construction/fabrication/construction_fabrication_queue_store.gd")
const FabricationProcessScript = preload("res://scripts/construction/fabrication/construction_fabrication_process.gd")
const MachineDefinitionScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_definition.gd")
const MachineCompilerScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_compiler.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BuildStageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")
const DamageProcessScript = preload("res://scripts/construction/damage/construction_damage_process.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_metric_families_and_determinism()
	_test_authoritative_fabrication_to_build_plan()
	_test_damage_split_repair_preserves_parametric_identity()
	_test_segmentation_and_semantic_capabilities()
	_finish()

func _test_metric_families_and_determinism() -> void:
	var beam := FixtureScript.beam_instance("metrics")
	_assert_close(float(beam["geometry"]["volume_m3"]), 0.08, "Beam volume mismatch")
	_assert_close(float(beam["mass_kg"]), 628.0, "Beam mass mismatch")
	_assert_close(float(beam["geometry"]["cross_section_area_m2"]), 0.02, "Beam cross section mismatch")
	_assert(UtilsScript.canonical_json(beam["geometry"]["bounding_box_m"]) == UtilsScript.canonical_json([4, 0.2, 0.1]), "Beam bounding box mismatch")
	var half := FixtureScript.beam_instance("metrics-half", 2.0)
	_assert_close(float(half["mass_kg"]), float(beam["mass_kg"]) * 0.5, "Beam mass did not scale with length")
	_assert_close(float(half["geometry"]["volume_m3"]), float(beam["geometry"]["volume_m3"]) * 0.5, "Beam volume did not scale with length")
	var panel := FixtureScript.panel_instance("metrics")
	_assert_close(float(panel["geometry"]["volume_m3"]), 0.02, "Panel volume mismatch")
	_assert_close(float(panel["mass_kg"]), 54.0, "Panel mass mismatch")
	_assert_close(float(panel["geometry"]["total_thickness_m"]), 0.01, "Panel thickness mismatch")
	var pipe := FixtureScript.pipe_instance("metrics")
	var pipe_area := PI * (0.05 * 0.05 - 0.045 * 0.045)
	_assert_close(float(pipe["geometry"]["cross_section_area_m2"]), pipe_area, "Pipe cross section mismatch")
	_assert_close(float(pipe["geometry"]["volume_m3"]), pipe_area * 3.0, "Pipe volume mismatch")
	_assert_close(float(pipe["mass_kg"]), pipe_area * 3.0 * 7850.0, "Pipe mass mismatch")
	var cable := FixtureScript.cable_instance("metrics")
	var cable_area := PI * 0.005 * 0.005
	_assert_close(float(cable["geometry"]["cross_section_area_m2"]), cable_area, "Cable cross section mismatch")
	_assert_close(float(cable["mass_kg"]), cable_area * 10.0 * 8960.0, "Cable mass mismatch")
	var wall := FixtureScript.wall_instance("metrics")
	_assert_close(float(wall["geometry"]["total_thickness_m"]), 0.2625, "Wall total thickness mismatch")
	_assert_close(float(wall["geometry"]["volume_m3"]), 3.15, "Wall volume mismatch")
	_assert(wall["material_usage"].size() == 3, "Wall material aggregation mismatch")
	var usage_by_material := {}
	for usage in wall["material_usage"]: usage_by_material[String(usage["material_id"])] = usage
	_assert_close(float(usage_by_material["material/concrete-c30"]["volume_m3"]), 1.8, "Concrete wall volume mismatch")
	_assert_close(float(usage_by_material["material/insulation"]["volume_m3"]), 1.2, "Insulation wall volume mismatch")
	_assert_close(float(usage_by_material["material/gypsum"]["volume_m3"]), 0.15, "Gypsum wall volume mismatch")
	var repeat := FixtureScript.wall_instance("metrics")
	_assert(UtilsScript.canonical_json(repeat) == UtilsScript.canonical_json(wall), "Repeated compilation is not deterministic")
	var integral_override := CompilerScript.compile(FixtureScript.beam_definition(), FixtureScript.materials(), {"length_m": 4}, "parametric-member/beam/integral", "item/parametric/beam/integral")
	var float_override := CompilerScript.compile(FixtureScript.beam_definition(), FixtureScript.materials(), {"length_m": 4.0}, "parametric-member/beam/integral", "item/parametric/beam/integral")
	_assert_ok(integral_override, "Integral override compile failed")
	_assert_ok(float_override, "Float override compile failed")
	_assert(UtilsScript.canonical_json(integral_override["instance"]) == UtilsScript.canonical_json(float_override["instance"]), "Int/float override changed compiled instance")

func _test_authoritative_fabrication_to_build_plan() -> void:
	var key := "c10-fabrication"
	var instance := FixtureScript.beam_instance(key, 2.0)
	var recipe_result := FabricationCompilerScript.compile_recipe("fabrication-recipe/parametric-beam", 1, "Parametric S355 beam", instance, 0.05)
	_assert_ok(recipe_result, "Recipe compile failed")
	var recipe: Dictionary = recipe_result["recipe"]
	var graph := C8FixtureScript.machine_item_graph(key)
	var stock_units := int(instance["material_usage"][0]["stock_units"])
	var stock := ProjectionScript.create("item/material/%s/steel-stock" % key, "steel_stock", "Steel stock", stock_units + 5, ProjectionScript.container_relation("container/raw/%s" % key), {"material_id": "material/steel-s355", "batch": "C10"}, 0)
	var graph_items: Array = Array(graph["items"]).duplicate(true); graph_items.append(stock)
	var adapter = AdapterScript.new(); _assert_ok(adapter.setup(graph_items, [graph["snapshot"]]), "Fabrication adapter setup failed")
	var catalog = FabricationCatalogScript.new(); _assert_ok(catalog.setup(), "Fabrication catalog setup failed"); _assert_ok(catalog.publish(recipe), "Parametric recipe publish failed")
	var queue = FabricationQueueScript.new(); _assert_ok(queue.setup(), "Fabrication queue setup failed")
	var process = FabricationProcessScript.new(); _assert_ok(process.setup(adapter, catalog, queue), "Fabrication process setup failed")
	var prefix := "part/fabrication/%s/" % key
	var machine_definition := MachineDefinitionScript.create("fabrication-machine/parametric-cell", [prefix + "controller", prefix + "spindle"], ["bond/fabrication/%s/controller" % key, "bond/fabrication/%s/spindle" % key], "container/fabrication/%s/input" % key, "container/fabrication/%s/output" % key, ["fabrication-recipe/parametric-beam"], ["WORKSTATION"], ["spatial-utility/power"], 2, {"process": "PARAMETRIC_MEMBER"})
	var profile_result := MachineCompilerScript.compile(graph["snapshot"], machine_definition, C8FixtureScript.behavior_profile(key, graph["snapshot"]), C8FixtureScript.powered_spatial_profile("power-%s" % key))
	_assert_ok(profile_result, "Parametric machine profile compile failed")
	var profile: Dictionary = profile_result["profile"]
	var enqueued := process.enqueue_job("fabrication-job/c10/beam", "fabrication-recipe/parametric-beam", 1, profile, [stock], {"member": String(instance["item_instance_id"])}, 900)
	_assert_ok(enqueued, "Parametric fabrication enqueue failed")
	_assert(String(enqueued["job"]["status"]) == "QUEUED", "Parametric job not queued")
	var reserved := process.reserve_job("fabrication-job/c10/beam", profile)
	_assert_ok(reserved, "Parametric input reservation failed")
	_assert(String(adapter.get_item_projection(String(stock["item_instance_id"]))["relation"]["container_id"]) == String(profile["input_container_id"]), "Parametric stock not reserved")
	var work_required := int(queue.get_job("fabrication-job/c10/beam")["work_required"])
	_assert(work_required > 0, "Parametric job work missing")
	_assert_ok(process.advance_job("fabrication-job/c10/beam", profile, work_required, "operation/c10/beam/progress"), "Parametric progress failed")
	var completed := process.complete_job("fabrication-job/c10/beam", profile)
	_assert_ok(completed, "Parametric completion failed")
	var output: Dictionary = adapter.get_item_projection(String(instance["item_instance_id"]))
	_assert(not output.is_empty(), "Parametric fabricated output missing")
	_assert(String(output["relation"]["container_id"]) == String(profile["output_container_id"]), "Parametric output container mismatch")
	_assert(String(output["components"]["parametric_member"]["checksum"]) == String(instance["checksum"]), "Fabrication changed parametric instance")
	_assert(String(output["components"]["fabrication_origin"]["recipe_checksum"]) == String(recipe["checksum"]), "Fabrication provenance missing")
	_assert_ok(ProjectionFactoryScript.validate_projection(output), "Fabricated parametric projection rejected")
	var remaining_stock: Dictionary = adapter.get_item_projection(String(stock["item_instance_id"]))
	_assert(int(remaining_stock["quantity"]) == 5, "Parametric material consumption mismatch")
	var part_result := ProjectionFactoryScript.create_part_record(instance, "part/c10/build/beam", "frame", [0.0, 0.0, 0.0])
	_assert_ok(part_result, "Fabricated parametric part creation failed")
	var target := SnapshotScript.create("construct/c10/beam-frame", "item/c10/beam-frame/root", 0, "OPERATIONAL", [part_result["part"]], [], {"operational": true, "capabilities": []})
	var stage := BuildStageScript.create("stage/c10/beam-frame/operational", 0, "Install parametric beam", "OPERATIONAL", ["part/c10/build/beam"], [], [], ["INSTALL_COMPONENT"])
	var build_plan := BuildPlanScript.create("build-plan/c10/beam-frame", "Parametric beam frame", ProjectionScript.world_relation(), target, [output], [stage])
	_assert_ok(BuildPlanScript.validate(build_plan), "Fabricated parametric member cannot enter C3 BuildPlan")
	_assert(String(build_plan["source_item_projections"][0]["item_instance_id"]) == String(instance["item_instance_id"]), "BuildPlan changed parametric item identity")
	_assert(float(build_plan["target_snapshot"]["parts"][0]["mass_kg"]) == float(instance["mass_kg"]), "BuildPlan part mass mismatch")

func _test_damage_split_repair_preserves_parametric_identity() -> void:
	var key := "c10-parametric"
	var source := C9FixtureScript.snapshot(key)
	var instance_result := CompilerScript.compile(FixtureScript.beam_definition(), FixtureScript.materials(), {"length_m": 2.0}, "parametric-member/bridge/%s/arm" % key, "item/bridge/%s/arm" % key, {"source": "C10_C9_COMPATIBILITY"})
	_assert_ok(instance_result, "Damage parametric instance compile failed")
	var instance: Dictionary = instance_result["instance"]
	var next_parts: Array = []
	for part in source["parts"]:
		if String(part["part_id"]) == "part/bridge/%s/arm" % key:
			var metadata := Dictionary(part["metadata"]).duplicate(true); metadata["parametric_member_checksum"] = String(instance["checksum"]); metadata["geometry"] = Dictionary(instance["geometry"]).duplicate(true)
			next_parts.append(PartScript.create(String(part["part_id"]), String(part["item_instance_id"]), "BEAM", String(part["role"]), float(instance["mass_kg"]), Array(part["local_position_m"]), metadata))
		else: next_parts.append(Dictionary(part).duplicate(true))
	var parametric_snapshot := SnapshotScript.create(String(source["construct_id"]), String(source["root_item_instance_id"]), int(source["state_revision"]), String(source["build_state"]), next_parts, Array(source["bonds"]).duplicate(true), Dictionary(source["compiled_facets"]).duplicate(true))
	var items := C9FixtureScript.items(key)
	var next_items: Array = []
	for item in items:
		if String(item["item_instance_id"]) == String(instance["item_instance_id"]):
			var components := Dictionary(item["components"]).duplicate(true); components["parametric_member"] = instance.duplicate(true)
			next_items.append(ProjectionScript.create(String(item["item_instance_id"]), String(item["definition_id"]), String(item["display_name"]), int(item["quantity"]), Dictionary(item["relation"]), components, int(item["revision"])))
		else: next_items.append(Dictionary(item).duplicate(true))
	var adapter = AdapterScript.new(); _assert_ok(adapter.setup(next_items, [parametric_snapshot]), "Damage adapter setup failed")
	var process = DamageProcessScript.new(); _assert_ok(process.setup(adapter), "Damage process setup failed")
	var damaged := process.apply_damage("plan/c10/damage", "operation/c10/damage", C9FixtureScript.request(key, parametric_snapshot))
	_assert_ok(damaged, "Parametric damage/split failed")
	var split_item: Dictionary = adapter.get_item_projection(String(instance["item_instance_id"]))
	_assert(String(split_item["relation"]["assembly_id"]) == "construct/bridge/%s/split-arm" % key, "Parametric member not rebound to split construct")
	_assert(String(split_item["components"]["parametric_member"]["checksum"]) == String(instance["checksum"]), "Damage changed parametric checksum")
	_assert(String(split_item["components"]["condition"]) == "INTACT", "Unhit parametric member condition changed")
	var repaired := process.apply_repair("plan/c10/repair", "operation/c10/repair", damaged["repair_plan"])
	_assert_ok(repaired, "Parametric repair failed")
	var restored_item: Dictionary = adapter.get_item_projection(String(instance["item_instance_id"]))
	_assert(String(restored_item["relation"]["assembly_id"]) == String(parametric_snapshot["construct_id"]), "Repair did not return parametric item")
	_assert(String(restored_item["components"]["parametric_member"]["checksum"]) == String(instance["checksum"]), "Repair changed parametric instance")
	var restored_snapshot: Dictionary = adapter.get_construct_snapshot(String(parametric_snapshot["construct_id"]))
	var restored_arm := {}
	for part in restored_snapshot["parts"]:
		if String(part["item_instance_id"]) == String(instance["item_instance_id"]): restored_arm = part
	_assert(not restored_arm.is_empty(), "Repaired parametric part missing")
	_assert(float(restored_arm["mass_kg"]) == float(instance["mass_kg"]), "Repair changed parametric part mass")
	_assert(String(restored_arm["metadata"]["parametric_member_checksum"]) == String(instance["checksum"]), "Repair changed parametric part provenance")

func _test_segmentation_and_semantic_capabilities() -> void:
	var cases := [
		[FixtureScript.beam_instance("cap-beam"), "LOAD_BEARING_MEMBER"],
		[FixtureScript.panel_instance("cap-panel"), "STRUCTURAL_PANEL"],
		[FixtureScript.pipe_instance("cap-pipe"), "FLUID_CONDUIT"],
		[FixtureScript.cable_instance("cap-cable"), "SIGNAL_CONDUIT"],
		[FixtureScript.wall_instance("cap-wall"), "ENCLOSURE_ASSEMBLY"],
	]
	for index in range(cases.size()):
		var instance: Dictionary = cases[index][0]
		var compiled := CapabilityCompilerScript.compile(instance, "part/c10/capability/%d" % index)
		_assert_ok(compiled, "Parametric capability compile failed")
		_assert(String(compiled["capability"]["capability_kind"]) == String(cases[index][1]), "Parametric capability mapping mismatch")
		_assert(String(compiled["capability"]["properties"]["member_instance_id"]) == String(instance["member_instance_id"]), "Capability lost member identity")
	var beam := FixtureScript.beam_instance("split-integration", 8.0)
	var split := SegmenterScript.split("parametric-segmentation/integration/beam", "parametric-repair/integration/beam", beam, [3.0, 5.0], ["parametric-member/integration/beam-a", "parametric-member/integration/beam-b", "parametric-member/integration/beam-c"], ["item/parametric/integration/beam-a", "item/parametric/integration/beam-b", "item/parametric/integration/beam-c"])
	_assert_ok(split, "Integration segmentation failed")
	var lengths: Array = []
	for segment in split["segments"]: lengths.append(float(segment["geometry"]["length_m"]))
	_assert(lengths == [3.0, 2.0, 3.0], "Integration segment lengths mismatch")
	var mass := 0.0; var volume := 0.0
	for segment in split["segments"]:
		mass += float(segment["mass_kg"]); volume += float(segment["geometry"]["volume_m3"])
	_assert_close(mass, float(beam["mass_kg"]), "Integration segment mass not conserved")
	_assert_close(volume, float(beam["geometry"]["volume_m3"]), "Integration segment volume not conserved")
	var reverse_segments: Array = Array(split["segments"]).duplicate(true); reverse_segments.reverse()
	var restored := RepairPlanScript.resolve(split["repair_plan"], reverse_segments)
	_assert_ok(restored, "Repair resolution depended on segment order")
	_assert(UtilsScript.canonical_json(restored["restored_instance"]) == UtilsScript.canonical_json(beam), "Parametric repair did not restore byte-semantic parent")
	var replay := SegmenterScript.split("parametric-segmentation/integration/beam", "parametric-repair/integration/beam", beam, [3, 5.0], ["parametric-member/integration/beam-a", "parametric-member/integration/beam-b", "parametric-member/integration/beam-c"], ["item/parametric/integration/beam-a", "item/parametric/integration/beam-b", "item/parametric/integration/beam-c"])
	_assert_ok(replay, "Segmentation canonical replay failed")
	_assert(UtilsScript.canonical_json(replay["plan"]) == UtilsScript.canonical_json(split["plan"]), "Segmentation int/float replay changed plan")

func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _assert_close(actual: float, expected: float, message: String) -> void:
	_assert(is_equal_approx(actual, expected) or absf(actual - expected) <= 0.0000001 * maxf(1.0, absf(expected)), "%s: actual=%s expected=%s" % [message, actual, expected])
func _finish() -> void:
	if failures.is_empty():
		print("C10 parametric members integration: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C10 parametric members integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
