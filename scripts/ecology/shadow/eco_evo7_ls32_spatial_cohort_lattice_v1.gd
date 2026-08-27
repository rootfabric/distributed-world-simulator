extends RefCounted

## ECO.EVO7 LS3.2 — deterministic RAM-only spatial metapopulation substrate.
##
## This stage materializes bounded ecological records over the accepted 32x32
## PlanetPatch. It intentionally does NOT reproduce, disperse, recruit, compete,
## mutate, persist, network, or write to production world state.
##
## All occupied records begin as exact copies of ONE canonical ancestor bundle.
## Environment identity is retained as read-only context, never as founder,
## placement, hereditary, or mutation identity.

const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const DevTraits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const ExtTraits = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")
const Shadow = preload("res://scripts/ecology/shadow/eco_evo7_live_world_shadow_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_spatial_cohort_lattice.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.2.3"
const MODE := "SHADOW_RAM_ONLY"
const R1_GRID_SIZE := 32
const MAX_SLOTS_PER_CELL := 4
const MAX_RECORDS := R1_GRID_SIZE * R1_GRID_SIZE * MAX_SLOTS_PER_CELL
const DEFAULT_INITIAL_RECORDS := 256
const AUTHORITY := {
    "world_write": false,
    "ecology_production_write": false,
    "persistence_write": false,
    "network_replication_write": false,
    "xfer_authority": false,
    "alternate_mutation_authority": false,
    "biome_classifier_ecology_input": false,
}
const SNAPSHOT_FIELDS: Array[String] = [
    "schema", "version", "revision", "mode", "shadow_only",
    "source_patch_hash", "environment_field_hash", "environment_recipe_id", "environment_seed",
    "grid_size", "cell_size_m", "slots_per_cell", "max_records", "record_count",
    "founder_seed", "placement_seed", "founder_bundle_checksum",
    "initial_population_hash", "hereditary_pool_hash", "occupied_slot_addresses_hash",
    "generation", "evolution_enabled", "authorities", "cells", "state_hash",
]
const CELL_FIELDS: Array[String] = ["index", "x", "y", "slots", "cell_hash"]
const EMPTY_SLOT_FIELDS: Array[String] = ["slot_index", "occupied"]
const OCCUPIED_SLOT_FIELDS: Array[String] = ["slot_index", "occupied", "record"]
const RECORD_FIELDS: Array[String] = [
    "record_id", "record_index", "cell_index", "slot_index", "cohort_count",
    "bundle_checksum", "hereditary_bundle", "record_hash",
]
const BUNDLE_FIELDS: Array[String] = [
    "schema", "version", "genome", "dev_traits", "ext_traits", "lineage",
    "individual_seed", "bundle_checksum",
]

var source_patch_hash := ""
var environment_field_hash := ""
var environment_recipe_id := ""
var environment_seed := 0
var grid_size := 0
var cell_size_m := 0.0
var founder_seed := 0
var placement_seed := 0
var generation := 0
var evolution_enabled := false
var founder_bundle: Dictionary = {}
var founder_bundle_checksum := ""
var cells: Array[Dictionary] = []
var record_count := 0
var initial_population_hash := ""
var hereditary_pool_hash := ""
var occupied_slot_addresses_hash := ""
var initialized := false

func setup(
    patch: Dictionary,
    environment_field: Dictionary,
    founder_seed_value: int = 20260832,
    placement_seed_value: int = 20260832,
    initial_records: int = DEFAULT_INITIAL_RECORDS
) -> bool:
    _reset()
    var patch_validator = PlanetPatch.new()
    if not patch_validator.validate_patch(patch):
        return false
    if int(patch.get("grid_size", 0)) != R1_GRID_SIZE:
        return false
    if initial_records < 1 or initial_records > MAX_RECORDS:
        return false
    if not _valid_environment_field(environment_field, patch):
        return false

    source_patch_hash = String(patch["patch_hash"])
    environment_field_hash = String(environment_field["field_hash"])
    environment_recipe_id = String(environment_field["recipe_id"])
    environment_seed = int(environment_field["environment_seed"])
    grid_size = int(patch["grid_size"])
    cell_size_m = float(patch["cell_size_m"])
    founder_seed = founder_seed_value
    placement_seed = placement_seed_value
    generation = 0
    evolution_enabled = false

    founder_bundle = _expected_founder_bundle(founder_seed)
    if founder_bundle.is_empty():
        return false
    founder_bundle_checksum = String(founder_bundle.get("bundle_checksum", ""))
    if founder_bundle_checksum.is_empty() or not _valid_bundle_identity(founder_bundle):
        return false

    cells = _empty_cells()
    if cells.size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return false
    var order := _placement_order(placement_seed, MAX_RECORDS)
    if order.size() != MAX_RECORDS:
        return false
    for record_index in initial_records:
        var ordinal := int(order[record_index])
        var cell_index := ordinal / MAX_SLOTS_PER_CELL
        var slot_index := ordinal % MAX_SLOTS_PER_CELL
        var record := _founder_record(record_index, cell_index, slot_index)
        if record.is_empty():
            return false
        var slot: Dictionary = cells[cell_index]["slots"][slot_index]
        if bool(slot.get("occupied", false)):
            return false
        slot["occupied"] = true
        slot["record"] = record
        cells[cell_index]["slots"][slot_index] = slot

    for cell_index in cells.size():
        cells[cell_index]["cell_hash"] = _cell_hash(cells[cell_index])
    record_count = initial_records
    initial_population_hash = _population_hash(cells)
    hereditary_pool_hash = _hereditary_pool_hash(cells)
    occupied_slot_addresses_hash = _occupied_addresses_hash(cells)
    initialized = true
    var snapshot := get_snapshot()
    if snapshot.is_empty() or not validate_snapshot(snapshot):
        _reset()
        return false
    return true

func get_snapshot() -> Dictionary:
    if not initialized:
        return {}
    var snapshot := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "mode": MODE,
        "shadow_only": true,
        "source_patch_hash": source_patch_hash,
        "environment_field_hash": environment_field_hash,
        "environment_recipe_id": environment_recipe_id,
        "environment_seed": environment_seed,
        "grid_size": grid_size,
        "cell_size_m": cell_size_m,
        "slots_per_cell": MAX_SLOTS_PER_CELL,
        "max_records": MAX_RECORDS,
        "record_count": record_count,
        "founder_seed": founder_seed,
        "placement_seed": placement_seed,
        "founder_bundle_checksum": founder_bundle_checksum,
        "initial_population_hash": initial_population_hash,
        "hereditary_pool_hash": hereditary_pool_hash,
        "occupied_slot_addresses_hash": occupied_slot_addresses_hash,
        "generation": generation,
        "evolution_enabled": evolution_enabled,
        "authorities": AUTHORITY.duplicate(true),
        "cells": cells.duplicate(true),
    }
    snapshot["state_hash"] = _snapshot_hash(snapshot)
    return snapshot

