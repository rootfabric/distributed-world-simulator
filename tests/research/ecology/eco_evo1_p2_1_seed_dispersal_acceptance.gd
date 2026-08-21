extends SceneTree

const Kernel = preload("res://scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd")
const Experiment = preload("res://scripts/research/ecology/plant_seed_dispersal_experiment_v1.gd")

const EXPECTED_PARENT_F := "f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed"
const EPSILON := 0.000000001

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var result: Dictionary = Experiment.run()
	_check(not result.is_empty(), "P2.1 experiment result must exist")
	if result.is_empty():
		_finish()
		return

	_check(String(result.get("cal1_f_parent_hash", "")) == EXPECTED_PARENT_F, "accepted CAL1-F parent hash must remain exact")
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash must be sha256")
	var repeat := Experiment.run()
	_check(not repeat.is_empty(), "same-process repeat must exist")
	if not repeat.is_empty():
		_check(String(repeat.get("aggregate_hash", "")) == String(result.get("aggregate_hash", "")), "same-process aggregate must be deterministic")

	var cases: Dictionary = result.get("cases", {})
	_check(cases.size() == Experiment.CASE_ORDER.size(), "all controlled dispersal cases must exist")
	for case_id in Experiment.CASE_ORDER:
		_check(cases.has(case_id), "missing controlled case: " + case_id)
		if not cases.has(case_id):
			continue
		var case: Dictionary = cases[case_id]
		_check(int(case.get("emitted_seed_count", -1)) == Experiment.EMITTED_SEEDS, "emitted count must stay controlled: " + case_id)
		_check(int(case.get("transported_seed_count", -1)) == Experiment.EMITTED_SEEDS, "transport must conserve emitted seed count: " + case_id)
		_check(int(case.get("inside_domain_seed_count", 0)) + int(case.get("outside_domain_seed_count", 0)) == Experiment.EMITTED_SEEDS, "inside + boundary-outside accounting must conserve seeds: " + case_id)
		_check(int(case.get("local_seed_count", 0)) + int(case.get("long_tail_seed_count", 0)) == Experiment.EMITTED_SEEDS, "local + long-tail accounting must conserve seeds: " + case_id)
		_check(int(case.get("packet_count", 0)) > 0 and int(case.get("packet_count", 0)) <= Kernel.DEFAULT_PACKET_COUNT, "cohort packet count must stay bounded: " + case_id)
		_check(String(case.get("result_hash", "")).length() == 64, "case result hash must be sha256: " + case_id)
		var packet_total := 0
		for packet_value in Array(case.get("packets", [])):
			var packet: Dictionary = packet_value
			packet_total += int(packet.get("seed_count", 0))
			_check(String(packet.get("lineage_id", "")) == Experiment.LINEAGE, "packet lineage identity must be preserved: " + case_id)
			_check(String(packet.get("genome_checksum", "")).length() == 64, "packet genome checksum must be preserved: " + case_id)
			_check(String(packet.get("packet_hash", "")).length() == 64, "packet hash must be sha256: " + case_id)
			_check(not packet.has("establishment_probability") and not packet.has("seed_bank_survival") and not packet.has("carrying_capacity"), "P2.1 must not smuggle P2.2 recruitment semantics")
		_check(packet_total == Experiment.EMITTED_SEEDS, "packet cohort counts must sum to emitted seeds: " + case_id)

	var base: Dictionary = cases.get("BASE_STILL", {})
	_check(int(base.get("long_tail_seed_count", 0)) > 0, "kernel must retain an explicit long-tail cohort")
	_check(int(base.get("local_seed_count", 0)) > int(base.get("long_tail_seed_count", 0)), "local kernel must contain the majority cohort")

	var distance_ratio := float(result.get("short_to_long_mean_distance_ratio", 0.0))
	_check(absf(distance_ratio - 6.0) <= EPSILON, "30m vs 5m inherited dispersal must scale mean distance by exactly 6 in still matched control")
	var release_ratio := float(result.get("release_height_mean_distance_ratio", 0.0))
	_check(absf(release_ratio - 2.0) <= EPSILON, "4m vs 1m release height must scale dispersal by sqrt(4)=2")

	var east_low: Dictionary = cases.get("EAST_BIAS_LOW_TURBULENCE", {})
	var east_high: Dictionary = cases.get("EAST_BIAS_HIGH_TURBULENCE", {})
	var west_low: Dictionary = cases.get("WEST_BIAS_LOW_TURBULENCE", {})
	_check(Vector2(east_low.get("mean_displacement", Vector2.ZERO)).x > 0.0, "east transport vector must create positive mean eastward displacement")
	_check(Vector2(west_low.get("mean_displacement", Vector2.ZERO)).x < 0.0, "west transport vector must create negative mean east-west displacement")
	_check(float(east_low.get("downwind_projection_m", 0.0)) > 0.0, "east-biased transport must have positive downwind projection")
	_check(float(east_low.get("downwind_projection_m", 0.0)) > float(east_high.get("downwind_projection_m", 0.0)), "higher turbulence must weaken matched directional transport bias")

	var boundary: Dictionary = cases.get("BOUNDARY_EAST", {})
	_check(int(boundary.get("outside_domain_seed_count", 0)) > 0, "bounded eastward case must explicitly account for boundary-exported seeds")
	_check(int(boundary.get("inside_domain_seed_count", 0)) + int(boundary.get("outside_domain_seed_count", 0)) == Experiment.EMITTED_SEEDS, "boundary export must not destroy seed count")

	var event_a: Dictionary = cases.get("EVENT_A", {})
	var event_b: Dictionary = cases.get("EVENT_B", {})
	_check(bool(result.get("event_hashes_differ", false)), "different reproduction events must produce different deterministic spatial realizations")
	_check(String(event_a.get("result_hash", "")) != String(event_b.get("result_hash", "")), "event A/B result hashes must differ")
	var event_mean_a := float(event_a.get("mean_distance_m", 0.0))
	var event_mean_b := float(event_b.get("mean_distance_m", 0.0))
	var event_scale_delta := absf(event_mean_a - event_mean_b) / maxf(maxf(event_mean_a, event_mean_b), EPSILON)
	_check(event_scale_delta <= 0.02, "event variation may rotate/jitter the kernel but must preserve mean-distance scale within 2 percent")

	print("ECO.EVO1-P2.1 distance_ratio=%.12f release_ratio=%.12f east_low=%.12f east_high=%.12f west_x=%.12f" % [
		distance_ratio,
		release_ratio,
		float(result["east_low_turbulence_projection_m"]),
		float(result["east_high_turbulence_projection_m"]),
		float(result["west_mean_displacement_x_m"])
	])
	print("ECO.EVO1-P2.1 boundary_outside=%d local=%d long_tail=%d event_hashes_differ=%s" % [
		int(result["boundary_outside_seed_count"]), int(result["base_local_seed_count"]), int(result["base_long_tail_seed_count"]), str(bool(result["event_hashes_differ"]))
	])
	print("ECO.EVO1-P2.1 Seed Dispersal Kernel: PASS (%d assertions) aggregate_hash=%s cal1_f=%s" % [assertions, String(result["aggregate_hash"]), String(result["cal1_f_parent_hash"])])
	_finish()

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		quit(0)
		return
	for message in failures:
		push_error("ECO.EVO1-P2.1 ASSERTION FAILED: " + message)
	print("ECO.EVO1-P2.1 Seed Dispersal Kernel: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
