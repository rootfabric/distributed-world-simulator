extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS34 = preload("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")

const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831
const INITIAL_RECORDS := 128

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new(); root.add_child(world)
    _check(world.setup(null), "real Earth initializes")
    var patch_builder = PlanetPatch.new()
    var land_center := Vector3(-0.5, -0.86602540378444, 0.0).normalized()
    var patch := patch_builder.build(world, land_center, 32, 16.0)
    _check(not patch.is_empty(), "accepted fully-land 32x32 patch builds")
    var env_generator = EnvironmentField.new()
    var water := env_generator.generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED)
    _check(not water.is_empty(), "physical environment builds")

    var on = LS34.new(); var off = LS34.new()
    _check(on.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS, true), "competition ON initializes")
    _check(off.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS, false), "competition OFF initializes")
    if not on.initialized or not off.initialized:
        world.queue_free(); _finish(); return

    var g1_on := on.step_generation(); var g1_off := off.step_generation()
    _check(not g1_on.is_empty() and not g1_off.is_empty(), "generation one completes ON/OFF")
    _check(String(g1_on["candidate_pool_hash"]) == String(g1_off["candidate_pool_hash"]), "competition ON/OFF preserves generation-one mutation identities")
    _check(String(g1_on["dispersal_pool_hash"]) == String(g1_off["dispersal_pool_hash"]), "competition ON/OFF preserves generation-one dispersal identities")
    _check(String(g1_on["recruitment_hash"]) == String(g1_off["recruitment_hash"]), "competition starts only after identical LS3.3 recruitment")
    _check(not String(g1_on["competition_hash"]).is_empty() and String(g1_off["competition_hash"]).is_empty(), "competition evidence exists only when enabled")
    _check(_water_is_bounded(g1_on), "sum local water uptake never exceeds available local water")
    _check(_resources_nonnegative(g1_on), "water resource state never becomes negative")
    _check(_light_is_physical_feedback(g1_on), "competition publishes accepted physical light feedback field")
    _check(_controlled_dense_canopy_attenuates(), "dense canopy lowers downstream light through accepted physical feedback field")
    _check(_root_cost_is_measurable(g1_on), "root investment has measurable construction/maintenance cost")
    _check(_controlled_root_heavy_cost(on), "root-heavy allocation increases root maintenance price")
    _check(on.validate_snapshot(g1_on), "LS3.4 snapshot validates fail-closed")

    # Extinction is a valid terminal ecology outcome, not a malformed competition state.
    var empty_field: Dictionary = on.call("_empty_competition_field", 1)
    _check(not empty_field.is_empty() and int(empty_field.get("record_count_before", -1)) == 0 and int(empty_field.get("record_count_after", -1)) == 0, "zero-population competition evidence materializes deterministically")
    _check(on.validate_competition_field(empty_field), "zero-population competition evidence validates")
    var forged_empty: Dictionary = empty_field.duplicate(true)
    forged_empty["light_field_hash"] = "0".repeat(64)
    forged_empty["field_hash"] = on.call("_competition_field_hash", forged_empty)
    _check(not on.validate_competition_field(forged_empty), "zero-population competition evidence rejects forged empty-light identity after rehash")

    var pass_source: Array = Array(on.last_competition_field.get("evaluations", []))
    _check(not pass_source.is_empty(), "competition evaluations materialize")
    var pre_records: Array = Array(off.core.get_snapshot()["records"]).duplicate(true)
    var pass_a: Dictionary = on.call("_competition_pass", pre_records, 1)
    var reversed: Array = pre_records.duplicate(true); reversed.reverse()
    var pass_b: Dictionary = on.call("_competition_pass", reversed, 1)
    _check(not pass_a.is_empty() and not pass_b.is_empty(), "direct competition passes build")
    _check(String(pass_a["field"]["field_hash"]) == String(pass_b["field"]["field_hash"]), "individual evaluation order cannot change competition field hash")
    _check(_record_ids(pass_a["survivors"]) == _record_ids(pass_b["survivors"]), "individual evaluation order cannot change survivors")

    var g2_on := on.step_generation(); var g2_off := off.step_generation()
    var g3_on := on.step_generation(); var g3_off := off.step_generation()
    _check(not g2_on.is_empty() and not g2_off.is_empty() and not g3_on.is_empty() and not g3_off.is_empty(), "three ON/OFF generations complete")
    _check(String(g3_on["postcompetition_population_hash"]) != String(g3_off["postcompetition_population_hash"]) or int(g3_on["record_count"]) != int(g3_off["record_count"]), "competition ON changes community outcome")

    var replay = LS34.new()
    _check(replay.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS, true), "competition replay initializes")
    var r1 := replay.step_generation(); var r2 := replay.step_generation(); var r3 := replay.step_generation()
    _check(String(r1["competition_hash"]) == String(g1_on["competition_hash"]), "competition generation-one replay exact")
    _check(String(r3["state_hash"]) == String(g3_on["state_hash"]), "competition generation-three state replay exact")

    var evo_off = LS34.new()
    _check(evo_off.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS, true), "Evolution-OFF competition control initializes")
    var before := evo_off.get_snapshot()
    _check(evo_off.set_evolution_enabled(false), "Evolution OFF accepted")
    _check(evo_off.step_generation().is_empty(), "Evolution OFF blocks LS3.3 and competition")
    var after_off := evo_off.get_snapshot()
    _check(String(before["postcompetition_population_hash"]) == String(after_off["postcompetition_population_hash"]), "Evolution OFF preserves exact LS3.4 population")
    _check(String(before["competition_hash"]) == String(after_off["competition_hash"]), "Evolution OFF preserves prior competition evidence")
    _check(not bool(after_off["evolution_enabled"]), "Evolution OFF is visible in state without changing ecology")

    var tampered_water: Dictionary = g1_on.duplicate(true)
    if not Array(tampered_water["competition_field"]["water_cells"]).is_empty():
        tampered_water["competition_field"]["water_cells"][0]["water_after_ppm"] = -1
        tampered_water["competition_field"]["water_field_hash"] = on.call("_water_cells_hash", tampered_water["competition_field"]["water_cells"])
        tampered_water["competition_field"]["field_hash"] = on.call("_competition_field_hash", tampered_water["competition_field"])
        tampered_water["competition_hash"] = tampered_water["competition_field"]["field_hash"]
        tampered_water["state_hash"] = on.call("_state_hash", tampered_water)
        _check(not on.validate_snapshot(tampered_water), "negative local resource fails closed after complete rehash")

    var authority_tamper: Dictionary = g1_on.duplicate(true)
    authority_tamper["authorities"]["competition_authority"] = true
    authority_tamper["state_hash"] = on.call("_state_hash", authority_tamper)
    _check(not on.validate_snapshot(authority_tamper), "competition production-authority escalation fails closed")

    _source_guard()
    world.queue_free(); _finish()

