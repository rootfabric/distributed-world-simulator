extends RefCounted

## ECO.EVO7 LS3.4 — deterministic local competition for light / water / space.
##
## Causal order remains:
##   LS3.3 reproduction + dispersal + recruitment
##   -> pre-competition realized phenotype
##   -> physical light/water/space feedback field
##   -> deterministic local survival
##
## Competition never changes mutation/dispersal identity already created by LS3.3.
## No biome label, renderer state, persistence, networking or production authority.

const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const FunctionalPhenotype = preload("res://scripts/research/ecology/plant_functional_phenotype_v1.gd")
const MorphologyEvidence = preload("res://scripts/research/ecology/plant_morphology_evidence_v1.gd")
const GraphReconstructionEvidence = preload("res://scripts/research/ecology/plant_growth_graph_reconstruction_evidence_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const LightField = preload("res://scripts/research/ecology/understory_light_field_v1.gd")
const WaterField = preload("res://scripts/research/ecology/soil_water_field_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_local_competition.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.4.2"
const PROFILE_SCHEMA := "distributed_world_simulator.ecology.evo7_perf1.ls34_profile.v1"
const MODE := "SHADOW_RAM_ONLY"
const GRID_SIZE := 32
const SLOTS_PER_CELL := 4
const CELL_SIZE_M := 16.0
const MOORE_RADIUS_CELLS := 1
const MAX_TRAIT_RADIUS_CELLS := 2
const SURVIVAL_BALANCE_FLOOR := -0.35
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
var competition_enabled := true
var core = null
var environment_cells: Array[Dictionary] = []
var last_competition_field: Dictionary = {}
var last_competition_hash := ""
var last_precompetition_population_hash := ""
var last_postcompetition_population_hash := ""
var last_survivor_count := 0
var last_culled_count := 0
var last_profile: Dictionary = {}
var last_competition_profile: Dictionary = {}
var last_morphology_records: Array[Dictionary] = []
var last_morphology_evidence: Dictionary = {}
var last_graph_reconstruction_records: Array[Dictionary] = []
var last_graph_reconstruction_evidence: Dictionary = {}

func setup(
    patch: Dictionary,
    environment_field: Dictionary,
    founder_seed_value: int = 20260832,
    placement_seed_value: int = 320032,
    evolution_seed_value: int = 330033,
    initial_records: int = 64,
    competition_enabled_value: bool = true
) -> bool:
    _reset()
    core = LS33.new()
    if not core.setup(patch, environment_field, founder_seed_value, placement_seed_value, evolution_seed_value, initial_records):
        return false
    var values = environment_field.get("cells")
    if not values is Array or Array(values).size() != GRID_SIZE * GRID_SIZE:
        return false
    environment_cells = Array(values).duplicate(true)
    competition_enabled = competition_enabled_value
    initialized = true
    return true

func set_evolution_enabled(value: bool) -> bool:
    if not initialized:
        return false
    return core.set_evolution_enabled(value)

func set_competition_enabled(value: bool) -> bool:
    if not initialized:
        return false
    if competition_enabled != value:
        last_morphology_records.clear()
        last_morphology_evidence.clear()
        last_graph_reconstruction_records.clear()
        last_graph_reconstruction_evidence.clear()
    competition_enabled = value
    return true

## PAR2 minimal pass-through: LS3.4 stays backend-ignorant; it only forwards
## the existing LS3.3 executor seam. No private-member tunneling beyond the
## public core handle LS3.4 itself owns.
func set_recruitment_executor(executor) -> bool:
    if not initialized or core == null:
        return false
    return core.set_recruitment_executor(executor)

func clear_recruitment_executor() -> void:
    if core != null:
        core.clear_recruitment_executor()

func has_recruitment_executor() -> bool:
    return core != null and core.has_recruitment_executor()

## PAR3 public pass-through: candidate execution is composed above LS3.3
## without exposing the core topology to PLAY0/runtime clients.
func set_candidate_executor(executor) -> bool:
    if not initialized or core == null:
        return false
    return core.set_candidate_executor(executor)

func clear_candidate_executor() -> void:
    if core != null:
        core.clear_candidate_executor()

func has_candidate_executor() -> bool:
    return core != null and core.has_candidate_executor()

func step_generation() -> Dictionary:
    if not initialized:
        return {}
    var total_started := Time.get_ticks_usec()
    var phase_started := Time.get_ticks_usec()
    var pre: Dictionary = core.step_generation()
    var ls33_total_ms := _elapsed_ms(phase_started)
    if pre.is_empty():
        return {}
    last_precompetition_population_hash = String(pre["population_hash"])
    last_competition_field = {}
    last_competition_hash = ""
    last_culled_count = 0
    last_profile.clear()
    last_competition_profile.clear()
    last_morphology_records.clear()
    last_morphology_evidence.clear()
    last_graph_reconstruction_records.clear()
    last_graph_reconstruction_evidence.clear()
    last_graph_reconstruction_records.clear()
    last_graph_reconstruction_evidence.clear()
    last_survivor_count = int(pre["record_count"])

    var competition_pass_ms := 0.0
    var survivor_apply_ms := 0.0
    if competition_enabled:
        if int(pre["record_count"]) > 0:
            phase_started = Time.get_ticks_usec()
            var competition_result: Dictionary = _competition_pass(Array(pre["records"]), int(pre["generation"]))
            competition_pass_ms = _elapsed_ms(phase_started)
            if competition_result.is_empty():
                return {}
            phase_started = Time.get_ticks_usec()
            var survivors: Array[Dictionary] = competition_result["survivors"]
            last_competition_field = Dictionary(competition_result["field"]).duplicate(true)
            last_competition_hash = String(last_competition_field["field_hash"])
            last_morphology_records = Array(competition_result.get("morphology_records", [])).duplicate(true)
            last_graph_reconstruction_records = Array(competition_result.get("graph_reconstruction_records", [])).duplicate(true)
            last_survivor_count = survivors.size()
            last_culled_count = int(pre["record_count"]) - survivors.size()
            core.records = survivors.duplicate(true)
            core.call("_refresh_population_hashes")
            if not survivors.is_empty() and not bool(core.call("_validate_current_records", survivors)):
                return {}
            survivor_apply_ms = _elapsed_ms(phase_started)
        else:
            phase_started = Time.get_ticks_usec()
            last_competition_field = _empty_competition_field(int(pre["generation"]))
            competition_pass_ms = _elapsed_ms(phase_started)
            if last_competition_field.is_empty():
                return {}
            last_competition_hash = String(last_competition_field["field_hash"])

    phase_started = Time.get_ticks_usec()
    var post: Dictionary = core.get_snapshot()
    last_postcompetition_population_hash = String(post["population_hash"])
    var post_snapshot_ms := _elapsed_ms(phase_started)
    if competition_enabled and int(pre.get("generation", 0)) > 0:
        last_morphology_evidence = MorphologyEvidence.seal_snapshot(
            last_morphology_records,
            int(pre["generation"]),
            last_precompetition_population_hash,
            last_competition_hash,
            last_postcompetition_population_hash,
            int(post.get("record_count", -1))
        )
        last_graph_reconstruction_evidence = GraphReconstructionEvidence.seal_snapshot(
            last_graph_reconstruction_records,
            int(pre["generation"]),
            last_precompetition_population_hash,
            last_competition_hash,
            last_postcompetition_population_hash,
            int(post.get("record_count", -1))
        )

    phase_started = Time.get_ticks_usec()
    var snapshot := get_snapshot()
    var snapshot_build_ms := _elapsed_ms(phase_started)
    last_profile = {
        "schema": PROFILE_SCHEMA,
        "generation": int(pre.get("generation", -1)),
        "record_count_precompetition": int(pre.get("record_count", 0)),
        "record_count_postcompetition": int(post.get("record_count", 0)),
        "ls33_total_ms": ls33_total_ms,
        "competition_pass_ms": competition_pass_ms,
        "survivor_apply_ms": survivor_apply_ms,
        "post_snapshot_ms": post_snapshot_ms,
        "snapshot_build_ms": snapshot_build_ms,
        "competition": last_competition_profile.duplicate(true),
        "ls33": core.get_last_profile(),
        "total_ms": _elapsed_ms(total_started),
    }
    return snapshot

func get_last_profile() -> Dictionary:
    return last_profile.duplicate(true)

func get_morphology_evidence() -> Dictionary:
    return last_morphology_evidence.duplicate(true)

func validate_morphology_evidence(evidence: Dictionary) -> bool:
    if not initialized or not MorphologyEvidence.validate_snapshot(evidence):
        return false
    if last_morphology_evidence.is_empty():
        return false
    if String(evidence.get("evidence_hash", "")) != String(last_morphology_evidence.get("evidence_hash", "")):
        return false
    var current: Dictionary = core.get_snapshot()
    if int(evidence.get("generation", -1)) != int(current.get("generation", -2)):
        return false
    if String(evidence.get("source_precompetition_population_hash", "")) != last_precompetition_population_hash:
        return false
    if String(evidence.get("source_competition_hash", "")) != last_competition_hash:
        return false
    if String(evidence.get("source_postcompetition_population_hash", "")) != String(current.get("population_hash", "")):
        return false
    var current_records: Array = Array(current.get("records", []))
    if int(evidence.get("record_count", -1)) != current_records.size():
        return false
    var evidence_by_id := {}
    for value in Array(evidence.get("records", [])):
        if not value is Dictionary:
            return false
        var item: Dictionary = value
        evidence_by_id[String(item.get("record_id", ""))] = item
    for value in current_records:
        if not value is Dictionary:
            return false
        var record: Dictionary = value
        var record_id := String(record.get("record_id", ""))
        if not evidence_by_id.has(record_id):
            return false
        var item: Dictionary = evidence_by_id[record_id]
        if int(item.get("cell_index", -1)) != int(record.get("cell_index", -2)):
            return false
        if String(item.get("bundle_checksum", "")) != String(record.get("bundle_checksum", "")):
            return false
        var bundle_value = record.get("hereditary_bundle")
        if not bundle_value is Dictionary:
            return false
        var bundle: Dictionary = bundle_value
        var lineage_value = bundle.get("lineage", bundle.get("lineage_record"))
        if not lineage_value is Dictionary:
            return false
        if int(item.get("hereditary_individual_seed", -1)) != int(bundle.get("individual_seed", -2)):
            return false
        if String(item.get("lineage_id", "")) != String(Dictionary(lineage_value).get("lineage_id", "")):
            return false
    return true

func _elapsed_ms(start_usec: int) -> float:
    return float(Time.get_ticks_usec() - start_usec) / 1000.0

func get_snapshot() -> Dictionary:
    if not initialized:
        return {}
    var base: Dictionary = core.get_snapshot()
    var snapshot := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "mode": MODE,
        "shadow_only": true,
        "generation": int(base.get("generation", 0)),
        "evolution_enabled": bool(base.get("evolution_enabled", true)),
        "competition_enabled": competition_enabled,
        "record_count": int(base.get("record_count", 0)),
        "source_patch_hash": String(base.get("source_patch_hash", "")),
        "environment_field_hash": String(base.get("environment_field_hash", "")),
        "environment_recipe_id": String(base.get("environment_recipe_id", "")),
        "candidate_pool_hash": String(base.get("candidate_pool_hash", "")),
        "dispersal_pool_hash": String(base.get("dispersal_pool_hash", "")),
        "recruitment_hash": String(base.get("recruitment_hash", "")),
        "precompetition_population_hash": last_precompetition_population_hash,
        "competition_hash": last_competition_hash,
        "postcompetition_population_hash": last_postcompetition_population_hash,
        "occupied_map_hash": String(base.get("occupied_map_hash", "")),
        "hereditary_pool_hash": String(base.get("hereditary_pool_hash", "")),
        "survivor_count": last_survivor_count,
        "culled_count": last_culled_count,
        "records": Array(base.get("records", [])).duplicate(true),
        "competition_field": last_competition_field.duplicate(true),
        "authorities": AUTHORITY.duplicate(true),
    }
    snapshot["state_hash"] = _state_hash(snapshot)
    return snapshot

func _competition_pass(source_records: Array, generation_value: int) -> Dictionary:
    if source_records.is_empty() or generation_value < 1:
        return {}
    var profile_total_started := Time.get_ticks_usec()
    var profile_phase_started := Time.get_ticks_usec()
    var ordered: Array[Dictionary] = []
    for value in source_records:
        if not value is Dictionary:
            return {}
        ordered.append(Dictionary(value).duplicate(true))
    ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )

    var provisional: Array[Dictionary] = []
    var light_records: Array = []
    var water_records_by_cell := {}
    for record in ordered:
        var cell_index := int(record["cell_index"])
        if cell_index < 0 or cell_index >= environment_cells.size():
            return {}
        var env_cell: Dictionary = environment_cells[cell_index]
        var env := _environment_sample(env_cell, generation_value, String(record["record_id"]))
        if env.is_empty():
            return {}
        var phenotype_package := _phenotype_package(record["hereditary_bundle"], env)
        if phenotype_package.is_empty():
            return {}
        var fp: Dictionary = phenotype_package["functional_phenotype"]
        # VIS4.1 evidence is strictly non-causal. Packaging failure must never
        # abort the accepted ecology generation; it only makes the derived
        # presentation sidecar unavailable/fail-closed for this generation.
        var ph2: Dictionary = phenotype_package["ph2"]
        var morphology_evidence := MorphologyEvidence.build_record(
            record,
            ph2,
            fp
        )
        var graph_reconstruction_evidence := GraphReconstructionEvidence.build_record(
            record,
            ph2
        )
        var position := _record_position(record)
        var identity := String(record["record_id"])
        provisional.append({
            "record": record,
            "identity": identity,
            "env_cell": env_cell,
            "environment": env,
            "fp": fp,
            "morphology_evidence": morphology_evidence,
            "graph_reconstruction_evidence": graph_reconstruction_evidence,
            "position": position,
        })
        light_records.append(_light_record(identity, position, fp, float(env_cell["incident_light"])))
        if not water_records_by_cell.has(cell_index):
            water_records_by_cell[cell_index] = []
        water_records_by_cell[cell_index].append(_water_record(identity, cell_index, fp))

    var prepare_ms := _elapsed_ms(profile_phase_started)
    profile_phase_started = Time.get_ticks_usec()
    var light_field := LightField.compute(light_records)
    if light_field.is_empty():
        return {}
    var light_field_ms := _elapsed_ms(profile_phase_started)
    profile_phase_started = Time.get_ticks_usec()
    var water_fields := {}
    var water_cells: Array[Dictionary] = []
    var cell_ids: Array = water_records_by_cell.keys()
    cell_ids.sort()
    for cell_value in cell_ids:
        var cell_index := int(cell_value)
        var env_cell: Dictionary = environment_cells[cell_index]
        var texture := _texture(env_cell)
        var base_ppm := clampi(int(round(float(env_cell["soil_moisture"]) * 1000000.0)), 0, 1000000)
        var wf := WaterField.compute(base_ppm, texture, float(env_cell["incident_light"]), water_records_by_cell[cell_index], generation_value)
        if wf.is_empty():
            return {}
        water_fields[cell_index] = wf
        water_cells.append({
            "cell_index": cell_index,
            "available_before_ppm": int(wf["available_before_ppm"]),
            "water_for_plants_ppm": maxi(int(wf["available_before_ppm"]) - int(wf["evaporation_loss_ppm"]), 0),
            "total_uptake_ppm": int(wf["total_uptake_ppm"]),
            "water_after_ppm": int(wf["water_after_ppm"]),
            "field_hash": String(wf["field_hash"]),
        })

    var water_fields_ms := _elapsed_ms(profile_phase_started)
    profile_phase_started = Time.get_ticks_usec()
    var geometry := _geometry_pressures(provisional)
    if geometry.is_empty():
        return {}
    var geometry_ms := _elapsed_ms(profile_phase_started)
    profile_phase_started = Time.get_ticks_usec()
    var evaluations: Array[Dictionary] = []
    var survivors: Array[Dictionary] = []
    var morphology_records: Array[Dictionary] = []
    var graph_reconstruction_records: Array[Dictionary] = []
    for item in provisional:
        var record: Dictionary = item["record"]
        var identity := String(item["identity"])
        var env_cell: Dictionary = item["env_cell"]
        var fp: Dictionary = item["fp"]
        var cell_index := int(record["cell_index"])
        var light_item: Dictionary = light_field["plant_light"][identity]
        var water_item: Dictionary = Dictionary(water_fields[cell_index]["plant_water"])[identity]
        var pressure: Dictionary = geometry[identity]
        var base_light := maxf(float(env_cell["incident_light"]), 0.000001)
        var effective_light := clampf(float(light_item["understory_light"]), 0.0, 1.0)
        var light_fraction := clampf(effective_light / base_light, 0.0, 1.0)
        var water_satisfaction := clampf(float(water_item["water_satisfaction"]), 0.0, 1.0)
        var space_factor := clampf(1.0 / (1.0 + 0.55 * float(pressure["crown_overlap_sum"]) + 0.45 * float(pressure["root_overlap_sum"])), 0.10, 1.0)
        var root_maintenance := _root_maintenance_cost(fp)
        var competed_env := _competition_environment(item["environment"], effective_light, float(water_item["effective_soil_moisture"]), identity, generation_value)
        if competed_env.is_empty():
            return {}
        var resource := ResourceModel.evaluate(competed_env, Dictionary(record["hereditary_bundle"])["genome"])
        if resource.is_empty():
            return {}
        var realized_gain := float(fp["photosynthetic_gain_proxy"]) * light_fraction * (0.20 + 0.80 * water_satisfaction) * space_factor
        var maintenance := float(fp["maintenance_cost_proxy"])
        var root_construction := float(resource["root_cost"])
        var structural_cost := float(resource["structural_cost"])
        var space_cost := (1.0 - space_factor) * (0.10 + 0.06 * float(fp["structural_investment"]))
        var realized_balance := realized_gain - maintenance - root_construction - structural_cost - space_cost
        var survives := water_satisfaction > 0.01 and effective_light > 0.01 and realized_balance >= SURVIVAL_BALANCE_FLOOR
        var evaluation := {
            "record_id": identity,
            "cell_index": cell_index,
            "bundle_checksum": String(record["bundle_checksum"]),
            "phenotype_hash": String(fp["phenotype_hash"]),
            "base_light": snappedf(base_light, 1e-9),
            "effective_light": snappedf(effective_light, 1e-9),
            "light_fraction": snappedf(light_fraction, 1e-9),
            "overlap_lai": snappedf(float(light_item["overlap_lai"]), 1e-9),
            "water_uptake_ppm": int(water_item["water_uptake_ppm"]),
            "water_satisfaction": snappedf(water_satisfaction, 1e-9),
            "effective_soil_moisture": snappedf(float(water_item["effective_soil_moisture"]), 1e-9),
            "crown_overlap_sum": snappedf(float(pressure["crown_overlap_sum"]), 1e-9),
            "root_overlap_sum": snappedf(float(pressure["root_overlap_sum"]), 1e-9),
            "space_factor": snappedf(space_factor, 1e-9),
            "realized_height_m": float(fp["realized_height_m"]),
            "leaf_area_index_proxy": float(fp["leaf_area_index_proxy"]),
            "realized_root_depth_m": float(fp["realized_root_depth_m"]),
            "realized_root_spread_m": float(fp["realized_root_spread_m"]),
            "root_shoot_ratio": float(fp["root_shoot_ratio"]),
            "root_maintenance_cost": snappedf(root_maintenance, 1e-9),
            "root_construction_cost": snappedf(root_construction, 1e-9),
            "structural_cost": snappedf(structural_cost, 1e-9),
            "space_cost": snappedf(space_cost, 1e-9),
            "realized_gain": snappedf(realized_gain, 1e-9),
            "realized_resource_balance": snappedf(realized_balance, 1e-9),
            "survives": survives,
        }
        evaluation["evaluation_hash"] = _evaluation_hash(evaluation)
        evaluations.append(evaluation)
        if survives:
            survivors.append(record.duplicate(true))
            var morphology_value = item.get("morphology_evidence")
            if morphology_value is Dictionary and not Dictionary(morphology_value).is_empty():
                morphology_records.append(Dictionary(morphology_value).duplicate(true))
            var reconstruction_value = item.get("graph_reconstruction_evidence")
            if reconstruction_value is Dictionary and not Dictionary(reconstruction_value).is_empty():
                graph_reconstruction_records.append(Dictionary(reconstruction_value).duplicate(true))

    var evaluation_ms := _elapsed_ms(profile_phase_started)
    profile_phase_started = Time.get_ticks_usec()
    evaluations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    survivors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["record_id"]) < String(b["record_id"])
    )
    water_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a["cell_index"]) < int(b["cell_index"])
    )
    var field := {
        "schema": SCHEMA + ".field",
        "version": VERSION,
        "revision": REVISION,
        "generation": generation_value,
        "neighborhood_policy": "SAME_CELL_WATER+MOORE_GEOMETRY+TRAIT_RADIUS",
        "moore_radius_cells": MOORE_RADIUS_CELLS,
        "max_trait_radius_cells": MAX_TRAIT_RADIUS_CELLS,
        "record_count_before": ordered.size(),
        "record_count_after": survivors.size(),
        "light_field_hash": String(light_field["plant_light_hash"]),
        "water_cells": water_cells,
        "evaluations": evaluations,
    }
    field["water_field_hash"] = _water_cells_hash(water_cells)
    field["field_hash"] = _competition_field_hash(field)
    if not validate_competition_field(field):
        return {}
    var finalize_validate_ms := _elapsed_ms(profile_phase_started)
    last_competition_profile = {
        "record_count": ordered.size(),
        "occupied_water_cells": water_cells.size(),
        "prepare_ms": prepare_ms,
        "light_field_ms": light_field_ms,
        "water_fields_ms": water_fields_ms,
        "geometry_ms": geometry_ms,
        "evaluation_ms": evaluation_ms,
        "finalize_validate_ms": finalize_validate_ms,
        "total_ms": _elapsed_ms(profile_total_started),
    }
    return {"survivors": survivors, "field": field, "morphology_records": morphology_records, "graph_reconstruction_records": graph_reconstruction_records}

