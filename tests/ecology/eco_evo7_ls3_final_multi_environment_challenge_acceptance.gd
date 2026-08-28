extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const Challenge = preload("res://scripts/ecology/shadow/eco_evo7_ls3final_multi_environment_challenge_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new()
    root.add_child(world)
    _check(world.setup(null), "real Earth initializes")

    var challenge = Challenge.new()
    var result := challenge.run(world)
    _check(not result.is_empty(), "LS3.FINAL multi-environment challenge completes")
    if result.is_empty():
        world.queue_free(); _finish(); return
    _check(challenge.validate_result(result), "LS3.FINAL result validates fail-closed")
    _check(String(result.get("challenge_hash", "")).length() == 64, "challenge publishes exact deterministic identity")

    var cases: Array = result["cases"]
    _check(cases.size() == 3, "challenge freezes exactly three contrasting physical environments")
    var by_id := {}
    var founder_hashes := {}
    var environment_hashes := {}
    var final_state_hashes := {}
    var final_heredity_hashes := {}
    for value in cases:
        var evidence: Dictionary = value
        by_id[String(evidence["id"])] = evidence
        founder_hashes[String(evidence["founder_hereditary_pool_hash"])] = true
        environment_hashes[String(evidence["environment_field_hash"])] = true
        final_state_hashes[String(evidence["final_ecology_state_hash"])] = true
        final_heredity_hashes[String(evidence["final_hereditary_pool_hash"])] = true
    _check(founder_hashes.size() == 1, "all environments start from the exact same founder heredity")
    _check(environment_hashes.size() == 3, "all three physical environment fields are distinct")
    _check(final_state_hashes.size() == 3, "same flora diverges to three distinct ecology states")
    _check(final_heredity_hashes.size() == 3, "selection/recruitment produce distinct hereditary outcomes")

    var wet: Dictionary = by_id.get("WET_SURFACE", {})
    var dry: Dictionary = by_id.get("DRY_DRAINED", {})
    var bright: Dictionary = by_id.get("BRIGHT_DRY", {})
    _check(not wet.is_empty() and not dry.is_empty() and not bright.is_empty(), "all frozen challenge labels are present")
    _check(float(wet["environment_means"]["surface_water_fraction"]) >= 0.95, "wet challenge is physically surface-water dominated")
    _check(String(wet["terminal_outcome"]) == "EXTINCT" and int(wet["terminal_generation"]) == 1 and int(wet["final_population"]) == 0, "surface-water environment yields explicit deterministic extinction, not pipeline failure")
    _check(String(wet["classification_hash"]).length() == 64 and String(wet["spatial_observatory_hash"]).length() == 64, "extinction still publishes classifier and spatial evidence")
    _check(float(dry["environment_means"]["soil_moisture"]) <= 0.40 and float(dry["environment_means"]["drainage_index"]) >= 0.70, "dry challenge is physically dry and strongly drained")
    _check(String(dry["terminal_outcome"]) == "SURVIVED" and int(dry["terminal_generation"]) == Challenge.MAX_GENERATIONS and int(dry["final_population"]) < Challenge.INITIAL_RECORDS, "dry/drained environment survives but contracts population")
    _check(float(bright["environment_means"]["incident_light"]) >= 0.85 and float(bright["environment_means"]["surface_water_fraction"]) <= 0.01, "bright challenge is physically high-light and non-surface-water")
    _check(String(bright["terminal_outcome"]) == "SURVIVED" and int(bright["terminal_generation"]) == Challenge.MAX_GENERATIONS and int(bright["final_population"]) > Challenge.INITIAL_RECORDS, "bright environment survives and expands population")
    _check(int(bright["final_population"]) - int(dry["final_population"]) >= 40, "environment alone creates a strong population response gap")

    # Exact replay of the terminal-extinction case through the public Workbench facade.
    var wet_spec := Workbench.default_spec()
    wet_spec["world_seed"] = int(wet["world_seed"])
    wet_spec["environment_seed"] = int(wet["environment_seed"])
    wet_spec["environment_recipe"] = String(wet["environment_recipe"])
    var replay = Workbench.new()
    _check(replay.setup(world, wet_spec), "wet extinction replay initializes from frozen public controls")
    var replay_step := replay.advance_generations(1)
    _check(not replay_step.is_empty(), "wet extinction is a valid generation result")
    _check(int(replay.get_spatial_history()[-1]["population_count"]) == 0, "wet extinction replay reaches zero population exactly")
    _check(String(replay_step["ecology_state_hash"]) == String(wet["final_ecology_state_hash"]), "wet terminal ecology hash replays exactly")
    _check(String(replay_step["hereditary_pool_hash"]) == String(wet["final_hereditary_pool_hash"]), "wet terminal hereditary hash replays exactly")

    var tampered: Dictionary = result.duplicate(true)
    tampered["cases"][0]["terminal_outcome"] = "SURVIVED"
    tampered["cases"][0]["final_population"] = 1
    tampered["cases"][0]["case_hash"] = challenge.call("_case_hash", tampered["cases"][0])
    tampered["challenge_hash"] = challenge.call("_challenge_hash", tampered)
    _check(not challenge.validate_result(tampered), "desired-outcome forgery fails semantic validation even after full rehash")

    var authority_tamper: Dictionary = result.duplicate(true)
    authority_tamper["authorities"]["genome_edit"] = true
    authority_tamper["challenge_hash"] = challenge.call("_challenge_hash", authority_tamper)
    _check(not challenge.validate_result(authority_tamper), "challenge authority escalation fails closed after rehash")

    _source_guard()
    world.queue_free()
    _finish()

func _source_guard() -> void:
    var source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls3final_multi_environment_challenge_v1.gd")
    var lower := source.to_lower()
    _check(source.contains("Workbench.new()") and source.contains("Workbench.default_spec()") and source.contains("advance_generations(1)"), "challenge runs only through the accepted public Workbench facade")
    _check(not source.contains("eco_evo7_ls33") and not source.contains("eco_evo7_ls34") and not source.contains("eco_evo7_ls35"), "challenge does not bypass Workbench into ecology internals")
    _check(not lower.contains("reproduce_bundle(") and not lower.contains("mutation_seed(") and not lower.contains("dispersal_seed("), "challenge owns no reproduction/mutation/dispersal authority")
    _check(not lower.contains("genome[") and not lower.contains("records[") and not lower.contains("fitness ="), "challenge cannot directly edit genome/population/fitness")
    _check(not lower.contains("fileaccess.open") and not lower.contains("diraccess") and not lower.contains("multiplayer"), "challenge owns no persistence/network write path")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 LS3.FINAL Multi-Environment Challenge: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error("ECO.EVO7 LS3.FINAL FAIL: %s" % failure)
    print("ECO.EVO7 LS3.FINAL Multi-Environment Challenge: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
