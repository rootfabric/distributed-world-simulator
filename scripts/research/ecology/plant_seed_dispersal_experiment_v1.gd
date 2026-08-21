extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Kernel = preload("res://scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_1_seed_dispersal_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.1.1"
const ACCEPTED_CAL1_F_HASH := "f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed"
const LINEAGE := "lineage/evo1-p2-1-controlled"
const SOURCE := Vector2.ZERO
const EMITTED_SEEDS := 80

const CASE_ORDER: Array[String] = [
	"BASE_STILL",
	"SHORT_DISTANCE",
	"LONG_DISTANCE",
	"LOW_RELEASE",
	"HIGH_RELEASE",
	"EAST_BIAS_LOW_TURBULENCE",
	"EAST_BIAS_HIGH_TURBULENCE",
	"WEST_BIAS_LOW_TURBULENCE",
	"BOUNDARY_EAST",
	"EVENT_A",
	"EVENT_B",
]

static func run() -> Dictionary:
	var base := Genome.create_default()
	if base.is_empty():
		return {}
	var short_distance := _with_dispersal(base, "short", 5.0)
	var long_distance := _with_dispersal(base, "long", 30.0)
	if short_distance.is_empty() or long_distance.is_empty():
		return {}

	var unbounded_still := Kernel.create_context(Vector2.ZERO, 0.0)
	var east_low := Kernel.create_context(Vector2(0.80, 0.0), 0.10)
	var east_high := Kernel.create_context(Vector2(0.80, 0.0), 0.90)
	var west_low := Kernel.create_context(Vector2(-0.80, 0.0), 0.10)
	var bounded_east := Kernel.create_context(Vector2(0.90, 0.0), 0.10, Rect2(-20.0, -20.0, 40.0, 40.0))
	for context in [unbounded_still, east_low, east_high, west_low, bounded_east]:
		if Dictionary(context).is_empty():
			return {}

	var cases := {
		"BASE_STILL": Kernel.disperse(base, LINEAGE, "event/base", SOURCE, EMITTED_SEEDS, 1.0, unbounded_still),
		"SHORT_DISTANCE": Kernel.disperse(short_distance, LINEAGE, "event/distance", SOURCE, EMITTED_SEEDS, 1.0, unbounded_still),
		"LONG_DISTANCE": Kernel.disperse(long_distance, LINEAGE, "event/distance", SOURCE, EMITTED_SEEDS, 1.0, unbounded_still),
		"LOW_RELEASE": Kernel.disperse(base, LINEAGE, "event/release", SOURCE, EMITTED_SEEDS, 1.0, unbounded_still),
		"HIGH_RELEASE": Kernel.disperse(base, LINEAGE, "event/release", SOURCE, EMITTED_SEEDS, 4.0, unbounded_still),
		"EAST_BIAS_LOW_TURBULENCE": Kernel.disperse(base, LINEAGE, "event/east", SOURCE, EMITTED_SEEDS, 1.0, east_low),
		"EAST_BIAS_HIGH_TURBULENCE": Kernel.disperse(base, LINEAGE, "event/east", SOURCE, EMITTED_SEEDS, 1.0, east_high),
		"WEST_BIAS_LOW_TURBULENCE": Kernel.disperse(base, LINEAGE, "event/west", SOURCE, EMITTED_SEEDS, 1.0, west_low),
		"BOUNDARY_EAST": Kernel.disperse(base, LINEAGE, "event/boundary", Vector2(18.0, 0.0), EMITTED_SEEDS, 4.0, bounded_east),
		"EVENT_A": Kernel.disperse(base, LINEAGE, "event/a", SOURCE, EMITTED_SEEDS, 1.0, east_low),
		"EVENT_B": Kernel.disperse(base, LINEAGE, "event/b", SOURCE, EMITTED_SEEDS, 1.0, east_low),
	}
	for case_id in CASE_ORDER:
		if not cases.has(case_id) or Dictionary(cases[case_id]).is_empty():
			return {}

	var short_mean := float(cases["SHORT_DISTANCE"]["mean_distance_m"])
	var long_mean := float(cases["LONG_DISTANCE"]["mean_distance_m"])
	var low_release_mean := float(cases["LOW_RELEASE"]["mean_distance_m"])
	var high_release_mean := float(cases["HIGH_RELEASE"]["mean_distance_m"])
	var east_low_projection := float(cases["EAST_BIAS_LOW_TURBULENCE"]["downwind_projection_m"])
	var east_high_projection := float(cases["EAST_BIAS_HIGH_TURBULENCE"]["downwind_projection_m"])
	var west_mean_x := Vector2(cases["WEST_BIAS_LOW_TURBULENCE"]["mean_displacement"]).x
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"cal1_f_parent_hash": ACCEPTED_CAL1_F_HASH,
		"case_order": CASE_ORDER.duplicate(),
		"cases": cases,
		"short_to_long_mean_distance_ratio": _ratio(long_mean, short_mean),
		"release_height_mean_distance_ratio": _ratio(high_release_mean, low_release_mean),
		"east_low_turbulence_projection_m": east_low_projection,
		"east_high_turbulence_projection_m": east_high_projection,
		"west_mean_displacement_x_m": west_mean_x,
		"boundary_outside_seed_count": int(cases["BOUNDARY_EAST"]["outside_domain_seed_count"]),
		"base_long_tail_seed_count": int(cases["BASE_STILL"]["long_tail_seed_count"]),
		"base_local_seed_count": int(cases["BASE_STILL"]["local_seed_count"]),
		"event_hashes_differ": String(cases["EVENT_A"]["result_hash"]) != String(cases["EVENT_B"]["result_hash"]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _with_dispersal(base: Dictionary, suffix: String, distance_m: float) -> Dictionary:
	return Genome.create(
		String(base["genome_id"]) + "/p2-1-" + suffix,
		float(base["height_m"]),
		float(base["growth_rate"]),
		float(base["root_depth_m"]),
		float(base["water_preference"]),
		float(base["water_tolerance_width"]),
		float(base["shade_tolerance"]),
		int(base["seed_count"]),
		distance_m,
		float(base["lifespan_years"])
	)

static func _ratio(a: float, b: float) -> float:
	return a / maxf(absf(b), 0.000000000001)

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("cal1_f_parent_hash", "")),
	])
	var cases: Dictionary = result["cases"]
	for case_id in CASE_ORDER:
		tokens.append("%s|%s" % [case_id, String(cases[case_id]["result_hash"])])
	for field_name in [
		"short_to_long_mean_distance_ratio",
		"release_height_mean_distance_ratio",
		"east_low_turbulence_projection_m",
		"east_high_turbulence_projection_m",
		"west_mean_displacement_x_m",
	]:
		tokens.append("%.12f" % float(result.get(field_name, 0.0)))
	tokens.append(str(int(result.get("boundary_outside_seed_count", 0))))
	tokens.append(str(int(result.get("base_long_tail_seed_count", 0))))
	tokens.append(str(int(result.get("base_local_seed_count", 0))))
	tokens.append(str(bool(result.get("event_hashes_differ", false))))
	return "\n".join(tokens).sha256_text()