func validate_snapshot(snapshot: Dictionary) -> bool:
    if snapshot.is_empty() or not _has_exact_fields(snapshot, SNAPSHOT_FIELDS):
        return false
    if String(snapshot.get("schema", "")) != SCHEMA or String(snapshot.get("version", "")) != VERSION:
        return false
    if String(snapshot.get("revision", "")) != REVISION or String(snapshot.get("mode", "")) != MODE:
        return false
    if typeof(snapshot.get("shadow_only")) != TYPE_BOOL or not bool(snapshot["shadow_only"]):
        return false
    if typeof(snapshot.get("evolution_enabled")) != TYPE_BOOL or bool(snapshot["evolution_enabled"]):
        return false
    if typeof(snapshot.get("generation")) != TYPE_INT or int(snapshot["generation"]) < 0:
        return false
    for int_field in ["environment_seed", "founder_seed", "placement_seed", "grid_size", "slots_per_cell", "max_records", "record_count"]:
        if typeof(snapshot.get(int_field)) != TYPE_INT:
            return false
    if int(snapshot["grid_size"]) != R1_GRID_SIZE:
        return false
    if int(snapshot["slots_per_cell"]) != MAX_SLOTS_PER_CELL or int(snapshot["max_records"]) != MAX_RECORDS:
        return false
    if not is_finite(float(snapshot.get("cell_size_m", NAN))) or float(snapshot["cell_size_m"]) <= 0.0:
        return false
    for hash_field in ["source_patch_hash", "environment_field_hash", "founder_bundle_checksum", "initial_population_hash", "hereditary_pool_hash", "occupied_slot_addresses_hash", "state_hash"]:
        if not _is_lower_hex_64(String(snapshot.get(hash_field, ""))):
            return false
    if String(snapshot.get("environment_recipe_id", "")).is_empty():
        return false
    var authorities_value = snapshot.get("authorities")
    if not authorities_value is Dictionary:
        return false
    var authorities: Dictionary = authorities_value
    if not _has_exact_fields(authorities, AUTHORITY.keys()):
        return false
    for key in AUTHORITY.keys():
        if typeof(authorities.get(key)) != TYPE_BOOL or bool(authorities[key]) != bool(AUTHORITY[key]):
            return false

    var expected_founder := _expected_founder_bundle(int(snapshot["founder_seed"]))
    if expected_founder.is_empty() or not _valid_bundle_identity(expected_founder):
        return false
    var expected_founder_checksum := String(expected_founder.get("bundle_checksum", ""))
    if String(snapshot["founder_bundle_checksum"]) != expected_founder_checksum:
        return false

    var record_limit := int(snapshot["record_count"])
    if record_limit < 1 or record_limit > MAX_RECORDS:
        return false
    var placement_order := _placement_order(int(snapshot["placement_seed"]), MAX_RECORDS)
    if placement_order.size() != MAX_RECORDS:
        return false

    var snapshot_cells_value = snapshot.get("cells")
    if not snapshot_cells_value is Array:
        return false
    var snapshot_cells: Array = snapshot_cells_value
    if snapshot_cells.size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return false

    var by_index := {}
    var seen_record_indexes := {}
    var counted_records := 0
    for value in snapshot_cells:
        if not value is Dictionary:
            return false
        var cell: Dictionary = value
        if not _has_exact_fields(cell, CELL_FIELDS):
            return false
        if typeof(cell.get("index")) != TYPE_INT or typeof(cell.get("x")) != TYPE_INT or typeof(cell.get("y")) != TYPE_INT:
            return false
        var index := int(cell["index"])
        var x := int(cell["x"])
        var y := int(cell["y"])
        if index < 0 or index >= R1_GRID_SIZE * R1_GRID_SIZE or by_index.has(index):
            return false
        if x < 0 or x >= R1_GRID_SIZE or y < 0 or y >= R1_GRID_SIZE or index != y * R1_GRID_SIZE + x:
            return false
        var slots_value = cell.get("slots")
        if not slots_value is Array or Array(slots_value).size() != MAX_SLOTS_PER_CELL:
            return false
        var seen_slots := {}
        for slot_value in Array(slots_value):
            if not slot_value is Dictionary:
                return false
            var slot: Dictionary = slot_value
            if typeof(slot.get("occupied")) != TYPE_BOOL or typeof(slot.get("slot_index")) != TYPE_INT:
                return false
            var occupied := bool(slot["occupied"])
            if not _has_exact_fields(slot, OCCUPIED_SLOT_FIELDS if occupied else EMPTY_SLOT_FIELDS):
                return false
            var slot_index := int(slot["slot_index"])
            if slot_index < 0 or slot_index >= MAX_SLOTS_PER_CELL or seen_slots.has(slot_index):
                return false
            seen_slots[slot_index] = true
            if not occupied:
                continue
            if not slot["record"] is Dictionary:
                return false
            var record: Dictionary = slot["record"]
            if not _has_exact_fields(record, RECORD_FIELDS):
                return false
            for record_int_field in ["record_index", "cell_index", "slot_index", "cohort_count"]:
                if typeof(record.get(record_int_field)) != TYPE_INT:
                    return false
            var record_index := int(record["record_index"])
            if record_index < 0 or record_index >= record_limit or seen_record_indexes.has(record_index):
                return false
            seen_record_indexes[record_index] = true
            var expected_ordinal := int(placement_order[record_index])
            var expected_cell_index := expected_ordinal / MAX_SLOTS_PER_CELL
            var expected_slot_index := expected_ordinal % MAX_SLOTS_PER_CELL
            if int(record["cell_index"]) != index or int(record["slot_index"]) != slot_index:
                return false
            if index != expected_cell_index or slot_index != expected_slot_index:
                return false
            if int(record["cohort_count"]) != 1:
                return false
            var bundle_value = record.get("hereditary_bundle")
            if not bundle_value is Dictionary:
                return false
            var bundle: Dictionary = bundle_value
            if not _valid_bundle_identity(bundle):
                return false
            if String(bundle.get("bundle_checksum", "")) != expected_founder_checksum:
                return false
            if String(record.get("bundle_checksum", "")) != expected_founder_checksum:
                return false
            var expected_record_id := _record_id(expected_founder_checksum, int(snapshot["placement_seed"]), expected_cell_index, expected_slot_index)
            if String(record.get("record_id", "")) != expected_record_id:
                return false
            if String(record.get("record_hash", "")) != _record_hash(record):
                return false
            counted_records += 1
        if seen_slots.size() != MAX_SLOTS_PER_CELL:
            return false
        if String(cell.get("cell_hash", "")) != _cell_hash(cell):
            return false
        by_index[index] = cell

    if by_index.size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return false
    if counted_records != record_limit or seen_record_indexes.size() != record_limit:
        return false
    for record_index in record_limit:
        if not seen_record_indexes.has(record_index):
            return false
    if String(snapshot["initial_population_hash"]) != _population_hash(snapshot_cells):
        return false
    if String(snapshot["hereditary_pool_hash"]) != _hereditary_pool_hash(snapshot_cells):
        return false
    if String(snapshot["occupied_slot_addresses_hash"]) != _occupied_addresses_hash(snapshot_cells):
        return false
    if String(snapshot["state_hash"]) != _snapshot_hash(snapshot):
        return false
    return true

