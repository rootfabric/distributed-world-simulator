extends RefCounted

## ECO.EVO7 LS4.1 — deterministic multi-species ecology aggregate.
##
## LS4.1 deliberately does NOT introduce inter-species interaction rules or
## shared resource allocation. Each frozen species population consumes the
## exact same PlanetPatch + EnvironmentField and advances through the accepted
## LS3.3/LS3.4 reproduction -> dispersal -> recruitment -> local competition
## chain. LS4.2 will add typed inter-species edges; LS4.3 will add explicit
## shared resource allocation.
##
## No accepted LS3/PERF2 runtime is modified here. This wrapper is the first
## LS4 authority extension and publishes only a complete aggregate generation.
## If any species step fails after another has advanced, the wrapper poisons
## itself and publishes nothing until an explicit reset/rebuild.

const PatchBuilder = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS34 = preload("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
const SpeciesCatalog = preload("res://scripts/ecology/shadow/eco_evo7_ls41_species_catalog_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_ls41_multi_species.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS4.1-R1"
const MODE := "RESEARCH_SHADOW_ONLY"
const GRID_SIZE := 32
const CELL_SIZE_M := 16.0
const INITIAL_RECORDS_PER_SPECIES := 24
const DEFAULT_WORLD_SEED := 360036
const DEFAULT_ENVIRONMENT_SEED := 310031
const DEFAULT_RECIPE := "MIXED_PHYSICAL_HETEROGENEITY"
const BASE_FOUNDER_SEED := 410041
const BASE_PLACEMENT_SEED := 410042
const BASE_EVOLUTION_SEED := 410043
const LAND_ANCHOR := Vector3(-0.5, -0.86602540378444, 0.0)
const MAX_CENTER_OFFSET_RAD := 0.10
const ALLOWED_STEPS: Array[int] = [1, 10]
const AUTHORITY := {
    "research_shadow_only": true,
    "extends_existing_ls3_chain": true,
    "direct_world_write": false,
    "production_promotion": false,
    "persistence_write": false,
    "network_replication_write": false,
    "renderer_write": false,
    "interaction_graph_authority": false,
    "shared_resource_authority": false,
}

var initialized := false
var poisoned := false
var generation := 0
var planet_source = null
var world_seed := DEFAULT_WORLD_SEED
var environment_seed := DEFAULT_ENVIRONMENT_SEED
var environment_recipe := DEFAULT_RECIPE
var patch: Dictionary = {}
var environment_field: Dictionary = {}
var catalog: Array[Dictionary] = []
var catalog_hash := ""
var species_cores: Array = []

func setup(
    source,
    world_seed_value: int = DEFAULT_WORLD_SEED,
    environment_seed_value: int = DEFAULT_ENVIRONMENT_SEED,
    recipe_id: String = DEFAULT_RECIPE
) -> bool:
    _reset_runtime()
    if source == null or not recipe_id in EnvironmentField.new().recipe_ids():
        return false
    planet_source = source
    world_seed = world_seed_value
    environment_seed = environment_seed_value
    environment_recipe = recipe_id
    return _rebuild()

func reset_same_inputs() -> bool:
    if planet_source == null:
        return false
    return _rebuild()

func apply_physical_controls(world_seed_value: int, environment_seed_value: int, recipe_id: String) -> bool:
    if planet_source == null or not recipe_id in EnvironmentField.new().recipe_ids():
        return false
    world_seed = world_seed_value
    environment_seed = environment_seed_value
    environment_recipe = recipe_id
    return _rebuild()

func step_generations(count: int = 1) -> Dictionary:
    if not initialized or poisoned or not count in ALLOWED_STEPS:
        return {}
    var result: Dictionary = {}
    for _index in count:
        result = _step_one_generation()
        if result.is_empty():
            return {}
    return result

func _step_one_generation() -> Dictionary:
    var expected_generation := generation + 1
    for core_value in species_cores:
        var core = core_value
        var species_result: Dictionary = core.step_generation()
        if species_result.is_empty() or int(species_result.get("generation", -1)) != expected_generation:
            poisoned = true
            return {}
    generation = expected_generation
    var snapshot := get_snapshot()
    if snapshot.is_empty() or not validate_snapshot(snapshot):
        poisoned = true
        return {}
    return snapshot

func get_snapshot() -> Dictionary:
    if not initialized or poisoned:
        return {}
    var species_summaries: Array[Dictionary] = []
    var total_records := 0
    for index in species_cores.size():
        var core = species_cores[index]
        var core_snapshot: Dictionary = core.get_snapshot()
        if core_snapshot.is_empty() or int(core_snapshot.get("generation", -1)) != generation:
            return {}
        var entry: Dictionary = catalog[index]
        var summary := {
            "species_id": String(entry["species_id"]),
            "display_name": String(entry["display_name"]),
            "species_hash": SpeciesCatalog.species_hash(entry),
            "functional_axes": Dictionary(entry["functional_axes"]).duplicate(true),
            "founder_seed": _species_seed(entry, BASE_FOUNDER_SEED, "founder"),
            "placement_seed": _species_seed(entry, BASE_PLACEMENT_SEED, "placement"),
            "evolution_seed": _species_seed(entry, BASE_EVOLUTION_SEED, "evolution"),
            "record_count": int(core_snapshot.get("record_count", 0)),
            "ecology_state_hash": String(core_snapshot.get("state_hash", "")),
            "population_hash": String(core_snapshot.get("postcompetition_population_hash", "")),
            "hereditary_pool_hash": String(core_snapshot.get("hereditary_pool_hash", "")),
        }
        total_records += int(summary["record_count"])
        species_summaries.append(summary)
    species_summaries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["species_id"]) < String(b["species_id"])
    )
    var projection := get_species_projection()
    if projection.size() != GRID_SIZE * GRID_SIZE:
        return {}
    var snapshot := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "mode": MODE,
        "shadow_only": true,
        "generation": generation,
        "source_patch_hash": String(patch.get("patch_hash", "")),
        "environment_field_hash": String(environment_field.get("field_hash", "")),
        "environment_recipe_id": environment_recipe,
        "environment_seed": environment_seed,
        "world_seed": world_seed,
        "species_catalog_hash": catalog_hash,
        "species_count": species_summaries.size(),
        "total_record_count": total_records,
        "species_projection_hash": _projection_hash(projection),
        "species": species_summaries,
        "authorities": AUTHORITY.duplicate(true),
    }
    snapshot["state_hash"] = _state_hash(snapshot)
    return snapshot

