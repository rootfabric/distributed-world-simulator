extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const DEFAULT_GENERATIONS := 12
const MAX_GENERATIONS := 100

func _init() -> void:
    var generations := DEFAULT_GENERATIONS
    if OS.has_environment("ECO_PERF1_GENERATIONS"):
        generations = clampi(int(OS.get_environment("ECO_PERF1_GENERATIONS")), 1, MAX_GENERATIONS)
    var world = EarthWorld.new(); root.add_child(world)
    if not world.setup(null):
        push_error("PERF1: Earth setup failed"); quit(1); return
    var workbench = Workbench.new()
    if not workbench.setup(world):
        push_error("PERF1: Workbench setup failed"); quit(1); return

    var rows: Array[Dictionary] = []
    var totals := _empty_totals()
    for _index in generations:
        var result: Dictionary = workbench.advance_generations(1)
        if result.is_empty():
            push_error("PERF1: generation advance failed at %d" % (_index + 1)); quit(1); return
        var row := _flatten(workbench.get_last_generation_profile())
        rows.append(row)
        _accumulate(totals, row)
        print("PERF1 gen=%d pop=%d parents=%d candidates=%d precomp=%d total=%.2fms ls33=%.2f candidate=%.2f recruitment=%.2f competition=%.2f geometry=%.2f classification=%.2f validate=%.2f repeated_validate=%.2f observatory=%.2f" % [
            int(row["generation"]), int(row["population"]), int(row["parent_count"]), int(row["candidate_count"]), int(row["precompetition_count"]), float(row["total_ms"]), float(row["ls33_total_ms"]), float(row["candidate_build_ms"]), float(row["recruitment_eval_ms"]), float(row["competition_pass_ms"]), float(row["geometry_ms"]), float(row["classification_ms"]), float(row["ecology_validation_ms"]), float(row["repeated_validation_ms"]), float(row["spatial_observatory_ms"]),
        ])

    var summary := _summary(rows, totals)
    print("PERF1_SUMMARY " + JSON.stringify(summary))
    var report := {"schema": "distributed_world_simulator.ecology.evo7_perf1.campaign.v1", "rows": rows, "summary": summary}
    var file := FileAccess.open("user://eco-evo7-perf1-profile.json", FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(report, "  "))
        file.close()
        print("PERF1_REPORT " + ProjectSettings.globalize_path("user://eco-evo7-perf1-profile.json"))
    quit(0)

func _flatten(profile: Dictionary) -> Dictionary:
    var ecology: Dictionary = profile.get("ecology", {})
    var ls33: Dictionary = ecology.get("ls33", {})
    var competition: Dictionary = ecology.get("competition", {})
    var observability: Dictionary = profile.get("observability", {})
    var classification_detail: Dictionary = observability.get("classification_detail", {})
    return {
        "generation": int(profile.get("generation", -1)),
        "population": int(profile.get("record_count", 0)),
        "parent_count": int(ls33.get("parent_count", 0)),
        "candidate_count": int(ls33.get("candidate_count", 0)),
        "precompetition_count": int(ecology.get("record_count_precompetition", 0)),
        "postcompetition_count": int(ecology.get("record_count_postcompetition", 0)),
        "total_ms": float(profile.get("total_ms", 0.0)),
        "ecology_step_ms": float(profile.get("ecology_step_ms", 0.0)),
        "ecology_validation_ms": float(profile.get("ecology_validation_ms", 0.0)),
        "repeated_validation_ms": float(observability.get("repeated_ecology_validation_ms", 0.0)),
        "classification_ms": float(observability.get("classification_ms", 0.0)),
        "classification_primary_ms": float(classification_detail.get("primary_compute_ms", 0.0)),
        "classification_validation_ms": float(classification_detail.get("validation_ms", 0.0)),
        "classification_recompute_ms": float(classification_detail.get("validation_recompute_ms", 0.0)),
        "spatial_observatory_ms": float(observability.get("spatial_observatory_ms", 0.0)),
        "ls33_total_ms": float(ecology.get("ls33_total_ms", 0.0)),
        "candidate_build_ms": float(ls33.get("candidate_build_ms", 0.0)),
        "route_build_ms": float(ls33.get("route_build_ms", 0.0)),
        "recruitment_eval_ms": float(ls33.get("recruitment_eval_ms", 0.0)),
        "materialize_ms": float(ls33.get("materialize_ms", 0.0)),
        "commit_hash_ms": float(ls33.get("commit_hash_ms", 0.0)),
        "ls33_validation_ms": float(ls33.get("validation_ms", 0.0)),
        "competition_pass_ms": float(ecology.get("competition_pass_ms", 0.0)),
        "competition_prepare_ms": float(competition.get("prepare_ms", 0.0)),
        "light_field_ms": float(competition.get("light_field_ms", 0.0)),
        "water_fields_ms": float(competition.get("water_fields_ms", 0.0)),
        "geometry_ms": float(competition.get("geometry_ms", 0.0)),
        "competition_evaluation_ms": float(competition.get("evaluation_ms", 0.0)),
        "competition_finalize_ms": float(competition.get("finalize_validate_ms", 0.0)),
    }

func _empty_totals() -> Dictionary:
    return {
        "total_ms": 0.0, "ls33_total_ms": 0.0, "candidate_build_ms": 0.0, "route_build_ms": 0.0,
        "recruitment_eval_ms": 0.0, "competition_pass_ms": 0.0, "geometry_ms": 0.0,
        "classification_ms": 0.0, "classification_primary_ms": 0.0, "classification_validation_ms": 0.0, "classification_recompute_ms": 0.0, "ecology_validation_ms": 0.0, "repeated_validation_ms": 0.0,
        "spatial_observatory_ms": 0.0,
    }

func _accumulate(totals: Dictionary, row: Dictionary) -> void:
    for key in totals.keys():
        totals[key] = float(totals[key]) + float(row.get(key, 0.0))

func _summary(rows: Array[Dictionary], totals: Dictionary) -> Dictionary:
    var count := maxi(rows.size(), 1)
    var averages := {}
    for key in totals.keys():
        averages[key] = float(totals[key]) / float(count)
    var candidates := ["candidate_build_ms", "recruitment_eval_ms", "competition_pass_ms", "classification_ms", "ecology_validation_ms", "repeated_validation_ms", "spatial_observatory_ms"]
    var dominant := ""
    var dominant_ms := -1.0
    for key in candidates:
        var value := float(averages.get(key, 0.0))
        if value > dominant_ms:
            dominant = key; dominant_ms = value
    return {
        "generations": rows.size(),
        "final_generation": int(rows[-1].get("generation", -1)) if not rows.is_empty() else -1,
        "final_population": int(rows[-1].get("population", 0)) if not rows.is_empty() else 0,
        "average_ms": averages,
        "dominant_stage": dominant,
        "dominant_stage_average_ms": dominant_ms,
        "parallelism_note": "Profile first; preserve deterministic ordering and exact state hashes before enabling parallel execution.",
    }