func set_evolution_enabled(value: bool) -> bool:
    ## LS3.2 intentionally owns no reproduction step. Evolution ON is fail-closed
    ## until LS3.3 introduces the canonical reproduce->disperse->recruit sequence.
    if value:
        return false
    evolution_enabled = false
    return true

func advance_observation_generations(count: int = 1) -> Dictionary:
    if not initialized or evolution_enabled or count < 1:
        return {}
    generation += count
    return get_snapshot()

func get_cell(x: int, y: int) -> Dictionary:
    if not initialized or x < 0 or x >= grid_size or y < 0 or y >= grid_size:
        return {}
    return cells[y * grid_size + x].duplicate(true)

func get_render_projection(max_records: int = 64) -> Array[Dictionary]:
    ## Read-only view adapter. Projection count and returned dictionaries never
    ## participate in ecological hashes and cannot mutate internal lattice state.
    if not initialized or max_records < 1:
        return []
    var result: Array[Dictionary] = []
    var ordered := _canonical_cells(cells)
    for cell in ordered:
        for slot_value in Array(cell["slots"]):
            var slot: Dictionary = slot_value
            if not bool(slot.get("occupied", false)):
                continue
            var record: Dictionary = slot["record"]
            result.append({
                "record_id": String(record["record_id"]),
                "cell_index": int(cell["index"]),
                "x": int(cell["x"]),
                "y": int(cell["y"]),
                "slot_index": int(slot["slot_index"]),
                "bundle_checksum": String(record["bundle_checksum"]),
            })
            if result.size() >= max_records:
                return result
    return result