func validate_snapshot(value: Dictionary) -> bool:
    if not initialized or poisoned:
        return false
    if String(value.get("schema", "")) != SCHEMA or String(value.get("version", "")) != VERSION:
        return false
    if String(value.get("revision", "")) != REVISION or String(value.get("mode", "")) != MODE:
        return false
    if not bool(value.get("shadow_only", false)) or int(value.get("generation", -1)) != generation:
        return false
    if String(value.get("source_patch_hash", "")) != String(patch.get("patch_hash", "")):
        return false
    if String(value.get("environment_field_hash", "")) != String(environment_field.get("field_hash", "")):
        return false
    if String(value.get("environment_recipe_id", "")) != environment_recipe or int(value.get("environment_seed", -1)) != environment_seed:
        return false
    if int(value.get("world_seed", 0)) != world_seed or String(value.get("species_catalog_hash", "")) != catalog_hash:
        return false
    if int(value.get("species_count", 0)) != catalog.size() or catalog.size() < 3:
        return false
    var authorities_value = value.get("authorities")
    if not authorities_value is Dictionary or Dictionary(authorities_value) != AUTHORITY:
        return false
    var species_value = value.get("species")
    if not species_value is Array or Array(species_value).size() != catalog.size():
        return false
    var by_id := {}
    var total_records := 0
    for item_value in Array(species_value):
        if not item_value is Dictionary:
            return false
        var item: Dictionary = item_value
        var species_id := String(item.get("species_id", ""))
        if species_id.is_empty() or by_id.has(species_id):
            return false
        by_id[species_id] = item
        if String(item.get("species_hash", "")).length() != 64:
            return false
        if String(item.get("ecology_state_hash", "")).length() != 64:
            return false
        if String(item.get("hereditary_pool_hash", "")).length() != 64:
            return false
        total_records += int(item.get("record_count", 0))
    for entry in catalog:
        var species_id := String(entry["species_id"])
        if not by_id.has(species_id):
            return false
        var item: Dictionary = by_id[species_id]
        if String(item["species_hash"]) != SpeciesCatalog.species_hash(entry):
            return false
        if Dictionary(item["functional_axes"]) != Dictionary(entry["functional_axes"]):
            return false
    if int(value.get("total_record_count", -1)) != total_records:
        return false
    var projection := get_species_projection()
    if String(value.get("species_projection_hash", "")) != _projection_hash(projection):
        return false
    if String(value.get("state_hash", "")) != _state_hash(value):
        return false
    return true

