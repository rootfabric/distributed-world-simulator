extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P4 Placement + Environment tests.
# Runner: Godot headless --script; prints checks/failed counts and PASS/FAIL.
# Coverage:
#   1. every placement preset generator produces entries that make the
#      manifest pass Manifest.validate (canonical validity);
#   2. grid / zone_seeded_random are deterministic (same seed -> same entries);
#      different seed still yields valid random placements;
#   3. random positions lie INSIDE their claimed zone (canonical band mapping);
#   4. common_garden places every founder into ONE zone;
#   5. environment patches: unknown field / unknown zone / out-of-bounds stock
#      rejected; a valid patch yields a NEW manifest with a different hash and
#      leaves the source manifest unchanged;
#   6. controller snapshot after initialize carries presentation views for
#      every placed founder (positions match the placement entries).

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const PlacementPlan = preload("res://scripts/ecology/workbench/placement_plan_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P4_FAIL " + message)

func _program() -> Dictionary:
	return {
		"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 4,
		"rules": [
			P.rule("r1", [
				P.action("extend", "support", [0, 100, 0], 10),
				P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
			]),
		],
	}

func _manifest() -> Dictionary:
	# 4x4 field (16 cells) with 3 zones in contiguous bands:
	# cells 0-5 -> zone/wet, 6-10 -> zone/dry, 11-15 -> zone/dark
	# (band mapping: zone = min(2, cell * 3 / 16)).
	var founder := Genome.create(_program(), "founder-a")
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p4",
		"seed": 20260920,
		"horizon_ticks": 64,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": null, "genome": founder},
			{"founder_id": "founder/b", "biological_hash": null, "genome": founder.duplicate(true)},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 4, "depth": 4},
			"zones": [
				{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
				{"id": "zone/dry", "water_mg": 50000, "light": 900, "temperature": 600, "nutrient_mg": 100, "organic_mg": 0},
				{"id": "zone/dark", "water_mg": 20000, "light": 100, "temperature": 450, "nutrient_mg": 50, "organic_mg": 0},
			],
		},
		"placement": {
			"entries": [
				{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]},
				{"founder_ref": "founder/b", "zone_id": "zone/dry", "position_mm": [2500, 0, 1500]},
			],
		},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}

func _with_placement(manifest: Dictionary, entries: Array) -> Dictionary:
	var next := manifest.duplicate(true)
	next.placement.entries = entries
	return next

