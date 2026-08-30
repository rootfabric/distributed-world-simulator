extends RefCounted

const PatchBuilder = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS34 = preload("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
const LS35 = preload("res://scripts/ecology/shadow/eco_evo7_ls35_emergent_biome_observatory_v1.gd")
const Observatory = preload("res://scripts/ecology/shadow/eco_evo7_evolution_observatory_v1.gd")

## ECO.EVO7 LS3.6 — deterministic Rule Workbench controller.
##
## The workbench controls experiment inputs and invokes accepted public ecology APIs.
## It never edits genomes, populations, classifier labels, fitness, mutation, dispersal,
## recruitment or competition internals directly.

const SCHEMA := "distributed_world_simulator.ecology.evo7_rule_workbench.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.6.2"
const PROFILE_SCHEMA := "distributed_world_simulator.ecology.evo7_perf1.workbench_profile.v1"
const PROFILE_HISTORY_LIMIT := 64
const MODE := "SHADOW_RAM_ONLY"
const GRID_SIZE := 32
const CELL_SIZE_M := 16.0
const DEFAULT_WORLD_SEED := 360036
const DEFAULT_ENVIRONMENT_SEED := 310031
const DEFAULT_RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const FOUNDER_SEED := 20260836
const PLACEMENT_SEED := 360032
const EVOLUTION_SEED := 360033
const INITIAL_RECORDS := 64
const LAND_ANCHOR := Vector3(-0.5, -0.86602540378444, 0.0)
const MAX_CENTER_OFFSET_RAD := 0.10
const ALLOWED_STEPS: Array[int] = [1, 10, 100]
const OVERLAY_SELECTORS := {
    "environment": ["soil_moisture", "surface_water_fraction", "temperature_c", "elevation_m", "incident_light", "drainage"],
    "population": ["occupancy", "lineage_richness"],
    "biome": ["emergent_biome", "base_biome"],
}
const AUTHORITY := {
    "world_write": false,
    "ecology_direct_write": false,
    "genome_edit": false,
    "mutation_authority": false,
    "classifier_to_ecology_edge": false,
    "persistence_write": false,
    "network_replication_write": false,
    "renderer_write": false,
}
const SPEC_FIELDS: Array[String] = [
    "world_seed", "environment_seed", "environment_recipe",
    "evolution_enabled", "competition_enabled",
    "environment_overlay", "population_overlay", "biome_overlay",
]

const WORKBENCH_FIELDS: Array[String] = [
    "schema", "version", "revision", "mode", "shadow_only", "playing", "generation",
    "spec", "patch_hash", "environment_field_hash", "ecology_state_hash", "population_hash",
    "hereditary_pool_hash", "classification_hash", "spatial_observatory_hash",
    "reset_count", "manual_step_count", "authorities", "workbench_hash",
]

var initialized := false
var playing := false
var planet_source = null
var spec: Dictionary = {}
var patch: Dictionary = {}
var environment_field: Dictionary = {}
var ecology = null
var classifier = null
var observatory = null
var classification: Dictionary = {}
var reset_count := 0
var manual_step_count := 0
var last_generation_profile: Dictionary = {}
var generation_profile_history: Array[Dictionary] = []
var last_observability_profile: Dictionary = {}

static func default_spec() -> Dictionary:
    return {
        "world_seed": DEFAULT_WORLD_SEED,
        "environment_seed": DEFAULT_ENVIRONMENT_SEED,
        "environment_recipe": DEFAULT_RECIPE,
        "evolution_enabled": true,
        "competition_enabled": true,
        "environment_overlay": "soil_moisture",
        "population_overlay": "occupancy",
        "biome_overlay": "emergent_biome",
    }

func setup(source, requested_spec: Dictionary = {}) -> bool:
    _reset_runtime()
    planet_source = source
    var resolved := default_spec()
    for key in requested_spec.keys():
        if not resolved.has(key):
            return false
        resolved[key] = requested_spec[key]
    if not validate_spec(resolved):
        return false
    spec = resolved.duplicate(true)
    return _rebuild()

func validate_spec(value: Dictionary) -> bool:
    if value.keys().size() != SPEC_FIELDS.size():
        return false
    for key in SPEC_FIELDS:
        if not value.has(key):
            return false
    if typeof(value["world_seed"]) != TYPE_INT or typeof(value["environment_seed"]) != TYPE_INT:
        return false
    if not String(value["environment_recipe"]) in EnvironmentField.new().recipe_ids():
        return false
    if typeof(value["evolution_enabled"]) != TYPE_BOOL or typeof(value["competition_enabled"]) != TYPE_BOOL:
        return false
    if not String(value["environment_overlay"]) in Array(OVERLAY_SELECTORS["environment"]):
        return false
    if not String(value["population_overlay"]) in Array(OVERLAY_SELECTORS["population"]):
        return false
    if not String(value["biome_overlay"]) in Array(OVERLAY_SELECTORS["biome"]):
        return false
    return true

func apply_physical_controls(world_seed: int, environment_seed: int, recipe_id: String) -> bool:
    if not initialized or not recipe_id in EnvironmentField.new().recipe_ids():
        return false
    spec["world_seed"] = world_seed
    spec["environment_seed"] = environment_seed
    spec["environment_recipe"] = recipe_id
    return _rebuild()

func reset_same_seeds() -> bool:
    if not initialized:
        return false
    return _rebuild()

func start() -> bool:
    if not initialized:
        return false
    playing = true
    return true

func pause() -> bool:
    if not initialized:
        return false
    playing = false
    return true

func is_playing() -> bool:
    return playing

func tick() -> Dictionary:
    if not initialized or not playing:
        return {}
    var result := advance_generations(1)
    if result.is_empty():
        playing = false
    return result

func advance_generations(count: int) -> Dictionary:
    if not initialized or not count in ALLOWED_STEPS:
        return {}
    if not bool(spec["evolution_enabled"]):
        return {}
    var result: Dictionary = {}
    for _index in count:
        var total_started := Time.get_ticks_usec()
        var phase_started := Time.get_ticks_usec()
        result = ecology.step_generation()
        var ecology_step_ms := _elapsed_ms(phase_started)
        if result.is_empty():
            return {}

        phase_started = Time.get_ticks_usec()
        if not ecology.validate_snapshot(result):
            return {}
        var ecology_validation_ms := _elapsed_ms(phase_started)

        if not _refresh_observability(result, true):
            return {}
        var profile := {
            "schema": PROFILE_SCHEMA,
            "generation": int(result.get("generation", -1)),
            "record_count": int(result.get("record_count", 0)),
            "ecology_step_ms": ecology_step_ms,
            "ecology_validation_ms": ecology_validation_ms,
            "observability": last_observability_profile.duplicate(true),
            "ecology": ecology.get_last_profile(),
            "total_ms": _elapsed_ms(total_started),
        }
        last_generation_profile = profile
        generation_profile_history.append(profile.duplicate(true))
        if generation_profile_history.size() > PROFILE_HISTORY_LIMIT:
            generation_profile_history.pop_front()
    manual_step_count += count
    return get_workbench_snapshot()

func get_last_generation_profile() -> Dictionary:
    return last_generation_profile.duplicate(true)

func get_generation_profile_history() -> Array[Dictionary]:
    return generation_profile_history.duplicate(true)

## PAR2 minimal pass-through: the Workbench stays backend-ignorant and never
## reaches into ecology.core private members; it forwards the existing LS3.3
## executor seam through the public LS3.4 facade.
func set_recruitment_executor(executor) -> bool:
    if not initialized or ecology == null:
        return false
    return ecology.set_recruitment_executor(executor)

func clear_recruitment_executor() -> void:
    if ecology != null:
        ecology.clear_recruitment_executor()

func has_recruitment_executor() -> bool:
    return ecology != null and ecology.has_recruitment_executor()

## PAR3 public pass-through: PLAY0/runtime composition never reaches
## workbench.ecology.core for candidate execution.
func set_candidate_executor(executor) -> bool:
    if not initialized or ecology == null:
        return false
    return ecology.set_candidate_executor(executor)

func clear_candidate_executor() -> void:
    if ecology != null:
        ecology.clear_candidate_executor()

func has_candidate_executor() -> bool:
    return ecology != null and ecology.has_candidate_executor()

func _elapsed_ms(start_usec: int) -> float:
    return float(Time.get_ticks_usec() - start_usec) / 1000.0

func set_evolution_enabled(value: bool) -> bool:
    if not initialized or not ecology.set_evolution_enabled(value):
        return false
    spec["evolution_enabled"] = value
    classification = {}
    return _refresh_observability(ecology.get_snapshot(), false)

func set_competition_enabled(value: bool) -> bool:
    if not initialized or not ecology.set_competition_enabled(value):
        return false
    spec["competition_enabled"] = value
    classification = {}
    return _refresh_observability(ecology.get_snapshot(), false)

func set_overlay_selector(group: String, selector: String) -> bool:
    if not initialized or not OVERLAY_SELECTORS.has(group) or not selector in Array(OVERLAY_SELECTORS[group]):
        return false
    spec["%s_overlay" % group] = selector
    return true

func get_overlay_projection(group: String) -> Array[Dictionary]:
    if not initialized or not OVERLAY_SELECTORS.has(group):
        return []
    match group:
        "environment":
            return _environment_projection(String(spec["environment_overlay"]))
        "population":
            return _population_projection(String(spec["population_overlay"]))
        "biome":
            return _biome_projection(String(spec["biome_overlay"]))
    return []

func get_workbench_snapshot() -> Dictionary:
    if not initialized:
        return {}
    var ecology_snapshot: Dictionary = ecology.get_snapshot()
    var out := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "mode": MODE,
        "shadow_only": true,
        "playing": playing,
        "generation": int(ecology_snapshot.get("generation", 0)),
        "spec": spec.duplicate(true),
        "patch_hash": String(patch.get("patch_hash", "")),
        "environment_field_hash": String(environment_field.get("field_hash", "")),
        "ecology_state_hash": String(ecology_snapshot.get("state_hash", "")),
        "population_hash": String(ecology_snapshot.get("postcompetition_population_hash", "")),
        "hereditary_pool_hash": String(ecology_snapshot.get("hereditary_pool_hash", "")),
        "classification_hash": String(classification.get("classification_hash", "")),
        "spatial_observatory_hash": String(observatory.get_spatial_latest().get("observatory_hash", "")) if observatory != null else "",
        "reset_count": reset_count,
        "manual_step_count": manual_step_count,
        "authorities": AUTHORITY.duplicate(true),
    }
    out["workbench_hash"] = _workbench_hash(out)
    return out if validate_workbench_snapshot(out) else {}

