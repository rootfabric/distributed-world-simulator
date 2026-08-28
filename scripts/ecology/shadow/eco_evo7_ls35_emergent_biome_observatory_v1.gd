extends RefCounted

const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LS34 = preload("res://scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")

## ECO.EVO7 LS3.5 — read-only emergent biome observatory.
##
## ONE-WAY ONLY:
##   physical EnvironmentField + accepted LS3.4 community snapshot
##     -> measured cell/community/spatial observables
##     -> post-hoc "*-like" research labels / ecotones
##
## This module never advances ecology and never writes back into fitness,
## reproduction, mutation, dispersal, recruitment, competition, persistence,
## networking, production world state, or renderer state.

const ENV_SCHEMA := "distributed_world_simulator.ecology.evo7_environment_field.v1"
const ENV_VERSION := "1.0.0"
const ECOLOGY_SCHEMA := "distributed_world_simulator.ecology.evo7_local_competition.v1"
const ECOLOGY_VERSION := "1.0.0"
const SCHEMA := "distributed_world_simulator.ecology.evo7_emergent_biome_observatory.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.5.2"
const GRID_SIZE := 32
const SLOTS_PER_CELL := 4
const LABELS: Array[String] = [
    "desert-like", "wetland-like", "forest-like", "grass/shrub-like", "alpine-like", "ecotone",
]
const BASE_LABELS: Array[String] = [
    "desert-like", "wetland-like", "forest-like", "grass/shrub-like", "alpine-like",
]
const AUTHORITY := {
    "ecology_write": false,
    "classifier_to_ecology_edge": false,
    "production_biome_truth": false,
    "persistence_write": false,
    "network_replication_write": false,
    "renderer_write": false,
}

const ENVIRONMENT_FIELDS: Array[String] = [
    "schema", "version", "revision", "source_patch_hash", "grid_size", "cell_size_m",
    "recipe_id", "environment_seed", "cells", "field_hash",
]
const ECOLOGY_FIELDS: Array[String] = [
    "schema", "version", "revision", "mode", "shadow_only", "generation", "evolution_enabled",
    "competition_enabled", "record_count", "source_patch_hash", "environment_field_hash",
    "environment_recipe_id", "candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
    "precompetition_population_hash", "competition_hash", "postcompetition_population_hash",
    "occupied_map_hash", "hereditary_pool_hash", "survivor_count", "culled_count", "records",
    "competition_field", "authorities", "state_hash",
]

func classify(environment_field: Dictionary, ecology_snapshot: Dictionary, enabled: bool = true) -> Dictionary:
    if not enabled:
        return {}
    var result := _classify_unchecked(environment_field, ecology_snapshot)
    if result.is_empty() or not validate_classification(result, environment_field, ecology_snapshot):
        return {}
    return result