func get_patch() -> Dictionary:
    return patch.duplicate(true)

func get_environment_field() -> Dictionary:
    return environment_field.duplicate(true)

func get_species_catalog() -> Array[Dictionary]:
    return catalog.duplicate(true)

func get_species_projection() -> Array[Dictionary]:
    if not initialized or poisoned:
        return []
    var species_ids := PackedStringArray()
    for entry in catalog:
        species_ids.append(String(entry["species_id"]))
    species_ids.sort()
    var counts: Array[Dictionary] = []
    counts.resize(GRID_SIZE * GRID_SIZE)
    for cell_index in counts.size():
        var cell_counts := {}
        for species_id in species_ids:
            cell_counts[species_id] = 0
        counts[cell_index] = cell_counts
    for index in species_cores.size():
        var species_id := String(catalog[index]["species_id"])
        var core_snapshot: Dictionary = species_cores[index].get_snapshot()
        for record_value in Array(core_snapshot.get("records", [])):
            if not record_value is Dictionary:
                return []
            var cell_index := int(Dictionary(record_value).get("cell_index", -1))
            if cell_index < 0 or cell_index >= counts.size():
                return []
            counts[cell_index][species_id] = int(counts[cell_index][species_id]) + 1
    var out: Array[Dictionary] = []
    for cell_index in counts.size():
        var cell_counts: Dictionary = counts[cell_index]
        var dominant := ""
        var dominant_count := 0
        var richness := 0
        var total := 0
        for species_id in species_ids:
            var count := int(cell_counts[species_id])
            total += count
            if count > 0:
                richness += 1
            if count > dominant_count or (count == dominant_count and count > 0 and (dominant.is_empty() or species_id < dominant)):
                dominant = species_id
                dominant_count = count
        out.append({
            "index": cell_index,
            "x": cell_index % GRID_SIZE,
            "y": cell_index / GRID_SIZE,
            "species_counts": cell_counts.duplicate(true),
            "dominant_species_id": dominant,
            "dominant_count": dominant_count,
            "species_richness": richness,
            "total_records": total,
        })
    return out

func get_species_summary(species_id: String) -> Dictionary:
    if not initialized or poisoned:
        return {}
    for item in Array(get_snapshot().get("species", [])):
        if String(Dictionary(item).get("species_id", "")) == species_id:
            return Dictionary(item).duplicate(true)
    return {}

func _rebuild() -> bool:
    initialized = false
    poisoned = false
    generation = 0
    patch.clear()
    environment_field.clear()
    catalog = SpeciesCatalog.catalog()
    catalog_hash = SpeciesCatalog.catalog_hash(catalog)
    species_cores.clear()
    if planet_source == null or catalog_hash.length() != 64 or not SpeciesCatalog.validate_catalog(catalog):
        return false
    patch = PatchBuilder.new().build(planet_source, _center_direction(world_seed), GRID_SIZE, CELL_SIZE_M)
    if patch.is_empty():
        return false
    environment_field = EnvironmentField.new().generate(patch, environment_recipe, environment_seed)
    if environment_field.is_empty():
        return false
    var seen_founder_checksums := {}
    for entry in catalog:
        var core = LS34.new()
        var founder_seed := _species_seed(entry, BASE_FOUNDER_SEED, "founder")
        var placement_seed := _species_seed(entry, BASE_PLACEMENT_SEED, "placement")
        var evolution_seed := _species_seed(entry, BASE_EVOLUTION_SEED, "evolution")
        if not core.setup(
            patch, environment_field,
            founder_seed, placement_seed, evolution_seed,
            INITIAL_RECORDS_PER_SPECIES, true
        ):
            return false
        if not core.set_evolution_enabled(true):
            return false
        var initial: Dictionary = core.get_snapshot()
        var hereditary := String(initial.get("hereditary_pool_hash", ""))
        if hereditary.length() != 64 or seen_founder_checksums.has(hereditary):
            return false
        seen_founder_checksums[hereditary] = true
        if String(initial.get("source_patch_hash", "")) != String(patch.get("patch_hash", "")):
            return false
        if String(initial.get("environment_field_hash", "")) != String(environment_field.get("field_hash", "")):
            return false
        species_cores.append(core)
    initialized = species_cores.size() == catalog.size() and species_cores.size() >= 3
    if not initialized:
        return false
    var snapshot := get_snapshot()
    return not snapshot.is_empty() and validate_snapshot(snapshot)