func _empty_competition_field(generation_value: int) -> Dictionary:
    if generation_value < 1:
        return {}
    var empty_water_cells: Array[Dictionary] = []
    var empty_evaluations: Array[Dictionary] = []
    var field := {
        "schema": SCHEMA + ".field",
        "version": VERSION,
        "revision": REVISION,
        "generation": generation_value,
        "neighborhood_policy": "SAME_CELL_WATER+MOORE_GEOMETRY+TRAIT_RADIUS",
        "moore_radius_cells": MOORE_RADIUS_CELLS,
        "max_trait_radius_cells": MAX_TRAIT_RADIUS_CELLS,
        "record_count_before": 0,
        "record_count_after": 0,
        "light_field_hash": _empty_light_field_hash(generation_value),
        "water_cells": empty_water_cells,
        "evaluations": empty_evaluations,
    }
    field["water_field_hash"] = _water_cells_hash(empty_water_cells)
    field["field_hash"] = _competition_field_hash(field)
    return field if validate_competition_field(field) else {}

func _empty_light_field_hash(generation_value: int) -> String:
    return ("%s|%s|%s|empty-light|%d" % [SCHEMA, VERSION, REVISION, generation_value]).sha256_text()

func validate_competition_field(field: Dictionary) -> bool:
    if field.is_empty():
        return false
    if String(field.get("schema", "")) != SCHEMA + ".field" or String(field.get("version", "")) != VERSION or String(field.get("revision", "")) != REVISION:
        return false
    if int(field.get("generation", -1)) < 1 or String(field.get("neighborhood_policy", "")) != "SAME_CELL_WATER+MOORE_GEOMETRY+TRAIT_RADIUS":
        return false
    if int(field.get("moore_radius_cells", -1)) != MOORE_RADIUS_CELLS or int(field.get("max_trait_radius_cells", -1)) != MAX_TRAIT_RADIUS_CELLS:
        return false
    var before := int(field.get("record_count_before", -1)); var after := int(field.get("record_count_after", -1))
    if before < 0 or after < 0 or after > before:
        return false
    if String(field.get("light_field_hash", "")).length() != 64 or String(field.get("water_field_hash", "")).length() != 64:
        return false
    var water_value = field.get("water_cells")
    var eval_value = field.get("evaluations")
    if not water_value is Array or not eval_value is Array or Array(eval_value).size() != before:
        return false
    if before == 0:
        if after != 0 or not Array(water_value).is_empty() or not Array(eval_value).is_empty():
            return false
        if String(field.get("light_field_hash", "")) != _empty_light_field_hash(int(field["generation"])):
            return false
    var water_cells: Array = water_value
    var seen_cells := {}
    var previous_cell := -1
    for value in water_cells:
        if not value is Dictionary:
            return false
        var cell: Dictionary = value
        var cell_index := int(cell.get("cell_index", -1))
        if cell_index < 0 or cell_index >= GRID_SIZE * GRID_SIZE or seen_cells.has(cell_index) or cell_index <= previous_cell:
            return false
        seen_cells[cell_index] = true; previous_cell = cell_index
        var available := int(cell.get("available_before_ppm", -1))
        var plant_water := int(cell.get("water_for_plants_ppm", -1))
        var uptake := int(cell.get("total_uptake_ppm", -1))
        var remaining := int(cell.get("water_after_ppm", -1))
        if available < 0 or plant_water < 0 or uptake < 0 or remaining < 0 or uptake > plant_water or remaining != plant_water - uptake:
            return false
        if String(cell.get("field_hash", "")).length() != 64:
            return false
    if String(field.get("water_field_hash", "")) != _water_cells_hash(water_cells):
        return false
    var seen_records := {}
    var survivor_count := 0
    for value in Array(eval_value):
        if not value is Dictionary:
            return false
        var e: Dictionary = value
        var record_id := String(e.get("record_id", ""))
        if record_id.is_empty() or seen_records.has(record_id) or int(e.get("cell_index", -1)) < 0:
            return false
        seen_records[record_id] = true
        for name in ["base_light", "effective_light", "water_satisfaction", "effective_soil_moisture", "space_factor", "root_maintenance_cost", "root_construction_cost", "structural_cost", "space_cost", "realized_gain"]:
            if not is_finite(float(e.get(name, NAN))) or float(e.get(name, -1.0)) < 0.0:
                return false
        if float(e["effective_light"]) > float(e["base_light"]) + 1e-9 or float(e["water_satisfaction"]) > 1.0 + 1e-9 or float(e["effective_soil_moisture"]) > 1.0 + 1e-9 or float(e["space_factor"]) > 1.0 + 1e-9:
            return false
        if not is_finite(float(e.get("realized_resource_balance", NAN))):
            return false
        if String(e.get("evaluation_hash", "")) != _evaluation_hash(e):
            return false
        if bool(e.get("survives", false)):
            survivor_count += 1
    if survivor_count != after:
        return false
    return String(field.get("field_hash", "")) == _competition_field_hash(field)

