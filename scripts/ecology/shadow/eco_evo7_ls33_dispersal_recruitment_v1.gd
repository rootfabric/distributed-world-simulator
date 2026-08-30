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
const Par0Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")
## PAR3: the single pure candidate kernel owns mutation-seed derivation, the
## reproduce_bundle call, the candidate field layout and candidate_hash.
## Serial and parallel candidate generation share this ONE implementation.
const Par3CandidateKernel = preload("res://scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd")
const Stream1RouteKernel = preload("res://scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd")
const Stream1Executor = preload("res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_dispersal_recruitment.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.3.2"
const PROFILE_SCHEMA := "distributed_world_simulator.ecology.evo7_perf1.ls33_profile.v1"
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

## LS4 may replace only the dynamic shadow forcing fields between generations.
## Terrain/substrate/address identity remains frozen to the LS3.1 field.
const ENVIRONMENT_FIELD_KEYS: Array[String] = [
    "schema", "version", "revision", "source_patch_hash", "grid_size",
    "cell_size_m", "recipe_id", "environment_seed", "cells", "field_hash",
]
const ENVIRONMENT_CELL_KEYS: Array[String] = [
    "index", "x", "y", "east_m", "north_m", "land_mask",
    "surface_water_fraction", "soil_moisture", "soil_texture_sand",
    "soil_texture_clay", "soil_texture_loam", "soil_water_retention",
    "temperature_c", "incident_light", "elevation_m", "local_relief_m",
    "drainage_index", "rainfall_forcing", "cell_hash",
]
const STATIC_ENVIRONMENT_CELL_FIELDS: Array[String] = [
    "index", "x", "y", "east_m", "north_m", "land_mask",
    "surface_water_fraction", "soil_texture_sand", "soil_texture_clay",
    "soil_texture_loam", "soil_water_retention", "elevation_m",
    "local_relief_m", "drainage_index",
]

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
var last_profile: Dictionary = {}
## PAR0.2: injectable recruitment executor (runtime-only dual-mode seam).
## Absent (null) -> canonical SERIAL path, unchanged. Present -> the executor
## owns serial-oracle + parallel-pool verification and its verified PARALLEL
## result becomes the canonical recruitment source. Injection is explicit
## (set_recruitment_executor); no environment variable activates dual mode.
var _recruitment_executor = null
var _dual_executor_calls := 0
var _last_dual_meta: Dictionary = {}
## PAR3: injectable candidate-build executor. Absent (null) -> the default
## SERIAL candidate path through the single pure kernel. Present -> the
## executor owns parallel candidate construction (fail-closed: any executor
## failure yields an empty candidate list and the generation commits
## nothing). Injection is explicit; no environment variable activates it.
var _candidate_executor = null
var _candidate_executor_calls := 0
var _last_candidate_meta: Dictionary = {}
## STREAM1: optional bounded generation-stream proposal executor. It owns no
## ecology state and is mutually exclusive with PAR2/PAR3 stage executors:
## a generation is either legacy staged execution or one STREAM1 proposal.
var _generation_stream_executor = null
var _generation_stream_executor_calls := 0
var _last_stream_meta: Dictionary = {}

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

## LS4 environment-forcing seam. This changes only the physical input used by
## the NEXT generation. It cannot advance generation or touch population
## identity, and it rejects any attempt to rewrite terrain/substrate/address
## fields. The LS3.1 cell/field hash implementation remains the validator.
func set_environment_field(environment_field: Dictionary) -> bool:
    if not initialized or environment_field.is_empty():
        return false
    if not _exact_environment_keys(environment_field, ENVIRONMENT_FIELD_KEYS):
        return false
    if (
        String(environment_field.get("schema", "")) != EnvironmentField.SCHEMA
        or String(environment_field.get("version", "")) != EnvironmentField.VERSION
        or String(environment_field.get("revision", "")) != EnvironmentField.REVISION
    ):
        return false
    if String(environment_field.get("source_patch_hash", "")) != source_patch_hash:
        return false
    if (
        int(environment_field.get("grid_size", 0)) != GRID_SIZE
        or absf(float(environment_field.get("cell_size_m", 0.0)) - cell_size_m) > 1e-12
    ):
        return false
    if (
        String(environment_field.get("recipe_id", "")) != environment_recipe_id
        or int(environment_field.get("environment_seed", 0)) != environment_seed
    ):
        return false

    var cells_value = environment_field.get("cells")
    if not cells_value is Array or Array(cells_value).size() != GRID_SIZE * GRID_SIZE:
        return false
    if environment_cells.size() != GRID_SIZE * GRID_SIZE:
        return false

    var validator = EnvironmentField.new()
    var next_cells: Array[Dictionary] = []
    for index in GRID_SIZE * GRID_SIZE:
        var value = Array(cells_value)[index]
        if not value is Dictionary:
            return false
        var cell: Dictionary = value
        if not _exact_environment_keys(cell, ENVIRONMENT_CELL_KEYS):
            return false
        if (
            typeof(cell.get("index")) != TYPE_INT
            or typeof(cell.get("x")) != TYPE_INT
            or typeof(cell.get("y")) != TYPE_INT
            or int(cell.get("index", -1)) != index
            or int(cell.get("x", -1)) != index % GRID_SIZE
            or int(cell.get("y", -1)) != index / GRID_SIZE
        ):
            return false
        var current: Dictionary = environment_cells[index]
        for field_name in STATIC_ENVIRONMENT_CELL_FIELDS:
            if cell.get(field_name) != current.get(field_name):
                return false
        for dynamic_name in ["soil_moisture", "temperature_c", "incident_light", "rainfall_forcing"]:
            if not cell.has(dynamic_name):
                return false
            var dynamic_type := typeof(cell[dynamic_name])
            if dynamic_type != TYPE_FLOAT and dynamic_type != TYPE_INT:
                return false
            if not is_finite(float(cell[dynamic_name])):
                return false
        if String(cell.get("cell_hash", "")) != String(validator.call("_cell_hash", cell)):
            return false
        next_cells.append(cell.duplicate(true))

    if String(environment_field.get("field_hash", "")) != String(validator.call("_field_hash", environment_field)):
        return false

    ## Mutation occurs only after the complete replacement field validates.
    environment_field_hash = String(environment_field["field_hash"])
    environment_cells = next_cells
    return true

func _exact_environment_keys(value: Dictionary, expected: Array[String]) -> bool:
    if value.keys().size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true

## PAR0.2: runtime-only dual-mode seam. The executor must implement
## evaluate_generation(generation, candidates, routes, immutable_context)
## -> Dictionary with "success" and "canonical_events". Domain code never
## creates a process pool itself and never selects the executor from env.
func set_recruitment_executor(executor) -> bool:
    if executor == null or _generation_stream_executor != null:
        return false
    _recruitment_executor = executor
    return true

func clear_recruitment_executor() -> void:
    _recruitment_executor = null

func has_recruitment_executor() -> bool:
    return _recruitment_executor != null

## PAR3 candidate-build seam. The executor must implement
## build_candidates(parents, generation) -> Dictionary with "success" and
## "candidates" (canonically sorted by candidate_hash). Domain code never
## spawns worker processes itself.
func set_candidate_executor(executor) -> bool:
    if executor == null or _generation_stream_executor != null:
        return false
    _candidate_executor = executor
    return true

func clear_candidate_executor() -> void:
    _candidate_executor = null

func has_candidate_executor() -> bool:
    return _candidate_executor != null

## STREAM1 authority seam. The executor may compute only a proposal; LS3.3
## validates the base identity and complete proposal before materialization
## and publication. Stage executors and STREAM1 are intentionally exclusive.
func set_generation_stream_executor(executor) -> bool:
    if executor == null or not executor.has_method("execute_generation"):
        return false
    if _candidate_executor != null or _recruitment_executor != null:
        return false
    _generation_stream_executor = executor
    return true

func clear_generation_stream_executor() -> void:
    _generation_stream_executor = null

func has_generation_stream_executor() -> bool:
    return _generation_stream_executor != null

func step_generation() -> Dictionary:
    if not initialized or not evolution_enabled or records.is_empty():
        return {}
    var total_started := Time.get_ticks_usec()
    var parent_count := records.size()
    var next_generation := generation + 1

    var candidates: Array[Dictionary] = []
    var routes: Array[Dictionary] = []
    var recruitment: Array[Dictionary] = []
    var candidate_build_ms := 0.0
    var route_build_ms := 0.0
    var recruitment_eval_ms := 0.0
    var phase_started := 0

    if _generation_stream_executor != null:
        var streamed := _execute_generation_stream(next_generation)
        if streamed.is_empty():
            return {}
        for value in Array(streamed["candidates"]):
            candidates.append(value)
        for value in Array(streamed["routes"]):
            routes.append(value)
        for value in Array(streamed["recruitment"]):
            recruitment.append(value)
        var stream_timings: Dictionary = Dictionary(_last_stream_meta.get("timings_ms", {}))
        candidate_build_ms = float(stream_timings.get("candidate_build_ms", 0.0))
        route_build_ms = float(stream_timings.get("route_build_ms", 0.0))
        recruitment_eval_ms = float(stream_timings.get("recruitment_eval_ms", 0.0))
    else:
        phase_started = Time.get_ticks_usec()
        candidates = _build_candidates(records, next_generation)
        candidate_build_ms = _elapsed_ms(phase_started)
        if candidates.is_empty():
            return {}

        phase_started = Time.get_ticks_usec()
        routes = _build_routes(candidates, next_generation)
        route_build_ms = _elapsed_ms(phase_started)
        if routes.size() != candidates.size():
            return {}

        phase_started = Time.get_ticks_usec()
        recruitment = _evaluate_recruitment(candidates, routes, next_generation)
        recruitment_eval_ms = _elapsed_ms(phase_started)
        if recruitment.is_empty():
            return {}

    phase_started = Time.get_ticks_usec()
    var next_records := _materialize_recruits(candidates, routes, recruitment, next_generation)
    var materialize_ms := _elapsed_ms(phase_started)

    ## Validate the complete proposed generation BEFORE mutating authority
    ## state. This closes the old validate-after-assignment window and makes
    ## every validation failure genuinely fail-closed.
    phase_started = Time.get_ticks_usec()
    var next_candidate_pool_hash := _candidate_pool_hash(candidates)
    var next_dispersal_pool_hash := _dispersal_pool_hash(routes)
    var next_recruitment_hash := _recruitment_hash(recruitment)
    if not _validate_generation_evidence_values(
        candidates, routes, recruitment,
        next_candidate_pool_hash, next_dispersal_pool_hash, next_recruitment_hash
    ):
        return {}
    if not next_records.is_empty() and not _validate_current_records(next_records):
        return {}
    var validation_ms := _elapsed_ms(phase_started)

    ## The only authoritative mutation point for a successful generation.
    phase_started = Time.get_ticks_usec()
    last_candidates = candidates.duplicate(true)
    last_routes = routes.duplicate(true)
    last_recruitment = recruitment.duplicate(true)
    last_candidate_pool_hash = next_candidate_pool_hash
    last_dispersal_pool_hash = next_dispersal_pool_hash
    last_recruitment_hash = next_recruitment_hash
    generation = next_generation
    records = next_records
    _refresh_population_hashes()
    var commit_hash_ms := _elapsed_ms(phase_started)

    phase_started = Time.get_ticks_usec()
    var snapshot := get_snapshot()
    var snapshot_build_ms := _elapsed_ms(phase_started)
    last_profile = {
        "schema": PROFILE_SCHEMA,
        "generation": next_generation,
        "parent_count": parent_count,
        "candidate_count": candidates.size(),
        "recruitment_event_count": recruitment.size(),
        "record_count_after": records.size(),
        ## PAR0.2 telemetry (non-canonical, never enters snapshot hashes):
        ## SERIAL is the default and only mode when no executor is injected.
        "recruitment_mode": "DUAL_VERIFY" if _recruitment_executor != null else "SERIAL",
        "dual_executor_calls": _dual_executor_calls,
        "candidate_build_ms": candidate_build_ms,
        "route_build_ms": route_build_ms,
        "recruitment_eval_ms": recruitment_eval_ms,
        "materialize_ms": materialize_ms,
        "commit_hash_ms": commit_hash_ms,
        "validation_ms": validation_ms,
        "snapshot_build_ms": snapshot_build_ms,
        "total_ms": _elapsed_ms(total_started),
    }
    ## PAR0.2: non-canonical dual-mode metadata (source authority, hashes,
    ## failure evidence). Never enters snapshot or any canonical hash.
    if not _last_dual_meta.is_empty():
        last_profile.merge(_last_dual_meta, true)
    ## PAR3: non-canonical candidate-build telemetry (never hashed).
    if not _last_candidate_meta.is_empty():
        last_profile.merge(_last_candidate_meta, true)
    ## STREAM1: proposal/chunk telemetry is side-channel only.
    if not _last_stream_meta.is_empty():
        last_profile.merge(_last_stream_meta, true)
    return snapshot

func get_last_profile() -> Dictionary:
    return last_profile.duplicate(true)

func _elapsed_ms(start_usec: int) -> float:
    return float(Time.get_ticks_usec() - start_usec) / 1000.0

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
            var reproductive_identity := _founder_reproductive_identity(source_record, bundle)
            if reproductive_identity.is_empty():
                return []
            out.append(_population_record(
                String(source_record["record_id"]),
                reproductive_identity,
                int(cell["index"]), int(slot["slot_index"]),
                bundle, 0, "founder", ""))
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    return out

func _founder_reproductive_identity(source_record: Dictionary, bundle: Dictionary) -> String:
    var record_index := int(source_record.get("record_index", -1))
    var bundle_checksum := String(bundle.get("bundle_checksum", ""))
    if record_index < 0 or bundle_checksum.is_empty():
        return ""
    ## Stable founder identity is hereditary/ordinal, never cell/slot/record-address based.
    return "ls33-founder/%s" % ("%s|%d|%d|%s" % [
        SCHEMA, founder_seed, record_index, bundle_checksum
    ]).sha256_text().substr(0, 24)

func _build_candidates(parents: Array[Dictionary], next_generation: int) -> Array[Dictionary]:
    ## PAR3: the single pure kernel owns the deterministic orchestration
    ## (mutation seed, reproduce_bundle call, fields, candidate_hash); the
    ## serial loop, formulas and ordering are unchanged. When a candidate
    ## executor is injected, it owns construction through the SAME kernel in
    ## parallel workers; every failure is fail-closed (empty result -> the
    ## generation commits nothing).
    if _candidate_executor != null:
        _candidate_executor_calls += 1
        var par3_result: Dictionary = _candidate_executor.build_candidates(parents, next_generation)
        _last_candidate_meta = {
            "candidate_build_mode": "PAR3_PARALLEL",
            "candidate_executor_calls": _candidate_executor_calls,
            "canonical_source": String(par3_result.get("canonical_source", "")),
            "comparison_passed": bool(par3_result.get("comparison_passed", false)),
        }
        if not bool(par3_result.get("success", false)):
            _last_candidate_meta["failure_code"] = String(par3_result.get("failure_code", "PAR3_CANDIDATE_EXECUTOR_FAILURE"))
            last_profile.merge(_last_candidate_meta, true)
            return []
        var parallel_candidates_value = par3_result.get("candidates", [])
        if not parallel_candidates_value is Array or (parallel_candidates_value as Array).size() != parents.size() * OFFSPRING_PER_PARENT:
            _last_candidate_meta["failure_code"] = "PAR3_CANDIDATE_COUNT_MISMATCH"
            last_profile.merge(_last_candidate_meta, true)
            return []
        var out_parallel: Array[Dictionary] = []
        for candidate_value in parallel_candidates_value:
            if not candidate_value is Dictionary:
                _last_candidate_meta["failure_code"] = "PAR3_CANDIDATE_TYPE_INVALID"
                last_profile.merge(_last_candidate_meta, true)
                return []
            out_parallel.append(candidate_value)
        return Par3CandidateKernel.sort_candidates(out_parallel)
    _last_candidate_meta = {}
    return Par3CandidateKernel.build_all(
        parents, next_generation, SCHEMA, VERSION, evolution_seed, OFFSPRING_PER_PARENT)

func _build_routes(candidates: Array[Dictionary], next_generation: int) -> Array[Dictionary]:
    return Stream1RouteKernel.build_all(
        candidates, next_generation, SCHEMA, VERSION,
        evolution_seed, cell_size_m, GRID_SIZE)

func _dispersal_seed(candidate: Dictionary, next_generation: int) -> int:
    return Stream1RouteKernel.dispersal_seed(candidate, next_generation, SCHEMA, evolution_seed)

func _route_for_child(candidate_hash: String, bundle: Dictionary, parent_cell_index: int, route_seed: int, next_generation: int) -> Dictionary:
    return Stream1RouteKernel.route_for_child(
        candidate_hash, bundle, parent_cell_index, route_seed, next_generation,
        SCHEMA, VERSION, cell_size_m, GRID_SIZE)

func _evaluate_recruitment(candidates: Array[Dictionary], routes: Array[Dictionary], next_generation: int) -> Array[Dictionary]:
	## PERF1-PAR0: the per-candidate calculation lives in the shared pure
    ## kernel (single implementation, also used by PAR0 workers). The serial
    ## evaluation order, formulas and hashes are unchanged; this loop is the
    ## canonical serial oracle.
    var candidate_by_hash := {}
    for candidate_value in candidates:
        var candidate: Dictionary = candidate_value
        candidate_by_hash[String(candidate["candidate_hash"])] = candidate
    var context := Par0Kernel.build_context(
        SCHEMA, VERSION, REVISION,
        environment_seed, environment_field_hash, environment_cells)

    ## PAR0.2 dual mode: an explicitly injected executor owns the
    ## serial-oracle + process-pool verification. On any failure the result
    ## is fail-closed: empty recruitment -> step_generation commits nothing.
    ## The verified PARALLEL event list becomes the canonical source.
    if _recruitment_executor != null:
        _dual_executor_calls += 1
        var dual_result: Dictionary = _recruitment_executor.evaluate_generation(
            next_generation, candidates, routes, context)
        _last_dual_meta = {
            "recruitment_mode": "DUAL_VERIFY",
            "dual_executor_calls": _dual_executor_calls,
            "canonical_source": String(dual_result.get("canonical_source", "")),
            "comparison_passed": bool(dual_result.get("comparison_passed", false)),
            "serial_hash": String(dual_result.get("serial_hash", "")),
            "parallel_hash": String(dual_result.get("parallel_hash", "")),
        }
        if not bool(dual_result.get("success", false)):
            _last_dual_meta["failure_code"] = String(dual_result.get("failure_code", "PAR02_EXECUTOR_FAILURE"))
            _last_dual_meta["evidence_path"] = String(dual_result.get("evidence_path", ""))
            last_profile.merge(_last_dual_meta, true)
            return []
        var parallel_events: Array = dual_result.get("canonical_events", [])
        if parallel_events.size() != candidates.size():
            _last_dual_meta["failure_code"] = "PAR02_EVENT_COUNT_MISMATCH"
            last_profile.merge(_last_dual_meta, true)
            return []
        var out: Array[Dictionary] = []
        for event_value in parallel_events:
            if not event_value is Dictionary:
                _last_dual_meta["failure_code"] = "PAR02_EVENT_TYPE_INVALID"
                last_profile.merge(_last_dual_meta, true)
                return []
            out.append(event_value)
        return out

    _last_dual_meta = {}
    var out_serial: Array[Dictionary] = []
    for route_value in routes:
        var route: Dictionary = route_value
        var candidate_hash := String(route["candidate_hash"])
        if not candidate_by_hash.has(candidate_hash):
            return []
        var candidate: Dictionary = candidate_by_hash[candidate_hash]
        var event_result := Par0Kernel.evaluate_recruitment_event(candidate, route, context)
        if event_result.is_empty():
            return []
        var event: Dictionary = event_result
        event["recruitment_event_hash"] = Par0Kernel.recruitment_event_hash(event, SCHEMA, VERSION)
        out_serial.append(event)
    out_serial.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["candidate_hash"]) < String(b["candidate_hash"])
    )
    return out_serial