func validate_classification(classification: Dictionary, environment_field: Dictionary, ecology_snapshot: Dictionary) -> bool:
    if classification.is_empty():
        return false
    if String(classification.get("schema", "")) != SCHEMA or String(classification.get("version", "")) != VERSION or String(classification.get("revision", "")) != REVISION:
        return false
    if not bool(classification.get("research_labels_only", false)) or int(classification.get("grid_size", 0)) != GRID_SIZE:
        return false
    if String(classification.get("source_environment_field_hash", "")) != String(environment_field.get("field_hash", "")):
        return false
    if String(classification.get("source_ecology_state_hash", "")) != String(ecology_snapshot.get("state_hash", "")):
        return false
    if String(classification.get("source_population_hash", "")) != String(ecology_snapshot.get("postcompetition_population_hash", "")):
        return false
    if int(classification.get("generation", -1)) != int(ecology_snapshot.get("generation", -2)):
        return false
    var authorities_value = classification.get("authorities")
    if not authorities_value is Dictionary:
        return false
    var authorities: Dictionary = authorities_value
    if authorities.keys().size() != AUTHORITY.keys().size():
        return false
    for key in AUTHORITY.keys():
        if not authorities.has(key) or typeof(authorities[key]) != TYPE_BOOL or bool(authorities[key]) != bool(AUTHORITY[key]):
            return false
    var cells_value = classification.get("cells")
    if not cells_value is Array or Array(cells_value).size() != GRID_SIZE * GRID_SIZE:
        return false
    var counted := {}
    for label in LABELS:
        counted[label] = 0
    for index in GRID_SIZE * GRID_SIZE:
        var value = Array(cells_value)[index]
        if not value is Dictionary:
            return false
        var cell: Dictionary = value
        if int(cell.get("index", -1)) != index or int(cell.get("x", -1)) != index % GRID_SIZE or int(cell.get("y", -1)) != index / GRID_SIZE:
            return false
        var label := String(cell.get("label", "")); var base_label := String(cell.get("base_label", ""))
        if not label in LABELS or not base_label in BASE_LABELS:
            return false
        if String(cell.get("cell_hash", "")) != _cell_hash(cell):
            return false
        counted[label] = int(counted[label]) + 1
    var summary_value = classification.get("summary")
    if not summary_value is Dictionary:
        return false
    var summary: Dictionary = summary_value
    var class_counts_value = summary.get("class_counts")
    if not class_counts_value is Dictionary:
        return false
    var class_counts: Dictionary = class_counts_value
    var class_fractions_value = summary.get("class_fractions")
    if not class_fractions_value is Dictionary:
        return false
    var class_fractions: Dictionary = class_fractions_value
    for label in LABELS:
        if int(class_counts.get(label, -1)) != int(counted[label]):
            return false
        var expected_fraction := snappedf(float(int(counted[label])) / float(GRID_SIZE * GRID_SIZE), 1e-9)
        if absf(float(class_fractions.get(label, -1.0)) - expected_fraction) > 1e-9:
            return false
    var distinct_base := {}
    var occupied_cells := 0; var ecotone_cells := 0
    for value in Array(cells_value):
        var cell: Dictionary = value
        distinct_base[String(cell["base_label"])] = true
        if int(cell["occupancy_count"]) > 0:
            occupied_cells += 1
        if String(cell["label"]) == "ecotone":
            ecotone_cells += 1
    if int(summary.get("distinct_base_classes", -1)) != distinct_base.size() or int(summary.get("occupied_cells", -1)) != occupied_cells or int(summary.get("ecotone_cells", -1)) != ecotone_cells:
        return false
    if absf(float(summary.get("mean_cover_proxy", -1.0)) - snappedf(_mean_metric(Array(cells_value), "cover_proxy"), 1e-9)) > 1e-9:
        return false
    if absf(float(summary.get("mean_continuity", -1.0)) - snappedf(_mean_metric(Array(cells_value), "continuity"), 1e-9)) > 1e-9:
        return false
    if absf(float(summary.get("mean_fragmentation", -1.0)) - snappedf(_mean_metric(Array(cells_value), "fragmentation"), 1e-9)) > 1e-9:
        return false
    if String(summary.get("summary_hash", "")) != _summary_hash(summary):
        return false
    if String(classification.get("classification_hash", "")) != _classification_hash(classification):
        return false
    var expected := _classify_unchecked(environment_field, ecology_snapshot)
    if expected.is_empty():
        return false
    return String(classification["classification_hash"]) == String(expected["classification_hash"])