func validate_snapshot(snapshot: Dictionary) -> bool:
    if snapshot.is_empty() or String(snapshot.get("schema", "")) != SCHEMA or String(snapshot.get("version", "")) != VERSION or String(snapshot.get("revision", "")) != REVISION or String(snapshot.get("mode", "")) != MODE:
        return false
    if not bool(snapshot.get("shadow_only", false)):
        return false
    var authorities_value = snapshot.get("authorities")
    if not authorities_value is Dictionary:
        return false
    var authorities: Dictionary = authorities_value
    if authorities.keys().size() != AUTHORITY.keys().size():
        return false
    for key in AUTHORITY.keys():
        if not authorities.has(key) or typeof(authorities[key]) != TYPE_BOOL or bool(authorities[key]) != bool(AUTHORITY[key]):
            return false
    var records_value = snapshot.get("records")
    if not records_value is Array:
        return false
    var snapshot_records: Array = records_value
    if int(snapshot.get("record_count", -1)) != snapshot_records.size():
        return false
    if not snapshot_records.is_empty() and not bool(core.call("_validate_current_records", snapshot_records)):
        return false
    if String(snapshot.get("postcompetition_population_hash", "")) != String(core.call("_population_hash", snapshot_records)):
        return false
    if String(snapshot.get("occupied_map_hash", "")) != String(core.call("_occupied_map_hash", snapshot_records)):
        return false
    if String(snapshot.get("hereditary_pool_hash", "")) != String(core.call("_hereditary_pool_hash", snapshot_records)):
        return false
    if bool(snapshot.get("competition_enabled", false)) and int(snapshot.get("generation", 0)) > 0:
        var field_value = snapshot.get("competition_field")
        if not field_value is Dictionary or not validate_competition_field(field_value):
            return false
        if String(snapshot.get("competition_hash", "")) != String(Dictionary(field_value).get("field_hash", "")):
            return false
    if String(snapshot.get("state_hash", "")) != _state_hash(snapshot):
        return false
    return true

