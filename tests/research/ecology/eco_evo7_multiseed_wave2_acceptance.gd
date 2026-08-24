extends SceneTree

## ECO.EVO7 multiseed wave-2 acceptance (independent research probe, R1 line).
##
## Wave 2 replicates the deterministic ECO.EVO7 bridges over FRESH lineage seeds
## [20260824, 20260825, 20260826] (seed 20260823 stays out: it is the already
## proven baseline of the per-feature acceptances and the wave-1 multiseed
## robustness probe). Asserts DIRECTIONAL STABILITY, not exact hashes:
##   WATER feedback bridge (FFF4, generations=16):
##     - directional stability per seed under feedback ON:
##         dry_sand mean leaf_area_index_proxy < mesic_loam;
##         dry_sand mean realized_root_depth_m > mesic_loam;
##         dry_sand mean_cell_moisture      < mesic_loam;
##     - causality per seed: feedback_on != feedback_off final_population_hash
##       in BOTH scenarios (dry_sand, mesic_loam);
##     - determinism: strict double run of seed 20260824 -> identical result_hash.
##   LITTER feedback bridge Experiment D (FFF5):
##     - populations differ modified vs pristine per seed;
##     - organic accumulation direction per seed: the legacy build ends ABOVE
##       the pristine initial state (initial organic map is empty => mean 0)
##       AND the modified pool keeps more organic than the pristine pool
##       (divergence.organic_modified_minus_pristine > 0);
##     - determinism: strict double run of seed 20260824 -> identical result_hash.
##   SUCCESSION simulation (FFF6, six frozen zones):
##     - ON/OFF divergence across zones >= 5/6 per seed, counted from per-zone
##       final population hashes and cross-checked against
##       comparison.on_off_divergent_zones;
##     - finite/bounded means in EVERY zone and BOTH modes: understory light,
##       cell moisture, cell organic within [0..1] (+1e-9 tolerance), all mean
##       features finite and non-negative, bound pinning fraction within [0..1];
##     - determinism: strict double run of seed 20260824 -> identical result_hash.
##
## Rate discipline: every directional/causality family must hold in 3/3 seeds
## (these are strong effects); any failing seed is recorded honestly - this
## probe never weakens bridge or module code.
##
## Research-only probe: creates no fixtures, writes no files, no platform RNG.

const WaterBridge = preload("res://scripts/research/ecology/evo7_water_feedback_bridge_v1.gd")
const LitterBridge = preload("res://scripts/research/ecology/evo7_litter_feedback_bridge_v1.gd")
const Succession = preload("res://scripts/research/ecology/evo7_succession_simulation_v1.gd")

const SEEDS := [20260824, 20260825, 20260826]
const DETERMINISM_SEED := 20260824
const REQUIRED_SEEDS := 3
const SUCCESSION_MIN_DIVERGENT_ZONES := 5
const BOUNDS_TOLERANCE := 1e-9

var assertions := 0
var failures: Array[String] = []
var matrix: Array[Dictionary] = []

