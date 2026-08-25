extends SceneTree

## ECO.EVO7 FFF6 integrated succession acceptance: >=100 cycles, multiple functional
## strategies, canopy gap recovery, anti-runaway, deterministic replay, and
## zone/phase-independent stochastic realization identity.
const Bridge = preload("res://scripts/research/ecology/evo7_succession_bridge_v1.gd")
const SEED := 20260823
const REQUIRED_GATE_EVIDENCE: Array[String] = [
	"FFF31_COUNTERFACTUAL_REALIZATION_IDENTITY_PASS",
	"FFF4_SCENARIO_INDEPENDENT_REALIZATION_IDENTITY_PASS",
	"FFF4_WATER_CONSERVATION_AND_PER_REQUEST_BOUNDS_PASS",
	"FFF5_MODIFIED_PRISTINE_REALIZATION_IDENTITY_PASS",
	"FFF6_ZONE_PHASE_INDEPENDENT_REALIZATION_IDENTITY_PASS",
	"FFF6_PRODUCTION_ECOLOGY_AUTHORITY_FAIL_CLOSED_PASS",
]
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_identity_contract()
	var started := Time.get_ticks_msec()
	var result := Bridge.run_all(SEED, 100, true)
	_check(not result.is_empty(), "FFF6 100-cycle integrated bridge runs")
	if result.is_empty():
		_finish()
		return
	print("ECO.EVO7 FFF6 runtime_ms=%d result_hash=%s" % [Time.get_ticks_msec() - started, String(result["result_hash"]).substr(0,16)])
	_check(String(result.get("evaluation_identity_rule", "")) == Bridge.EVALUATION_IDENTITY_RULE, "FFF6 publishes bundle-seed-only evaluation identity rule")
	_check(int(result["cycles"]) >= 100, "FFF6 stability horizon >=100 cycles")
	_check(String(result["common_first_candidate_pool_hash"]).length() == 64, "all six zones share generation-one mutation pool")
	_check(int(result["distinct_final_population_count"]) >= 3, "at least three distinct evolved populations emerge")
	_check(int(result["geometry_cluster_count"]) >= 3, "geometry-only feature space contains >=3 distinct strategy clusters")

	var zones: Dictionary = result["zones"]
	var dry: Dictionary = zones["dry_sand"]
	var mesic: Dictionary = zones["mesic_loam"]
	var riparian: Dictionary = zones["riparian"]
	var understory: Dictionary = zones["under_canopy"]
	var gap: Dictionary = zones["canopy_gap"]
	print("ECO.EVO7 FFF6 strategy_metrics dry(lai=%.6f,height=%.6f,root=%.6f,rsr=%.6f,water=%.6f) mesic(lai=%.6f,height=%.6f,root=%.6f,rsr=%.6f,water=%.6f) riparian(lai=%.6f,height=%.6f,root=%.6f,rsr=%.6f,water=%.6f)" % [
		float(dry["mean_features"]["leaf_area_index_proxy"]), float(dry["mean_features"]["realized_height_m"]), float(dry["mean_features"]["realized_root_depth_m"]), float(dry["mean_root_shoot_ratio"]), float(dry["mean_water_satisfaction"]),
		float(mesic["mean_features"]["leaf_area_index_proxy"]), float(mesic["mean_features"]["realized_height_m"]), float(mesic["mean_features"]["realized_root_depth_m"]), float(mesic["mean_root_shoot_ratio"]), float(mesic["mean_water_satisfaction"]),
		float(riparian["mean_features"]["leaf_area_index_proxy"]), float(riparian["mean_features"]["realized_height_m"]), float(riparian["mean_features"]["realized_root_depth_m"]), float(riparian["mean_root_shoot_ratio"]), float(riparian["mean_water_satisfaction"]),
	])
	_check(float(dry["mean_water_satisfaction"]) < float(riparian["mean_water_satisfaction"]), "dry sand remains more water-limited than riparian")
	var dry_compact_signals := 0
	if float(dry["mean_features"]["leaf_area_index_proxy"]) < float(mesic["mean_features"]["leaf_area_index_proxy"]): dry_compact_signals += 1
	if float(dry["mean_features"]["realized_height_m"]) < float(mesic["mean_features"]["realized_height_m"]): dry_compact_signals += 1
	if float(dry["mean_features"]["realized_root_depth_m"]) > float(mesic["mean_features"]["realized_root_depth_m"]): dry_compact_signals += 1
	if float(dry["mean_root_shoot_ratio"]) > float(mesic["mean_root_shoot_ratio"]): dry_compact_signals += 1
	_check(dry_compact_signals >= 2, "dry-sand compact/root-heavy strategy emerges from >=2 trade-off signals")
	_check(float(riparian["mean_features"]["leaf_area_index_proxy"]) > float(dry["mean_features"]["leaf_area_index_proxy"]), "riparian strategy supports more leaf area than dry sand")
	_check(float(understory["mean_understory_light"]) < float(gap["mean_understory_light"]), "persistent canopy remains darker than final gap")
	_check(float(result["gap_light_recovery"]) > 0.03, "canopy removal produces a measurable deterministic light recovery")
	_check(float(understory["mean_shade_tolerance"]) >= float(mesic["mean_shade_tolerance"]) - 0.02, "under-canopy lineage does not lose shade-tolerance strategy")
	for zone_name in Bridge.ZONE_ORDER:
		var zone: Dictionary = zones[zone_name]
		_check(int(zone["organic_matter_ppm"]) > 0, "%s develops soil legacy" % zone_name)
		_check(float(zone["saturation_fraction"]) < 0.75, "%s passes anti-runaway morphology bound" % zone_name)

	var replay := Bridge.run_all(SEED, 100, true)
	_check(not replay.is_empty() and String(replay["result_hash"]) == String(result["result_hash"]), "100-cycle replay is hash-identical")
	var other_seed := Bridge.run_all(SEED + 1, 100, true)
	_check(not other_seed.is_empty() and String(other_seed["result_hash"]) != String(result["result_hash"]), "different lineage seed changes integrated succession")
	_source_boundaries()
	_finish()