func request_authoritative_write(surface: String, payload: Dictionary = {}) -> Dictionary:
    return Shadow.request_authoritative_write(surface, payload)

func _reset() -> void:
    source_patch_hash = ""
    environment_field_hash = ""
    environment_recipe_id = ""
    environment_seed = 0
    grid_size = 0
    cell_size_m = 0.0
    founder_seed = 0
    placement_seed = 0
    generation = 0
    evolution_enabled = false
    founder_bundle.clear()
    founder_bundle_checksum = ""
    cells.clear()
    record_count = 0
    initial_population_hash = ""
    hereditary_pool_hash = ""
    occupied_slot_addresses_hash = ""
    initialized = false

func _valid_environment_field(field: Dictionary, patch: Dictionary) -> bool:
    if field.is_empty():
        return false
    if String(field.get("schema", "")) != EnvironmentField.SCHEMA or String(field.get("version", "")) != EnvironmentField.VERSION:
        return false
    if String(field.get("source_patch_hash", "")) != String(patch.get("patch_hash", "")):
        return false
    if int(field.get("grid_size", 0)) != int(patch.get("grid_size", -1)):
        return false
    if absf(float(field.get("cell_size_m", NAN)) - float(patch.get("cell_size_m", NAN))) > 1e-9:
        return false
    var values = field.get("cells")
    if not values is Array or Array(values).size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return false
    var generator = EnvironmentField.new()
    for index in Array(values).size():
        var cell_value = Array(values)[index]
        if not cell_value is Dictionary:
            return false
        var cell: Dictionary = cell_value
        if int(cell.get("index", -1)) != index or int(cell.get("x", -1)) != index % R1_GRID_SIZE or int(cell.get("y", -1)) != index / R1_GRID_SIZE:
            return false
        if String(cell.get("cell_hash", "")) != String(generator.call("_cell_hash", cell)):
            return false
    return String(field.get("field_hash", "")) == String(generator.call("_field_hash", field))

