extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new(); root.add_child(world)
    _check(world.setup(null), "real Earth source initializes")

    var a = Workbench.new()
    var b = Workbench.new()
    _check(a.setup(world), "profiled workbench A initializes")
    _check(b.setup(world), "deterministic oracle workbench B initializes")

    var a0: Dictionary = a.get_workbench_snapshot()
    var b0: Dictionary = b.get_workbench_snapshot()
    _check(String(a0.get("workbench_hash", "")) == String(b0.get("workbench_hash", "")), "identical setup starts from identical workbench identity")
    _check(not a0.has("profile") and not a0.has("timings") and not a0.has("generation_profile"), "profiling telemetry is excluded from canonical workbench snapshot")

    var a1: Dictionary = a.advance_generations(1)
    var b1: Dictionary = b.advance_generations(1)
    _check(not a1.is_empty() and not b1.is_empty(), "both deterministic workbenches advance one generation")
    _check(String(a1.get("workbench_hash", "")) == String(b1.get("workbench_hash", "")), "profiling does not change workbench identity")
    _check(String(a1.get("ecology_state_hash", "")) == String(b1.get("ecology_state_hash", "")), "profiling does not change ecology identity")
    _check(String(a1.get("population_hash", "")) == String(b1.get("population_hash", "")), "profiling does not change population identity")
    _check(String(a1.get("classification_hash", "")) == String(b1.get("classification_hash", "")), "profiling does not change biome classification identity")

    var p: Dictionary = a.get_last_generation_profile()
    _check(not p.is_empty(), "workbench exposes last generation profile")
    _check(String(p.get("schema", "")) == "distributed_world_simulator.ecology.evo7_perf1.workbench_profile.v1", "profile schema is explicit")
    _check(int(p.get("generation", -1)) == 1, "profile is generation-bound")
    _check(int(p.get("record_count", -1)) == int(a.get_ecology_snapshot().get("record_count", -2)), "profile population count matches ecology")
    for key in ["ecology_step_ms", "ecology_validation_ms", "total_ms"]:
        _check(_finite_nonnegative(p.get(key)), "workbench timing %s is finite/nonnegative" % key)

    var obs: Dictionary = p.get("observability", {})
    for key in ["repeated_ecology_validation_ms", "classification_ms", "spatial_observatory_ms", "total_ms"]:
        _check(_finite_nonnegative(obs.get(key)), "observability timing %s is finite/nonnegative" % key)
    var classification_detail: Dictionary = obs.get("classification_detail", {})
    _check(String(classification_detail.get("schema", "")) == "distributed_world_simulator.ecology.evo7_perf1.ls35_profile.v1", "LS3.5 classifier profile schema is explicit")
    for key in ["primary_compute_ms", "validation_ms", "validation_recompute_ms", "total_ms"]:
        _check(_finite_nonnegative(classification_detail.get(key)), "LS3.5 timing %s is finite/nonnegative" % key)
    _check(float(classification_detail.get("validation_ms", 0.0)) + 0.001 >= float(classification_detail.get("validation_recompute_ms", 0.0)), "classification validation covers deterministic recompute oracle")

    var eco: Dictionary = p.get("ecology", {})
    _check(String(eco.get("schema", "")) == "distributed_world_simulator.ecology.evo7_perf1.ls34_profile.v1", "LS3.4 profile schema is explicit")
    _check(int(eco.get("generation", -1)) == 1, "LS3.4 profile generation matches workbench")
    for key in ["ls33_total_ms", "competition_pass_ms", "survivor_apply_ms", "post_snapshot_ms", "snapshot_build_ms", "total_ms"]:
        _check(_finite_nonnegative(eco.get(key)), "LS3.4 timing %s is finite/nonnegative" % key)

    var ls33: Dictionary = eco.get("ls33", {})
    _check(String(ls33.get("schema", "")) == "distributed_world_simulator.ecology.evo7_perf1.ls33_profile.v1", "LS3.3 profile schema is explicit")
    _check(int(ls33.get("generation", -1)) == 1, "LS3.3 profile generation matches workbench")
    _check(int(ls33.get("parent_count", 0)) == 64, "first generation profile sees 64 founders")
    _check(int(ls33.get("candidate_count", 0)) == 128, "two deterministic candidates are built per founder")
    for key in ["candidate_build_ms", "route_build_ms", "recruitment_eval_ms", "materialize_ms", "commit_hash_ms", "validation_ms", "snapshot_build_ms", "total_ms"]:
        _check(_finite_nonnegative(ls33.get(key)), "LS3.3 timing %s is finite/nonnegative" % key)

    var competition: Dictionary = eco.get("competition", {})
    _check(int(competition.get("record_count", -1)) >= int(eco.get("record_count_postcompetition", -1)), "competition profile record count covers survivors")
    for key in ["prepare_ms", "light_field_ms", "water_fields_ms", "geometry_ms", "evaluation_ms", "finalize_validate_ms", "total_ms"]:
        _check(_finite_nonnegative(competition.get(key)), "competition timing %s is finite/nonnegative" % key)

    _check(float(p.get("total_ms", 0.0)) + 0.001 >= float(p.get("ecology_step_ms", 0.0)), "workbench total covers ecology step")
    _check(float(eco.get("total_ms", 0.0)) + 0.001 >= float(eco.get("ls33_total_ms", 0.0)), "LS3.4 total covers LS3.3")
    _check(float(eco.get("competition_pass_ms", 0.0)) + 0.001 >= float(competition.get("geometry_ms", 0.0)), "competition pass covers geometry phase")
    _check(float(ls33.get("total_ms", 0.0)) + 0.001 >= float(ls33.get("recruitment_eval_ms", 0.0)), "LS3.3 total covers recruitment evaluation")

    var before_read: Dictionary = a.get_workbench_snapshot()
    var exposed := a.get_last_generation_profile()
    exposed["generation"] = 999
    var after_read: Dictionary = a.get_workbench_snapshot()
    _check(String(before_read.get("workbench_hash", "")) == String(after_read.get("workbench_hash", "")), "reading/mutating copied profile cannot change Workbench identity")
    _check(int(a.get_last_generation_profile().get("generation", -1)) == 1, "profile accessor returns deep copy")

    _check(not a.advance_generations(1).is_empty(), "second profiled generation advances")
    var hist: Array[Dictionary] = a.get_generation_profile_history()
    _check(hist.size() == 2, "profile history records each observed generation")
    _check(int(hist[0].get("generation", -1)) == 1 and int(hist[1].get("generation", -1)) == 2, "profile history preserves generation order")
    _check(a.PROFILE_HISTORY_LIMIT == 64, "profile history has bounded 64-frame policy")

    _source_guard()
    world.queue_free()
    _finish()

func _finite_nonnegative(value) -> bool:
    var number := float(value)
    return is_finite(number) and number >= 0.0

func _source_guard() -> void:
    var ls33 := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd").to_lower()
    var ls34 := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd").to_lower()
    var ls36 := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd").to_lower()
    _check(ls33.contains("time.get_ticks_usec") and ls34.contains("time.get_ticks_usec") and ls36.contains("time.get_ticks_usec"), "PERF1 timing is instrumented at LS3.3/LS3.4/Workbench boundaries")
    _check(not ls36.contains('"generation_profile",') and not ls36.contains('"timings",'), "canonical Workbench snapshot field list does not absorb profiler telemetry")
    _check(ls34.contains("func _geometry_pressures") and ls34.contains("for j in range(i + 1, ordered.size())"), "PERF1 documents current quadratic geometry candidate for future optimization")
    _check(ls33.contains("func _build_candidates") and ls33.contains("func _evaluate_recruitment"), "PERF1 source exposes deterministic per-parent/per-candidate parallel candidates")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 PERF1 Generation Profiler: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error("ECO.EVO7 PERF1 FAIL: %s" % failure)
    print("ECO.EVO7 PERF1 Generation Profiler: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