func _execute_generation_stream(next_generation: int) -> Dictionary:
    _generation_stream_executor_calls += 1
    var context := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "evolution_seed": evolution_seed,
        "offspring_per_parent": OFFSPRING_PER_PARENT,
        "cell_size_m": cell_size_m,
        "grid_size": GRID_SIZE,
        "environment_seed": environment_seed,
        "environment_field_hash": environment_field_hash,
        "environment_cells": environment_cells.duplicate(true),
        "base_generation": generation,
        "base_population_hash": population_hash,
    }
    var result: Dictionary = _generation_stream_executor.execute_generation(
        records.duplicate(true), next_generation, context)
    var report: Dictionary = Dictionary(result.get("report", {}))
    _last_stream_meta = {
        "stream_mode": "STREAM1_BOUNDED_PROPOSAL",
        "stream_executor_calls": _generation_stream_executor_calls,
        "stream_source": String(result.get("source", "")),
        "stream_chunk_count": int(report.get("chunk_count", 0)),
        "stream_parents_per_chunk": int(report.get("parents_per_chunk", 0)),
        "stream_max_parent_chunk": int(report.get("max_parent_chunk", 0)),
        "stream_max_candidate_chunk": int(report.get("max_candidate_chunk", 0)),
        "stream_audited": bool(report.get("audited", false)),
        "stream_proposal_hash": String(report.get("proposal_hash", "")),
        "timings_ms": Dictionary(report.get("timings_ms", {})).duplicate(true),
    }
    if not bool(result.get("success", false)):
        _last_stream_meta["failure_code"] = String(result.get("failure_code", "STREAM1_EXECUTOR_FAILURE"))
        _last_stream_meta["failure_detail"] = String(result.get("failure_detail", ""))
        last_profile = _last_stream_meta.duplicate(true)
        return {}
    var proposal_value = result.get("proposal")
    if not proposal_value is Dictionary:
        _last_stream_meta["failure_code"] = "STREAM1_PROPOSAL_TYPE_INVALID"
        last_profile = _last_stream_meta.duplicate(true)
        return {}
    var proposal: Dictionary = proposal_value
    var accepted := _validate_stream_proposal(proposal, next_generation)
    if accepted.is_empty():
        last_profile = _last_stream_meta.duplicate(true)
        return {}
    return accepted