func _water_is_bounded(snapshot: Dictionary) -> bool:
    var field: Dictionary = snapshot.get("competition_field", {})
    for value in Array(field.get("water_cells", [])):
        var cell: Dictionary = value
        if int(cell["total_uptake_ppm"]) > int(cell["water_for_plants_ppm"]):
            return false
    return true

func _resources_nonnegative(snapshot: Dictionary) -> bool:
    var field: Dictionary = snapshot.get("competition_field", {})
    for value in Array(field.get("water_cells", [])):
        var cell: Dictionary = value
        if int(cell["available_before_ppm"]) < 0 or int(cell["water_for_plants_ppm"]) < 0 or int(cell["water_after_ppm"]) < 0 or int(cell["total_uptake_ppm"]) < 0:
            return false
    for value in Array(field.get("evaluations", [])):
        var e: Dictionary = value
        if float(e["effective_light"]) < 0.0 or float(e["water_satisfaction"]) < 0.0 or float(e["effective_soil_moisture"]) < 0.0 or float(e["space_factor"]) < 0.0 or float(e["realized_gain"]) < 0.0:
            return false
    return true

func _light_is_physical_feedback(snapshot: Dictionary) -> bool:
    var field: Dictionary = snapshot.get("competition_field", {})
    return not String(field.get("light_field_hash", "")).is_empty()