func _classify_unchecked(environment_field: Dictionary, ecology_snapshot: Dictionary) -> Dictionary:
    if not _valid_sources(environment_field, ecology_snapshot):
        return {}
    var env_cells := _canonical_environment_cells(Array(environment_field["cells"]))
    if env_cells.size() != GRID_SIZE * GRID_SIZE:
        return {}
    var records: Array = ecology_snapshot["records"]
    var competition_field: Dictionary = ecology_snapshot["competition_field"]
    var evaluations: Array = competition_field["evaluations"]
    var water_cells: Array = competition_field["water_cells"]

    var eval_by_id := {}
    for value in evaluations:
        if not value is Dictionary:
            return {}
        var e: Dictionary = value
        var record_id := String(e.get("record_id", ""))
        if record_id.is_empty() or eval_by_id.has(record_id):
            return {}
        eval_by_id[record_id] = e

    var water_by_cell := {}
    for value in water_cells:
        if not value is Dictionary:
            return {}
        var w: Dictionary = value
        var cell_index := int(w.get("cell_index", -1))
        if cell_index < 0 or cell_index >= GRID_SIZE * GRID_SIZE or water_by_cell.has(cell_index):
            return {}
        water_by_cell[cell_index] = w

    var survivor_ids := {}
    var records_by_cell := {}
    for value in records:
        if not value is Dictionary:
            return {}
        var record: Dictionary = value
        var record_id := String(record.get("record_id", ""))
        var cell_index := int(record.get("cell_index", -1))
        if record_id.is_empty() or survivor_ids.has(record_id) or cell_index < 0 or cell_index >= GRID_SIZE * GRID_SIZE:
            return {}
        if not eval_by_id.has(record_id):
            return {}
        survivor_ids[record_id] = true
        if not records_by_cell.has(cell_index):
            records_by_cell[cell_index] = []
        records_by_cell[cell_index].append(record)

    var cells: Array[Dictionary] = []
    for index in GRID_SIZE * GRID_SIZE:
        var env: Dictionary = env_cells[index]
        var cell_records: Array = records_by_cell.get(index, [])
        var metrics := _cell_metrics(index, env, cell_records, eval_by_id, water_by_cell)
        if metrics.is_empty():
            return {}
        cells.append(metrics)

    _add_spatial_metrics(cells)
    for index in cells.size():
        var scores := _base_scores(cells[index])
        var ranked := _rank_scores(scores)
        if ranked.size() != BASE_LABELS.size():
            return {}
        cells[index]["scores"] = scores
        cells[index]["base_label"] = String(ranked[0]["label"])
        cells[index]["base_score"] = float(ranked[0]["score"])
        cells[index]["second_score"] = float(ranked[1]["score"])
        cells[index]["class_margin"] = snappedf(float(ranked[0]["score"]) - float(ranked[1]["score"]), 1e-9)

    _apply_ecotones(cells)

    var counts := {}
    for label in LABELS:
        counts[label] = 0
    var distinct_base := {}
    var ecotone_count := 0
    for cell in cells:
        var label := String(cell["label"])
        counts[label] = int(counts[label]) + 1
        distinct_base[String(cell["base_label"])] = true
        if label == "ecotone":
            ecotone_count += 1
        cell["cell_hash"] = _cell_hash(cell)

    var class_fractions := {}
    for label in LABELS:
        class_fractions[label] = snappedf(float(int(counts[label])) / float(GRID_SIZE * GRID_SIZE), 1e-9)
    var summary := {
        "class_counts": counts,
        "class_fractions": class_fractions,
        "distinct_base_classes": distinct_base.size(),
        "ecotone_cells": ecotone_count,
        "occupied_cells": _occupied_cell_count(cells),
        "mean_cover_proxy": snappedf(_mean_metric(cells, "cover_proxy"), 1e-9),
        "mean_continuity": snappedf(_mean_metric(cells, "continuity"), 1e-9),
        "mean_fragmentation": snappedf(_mean_metric(cells, "fragmentation"), 1e-9),
    }
    summary["summary_hash"] = _summary_hash(summary)
    var result := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "research_labels_only": true,
        "source_environment_field_hash": String(environment_field["field_hash"]),
        "source_ecology_state_hash": String(ecology_snapshot["state_hash"]),
        "source_population_hash": String(ecology_snapshot["postcompetition_population_hash"]),
        "generation": int(ecology_snapshot["generation"]),
        "grid_size": GRID_SIZE,
        "cells": cells,
        "summary": summary,
        "authorities": AUTHORITY.duplicate(true),
    }
    result["classification_hash"] = _classification_hash(result)
    return result