func _run() -> void:
	var manifest := _manifest()
	_check(Manifest.validate(manifest) == "", "base manifest is valid")

	# --- 1. every preset generates manifest-valid placement -------------------
	for preset in PlacementPlan.PRESETS:
		var generated: Dictionary = PlacementPlan.generate(manifest, preset)
		_check(bool(generated.get("success", false)), "preset %s generates: %s" % [preset, str(generated.get("error", ""))])
		if not bool(generated.get("success", false)):
			continue
		var with_placement := _with_placement(manifest, generated.entries)
		_check(Manifest.validate(with_placement) == "", "preset %s placement passes Manifest.validate" % preset)
		_check(not generated.entries.is_empty(), "preset %s produces non-empty entries" % preset)

	# --- 2. determinism: same seed -> same entries -----------------------------
	for preset in ["grid", "zone_seeded_random", "mixed"]:
		var first: Dictionary = PlacementPlan.generate(manifest, preset)
		var second: Dictionary = PlacementPlan.generate(_manifest(), preset)
		_check(first.entries == second.entries, "preset %s deterministic (same seed -> same entries)" % preset)
	var reseeded := _manifest()
	reseeded.seed = 20260921
	var random_other: Dictionary = PlacementPlan.generate(reseeded, "zone_seeded_random")
	_check(bool(random_other.get("success", false)), "zone_seeded_random with different seed still valid")
	_check(Manifest.validate(_with_placement(reseeded, random_other.entries)) == "", "different-seed random placement passes Manifest.validate")

	# --- 3. random positions lie inside their claimed zone ---------------------
	var random_entries: Array = PlacementPlan.generate(manifest, "zone_seeded_random").entries
	var environment: Dictionary = manifest.environment
	for entry in random_entries:
		_check(
			PlacementPlan.zone_id_at(environment, entry.position_mm) == String(entry.zone_id),
			"random position %s lies inside zone %s" % [str(entry.position_mm), entry.zone_id]
		)
		_check(FieldContract.valid_footprint(
			environment.spatial.origin_mm, environment.spatial.cell_size_mm,
			environment.spatial.width, environment.spatial.depth),
			"footprint remains canonical"
		)

	# --- 4. common_garden -> one zone -----------------------------------------
	var garden: Array = PlacementPlan.generate(manifest, "common_garden").entries
	var garden_zones := {}
	for entry in garden:
		garden_zones[entry.zone_id] = true
	_check(garden_zones.size() == 1, "common_garden places all founders into ONE zone (%s)" % str(garden_zones.keys()))
	_check(garden.size() == manifest.founders.size(), "common_garden places every founder once")
	var garden_positions := {}
	for entry in garden:
		garden_positions[str(entry.position_mm)] = true
	_check(garden_positions.size() == 1, "common_garden founders share one canonical position")

	# --- 5. environment patch validation (fail-closed) -------------------------
	var bad_field := EnvironmentPatch.patch("zone/wet", "ph", 5)
	_check(not EnvironmentPatch.validate_patch(manifest, bad_field).is_empty(), "patch with unknown field rejected")
	var bad_zone := EnvironmentPatch.patch("zone/ghost", "water_mg", 5)
	_check(not EnvironmentPatch.validate_patch(manifest, bad_zone).is_empty(), "patch with unknown zone rejected")
	var negative := EnvironmentPatch.patch("zone/wet", "water_mg", -1)
	_check(not EnvironmentPatch.validate_patch(manifest, negative).is_empty(), "patch with negative stock rejected")
	var over_max := EnvironmentPatch.patch("zone/wet", "water_mg", Manifest.CELL_CAPACITY_MG + 1)
	_check(not EnvironmentPatch.validate_patch(manifest, over_max).is_empty(), "patch with out-of-bounds stock rejected")
	var bad_signal := EnvironmentPatch.patch("zone/dry", "light", -50)
	_check(not EnvironmentPatch.validate_patch(manifest, bad_signal).is_empty(), "patch with negative signal rejected")
	var bad_schema := {"zones": {"zone/wet": {"water_mg": 1}}}
	_check(not EnvironmentPatch.validate_patch(manifest, bad_schema).is_empty(), "patch without schema rejected")

	# --- 6. valid patch: immutable apply, new hash, source unchanged ----------
	var old_hash := Manifest.canonical_hash(manifest)
	var manifest_before := manifest.duplicate(true)
	var applied: Dictionary = EnvironmentPatch.apply_patch(manifest, EnvironmentPatch.patch("zone/dry", "water_mg", 300000))
	_check(bool(applied.get("success", false)), "valid patch applies: " + str(applied.get("error", "")))
	if bool(applied.get("success", false)):
		_check(String(applied.manifest_hash) != old_hash, "patched manifest has a NEW hash")
		_check(String(applied.previous_hash) == old_hash, "apply reports the previous hash")
		_check(Manifest.canonical_hash(manifest) == old_hash, "source manifest unchanged after apply")
		_check(manifest == manifest_before, "source manifest deep-equal to its pre-apply copy")
		_check(int(applied.manifest.environment.zones[1].water_mg) == 300000, "patched field value applied")
		_check(int(applied.manifest.environment.zones[0].water_mg) == 500000, "other zones untouched")
		var rejected: Dictionary = EnvironmentPatch.apply_patch(manifest, negative)
		_check(not bool(rejected.get("success", false)), "apply_patch rejects invalid patch")

	# --- 7. snapshot presentation views match the placement -------------------
	var snapshot_manifest := _with_placement(manifest, PlacementPlan.generate(manifest, "grid").entries)
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(snapshot_manifest)
	_check(bool(init_result.get("success", false)), "controller initializes with generated placement: " + str(init_result))
	if bool(init_result.get("success", false)):
		var snapshot: Dictionary = ctl.get_snapshot()
		var presentation: Array = snapshot.presentation
		_check(presentation.size() == snapshot_manifest.placement.entries.size(), "presentation view per placed founder")
		var position_match := true
		for index in presentation.size():
			if presentation[index].position_mm != snapshot_manifest.placement.entries[index].position_mm:
				position_match = false
		_check(position_match, "presentation positions match placement entries (in order)")
		var founders_only := true
		for view in presentation:
			if view.origin_kind != "FOUNDER_ENDOWMENT" or view.parent_id != "" or view.lineage_depth != 0:
				founders_only = false
		_check(founders_only, "founder presentation views: FOUNDER_ENDOWMENT, no parent, lineage_depth 0")
		var zone_match := true
		for view in presentation:
			if PlacementPlan.zone_id_at(environment, view.position_mm) != String(view.zone_id):
				zone_match = false
		_check(zone_match, "presentation zone_id matches canonical band mapping")
		_check(snapshot.presentation.size() == snapshot.population.size(), "presentation count == population hash count")

	# --- 8. explicit ecology capacity preserves water semantics ---------------
	var high_stock := _manifest()
	high_stock.environment.spatial.width = 2
	high_stock.environment.spatial.depth = 1
	high_stock.environment.zones = [{
		"id": "zone/high",
		"water_mg": Manifest.CELL_CAPACITY_MG,
		"light": 700,
		"temperature": 500,
		"nutrient_mg": 0,
		"organic_mg": 0,
	}]
	high_stock.placement.entries = [{
		"founder_ref": "founder/a",
		"zone_id": "zone/high",
		"position_mm": [500, 0, 500],
	}]
	_check(Manifest.validate(high_stock).is_empty(), "stock at explicit ecology cell capacity validates")
	var high_ctl := Controller.new()
	var high_init: Dictionary = high_ctl.initialize(high_stock)
	_check(bool(high_init.get("success", false)), "controller initializes at exact ecology cell capacity")
	if bool(high_init.get("success", false)):
		var high_field: Dictionary = high_ctl.debug_state().field
		for cell in high_field.cells:
			_check(int(cell.capacities.water_mg) == Manifest.CELL_CAPACITY_MG, "water capacity preserves canonical ecology normalization in " + String(cell.id))
			_check(int(cell.stocks.water_mg) == Manifest.CELL_CAPACITY_MG, "water stock reaches exact capacity in " + String(cell.id))
	var too_high := high_stock.duplicate(true)
	too_high.environment.zones[0].water_mg = Manifest.CELL_CAPACITY_MG + 1
	_check(not Manifest.validate(too_high).is_empty(), "stock above ecology cell capacity fails closed at manifest admission")

	# --- 9. multi-cell patch respects the same capacity boundary ---------------
	var patch_manifest := _manifest()
	patch_manifest.environment.spatial.width = 2
	patch_manifest.environment.spatial.depth = 1
	patch_manifest.environment.zones = [{
		"id": "zone/patch",
		"water_mg": 0,
		"light": 700,
		"temperature": 500,
		"nutrient_mg": 0,
		"organic_mg": 0,
	}]
	patch_manifest.placement.entries = [{
		"founder_ref": "founder/a",
		"zone_id": "zone/patch",
		"position_mm": [500, 0, 500],
	}]
	_check(Manifest.validate(patch_manifest).is_empty(), "capacity-patch fixture manifest validates")
	var patch_ctl := Controller.new()
	var patch_init: Dictionary = patch_ctl.initialize(patch_manifest)
	_check(bool(patch_init.get("success", false)), "capacity-patch controller initializes")
	if bool(patch_init.get("success", false)):
		var exact_patch := {
			"schema": EnvironmentPatch.SCHEMA,
			"zones": {
				"zone/patch": {
					"water_mg": Manifest.CELL_CAPACITY_MG,
					"nutrient_mg": Manifest.CELL_CAPACITY_MG,
					"organic_mg": Manifest.CELL_CAPACITY_MG,
				},
			},
		}
		var applied_exact: Dictionary = patch_ctl.apply_field_patch(exact_patch)
		_check(bool(applied_exact.get("success", false)), "multi-cell patch to exact ecology capacity succeeds")
		if bool(applied_exact.get("success", false)):
			var patched_field: Dictionary = patch_ctl.debug_state().field
			for cell in patched_field.cells:
				_check(int(cell.stocks.water_mg) == Manifest.CELL_CAPACITY_MG, "patch water exact in " + String(cell.id))
				_check(int(cell.stocks.nutrient_mg) == Manifest.CELL_CAPACITY_MG, "patch nutrient exact in " + String(cell.id))
				_check(int(cell.stocks.organic_mg) == Manifest.CELL_CAPACITY_MG, "patch organic exact in " + String(cell.id))

	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_PLACEMENT_P4 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_PLACEMENT_P4 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P4_FAILURE " + failure)
		quit(1)
