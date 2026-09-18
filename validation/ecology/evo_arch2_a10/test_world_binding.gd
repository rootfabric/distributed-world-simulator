extends SceneTree

const Binding = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const Cell = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const Brick = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Sample = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const Query = preload("res://scripts/simulation/matter/query/matter_query_result.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
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

func _run() -> void:
	var cell := Cell.create("u", "i", "surface", "grid", 1, "root")
	_check(bool(Cell.validate(cell).get("success", false)), "production cell fixture")
	var brick := Brick.create(cell, 0, 0, 0, 0)
	_check(bool(Brick.validate(brick).get("success", false)), "production brick fixture")
	var composition := Composition.create([
		{"material_id": "material/soil", "mass_fraction": 0.8},
		{"material_id": "material/water", "mass_fraction": 0.2},
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
	var selector := {"kind": "CHUNK_SET", "partition_prefix": "", "chunk_ids": [cell["cell_id"]]}
	var region := Region.create("region/a", "u", "i", "surface", "octree", 1, selector, "node/a", 3, "ACTIVE", 4)
	_check(bool(Region.validate(region).get("success", false)), "production region fixture")
	var cursor := {
		"entity_id": "organism/a",
		"region_id": "region/a",
		"owner_id": "node/a",
		"owner_epoch": 3,
		"revision": 8,
		"clock": 21,
		"ecology_step": 5,
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
	var excluded_selector := {"kind": "CHUNK_SET", "partition_prefix": "", "chunk_ids": ["other/cell"]}
	var excluded_region := Region.create("region/a", "u", "i", "surface", "octree", 1, excluded_selector, "node/a", 3, "ACTIVE", 6)
	var excluded := Binding.bind_matter_site(query, excluded_region, cursor)
	_check(not bool(excluded.get("success", false)) and excluded.get("error") == "A10_REGION_SELECTOR_EXCLUDES_CELL", "region selector bounds Matter site")

	var request := DamageRequest.create(
		"damage/a10", "construct/tree", "c".repeat(64), "part/trunk", [], [],
		{"part/leaf": "DEGRADED", "part/root": "DESTROYED"}
	)
	_check(bool(DamageRequest.validate(request).get("success", false)), "production damage request fixture")
	var snapshot := Snapshot.create("construct/tree", "item/root", 1, "OPERATIONAL", [], [], {})
	_check(bool(Snapshot.validate(snapshot).get("success", false)), "production construct snapshot fixture")
	var repair := RepairPlan.create("repair/a10", "damage/a10", snapshot, [], [], [], [], request["checksum"])
	_check(bool(RepairPlan.validate(repair).get("success", false)), "production repair plan fixture")
	var record := DamageRecord.create("damage/a10", request["checksum"], "d".repeat(64), repair, [], 9)
	_check(bool(DamageRecord.validate(record).get("success", false)), "production applied damage record fixture")
	var projected := Binding.project_construction_damage(request, record, {
		"part/leaf": "module.leaf",
		"part/root": "module.root",
	})
	_check(bool(projected.get("success", false)), "project applied C9 damage into ECO module event")
	if bool(projected.get("success", false)):
		var event: Dictionary = projected["event"]
		_check(event["events"].size() == 2, "two affected body modules projected")
		_check(event["events"][0]["part_id"] == "part/leaf" and event["events"][0]["severity_milli"] == 500, "degraded part projection")
		_check(event["events"][1]["part_id"] == "part/root" and event["events"][1]["severity_milli"] == 1000, "destroyed part projection")
		_check(String(event["binding_hash"]).length() == 64, "damage projection sealed")

	var missing_map := Binding.project_construction_damage(request, record, {"part/leaf": "module.leaf"})
	_check(not bool(missing_map.get("success", false)) and missing_map.get("error") == "A10_DAMAGE_PART_UNBOUND", "unknown affected part fails closed")
	var duplicate_map := Binding.project_construction_damage(request, record, {
		"part/leaf": "module.same",
		"part/root": "module.same",
	})
	_check(not bool(duplicate_map.get("success", false)) and duplicate_map.get("error") == "A10_MODULE_BINDING_NOT_ONE_TO_ONE", "part-module mapping is one-to-one")
	var repaired_record := DamageRecord.mark_repaired(record, 10)
	_check(bool(DamageRecord.validate(repaired_record).get("success", false)), "repaired production record fixture")
	var replay_damage := Binding.project_construction_damage(request, repaired_record, {
		"part/leaf": "module.leaf",
		"part/root": "module.root",
	})
	_check(not bool(replay_damage.get("success", false)) and replay_damage.get("error") == "A10_DAMAGE_RECORD_NOT_APPLIED", "repair does not replay biological damage")
	var other_request := DamageRequest.create(
		"damage/a10", "construct/tree", "e".repeat(64), "part/trunk", [], [],
		{"part/leaf": "DEGRADED", "part/root": "DESTROYED"}
	)
	var mismatch := Binding.project_construction_damage(other_request, record, {
		"part/leaf": "module.leaf",
		"part/root": "module.root",
	})
	_check(not bool(mismatch.get("success", false)) and mismatch.get("error") == "A10_DAMAGE_REQUEST_RECORD_MISMATCH", "forged request cannot reuse applied record")

	print("EVO_ARCH2_A10_WORLD_BINDING checks=%d failed=%d" % [checks, failures.size()])
	if not failures.is_empty():
		for failure in failures:
			print("A10_FAILURE " + failure)
		quit(1)
	else:
		print("EVO_ARCH2_A10_WORLD_BINDING PASS")
		quit(0)