func _valid_sources(environment_field: Dictionary, ecology_snapshot: Dictionary) -> bool:
    if not _exact_keys(environment_field, ENVIRONMENT_FIELDS):
        return false
    if String(environment_field.get("schema", "")) != ENV_SCHEMA or String(environment_field.get("version", "")) != ENV_VERSION or String(environment_field.get("revision", "")) != EnvironmentField.REVISION:
        return false
    if int(environment_field.get("grid_size", 0)) != GRID_SIZE or not environment_field.get("cells") is Array or Array(environment_field["cells"]).size() != GRID_SIZE * GRID_SIZE:
        return false
    var env_validator = EnvironmentField.new()
    for value in Array(environment_field["cells"]):
        if not value is Dictionary:
            return false
        var env_cell: Dictionary = value
        if String(env_cell.get("cell_hash", "")) != String(env_validator.call("_cell_hash", env_cell)):
            return false
    if String(environment_field.get("field_hash", "")) != String(env_validator.call("_field_hash", environment_field)):
        return false

    if not _exact_keys(ecology_snapshot, ECOLOGY_FIELDS):
        return false
    if String(ecology_snapshot.get("schema", "")) != ECOLOGY_SCHEMA or String(ecology_snapshot.get("version", "")) != ECOLOGY_VERSION or String(ecology_snapshot.get("revision", "")) != LS34.REVISION or String(ecology_snapshot.get("mode", "")) != LS34.MODE:
        return false
    if not bool(ecology_snapshot.get("shadow_only", false)) or int(ecology_snapshot.get("generation", 0)) < 1 or not bool(ecology_snapshot.get("competition_enabled", false)):
        return false
    if not _valid_ecology_authorities(ecology_snapshot.get("authorities")):
        return false
    if String(ecology_snapshot.get("source_patch_hash", "")) != String(environment_field.get("source_patch_hash", "")):
        return false
    if String(ecology_snapshot.get("environment_field_hash", "")) != String(environment_field["field_hash"]):
        return false
    for hash_name in [
        "state_hash", "candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
        "precompetition_population_hash", "competition_hash", "postcompetition_population_hash",
        "occupied_map_hash", "hereditary_pool_hash",
    ]:
        if String(ecology_snapshot.get(hash_name, "")).length() != 64:
            return false
    var records_value = ecology_snapshot.get("records")
    if not records_value is Array:
        return false
    var snapshot_records: Array = records_value
    if int(ecology_snapshot.get("record_count", -1)) != snapshot_records.size() or int(ecology_snapshot.get("survivor_count", -1)) != snapshot_records.size():
        return false

    var record_validator = LS33.new()
    if not bool(record_validator.call("_validate_current_records", snapshot_records)):
        return false
    if String(ecology_snapshot.get("postcompetition_population_hash", "")) != String(record_validator.call("_population_hash", snapshot_records)):
        return false
    if String(ecology_snapshot.get("occupied_map_hash", "")) != String(record_validator.call("_occupied_map_hash", snapshot_records)):
        return false
    if String(ecology_snapshot.get("hereditary_pool_hash", "")) != String(record_validator.call("_hereditary_pool_hash", snapshot_records)):
        return false

    var field_value = ecology_snapshot.get("competition_field")
    if not field_value is Dictionary:
        return false
    var field: Dictionary = field_value
    var competition_validator = LS34.new()
    if not competition_validator.validate_competition_field(field):
        return false
    if String(ecology_snapshot.get("competition_hash", "")) != String(field.get("field_hash", "")):
        return false
    var field_before := int(field.get("record_count_before", -1)); var field_after := int(field.get("record_count_after", -1))
    if field_after != snapshot_records.size() or field_before < field_after or int(ecology_snapshot.get("culled_count", -1)) != field_before - field_after:
        return false

    var surviving_evaluations := {}
    for value in Array(field.get("evaluations", [])):
        if not value is Dictionary:
            return false
        var evaluation: Dictionary = value
        if bool(evaluation.get("survives", false)):
            var evaluation_id := String(evaluation.get("record_id", ""))
            if evaluation_id.is_empty() or surviving_evaluations.has(evaluation_id):
                return false
            surviving_evaluations[evaluation_id] = evaluation
    if surviving_evaluations.size() != snapshot_records.size():
        return false
    for record_value in snapshot_records:
        var record: Dictionary = record_value
        var record_id := String(record.get("record_id", ""))
        if not surviving_evaluations.has(record_id):
            return false
        var evaluation: Dictionary = surviving_evaluations[record_id]
        if int(evaluation.get("cell_index", -1)) != int(record.get("cell_index", -2)) or String(evaluation.get("bundle_checksum", "")) != String(record.get("bundle_checksum", "")):
            return false

    if String(ecology_snapshot.get("state_hash", "")) != String(competition_validator.call("_state_hash", ecology_snapshot)):
        return false
    return true

