extends SceneTree

const Mapping = preload("res://scripts/research/ecology/v2/matter_resource_mapping_v1.gd")
const Catalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const Batch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_R2_FAIL " + message)

func _batch(batch_id: String, total_mass_kg: float, components: Array) -> Dictionary:
	return Batch.create({
		"batch_id": batch_id,
		"container_id": "container/a10-r2",
		"source_body_id": "body/moon",
		"source_operation_id": "operation/a10-r2",
		"total_mass_kg": total_mass_kg,
		"bulk_volume_m3": 0.000001,
		"composition": Composition.create(components),
		"temperature_k": 273.15,
	})

func _run() -> void:
	var catalog := Catalog.default_catalog()
	_check(bool(Catalog.validate(catalog).get("success", false)), "default production Matter catalog")

	var empty_map := Mapping.create(catalog, "eco-map/empty", [])
	_check(not empty_map.is_empty() and Mapping.validate(empty_map, catalog).is_empty(), "empty mapping is valid and explicit")

	var mixed := _batch("batch/a10-r2-mixed", 0.001, [
		{"material_id": "matter/regolith-loose", "mass_fraction": 0.75},
		{"material_id": "matter/water-ice", "mass_fraction": 0.25},
	])
	_check(bool(Batch.validate(mixed).get("success", false)), "mixed production batch fixture")

	var no_semantics := Mapping.admit_material_batch(mixed, catalog, empty_map)
	_check(bool(no_semantics.get("success", false)), "empty map still admits accounting")
	if bool(no_semantics.get("success", false)):
		var a: Dictionary = no_semantics["admission"]
		_check(a["resources"] == {"water_mg": 0, "nutrient_mg": 0, "organic_mg": 0}, "empty map mints no ECO resources")
		_check(a["mapped_mass_mg"] == 0 and a["unmapped_mass_mg"] == 1000, "all mass stays explicitly unmapped")
		_check(a["mapped_mass_mg"] + a["unmapped_mass_mg"] == a["total_mass_mg"], "empty map conserves mass")

	var water_map := Mapping.create(catalog, "eco-map/explicit-water-fixture", [
		{"material_id": "matter/water-ice", "resource": "water_mg"},
	])
	_check(not water_map.is_empty() and Mapping.validate(water_map, catalog).is_empty(), "caller can explicitly map a known material")
	var admitted := Mapping.admit_material_batch(mixed, catalog, water_map)
	_check(bool(admitted.get("success", false)), "explicit mapped/unmapped batch admission")
	if bool(admitted.get("success", false)):
		var a: Dictionary = admitted["admission"]
		_check(a["total_mass_mg"] == 1000, "kg to mg is exact")
		_check(a["resources"]["water_mg"] == 250, "explicit water fixture maps only its material mass")
		_check(a["resources"]["nutrient_mg"] == 0 and a["resources"]["organic_mg"] == 0, "nutrient and organic are not guessed")
		_check(a["unmapped_materials"].size() == 1 and a["unmapped_materials"][0]["material_id"] == "matter/regolith-loose" and a["unmapped_materials"][0]["mass_mg"] == 750, "regolith remains unmapped")
		_check(a["mapped_mass_mg"] == 250 and a["unmapped_mass_mg"] == 750, "mixed mass accounting exact")
		_check(a["mapped_mass_mg"] + a["unmapped_mass_mg"] == a["total_mass_mg"], "mixed batch conserves mass")
		_check(String(a["accounting_hash"]).length() == 64, "admission accounting sealed")

	var unknown := Mapping.create(catalog, "eco-map/unknown", [
		{"material_id": "matter/biological-nutrient-that-does-not-exist", "resource": "nutrient_mg"},
	])
	_check(unknown.is_empty(), "unknown production material cannot become nutrient")

	var duplicate := Mapping.create(catalog, "eco-map/ambiguous", [
		{"material_id": "matter/water-ice", "resource": "water_mg"},
		{"material_id": "matter/water-ice", "resource": "organic_mg"},
	])
	_check(duplicate.is_empty(), "same material cannot mean two ECO resources")

	var stale_map := water_map.duplicate(true)
	stale_map["catalog_hash"] = "0".repeat(64)
	_check(Mapping.validate(stale_map, catalog) == "A10_R2_CATALOG_HASH", "mapping is bound to exact catalog hash")

	var half_mg := _batch("batch/a10-r2-half-mg", 0.000001, [
		{"material_id": "matter/regolith-loose", "mass_fraction": 0.5},
		{"material_id": "matter/water-ice", "mass_fraction": 0.5},
	])
	_check(bool(Batch.validate(half_mg).get("success", false)), "fractional-mg production batch is otherwise valid")
	var rejected_rounding := Mapping.admit_material_batch(half_mg, catalog, water_map)
	_check(not bool(rejected_rounding.get("success", false)) and rejected_rounding.get("error") == "A10_R2_COMPONENT_MASS_NOT_EXACT_MG", "hidden component rounding is rejected")

	var unknown_batch := _batch("batch/a10-r2-unknown-material", 0.001, [
		{"material_id": "matter/not-in-catalog", "mass_fraction": 1.0},
	])
	_check(bool(Batch.validate(unknown_batch).get("success", false)), "batch schema alone permits catalog-external material identity")
	var rejected_unknown_batch := Mapping.admit_material_batch(unknown_batch, catalog, empty_map)
	_check(not bool(rejected_unknown_batch.get("success", false)) and rejected_unknown_batch.get("error") == "A10_R2_BATCH_MATERIAL_NOT_IN_CATALOG", "R2 enforces catalog membership")

	print("EVO_ARCH2_A10_R2_RESOURCE_MAPPING checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_R2_RESOURCE_MAPPING PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_R2_FAILURE " + failure)
		quit(1)
