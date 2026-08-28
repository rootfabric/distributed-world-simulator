extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const Observatory = preload("res://scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd")
const WorkbenchLabScene = preload("res://scenes/labs/ecology/eco_evo7_ls36_rule_workbench_lab.tscn")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new()
    root.add_child(world)
    _check(world.setup(null), "real Earth initializes")

    var wb = Workbench.new()
    _check(wb.setup(world), "LS3.6 default workbench initializes")
    var initial := wb.get_workbench_snapshot()
    _check(int(initial.get("generation", -1)) == 0, "workbench starts at generation zero")
    _check(not wb.is_playing(), "workbench starts paused")
    _check(String(initial.get("patch_hash", "")).length() == 64, "workbench publishes exact patch hash")
    _check(String(initial.get("environment_field_hash", "")).length() == 64, "workbench publishes exact environment hash")
    _check(String(initial.get("hereditary_pool_hash", "")).length() == 64, "workbench publishes hereditary identity")
    _check(wb.get_spatial_history().size() == 1, "existing Observatory stores spatial generation zero")
    _check(wb.validate_workbench_snapshot(initial), "initial workbench snapshot validates fail-closed")
    var initial_workbench_hash := String(initial.get("workbench_hash", ""))

    var initial_ecology := wb.get_ecology_snapshot()
    var initial_state_hash := String(initial_ecology["state_hash"])
    var initial_patch_hash := String(initial["patch_hash"])
    var initial_environment_hash := String(initial["environment_field_hash"])
    var initial_hereditary_hash := String(initial["hereditary_pool_hash"])

    # Overlay controls are observatory-only and must never change ecology.
    _check(wb.set_overlay_selector("environment", "temperature_c"), "environment overlay selector changes")
    _check(wb.set_overlay_selector("population", "lineage_richness"), "population overlay selector changes")
    _check(wb.set_overlay_selector("biome", "base_biome"), "biome overlay selector changes")
    _check(String(wb.get_ecology_snapshot()["state_hash"]) == initial_state_hash, "overlay selection cannot change ecology state")
    _check(String(wb.get_workbench_snapshot()["workbench_hash"]) == initial_workbench_hash, "overlay selection is excluded from causal workbench identity")
    _check(wb.get_overlay_projection("environment").size() == 1024, "environment overlay covers all cells")
    _check(wb.get_overlay_projection("population").size() == 1024, "population overlay covers all cells")
    _check(wb.get_overlay_projection("biome").is_empty(), "biome overlay is unavailable before first post-competition generation")

    # Evolution OFF is a hard fence: no hidden generation advance.
    _check(wb.set_evolution_enabled(false), "Evolution OFF accepted")
    var off_hash := String(wb.get_ecology_snapshot()["state_hash"])
    _check(wb.advance_generations(1).is_empty(), "Evolution OFF blocks manual +1")
    _check(String(wb.get_ecology_snapshot()["state_hash"]) == off_hash, "Evolution OFF preserves ecology state")
    _check(wb.set_evolution_enabled(true), "Evolution ON restored")

    # Start/Pause governs automatic tick only; manual +N remains explicit.
    _check(wb.tick().is_empty(), "paused workbench does not auto-step")
    _check(wb.start(), "Start accepted")
    var ticked := wb.tick()
    _check(not ticked.is_empty() and int(ticked["generation"]) == 1, "Start + tick advances exactly one generation")
    _check(wb.pause(), "Pause accepted")
    var paused_hash := String(wb.get_ecology_snapshot()["state_hash"])
    _check(wb.tick().is_empty(), "Pause blocks subsequent auto-step")
    _check(String(wb.get_ecology_snapshot()["state_hash"]) == paused_hash, "Pause preserves ecology state")
    _check(wb.get_overlay_projection("biome").size() == 1024, "emergent biome overlay covers all cells after generation one")
    _check(wb.get_spatial_history().size() == 2, "spatial Observatory records generation one")
    var spatial_latest := wb.get_spatial_history()[-1]
    _check(int(spatial_latest["generation"]) == 1, "spatial Observatory latest generation is one")
    _check(int(spatial_latest["occupied_cells"]) >= 0 and int(spatial_latest["occupied_cells"]) <= 1024, "spatial occupied-cell metric bounded")
    _check(float(spatial_latest["shannon_entropy"]) >= 0.0, "spatial lineage entropy non-negative")
    var obs_validator = Observatory.new()
    _check(obs_validator.validate_spatial_entry(spatial_latest), "spatial Observatory entry validates exact full metrics hash")
    var spatial_tamper: Dictionary = spatial_latest.duplicate(true); spatial_tamper["mean_continuity"] = 0.123456
    _check(not obs_validator.validate_spatial_entry(spatial_tamper), "spatial metric tamper fails without hash rewrite")
    var stale_obs = Observatory.new()
    _check(stale_obs.setup_spatial(wb.get_environment_field(), wb.get_ecology_snapshot()), "standalone spatial Observatory accepts exact current sources")
    var stale_classification: Dictionary = wb.get_classification().duplicate(true)
    stale_classification["source_ecology_state_hash"] = "0".repeat(64)
    _check(not stale_obs.record_spatial_snapshot(wb.get_environment_field(), wb.get_ecology_snapshot(), stale_classification), "spatial Observatory rejects stale classification source binding")

    # Reset with exact same seeds must replay the exact physical/environment/ecology start.
    _check(wb.reset_same_seeds(), "Reset same seeds succeeds")
    var reset := wb.get_workbench_snapshot()
    _check(int(reset["generation"]) == 0, "reset returns to generation zero")
    _check(String(reset["patch_hash"]) == initial_patch_hash, "same world seed replays exact patch")
    _check(String(reset["environment_field_hash"]) == initial_environment_hash, "same environment seed/recipe replays exact field")
    _check(String(reset["hereditary_pool_hash"]) == initial_hereditary_hash, "reset preserves exact founder hereditary pool")
    _check(String(wb.get_ecology_snapshot()["state_hash"]) == initial_state_hash, "same controls replay exact initial ecology state")

    # Physical counterfactuals may change physics but not founder heredity.
    var recipes := EnvironmentField.new().recipe_ids()
    _check(recipes.size() == 3, "workbench exposes three frozen physical recipes")
    var alt_recipe := String(recipes[0]) if String(recipes[0]) != String(Workbench.DEFAULT_RECIPE) else String(recipes[1])
    _check(wb.apply_physical_controls(Workbench.DEFAULT_WORLD_SEED, Workbench.DEFAULT_ENVIRONMENT_SEED, alt_recipe), "recipe counterfactual resets workbench")
    var recipe_state := wb.get_workbench_snapshot()
    _check(String(recipe_state["patch_hash"]) == initial_patch_hash, "recipe change preserves physical patch identity")
    _check(String(recipe_state["environment_field_hash"]) != initial_environment_hash, "recipe change alters physical environment field")
    _check(String(recipe_state["hereditary_pool_hash"]) == initial_hereditary_hash, "recipe change cannot alter founder hereditary pool")

    _check(wb.apply_physical_controls(Workbench.DEFAULT_WORLD_SEED + 17, Workbench.DEFAULT_ENVIRONMENT_SEED, Workbench.DEFAULT_RECIPE), "world-seed counterfactual resets workbench")
    var world_state := wb.get_workbench_snapshot()
    _check(String(world_state["patch_hash"]) != initial_patch_hash, "world seed changes sampled physical patch")
    _check(String(world_state["hereditary_pool_hash"]) == initial_hereditary_hash, "world seed cannot alter founder hereditary pool")

    _check(wb.apply_physical_controls(Workbench.DEFAULT_WORLD_SEED, Workbench.DEFAULT_ENVIRONMENT_SEED + 19, Workbench.DEFAULT_RECIPE), "environment-seed counterfactual resets workbench")
    var env_seed_state := wb.get_workbench_snapshot()
    _check(String(env_seed_state["patch_hash"]) == initial_patch_hash, "environment seed preserves patch")
    _check(String(env_seed_state["environment_field_hash"]) != initial_environment_hash, "environment seed changes generated field")
    _check(String(env_seed_state["hereditary_pool_hash"]) == initial_hereditary_hash, "environment seed cannot alter founder hereditary pool")

    # Competition ON/OFF: LS3.3 mutation/dispersal/recruitment evidence is identical; only selection may differ.
    var on = Workbench.new(); var off = Workbench.new()
    _check(on.setup(world), "competition-ON counterfactual initializes")
    var off_spec := Workbench.default_spec(); off_spec["competition_enabled"] = false
    _check(off.setup(world, off_spec), "competition-OFF counterfactual initializes")
    _check(not on.advance_generations(1).is_empty(), "competition-ON advances one generation")
    _check(not off.advance_generations(1).is_empty(), "competition-OFF advances one generation")
    var on_ecology := on.get_ecology_snapshot(); var off_ecology := off.get_ecology_snapshot()
    _check(String(on_ecology["candidate_pool_hash"]) == String(off_ecology["candidate_pool_hash"]), "competition toggle cannot alter mutation candidate identity")
    _check(String(on_ecology["dispersal_pool_hash"]) == String(off_ecology["dispersal_pool_hash"]), "competition toggle cannot alter dispersal identity")
    _check(String(on_ecology["recruitment_hash"]) == String(off_ecology["recruitment_hash"]), "competition toggle cannot alter recruitment identity")
    _check(off.get_classification().is_empty(), "competition OFF produces no LS3.5 classification input stage")

    # +10 is deterministic against ten explicit +1 operations.
    var ten = Workbench.new(); var singles = Workbench.new()
    _check(ten.setup(world), "+10 reference initializes")
    _check(singles.setup(world), "ten +1 replay initializes")
    _check(not ten.advance_generations(10).is_empty(), "+10 control advances ten generations")
    var singles_ok := true
    for _i in 10:
        if singles.advance_generations(1).is_empty():
            singles_ok = false
            break
    _check(singles_ok, "ten explicit +1 operations complete")
    _check(String(ten.get_ecology_snapshot()["state_hash"]) == String(singles.get_ecology_snapshot()["state_hash"]), "+10 equals ten deterministic +1 operations")
    _check(String(ten.get_classification().get("classification_hash", "")) == String(singles.get_classification().get("classification_hash", "")), "+10 reproduces exact final classification")
    var ten_snapshot := ten.get_workbench_snapshot(); var singles_snapshot := singles.get_workbench_snapshot()
    _check(String(ten_snapshot.get("patch_hash", "")) == String(singles_snapshot.get("patch_hash", "")), "same controls/actions replay exact physical patch")
    _check(String(ten_snapshot.get("environment_field_hash", "")) == String(singles_snapshot.get("environment_field_hash", "")), "same controls/actions replay exact environment")
    _check(String(ten_snapshot.get("spatial_observatory_hash", "")) == String(singles_snapshot.get("spatial_observatory_hash", "")), "same controls/actions replay exact spatial observatory")
    _check(String(ten_snapshot.get("workbench_hash", "")) == String(singles_snapshot.get("workbench_hash", "")), "same controls/actions replay exact workbench identity")
    _check(100 in Workbench.ALLOWED_STEPS, "+100 is an explicit supported manual control")
    _check(ten.advance_generations(2).is_empty(), "unsupported +2 fails closed")

    # Control spec is fail-closed; no hidden controls or desired-biome shortcuts.
    var hidden := Workbench.default_spec(); hidden["make_desert_plants"] = true
    _check(not Workbench.new().setup(world, hidden), "hidden desired-biome control rejected")
    var invalid := Workbench.default_spec(); invalid["environment_recipe"] = "MAKE_FOREST"
    _check(not Workbench.new().setup(world, invalid), "invalid desired-result recipe rejected")

    var canonical_workbench := wb.get_workbench_snapshot()
    _check(wb.validate_workbench_snapshot(canonical_workbench), "canonical workbench snapshot validates")
    var authority_tamper: Dictionary = canonical_workbench.duplicate(true); authority_tamper["authorities"]["genome_edit"] = true
    authority_tamper["workbench_hash"] = wb.call("_workbench_hash", authority_tamper)
    _check(not wb.validate_workbench_snapshot(authority_tamper), "workbench authority escalation fails closed after rehash")
    var hidden_snapshot: Dictionary = canonical_workbench.duplicate(true); hidden_snapshot["hidden_control"] = true
    _check(not wb.validate_workbench_snapshot(hidden_snapshot), "unexpected hidden workbench field fails closed")
    var forged_spec: Dictionary = canonical_workbench.duplicate(true); forged_spec["spec"]["world_seed"] = int(forged_spec["spec"]["world_seed"]) + 1
    forged_spec["workbench_hash"] = wb.call("_workbench_hash", forged_spec)
    _check(not wb.validate_workbench_snapshot(forged_spec), "forged valid-looking control spec fails source binding")

    # Minimal interactive lab/UI is a thin facade over the already-tested workbench API.
    var lab = WorkbenchLabScene.instantiate(); lab.auto_initialize = false; lab.ensure_ui_built(); root.add_child(lab)
    var ui_contract: Dictionary = lab.get_ui_contract()
    _check(int(ui_contract.get("grid_cells", 0)) == 1024, "interactive lab builds one 32x32 diagnostic grid")
    for control_name in ["world_seed", "environment_seed", "recipe", "start", "pause", "reset", "step_1", "step_10", "step_100", "evolution", "competition", "environment_overlay", "population_overlay", "biome_overlay"]:
        _check(bool(ui_contract.get(control_name, false)), "interactive lab exposes %s control" % control_name)
    _check(lab.initialize_runtime(world), "interactive lab initializes against real Earth source")
    var lab_before := String(lab.get_workbench_snapshot().get("ecology_state_hash", ""))
    _check(lab.set_active_overlay_group("population"), "interactive lab switches display group")
    _check(String(lab.get_workbench_snapshot().get("ecology_state_hash", "")) == lab_before, "interactive lab display switch is non-causal")
    _check(lab.manual_step(1), "interactive lab +1 facade advances workbench")
    _check(int(lab.get_workbench_snapshot().get("generation", -1)) == 1, "interactive lab reports stepped generation")
    lab.queue_free()

    _source_guard()
    world.queue_free()
    _finish()

