extends SceneTree

const Binding = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Cell = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const Brick = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Sample = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const Query = preload("res://scripts/simulation/matter/query/matter_query_result.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const DamageRecord = preload("res://scripts/construction/damage/construction_damage_record.gd")
const RepairPlan = preload("res://scripts/construction/damage/construction_repair_plan.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_FAIL " + message)

func _body_modules() -> Array:
	var modules: Array = [Body.root()]
	var leaf := {
		"id": "m000001", "parent": "m000000", "role": "collector",
		"start_mm": [0, 0, 0], "end_mm": [0, 100, 0],
		"radius_mm": 1, "area_mm2": 100, "reach_mm": 0, "cost": Body.stock(),
	}
	leaf["cost"] = Body.cost(leaf)
	modules.append(leaf)
	var root := {
		"id": "m000002", "parent": "m000000", "role": "absorber",
		"start_mm": [0, 0, 0], "end_mm": [0, -100, 0],
		"radius_mm": 1, "area_mm2": 0, "reach_mm": 100, "cost": Body.stock(),
	}
	root["cost"] = Body.cost(root)
	modules.append(root)
	return modules

func _run() -> void:
	var cell := Cell.create("u", "i", "surface", "grid", 1, "root")
	_check(bool(Cell.validate(cell).get("success", false)), "production cell fixture")
	var brick := Brick.create(cell, 0, 0, 0, 0)
	_check(bool(Brick.validate(brick).get("success", false)), "production brick fixture")
	var composition := Composition.create([
		{"material_id": "matter/regolith-loose", "mass_fraction": 0.8},
		{"material_id": "matter/water-ice", "mass_fraction": 0.2},
	])
	_check(bool(Composition.validate(composition).get("success", false)), "production composition fixture")
	var sample := Sample.create(-0.25, 1.0, 1350.0, composition, 0.9, 289.5, 0.35, ["matter-state/solid"])
	_check(bool(Sample.validate(sample).get("success", false)), "production matter sample fixture")
	var query := Query.create({
		"query_id": "matter-query/a10",
		"body_id": "body/moon",
		"body_frame_id": "frame/moon",
		"body_definition_hash": "a".repeat(64),
		"grid_profile_hash": "b".repeat(64),
		"generator_version": "1.0.0",
		"generator_seed": 7,
		"local_position_m": Vector3(12.5, -0.25, 8.0),
		"requested_level": 0,
		"source": "MATERIALIZED_BRICK",
		"cell_address": cell,
		"brick_address": brick,
		"sample_lattice_index": [0, 0, 0],
		"state_revision": 11,
		"sample": sample,
	})
	_check(bool(Query.validate(query).get("success", false)), "production matter query fixture")
	var selector := {"kind": "GLOBAL_SPACE", "partition_prefix": "", "chunk_ids": []}
	var region := Region.create("region/a", "u", "i", "surface", "octree", 1, selector, "node/a", 3, "ACTIVE", 4)
	_check(bool(Region.validate(region).get("success", false)), "production region fixture")
	var cursor := {
		"entity_id": "organism/a", "region_id": "region/a", "owner_id": "node/a",
		"owner_epoch": 3, "revision": 8, "clock": 21, "ecology_step": 5,
	}
	var bound := Binding.bind_matter_site(query, region, cursor)
	_check(bool(bound.get("success", false)), "bind current-main Matter to ECO site")
	if bool(bound.get("success", false)):
		var site: Dictionary = bound["binding"]
		_check(site["resource_stock_authority"] == "NOT_DERIVED_FROM_POINT_SAMPLE", "point sample cannot mint ecological stock")
		_check(not site.has("water_mg") and not site.has("nutrient_mg") and not site.has("organic_mg"), "no invented resource stock fields")
		_check(site["physical_sample"]["temperature_k"] == 289.5 and site["physical_sample"]["porosity_ratio"] == 0.35, "physical sample preserved")
		_check(String(site["binding_hash"]).length() == 64, "float-bearing production binding has canonical hash")
		_check(site["cell_id"] == cell["cell_id"] and site["matter_state_revision"] == 11, "Matter provenance preserved")

	var stale_owner := cursor.duplicate(true)
	stale_owner["owner_id"] = "node/b"
	var stale_result := Binding.bind_matter_site(query, region, stale_owner)
	_check(not bool(stale_result.get("success", false)) and stale_result.get("error") == "A10_CURSOR_OWNER_MISMATCH", "stale owner fails closed")
	var stale_epoch := cursor.duplicate(true)
	stale_epoch["owner_epoch"] = 2
	var epoch_result := Binding.admit_cursor(stale_epoch, region)
	_check(not bool(epoch_result.get("success", false)) and epoch_result.get("error") == "A10_CURSOR_EPOCH_MISMATCH", "stale epoch fails closed")
	var dormant := Region.create("region/a", "u", "i", "surface", "octree", 1, selector, "node/a", 3, "DORMANT", 5)
	var dormant_result := Binding.admit_cursor(cursor, dormant)
	_check(not bool(dormant_result.get("success", false)) and dormant_result.get("error") == "A10_REGION_NOT_EXECUTABLE", "dormant region cannot execute ecology")
	var partition_selector := {"kind": "CHUNK_SET", "partition_prefix": "", "chunk_ids": [cell["cell_id"]]}
	var partition_region := Region.create("region/a", "u", "i", "surface", "octree", 1, partition_selector, "node/a", 3, "ACTIVE", 6)
	var partition_result := Binding.bind_matter_site(query, partition_region, cursor)
	_check(not bool(partition_result.get("success", false)) and partition_result.get("error") == "A10_REGION_SELECTOR_UNSUPPORTED", "partition-specific Matter membership is not guessed from cell/chunk strings")

	var trunk := Part.create("part/trunk", "item/trunk", "BIO_PROXY", "support", 1.0, [0.0, 0.0, 0.0])
	var leaf_part := Part.create("part/leaf", "item/leaf", "BIO_PROXY", "collector", 0.2, [0.0, 1.0, 0.0])
	var root_part := Part.create("part/root", "item/root-part", "BIO_PROXY", "absorber", 0.3, [0.0, -1.0, 0.0])
	var source_snapshot := Snapshot.create("construct/tree", "item/tree-root", 1, "OPERATIONAL", [trunk, leaf_part, root_part], [], {})
	_check(bool(Snapshot.validate(source_snapshot).get("success", false)), "production source construct snapshot fixture")
	var request := DamageRequest.create(
		"damage/a10", "construct/tree", source_snapshot["checksum"], "part/trunk", [], [],
		{"part/leaf": "DEGRADED", "part/root": "DESTROYED"}
	)
	_check(bool(DamageRequest.validate(request).get("success", false)), "production damage request fixture")
	var target_snapshot := Snapshot.create("construct/tree", "item/tree-root", 2, "DAMAGED", [trunk, leaf_part], [], {})
	_check(bool(Snapshot.validate(target_snapshot).get("success", false)), "production target construct snapshot fixture")
	var repair := RepairPlan.create("repair/a10", "damage/a10", target_snapshot, [], [], [], [], request["checksum"])
	_check(bool(RepairPlan.validate(repair).get("success", false)), "production repair plan fixture")
	var record := DamageRecord.create("damage/a10", request["checksum"], "d".repeat(64), repair, [], 9)
	_check(bool(DamageRecord.validate(record).get("success", false)), "production applied damage record fixture")
	var body_modules := _body_modules()
	_check(Body.validate(body_modules).is_empty(), "real ECO BodyGraph fixture")
	var mapping := {"part/leaf": "m000001", "part/root": "m000002"}
	var projected := Binding.project_construction_damage(request, record, source_snapshot, body_modules, mapping, record["checksum"])
	_check(bool(projected.get("success", false)), "project applied C9 damage into existing ECO body modules")
	if bool(projected.get("success", false)):
		var event: Dictionary = projected["event"]
		_check(event["events"].size() == 2, "two affected body modules projected")
		_check(event["events"][0]["part_id"] == "part/leaf" and event["events"][0]["module_id"] == "m000001" and event["events"][0]["severity_milli"] == 500, "degraded part projection")
		_check(event["events"][1]["part_id"] == "part/root" and event["events"][1]["module_id"] == "m000002" and event["events"][1]["severity_milli"] == 1000, "destroyed part projection")
		_check(String(event["body_hash"]).length() == 64 and String(event["binding_hash"]).length() == 64, "damage projection sealed to body")

	var bad_anchor := Binding.project_construction_damage(request, record, source_snapshot, body_modules, mapping, "0".repeat(64))
	_check(not bool(bad_anchor.get("success", false)) and bad_anchor.get("error") == "A10_DAMAGE_RECORD_ANCHOR", "damage record requires external trusted checksum")
	var missing_map := Binding.project_construction_damage(request, record, source_snapshot, body_modules, {"part/leaf": "m000001"}, record["checksum"])
	_check(not bool(missing_map.get("success", false)) and missing_map.get("error") == "A10_DAMAGE_PART_UNBOUND", "unknown affected part fails closed")
	var duplicate_map := Binding.project_construction_damage(request, record, source_snapshot, body_modules, {"part/leaf": "m000001", "part/root": "m000001"}, record["checksum"])
	_check(not bool(duplicate_map.get("success", false)) and duplicate_map.get("error") == "A10_MODULE_BINDING_NOT_ONE_TO_ONE", "part-module mapping is one-to-one")
	var unknown_module := Binding.project_construction_damage(request, record, source_snapshot, body_modules, {"part/leaf": "m000001", "part/root": "m999999"}, record["checksum"])
	_check(not bool(unknown_module.get("success", false)) and unknown_module.get("error") == "A10_MODULE_BINDING_UNKNOWN", "mapping cannot target nonexistent ECO module")
	var extraneous_part := Binding.project_construction_damage(request, record, source_snapshot, body_modules, {"part/leaf": "m000001", "part/root": "m000002", "part/ghost": "m000000"}, record["checksum"])
	_check(not bool(extraneous_part.get("success", false)) and extraneous_part.get("error") == "A10_PART_BINDING_UNKNOWN_SOURCE", "mapping cannot target nonexistent source part")

	var other_source := Snapshot.create("construct/tree", "item/tree-root", 2, "OPERATIONAL", [trunk, leaf_part, root_part], [], {})
	var wrong_source := Binding.project_construction_damage(request, record, other_source, body_modules, mapping, record["checksum"])
	_check(not bool(wrong_source.get("success", false)) and wrong_source.get("error") == "A10_DAMAGE_SOURCE_SNAPSHOT_MISMATCH", "request is bound to exact source snapshot")
	var repaired_record := DamageRecord.mark_repaired(record, 10)
	_check(bool(DamageRecord.validate(repaired_record).get("success", false)), "repaired production record fixture")
	var replay_damage := Binding.project_construction_damage(request, repaired_record, source_snapshot, body_modules, mapping, repaired_record["checksum"])
	_check(not bool(replay_damage.get("success", false)) and replay_damage.get("error") == "A10_DAMAGE_RECORD_NOT_APPLIED", "repair does not replay biological damage")
	var other_request := DamageRequest.create(
		"damage/a10", "construct/tree", source_snapshot["checksum"], "part/trunk", [], [],
		{"part/leaf": "DESTROYED", "part/root": "DESTROYED"}
	)
	var mismatch := Binding.project_construction_damage(other_request, record, source_snapshot, body_modules, mapping, record["checksum"])
	_check(not bool(mismatch.get("success", false)) and mismatch.get("error") == "A10_DAMAGE_REQUEST_RECORD_MISMATCH", "forged request cannot reuse applied record")

	print("EVO_ARCH2_A10_WORLD_BINDING checks=%d failed=%d" % [checks, failures.size()])
	if not failures.is_empty():
		for failure in failures:
			print("A10_FAILURE " + failure)
		quit(1)
	else:
		print("EVO_ARCH2_A10_WORLD_BINDING PASS")
		quit(0)