func validate_workbench_snapshot(value: Dictionary) -> bool:
    if not initialized or value.keys().size() != WORKBENCH_FIELDS.size():
        return false
    for key in WORKBENCH_FIELDS:
        if not value.has(key):
            return false
    if String(value.get("schema", "")) != SCHEMA or String(value.get("version", "")) != VERSION or String(value.get("revision", "")) != REVISION or String(value.get("mode", "")) != MODE:
        return false
    if not bool(value.get("shadow_only", false)) or typeof(value.get("playing")) != TYPE_BOOL:
        return false
    var controls_value = value.get("spec")
    if not controls_value is Dictionary or not validate_spec(controls_value) or Dictionary(controls_value) != spec:
        return false
    var authorities_value = value.get("authorities")
    if not authorities_value is Dictionary:
        return false
    var authorities: Dictionary = authorities_value
    if authorities.keys().size() != AUTHORITY.keys().size():
        return false
    for key in AUTHORITY.keys():
        if not authorities.has(key) or typeof(authorities[key]) != TYPE_BOOL or bool(authorities[key]) != bool(AUTHORITY[key]):
            return false
    if bool(value.get("playing", false)) != playing:
        return false
    if int(value.get("reset_count", -1)) != reset_count or int(value.get("manual_step_count", -1)) != manual_step_count:
        return false
    var current_ecology: Dictionary = ecology.get_snapshot()
    if int(current_ecology.get("generation", 0)) > 0:
        if not ecology.validate_snapshot(current_ecology):
            return false
    elif String(current_ecology.get("state_hash", "")).length() != 64 or String(current_ecology.get("hereditary_pool_hash", "")).length() != 64:
        return false
    if int(value.get("generation", -1)) != int(current_ecology.get("generation", -2)):
        return false
    if String(value.get("patch_hash", "")) != String(patch.get("patch_hash", "")) or String(value.get("environment_field_hash", "")) != String(environment_field.get("field_hash", "")):
        return false
    if String(value.get("ecology_state_hash", "")) != String(current_ecology.get("state_hash", "")):
        return false
    if String(value.get("population_hash", "")) != String(current_ecology.get("postcompetition_population_hash", "")) or String(value.get("hereditary_pool_hash", "")) != String(current_ecology.get("hereditary_pool_hash", "")):
        return false
    if String(value.get("classification_hash", "")) != String(classification.get("classification_hash", "")):
        return false
    if not classification.is_empty():
        if int(classification.get("generation", -1)) != int(current_ecology.get("generation", -2)):
            return false
        if String(classification.get("source_ecology_state_hash", "")) != String(current_ecology.get("state_hash", "")):
            return false
    var latest: Dictionary = observatory.get_spatial_latest() if observatory != null else {}
    if latest.is_empty() or String(value.get("spatial_observatory_hash", "")) != String(latest.get("observatory_hash", "")):
        return false
    if String(value.get("workbench_hash", "")) != _workbench_hash(value):
        return false
    return true

