extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const Lattice = preload("res://scripts/ecology/shadow/eco_evo7_ls32_spatial_cohort_lattice_v1.gd")

const FOUNDER_SEED := 20260832
const PLACEMENT_SEED := 320032
const ENV_SEED := 20260831
const INITIAL_RECORDS := 256

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new()
    root.add_child(world)
    _check(world.setup(null), "real Earth initializes")
    var center: Vector3 = world.surface_center_direction
    var patch_builder = PlanetPatch.new()
    var patch := patch_builder.build(world, center, 32, 16.0)
    _check(not patch.is_empty(), "accepted 32x32 PlanetPatch builds")
    if patch.is_empty():
        _finish(); return

    var env_generator = EnvironmentField.new()
    var water := env_generator.generate(patch, "WATER_GRADIENT_STRONG", ENV_SEED)
    var relief := env_generator.generate(patch, "RELIEF_DRAINAGE_STRONG", ENV_SEED)
    var mixed := env_generator.generate(patch, "MIXED_PHYSICAL_HETEROGENEITY", ENV_SEED)
    _check(not water.is_empty() and not relief.is_empty() and not mixed.is_empty(), "three counterfactual physical fields build")
    _check(String(water["field_hash"]) != String(relief["field_hash"]), "counterfactual field identities differ")

    var a = Lattice.new()
    var b = Lattice.new()
    var c = Lattice.new()
    _check(a.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, INITIAL_RECORDS), "water counterfactual lattice initializes")
    _check(b.setup(patch, relief, FOUNDER_SEED, PLACEMENT_SEED, INITIAL_RECORDS), "relief counterfactual lattice initializes")
    _check(c.setup(patch, mixed, FOUNDER_SEED, PLACEMENT_SEED, INITIAL_RECORDS), "mixed counterfactual lattice initializes")
    if not a.initialized or not b.initialized or not c.initialized:
        world.queue_free(); _finish(); return

    var sa := a.get_snapshot()
    var sb := b.get_snapshot()
    var sc := c.get_snapshot()
    _check(a.validate_snapshot(sa) and b.validate_snapshot(sb) and c.validate_snapshot(sc), "counterfactual snapshots validate")
    _check(int(sa["grid_size"]) == 32 and Array(sa["cells"]).size() == 1024, "lattice is one 32x32 metapopulation")
    _check(int(sa["slots_per_cell"]) == 4, "each cell exposes exactly four bounded slots")
    _check(int(sa["max_records"]) == 4096, "32x32x4 ecological record ceiling is 4096")
    _check(int(sa["record_count"]) == INITIAL_RECORDS, "R1 founder initialization materializes configured bounded record count")

    _check(String(sa["initial_population_hash"]) == String(sb["initial_population_hash"]) and String(sb["initial_population_hash"]) == String(sc["initial_population_hash"]), "initial population hash is identical across counterfactual recipes")
    _check(String(sa["hereditary_pool_hash"]) == String(sb["hereditary_pool_hash"]) and String(sb["hereditary_pool_hash"]) == String(sc["hereditary_pool_hash"]), "hereditary pool is identical across counterfactual recipes")
    _check(String(sa["occupied_slot_addresses_hash"]) == String(sb["occupied_slot_addresses_hash"]) and String(sb["occupied_slot_addresses_hash"]) == String(sc["occupied_slot_addresses_hash"]), "same placement seed gives identical addresses across environments")
    _check(String(sa["founder_bundle_checksum"]) == String(sb["founder_bundle_checksum"]), "counterfactuals use one exact founder source")
    _check(String(sa["environment_field_hash"]) != String(sb["environment_field_hash"]), "environment context remains distinguishable outside population identity")

    var unique_bundles := {}
    var occupied_cells := 0
    var empty_cells := 0
    var first_occupied: Dictionary = {}
    var first_empty: Dictionary = {}
    for cell_value in Array(sa["cells"]):
        var cell: Dictionary = cell_value
        var occupied_in_cell := 0
        _check(Array(cell["slots"]).size() == 4, "cell %d has four slots" % int(cell["index"]))
        for slot_value in Array(cell["slots"]):
            var slot: Dictionary = slot_value
            if bool(slot["occupied"]):
                occupied_in_cell += 1
                var record: Dictionary = slot["record"]
                unique_bundles[String(record["bundle_checksum"])] = true
                _check(String(record["bundle_checksum"]) == String(Dictionary(record["hereditary_bundle"])["bundle_checksum"]), "record hereditary identity is internally exact")
        _check(occupied_in_cell <= 4, "cell %d never exceeds four live records" % int(cell["index"]))
        if occupied_in_cell > 0:
            occupied_cells += 1
            if first_occupied.is_empty():
                first_occupied = cell
        else:
            empty_cells += 1
            if first_empty.is_empty():
                first_empty = cell
    _check(unique_bundles.size() == 1, "all founder records are exact copies of one hereditary bundle")
    _check(occupied_cells > 0 and empty_cells > 0, "initial lattice contains deterministic occupied and empty cells")
    _check(not first_occupied.is_empty() and not first_empty.is_empty() and String(first_occupied["cell_hash"]) != String(first_empty["cell_hash"]), "empty and occupied cells have unambiguous distinct state hashes")

    var replay = Lattice.new()
    _check(replay.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, INITIAL_RECORDS), "same-seed replay initializes")
    var sr := replay.get_snapshot()
    _check(String(sr["state_hash"]) == String(sa["state_hash"]), "same patch/environment/founder/placement replays exactly")
    if not first_occupied.is_empty():
        var replay_cell: Dictionary = Array(sr["cells"])[int(first_occupied["index"])]
        _check(String(replay_cell["cell_hash"]) == String(first_occupied["cell_hash"]), "occupied cell state hash replays exactly")
    if not first_empty.is_empty():
        var replay_empty: Dictionary = Array(sr["cells"])[int(first_empty["index"])]
        _check(String(replay_empty["cell_hash"]) == String(first_empty["cell_hash"]), "empty cell state hash replays exactly")

    var moved = Lattice.new()
    _check(moved.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED + 1, INITIAL_RECORDS), "alternate placement seed initializes")
    var sm := moved.get_snapshot()
    _check(String(sm["occupied_slot_addresses_hash"]) != String(sa["occupied_slot_addresses_hash"]), "placement seed alone changes spatial addresses")
    _check(String(sm["initial_population_hash"]) != String(sa["initial_population_hash"]), "placement seed changes spatial population hash")
    _check(String(sm["hereditary_pool_hash"]) == String(sa["hereditary_pool_hash"]), "placement seed cannot change hereditary pool")
    _check(String(sm["founder_bundle_checksum"]) == String(sa["founder_bundle_checksum"]), "placement seed cannot change founder bundle")

    var other_founder = Lattice.new()
    _check(other_founder.setup(patch, water, FOUNDER_SEED + 1, PLACEMENT_SEED, INITIAL_RECORDS), "alternate founder seed initializes")
    var sf := other_founder.get_snapshot()
    _check(String(sf["occupied_slot_addresses_hash"]) == String(sa["occupied_slot_addresses_hash"]), "founder seed cannot change placement")
    _check(String(sf["hereditary_pool_hash"]) != String(sa["hereditary_pool_hash"]), "founder seed changes hereditary identity")

    _check(a.set_evolution_enabled(false), "Evolution OFF is accepted")
    var before_off := a.get_snapshot()
    var after_off := a.advance_observation_generations(7)
    _check(int(after_off.get("generation", -1)) == 7, "Evolution OFF control advances observation generation")
    _check(String(after_off.get("initial_population_hash", "")) == String(before_off.get("initial_population_hash", "")), "Evolution OFF preserves exact spatial population identity")
    _check(String(after_off.get("hereditary_pool_hash", "")) == String(before_off.get("hereditary_pool_hash", "")), "Evolution OFF preserves exact hereditary bundle identities")
    _check(not a.set_evolution_enabled(true), "LS3.2 fails closed on premature Evolution ON")

    var state_before_projection := String(a.get_snapshot()["state_hash"])
    var projection16 := a.get_render_projection(16)
    var projection64 := a.get_render_projection(64)
    _check(projection16.size() == 16 and projection64.size() == 64, "renderer projection may materialize fewer records than ecology")
    _check(projection64.size() < int(a.get_snapshot()["record_count"]), "render materialization count is not ecological record count")
    if not projection16.is_empty():
        projection16[0]["record_id"] = "tampered-render-copy"
    _check(String(a.get_snapshot()["state_hash"]) == state_before_projection, "renderer projection cannot mutate ecological truth")
    _check(not a.get_snapshot().has("render_projection"), "renderer state is absent from ecological snapshot")

    var cell_copy := a.get_cell(int(first_occupied["x"]), int(first_occupied["y"]))
    var internal_hash_before := String(first_occupied["cell_hash"])
    if not cell_copy.is_empty():
        cell_copy["cell_hash"] = "tampered-copy"
    var internal_cell_after := a.get_cell(int(first_occupied["x"]), int(first_occupied["y"]))
    _check(String(internal_cell_after.get("cell_hash", "")) == internal_hash_before, "get_cell returns a non-authoritative copy")

    var reordered: Dictionary = sa.duplicate(true)
    var reordered_cells: Array = reordered["cells"]
    reordered_cells.reverse()
    reordered["cells"] = reordered_cells
    _check(a.validate_snapshot(reordered), "cell array order does not alter canonical lattice validation")

    var stale_env: Dictionary = water.duplicate(true)
    stale_env["cells"][0]["soil_moisture"] = 0.123456
    var stale_lattice = Lattice.new()
    _check(not stale_lattice.setup(patch, stale_env, FOUNDER_SEED, PLACEMENT_SEED, INITIAL_RECORDS), "stale environment identity is rejected before lattice initialization")

    var tampered: Dictionary = sa.duplicate(true)
    var tamper_cell: Dictionary = {}
    var tamper_slot: Dictionary = {}
    for cell_value in Array(tampered["cells"]):
        var cell: Dictionary = cell_value
        for slot_value in Array(cell["slots"]):
            var slot: Dictionary = slot_value
            if bool(slot.get("occupied", false)):
                tamper_cell = cell
                tamper_slot = slot
                break
        if not tamper_slot.is_empty():
            break
    if not tamper_slot.is_empty():
        var record: Dictionary = tamper_slot["record"]
        record["bundle_checksum"] = "0".repeat(64)
        record["record_hash"] = a.call("_record_hash", record)
        tamper_slot["record"] = record
        tamper_cell["cell_hash"] = a.call("_cell_hash", tamper_cell)
        tampered["initial_population_hash"] = a.call("_population_hash", tampered["cells"])
        tampered["hereditary_pool_hash"] = a.call("_hereditary_pool_hash", tampered["cells"])
        tampered["state_hash"] = a.call("_snapshot_hash", tampered)
        _check(not a.validate_snapshot(tampered), "hereditary tamper fails closed even after ecological hashes are recomputed")

    var deep_tamper: Dictionary = sa.duplicate(true)
    var deep_address := _first_occupied_address(deep_tamper)
    if not deep_address.is_empty():
        var deep_cell: Dictionary = deep_tamper["cells"][int(deep_address["cell_array_index"])]
        var deep_slot: Dictionary = deep_cell["slots"][int(deep_address["slot_array_index"])]
        var deep_record: Dictionary = deep_slot["record"]
        var deep_bundle: Dictionary = deep_record["hereditary_bundle"]
        var deep_genome: Dictionary = deep_bundle["genome"]
        deep_genome["root_depth_m"] = float(deep_genome["root_depth_m"]) + 0.125
        _rehash_snapshot(a, deep_tamper)
        _check(not a.validate_snapshot(deep_tamper), "nested genome tamper fails closed after ecological rehash")

    var foreign_one: Dictionary = sa.duplicate(true)
    var foreign_address := _first_occupied_address(foreign_one)
    var foreign_source_address := _first_occupied_address(sf)
    if not foreign_address.is_empty() and not foreign_source_address.is_empty():
        var foreign_cell: Dictionary = foreign_one["cells"][int(foreign_address["cell_array_index"])]
        var foreign_slot: Dictionary = foreign_cell["slots"][int(foreign_address["slot_array_index"])]
        var foreign_record: Dictionary = foreign_slot["record"]
        var source_cell: Dictionary = sf["cells"][int(foreign_source_address["cell_array_index"])]
        var source_slot: Dictionary = source_cell["slots"][int(foreign_source_address["slot_array_index"])]
        var source_record: Dictionary = source_slot["record"]
        var foreign_bundle: Dictionary = Dictionary(source_record["hereditary_bundle"]).duplicate(true)
        foreign_record["hereditary_bundle"] = foreign_bundle
        foreign_record["bundle_checksum"] = String(foreign_bundle["bundle_checksum"])
        foreign_record["record_id"] = a.call("_record_id", String(foreign_bundle["bundle_checksum"]), PLACEMENT_SEED, int(foreign_record["cell_index"]), int(foreign_record["slot_index"]))
        _rehash_snapshot(a, foreign_one)
        _check(not a.validate_snapshot(foreign_one), "single valid foreign founder injection fails closed after complete rehash")

    var authority_tamper: Dictionary = sa.duplicate(true)
    authority_tamper["authorities"]["world_write"] = true
    authority_tamper["state_hash"] = a.call("_snapshot_hash", authority_tamper)
    _check(not a.validate_snapshot(authority_tamper), "authority escalation fails closed after state rehash")

    var evolution_tamper: Dictionary = sa.duplicate(true)
    evolution_tamper["evolution_enabled"] = true
    evolution_tamper["state_hash"] = a.call("_snapshot_hash", evolution_tamper)
    _check(not a.validate_snapshot(evolution_tamper), "premature evolution state fails closed after state rehash")

    var foreign_population: Dictionary = sf.duplicate(true)
    foreign_population["founder_seed"] = FOUNDER_SEED
    foreign_population["state_hash"] = a.call("_snapshot_hash", foreign_population)
    _check(not a.validate_snapshot(foreign_population), "whole valid foreign population cannot lie about founder seed after rehash")

    var relocated: Dictionary = sa.duplicate(true)
    var relocate_source := _first_occupied_address(relocated)
    var relocate_target := _first_empty_address(relocated)
    if not relocate_source.is_empty() and not relocate_target.is_empty():
        var source_cell_reloc: Dictionary = relocated["cells"][int(relocate_source["cell_array_index"])]
        var source_slot_reloc: Dictionary = source_cell_reloc["slots"][int(relocate_source["slot_array_index"])]
        var moved_record: Dictionary = Dictionary(source_slot_reloc["record"]).duplicate(true)
        source_cell_reloc["slots"][int(relocate_source["slot_array_index"])] = {
            "slot_index": int(source_slot_reloc["slot_index"]), "occupied": false,
        }
        var target_cell_reloc: Dictionary = relocated["cells"][int(relocate_target["cell_array_index"])]
        var target_slot_reloc: Dictionary = target_cell_reloc["slots"][int(relocate_target["slot_array_index"])]
        moved_record["cell_index"] = int(target_cell_reloc["index"])
        moved_record["slot_index"] = int(target_slot_reloc["slot_index"])
        moved_record["record_id"] = a.call("_record_id", String(moved_record["bundle_checksum"]), PLACEMENT_SEED, int(moved_record["cell_index"]), int(moved_record["slot_index"]))
        target_cell_reloc["slots"][int(relocate_target["slot_array_index"])] = {
            "slot_index": int(target_slot_reloc["slot_index"]), "occupied": true, "record": moved_record,
        }
        _rehash_snapshot(a, relocated)
        _check(not a.validate_snapshot(relocated), "record relocation fails closed after complete self-consistent rehash")

    var revision_tamper: Dictionary = sa.duplicate(true)
    revision_tamper["revision"] = "ECO.EVO7-LS3.2.hidden"
    revision_tamper["state_hash"] = a.call("_snapshot_hash", revision_tamper)
    _check(not a.validate_snapshot(revision_tamper), "revision drift fails closed after state rehash")

    var hidden_field: Dictionary = sa.duplicate(true)
    hidden_field["hidden_authority"] = true
    hidden_field["state_hash"] = a.call("_snapshot_hash", hidden_field)
    _check(not a.validate_snapshot(hidden_field), "unexpected hidden authority field fails closed after state rehash")

    var full = Lattice.new()
    _check(full.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, Lattice.MAX_RECORDS), "maximum 4096-record lattice initializes")
    var full_snapshot := full.get_snapshot()
    _check(int(full_snapshot.get("record_count", 0)) == 4096, "maximum lattice materializes exactly 4096 ecological records")
    var full_cells_ok := true
    for cell_value in Array(full_snapshot.get("cells", [])):
        var occupied := 0
        for slot_value in Array(Dictionary(cell_value)["slots"]):
            if bool(Dictionary(slot_value).get("occupied", false)):
                occupied += 1
        if occupied != 4:
            full_cells_ok = false
            break
    _check(full_cells_ok, "4096-record ceiling is exactly four occupied slots per cell")
    var overflow = Lattice.new()
    _check(not overflow.setup(patch, water, FOUNDER_SEED, PLACEMENT_SEED, Lattice.MAX_RECORDS + 1), "record budget above 4096 fails closed")

    var denied := a.request_authoritative_write("earth", {"forbidden": true})
    _check(not bool(denied.get("success", true)) and String(denied.get("error_code", "")) == "ECO_SHADOW_WRITE_FORBIDDEN", "authoritative write remains fail-closed")
    for key in ["world_write", "ecology_production_write", "persistence_write", "network_replication_write", "xfer_authority", "alternate_mutation_authority", "biome_classifier_ecology_input"]:
        _check(not bool(Dictionary(sa["authorities"]).get(key, true)), "LS3.2 forbids authority %s" % key)

    _source_guard()
    world.queue_free()
    _finish()

