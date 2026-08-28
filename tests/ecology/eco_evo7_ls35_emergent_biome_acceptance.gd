extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS34 = preload("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
const LS35 = preload("res://scripts/ecology/shadow/eco_evo7_ls35_emergent_biome_observatory_v1.gd")

const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const EVOLUTION_SEED := 330033
const ENV_SEED := 20260831
const INITIAL_RECORDS := 128
const OBSERVE_GENERATIONS := 5

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new(); root.add_child(world)
    _check(world.setup(null), "real Earth initializes")
    var patch := PlanetPatch.new().build(world, Vector3(-0.5, -0.86602540378444, 0.0).normalized(), 32, 16.0)
    _check(not patch.is_empty(), "accepted fully-land 32x32 patch builds")
    var env_generator = EnvironmentField.new()
    var environment := env_generator.generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED)
    _check(not environment.is_empty(), "heterogeneous physical environment builds")

    var observed = LS34.new(); var control = LS34.new(); var classifier = LS35.new()
    _check(observed.setup(patch, environment, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS, true), "observed LS3.4 ecology initializes")
    _check(control.setup(patch, environment, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS, true), "classifier-OFF control ecology initializes")
    if not observed.initialized or not control.initialized:
        world.queue_free(); _finish(); return

    var observed_snapshot: Dictionary = {}
    var control_snapshot: Dictionary = {}
    for generation in OBSERVE_GENERATIONS:
        observed_snapshot = observed.step_generation()
        control_snapshot = control.step_generation()
        _check(not observed_snapshot.is_empty() and not control_snapshot.is_empty(), "generation %d ecology completes" % [generation + 1])
        if observed_snapshot.is_empty() or control_snapshot.is_empty():
            world.queue_free(); _finish(); return
        var ecology_hash_before := String(observed_snapshot["state_hash"])
        var classification := classifier.classify(environment, observed_snapshot, true)
        var disabled := classifier.classify(environment, control_snapshot, false)
        _check(not classification.is_empty(), "generation %d classifier observes post-hoc" % [generation + 1])
        _check(disabled.is_empty(), "generation %d classifier disabled produces no artifact" % [generation + 1])
        _check(String(observed_snapshot["state_hash"]) == ecology_hash_before, "generation %d observation does not mutate ecology snapshot" % [generation + 1])
        _check(_ecology_identity_equal(observed_snapshot, control_snapshot), "generation %d classifier ON/OFF leaves ecology/community hashes identical" % [generation + 1])

    var result := classifier.classify(environment, observed_snapshot, true)
    _check(not result.is_empty(), "final emergent classification materializes")
    if result.is_empty():
        world.queue_free(); _finish(); return
    _check(classifier.validate_classification(result, environment, observed_snapshot), "classification artifact validates against exact physical/community sources")
    _check(int(result["grid_size"]) == 32 and Array(result["cells"]).size() == 1024, "classifier covers exact 32x32 patch")
    _check(bool(result["research_labels_only"]), "labels are explicitly research-only")
    _check(String(result["source_ecology_state_hash"]) == String(observed_snapshot["state_hash"]), "classification binds exact LS3.4 ecology state")
    _check(String(result["source_population_hash"]) == String(observed_snapshot["postcompetition_population_hash"]), "classification binds exact evolved community")
    _check(String(result["source_environment_field_hash"]) == String(environment["field_hash"]), "classification binds exact physical environment")

    var summary: Dictionary = result["summary"]
    _check(int(summary["distinct_base_classes"]) >= 3, "one real patch contains multiple emergent base classes")
    _check(int(summary["ecotone_cells"]) > 0, "one real patch contains measured ecotones")
    _check(_class_counts_sum(summary) == 1024, "all cells receive exactly one post-hoc class")
    _check(_has_multiple_final_classes(summary), "final map contains multiple labels, not one global preset")
    _check(_has_measured_boundary(Array(result["cells"])), "class boundary coincides with measured environment/community differences")
    _check(_ecotones_are_local_boundaries(Array(result["cells"])), "ecotone cells require local class disagreement")
    _check(_observables_present(Array(result["cells"])), "classifier exposes physical/community/spatial observables")
    _check(_continuity_is_bounded(Array(result["cells"])), "continuity and fragmentation remain bounded complements")
    _check(_occupied_cells_have_lineage(Array(result["cells"])), "occupied communities expose lineage richness")

    _check(_controlled_base_label(classifier, _metric_case("desert")) == "desert-like", "dry sparse measured fields classify desert-like")
    _check(_controlled_base_label(classifier, _metric_case("wetland")) == "wetland-like", "wet measured fields classify wetland-like")
    _check(_controlled_base_label(classifier, _metric_case("forest")) == "forest-like", "tall dense measured community classifies forest-like")
    _check(_controlled_base_label(classifier, _metric_case("shrub")) == "grass/shrub-like", "low open measured community classifies grass/shrub-like")
    _check(_controlled_base_label(classifier, _metric_case("alpine")) == "alpine-like", "cold high measured fields classify alpine-like")

    var replay = LS34.new()
    _check(replay.setup(patch, environment, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED, INITIAL_RECORDS, true), "classification replay ecology initializes")
    var replay_snapshot: Dictionary = {}
    for generation in OBSERVE_GENERATIONS:
        replay_snapshot = replay.step_generation()
    var replay_result := classifier.classify(environment, replay_snapshot, true)
    _check(not replay_result.is_empty() and String(replay_result["classification_hash"]) == String(result["classification_hash"]), "same physical/community state replays exact classification hash")

    var tampered: Dictionary = result.duplicate(true)
    var tamper_index := _first_non_forest_cell(Array(tampered["cells"]))
    if tamper_index >= 0:
        var cell: Dictionary = tampered["cells"][tamper_index]
        var old_label := String(cell["label"])
        cell["label"] = "forest-like"
        cell["cell_hash"] = classifier.call("_cell_hash", cell)
        tampered["summary"]["class_counts"][old_label] = int(tampered["summary"]["class_counts"][old_label]) - 1
        tampered["summary"]["class_counts"]["forest-like"] = int(tampered["summary"]["class_counts"]["forest-like"]) + 1
        for label in LS35.LABELS:
            tampered["summary"]["class_fractions"][label] = snappedf(float(int(tampered["summary"]["class_counts"][label])) / 1024.0, 1e-9)
        if old_label == "ecotone":
            tampered["summary"]["ecotone_cells"] = int(tampered["summary"]["ecotone_cells"]) - 1
        tampered["summary"]["summary_hash"] = classifier.call("_summary_hash", tampered["summary"])
        tampered["classification_hash"] = classifier.call("_classification_hash", tampered)
        _check(not classifier.validate_classification(tampered, environment, observed_snapshot), "label tamper fails closed even after complete classifier rehash")

    var authority_tamper: Dictionary = result.duplicate(true)
    authority_tamper["authorities"]["classifier_to_ecology_edge"] = true
    authority_tamper["classification_hash"] = classifier.call("_classification_hash", authority_tamper)
    _check(not classifier.validate_classification(authority_tamper, environment, observed_snapshot), "classifier-to-ecology authority escalation fails closed")

    var stale_environment: Dictionary = environment.duplicate(true)
    stale_environment["cells"][0]["soil_moisture"] = 0.123456
    _check(classifier.classify(stale_environment, observed_snapshot, true).is_empty(), "stale/tampered physical source fails closed")

    _source_guard()
    world.queue_free(); _finish()