func get_patch() -> Dictionary:
    return patch.duplicate(true)

func get_environment_field() -> Dictionary:
    return environment_field.duplicate(true)

func get_ecology_snapshot() -> Dictionary:
    return {} if ecology == null else ecology.get_snapshot()

func get_morphology_evidence() -> Dictionary:
    return {} if ecology == null else ecology.get_morphology_evidence()

func validate_morphology_evidence(value: Dictionary) -> bool:
    return ecology != null and ecology.validate_morphology_evidence(value)

func get_classification() -> Dictionary:
    return classification.duplicate(true)

func get_spatial_history() -> Array[Dictionary]:
    return [] if observatory == null else observatory.get_spatial_history()

func _rebuild() -> bool:
    if planet_source == null or not validate_spec(spec):
        return false
    playing = false
    patch = PatchBuilder.new().build(planet_source, _center_direction(int(spec["world_seed"])), GRID_SIZE, CELL_SIZE_M)
    if patch.is_empty():
        return false
    environment_field = EnvironmentField.new().generate(patch, String(spec["environment_recipe"]), int(spec["environment_seed"]))
    if environment_field.is_empty():
        return false
    ecology = LS34.new()
    if not ecology.setup(
        patch, environment_field, FOUNDER_SEED, PLACEMENT_SEED, EVOLUTION_SEED,
        INITIAL_RECORDS, bool(spec["competition_enabled"])
    ):
        return false
    if not ecology.set_evolution_enabled(bool(spec["evolution_enabled"])):
        return false
    classifier = LS35.new()
    classification = {}
    observatory = Observatory.new()
    var initial_ecology: Dictionary = ecology.get_snapshot()
    if String(initial_ecology.get("state_hash", "")).length() != 64 or String(initial_ecology.get("hereditary_pool_hash", "")).length() != 64:
        return false
    if not observatory.setup_spatial(environment_field, initial_ecology):
        return false
    initialized = true
    reset_count += 1
    manual_step_count = 0
    return not get_workbench_snapshot().is_empty()