func _controlled_dense_canopy_attenuates() -> bool:
    var records: Array = [
        {"identity":"tall","world_x_m":0.0,"world_z_m":0.0,"realized_height_m":8.0,"realized_crown_radius_m":4.0,"realized_crown_density":0.90,"leaf_area_index_proxy":3.5,"base_sunlight":0.90,"shade_output_ppm":250000,"source_phenotype_hash":"a".repeat(64)},
        {"identity":"short","world_x_m":0.5,"world_z_m":0.0,"realized_height_m":1.0,"realized_crown_radius_m":1.0,"realized_crown_density":0.40,"leaf_area_index_proxy":0.5,"base_sunlight":0.90,"shade_output_ppm":30000,"source_phenotype_hash":"b".repeat(64)},
    ]
    var field := LightField.compute(records)
    if field.is_empty():
        return false
    var short_light: Dictionary = field["plant_light"]["short"]
    return float(short_light["overlap_lai"]) > 0.0 and float(short_light["understory_light"]) < 0.90

func _root_cost_is_measurable(snapshot: Dictionary) -> bool:
    var field: Dictionary = snapshot.get("competition_field", {})
    var saw_positive := false
    for value in Array(field.get("evaluations", [])):
        var e: Dictionary = value
        if float(e["root_maintenance_cost"]) > 0.0 and float(e["root_construction_cost"]) > 0.0:
            saw_positive = true
    return saw_positive

func _controlled_root_heavy_cost(engine) -> bool:
    var light := {"root_shoot_ratio":0.20,"realized_root_depth_m":2.0,"realized_root_spread_m":2.0}
    var heavy := {"root_shoot_ratio":0.80,"realized_root_depth_m":2.0,"realized_root_spread_m":2.0}
    return float(engine.call("_root_maintenance_cost", heavy)) > float(engine.call("_root_maintenance_cost", light))

func _record_ids(records: Array) -> PackedStringArray:
    var ids := PackedStringArray()
    for value in records:
        ids.append(String(Dictionary(value)["record_id"]))
    ids.sort(); return ids

func _source_guard() -> void:
    var path := "res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd"
    var source := FileAccess.get_file_as_string(path)
    var lower := source.to_lower()
    _check(not source.contains("reproduce_bundle("), "LS3.4 owns no reproduction call site")
    _check(not lower.contains("mutation_seed") and not lower.contains("dispersal_seed"), "LS3.4 owns no mutation/dispersal seed authority")
    _check(not lower.contains("biome_code") and not lower.contains("biome_name") and not lower.contains("tree_density"), "LS3.4 has no biome/legacy vegetation causal input")
    _check(not source.contains("get_render_projection") and not lower.contains("multiplayer"), "LS3.4 has no renderer/network causal input")
    _check(not lower.contains("fileaccess.open") and not lower.contains("diraccess"), "LS3.4 has no persistence path")
    _check(source.contains("LightField.compute(") and source.contains("WaterField.compute("), "competition consumes accepted physical feedback fields")
    _check(source.contains("SAME_CELL_WATER+MOORE_GEOMETRY+TRAIT_RADIUS"), "competition neighborhood policy is explicitly frozen")
    _check(source.find("core.step_generation()") < source.find("_competition_pass(Array(pre"), "competition executes only after LS3.3 recruitment")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 LS3.4 Local Competition: PASS (%d assertions)" % assertions)
        quit(0); return
    for failure in failures:
        push_error("ECO.EVO7 LS3.4 FAIL: %s" % failure)
    print("ECO.EVO7 LS3.4 Local Competition: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