func _phenotype_package(bundle: Dictionary, env: Dictionary) -> Dictionary:
    var seed_tag := "ls34-phenotype|%d|%s" % [int(bundle["individual_seed"]), String(bundle["bundle_checksum"]).substr(0, 16)]
    var envelope := Contract.create_seed_envelope(
        bundle["genome"], bundle["dev_traits"], String(bundle["lineage"]["lineage_id"]), seed_tag, 0, 1.25)
    var ph2 := CoupledDevelopment.realize(envelope, bundle["dev_traits"], env)
    if ph2.is_empty():
        return {}
    var fp := FunctionalPhenotype.compile({
        "genome": bundle["genome"],
        "ph2_realized": ph2,
        "traits_extension": bundle["ext_traits"],
        "environment_sample": env,
        "age_fraction": 1.0,
    })
    if fp.is_empty():
        return {}
    return {
        "ph2": ph2,
        "functional_phenotype": fp,
    }

func _functional_phenotype(bundle: Dictionary, env: Dictionary) -> Dictionary:
    ## Compatibility helper for focused tests/debug callers. The competition path
    ## uses _phenotype_package() once so morphology evidence never recomputes biology.
    var package := _phenotype_package(bundle, env)
    return {} if package.is_empty() else Dictionary(package["functional_phenotype"]).duplicate(true)