func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
    if value.keys().size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true

func _valid_ecology_authorities(value) -> bool:
    if not value is Dictionary:
        return false
    var authorities: Dictionary = value
    var expected: Dictionary = LS34.AUTHORITY
    if authorities.keys().size() != expected.keys().size():
        return false
    for key in expected.keys():
        if not authorities.has(key) or typeof(authorities[key]) != TYPE_BOOL or bool(authorities[key]) != bool(expected[key]):
            return false
    return true

func _canonical_environment_cells(values: Array) -> Array[Dictionary]:
    var by_index := {}
    for value in values:
        if not value is Dictionary:
            return []
        var cell: Dictionary = value
        var index := int(cell.get("index", -1)); var x := int(cell.get("x", -1)); var y := int(cell.get("y", -1))
        if index < 0 or index >= GRID_SIZE * GRID_SIZE or by_index.has(index) or index != y * GRID_SIZE + x:
            return []
        by_index[index] = cell
    if by_index.size() != GRID_SIZE * GRID_SIZE:
        return []
    var result: Array[Dictionary] = []
    for index in GRID_SIZE * GRID_SIZE:
        result.append(Dictionary(by_index[index]))
    return result

func _cell_metrics(index: int, env: Dictionary, records: Array, eval_by_id: Dictionary, water_by_cell: Dictionary) -> Dictionary:
    var lineage_ids := {}
    var lai_sum := 0.0; var height_max := 0.0; var root_depth_sum := 0.0; var root_shoot_sum := 0.0; var water_sat_sum := 0.0
    var cover_sum := 0.0
    for value in records:
        var record: Dictionary = value
        var record_id := String(record["record_id"])
        if not eval_by_id.has(record_id):
            return {}
        var evaluation: Dictionary = eval_by_id[record_id]
        var bundle_value = record.get("hereditary_bundle")
        if not bundle_value is Dictionary:
            return {}
        var bundle: Dictionary = bundle_value
        var lineage_value = bundle.get("lineage")
        if not lineage_value is Dictionary:
            return {}
        var lineage_id := String(Dictionary(lineage_value).get("lineage_id", ""))
        if lineage_id.is_empty():
            return {}
        lineage_ids[lineage_id] = true
        var lai := maxf(float(evaluation.get("leaf_area_index_proxy", 0.0)), 0.0)
        lai_sum += lai
        height_max = maxf(height_max, maxf(float(evaluation.get("realized_height_m", 0.0)), 0.0))
        root_depth_sum += maxf(float(evaluation.get("realized_root_depth_m", 0.0)), 0.0)
        root_shoot_sum += clampf(float(evaluation.get("root_shoot_ratio", 0.0)), 0.0, 2.0)
        water_sat_sum += clampf(float(evaluation.get("water_satisfaction", 0.0)), 0.0, 1.0)
        cover_sum += 0.25 * clampf(lai / 0.40, 0.0, 1.0)
    var count := records.size()
    var divisor := maxf(float(count), 1.0)
    var water_after := clampf(float(env.get("soil_moisture", 0.0)), 0.0, 1.0)
    if water_by_cell.has(index):
        water_after = clampf(float(Dictionary(water_by_cell[index]).get("water_after_ppm", 0)) / 1000000.0, 0.0, 1.0)
    return {
        "index": index,
        "x": index % GRID_SIZE,
        "y": index / GRID_SIZE,
        "soil_moisture": clampf(float(env.get("soil_moisture", 0.0)), 0.0, 1.0),
        "surface_water_fraction": clampf(float(env.get("surface_water_fraction", 0.0)), 0.0, 1.0),
        "temperature_c": float(env.get("temperature_c", 0.0)),
        "elevation_m": float(env.get("elevation_m", 0.0)),
        "incident_light": clampf(float(env.get("incident_light", 0.0)), 0.0, 1.0),
        "drainage_index": clampf(float(env.get("drainage_index", 0.0)), 0.0, 1.0),
        "local_relief_m": float(env.get("local_relief_m", 0.0)),
        "occupancy_count": count,
        "occupancy_fraction": snappedf(clampf(float(count) / float(SLOTS_PER_CELL), 0.0, 1.0), 1e-9),
        "cover_proxy": snappedf(clampf(cover_sum, 0.0, 1.0), 1e-9),
        "lineage_richness": lineage_ids.size(),
        "mean_lai": snappedf(lai_sum / divisor if count > 0 else 0.0, 1e-9),
        "canopy_height_m": snappedf(height_max, 1e-9),
        "mean_root_depth_m": snappedf(root_depth_sum / divisor if count > 0 else 0.0, 1e-9),
        "mean_root_shoot_ratio": snappedf(root_shoot_sum / divisor if count > 0 else 0.0, 1e-9),
        "mean_water_satisfaction": snappedf(water_sat_sum / divisor if count > 0 else water_after, 1e-9),
        "water_state": snappedf(water_after, 1e-9),
    }

