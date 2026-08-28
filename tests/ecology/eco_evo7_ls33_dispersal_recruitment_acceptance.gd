extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")

const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831
const INITIAL_RECORDS := 64

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new()
    root.add_child(world)
    _check(world.setup(null), "real Earth initializes")
    var patch_builder = PlanetPatch.new()
    var land_center := Vector3(-0.5, -0.86602540378444, 0.0).normalized()
    var patch := patch_builder.build(world, land_center, 32, 16.0)
    _check(not patch.is_empty(), "accepted 32x32 land PlanetPatch builds")
    var land_cells := 0
    for cell_value in Array(patch.get("cells", [])):
        if float(Dictionary(cell_value).get("land_mask", 0.0)) >= 0.5:
            land_cells += 1
    _check(land_cells == 1024, "deterministic acceptance patch is fully land")
    var env_generator = EnvironmentField.new()
    var water := env_generator.generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED)
    var relief := env_generator.generate(patch, "RELIEF_DRAINAGE_STRONG", ENV_SEED)
    var mixed := env_generator.generate(patch, "MIXED_PHYSICAL_HETEROGENEITY", ENV_SEED)
    _check(not water.is_empty() and not relief.is_empty() and not mixed.is_empty(), "three physical counterfactuals build")

    var a = LS33.new(); var b = LS33.new(); var c = LS33.new()
    _check(a.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "water LS3.3 initializes")
    _check(b.setup(patch, relief, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "relief LS3.3 initializes")
    _check(c.setup(patch, mixed, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "mixed LS3.3 initializes")
    if not a.initialized or not b.initialized or not c.initialized:
        world.queue_free(); _finish(); return

    var g1a := a.step_generation(); var g1b := b.step_generation(); var g1c := c.step_generation()
    _check(not g1a.is_empty() and not g1b.is_empty() and not g1c.is_empty(), "generation one completes in all counterfactuals")
    _check(String(g1a["candidate_pool_hash"]) == String(g1b["candidate_pool_hash"]) and String(g1b["candidate_pool_hash"]) == String(g1c["candidate_pool_hash"]), "same parents produce same mutation candidate identities across recipes")
    _check(String(g1a["dispersal_pool_hash"]) == String(g1b["dispersal_pool_hash"]) and String(g1b["dispersal_pool_hash"]) == String(g1c["dispersal_pool_hash"]), "same child identities produce same dispersal routes across recipes")
    _check(_candidate_route_pairs(g1a) == _candidate_route_pairs(g1b) and _candidate_route_pairs(g1b) == _candidate_route_pairs(g1c), "candidate-to-destination mapping is counterfactual invariant")
    _check(String(g1a["recruitment_hash"]) != String(g1b["recruitment_hash"]) or String(g1b["recruitment_hash"]) != String(g1c["recruitment_hash"]), "physical environments change recruitment evidence")
    _check(_eligible_count(g1a) != _eligible_count(g1b) or _eligible_count(g1b) != _eligible_count(g1c), "physical environments change establishment success")
    _check(int(g1a["record_count"]) <= LS33.MAX_RECORDS and int(g1b["record_count"]) <= LS33.MAX_RECORDS and int(g1c["record_count"]) <= LS33.MAX_RECORDS, "recruitment remains globally bounded")
    _check(_max_cell_occupancy(g1a) <= 4 and _max_cell_occupancy(g1b) <= 4 and _max_cell_occupancy(g1c) <= 4, "recruitment remains bounded to four records per cell")

    var g2a := a.step_generation(); var g2b := b.step_generation(); var g2c := c.step_generation()
    var g3a := a.step_generation(); var g3b := b.step_generation(); var g3c := c.step_generation()
    _check(not g2a.is_empty() and not g2b.is_empty() and not g2c.is_empty() and not g3a.is_empty() and not g3b.is_empty() and not g3c.is_empty(), "three generations complete")
    _check(String(g3a["occupied_map_hash"]) != String(g3b["occupied_map_hash"]) or String(g3b["occupied_map_hash"]) != String(g3c["occupied_map_hash"]), "occupied maps diverge across strong physical recipes by generation three")
    _check(String(g3a["population_hash"]) != String(g3b["population_hash"]) or String(g3b["population_hash"]) != String(g3c["population_hash"]), "spatial populations diverge across environments")

    var replay = LS33.new()
    _check(replay.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "replay initializes")
    var r1 := replay.step_generation(); var r2 := replay.step_generation(); var r3 := replay.step_generation()
    _check(String(r1["candidate_pool_hash"]) == String(g1a["candidate_pool_hash"]), "replay generation-one mutation pool exact")
    _check(String(r1["dispersal_pool_hash"]) == String(g1a["dispersal_pool_hash"]), "replay generation-one dispersal pool exact")
    _check(String(r3["population_hash"]) == String(g3a["population_hash"]), "deterministic replay gives exact generation-three population hash")
    _check(String(r3["occupied_map_hash"]) == String(g3a["occupied_map_hash"]), "deterministic replay gives exact generation-three spatial hash")

    var off = LS33.new()
    _check(off.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS), "Evolution-OFF control initializes")
    var before_off := off.get_snapshot()
    _check(off.set_evolution_enabled(false), "Evolution OFF accepted")
    _check(off.step_generation().is_empty(), "Evolution OFF blocks reproduction/dispersal/recruitment")
    var after_off := off.get_snapshot()
    _check(String(before_off["population_hash"]) == String(after_off["population_hash"]), "Evolution OFF preserves population")
    _check(String(before_off["hereditary_pool_hash"]) == String(after_off["hereditary_pool_hash"]), "Evolution OFF preserves heredity")

    _check(_all_routes_valid(g1a), "generation-one route evidence is internally consistent")
    _check(_all_recruitment_routes_bound(g1a), "recruitment evidence binds to exact dispersal route")
    _source_guard()
    world.queue_free()
    _finish()

func _candidate_route_pairs(snapshot: Dictionary) -> PackedStringArray:
    var out := PackedStringArray()
    for route_value in Array(snapshot.get("last_routes", [])):
        var route: Dictionary = route_value
        out.append("%s:%d" % [String(route["candidate_hash"]), int(route["destination_cell_index"])])
    out.sort(); return out

func _eligible_count(snapshot: Dictionary) -> int:
    var count := 0
    for event_value in Array(snapshot.get("last_recruitment", [])):
        if bool(Dictionary(event_value).get("eligible", false)):
            count += 1
    return count

func _max_cell_occupancy(snapshot: Dictionary) -> int:
    var counts := {}
    var maximum := 0
    for record_value in Array(snapshot.get("records", [])):
        var cell := int(Dictionary(record_value)["cell_index"])
        counts[cell] = int(counts.get(cell, 0)) + 1
        maximum = maxi(maximum, int(counts[cell]))
    return maximum

func _all_routes_valid(snapshot: Dictionary) -> bool:
    for route_value in Array(snapshot.get("last_routes", [])):
        var route: Dictionary = route_value
        var parent := int(route["parent_cell_index"])
        var x := parent % 32 + int(route["dx_cells"])
        var y := parent / 32 + int(route["dy_cells"])
        var inside := x >= 0 and x < 32 and y >= 0 and y < 32
        var expected := y * 32 + x if inside else -1
        if inside != bool(route["in_patch"]) or expected != int(route["destination_cell_index"]):
            return false
        if String(route["out_of_patch_rule"]) != "REJECT":
            return false
    return true

func _all_recruitment_routes_bound(snapshot: Dictionary) -> bool:
    var route_hash_by_candidate := {}
    for route_value in Array(snapshot.get("last_routes", [])):
        var route: Dictionary = route_value
        route_hash_by_candidate[String(route["candidate_hash"])] = String(route["route_hash"])
    for event_value in Array(snapshot.get("last_recruitment", [])):
        var event: Dictionary = event_value
        var candidate_hash := String(event["candidate_hash"])
        if not route_hash_by_candidate.has(candidate_hash) or String(event["route_hash"]) != String(route_hash_by_candidate[candidate_hash]):
            return false
    return true

func _source_guard() -> void:
    var path := "res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd"
    var source := FileAccess.get_file_as_string(path)
    var lower := source.to_lower()
    _check(source.count("LineageExtension.reproduce_bundle(") == 1, "LS3.3 has exactly one canonical reproduce_bundle call site")
    _check(not lower.contains("biome_code") and not lower.contains("biome_name") and not lower.contains("tree_density"), "LS3.3 has no legacy biome/vegetation causal input")
    _check(not lower.contains("randomize(") and not lower.contains("randf(") and not lower.contains("randi("), "LS3.3 adds no RNG authority")
    _check(not lower.contains("fileaccess.open") and not lower.contains("diraccess"), "LS3.3 has no persistence write path")
    _check(not lower.contains("multiplayer"), "LS3.3 has no network path")
    _check(not lower.contains("competition_score") and not lower.contains("neighbor_pressure") and not lower.contains("canopy_competition"), "LS3.3 does not implement LS3.4 competition")
    var mutation_start := source.find("func _mutation_seed")
    var mutation_end := source.find("\nfunc ", mutation_start + 1)
    var mutation_logic := source.substr(mutation_start, mutation_end - mutation_start).to_lower()
    _check(not mutation_logic.contains("environment") and not mutation_logic.contains("recipe") and not mutation_logic.contains("moisture"), "mutation seed is destination-environment neutral")
    var dispersal_start := source.find("func _dispersal_seed")
    var dispersal_end := source.find("\nfunc ", dispersal_start + 1)
    var dispersal_logic := source.substr(dispersal_start, dispersal_end - dispersal_start).to_lower()
    _check(not dispersal_logic.contains("environment") and not dispersal_logic.contains("recipe") and not dispersal_logic.contains("moisture"), "dispersal seed is destination-environment neutral")
    var route_start := source.find("func _route_for_child")
    var route_end := source.find("\nfunc ", route_start + 1)
    var route_logic := source.substr(route_start, route_end - route_start).to_lower()
    _check(not route_logic.contains("environment") and not route_logic.contains("recipe") and not route_logic.contains("moisture"), "route is fixed before destination environment read")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 LS3.3 Dispersal Recruitment: PASS (%d assertions)" % assertions)
        quit(0); return
    for failure in failures:
        push_error("ECO.EVO7 LS3.3 FAIL: %s" % failure)
    print("ECO.EVO7 LS3.3 Dispersal Recruitment: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