func _valid_bundle_identity(bundle: Dictionary) -> bool:
    if not _has_exact_fields(bundle, BUNDLE_FIELDS):
        return false
    if String(bundle.get("schema", "")) != LineageExtension.SCHEMA or String(bundle.get("version", "")) != LineageExtension.VERSION:
        return false
    if typeof(bundle.get("individual_seed")) != TYPE_INT:
        return false
    if not bundle.get("genome") is Dictionary or not bool(Genome.validate(bundle["genome"]).get("success", false)):
        return false
    if not bundle.get("dev_traits") is Dictionary or not bool(DevTraits.validate(bundle["dev_traits"]).get("success", false)):
        return false
    if not bundle.get("ext_traits") is Dictionary or not bool(ExtTraits.validate(bundle["ext_traits"]).get("success", false)):
        return false
    if not bundle.get("lineage") is Dictionary or not bool(LineageRecord.validate(bundle["lineage"]).get("success", false)):
        return false
    if String(Dictionary(bundle["lineage"]).get("genome_checksum", "")) != String(Dictionary(bundle["genome"]).get("checksum", "")):
        return false
    var expected := LineageExtension.bundle_checksum(
        bundle["genome"], bundle["dev_traits"], bundle["ext_traits"],
        bundle["lineage"], int(bundle["individual_seed"]))
    return _is_lower_hex_64(expected) and String(bundle["bundle_checksum"]) == expected

func _expected_founder_bundle(seed: int) -> Dictionary:
    ## SINGLE canonical founder factory call site for LS3.2 setup + validation.
    return Morphology.default_ancestor_bundle(seed)

