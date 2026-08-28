extends RefCounted

## ECO.EVO7 LS3.3 — deterministic RAM-only dispersal + recruitment.
##
## Frozen causal order:
##   parent bundle -> canonical reproduce_bundle() -> immutable child identity
##   -> deterministic dispersal route -> destination physical environment
##   -> establishment gate -> bounded recruitment.
##
## Destination environment never participates in mutation or dispersal identity.
## There is no local competition model here; LS3.4 owns competition.

const Lattice = preload("res://scripts/ecology/shadow/eco_evo7_ls32_spatial_cohort_lattice_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Shadow = preload("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_dispersal_recruitment.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.3.1"
const MODE := "SHADOW_RAM_ONLY"
const GRID_SIZE := 32
const SLOTS_PER_CELL := 4
const MAX_RECORDS := GRID_SIZE * GRID_SIZE * SLOTS_PER_CELL
const OFFSPRING_PER_PARENT := 2
const AUTHORITY := {
    "world_write": false,
    "ecology_production_write": false,
    "persistence_write": false,
    "network_replication_write": false,
    "xfer_authority": false,
    "alternate_mutation_authority": false,
    "competition_authority": false,
    "biome_classifier_ecology_input": false,
}

var initialized := false
var evolution_enabled := true
var generation := 0
var cell_size_m := 0.0
var evolution_seed := 0
var source_patch_hash := ""
var environment_field_hash := ""
var environment_recipe_id := ""
var environment_seed := 0
var founder_seed := 0
var placement_seed := 0
var environment_cells: Array[Dictionary] = []
var records: Array[Dictionary] = []
var last_candidates: Array[Dictionary] = []
var last_routes: Array[Dictionary] = []
var last_recruitment: Array[Dictionary] = []
var last_candidate_pool_hash := ""
var last_dispersal_pool_hash := ""
var last_recruitment_hash := ""
var occupied_map_hash := ""
var hereditary_pool_hash := ""
var population_hash := ""

func setup(
    patch: Dictionary,
    environment_field: Dictionary,
    founder_seed_value: int = 20260832,
    placement_seed_value: int = 320032,
    evolution_seed_value: int = 330033,
    initial_records: int = 256
) -> bool:
    _reset()
    if initial_records < 1 or initial_records > MAX_RECORDS:
        return false
    var lattice = Lattice.new()
    if not lattice.setup(patch, environment_field, founder_seed_value, placement_seed_value, initial_records):
        return false
    var base := lattice.get_snapshot()
    if base.is_empty() or not lattice.validate_snapshot(base):
        return false
    var field_cells_value = environment_field.get("cells")
    if not field_cells_value is Array or Array(field_cells_value).size() != GRID_SIZE * GRID_SIZE:
        return false

    source_patch_hash = String(base["source_patch_hash"])
    environment_field_hash = String(environment_field["field_hash"])
    environment_recipe_id = String(environment_field["recipe_id"])
    environment_seed = int(environment_field["environment_seed"])
    founder_seed = founder_seed_value
    placement_seed = placement_seed_value
    evolution_seed = evolution_seed_value
    cell_size_m = float(base["cell_size_m"])
    environment_cells = Array(field_cells_value).duplicate(true)
    records = _records_from_lattice(base)
    if records.size() != initial_records:
        return false
    generation = 0
    evolution_enabled = true
    _refresh_population_hashes()
    initialized = _validate_current_records(records)
    return initialized

func set_evolution_enabled(value: bool) -> bool:
    if not initialized:
        return false
    evolution_enabled = value
    return true

func step_generation() -> Dictionary:
    if not initialized or not evolution_enabled or records.is_empty():
        return {}
    var next_generation := generation + 1
    var candidates := _build_candidates(records, next_generation)
    if candidates.is_empty():
        return {}
    var routes := _build_routes(candidates, next_generation)
    if routes.size() != candidates.size():
        return {}
    var recruitment := _evaluate_recruitment(candidates, routes, next_generation)
    if recruitment.is_empty():
        return {}
    var next_records := _materialize_recruits(candidates, routes, recruitment, next_generation)

    last_candidates = candidates.duplicate(true)
    last_routes = routes.duplicate(true)
    last_recruitment = recruitment.duplicate(true)
    last_candidate_pool_hash = _candidate_pool_hash(last_candidates)
    last_dispersal_pool_hash = _dispersal_pool_hash(last_routes)
    last_recruitment_hash = _recruitment_hash(last_recruitment)
    generation = next_generation
    records = next_records
    _refresh_population_hashes()

    if not _validate_generation_evidence():
        return {}
    if not records.is_empty() and not _validate_current_records(records):
        return {}
    return get_snapshot()

func get_snapshot() -> Dictionary:
    if not initialized:
        return {}
    var snapshot := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "mode": MODE,
        "shadow_only": true,
        "generation": generation,
        "evolution_enabled": evolution_enabled,
        "grid_size": GRID_SIZE,
        "slots_per_cell": SLOTS_PER_CELL,
        "max_records": MAX_RECORDS,
        "offspring_per_parent": OFFSPRING_PER_PARENT,
        "record_count": records.size(),
        "source_patch_hash": source_patch_hash,
        "environment_field_hash": environment_field_hash,
        "environment_recipe_id": environment_recipe_id,
        "environment_seed": environment_seed,
        "founder_seed": founder_seed,
        "placement_seed": placement_seed,
        "evolution_seed": evolution_seed,
        "candidate_pool_hash": last_candidate_pool_hash,
        "dispersal_pool_hash": last_dispersal_pool_hash,
        "recruitment_hash": last_recruitment_hash,
        "occupied_map_hash": occupied_map_hash,
        "hereditary_pool_hash": hereditary_pool_hash,
        "population_hash": population_hash,
        "records": records.duplicate(true),
        "last_candidates": last_candidates.duplicate(true),
        "last_routes": last_routes.duplicate(true),
        "last_recruitment": last_recruitment.duplicate(true),
        "authorities": AUTHORITY.duplicate(true),
    }
    snapshot["state_hash"] = _state_hash(snapshot)
    return snapshot

