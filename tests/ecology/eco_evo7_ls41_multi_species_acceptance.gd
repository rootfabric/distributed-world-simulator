extends SceneTree

const EarthWorld = preload("res://scripts/world/earth/procedural_earth_world.gd")
const LS41 = preload("res://scripts/ecology/shadow/eco_evo7_ls41_multi_species_ecology_v1.gd")
const SpeciesCatalog = preload("res://scripts/ecology/shadow/eco_evo7_ls41_species_catalog_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")
const LegacyWorkbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
    var world = EarthWorld.new()
    root.add_child(world)
    _check(world.setup(null), "real Earth initializes")

    # Frozen species catalog: >=3 distinct functional strategies, no authored placement.
    var catalog := SpeciesCatalog.catalog()
    _check(SpeciesCatalog.validate_catalog(catalog), "species catalog validates")
    _check(catalog.size() >= 3, "catalog contains at least three species")
    var catalog_hash := SpeciesCatalog.catalog_hash(catalog)
    _check(catalog_hash.length() == 64, "catalog publishes stable hash")
    var species_ids := {}
    var species_hashes := {}
    var axis_signatures := {}
    for entry in catalog:
        var species_id := String(entry.get("species_id", ""))
        _check(not species_id.is_empty() and not species_ids.has(species_id), "species id is unique: %s" % species_id)
        species_ids[species_id] = true
        var species_hash := SpeciesCatalog.species_hash(entry)
        _check(species_hash.length() == 64 and not species_hashes.has(species_hash), "species identity is unique: %s" % species_id)
        species_hashes[species_hash] = true
        var axes: Dictionary = entry.get("functional_axes", {})
        var signature := JSON.stringify(axes, "", true)
        _check(not axis_signatures.has(signature), "functional strategy is distinct: %s" % species_id)
        axis_signatures[signature] = true
        for forbidden in ["biome", "biome_id", "cell", "cell_index", "x", "y", "world", "world_seed", "placement_seed"]:
            _check(not entry.has(forbidden), "catalog has no desired-biome/placement field %s" % forbidden)

    # Main LS4.1 aggregate on one shared physical patch/environment.
    var eco = LS41.new()
    _check(eco.setup(world), "LS4.1 aggregate initializes")
    var initial := eco.get_snapshot()
    _check(not initial.is_empty(), "initial aggregate snapshot exists")
    _check(eco.validate_snapshot(initial), "initial aggregate snapshot validates")
    _check(int(initial.get("generation", -1)) == 0, "aggregate starts at generation zero")
    _check(int(initial.get("species_count", 0)) == catalog.size(), "all catalog species are materialized")
    _check(String(initial.get("species_catalog_hash", "")) == catalog_hash, "aggregate binds exact catalog identity")
    _check(String(initial.get("source_patch_hash", "")).length() == 64, "aggregate binds physical patch")
    _check(String(initial.get("environment_field_hash", "")).length() == 64, "aggregate binds environment field")
    _check(int(initial.get("total_record_count", 0)) == catalog.size() * LS41.INITIAL_RECORDS_PER_SPECIES, "initial records are bounded per species")

    var founder_pools := {}
    var state_hashes := {}
    for item_value in Array(initial.get("species", [])):
        var item: Dictionary = item_value
        var species_id := String(item.get("species_id", ""))
        _check(String(item.get("species_hash", "")).length() == 64, "species summary binds species hash: %s" % species_id)
        _check(String(item.get("hereditary_pool_hash", "")).length() == 64, "species has hereditary pool: %s" % species_id)
        _check(not founder_pools.has(String(item["hereditary_pool_hash"])), "species has distinct founder heredity: %s" % species_id)
        founder_pools[String(item["hereditary_pool_hash"])] = true
        _check(String(item.get("ecology_state_hash", "")).length() == 64, "species runs accepted LS3 ecology state: %s" % species_id)
        state_hashes[String(item["ecology_state_hash"])] = true
    _check(founder_pools.size() == catalog.size(), "all species founder pools are distinct")
    _check(state_hashes.size() == catalog.size(), "all species have distinct causal ecology identity")

    # Derived LS4-VIS1 projection is read-only and deterministic.
    var before_projection_state := String(initial.get("state_hash", ""))
    var projection_a := eco.get_species_projection()
    var projection_b := eco.get_species_projection()
    _check(projection_a.size() == 1024, "species projection covers full 32x32 patch")
    _check(projection_a == projection_b, "species projection is deterministic")
    _check(String(eco.get_snapshot().get("state_hash", "")) == before_projection_state, "species projection cannot mutate ecology")
    var occupied_cells := 0
    for cell_value in projection_a:
        var cell: Dictionary = cell_value
        _check(int(cell.get("species_richness", -1)) >= 0 and int(cell.get("species_richness", -1)) <= catalog.size(), "cell species richness is bounded")
        _check(int(cell.get("total_records", -1)) >= 0, "cell population count is non-negative")
        if int(cell.get("total_records", 0)) > 0:
            occupied_cells += 1
            _check(not String(cell.get("dominant_species_id", "")).is_empty(), "occupied cell has deterministic dominant species")
    _check(occupied_cells > 0, "initial multi-species projection has occupied cells")

    # One complete aggregate generation: every species advances exactly once.
    var generation_one := eco.step_generations(1)
    _check(not generation_one.is_empty(), "aggregate advances one generation")
    _check(int(generation_one.get("generation", -1)) == 1, "aggregate generation is one")
    _check(eco.validate_snapshot(generation_one), "generation-one snapshot validates")
    for item_value in Array(generation_one.get("species", [])):
        var item: Dictionary = item_value
        _check(String(item.get("ecology_state_hash", "")).length() == 64, "post-step species state remains sealed")
        _check(int(item.get("record_count", -1)) >= 0 and int(item.get("record_count", -1)) <= 4096, "post-step species population remains bounded")

    # Exact replay: same physical inputs + same catalog => same aggregate identity.
    var replay = LS41.new()
    _check(replay.setup(world), "replay aggregate initializes")
    var replay_one := replay.step_generations(1)
    _check(not replay_one.is_empty(), "replay advances one generation")
    _check(String(replay_one.get("state_hash", "")) == String(generation_one.get("state_hash", "")), "same inputs replay exact aggregate state")
    _check(String(replay_one.get("species_projection_hash", "")) == String(generation_one.get("species_projection_hash", "")), "same inputs replay exact species distribution")

    # Physical counterfactual: founder catalog is immutable; environment changes distribution causally.
    var recipes := EnvironmentField.new().recipe_ids()
    var alternate_recipe := ""
    for recipe in recipes:
        if String(recipe) != LS41.DEFAULT_RECIPE:
            alternate_recipe = String(recipe)
            break
    _check(not alternate_recipe.is_empty(), "an alternate physical recipe exists")
    var counterfactual = LS41.new()
    _check(counterfactual.setup(world, LS41.DEFAULT_WORLD_SEED, LS41.DEFAULT_ENVIRONMENT_SEED, alternate_recipe), "physical counterfactual initializes")
    var counter_initial := counterfactual.get_snapshot()
    _check(String(counter_initial.get("species_catalog_hash", "")) == catalog_hash, "physical counterfactual preserves species catalog")
    _check(String(counter_initial.get("source_patch_hash", "")) == String(initial.get("source_patch_hash", "")), "recipe counterfactual preserves physical patch")
    _check(String(counter_initial.get("environment_field_hash", "")) != String(initial.get("environment_field_hash", "")), "recipe counterfactual changes environment field")
    var counter_one := counterfactual.step_generations(1)
    _check(not counter_one.is_empty(), "physical counterfactual advances")
    _check(String(counter_one.get("species_catalog_hash", "")) == catalog_hash, "counterfactual cannot retune species")
    _check(String(counter_one.get("state_hash", "")) != String(generation_one.get("state_hash", "")), "physical environment changes aggregate causal state")
    _check(String(counter_one.get("species_projection_hash", "")) != String(generation_one.get("species_projection_hash", "")), "physical environment changes species distribution")

    # Authority fences: LS4.1 has no WORLD/shared-resource/interaction authority yet.
    var authorities: Dictionary = initial.get("authorities", {})
    _check(bool(authorities.get("research_shadow_only", false)), "LS4.1 remains research shadow only")
    _check(bool(authorities.get("extends_existing_ls3_chain", false)), "LS4.1 explicitly extends accepted LS3 chain")
    _check(not bool(authorities.get("direct_world_write", true)), "LS4.1 has no direct WORLD write")
    _check(not bool(authorities.get("interaction_graph_authority", true)), "LS4.2 interaction authority is absent")
    _check(not bool(authorities.get("shared_resource_authority", true)), "LS4.3 shared-resource authority is absent")

    # Accepted LS3 workbench remains independently executable: LS4.1 did not replace it.
    var legacy = LegacyWorkbench.new()
    _check(legacy.setup(world), "accepted LS3.6 workbench still initializes")
    var legacy_before := legacy.get_workbench_snapshot()
    _check(not legacy_before.is_empty() and int(legacy_before.get("generation", -1)) == 0, "accepted LS3.6 starts unchanged")
    var legacy_after := legacy.advance_generations(1)
    _check(not legacy_after.is_empty() and int(legacy_after.get("generation", -1)) == 1, "accepted LS3.6 still advances independently")

    if failures.is_empty():
        print("ECO.EVO7 LS4.1 Multi-Species: PASS (%d assertions)" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("LS4.1 FAIL: %s" % failure)
        print("ECO.EVO7 LS4.1 Multi-Species: FAIL (%d/%d failed)" % [failures.size(), assertions])
        quit(1)

func _check(condition: bool, label: String) -> void:
    assertions += 1
    if not condition:
        failures.append(label)