func _has_exact_fields(value: Dictionary, expected_fields) -> bool:
    if value.keys().size() != expected_fields.size():
        return false
    for field in expected_fields:
        if not value.has(field):
            return false
    return true

func _is_lower_hex_64(value: String) -> bool:
    if value.length() != 64 or value != value.to_lower():
        return false
    for character in value:
        if not String(character) in [
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "a", "b", "c", "d", "e", "f",
        ]:
            return false
    return true

func _empty_cells() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for index in R1_GRID_SIZE * R1_GRID_SIZE:
        var slots: Array[Dictionary] = []
        for slot_index in MAX_SLOTS_PER_CELL:
            slots.append({"slot_index": slot_index, "occupied": false})
        result.append({
            "index": index,
            "x": index % R1_GRID_SIZE,
            "y": index / R1_GRID_SIZE,
            "slots": slots,
            "cell_hash": "",
        })
    return result

func _placement_order(seed: int, total_slots: int) -> Array[int]:
    var keyed: Array[Dictionary] = []
    for ordinal in total_slots:
        keyed.append({
            "ordinal": ordinal,
            "key": ("ECO.EVO7-LS3.2|placement|%d|%d" % [seed, ordinal]).sha256_text(),
        })
    keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var key_a := String(a["key"])
        var key_b := String(b["key"])
        if key_a != key_b:
            return key_a < key_b
        return int(a["ordinal"]) < int(b["ordinal"])
    )
    var result: Array[int] = []
    for item in keyed:
        result.append(int(item["ordinal"]))
    return result

func _founder_record(record_index: int, cell_index: int, slot_index: int) -> Dictionary:
    if founder_bundle.is_empty() or cell_index < 0 or slot_index < 0:
        return {}
    var record_id := _record_id(founder_bundle_checksum, placement_seed, cell_index, slot_index)
    var record := {
        "record_id": record_id,
        "record_index": record_index,
        "cell_index": cell_index,
        "slot_index": slot_index,
        "cohort_count": 1,
        "bundle_checksum": founder_bundle_checksum,
        "hereditary_bundle": founder_bundle.duplicate(true),
    }
    record["record_hash"] = _record_hash(record)
    return record

func _record_id(bundle_checksum: String, placement_seed_value: int, cell_index: int, slot_index: int) -> String:
    return "ls32/%s" % ("%s|%d|%d|%d" % [
        bundle_checksum, placement_seed_value, cell_index, slot_index]).sha256_text().substr(0, 24)

func _record_hash(record: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION,
        String(record.get("record_id", "")),
        str(int(record.get("record_index", -1))),
        str(int(record.get("cell_index", -1))),
        str(int(record.get("slot_index", -1))),
        str(int(record.get("cohort_count", 0))),
        String(record.get("bundle_checksum", "")),
    ])).sha256_text()

func _cell_hash(cell: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION,
        str(int(cell.get("index", -1))),
        str(int(cell.get("x", -1))),
        str(int(cell.get("y", -1))),
    ])
    var slots_value = cell.get("slots", [])
    if not slots_value is Array:
        return ""
    var slots: Array = slots_value
    var by_slot := {}
    for slot_value in slots:
        if not slot_value is Dictionary:
            return ""
        var slot: Dictionary = slot_value
        var slot_index := int(slot.get("slot_index", -1))
        if slot_index < 0 or slot_index >= MAX_SLOTS_PER_CELL or by_slot.has(slot_index):
            return ""
        by_slot[slot_index] = slot
    if by_slot.size() != MAX_SLOTS_PER_CELL:
        return ""
    for slot_index in MAX_SLOTS_PER_CELL:
        var slot: Dictionary = by_slot[slot_index]
        if bool(slot.get("occupied", false)):
            if not slot.has("record") or not slot["record"] is Dictionary:
                return ""
            tokens.append("%d:1:%s" % [slot_index, String(Dictionary(slot["record"]).get("record_hash", ""))])
        else:
            if slot.has("record"):
                return ""
            tokens.append("%d:0" % slot_index)
    return "|".join(tokens).sha256_text()