func _species_seed(entry: Dictionary, base_seed: int, channel: String) -> int:
    var identity := SpeciesCatalog.species_hash(entry)
    if identity.length() != 64:
        return 0
    var offset := int(("%s|%s|%s" % [SCHEMA, channel, identity]).sha256_text().substr(0, 8).hex_to_int() % 1000000)
    return base_seed + offset

func _projection_hash(projection: Array[Dictionary]) -> String:
    var tokens := PackedStringArray([SCHEMA, VERSION, "species-projection", str(generation), catalog_hash])
    for cell in projection:
        tokens.append(str(int(cell.get("index", -1))))
        tokens.append(String(cell.get("dominant_species_id", "")))
        tokens.append(str(int(cell.get("dominant_count", 0))))
        tokens.append(str(int(cell.get("species_richness", 0))))
        tokens.append(str(int(cell.get("total_records", 0))))
        var cell_counts: Dictionary = Dictionary(cell.get("species_counts", {}))
        var ids := PackedStringArray(cell_counts.keys())
        ids.sort()
        for species_id in ids:
            tokens.append("%s=%d" % [species_id, int(cell_counts[species_id])])
    return "|".join(tokens).sha256_text()

func _state_hash(snapshot: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION, REVISION, MODE,
        str(int(snapshot.get("generation", -1))),
        str(int(snapshot.get("world_seed", 0))),
        str(int(snapshot.get("environment_seed", 0))),
        String(snapshot.get("environment_recipe_id", "")),
        String(snapshot.get("source_patch_hash", "")),
        String(snapshot.get("environment_field_hash", "")),
        String(snapshot.get("species_catalog_hash", "")),
        String(snapshot.get("species_projection_hash", "")),
        str(int(snapshot.get("total_record_count", 0))),
    ])
    for item in Array(snapshot.get("species", [])):
        var species: Dictionary = item
        tokens.append(String(species.get("species_id", "")))
        tokens.append(String(species.get("species_hash", "")))
        tokens.append(String(species.get("ecology_state_hash", "")))
        tokens.append(String(species.get("population_hash", "")))
        tokens.append(String(species.get("hereditary_pool_hash", "")))
    return "|".join(tokens).sha256_text()

func _center_direction(seed: int) -> Vector3:
    var anchor := LAND_ANCHOR.normalized()
    if seed == DEFAULT_WORLD_SEED:
        return anchor
    var east := Vector3.UP.cross(anchor)
    if east.length_squared() < 0.000001:
        east = Vector3.RIGHT.cross(anchor)
    east = east.normalized()
    var north := east.cross(anchor).normalized()
    var ex := (2.0 * _unit01("LS4.1|world|%d|east" % seed) - 1.0) * MAX_CENTER_OFFSET_RAD
    var ny := (2.0 * _unit01("LS4.1|world|%d|north" % seed) - 1.0) * MAX_CENTER_OFFSET_RAD
    return (anchor + east * tan(ex) + north * tan(ny)).normalized()

func _unit01(key: String) -> float:
    return float(key.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0

func _reset_runtime() -> void:
    initialized = false
    poisoned = false
    generation = 0
    planet_source = null
    world_seed = DEFAULT_WORLD_SEED
    environment_seed = DEFAULT_ENVIRONMENT_SEED
    environment_recipe = DEFAULT_RECIPE
    patch.clear()
    environment_field.clear()
    catalog.clear()
    catalog_hash = ""
    species_cores.clear()