func _init() -> void:
	var started := Time.get_ticks_msec()
	_water_multiseed()
	_litter_multiseed()
	_succession_multiseed()
	_stability_rates()
	_print_matrix()
	print("total runtime_ms=%d" % (Time.get_ticks_msec() - started))
	if failures.is_empty():
		print("ECO.EVO7 multiseed wave2: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 multiseed wave2 FAIL: %s" % failure)
	print("ECO.EVO7 multiseed wave2: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

## ------------------------------------------------------------------- WATER --

func _water_multiseed() -> void:
	var started := Time.get_ticks_msec()
	var lai_values: Array[bool] = []
	var root_values: Array[bool] = []
	var moisture_values: Array[bool] = []
	var on_off_dry_values: Array[bool] = []
	var on_off_mesic_values: Array[bool] = []
	var hash_by_seed := {}
	for seed in SEEDS:
		var s := int(seed)
		var run_started := Time.get_ticks_msec()
		var result: Dictionary = WaterBridge.run_all(s)
		if result.is_empty():
			push_error("WATER run_all returned an empty result for seed %d" % s)
			print("WATER seed=%d BRIDGE FAILED (empty result)" % s)
			lai_values.append(false)
			root_values.append(false)
			moisture_values.append(false)
			on_off_dry_values.append(false)
			on_off_mesic_values.append(false)
			continue
		hash_by_seed[s] = String(result["result_hash"])
		var dry: Dictionary = result["scenarios"]["dry_sand"]
		var mesic: Dictionary = result["scenarios"]["mesic_loam"]
		var dry_on: Dictionary = dry["feedback_on"]
		var mesic_on: Dictionary = mesic["feedback_on"]
		var dry_lai := float(dry_on["mean_features"]["leaf_area_index_proxy"])
		var mesic_lai := float(mesic_on["mean_features"]["leaf_area_index_proxy"])
		var dry_root := float(dry_on["mean_features"]["realized_root_depth_m"])
		var mesic_root := float(mesic_on["mean_features"]["realized_root_depth_m"])
		var dry_moisture := float(dry_on["mean_cell_moisture"])
		var mesic_moisture := float(mesic_on["mean_cell_moisture"])
		var on_off_dry := String(dry_on["final_population_hash"]) != String(dry["feedback_off"]["final_population_hash"])
		var on_off_mesic := String(mesic_on["final_population_hash"]) != String(mesic["feedback_off"]["final_population_hash"])
		lai_values.append(dry_lai < mesic_lai)
		root_values.append(dry_root > mesic_root)
		moisture_values.append(dry_moisture < mesic_moisture)
		on_off_dry_values.append(on_off_dry)
		on_off_mesic_values.append(on_off_mesic)
		print("WATER seed=%d lai[dry=%.3f mesic=%.3f want<] root[dry=%.2f mesic=%.2f want>] moisture[dry=%.3f mesic=%.3f want<] on!=off[dry=%s mesic=%s] runtime_ms=%d result_hash=%s" % [
			s, dry_lai, mesic_lai, dry_root, mesic_root, dry_moisture, mesic_moisture,
			str(on_off_dry), str(on_off_mesic), Time.get_ticks_msec() - run_started,
			String(result["result_hash"]).substr(0, 16)])

	_row("WATER", "WATER lai: dry_sand < mesic_loam (feedback_on)", REQUIRED_SEEDS, lai_values)
	_row("WATER", "WATER root_depth: dry_sand > mesic_loam (feedback_on)", REQUIRED_SEEDS, root_values)
	_row("WATER", "WATER cell_moisture: dry_sand < mesic_loam (feedback_on)", REQUIRED_SEEDS, moisture_values)
	_row("WATER", "WATER causality: on != off population hash (dry_sand)", REQUIRED_SEEDS, on_off_dry_values)
	_row("WATER", "WATER causality: on != off population hash (mesic_loam)", REQUIRED_SEEDS, on_off_mesic_values)

	# Strict end-to-end determinism on ONE wave-2 seed: bridge vs bridge.
	var repeat: Dictionary = WaterBridge.run_all(DETERMINISM_SEED)
	var twice_identical: bool = not repeat.is_empty() \
		and hash_by_seed.has(DETERMINISM_SEED) \
		and String(repeat["result_hash"]) == String(hash_by_seed[DETERMINISM_SEED])
	_check(twice_identical, "WATER determinism: seed %d double run -> identical result_hash" % DETERMINISM_SEED)
	print("WATER strict double run seed=%d twice_identical=%s" % [DETERMINISM_SEED, str(twice_identical)])
	print("WATER phase runtime_ms=%d" % (Time.get_ticks_msec() - started))

## ------------------------------------------------------------------ LITTER --

func _litter_multiseed() -> void:
	var started := Time.get_ticks_msec()
	var differ_values: Array[bool] = []
	var organic_values: Array[bool] = []
	var hash_by_seed := {}
	for seed in SEEDS:
		var s := int(seed)
		var run_started := Time.get_ticks_msec()
		var result: Dictionary = LitterBridge.run_all(s)
		if result.is_empty():
			push_error("LITTER run_all returned an empty result for seed %d" % s)
			print("LITTER seed=%d BRIDGE FAILED (empty result)" % s)
			differ_values.append(false)
			organic_values.append(false)
			continue
		hash_by_seed[s] = String(result["result_hash"])
		var legacy: Dictionary = result["legacy_phase"]
		var experiment: Dictionary = result["experiment_d"]
		var divergence: Dictionary = experiment["divergence"]
		var populations_differ := bool(divergence["populations_differ_modified_vs_pristine"])
		# Documented direction (bridge header, spec sections 10/17-D): the plot
		# starts PRISTINE (empty organic map => mean 0), the legacy community
		# must build organic memory above that initial state, and the modified
		# pool must keep more organic than the pristine pool.
		var legacy_final_organic := float(legacy["mean_cell_organic"])
		var organic_delta := float(divergence["organic_modified_minus_pristine"])
		var establishment_delta := float(divergence["establishment_component_modified_minus_pristine"])
		var moisture_delta := float(divergence["moisture_modified_minus_pristine"])
		var organic_direction := legacy_final_organic > 0.0 and organic_delta > 0.0
		differ_values.append(populations_differ)
		organic_values.append(organic_direction)
		print("LITTER seed=%d pop_differ=%s legacy_organic=%.4f(want>0) organic[mod-pristine]=%.4f(want>0) establishment[mod-pristine]=%.5f moisture[mod-pristine]=%.4f pools_identical=%s runtime_ms=%d result_hash=%s" % [
			s, str(populations_differ), legacy_final_organic, organic_delta,
			establishment_delta, moisture_delta,
			str(bool(experiment["seed_pools_identical"])), Time.get_ticks_msec() - run_started,
			String(result["result_hash"]).substr(0, 16)])

	_row("LITTER", "LITTER experiment D: populations differ modified vs pristine", REQUIRED_SEEDS, differ_values)
	_row("LITTER", "LITTER organic direction: legacy > initial and modified > pristine", REQUIRED_SEEDS, organic_values)

	# Strict end-to-end determinism on ONE wave-2 seed: bridge vs bridge.
	var repeat: Dictionary = LitterBridge.run_all(DETERMINISM_SEED)
	var twice_identical: bool = not repeat.is_empty() \
		and hash_by_seed.has(DETERMINISM_SEED) \
		and String(repeat["result_hash"]) == String(hash_by_seed[DETERMINISM_SEED])
	_check(twice_identical, "LITTER determinism: seed %d double run -> identical result_hash" % DETERMINISM_SEED)
	print("LITTER strict double run seed=%d twice_identical=%s" % [DETERMINISM_SEED, str(twice_identical)])
	print("LITTER phase runtime_ms=%d" % (Time.get_ticks_msec() - started))

## --------------------------------------------------------------- SUCCESSION --

func _succession_multiseed() -> void:
	var started := Time.get_ticks_msec()
	var divergence_values: Array[bool] = []
	var bounded_values: Array[bool] = []
	var hash_by_seed := {}
	for seed in SEEDS:
		var s := int(seed)
		var run_started := Time.get_ticks_msec()
		var result: Dictionary = Succession.run_all(s)
		if result.is_empty():
			push_error("SUCCESSION run_all returned an empty result for seed %d" % s)
			print("SUCCESSION seed=%d MODULE FAILED (empty result)" % s)
			divergence_values.append(false)
			bounded_values.append(false)
			continue
		hash_by_seed[s] = String(result["result_hash"])
		var zones: Dictionary = result["zones"]
		var divergent := 0
		var divergent_list: Array[String] = []
		for zone_name in Succession.ZONE_ORDER:
			var zone: Dictionary = zones[String(zone_name)]
			if String(zone["feedback_on"]["final_population_hash"]) != String(zone["feedback_off"]["final_population_hash"]):
				divergent += 1
				divergent_list.append(String(zone_name))
		# Independent recount from per-zone hashes must agree with the module's
		# own cross-zone comparison (enforced, not assumed).
		var reported_divergent := int(result["comparison"]["on_off_divergent_zones"])
		_check(divergent == reported_divergent,
			"SUCCESSION seed %d: recounted divergent zones %d match comparison %d" % [s, divergent, reported_divergent])
		var bounded := _succession_means_bounded(zones)
		divergence_values.append(divergent >= SUCCESSION_MIN_DIVERGENT_ZONES)
		bounded_values.append(bounded)
		print("SUCCESSION seed=%d divergent=%d/%d zones=[%s] finite_bounded_means=%s runtime_ms=%d result_hash=%s" % [
			s, divergent, Succession.ZONE_ORDER.size(), "|".join(divergent_list),
			str(bounded), Time.get_ticks_msec() - run_started,
			String(result["result_hash"]).substr(0, 16)])

	_row("SUCCESSION", "SUCCESSION on/off divergence >= %d/6 zones" % SUCCESSION_MIN_DIVERGENT_ZONES, REQUIRED_SEEDS, divergence_values)
	_row("SUCCESSION", "SUCCESSION finite + bounded means (all zones, both modes)", REQUIRED_SEEDS, bounded_values)

	# Strict end-to-end determinism on ONE wave-2 seed: module vs module.
	var repeat: Dictionary = Succession.run_all(DETERMINISM_SEED)
	var twice_identical: bool = not repeat.is_empty() \
		and hash_by_seed.has(DETERMINISM_SEED) \
		and String(repeat["result_hash"]) == String(hash_by_seed[DETERMINISM_SEED])
	_check(twice_identical, "SUCCESSION determinism: seed %d double run -> identical result_hash" % DETERMINISM_SEED)
	print("SUCCESSION strict double run seed=%d twice_identical=%s" % [DETERMINISM_SEED, str(twice_identical)])
	print("SUCCESSION phase runtime_ms=%d" % (Time.get_ticks_msec() - started))

## Finite/bounded audit over every zone and both modes: the three normalized
## state means stay within [0..1] (+tolerance) and finite; every mean feature is
## finite and non-negative; the bound-pinning fraction stays a valid fraction
## (no NaN, no runaway past declared trait bounds).
func _succession_means_bounded(zones: Dictionary) -> bool:
	var ratio_fields: Array[String] = ["mean_understory_light", "mean_cell_moisture", "mean_cell_organic"]
	for zone_name in Succession.ZONE_ORDER:
		var zone: Dictionary = zones[String(zone_name)]
		if zone.is_empty():
			return false
		for mode_key in ["feedback_on", "feedback_off"]:
			var mode_result: Dictionary = zone[mode_key]
			if mode_result.is_empty():
				return false
			for ratio_field in ratio_fields:
				var value := float(mode_result[ratio_field])
				if not is_finite(value) or value < -BOUNDS_TOLERANCE or value > 1.0 + BOUNDS_TOLERANCE:
					return false
			var features: Dictionary = mode_result["mean_features"]
			for axis in features.keys():
				var feature_value := float(features[axis])
				if not is_finite(feature_value) or feature_value < -BOUNDS_TOLERANCE:
					return false
			var pinning := float(mode_result["max_bound_pinning_fraction"])
			if not is_finite(pinning) or pinning < -BOUNDS_TOLERANCE or pinning > 1.0 + BOUNDS_TOLERANCE:
				return false
	return true

## -------------------------------------------------------------- reporting --

func _row(bridge: String, label: String, required_seeds: int, values: Array[bool]) -> void:
	matrix.append({
		"bridge": bridge,
		"label": label,
		"required": required_seeds,
		"values": values,
	})

func _stability_rates() -> void:
	for row in matrix:
		var passes := 0
		for value in row["values"]:
			if bool(value):
				passes += 1
		_check(passes >= int(row["required"]), "stability rate [%s] %s: %d/%d seeds (required >= %d)" % [
			String(row["bridge"]), String(row["label"]), passes, SEEDS.size(), int(row["required"])])

func _print_matrix() -> void:
	print("")
	print("=== ECO.EVO7 multiseed wave2: check x seed (every family required >= %d/%d) ===" % [
		REQUIRED_SEEDS, SEEDS.size()])
	var header := "%-64s" % "check"
	for seed in SEEDS:
		header += "%10d" % int(seed)
	header += "%8s" % "rate"
	print(header)
	for row in matrix:
		var line := "%-64s" % String(row["label"])
		var passes := 0
		for value in row["values"]:
			if bool(value):
				passes += 1
			line += "%10s" % ("pass" if bool(value) else "FAIL")
		line += "%7s" % ("%d/%d" % [passes, int(row["required"])])
		print(line)
	print("")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