func _identity_contract() -> void:
	var tag := Bridge.stable_evaluation_seed_tag({"individual_seed": 424242})
	_check(tag == "evo7-fff6-eval|424242", "FFF6 realization identity derives from candidate bundle seed only")
	for forbidden in ["flood", "riparian", "mesic", "dry", "sand", "canopy", "gap", "provisional", "final", "feedback"]:
		_check(not tag.contains(forbidden), "FFF6 realization identity excludes %s context" % forbidden)
	_check(Bridge.stable_evaluation_seed_tag({"individual_seed": -1}).is_empty(), "invalid FFF6 realization identity fails closed")

func _source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_succession_bridge_v1.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "species_class", "tree:", "bush:", "grass:"]:
		_check(not source.contains(forbidden), "FFF6 source excludes %s" % forbidden)
	_check(source.contains("lineageextension.reproduce_bundle"), "FFF6 uses the single lineage authority")
	_check(source.contains("lightfield.compute"), "FFF6 consumes canopy light feedback")
	_check(source.contains("waterfield.compute"), "FFF6 consumes bounded soil-water feedback")
	_check(source.contains("legacy.apply_cycle"), "FFF6 feeds selected plants into slow soil memory")
	_check(source.contains("stable_evaluation_seed_tag(bundle)"), "FFF6 functional realization consumes stable bundle identity")
	_check(not source.contains("_functional(bundle, base_env,"), "FFF6 provisional realization cannot receive zone/phase seed tag")
	_check(not source.contains("_functional(item[\"bundle\"],env,"), "FFF6 final realization cannot receive zone/phase seed tag")
	_check(not source.contains("fff6-provisional|%s"), "FFF6 zone name is absent from provisional realization identity")
	_check(not source.contains("fff6-final|%s"), "FFF6 zone name is absent from final realization identity")
	var gate_text := FileAccess.get_file_as_string("res://config/ecology/research/evo7_fff7_xfer_gate.v1.json")
	var gate = JSON.parse_string(gate_text)
	_check(typeof(gate) == TYPE_DICTIONARY, "FFF7/XFER gate JSON parses")
	if typeof(gate) == TYPE_DICTIONARY:
		_check(not bool(gate.get("fff7_activation_authorized", true)), "FFF7 remains fail-closed before FFF6 acceptance")
		_check(not bool(gate.get("xfer_authorized", true)), "XFER remains fail-closed before FFF6 acceptance")
		_check(not bool(gate.get("production_ecology_authority_authorized", true)), "production ecology authority remains fail-closed before FFF6 acceptance")
		var required_evidence: Array = gate.get("required_evidence", [])
		for evidence in REQUIRED_GATE_EVIDENCE:
			_check(required_evidence.has(evidence), "FFF7 gate requires causality evidence %s" % evidence)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF6 Closed Community / Succession: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures: push_error("ECO.EVO7 FFF6 FAIL: %s" % failure)
	print("ECO.EVO7 FFF6 Closed Community / Succession: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