func _environment_sample(env_cell: Dictionary, generation_value: int, identity: String) -> Dictionary:
    return EnvironmentSample.create(
        float(env_cell["east_m"]), float(env_cell["north_m"]),
        float(env_cell["temperature_c"]), float(env_cell["soil_moisture"]),
        float(env_cell["incident_light"]), 0.50,
        clampf(float(env_cell["surface_water_fraction"]), 0.0, 1.0),
        int(core.environment_seed),
        "%s|base|g%d|cell=%s|id=%s" % [REVISION, generation_value, String(env_cell["cell_hash"]), identity]
    )

func _competition_environment(base_env: Dictionary, light: float, moisture: float, identity: String, generation_value: int) -> Dictionary:
    return EnvironmentSample.create(
        float(base_env["world_x_m"]), float(base_env["world_z_m"]), float(base_env["temperature_c"]),
        clampf(moisture, 0.0, 1.0), clampf(light, 0.0, 1.0), float(base_env["nutrients"]),
        float(base_env["flood_frequency"]), int(base_env["seed"]),
        "%s|competed|g%d|%s" % [REVISION, generation_value, identity]
    )

func _light_record(identity: String, position: Vector2, fp: Dictionary, base_sunlight: float) -> Dictionary:
    return {
        "identity": identity,
        "world_x_m": position.x, "world_z_m": position.y,
        "realized_height_m": float(fp["realized_height_m"]),
        "realized_crown_radius_m": float(fp["realized_crown_radius_m"]),
        "realized_crown_density": float(fp["realized_crown_density"]),
        "leaf_area_index_proxy": float(fp["leaf_area_index_proxy"]),
        "base_sunlight": clampf(base_sunlight, 0.0, 1.0),
        "shade_output_ppm": int(fp["shade_output_ppm"]),
        "source_phenotype_hash": String(fp["phenotype_hash"]),
    }

