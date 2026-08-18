extends SceneTree

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const DivergenceDiagnostics = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")
const BakeExport = preload("res://scripts/research/ecology/plant_evolution_bake_export_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const Transfer = preload("res://scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd")

const FINAL_YEAR := 12
const SOURCE_RUN_HASH := "d44a160531d7f49cd0d0018a1fa8cb55d6be8ebf8157e5cb555232b8dd0fb337"
const YEARS := 30
const REACHABLE_PATCH := "target/e23-reachable"
const ISOLATED_PATCH := "target/e23-isolated"

var assertions := 0
var failed := false

func _init() -> void:
	var bake := _accepted_e2_2_bake()
	_check(not bake.is_empty(), "accepted E2.2 bake fixture builds")
	_check(BakeExport.validate_export(bake), "accepted E2.2 bake fixture validates")
	_check(String(bake.get("bake_hash", "")) == Transfer.ACCEPTED_E2_2_BAKE_HASH, "exact accepted E2.2 bake hash pinned")
	_check(String(bake.get("catalog_hash", "")) == Transfer.ACCEPTED_E2_2_CATALOG_HASH, "exact accepted E2.2 catalog hash pinned")

	var hidden_environment := EnvironmentSample.create(230.0, -45.0, 18.0, 0.52, 0.95, 0.85, 0.02, 2303002, "eco-evo2-e2-3-hidden-target")
	_check(bool(EnvironmentSample.validate(hidden_environment).get("success", false)), "hidden target environment validates")
	var reachable_patch := PatchMigration.create_patch(REACHABLE_PATCH, Rect2(1.01, -80.0, 100.0, 160.0), hidden_environment)
	var isolated_patch := PatchMigration.create_patch(ISOLATED_PATCH, Rect2(500.0, -80.0, 100.0, 160.0), hidden_environment)
	_check(not reachable_patch.is_empty() and not isolated_patch.is_empty(), "reachable and isolated target patches build")

	var schedule := [
		{"year_start": 1, "transport_vector": Vector2(1.0, 0.0), "turbulence": 0.20},
		{"year_start": 15, "transport_vector": Vector2(-1.0, 0.0), "turbulence": 0.20},
		{"year_start": 19, "transport_vector": Vector2(1.0, 0.0), "turbulence": 0.20},
	]
	var reversed_schedule := schedule.duplicate(true)
	reversed_schedule.reverse()
	var target_reachable := Transfer.create_target("E2.3/TARGET_REACHABLE", [reachable_patch], YEARS, schedule)
	var target_reachable_reordered := Transfer.create_target("E2.3/TARGET_REACHABLE", [reachable_patch], YEARS, reversed_schedule)
	var target_isolated := Transfer.create_target("E2.3/TARGET_UNREACHABLE", [isolated_patch], YEARS, schedule)
	_check(not target_reachable.is_empty() and not target_isolated.is_empty(), "paired E2.3 targets build")
	_check(Transfer.validate_target(target_reachable) and Transfer.validate_target(target_isolated), "paired targets validate")
	_check(target_reachable == target_reachable_reordered, "transport schedule input order canonicalizes")
	_check(String(Dictionary(reachable_patch["environment"])["checksum"]) == String(Dictionary(isolated_patch["environment"])["checksum"]), "reachable and isolated controls share exact suitability")
	_check(String(target_reachable["target_hash"]) != String(target_isolated["target_hash"]), "target identity includes geography despite equal environment")

	var bake_before := bake.duplicate(true)
	var reachable_before := target_reachable.duplicate(true)
	var result_reachable := Transfer.transfer(bake, target_reachable)
	_check(not result_reachable.is_empty(), "reachable frozen-catalog transfer executes")
	_check(Transfer.validate_result(bake, target_reachable, result_reachable), "reachable transfer independently replays and validates")
	_check(bake == bake_before, "transfer does not mutate frozen E2.2 bake/catalog")
	_check(target_reachable == reachable_before, "transfer does not mutate target input")
	_check(String(result_reachable["parent_e2_2_accepted_aggregate"]) == Transfer.PARENT_E2_2_ACCEPTED_AGGREGATE, "accepted E2.2 aggregate pinned")
	_check(String(result_reachable["e2_2_bake_hash"]) == Transfer.ACCEPTED_E2_2_BAKE_HASH, "result carries exact frozen bake hash")
	_check(String(result_reachable["catalog_hash"]) == Transfer.ACCEPTED_E2_2_CATALOG_HASH, "result carries exact frozen catalog hash")
	_check(not bool(result_reachable["evolution_enabled"]), "evolution is hard-disabled in transfer truth")
	_check(not bool(result_reachable["canonical_species_declared"]), "transfer does not promote canonical taxonomy")
	_check(not bool(result_reachable["production_authority_claimed"]), "transfer remains research-only")
	_check(Array(result_reachable["initial_inoculum"]).size() == Array(Dictionary(bake["species_catalog"])["entries"]).size(), "all frozen catalog entries seed the source port without target-aware filtering")
	_check(_inoculum_species_ids(result_reachable) == _catalog_species_ids(bake), "initial inoculum species set exactly equals frozen catalog")
	_check(_target_starts_empty(result_reachable, REACHABLE_PATCH), "suitable target starts with zero population and zero seed bank")
	_check(String(result_reachable["colonization_status"]) == "COLONIZED", "reachable hidden target colonizes causally")
	_check(int(result_reachable["first_colonization_year"]) > 0 and int(result_reachable["first_colonization_year"]) <= YEARS, "reachable colonization occurs after transfer begins")
	_check(_has_event(result_reachable, REACHABLE_PATCH, "RECRUITMENT_COLONIZATION"), "successful establishment is exposed as recruitment/colonization event")
	_check(_target_event_species_are_catalog_species(result_reachable, bake), "target events use frozen research_species_id identities only")
	_check(_target_ever_has_adult(result_reachable, REACHABLE_PATCH), "reachable target develops adult population")
	_check(_competition_changes_composition(result_reachable, REACHABLE_PATCH), "shared-resource competition can alter composition after co-establishment")
	_check(String(result_reachable["final_population_state_hash"]).length() == 64, "reachable final population state hash shape")
	_check(String(result_reachable["result_hash"]).length() == 64, "reachable transfer result hash shape")
	_check(Array(result_reachable["history"]).size() == YEARS + 1, "reachable yearly history complete")

	var repeat_reachable := Transfer.transfer(bake, target_reachable)
	_check(repeat_reachable == result_reachable, "same-process frozen transfer is exact deterministic")
	_check(String(repeat_reachable["result_hash"]) == String(result_reachable["result_hash"]), "same-process result hash stable")

	seed(23032303)
	var rng_expected := [randi(), randi(), randi(), randi()]
	seed(23032303)
	Transfer.transfer(bake, target_reachable)
	var rng_actual := [randi(), randi(), randi(), randi()]
	_check(rng_actual == rng_expected, "frozen transfer consumes no global RNG")

	var isolated_before := target_isolated.duplicate(true)
	var result_isolated := Transfer.transfer(bake, target_isolated)
	_check(not result_isolated.is_empty(), "unreachable target is a valid executed transfer")
	_check(Transfer.validate_result(bake, target_isolated, result_isolated), "unreachable transfer validates")
	_check(target_isolated == isolated_before, "unreachable target input remains immutable")
	_check(String(result_isolated["colonization_status"]) == "VALID_NO_COLONIZATION", "explicit no-colonization is valid semantics, not an error")
	_check(int(result_isolated["first_colonization_year"]) == -1, "unreachable target has no fabricated colonization year")
	_check(not _target_ever_has_adult(result_isolated, ISOLATED_PATCH), "equal-suitability isolated target never gets adult population")
	_check(_all_target_seed_banks_zero(result_isolated, ISOLATED_PATCH), "unreachable target receives no hidden scatter/seed placement")
	_check(String(result_isolated["final_population_state_hash"]).length() == 64, "no-colonization final state still hashes canonically")
	_check(String(result_reachable["result_hash"]) != String(result_isolated["result_hash"]), "reachability changes causal transfer outcome at equal suitability")

	var tampered_target := target_reachable.duplicate(true)
	tampered_target["target_hash"] = "0".repeat(64)
	_check(not Transfer.validate_target(tampered_target), "target hash tamper fails closed")
	_check(Transfer.transfer(bake, tampered_target).is_empty(), "tampered target cannot execute")

	var observed_id_patch := PatchMigration.create_patch("patch/alpha", Rect2(650.0, -80.0, 100.0, 160.0), hidden_environment)
	var observed_id_target := Transfer.create_target("E2.3/OBSERVED_PATCH_ATTACK", [observed_id_patch], 5, [schedule[0]])
	_check(not observed_id_target.is_empty(), "observed-patch attack target is structurally valid")
	_check(Transfer.transfer(bake, observed_id_target).is_empty(), "target patch already present in bake evidence is rejected")

	var source_environment := _first_bake_environment(bake)
	var reused_env_patch := PatchMigration.create_patch("target/e23-reused-environment", Rect2(800.0, -80.0, 100.0, 160.0), source_environment)
	var reused_env_target := Transfer.create_target("E2.3/OBSERVED_ENV_ATTACK", [reused_env_patch], 5, [schedule[0]])
	_check(not reused_env_target.is_empty(), "observed-environment attack target is structurally valid")
	_check(Transfer.transfer(bake, reused_env_target).is_empty(), "exact environment checksum present during bake is rejected as non-hidden target")

	var tampered_bake := bake.duplicate(true)
	tampered_bake["bake_hash"] = "0".repeat(64)
	_check(Transfer.transfer(tampered_bake, target_reachable).is_empty(), "tampered E2.2 bake cannot transfer")
	var altered_catalog_bake := bake.duplicate(true)
	var altered_catalog: Dictionary = Dictionary(altered_catalog_bake["species_catalog"]).duplicate(true)
	altered_catalog["catalog_hash"] = "0".repeat(64)
	altered_catalog_bake["species_catalog"] = altered_catalog
	_check(Transfer.transfer(altered_catalog_bake, target_reachable).is_empty(), "altered frozen catalog cannot transfer")

	var tampered_result := result_reachable.duplicate(true)
	tampered_result["colonization_status"] = "VALID_NO_COLONIZATION"
	tampered_result["result_hash"] = Transfer.compute_result_hash(tampered_result)
	_check(not Transfer.validate_result(bake, target_reachable, tampered_result), "rehashed result tamper rejected by independent deterministic replay")

	var transfer_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd")
	_check(transfer_source.find("plant_mutation") == -1 and transfer_source.find("mutation_kernel") == -1, "transfer has no mutation/evolution kernel path")
	_check(transfer_source.find("biome") == -1 and transfer_source.find("species_table") == -1, "transfer has no biome-to-species placement table")
	_check(transfer_source.find("static func transfer(bake_export: Dictionary, target: Dictionary)") >= 0, "transfer API exposes no target species list or mutation callback")
	_check(transfer_source.find("Biogeography.simulate") >= 0, "accepted P2.6 biogeography solver reused directly")
	_check(transfer_source.find("const EVOLUTION_ENABLED := false") >= 0, "hard freeze is explicit in executable source")

	var aggregate_hash := "\n".join(PackedStringArray([
		String(bake["bake_hash"]), String(bake["catalog_hash"]), String(target_reachable["target_hash"]),
		String(result_reachable["result_hash"]), String(target_isolated["target_hash"]), String(result_isolated["result_hash"]),
	])).sha256_text()
	if failed:
		quit(1)
		return
	print("ECO.EVO2 E2.3 Frozen-Catalog Transfer: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("parent_e2_2=" + Transfer.PARENT_E2_2_ACCEPTED_AGGREGATE)
	print("bake_hash=" + String(bake["bake_hash"]))
	print("catalog_hash=" + String(bake["catalog_hash"]))
	print("reachable_target_hash=" + String(target_reachable["target_hash"]))
	print("reachable_result_hash=" + String(result_reachable["result_hash"]))
	print("reachable_final_state_hash=" + String(result_reachable["final_population_state_hash"]))
	print("reachable_first_colonization_year=" + str(int(result_reachable["first_colonization_year"])))
	print("isolated_target_hash=" + String(target_isolated["target_hash"]))
	print("isolated_result_hash=" + String(result_isolated["result_hash"]))
	print("isolated_final_state_hash=" + String(result_isolated["final_population_state_hash"]))
	print("isolated_status=" + String(result_isolated["colonization_status"]))
	quit(0)

func _accepted_e2_2_bake() -> Dictionary:
	var genome_alpha_early := PlantGenome.create("genome/e22-alpha-early", 1.2, 0.48, 1.4, 0.38, 0.22, 0.62, 140, 14.0, 8.0)
	var genome_alpha_late := PlantGenome.create("genome/e22-alpha-late", 1.5, 0.54, 1.7, 0.34, 0.25, 0.65, 130, 16.0, 8.5)
	var genome_beta := PlantGenome.create("genome/e22-beta", 0.8, 0.72, 0.6, 0.70, 0.28, 0.28, 360, 28.0, 3.0)
	var genome_other := PlantGenome.create("genome/e22-other", 2.3, 0.60, 2.2, 0.50, 0.32, 0.48, 180, 20.0, 10.0)
	var traits_alpha := RecruitmentTraits.create("recruit/e22-alpha", 0.38, 4.5)
	var traits_beta := RecruitmentTraits.create("recruit/e22-beta", 0.18, 1.8)
	var traits_other := RecruitmentTraits.create("recruit/e22-other", 0.30, 3.0)
	var alpha_early := _observation("eco-lineage/e22-alpha", ["eco-lineage/e22-root", "eco-lineage/e22-alpha"], 2, 8, genome_alpha_early, traits_alpha, "patch/alpha")
	var alpha_late := _observation("eco-lineage/e22-alpha", ["eco-lineage/e22-root", "eco-lineage/e22-alpha"], 2, 12, genome_alpha_late, traits_alpha, "patch/alpha")
	var beta := _observation("eco-lineage/e22-beta", ["eco-lineage/e22-root", "eco-lineage/e22-beta"], 1, 12, genome_beta, traits_beta, "patch/beta")
	var extinct := _observation("eco-lineage/e22-extinct", ["eco-lineage/e22-root", "eco-lineage/e22-extinct"], 1, 12, genome_other, traits_other, "patch/extinct")
	var transient := _observation("eco-lineage/e22-transient", ["eco-lineage/e22-root", "eco-lineage/e22-transient"], 1, 12, genome_other, traits_other, "patch/transient")
	var recent := _observation("eco-lineage/e22-recent", ["eco-lineage/e22-root", "eco-lineage/e22-recent"], 8, 12, genome_other, traits_other, "patch/recent")
	var stale := _observation("eco-lineage/e22-stale", ["eco-lineage/e22-root", "eco-lineage/e22-stale"], 1, 9, genome_other, traits_other, "patch/stale")
	var lineages := [
		_lineage("eco-lineage/e22-alpha", [alpha_late, alpha_early], [1, 2, 2, 2, 3, 3, 3, 4]),
		_lineage("eco-lineage/e22-beta", [beta], [0, 1, 1, 1, 1, 2, 2, 2]),
		_lineage("eco-lineage/e22-extinct", [extinct], [1, 1, 1, 1, 1, 1, 1, 0]),
		_lineage("eco-lineage/e22-transient", [transient], [0, 0, 0, 1, 0, 1, 1, 1]),
		_lineage("eco-lineage/e22-recent", [recent], [0, 0, 0, 0, 1, 1, 1, 1]),
		_lineage("eco-lineage/e22-stale", [stale], [1, 1, 1, 1, 1, 1, 1, 1]),
	]
	var source := BakeExport.create_source(lineages, FINAL_YEAR, SOURCE_RUN_HASH)
	return BakeExport.export_catalog(source) if not source.is_empty() else {}

func _lineage(lineage_id: String, observations: Array, window_counts: Array) -> Dictionary:
	var history: Array = []
	var start_year := FINAL_YEAR - BakeExport.WINDOW_YEARS + 1
	for index in range(window_counts.size()): history.append({"year": start_year + index, "occupied_patch_count": int(window_counts[index])})
	return {"lineage_id": lineage_id, "observations": observations.duplicate(true), "occupancy_history": history}

func _observation(lineage_id: String, ancestry: Array, split_year: int, end_year: int, genome: Dictionary, traits: Dictionary, patch_id: String) -> Dictionary:
	var geography: Array = []; var ecology: Array = []
	for year in range(split_year + 1, end_year + 1):
		geography.append({"year": year, "patch_ids": [patch_id]})
		var environment := EnvironmentSample.create(float(year), float(-year), 10.0 + float(year) * 0.2, 0.45, 0.75, 0.62, 0.02, 22000 + year, "e22-fixture")
		ecology.append({"year": year, "environment": environment})
	return DivergenceDiagnostics.create_observation(lineage_id, ancestry, split_year, genome, traits, geography, ecology)

func _first_bake_environment(bake: Dictionary) -> Dictionary:
	var source: Dictionary = bake["source"]
	var lineage: Dictionary = Array(source["lineages"])[0]
	var observation: Dictionary = Array(lineage["observations"])[0]
	var ecology: Dictionary = Array(observation["ecology_history"])[0]
	return Dictionary(ecology["environment"]).duplicate(true)

func _inoculum_species_ids(result: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for value in Array(result.get("initial_inoculum", [])): ids.append(String(Dictionary(value).get("research_species_id", "")))
	ids.sort(); return ids

func _catalog_species_ids(bake: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for value in Array(Dictionary(bake["species_catalog"])["entries"]): ids.append(String(Dictionary(value).get("research_species_id", "")))
	ids.sort(); return ids

func _target_starts_empty(result: Dictionary, patch_id: String) -> bool:
	var history: Array = result.get("history", [])
	if history.is_empty() or int(Dictionary(history[0]).get("year", -1)) != 0: return false
	var patch := _history_patch(Dictionary(history[0]), patch_id)
	return not patch.is_empty() and float(patch.get("total_adult_biomass_kg_m2", -1.0)) == 0.0 and int(patch.get("total_seed_bank_seed_count", -1)) == 0

func _target_ever_has_adult(result: Dictionary, patch_id: String) -> bool:
	for value in Array(result.get("history", [])):
		var patch := _history_patch(Dictionary(value), patch_id)
		if not patch.is_empty() and float(patch.get("total_adult_biomass_kg_m2", 0.0)) > 0.000001: return true
	return false

func _all_target_seed_banks_zero(result: Dictionary, patch_id: String) -> bool:
	for value in Array(result.get("history", [])):
		var patch := _history_patch(Dictionary(value), patch_id)
		if patch.is_empty() or int(patch.get("total_seed_bank_seed_count", 0)) != 0: return false
	return true

func _competition_changes_composition(result: Dictionary, patch_id: String) -> bool:
	var first_ratio := -1.0
	for value in Array(result.get("history", [])):
		var patch := _history_patch(Dictionary(value), patch_id)
		if patch.is_empty() or int(patch.get("occupied_species_count", 0)) < 2: continue
		var positive: Array[float] = []
		for species_value in Array(patch.get("adult_biomass_by_lineage", {}).keys()):
			var biomass := float(Dictionary(patch.get("adult_biomass_by_lineage", {})).get(species_value, 0.0))
			if biomass > 0.000001: positive.append(biomass)
		if positive.size() < 2: continue
		var ratio := positive[0] / maxf(positive[1], 0.000000001)
		if first_ratio < 0.0: first_ratio = ratio
		elif absf(ratio - first_ratio) > 0.000001: return true
	return false

func _history_patch(history: Dictionary, patch_id: String) -> Dictionary:
	for value in Array(history.get("patch_summaries", [])):
		var patch: Dictionary = value
		if String(patch.get("patch_id", "")) == patch_id: return patch
	return {}

func _has_event(result: Dictionary, patch_id: String, event_type: String) -> bool:
	for value in Array(result.get("population_events", [])):
		var event: Dictionary = value
		if String(event.get("patch_id", "")) == patch_id and String(event.get("event_type", "")) == event_type: return true
	return false

func _target_event_species_are_catalog_species(result: Dictionary, bake: Dictionary) -> bool:
	var ids := _catalog_species_ids(bake)
	for value in Array(result.get("population_events", [])):
		if not String(Dictionary(value).get("research_species_id", "")) in ids: return false
	return true

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition: return
	failed = true
	push_error("ECO.EVO2 E2.3 assertion failed: " + label)