func _records_from_lattice(snapshot: Dictionary) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for cell_value in Array(snapshot.get("cells", [])):
        var cell: Dictionary = cell_value
        for slot_value in Array(cell.get("slots", [])):
            var slot: Dictionary = slot_value
            if not bool(slot.get("occupied", false)):
                continue
            var source_record: Dictionary = slot["record"]
            var bundle: Dictionary = Dictionary(source_record["hereditary_bundle"]).duplicate(true)
            out.append(_population_record(
                String(source_record["record_id"]),
                String(source_record["record_id"]),
                int(cell["index"]), int(slot["slot_index"]),
                bundle, 0, "founder", ""))
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    return out

func _build_candidates(parents: Array[Dictionary], next_generation: int) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var ordered := parents.duplicate(true)
    ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    for parent_value in ordered:
        var parent: Dictionary = parent_value
        var parent_bundle: Dictionary = parent["hereditary_bundle"]
        for offspring_ordinal in OFFSPRING_PER_PARENT:
            var mutation_seed := _mutation_seed(parent, next_generation, offspring_ordinal)
            var reproduction := _canonical_reproduce(parent_bundle, mutation_seed, offspring_ordinal)
            if reproduction.is_empty():
                return []
            var child_bundle: Dictionary = Dictionary(reproduction["bundle"]).duplicate(true)
            var candidate := {
                "parent_record_id": String(parent["record_id"]),
                "parent_reproductive_identity": String(parent["reproductive_identity"]),
                "parent_cell_index": int(parent["cell_index"]),
                "generation": next_generation,
                "offspring_ordinal": offspring_ordinal,
                "mutation_seed": mutation_seed,
                "reproduction_result_hash": String(reproduction["result_hash"]),
                "child_bundle_checksum": String(child_bundle["bundle_checksum"]),
                "child_individual_id": String(Dictionary(child_bundle["lineage"])["individual_id"]),
                "child_bundle": child_bundle,
            }
            candidate["candidate_hash"] = _candidate_hash(candidate)
            out.append(candidate)
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["candidate_hash"]) < String(b["candidate_hash"])
    )
    return out