func _first_occupied_address(snapshot: Dictionary) -> Dictionary:
    var snapshot_cells: Array = snapshot.get("cells", [])
    for cell_array_index in snapshot_cells.size():
        var cell: Dictionary = snapshot_cells[cell_array_index]
        var slots: Array = cell.get("slots", [])
        for slot_array_index in slots.size():
            if bool(Dictionary(slots[slot_array_index]).get("occupied", false)):
                return {"cell_array_index": cell_array_index, "slot_array_index": slot_array_index}
    return {}

func _first_empty_address(snapshot: Dictionary) -> Dictionary:
    var snapshot_cells: Array = snapshot.get("cells", [])
    for cell_array_index in snapshot_cells.size():
        var cell: Dictionary = snapshot_cells[cell_array_index]
        var slots: Array = cell.get("slots", [])
        for slot_array_index in slots.size():
            if not bool(Dictionary(slots[slot_array_index]).get("occupied", false)):
                return {"cell_array_index": cell_array_index, "slot_array_index": slot_array_index}
    return {}

func _rehash_snapshot(lattice, snapshot: Dictionary) -> void:
    for cell_value in Array(snapshot.get("cells", [])):
        var cell: Dictionary = cell_value
        for slot_value in Array(cell.get("slots", [])):
            var slot: Dictionary = slot_value
            if bool(slot.get("occupied", false)) and slot.has("record") and slot["record"] is Dictionary:
                var record: Dictionary = slot["record"]
                record["record_hash"] = lattice.call("_record_hash", record)
        cell["cell_hash"] = lattice.call("_cell_hash", cell)
    snapshot["initial_population_hash"] = lattice.call("_population_hash", snapshot["cells"])
    snapshot["hereditary_pool_hash"] = lattice.call("_hereditary_pool_hash", snapshot["cells"])
    snapshot["occupied_slot_addresses_hash"] = lattice.call("_occupied_addresses_hash", snapshot["cells"])
    snapshot["state_hash"] = lattice.call("_snapshot_hash", snapshot)

