extends SceneTree

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const DivergenceDiagnostics = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")
const SpeciesCatalog = preload("res://scripts/research/ecology/plant_species_catalog_v1.gd")
const BakeExport = preload("res://scripts/research/ecology/plant_evolution_bake_export_v1.gd")

const FINAL_YEAR := 12
const SOURCE_RUN_HASH := "d44a160531d7f49cd0d0018a1fa8cb55d6be8ebf8157e5cb555232b8dd0fb337"

var assertions := 0
var failed := false


func _init() -> void:
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
	for observation in [alpha_early, alpha_late, beta, extinct, transient, recent, stale]:
		_check(not Dictionary(observation).is_empty(), "fixture observation builds")
		_check(DivergenceDiagnostics.validate_observation(observation), "fixture observation validates through P2.7")

	var lineages := [
		_lineage("eco-lineage/e22-alpha", [alpha_late, alpha_early], [1, 2, 2, 2, 3, 3, 3, 4]),
		_lineage("eco-lineage/e22-beta", [beta], [0, 1, 1, 1, 1, 2, 2, 2]),
		_lineage("eco-lineage/e22-extinct", [extinct], [1, 1, 1, 1, 1, 1, 1, 0]),
		_lineage("eco-lineage/e22-transient", [transient], [0, 0, 0, 1, 0, 1, 1, 1]),
		_lineage("eco-lineage/e22-recent", [recent], [0, 0, 0, 0, 1, 1, 1, 1]),
		_lineage("eco-lineage/e22-stale", [stale], [1, 1, 1, 1, 1, 1, 1, 1]),
	]
	var reverse_lineages := lineages.duplicate(true)
	reverse_lineages.reverse()
	var source_before := lineages.duplicate(true)

	var source := BakeExport.create_source(lineages, FINAL_YEAR, SOURCE_RUN_HASH)
	var source_reversed := BakeExport.create_source(reverse_lineages, FINAL_YEAR, SOURCE_RUN_HASH)
	_check(not source.is_empty(), "canonical bake source builds")
	_check(BakeExport.validate_source(source), "canonical bake source validates")
	_check(source == source_reversed, "source is lineage-input-order independent")
	_check(String(source["source_hash"]) == String(source_reversed["source_hash"]), "source hash is lineage-input-order independent")
	_check(lineages == source_before, "source construction does not mutate caller lineage histories")
	_check(String(source["parent_p2_8_accepted_aggregate"]) == BakeExport.PARENT_P2_8_ACCEPTED_AGGREGATE, "accepted P2.8 parent is pinned")

	var export_a := BakeExport.export_catalog(source)
	var export_b := BakeExport.export_catalog(source_reversed)
	_check(not export_a.is_empty(), "bake export produces a catalog")
	_check(BakeExport.validate_export(export_a), "bake export validates")
	_check(export_a == export_b, "bake export is input-order independent")
	_check(String(export_a["bake_hash"]) == String(export_b["bake_hash"]), "bake hash is input-order independent")
	_check(String(export_a["parent_e2_1_accepted_aggregate"]) == BakeExport.PARENT_E2_1_ACCEPTED_AGGREGATE, "accepted E2.1 parent is pinned")
	_check(String(export_a["parent_p2_8_accepted_aggregate"]) == BakeExport.PARENT_P2_8_ACCEPTED_AGGREGATE, "bake preserves P2.8 parent")
	_check(String(export_a["source_run_hash"]) == SOURCE_RUN_HASH, "exact source run provenance is preserved")
	_check(Dictionary(export_a["source"]) == source, "bake embeds the exact validated source evidence")
	_check(String(export_a["bake_id"]).begins_with("eco-evo2-bake/"), "bake id uses explicit deterministic research namespace")

	var selected: Array = export_a["selected_lineages"]
	var rejected: Array = export_a["rejected_lineages"]
	_check(selected.size() == 2, "exactly two persistent lineages are retained")
	_check(rejected.size() == 4, "four non-portable lineages are explicitly rejected")
	_check(String(selected[0]["lineage_id"]) == "eco-lineage/e22-alpha", "selected lineages are canonical-sorted")
	_check(String(selected[1]["lineage_id"]) == "eco-lineage/e22-beta", "second retained lineage is beta")
	_check(int(selected[0]["representative_year"]) == FINAL_YEAR, "latest alpha observation is selected deterministically")
	_check(String(selected[0]["representative_observation_hash"]) == String(alpha_late["observation_hash"]), "alpha representative is latest exact observation")
	_check(String(selected[0]["research_species_id"]) == SpeciesCatalog.research_species_id("eco-lineage/e22-alpha"), "retained alpha maps through E2.1 stable species identity")
	_check(int(selected[1]["occupied_years_in_window"]) == 7, "beta persistence threshold is measured explicitly")
	_check(_reason(rejected, "eco-lineage/e22-extinct") == "EXTINCT_AT_FINAL", "final extinction is rejected explicitly")
	_check(_reason(rejected, "eco-lineage/e22-transient") == "TRANSIENT_PERSISTENCE", "transient lineage is rejected explicitly")
	_check(_reason(rejected, "eco-lineage/e22-recent") == "RECENT_LINEAGE", "recent lineage is rejected explicitly")
	_check(_reason(rejected, "eco-lineage/e22-stale") == "STALE_REPRESENTATIVE", "stale representative is rejected explicitly")

	var catalog: Dictionary = export_a["species_catalog"]
	_check(SpeciesCatalog.validate_catalog(catalog), "exported SpeciesCatalog passes accepted E2.1 validation")
	_check(Array(catalog["entries"]).size() == selected.size(), "catalog contains exactly retained lineages")
	_check(String(catalog["source_run_hash"]) == SOURCE_RUN_HASH, "catalog carries exact evolution source run hash")
	_check(String(catalog["bake_id"]) == String(export_a["bake_id"]), "catalog and bake share deterministic bake id")
	_check(not bool(catalog["canonical_species_declared"]), "bake cannot promote research identities to canonical species")

	seed(24681357)
	var rng_expected := [randi(), randi(), randi(), randi()]
	seed(24681357)
	BakeExport.export_catalog(source)
	var rng_actual := [randi(), randi(), randi(), randi()]
	_check(rng_actual == rng_expected, "bake export consumes no global RNG")

	var tampered_source := source.duplicate(true)
	tampered_source["source_hash"] = "0".repeat(64)
	_check(not BakeExport.validate_source(tampered_source), "source hash tamper is rejected")
	tampered_source = source.duplicate(true)
	tampered_source["unexpected"] = true
	_check(not BakeExport.validate_source(tampered_source), "unexpected source field is rejected")
	tampered_source = source.duplicate(true)
	var tampered_lineages: Array = Array(tampered_source["lineages"]).duplicate(true)
	var first_lineage: Dictionary = Dictionary(tampered_lineages[0]).duplicate(true)
	first_lineage["lineage_hash"] = "0".repeat(64)
	tampered_lineages[0] = first_lineage
	tampered_source["lineages"] = tampered_lineages
	tampered_source["source_hash"] = BakeExport.compute_source_hash(tampered_source)
	_check(not BakeExport.validate_source(tampered_source), "lineage hash tamper is rejected even with recomputed source hash")

	var duplicate_lineages := lineages.duplicate(true)
	duplicate_lineages.append(lineages[0].duplicate(true))
	_check(BakeExport.create_source(duplicate_lineages, FINAL_YEAR, SOURCE_RUN_HASH).is_empty(), "duplicate lineage is rejected")
	var duplicate_year_lineages := lineages.duplicate(true)
	var duplicate_year_record: Dictionary = Dictionary(duplicate_year_lineages[0]).duplicate(true)
	var duplicate_history: Array = Array(duplicate_year_record["occupancy_history"]).duplicate(true)
	duplicate_history.append(duplicate_history[0].duplicate(true))
	duplicate_year_record["occupancy_history"] = duplicate_history
	duplicate_year_lineages[0] = duplicate_year_record
	_check(BakeExport.create_source(duplicate_year_lineages, FINAL_YEAR, SOURCE_RUN_HASH).is_empty(), "duplicate occupancy year is rejected")

	var missing_window_lineages := lineages.duplicate(true)
	var missing_record: Dictionary = Dictionary(missing_window_lineages[0]).duplicate(true)
	var missing_history: Array = Array(missing_record["occupancy_history"]).duplicate(true)
	missing_history.remove_at(0)
	missing_record["occupancy_history"] = missing_history
	missing_window_lineages[0] = missing_record
	_check(BakeExport.create_source(missing_window_lineages, FINAL_YEAR, SOURCE_RUN_HASH).is_empty(), "incomplete trailing persistence window is rejected")
	_check(BakeExport.create_source(lineages, FINAL_YEAR, "bad").is_empty(), "malformed source-run provenance is rejected")

	var ambiguous_lineages := lineages.duplicate(true)
	var ambiguous_record: Dictionary = Dictionary(ambiguous_lineages[0]).duplicate(true)
	var ambiguous_observations: Array = Array(ambiguous_record["observations"]).duplicate(true)
	var alpha_same_year_other := _observation("eco-lineage/e22-alpha", ["eco-lineage/e22-root", "eco-lineage/e22-alpha"], 2, 12, genome_alpha_early, traits_alpha, "patch/alpha")
	_check(String(alpha_same_year_other["observation_hash"]) != String(alpha_late["observation_hash"]), "ambiguous fixture has distinct hash at same observation year")
	ambiguous_observations.append(alpha_same_year_other)
	ambiguous_record["observations"] = ambiguous_observations
	ambiguous_lineages[0] = ambiguous_record
	_check(BakeExport.create_source(ambiguous_lineages, FINAL_YEAR, SOURCE_RUN_HASH).is_empty(), "ambiguous same-year representative observations fail closed")

	var all_rejected := [
		_lineage("eco-lineage/e22-only-recent", [_observation("eco-lineage/e22-only-recent", ["eco-lineage/e22-root", "eco-lineage/e22-only-recent"], 9, 12, genome_other, traits_other, "patch/recent")], [0, 0, 0, 0, 0, 1, 1, 1]),
	]
	var all_rejected_source := BakeExport.create_source(all_rejected, FINAL_YEAR, SOURCE_RUN_HASH)
	_check(not all_rejected_source.is_empty(), "all-rejected source is structurally valid")
	_check(BakeExport.export_catalog(all_rejected_source).is_empty(), "bake fails closed when no lineage satisfies portability policy")

	var tampered_export := export_a.duplicate(true)
	tampered_export["bake_hash"] = "0".repeat(64)
	_check(not BakeExport.validate_export(tampered_export), "bake hash tamper is rejected")
	tampered_export = export_a.duplicate(true)
	var altered_selected: Array = Array(tampered_export["selected_lineages"]).duplicate(true)
	var altered_selection: Dictionary = Dictionary(altered_selected[0]).duplicate(true)
	altered_selection["final_occupied_patch_count"] = int(altered_selection["final_occupied_patch_count"]) + 1
	altered_selection["selection_hash"] = _selection_hash_fixture(altered_selection)
	altered_selected[0] = altered_selection
	tampered_export["selected_lineages"] = altered_selected
	tampered_export["bake_hash"] = BakeExport.compute_bake_hash(tampered_export)
	_check(not BakeExport.validate_export(tampered_export), "selection policy tamper is rejected even with recomputed selection and bake hashes")
	tampered_export = export_a.duplicate(true)
	var embedded_source: Dictionary = Dictionary(tampered_export["source"]).duplicate(true)
	var embedded_lineages: Array = Array(embedded_source["lineages"]).duplicate(true)
	var embedded_alpha: Dictionary = Dictionary(embedded_lineages[0]).duplicate(true)
	var embedded_occupancy: Array = Array(embedded_alpha["occupancy_history"]).duplicate(true)
	embedded_occupancy[embedded_occupancy.size() - 1] = {"year": FINAL_YEAR, "occupied_patch_count": 0}
	embedded_alpha["occupancy_history"] = embedded_occupancy
	embedded_lineages[0] = embedded_alpha
	embedded_source["lineages"] = embedded_lineages
	tampered_export["source"] = embedded_source
	_check(not BakeExport.validate_export(tampered_export), "embedded source evidence tamper is rejected before policy claims can be trusted")
	tampered_export = export_a.duplicate(true)
	var altered_catalog: Dictionary = Dictionary(tampered_export["species_catalog"]).duplicate(true)
	altered_catalog["canonical_species_declared"] = true
	altered_catalog["catalog_hash"] = SpeciesCatalog.compute_catalog_hash(altered_catalog)
	tampered_export["species_catalog"] = altered_catalog
	tampered_export["catalog_hash"] = String(altered_catalog["catalog_hash"])
	tampered_export["bake_hash"] = BakeExport.compute_bake_hash(tampered_export)
	_check(not BakeExport.validate_export(tampered_export), "canonical taxonomy promotion is rejected at bake validation boundary")

	var aggregate_hash := "\n".join(PackedStringArray([
		String(source["source_hash"]),
		String(export_a["bake_hash"]),
		String(export_a["catalog_hash"]),
		String(selected[0]["research_species_id"]),
		String(selected[1]["research_species_id"]),
	])).sha256_text()

	if failed:
		quit(1)
		return
	print("ECO.EVO2 E2.2 Deterministic Evolution Bake Export: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("source_hash=" + String(source["source_hash"]))
	print("bake_hash=" + String(export_a["bake_hash"]))
	print("catalog_hash=" + String(export_a["catalog_hash"]))
	print("selected_count=" + str(selected.size()))
	print("rejected_count=" + str(rejected.size()))
	print("parent_e2_1=" + BakeExport.PARENT_E2_1_ACCEPTED_AGGREGATE)
	print("parent_p2_8=" + BakeExport.PARENT_P2_8_ACCEPTED_AGGREGATE)
	quit(0)


func _lineage(lineage_id: String, observations: Array, window_counts: Array) -> Dictionary:
	var history: Array = []
	var start_year := FINAL_YEAR - BakeExport.WINDOW_YEARS + 1
	for index in range(window_counts.size()):
		history.append({"year": start_year + index, "occupied_patch_count": int(window_counts[index])})
	return {"lineage_id": lineage_id, "observations": observations.duplicate(true), "occupancy_history": history}


func _observation(lineage_id: String, ancestry: Array, split_year: int, end_year: int, genome: Dictionary, traits: Dictionary, patch_id: String) -> Dictionary:
	var geography: Array = []
	var ecology: Array = []
	for year in range(split_year + 1, end_year + 1):
		geography.append({"year": year, "patch_ids": [patch_id]})
		var environment := EnvironmentSample.create(float(year), float(-year), 10.0 + float(year) * 0.2, 0.45, 0.75, 0.62, 0.02, 22000 + year, "e22-fixture")
		ecology.append({"year": year, "environment": environment})
	return DivergenceDiagnostics.create_observation(lineage_id, ancestry, split_year, genome, traits, geography, ecology)


func _reason(rejected: Array, lineage_id: String) -> String:
	for value in rejected:
		var record: Dictionary = value
		if String(record.get("lineage_id", "")) == lineage_id:
			return String(record.get("reason", ""))
	return ""


func _selection_hash_fixture(selection: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		String(selection.get("lineage_id", "")),
		String(selection.get("representative_observation_hash", "")),
		str(int(selection.get("representative_year", -1))),
		str(int(selection.get("occupied_years_in_window", -1))),
		str(int(selection.get("final_occupied_patch_count", -1))),
		String(selection.get("research_species_id", "")),
	])).sha256_text()


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.EVO2 E2.2 assertion failed: " + label)