func _canonical_reproduce(parent_bundle: Dictionary, mutation_seed: int, offspring_ordinal: int) -> Dictionary:
    ## The only LS3.3 offspring creation call site. No alternate mutation kernel.
    return LineageExtension.reproduce_bundle(parent_bundle, mutation_seed, offspring_ordinal)

func _mutation_seed(parent: Dictionary, next_generation: int, offspring_ordinal: int) -> int:
    var key := "%s|mutation|%d|%s|%s|%d|%d" % [
        SCHEMA, evolution_seed, String(parent["reproductive_identity"]),
        String(parent["bundle_checksum"]), next_generation, offspring_ordinal,
    ]
    return _seed48(key)

func _build_routes(candidates: Array[Dictionary], next_generation: int) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for candidate_value in candidates:
        var candidate: Dictionary = candidate_value
        var bundle: Dictionary = candidate["child_bundle"]
        var route_seed := _dispersal_seed(candidate, next_generation)
        var route := _route_for_child(
            String(candidate["candidate_hash"]), bundle,
            int(candidate["parent_cell_index"]), route_seed, next_generation)
        if route.is_empty():
            return []
        out.append(route)
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["candidate_hash"]) < String(b["candidate_hash"])
    )
    return out

func _dispersal_seed(candidate: Dictionary, next_generation: int) -> int:
    var key := "%s|dispersal|%d|%s|%s|%d|%d" % [
        SCHEMA, evolution_seed, String(candidate["child_individual_id"]),
        String(candidate["child_bundle_checksum"]), next_generation,
        int(candidate["offspring_ordinal"]),
    ]
    return _seed48(key)

func _route_for_child(candidate_hash: String, bundle: Dictionary, parent_cell_index: int, route_seed: int, next_generation: int) -> Dictionary:
    if parent_cell_index < 0 or parent_cell_index >= GRID_SIZE * GRID_SIZE:
        return {}
    var inherited_distance := maxf(0.0, float(Dictionary(bundle["genome"])["seed_dispersal_distance_m"]))
    var angle_u := _unit01("%d|angle" % route_seed)
    var distance_u := _unit01("%d|distance" % route_seed)
    var angle := angle_u * TAU
    var distance_m := inherited_distance * (0.20 + 1.80 * distance_u)
    var dx_cells := int(round(cos(angle) * distance_m / cell_size_m))
    var dy_cells := int(round(sin(angle) * distance_m / cell_size_m))
    var parent_x := parent_cell_index % GRID_SIZE
    var parent_y := parent_cell_index / GRID_SIZE
    var destination_x := parent_x + dx_cells
    var destination_y := parent_y + dy_cells
    var in_patch := destination_x >= 0 and destination_x < GRID_SIZE and destination_y >= 0 and destination_y < GRID_SIZE
    var destination_index := destination_y * GRID_SIZE + destination_x if in_patch else -1
    var route := {
        "candidate_hash": candidate_hash,
        "generation": next_generation,
        "dispersal_seed": route_seed,
        "parent_cell_index": parent_cell_index,
        "dx_cells": dx_cells,
        "dy_cells": dy_cells,
        "distance_m": snappedf(distance_m, 1e-9),
        "destination_cell_index": destination_index,
        "in_patch": in_patch,
        "out_of_patch_rule": "REJECT",
    }
    route["route_hash"] = _route_hash(route)
    return route