func _validate_stream_proposal(proposal: Dictionary, next_generation: int) -> Dictionary:
    if not Stream1Executor.validate_proposal_shape(proposal):
        _last_stream_meta["failure_code"] = "STREAM1_PROPOSAL_INVALID"
        return {}
    if int(proposal.get("generation", -1)) != next_generation     or int(proposal.get("base_generation", -1)) != generation     or String(proposal.get("base_population_hash", "")) != population_hash:
        _last_stream_meta["failure_code"] = "STREAM1_STALE_BASE"
        return {}
    if int(proposal.get("parent_count", -1)) != records.size()     or int(proposal.get("candidate_count", -1)) != records.size() * OFFSPRING_PER_PARENT:
        _last_stream_meta["failure_code"] = "STREAM1_COUNT_MISMATCH"
        return {}

    var candidates: Array[Dictionary] = []
    var routes: Array[Dictionary] = []
    var recruitment: Array[Dictionary] = []
    for value in Array(proposal["candidates"]):
        if not value is Dictionary:
            _last_stream_meta["failure_code"] = "STREAM1_CANDIDATE_TYPE_INVALID"
            return {}
        candidates.append(value)
    for value in Array(proposal["routes"]):
        if not value is Dictionary:
            _last_stream_meta["failure_code"] = "STREAM1_ROUTE_TYPE_INVALID"
            return {}
        routes.append(value)
    for value in Array(proposal["recruitment"]):
        if not value is Dictionary:
            _last_stream_meta["failure_code"] = "STREAM1_RECRUITMENT_TYPE_INVALID"
            return {}
        recruitment.append(value)
    if candidates.size() != records.size() * OFFSPRING_PER_PARENT     or routes.size() != candidates.size() or recruitment.size() != candidates.size():
        _last_stream_meta["failure_code"] = "STREAM1_COUNT_MISMATCH"
        return {}
    if not _candidate_order_canonical(candidates)     or not _candidate_order_canonical(routes)     or not _candidate_order_canonical(recruitment):
        _last_stream_meta["failure_code"] = "STREAM1_NONCANONICAL_ORDER"
        return {}

    var parent_by_record_id := {}
    for parent in records:
        parent_by_record_id[String(parent.get("record_id", ""))] = parent
    var bundle_validator = Lattice.new()
    var seen_parent_ordinals := {}
    var candidate_by_hash := {}
    for candidate in candidates:
        var candidate_hash := String(candidate.get("candidate_hash", ""))
        if candidate_hash.is_empty() or candidate_by_hash.has(candidate_hash)         or candidate_hash != Par3CandidateKernel.candidate_hash(SCHEMA, VERSION, candidate):
            _last_stream_meta["failure_code"] = "STREAM1_CANDIDATE_HASH_INVALID"
            return {}
        var parent_record_id := String(candidate.get("parent_record_id", ""))
        if not parent_by_record_id.has(parent_record_id)         or not Par3CandidateKernel.validate_parent_binding(
            parent_by_record_id[parent_record_id], candidate, next_generation,
            SCHEMA, evolution_seed, OFFSPRING_PER_PARENT
        ):
            _last_stream_meta["failure_code"] = "STREAM1_CANDIDATE_PARENT_BINDING_INVALID"
            return {}
        var child_bundle_value = candidate.get("child_bundle")
        if not child_bundle_value is Dictionary         or not bool(bundle_validator.call("_valid_bundle_identity", child_bundle_value)):
            _last_stream_meta["failure_code"] = "STREAM1_CANDIDATE_BUNDLE_INVALID"
            return {}
        var parent_ordinal_key := "%s:%d" % [
            parent_record_id, int(candidate.get("offspring_ordinal", -1))
        ]
        if seen_parent_ordinals.has(parent_ordinal_key):
            _last_stream_meta["failure_code"] = "STREAM1_CANDIDATE_PARENT_BINDING_INVALID"
            return {}
        seen_parent_ordinals[parent_ordinal_key] = true
        candidate_by_hash[candidate_hash] = candidate
    if seen_parent_ordinals.size() != records.size() * OFFSPRING_PER_PARENT:
        _last_stream_meta["failure_code"] = "STREAM1_CANDIDATE_PARENT_BINDING_INVALID"
        return {}

    var route_by_hash := {}
    for route in routes:
        var candidate_hash := String(route.get("candidate_hash", ""))
        if not candidate_by_hash.has(candidate_hash) or route_by_hash.has(candidate_hash)         or int(route.get("generation", -1)) != next_generation:
            _last_stream_meta["failure_code"] = "STREAM1_ROUTE_HASH_INVALID"
            return {}
        var expected_route := Stream1RouteKernel.build_route(
            candidate_by_hash[candidate_hash], next_generation,
            SCHEMA, VERSION, evolution_seed, cell_size_m, GRID_SIZE
        )
        if expected_route.is_empty() or route != expected_route:
            _last_stream_meta["failure_code"] = "STREAM1_ROUTE_HASH_INVALID"
            return {}
        route_by_hash[candidate_hash] = route

    for event in recruitment:
        var candidate_hash := String(event.get("candidate_hash", ""))
        if not candidate_by_hash.has(candidate_hash) or not route_by_hash.has(candidate_hash)         or int(event.get("generation", -1)) != next_generation         or String(event.get("route_hash", "")) != String(route_by_hash[candidate_hash].get("route_hash", ""))         or int(event.get("destination_cell_index", -2)) != int(route_by_hash[candidate_hash].get("destination_cell_index", -3))         or String(event.get("recruitment_event_hash", "")) != Par0Kernel.recruitment_event_hash(event, SCHEMA, VERSION):
            _last_stream_meta["failure_code"] = "STREAM1_RECRUITMENT_HASH_INVALID"
            return {}
        var destination := int(event.get("destination_cell_index", -1))
        if bool(route_by_hash[candidate_hash].get("in_patch", false)):
            if destination < 0 or destination >= environment_cells.size()             or String(event.get("environment_cell_hash", "")) != String(environment_cells[destination].get("cell_hash", "")):
                _last_stream_meta["failure_code"] = "STREAM1_RECRUITMENT_ENV_BINDING_INVALID"
                return {}
        elif destination != -1 or not String(event.get("environment_cell_hash", "")).is_empty():
            _last_stream_meta["failure_code"] = "STREAM1_RECRUITMENT_ENV_BINDING_INVALID"
            return {}

    if String(proposal.get("candidate_pool_hash", "")) != _candidate_pool_hash(candidates)     or String(proposal.get("dispersal_pool_hash", "")) != _dispersal_pool_hash(routes)     or String(proposal.get("recruitment_hash", "")) != _recruitment_hash(recruitment)     or String(proposal.get("proposal_hash", "")) != Stream1Executor.proposal_hash(proposal):
        _last_stream_meta["failure_code"] = "STREAM1_PROPOSAL_HASH_MISMATCH"
        return {}
    return {
        "candidates": candidates,
        "routes": routes,
        "recruitment": recruitment,
    }