func _source_guard() -> void:
    var source := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd").to_lower()
    _check(not source.contains("reproduce_bundle("), "workbench has no reproduction call site")
    _check(not source.contains("mutation_seed("), "workbench has no mutation-seed authority")
    _check(not source.contains("dispersal_seed("), "workbench has no dispersal-seed authority")
    _check(not source.contains("genome["), "workbench has no direct genome editing")
    _check(not source.contains("make desert") and not source.contains("make forest"), "workbench has no desired-biome action")
    _check(not source.contains("fileaccess.open") and not source.contains("diraccess"), "workbench has no persistence write path")
    _check(not source.contains("multiplayer"), "workbench has no network authority")
    var ls34 := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd").to_lower()
    var ls33 := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd").to_lower()
    _check(not ls34.contains("ls35") and not ls34.contains("emergent_biome"), "competition remains independent of classifier/workbench labels")
    _check(not ls33.contains("ls35") and not ls33.contains("emergent_biome"), "mutation/dispersal/recruitment remain independent of classifier/workbench labels")
    var obs := FileAccess.get_file_as_string("res://scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd").to_lower()
    _check(obs.contains("setup_spatial") and obs.contains("record_spatial_snapshot"), "LS2.1 Observatory is extended for spatial metrics")
    _check(obs.contains("spatial_revision") and obs.contains("validate_spatial_entry"), "spatial Observatory publishes a separately hardened LS3.6 evidence revision")
    var lab_source := FileAccess.get_file_as_string("res://scripts/labs/ecology/eco_evo7_ls36_rule_workbench_lab.gd").to_lower()
    _check(not lab_source.contains("reproduce_bundle(") and not lab_source.contains("mutation_seed("), "interactive lab has no reproduction/mutation authority")
    _check(not lab_source.contains("genome[") and not lab_source.contains("records[") , "interactive lab has no direct genome/population editing")
    _check(lab_source.contains("get_overlay_projection") and lab_source.contains("advance_generations"), "interactive lab uses the public workbench facade")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 LS3.6 Rule Workbench: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error("ECO.EVO7 LS3.6 FAIL: %s" % failure)
    print("ECO.EVO7 LS3.6 Rule Workbench: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