func _evaluate_recruitment(candidates: Array[Dictionary], routes: Array[Dictionary], next_generation: int) -> Array[Dictionary]:
    var candidate_by_hash := {}
    for candidate_value in candidates:
        var candidate: Dictionary = candidate_value
        candidate_by_hash[String(candidate["candidate_hash"])] = candidate
    var out: Array[Dictionary] = []
    for route_value in routes:
        var route: Dictionary = route_value
        var candidate_hash := String(route["candidate_hash"])
        if not candidate_by_hash.has(candidate_hash):
            return []
        var candidate: Dictionary = candidate_by_hash[candidate_hash]
        var in_patch := bool(route["in_patch"])
        var destination_index := int(route["destination_cell_index"])
        if not in_patch:
            var rejected := {
                "candidate_hash": candidate_hash,
                "route_hash": String(route["route_hash"]),
                "generation": next_generation,
                "destination_cell_index": -1,
                "environment_cell_hash": "",
                "evaluation_hash": "",
                "shadow_fitness": -999.0,
                "establishment_capacity": 0.0,
                "establishment_probability": 0.0,
                "establishment_gate": 1.0,
                "eligible": false,
                "reason": "OUT_OF_PATCH",
            }
            rejected["recruitment_event_hash"] = _recruitment_event_hash(rejected)
            out.append(rejected)
            continue
        if destination_index < 0 or destination_index >= environment_cells.size():
            return []
        var env_cell: Dictionary = environment_cells[destination_index]
        var observation := _environment_observation(env_cell, next_generation, candidate_hash)
        if observation.is_empty():
            return []
        var evaluation_result := Shadow.evaluate_bundle_against_observation(candidate["child_bundle"], observation)
        if not bool(evaluation_result.get("success", false)):
            return []
        var evaluation: Dictionary = evaluation_result["details"]
        var fitness := float(evaluation["shadow_fitness"])
        var establishment_capacity := float(evaluation["establishment_capacity"])
        var resource_open := clampf(1.0 - float(env_cell["surface_water_fraction"]), 0.0, 1.0)
        var probability := clampf(0.22 + 0.28 * fitness + 0.34 * establishment_capacity + 0.16 * resource_open, 0.02, 0.98)
        var gate := _unit01("%s|recruit|%d|%d" % [String(candidate["child_bundle_checksum"]), next_generation, destination_index])
        var eligible := float(env_cell["land_mask"]) >= 0.5 and gate < probability
        var reason := "ELIGIBLE" if eligible else ("NON_LAND" if float(env_cell["land_mask"]) < 0.5 else "ESTABLISHMENT_FAIL")
        var event := {
            "candidate_hash": candidate_hash,
            "route_hash": String(route["route_hash"]),
            "generation": next_generation,
            "destination_cell_index": destination_index,
            "environment_cell_hash": String(env_cell["cell_hash"]),
            "evaluation_hash": String(evaluation["shadow_result_hash"]),
            "shadow_fitness": snappedf(fitness, 1e-9),
            "establishment_capacity": snappedf(establishment_capacity, 1e-9),
            "establishment_probability": snappedf(probability, 1e-9),
            "establishment_gate": snappedf(gate, 1e-9),
            "eligible": eligible,
            "reason": reason,
        }
        event["recruitment_event_hash"] = _recruitment_event_hash(event)
        out.append(event)
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["candidate_hash"]) < String(b["candidate_hash"])
    )
    return out

func _environment_observation(env_cell: Dictionary, next_generation: int, candidate_hash: String) -> Dictionary:
    var sand := float(env_cell["soil_texture_sand"])
    var clay := float(env_cell["soil_texture_clay"])
    var texture := "sand" if sand >= 0.55 and sand >= clay else ("clay" if clay >= 0.38 else "loam")
    var env := EnvironmentSample.create(
        float(env_cell["east_m"]), float(env_cell["north_m"]),
        float(env_cell["temperature_c"]), float(env_cell["soil_moisture"]),
        float(env_cell["incident_light"]), 0.50,
        clampf(float(env_cell["surface_water_fraction"]), 0.0, 1.0),
        environment_seed,
        "%s|field=%s|cell=%s" % [REVISION, environment_field_hash, String(env_cell["cell_hash"])]
    )
    if not bool(EnvironmentSample.validate(env).get("success", false)):
        return {}
    var obs := {
        "schema": Shadow.SCHEMA,
        "version": Shadow.VERSION,
        "mode": Shadow.MODE,
        "observation_id": "ls33/%d/%d/%s" % [next_generation, int(env_cell["index"]), candidate_hash.substr(0, 12)],
        "world_time": float(next_generation),
        "live_state_hash": String(env_cell["cell_hash"]),
        "environment_sample": env,
        "shadow_texture_proxy": texture,
        "open_sunlight": float(env_cell["incident_light"]),
        "canopy_adjusted_sunlight": float(env_cell["incident_light"]),
    }
    obs["observation_hash"] = _shadow_observation_hash(obs)
    return obs