func _ecology_identity_equal(a: Dictionary, b: Dictionary) -> bool:
    for key in [
        "state_hash", "candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
        "precompetition_population_hash", "competition_hash", "postcompetition_population_hash",
        "occupied_map_hash", "hereditary_pool_hash",
    ]:
        if String(a.get(key, "")) != String(b.get(key, "")):
            return false
    return int(a.get("record_count", -1)) == int(b.get("record_count", -2))

func _class_counts_sum(summary: Dictionary) -> int:
    var total := 0
    for label in LS35.LABELS:
        total += int(Dictionary(summary["class_counts"]).get(label, 0))
    return total

func _has_multiple_final_classes(summary: Dictionary) -> bool:
    var present := 0
    for label in LS35.LABELS:
        if int(Dictionary(summary["class_counts"]).get(label, 0)) > 0:
            present += 1
    return present >= 3

func _has_measured_boundary(cells: Array) -> bool:
    for y in 32:
        for x in 31:
            var a: Dictionary = cells[y * 32 + x]
            var b: Dictionary = cells[y * 32 + x + 1]
            if String(a["base_label"]) == String(b["base_label"]):
                continue
            var physical_delta := absf(float(a["soil_moisture"]) - float(b["soil_moisture"])) + absf(float(a["temperature_c"]) - float(b["temperature_c"])) / 20.0
            var community_delta := absf(float(a["cover_proxy"]) - float(b["cover_proxy"])) + absf(float(a["canopy_height_m"]) - float(b["canopy_height_m"])) / 5.0
            if physical_delta + community_delta > 0.000001:
                return true
    return false

func _ecotones_are_local_boundaries(cells: Array) -> bool:
    var saw := false
    for value in cells:
        var cell: Dictionary = value
        if String(cell["label"]) != "ecotone":
            continue
        saw = true
        if int(cell["neighbor_base_class_count"]) < 2 or float(cell["class_disagreement"]) < 0.25 or float(cell["boundary_strength"]) <= 0.0:
            return false
    return saw

func _observables_present(cells: Array) -> bool:
    if cells.size() != 1024:
        return false
    var required := [
        "soil_moisture", "surface_water_fraction", "temperature_c", "elevation_m", "incident_light",
        "occupancy_count", "cover_proxy", "lineage_richness", "mean_lai", "canopy_height_m",
        "mean_root_depth_m", "mean_root_shoot_ratio", "water_state", "continuity", "fragmentation",
    ]
    for key in required:
        if not Dictionary(cells[0]).has(key):
            return false
    return true

func _continuity_is_bounded(cells: Array) -> bool:
    for value in cells:
        var cell: Dictionary = value
        var continuity := float(cell["continuity"]); var fragmentation := float(cell["fragmentation"])
        if continuity < 0.0 or continuity > 1.0 or fragmentation < 0.0 or fragmentation > 1.0 or absf(continuity + fragmentation - 1.0) > 1e-8:
            return false
    return true