func _water_record(identity: String, cell_index: int, fp: Dictionary) -> Dictionary:
    return {
        "identity": identity,
        "cell_identity": "ls34-cell-%04d" % cell_index,
        "realized_root_depth_m": float(fp["realized_root_depth_m"]),
        "realized_root_spread_m": float(fp["realized_root_spread_m"]),
        "root_shoot_ratio": float(fp["root_shoot_ratio"]),
        "leaf_area_index_proxy": float(fp["leaf_area_index_proxy"]),
        "transpiration_demand_ppm": int(fp["transpiration_demand_ppm"]),
        "shade_output_ppm": int(fp["shade_output_ppm"]),
        "source_phenotype_hash": String(fp["phenotype_hash"]),
    }

func _record_position(record: Dictionary) -> Vector2:
    var cell_index := int(record["cell_index"])
    var x := cell_index % GRID_SIZE
    var y := cell_index / GRID_SIZE
    var offsets := [Vector2(-3.0, -3.0), Vector2(3.0, -3.0), Vector2(-3.0, 3.0), Vector2(3.0, 3.0)]
    var offset: Vector2 = offsets[int(record["slot_index"])]
    return Vector2(float(x) * CELL_SIZE_M + CELL_SIZE_M * 0.5, float(y) * CELL_SIZE_M + CELL_SIZE_M * 0.5) + offset