func _shadow_observation_hash(observation: Dictionary) -> String:
    return "|".join(PackedStringArray([
        Shadow.SCHEMA, Shadow.VERSION, Shadow.MODE,
        String(observation.get("observation_id", "")),
        "%.9f" % float(observation.get("world_time", -1.0)),
        String(observation.get("live_state_hash", "")),
        String(Dictionary(observation.get("environment_sample", {})).get("checksum", "")),
        String(observation.get("shadow_texture_proxy", "")),
        "%.9f" % float(observation.get("open_sunlight", 0.0)),
        "%.9f" % float(observation.get("canopy_adjusted_sunlight", 0.0)),
    ])).sha256_text()

func _materialize_recruits(candidates: Array[Dictionary], routes: Array[Dictionary], recruitment: Array[Dictionary], next_generation: int) -> Array[Dictionary]:
    var candidate_by_hash := {}
    var route_by_hash := {}
    for candidate_value in candidates:
        var candidate: Dictionary = candidate_value
        candidate_by_hash[String(candidate["candidate_hash"])] = candidate
    for route_value in routes:
        var route: Dictionary = route_value
        route_by_hash[String(route["candidate_hash"])] = route
    var by_destination := {}
    for event_value in recruitment:
        var event: Dictionary = event_value
        if not bool(event["eligible"]):
            continue
        var destination := int(event["destination_cell_index"])
        if not by_destination.has(destination):
            by_destination[destination] = []
        by_destination[destination].append(event)

    var out: Array[Dictionary] = []
    var destinations: Array = by_destination.keys()
    destinations.sort()
    for destination_value in destinations:
        var destination := int(destination_value)
        var events: Array = by_destination[destination]
        ## Capacity is recruitment resource availability, not LS3.4 competition.
        ## Winners are chosen by environment-neutral candidate identity only.
        events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            return String(a["candidate_hash"]) < String(b["candidate_hash"])
        )
        var admitted := mini(SLOTS_PER_CELL, events.size())
        for slot_index in admitted:
            var event: Dictionary = events[slot_index]
            var candidate_hash := String(event["candidate_hash"])
            var candidate: Dictionary = candidate_by_hash[candidate_hash]
            var route: Dictionary = route_by_hash[candidate_hash]
            var record_id := "ls33/%s" % ("%s|%d|%d|%d" % [candidate_hash, next_generation, destination, slot_index]).sha256_text().substr(0, 24)
            out.append(_population_record(
                record_id, candidate_hash, destination, slot_index,
                Dictionary(candidate["child_bundle"]).duplicate(true), next_generation,
                candidate_hash, String(route["route_hash"])))
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    return out

func _population_record(record_id: String, reproductive_identity: String, cell_index: int, slot_index: int, bundle: Dictionary, born_generation: int, candidate_hash: String, route_hash: String) -> Dictionary:
    var record := {
        "record_id": record_id,
        "reproductive_identity": reproductive_identity,
        "cell_index": cell_index,
        "slot_index": slot_index,
        "born_generation": born_generation,
        "candidate_hash": candidate_hash,
        "route_hash": route_hash,
        "bundle_checksum": String(bundle["bundle_checksum"]),
        "hereditary_bundle": bundle.duplicate(true),
    }
    record["record_hash"] = _record_hash(record)
    return record

func _validate_generation_evidence() -> bool:
    if last_candidates.size() != last_routes.size() or last_routes.size() != last_recruitment.size():
        return false
    if last_candidate_pool_hash != _candidate_pool_hash(last_candidates):
        return false
    if last_dispersal_pool_hash != _dispersal_pool_hash(last_routes):
        return false
    if last_recruitment_hash != _recruitment_hash(last_recruitment):
        return false
    var candidate_by_hash := {}
    for candidate_value in last_candidates:
        var candidate: Dictionary = candidate_value
        if String(candidate.get("candidate_hash", "")) != _candidate_hash(candidate):
            return false
        candidate_by_hash[String(candidate["candidate_hash"])] = candidate
    for route_value in last_routes:
        var route: Dictionary = route_value
        var candidate_hash := String(route.get("candidate_hash", ""))
        if not candidate_by_hash.has(candidate_hash):
            return false
        if String(route.get("route_hash", "")) != _route_hash(route):
            return false
        var parent_cell := int(route["parent_cell_index"])
        var expected_x := parent_cell % GRID_SIZE + int(route["dx_cells"])
        var expected_y := parent_cell / GRID_SIZE + int(route["dy_cells"])
        var expected_in_patch := expected_x >= 0 and expected_x < GRID_SIZE and expected_y >= 0 and expected_y < GRID_SIZE
        var expected_destination := expected_y * GRID_SIZE + expected_x if expected_in_patch else -1
        if bool(route["in_patch"]) != expected_in_patch or int(route["destination_cell_index"]) != expected_destination:
            return false
    return true