func _occupied_cells_have_lineage(cells: Array) -> bool:
    var saw := false
    for value in cells:
        var cell: Dictionary = value
        if int(cell["occupancy_count"]) <= 0:
            continue
        saw = true
        if int(cell["lineage_richness"]) < 1:
            return false
    return saw

func _metric_case(kind: String) -> Dictionary:
    var cell := {
        "soil_moisture": 0.50, "surface_water_fraction": 0.0, "temperature_c": 15.0,
        "elevation_m": 200.0, "incident_light": 0.8, "drainage_index": 0.5, "local_relief_m": 2.0,
        "occupancy_count": 0, "occupancy_fraction": 0.0, "cover_proxy": 0.0, "lineage_richness": 0,
        "mean_lai": 0.0, "canopy_height_m": 0.0, "mean_root_depth_m": 0.0, "mean_root_shoot_ratio": 0.0,
        "mean_water_satisfaction": 0.50, "water_state": 0.50, "continuity": 0.20, "fragmentation": 0.80,
    }
    if kind == "desert":
        cell["soil_moisture"] = 0.08; cell["drainage_index"] = 0.80
    elif kind == "wetland":
        cell["soil_moisture"] = 0.92; cell["surface_water_fraction"] = 0.70; cell["drainage_index"] = 0.10; cell["mean_water_satisfaction"] = 0.90
    elif kind == "forest":
        cell["soil_moisture"] = 0.65; cell["cover_proxy"] = 0.85; cell["continuity"] = 0.80; cell["mean_water_satisfaction"] = 0.80; cell["canopy_height_m"] = 6.0; cell["mean_lai"] = 0.50; cell["occupancy_count"] = 4
    elif kind == "shrub":
        cell["soil_moisture"] = 0.50; cell["cover_proxy"] = 0.20; cell["continuity"] = 0.35; cell["mean_water_satisfaction"] = 0.60; cell["canopy_height_m"] = 1.0; cell["mean_lai"] = 0.08; cell["occupancy_count"] = 1
    elif kind == "alpine":
        cell["soil_moisture"] = 0.40; cell["cover_proxy"] = 0.05; cell["continuity"] = 0.15; cell["mean_water_satisfaction"] = 0.40; cell["canopy_height_m"] = 0.5; cell["mean_lai"] = 0.03; cell["temperature_c"] = -15.0; cell["elevation_m"] = 3000.0; cell["local_relief_m"] = 20.0; cell["occupancy_count"] = 1
    return cell

func _controlled_base_label(classifier, metrics: Dictionary) -> String:
    var scores: Dictionary = classifier.call("_base_scores", metrics)
    var ranked: Array = classifier.call("_rank_scores", scores)
    if ranked.is_empty():
        return ""
    return String(Dictionary(ranked[0])["label"])

func _first_non_forest_cell(cells: Array) -> int:
    for index in cells.size():
        if String(Dictionary(cells[index])["label"]) != "forest-like":
            return index
    return -1

func _source_guard() -> void:
    var classifier_path := "res://scripts/ecology/shadow/eco_evo7_ls35_emergent_biome_observatory_v1.gd"
    var source := FileAccess.get_file_as_string(classifier_path)
    var lower := source.to_lower()
    _check(not source.contains(".step_generation("), "LS3.5 classifier cannot advance ecology")
    _check(not source.contains("reproduce_bundle(") and not lower.contains("mutation_seed") and not lower.contains("dispersal_seed"), "LS3.5 owns no reproduction/mutation/dispersal authority")
    _check(not lower.contains("fileaccess.open") and not lower.contains("diraccess") and not lower.contains("multiplayer"), "LS3.5 owns no persistence/network path")
    _check(not lower.contains("biome_code") and not lower.contains("biome_name") and not lower.contains("tree_density"), "LS3.5 reads no legacy biome truth")
    var score_start := source.find("func _base_scores")
    var score_end := source.find("\nfunc ", score_start + 1)
    var scoring := source.substr(score_start, score_end - score_start).to_lower()
    _check(not scoring.contains("recipe") and not scoring.contains("[\"x\"]") and not scoring.contains("[\"y\"]") and not scoring.contains("[\"index\"]"), "base classification has no recipe/coordinate segmentation input")

    for path in [
        "res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd",
        "res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd",
        "res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd",
    ]:
        var causal := FileAccess.get_file_as_string(path).to_lower()
        _check(not causal.contains("eco_evo7_ls35") and not causal.contains("emergent_biome") and not causal.contains("desert-like") and not causal.contains("wetland-like") and not causal.contains("forest-like") and not causal.contains("grass/shrub-like") and not causal.contains("alpine-like"), "no classifier/label read in causal ecology: %s" % path)

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 LS3.5 Emergent Biomes: PASS (%d assertions)" % assertions)
        quit(0); return
    for failure in failures:
        push_error("ECO.EVO7 LS3.5 FAIL: %s" % failure)
    print("ECO.EVO7 LS3.5 Emergent Biomes: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