func _geometry_pressures(provisional: Array[Dictionary]) -> Dictionary:
    var by_id := {}
    for item in provisional:
        by_id[String(item["identity"])] = {"crown_overlap_sum": 0.0, "root_overlap_sum": 0.0}
    var ordered := provisional.duplicate(true)
    ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return String(a["identity"]) < String(b["identity"])
    )
    for i in ordered.size():
        var a: Dictionary = ordered[i]
        var fp_a: Dictionary = a["fp"]
        var cell_a := int(Dictionary(a["record"])["cell_index"])
        var ax := cell_a % GRID_SIZE; var ay := cell_a / GRID_SIZE
        for j in range(i + 1, ordered.size()):
            var b: Dictionary = ordered[j]
            var fp_b: Dictionary = b["fp"]
            var cell_b := int(Dictionary(b["record"])["cell_index"])
            var bx := cell_b % GRID_SIZE; var by := cell_b / GRID_SIZE
            var max_radius_m := maxf(maxf(float(fp_a["realized_crown_radius_m"]), float(fp_a["realized_root_spread_m"])), maxf(float(fp_b["realized_crown_radius_m"]), float(fp_b["realized_root_spread_m"])))
            var radius_cells := clampi(maxi(MOORE_RADIUS_CELLS, int(ceil(max_radius_m / CELL_SIZE_M))), MOORE_RADIUS_CELLS, MAX_TRAIT_RADIUS_CELLS)
            if absi(ax - bx) > radius_cells or absi(ay - by) > radius_cells:
                continue
            var distance := Vector2(a["position"]).distance_to(Vector2(b["position"]))
            var crown_a := maxf(float(fp_a["realized_crown_radius_m"]), 0.0)
            var crown_b := maxf(float(fp_b["realized_crown_radius_m"]), 0.0)
            var root_a := maxf(float(fp_a["realized_root_spread_m"]), 0.0)
            var root_b := maxf(float(fp_b["realized_root_spread_m"]), 0.0)
            var crown_pair := _overlap_fractions(crown_a, crown_b, distance)
            var root_pair := _overlap_fractions(root_a, root_b, distance)
            by_id[String(a["identity"])]["crown_overlap_sum"] = snappedf(float(by_id[String(a["identity"])]["crown_overlap_sum"]) + float(crown_pair.x), 1e-9)
            by_id[String(b["identity"])]["crown_overlap_sum"] = snappedf(float(by_id[String(b["identity"])]["crown_overlap_sum"]) + float(crown_pair.y), 1e-9)
            by_id[String(a["identity"])]["root_overlap_sum"] = snappedf(float(by_id[String(a["identity"])]["root_overlap_sum"]) + float(root_pair.x), 1e-9)
            by_id[String(b["identity"])]["root_overlap_sum"] = snappedf(float(by_id[String(b["identity"])]["root_overlap_sum"]) + float(root_pair.y), 1e-9)
    return by_id