func _validate_current_records(source_records: Array[Dictionary]) -> bool:
    if source_records.size() > MAX_RECORDS:
        return false
    var bundle_validator = Lattice.new()
    var seen_ids := {}
    var seen_slots := {}
    for record_value in source_records:
        var record: Dictionary = record_value
        var record_id := String(record.get("record_id", ""))
        var reproductive_identity := String(record.get("reproductive_identity", ""))
        if record_id.is_empty() or reproductive_identity.is_empty() or seen_ids.has(record_id):
            return false
        seen_ids[record_id] = true
        var cell_index := int(record.get("cell_index", -1))
        var slot_index := int(record.get("slot_index", -1))
        if cell_index < 0 or cell_index >= GRID_SIZE * GRID_SIZE or slot_index < 0 or slot_index >= SLOTS_PER_CELL:
            return false
        var slot_key := "%d:%d" % [cell_index, slot_index]
        if seen_slots.has(slot_key):
            return false
        seen_slots[slot_key] = true
        var bundle_value = record.get("hereditary_bundle")
        if not bundle_value is Dictionary or not bool(bundle_validator.call("_valid_bundle_identity", bundle_value)):
            return false
        if String(record.get("bundle_checksum", "")) != String(Dictionary(bundle_value).get("bundle_checksum", "")):
            return false
        if String(record.get("record_hash", "")) != _record_hash(record):
            return false
    return true

func _refresh_population_hashes() -> void:
    occupied_map_hash = _occupied_map_hash(records)
    hereditary_pool_hash = _hereditary_pool_hash(records)
    population_hash = _population_hash(records)

func _candidate_hash(candidate: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, "candidate",
        String(candidate.get("parent_reproductive_identity", "")),
        str(int(candidate.get("generation", -1))),
        str(int(candidate.get("offspring_ordinal", -1))),
        str(int(candidate.get("mutation_seed", 0))),
        String(candidate.get("reproduction_result_hash", "")),
        String(candidate.get("child_bundle_checksum", "")),
        String(candidate.get("child_individual_id", "")),
    ])).sha256_text()

func _route_hash(route: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, "route",
        String(route.get("candidate_hash", "")),
        str(int(route.get("generation", -1))),
        str(int(route.get("dispersal_seed", 0))),
        str(int(route.get("parent_cell_index", -1))),
        str(int(route.get("dx_cells", 0))), str(int(route.get("dy_cells", 0))),
        "%.9f" % float(route.get("distance_m", 0.0)),
        str(int(route.get("destination_cell_index", -1))),
        "1" if bool(route.get("in_patch", false)) else "0",
        String(route.get("out_of_patch_rule", "")),
    ])).sha256_text()

func _recruitment_event_hash(event: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, "recruitment",
        String(event.get("candidate_hash", "")), String(event.get("route_hash", "")),
        str(int(event.get("generation", -1))), str(int(event.get("destination_cell_index", -1))),
        String(event.get("environment_cell_hash", "")), String(event.get("evaluation_hash", "")),
        "%.9f" % float(event.get("shadow_fitness", 0.0)),
        "%.9f" % float(event.get("establishment_capacity", 0.0)),
        "%.9f" % float(event.get("establishment_probability", 0.0)),
        "%.9f" % float(event.get("establishment_gate", 0.0)),
        "1" if bool(event.get("eligible", false)) else "0", String(event.get("reason", "")),
    ])).sha256_text()