func _source_guard() -> void:
    var path := "res://scripts/ecology/shadow/eco_evo7_ls32_spatial_cohort_lattice_v1.gd"
    var source := FileAccess.get_file_as_string(path)
    var lower := source.to_lower()
    _check(not lower.contains("biome_code") and not lower.contains("biome_name") and not lower.contains("tree_density"), "LS3.2 has no legacy vegetation-class causal read")
    _check(not source.contains("reproduce_bundle("), "LS3.2 has no reproduction call site")
    _check(not lower.contains("mutation_seed"), "LS3.2 owns no mutation seed path")
    _check(not lower.contains("randomize("), "LS3.2 introduces no random RNG authority")
    _check(not lower.contains("randf("), "LS3.2 introduces no randf path")
    _check(not lower.contains("randi("), "LS3.2 introduces no randi path")
    _check(not lower.contains("fileaccess.open"), "LS3.2 has no persistence write path")
    _check(not lower.contains("diraccess"), "LS3.2 has no directory write path")
    _check(not lower.contains("multiplayer"), "LS3.2 has no network path")
    _check(source.count("Morphology.default_ancestor_bundle(") == 1, "LS3.2 has one exact founder source call site")
    var placement_start := source.find("func _placement_order")
    var placement_end := source.find("\nfunc ", placement_start + 1)
    var placement_logic := source.substr(placement_start, placement_end - placement_start).to_lower()
    _check(not placement_logic.contains("environment") and not placement_logic.contains("recipe") and not placement_logic.contains("moisture"), "placement seed path is environment-neutral")
    var founder_start := source.find("func _founder_record")
    var founder_end := source.find("\nfunc ", founder_start + 1)
    var founder_logic := source.substr(founder_start, founder_end - founder_start).to_lower()
    _check(not founder_logic.contains("environment") and not founder_logic.contains("recipe") and not founder_logic.contains("moisture"), "founder materialization is environment-neutral")
    var population_hash_start := source.find("func _population_hash")
    var population_hash_end := source.find("\nfunc ", population_hash_start + 1)
    var population_hash_logic := source.substr(population_hash_start, population_hash_end - population_hash_start).to_lower()
    _check(not population_hash_logic.contains("render"), "renderer is absent from ecological population identity")

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)

func _finish() -> void:
    if failures.is_empty():
        print("ECO.EVO7 LS3.2 Spatial Cohort Lattice: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error("ECO.EVO7 LS3.2 FAIL: %s" % failure)
    print("ECO.EVO7 LS3.2 Spatial Cohort Lattice: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)