func _overlap_fractions(radius_a: float, radius_b: float, distance: float) -> Vector2:
    if radius_a <= 0.0 or radius_b <= 0.0 or distance >= radius_a + radius_b:
        return Vector2.ZERO
    var area := _circle_overlap_area(radius_a, radius_b, distance)
    return Vector2(clampf(area / maxf(PI * radius_a * radius_a, 1e-12), 0.0, 1.0), clampf(area / maxf(PI * radius_b * radius_b, 1e-12), 0.0, 1.0))

func _circle_overlap_area(radius_a: float, radius_b: float, distance: float) -> float:
    if distance <= absf(radius_a - radius_b):
        var inner := minf(radius_a, radius_b)
        return PI * inner * inner
    if distance <= 0.0:
        return 0.0
    var a2 := radius_a * radius_a; var b2 := radius_b * radius_b; var d2 := distance * distance
    var alpha := acos(clampf((d2 + a2 - b2) / (2.0 * distance * radius_a), -1.0, 1.0))
    var beta := acos(clampf((d2 + b2 - a2) / (2.0 * distance * radius_b), -1.0, 1.0))
    var radicand := maxf(0.0, (-distance + radius_a + radius_b) * (distance + radius_a - radius_b) * (distance - radius_a + radius_b) * (distance + radius_a + radius_b))
    return a2 * alpha + b2 * beta - 0.5 * sqrt(radicand)

func _root_maintenance_cost(fp: Dictionary) -> float:
    var root_alloc := 2.0 * clampf(float(fp["root_shoot_ratio"]), 0.0, 1.0)
    return snappedf(FunctionalPhenotype.ROOT_MAINTENANCE_PER_METER * (float(fp["realized_root_depth_m"]) / 5.0 + float(fp["realized_root_spread_m"]) / 6.0) * root_alloc, 1e-9)

func _texture(env_cell: Dictionary) -> String:
    var sand := float(env_cell["soil_texture_sand"]); var clay := float(env_cell["soil_texture_clay"])
    return "sand" if sand >= 0.55 and sand >= clay else ("clay" if clay >= 0.38 else "loam")

func _evaluation_hash(e: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, "evaluation", String(e["record_id"]), str(int(e["cell_index"])), String(e["bundle_checksum"]), String(e["phenotype_hash"]),
        "%.9f" % float(e["base_light"]), "%.9f" % float(e["effective_light"]), "%.9f" % float(e["water_satisfaction"]),
        str(int(e["water_uptake_ppm"])), "%.9f" % float(e["space_factor"]), "%.9f" % float(e["root_maintenance_cost"]),
        "%.9f" % float(e["root_construction_cost"]), "%.9f" % float(e["structural_cost"]), "%.9f" % float(e["realized_resource_balance"]),
        "1" if bool(e["survives"]) else "0",
    ])).sha256_text()

func _water_cells_hash(cells: Array[Dictionary]) -> String:
    var tokens := PackedStringArray([SCHEMA, VERSION, "water-cells"])
    for c in cells:
        tokens.append("%d:%d:%d:%d:%s" % [int(c["cell_index"]), int(c["available_before_ppm"]), int(c["total_uptake_ppm"]), int(c["water_after_ppm"]), String(c["field_hash"])])
    return "|".join(tokens).sha256_text()

func _competition_field_hash(field: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION, REVISION, "field", str(int(field["generation"])), String(field["neighborhood_policy"]),
        str(int(field["record_count_before"])), str(int(field["record_count_after"])), String(field["light_field_hash"]), String(field["water_field_hash"]),
    ])
    for e in field["evaluations"]:
        tokens.append(String(Dictionary(e)["evaluation_hash"]))
    return "|".join(tokens).sha256_text()

func _state_hash(snapshot: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, REVISION, MODE, str(int(snapshot["generation"])),
        "1" if bool(snapshot["evolution_enabled"]) else "0", "1" if bool(snapshot["competition_enabled"]) else "0",
        String(snapshot["source_patch_hash"]), String(snapshot["environment_field_hash"]), String(snapshot["candidate_pool_hash"]), String(snapshot["dispersal_pool_hash"]),
        String(snapshot["recruitment_hash"]), String(snapshot["precompetition_population_hash"]), String(snapshot["competition_hash"]), String(snapshot["postcompetition_population_hash"]),
        String(snapshot["occupied_map_hash"]), String(snapshot["hereditary_pool_hash"]), str(int(snapshot["survivor_count"])), str(int(snapshot["culled_count"])),
        _authority_hash(),
    ])).sha256_text()

func _authority_hash() -> String:
    var tokens := PackedStringArray([SCHEMA, VERSION, "authority"])
    var keys: Array = AUTHORITY.keys(); keys.sort()
    for key in keys:
        tokens.append("%s=%s" % [String(key), "1" if bool(AUTHORITY[key]) else "0"])
    return "|".join(tokens).sha256_text()

func _reset() -> void:
    initialized = false
    competition_enabled = true
    core = null
    environment_cells.clear()
    last_competition_field.clear()
    last_competition_hash = ""
    last_precompetition_population_hash = ""
    last_postcompetition_population_hash = ""
    last_survivor_count = 0
    last_culled_count = 0
    last_profile.clear()
    last_competition_profile.clear()
    last_morphology_records.clear()
    last_morphology_evidence.clear()