func _record_hash(record: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, "record",
        String(record.get("record_id", "")), String(record.get("reproductive_identity", "")),
        str(int(record.get("cell_index", -1))),
        str(int(record.get("slot_index", -1))), str(int(record.get("born_generation", -1))),
        String(record.get("candidate_hash", "")), String(record.get("route_hash", "")),
        String(record.get("bundle_checksum", "")),
    ])).sha256_text()

func _candidate_pool_hash(source: Array[Dictionary]) -> String:
    var hashes := PackedStringArray()
    for value in source:
        hashes.append(String(value.get("candidate_hash", "")))
    hashes.sort()
    return (SCHEMA + "|" + VERSION + "|candidate-pool|" + "|".join(hashes)).sha256_text()

func _dispersal_pool_hash(source: Array[Dictionary]) -> String:
    var hashes := PackedStringArray()
    for value in source:
        hashes.append(String(value.get("route_hash", "")))
    hashes.sort()
    return (SCHEMA + "|" + VERSION + "|route-pool|" + "|".join(hashes)).sha256_text()

func _recruitment_hash(source: Array[Dictionary]) -> String:
    var hashes := PackedStringArray()
    for value in source:
        hashes.append(String(value.get("recruitment_event_hash", "")))
    hashes.sort()
    return (SCHEMA + "|" + VERSION + "|recruitment-pool|" + "|".join(hashes)).sha256_text()

func _occupied_map_hash(source: Array[Dictionary]) -> String:
    var addresses := PackedStringArray()
    for record in source:
        addresses.append("%d:%d" % [int(record["cell_index"]), int(record["slot_index"])])
    addresses.sort()
    return (SCHEMA + "|" + VERSION + "|occupied-map|" + "|".join(addresses)).sha256_text()

func _hereditary_pool_hash(source: Array[Dictionary]) -> String:
    var bundles := PackedStringArray()
    for record in source:
        bundles.append(String(record["bundle_checksum"]))
    bundles.sort()
    return (SCHEMA + "|" + VERSION + "|hereditary-pool|" + "|".join(bundles)).sha256_text()

func _population_hash(source: Array[Dictionary]) -> String:
    var hashes := PackedStringArray()
    for record in source:
        hashes.append(String(record["record_hash"]))
    hashes.sort()
    return (SCHEMA + "|" + VERSION + "|population|" + "|".join(hashes)).sha256_text()

func _state_hash(snapshot: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, REVISION, MODE,
        str(int(snapshot.get("generation", -1))),
        "1" if bool(snapshot.get("evolution_enabled", false)) else "0",
        String(snapshot.get("source_patch_hash", "")), String(snapshot.get("environment_field_hash", "")),
        String(snapshot.get("environment_recipe_id", "")), str(int(snapshot.get("environment_seed", 0))),
        str(int(snapshot.get("founder_seed", 0))), str(int(snapshot.get("placement_seed", 0))),
        str(int(snapshot.get("evolution_seed", 0))),
        String(snapshot.get("candidate_pool_hash", "")), String(snapshot.get("dispersal_pool_hash", "")),
        String(snapshot.get("recruitment_hash", "")), String(snapshot.get("occupied_map_hash", "")),
        String(snapshot.get("hereditary_pool_hash", "")), String(snapshot.get("population_hash", "")),
    ])).sha256_text()

func _seed48(key: String) -> int:
    return key.sha256_text().substr(0, 12).hex_to_int()

func _unit01(key: String) -> float:
    return float(key.sha256_text().substr(0, 12).hex_to_int()) / 281474976710655.0

func _reset() -> void:
    initialized = false
    evolution_enabled = true
    generation = 0
    cell_size_m = 0.0
    evolution_seed = 0
    source_patch_hash = ""
    environment_field_hash = ""
    environment_recipe_id = ""
    environment_seed = 0
    founder_seed = 0
    placement_seed = 0
    environment_cells.clear()
    records.clear()
    last_candidates.clear()
    last_routes.clear()
    last_recruitment.clear()
    last_candidate_pool_hash = ""
    last_dispersal_pool_hash = ""
    last_recruitment_hash = ""
    occupied_map_hash = ""
    hereditary_pool_hash = ""
    population_hash = ""