func _add_spatial_metrics(cells: Array[Dictionary]) -> void:
    for index in cells.size():
        var x := index % GRID_SIZE; var y := index / GRID_SIZE
        var neighbor_count := 0; var occupied_neighbors := 0; var cover_sum := 0.0
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                if dx == 0 and dy == 0:
                    continue
                var nx := x + dx; var ny := y + dy
                if nx < 0 or nx >= GRID_SIZE or ny < 0 or ny >= GRID_SIZE:
                    continue
                var neighbor: Dictionary = cells[ny * GRID_SIZE + nx]
                neighbor_count += 1
                if int(neighbor["occupancy_count"]) > 0:
                    occupied_neighbors += 1
                cover_sum += float(neighbor["cover_proxy"])
        var occupied_neighbor_fraction := float(occupied_neighbors) / float(maxi(neighbor_count, 1))
        var neighbor_cover := cover_sum / float(maxi(neighbor_count, 1))
        var continuity := clampf(0.65 * occupied_neighbor_fraction + 0.35 * neighbor_cover, 0.0, 1.0)
        cells[index]["occupied_neighbor_fraction"] = snappedf(occupied_neighbor_fraction, 1e-9)
        cells[index]["neighbor_cover_mean"] = snappedf(neighbor_cover, 1e-9)
        cells[index]["continuity"] = snappedf(continuity, 1e-9)
        cells[index]["fragmentation"] = snappedf(1.0 - continuity, 1e-9)