func _candidate_order_canonical(source: Array[Dictionary]) -> bool:
    var previous := ""
    for value in source:
        var current := String(value.get("candidate_hash", ""))
        if current.is_empty() or (not previous.is_empty() and (current == previous or current < previous)):
            return false
        previous = current
    return true

func _environment_observation(env_cell: Dictionary, next_generation: int, candidate_hash: String) -> Dictionary:
    ## PERF1-PAR0: observation construction moved to the shared kernel.
    var context := Par0Kernel.build_context(
        SCHEMA, VERSION, REVISION,
        environment_seed, environment_field_hash, environment_cells)
    return Par0Kernel.build_observation(env_cell, context, next_generation, candidate_hash)

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
    return _validate_generation_evidence_values(
        last_candidates, last_routes, last_recruitment,
        last_candidate_pool_hash, last_dispersal_pool_hash, last_recruitment_hash
    )

func _validate_generation_evidence_values(
    candidate_values: Array[Dictionary],
    route_values: Array[Dictionary],
    recruitment_values: Array[Dictionary],
    candidate_pool_hash_value: String,
    dispersal_pool_hash_value: String,
    recruitment_hash_value: String
) -> bool:
    if candidate_values.size() != route_values.size() or route_values.size() != recruitment_values.size():
        return false
    if candidate_pool_hash_value != _candidate_pool_hash(candidate_values):
        return false
    if dispersal_pool_hash_value != _dispersal_pool_hash(route_values):
        return false
    if recruitment_hash_value != _recruitment_hash(recruitment_values):
        return false
    var candidate_by_hash := {}
    for candidate in candidate_values:
        var candidate_hash := String(candidate.get("candidate_hash", ""))
        if candidate_hash.is_empty() or candidate_by_hash.has(candidate_hash):
            return false
        if candidate_hash != Par3CandidateKernel.candidate_hash(SCHEMA, VERSION, candidate):
            return false
        candidate_by_hash[candidate_hash] = candidate
    var route_by_hash := {}
    for route in route_values:
        var candidate_hash := String(route.get("candidate_hash", ""))
        if not candidate_by_hash.has(candidate_hash) or route_by_hash.has(candidate_hash):
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
        route_by_hash[candidate_hash] = route
    for event in recruitment_values:
        var candidate_hash := String(event.get("candidate_hash", ""))
        if not route_by_hash.has(candidate_hash):
            return false
        if String(event.get("route_hash", "")) != String(route_by_hash[candidate_hash].get("route_hash", "")):
            return false
        if String(event.get("recruitment_event_hash", "")) != Par0Kernel.recruitment_event_hash(event, SCHEMA, VERSION):
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

func _route_hash(route: Dictionary) -> String:
    return Stream1RouteKernel.route_hash(route, SCHEMA, VERSION)

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
    return Stream1RouteKernel.route_pool_hash(source, SCHEMA, VERSION)

func _recruitment_hash(source: Array[Dictionary]) -> String:
    return Par0Kernel.recruitment_pool_hash(source, SCHEMA, VERSION)

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

func _reset() -> void:
    initialized = false
    evolution_enabled = true
    generation = 0
    ## PAR0.2: a reset simulation starts SERIAL again; the owner must
    ## re-inject the executor explicitly for the new run (no hidden dual).
    _recruitment_executor = null
    _dual_executor_calls = 0
    _last_dual_meta = {}
    ## PAR3: same isolation for the candidate-build executor.
    _candidate_executor = null
    _candidate_executor_calls = 0
    _last_candidate_meta = {}
    ## STREAM1: no executor survives a simulation reset/rebuild.
    _generation_stream_executor = null
    _generation_stream_executor_calls = 0
    _last_stream_meta = {}
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
    last_profile.clear()