func _refresh_observability(ecology_snapshot: Dictionary, require_classification: bool) -> bool:
    if ecology_snapshot.is_empty():
        return false
    var total_started := Time.get_ticks_usec()
    var phase_started := Time.get_ticks_usec()
    if int(ecology_snapshot.get("generation", 0)) > 0 and not ecology.validate_snapshot(ecology_snapshot):
        return false
    var repeated_validation_ms := _elapsed_ms(phase_started)

    classification = {}
    var classification_ms := 0.0
    if bool(spec["competition_enabled"]) and int(ecology_snapshot.get("generation", 0)) > 0:
        phase_started = Time.get_ticks_usec()
        classification = classifier.classify(environment_field, ecology_snapshot, true)
        classification_ms = _elapsed_ms(phase_started)
        if require_classification and classification.is_empty():
            return false

    phase_started = Time.get_ticks_usec()
    var recorded: bool = bool(observatory.record_spatial_snapshot(environment_field, ecology_snapshot, classification))
    var spatial_observatory_ms := _elapsed_ms(phase_started)
    last_observability_profile = {
        "repeated_ecology_validation_ms": repeated_validation_ms,
        "classification_ms": classification_ms,
        "classification_detail": classifier.get_last_profile() if classifier != null and classifier.has_method("get_last_profile") else {},
        "spatial_observatory_ms": spatial_observatory_ms,
        "total_ms": _elapsed_ms(total_started),
    }
    return recorded