func _base_scores(cell: Dictionary) -> Dictionary:
    var moisture := clampf(float(cell["soil_moisture"]), 0.0, 1.0)
    var wetness := maxf(moisture, clampf(float(cell["surface_water_fraction"]), 0.0, 1.0))
    var dryness := 1.0 - moisture
    var cover := clampf(float(cell["cover_proxy"]), 0.0, 1.0)
    var continuity := clampf(float(cell["continuity"]), 0.0, 1.0)
    var drainage := clampf(float(cell["drainage_index"]), 0.0, 1.0)
    var water_sat := clampf(float(cell["mean_water_satisfaction"]), 0.0, 1.0)
    var height_n := clampf(float(cell["canopy_height_m"]) / 5.0, 0.0, 1.0)
    var lai_n := clampf(float(cell["mean_lai"]) / 0.35, 0.0, 1.0)
    var cold_n := clampf((-float(cell["temperature_c"]) - 2.0) / 18.0, 0.0, 1.0)
    var elevation_n := clampf((float(cell["elevation_m"]) - 800.0) / 2200.0, 0.0, 1.0)
    var relief_n := clampf(absf(float(cell["local_relief_m"])) / 30.0, 0.0, 1.0)
    var moderate_moisture := clampf(1.0 - absf(moisture - 0.50) / 0.50, 0.0, 1.0)
    var occupied := int(cell["occupancy_count"]) > 0
    var forest := 0.0
    var shrub := 0.0
    if occupied:
        forest = 0.28 * cover + 0.20 * height_n + 0.22 * lai_n + 0.15 * continuity + 0.15 * moisture
        shrub = 0.24 * (1.0 - height_n) + 0.22 * (1.0 - lai_n) + 0.18 * (1.0 - cover) + 0.18 * moderate_moisture + 0.18 * continuity
    return {
        "desert-like": snappedf(0.48 * dryness + 0.22 * (1.0 - cover) + 0.15 * drainage + 0.15 * (1.0 - continuity), 1e-9),
        "wetland-like": snappedf(0.50 * wetness + 0.15 * float(cell["surface_water_fraction"]) + 0.15 * (1.0 - drainage) + 0.10 * cover + 0.10 * water_sat, 1e-9),
        "forest-like": snappedf(forest, 1e-9),
        "grass/shrub-like": snappedf(shrub, 1e-9),
        "alpine-like": snappedf(0.30 * cold_n + 0.25 * elevation_n + 0.20 * (1.0 - height_n) + 0.15 * (1.0 - cover) + 0.10 * relief_n, 1e-9),
    }

func _rank_scores(scores: Dictionary) -> Array[Dictionary]:
    var ranked: Array[Dictionary] = []
    for label in BASE_LABELS:
        ranked.append({"label": label, "score": float(scores.get(label, -1.0))})
    ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if absf(float(a["score"]) - float(b["score"])) > 1e-12:
            return float(a["score"]) > float(b["score"])
        return String(a["label"]) < String(b["label"])
    )
    return ranked

func _apply_ecotones(cells: Array[Dictionary]) -> void:
    for index in cells.size():
        var cell: Dictionary = cells[index]
        var x := index % GRID_SIZE; var y := index / GRID_SIZE
        var neighbor_labels := {}; var neighbor_count := 0; var moisture_gradient := 0.0; var cover_gradient := 0.0; var height_gradient := 0.0
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                if dx == 0 and dy == 0:
                    continue
                var nx := x + dx; var ny := y + dy
                if nx < 0 or nx >= GRID_SIZE or ny < 0 or ny >= GRID_SIZE:
                    continue
                var neighbor: Dictionary = cells[ny * GRID_SIZE + nx]
                var neighbor_label := String(neighbor["base_label"])
                neighbor_labels[neighbor_label] = int(neighbor_labels.get(neighbor_label, 0)) + 1
                neighbor_count += 1
                moisture_gradient += absf(float(cell["soil_moisture"]) - float(neighbor["soil_moisture"]))
                cover_gradient += absf(float(cell["cover_proxy"]) - float(neighbor["cover_proxy"]))
                height_gradient += clampf(absf(float(cell["canopy_height_m"]) - float(neighbor["canopy_height_m"])) / 5.0, 0.0, 1.0)
        var dominant_count := 0
        for count_value in neighbor_labels.values():
            dominant_count = maxi(dominant_count, int(count_value))
        var disagreement := 0.0 if neighbor_count == 0 else 1.0 - float(dominant_count) / float(neighbor_count)
        var gradient := 0.0 if neighbor_count == 0 else 0.50 * moisture_gradient / float(neighbor_count) + 0.30 * cover_gradient / float(neighbor_count) + 0.20 * height_gradient / float(neighbor_count)
        var boundary_strength := clampf(0.60 * disagreement + 0.40 * gradient, 0.0, 1.0)
        var is_ecotone := neighbor_labels.size() >= 2 and disagreement >= 0.25 and (float(cell["class_margin"]) <= 0.18 or boundary_strength >= 0.24)
        cell["neighbor_base_class_count"] = neighbor_labels.size()
        cell["class_disagreement"] = snappedf(disagreement, 1e-9)
        cell["measured_gradient"] = snappedf(gradient, 1e-9)
        cell["boundary_strength"] = snappedf(boundary_strength, 1e-9)
        cell["label"] = "ecotone" if is_ecotone else String(cell["base_label"])