func _population_hash(source_cells: Array) -> String:
    var ordered := _canonical_cells(source_cells)
    if ordered.size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return ""
    var tokens := PackedStringArray([SCHEMA, VERSION, str(R1_GRID_SIZE), str(MAX_SLOTS_PER_CELL)])
    for cell in ordered:
        tokens.append(String(cell.get("cell_hash", "")))
    return "|".join(tokens).sha256_text()

func _hereditary_pool_hash(source_cells: Array) -> String:
    var ordered := _canonical_cells(source_cells)
    if ordered.size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return ""
    var tokens := PackedStringArray([SCHEMA, VERSION, "hereditary-pool"])
    for cell in ordered:
        var by_slot := _slots_by_index(Array(cell["slots"]))
        if by_slot.size() != MAX_SLOTS_PER_CELL:
            return ""
        for slot_index in MAX_SLOTS_PER_CELL:
            var slot: Dictionary = by_slot[slot_index]
            if bool(slot.get("occupied", false)):
                tokens.append(String(Dictionary(slot["record"]).get("bundle_checksum", "")))
    return "|".join(tokens).sha256_text()

func _occupied_addresses_hash(source_cells: Array) -> String:
    var ordered := _canonical_cells(source_cells)
    if ordered.size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return ""
    var tokens := PackedStringArray([SCHEMA, VERSION, "occupied-addresses"])
    for cell in ordered:
        var by_slot := _slots_by_index(Array(cell["slots"]))
        if by_slot.size() != MAX_SLOTS_PER_CELL:
            return ""
        for slot_index in MAX_SLOTS_PER_CELL:
            if bool(Dictionary(by_slot[slot_index]).get("occupied", false)):
                tokens.append("%d:%d" % [int(cell["index"]), slot_index])
    return "|".join(tokens).sha256_text()

func _canonical_cells(source_cells: Array) -> Array[Dictionary]:
    var by_index := {}
    for value in source_cells:
        if not value is Dictionary:
            return []
        var cell: Dictionary = value
        var index := int(cell.get("index", -1))
        if index < 0 or index >= R1_GRID_SIZE * R1_GRID_SIZE or by_index.has(index):
            return []
        by_index[index] = cell
    if by_index.size() != R1_GRID_SIZE * R1_GRID_SIZE:
        return []
    var result: Array[Dictionary] = []
    for index in R1_GRID_SIZE * R1_GRID_SIZE:
        if not by_index.has(index):
            return []
        result.append(Dictionary(by_index[index]))
    return result

func _slots_by_index(source_slots: Array) -> Dictionary:
    var result := {}
    for value in source_slots:
        if not value is Dictionary:
            return {}
        var slot: Dictionary = value
        var slot_index := int(slot.get("slot_index", -1))
        if slot_index < 0 or slot_index >= MAX_SLOTS_PER_CELL or result.has(slot_index):
            return {}
        result[slot_index] = slot
    return result

func _snapshot_hash(snapshot: Dictionary) -> String:
    return "|".join(PackedStringArray([
        SCHEMA, VERSION, REVISION, MODE,
        String(snapshot.get("source_patch_hash", "")),
        String(snapshot.get("environment_field_hash", "")),
        String(snapshot.get("environment_recipe_id", "")),
        str(int(snapshot.get("environment_seed", 0))),
        str(int(snapshot.get("founder_seed", 0))),
        str(int(snapshot.get("placement_seed", 0))),
        str(int(snapshot.get("generation", 0))),
        "evo=1" if bool(snapshot.get("evolution_enabled", false)) else "evo=0",
        String(snapshot.get("founder_bundle_checksum", "")),
        String(snapshot.get("initial_population_hash", "")),
        String(snapshot.get("hereditary_pool_hash", "")),
        String(snapshot.get("occupied_slot_addresses_hash", "")),
    ])).sha256_text()