func _center_direction(world_seed: int) -> Vector3:
    var anchor := LAND_ANCHOR.normalized()
    if world_seed == DEFAULT_WORLD_SEED:
        return anchor
    var east := Vector3.UP.cross(anchor)
    if east.length_squared() < 0.000001:
        east = Vector3.RIGHT.cross(anchor)
    east = east.normalized()
    var north := east.cross(anchor).normalized()
    var ex := (2.0 * _unit01("LS3.6|world|%d|east" % world_seed) - 1.0) * MAX_CENTER_OFFSET_RAD
    var ny := (2.0 * _unit01("LS3.6|world|%d|north" % world_seed) - 1.0) * MAX_CENTER_OFFSET_RAD
    return (anchor + east * tan(ex) + north * tan(ny)).normalized()

func _environment_projection(selector: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for value in Array(environment_field.get("cells", [])):
        var cell: Dictionary = value
        var raw = cell.get(selector, 0.0)
        out.append({
            "index": int(cell["index"]), "x": int(cell["x"]), "y": int(cell["y"]),
            "selector": selector, "value": float(raw),
        })
    return out

func _population_projection(selector: String) -> Array[Dictionary]:
    var counts: Array[int] = []
    var lineages: Array[Dictionary] = []
    counts.resize(GRID_SIZE * GRID_SIZE); counts.fill(0)
    lineages.resize(GRID_SIZE * GRID_SIZE)
    for index in lineages.size():
        lineages[index] = {}
    for value in Array(ecology.get_snapshot().get("records", [])):
        var record: Dictionary = value
        var cell_index := int(record.get("cell_index", -1))
        if cell_index < 0 or cell_index >= counts.size():
            continue
        counts[cell_index] += 1
        var lineage_id := _lineage_id(record)
        if not lineage_id.is_empty():
            lineages[cell_index][lineage_id] = true
    var out: Array[Dictionary] = []
    for index in GRID_SIZE * GRID_SIZE:
        var value := float(counts[index]) if selector == "occupancy" else float(lineages[index].size())
        out.append({
            "index": index, "x": index % GRID_SIZE, "y": index / GRID_SIZE,
            "selector": selector, "value": value,
        })
    return out

func _biome_projection(selector: String) -> Array[Dictionary]:
    if classification.is_empty():
        return []
    var out: Array[Dictionary] = []
    for value in Array(classification.get("cells", [])):
        var cell: Dictionary = value
        out.append({
            "index": int(cell["index"]), "x": int(cell["x"]), "y": int(cell["y"]),
            "selector": selector,
            "label": String(cell["label"] if selector == "emergent_biome" else cell["base_label"]),
        })
    return out

func _lineage_id(record: Dictionary) -> String:
    var bundle_value = record.get("hereditary_bundle")
    if not bundle_value is Dictionary:
        return ""
    var lineage_value = Dictionary(bundle_value).get("lineage_record")
    if not lineage_value is Dictionary:
        return ""
    return String(Dictionary(lineage_value).get("lineage_id", ""))

func _workbench_hash(value: Dictionary) -> String:
    var controls: Dictionary = value.get("spec", {})
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, REVISION,
        str(int(value.get("generation", 0))),
        str(int(controls.get("world_seed", 0))), str(int(controls.get("environment_seed", 0))),
        String(controls.get("environment_recipe", "")),
        str(bool(controls.get("evolution_enabled", false))), str(bool(controls.get("competition_enabled", false))),
        String(value.get("patch_hash", "")), String(value.get("environment_field_hash", "")),
        String(value.get("ecology_state_hash", "")), String(value.get("classification_hash", "")),
        String(value.get("spatial_observatory_hash", "")),
    ])).sha256_text()

func _unit01(key: String) -> float:
    return float(key.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0

func _reset_runtime() -> void:
    initialized = false
    playing = false
    planet_source = null
    spec.clear(); patch.clear(); environment_field.clear(); classification.clear()
    ecology = null; classifier = null; observatory = null
    reset_count = 0; manual_step_count = 0
    last_generation_profile.clear(); generation_profile_history.clear(); last_observability_profile.clear()