func _occupied_cell_count(cells: Array[Dictionary]) -> int:
    var count := 0
    for cell in cells:
        if int(cell["occupancy_count"]) > 0:
            count += 1
    return count

func _mean_metric(cells: Array[Dictionary], key: String) -> float:
    if cells.is_empty():
        return 0.0
    var total := 0.0
    for cell in cells:
        total += float(cell.get(key, 0.0))
    return total / float(cells.size())

func _cell_hash(cell: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION, REVISION,
        str(int(cell["index"])),
        _f(float(cell["soil_moisture"])), _f(float(cell["surface_water_fraction"])), _f(float(cell["temperature_c"])), _f(float(cell["elevation_m"])),
        _f(float(cell["incident_light"])), _f(float(cell["drainage_index"])), _f(float(cell["local_relief_m"])),
        str(int(cell["occupancy_count"])), _f(float(cell["occupancy_fraction"])), _f(float(cell["cover_proxy"])), str(int(cell["lineage_richness"])),
        _f(float(cell["mean_lai"])), _f(float(cell["canopy_height_m"])), _f(float(cell["mean_root_depth_m"])), _f(float(cell["mean_root_shoot_ratio"])),
        _f(float(cell["mean_water_satisfaction"])), _f(float(cell["water_state"])), _f(float(cell["continuity"])), _f(float(cell["fragmentation"])),
        String(cell["base_label"]), String(cell["label"]), _f(float(cell["base_score"])), _f(float(cell["second_score"])), _f(float(cell["class_margin"])),
        _f(float(cell["class_disagreement"])), _f(float(cell["measured_gradient"])), _f(float(cell["boundary_strength"])),
    ])
    for label in BASE_LABELS:
        tokens.append("%s=%s" % [label, _f(float(Dictionary(cell["scores"])[label]))])
    return "|".join(tokens).sha256_text()

func _summary_hash(summary: Dictionary) -> String:
    var tokens := PackedStringArray([SCHEMA, VERSION, REVISION, "summary"])
    var counts: Dictionary = summary["class_counts"]
    var fractions: Dictionary = summary["class_fractions"]
    for label in LABELS:
        tokens.append("%s=%d" % [label, int(counts[label])])
        tokens.append("%s_fraction=%s" % [label, _f(float(fractions[label]))])
    tokens.append(str(int(summary["distinct_base_classes"])))
    tokens.append(str(int(summary["ecotone_cells"])))
    tokens.append(str(int(summary["occupied_cells"])))
    tokens.append(_f(float(summary["mean_cover_proxy"])))
    tokens.append(_f(float(summary["mean_continuity"])))
    tokens.append(_f(float(summary["mean_fragmentation"])))
    return "|".join(tokens).sha256_text()

func _classification_hash(result: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION, REVISION,
        String(result["source_environment_field_hash"]), String(result["source_ecology_state_hash"]), String(result["source_population_hash"]),
        str(int(result["generation"])), String(Dictionary(result["summary"])["summary_hash"]), _authority_hash(),
    ])
    for cell_value in Array(result["cells"]):
        tokens.append(String(Dictionary(cell_value)["cell_hash"]))
    return "|".join(tokens).sha256_text()

func _authority_hash() -> String:
    var tokens := PackedStringArray([SCHEMA, VERSION, REVISION, "authority"])
    var keys: Array = AUTHORITY.keys(); keys.sort()
    for key in keys:
        tokens.append("%s=%s" % [String(key), "1" if bool(AUTHORITY[key]) else "0"])
    return "|".join(tokens).sha256_text()

func _f(value: float) -> String:
    return "%.9f" % value
