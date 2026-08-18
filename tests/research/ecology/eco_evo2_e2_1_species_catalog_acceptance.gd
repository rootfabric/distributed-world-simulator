extends SceneTree

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const DivergenceDiagnostics = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")
const SpeciesCatalog = preload("res://scripts/research/ecology/plant_species_catalog_v1.gd")

# Synthetic provenance digest used only by this contract fixture. It intentionally
# does not impersonate an accepted ecology result hash.
const SOURCE_RUN_HASH := "f4a2c4df81414b8b527c572454da622fbd730858a85e5bfe8f5f2eaa05418914"
const BAKE_ID := "evo2-e2-1-contract-fixture"

var assertions := 0
var failed := false


func _init() -> void:
	var genome_a := PlantGenome.create("genome/e2-alpha", 1.8, 0.62, 1.1, 0.36, 0.24, 0.55, 120, 18.0, 6.0)
	var genome_b := PlantGenome.create("genome/e2-beta", 0.7, 0.82, 0.45, 0.72, 0.30, 0.20, 400, 31.0, 2.5)
	var genome_a_later := PlantGenome.create("genome/e2-alpha-later", 2.0, 0.58, 1.25, 0.34, 0.26, 0.60, 105, 20.0, 6.5)
	var traits_a := RecruitmentTraits.create("recruitment/e2-alpha", 0.40, 4.0)
	var traits_b := RecruitmentTraits.create("recruitment/e2-beta", 0.15, 1.5)

	var observation_a := _observation(
		"eco-lineage/e2-alpha",
		["eco-lineage/e2-root", "eco-lineage/e2-alpha"],
		4,
		genome_a,
		traits_a,
		[["patch-b", "patch-a"], ["patch-a", "patch-c"], ["patch-c"]],
		0.34
	)
	var observation_b := _observation(
		"eco-lineage/e2-beta",
		["eco-lineage/e2-root", "eco-lineage/e2-beta"],
		4,
		genome_b,
		traits_b,
		[["patch-c"], ["patch-d"], ["patch-d", "patch-e"]],
		0.72
	)
	var observation_a_later := _observation(
		"eco-lineage/e2-alpha",
		["eco-lineage/e2-root", "eco-lineage/e2-alpha"],
		4,
		genome_a_later,
		traits_a,
		[["patch-a"], ["patch-a", "patch-c"], ["patch-c"]],
		0.31
	)

	_check(DivergenceDiagnostics.validate_observation(observation_a), "alpha source observation validates")
	_check(DivergenceDiagnostics.validate_observation(observation_b), "beta source observation validates")
	_check(DivergenceDiagnostics.validate_observation(observation_a_later), "later alpha source observation validates")

	var source_a_before := observation_a.duplicate(true)
	var source_b_before := observation_b.duplicate(true)

	var single := SpeciesCatalog.build([observation_a], BAKE_ID, SOURCE_RUN_HASH)
	_check(not single.is_empty(), "single-entry catalog builds")
	_check(SpeciesCatalog.validate_catalog(single), "single-entry catalog validates")
	_check(Array(single["entries"]).size() == 1, "single-entry catalog contains exactly one entry")
	var entry_a: Dictionary = Array(single["entries"])[0]
	_check(SpeciesCatalog.validate_entry(entry_a), "alpha entry validates")
	_check(String(entry_a["research_species_id"]).begins_with("eco-research-species/"), "research species id uses explicit research namespace")
	_check(String(entry_a["lineage_id"]) == "eco-lineage/e2-alpha", "lineage identity is preserved")
	_check(String(entry_a["parent_lineage_id"]) == "eco-lineage/e2-root", "immediate lineage parent is preserved")
	_check(Array(entry_a["ancestry_path"]) == ["eco-lineage/e2-root", "eco-lineage/e2-alpha"], "full ancestry is preserved")
	_check(Array(entry_a["observed_patch_ids"]) == ["patch-a", "patch-b", "patch-c"], "observed range prior is canonical sorted unique evidence")
	_check(String(entry_a["genome_checksum"]) == String(genome_a["checksum"]), "genome checksum is preserved")
	_check(String(entry_a["recruitment_traits_checksum"]) == String(traits_a["checksum"]), "recruitment trait checksum is preserved")
	_check(String(entry_a["source_observation_hash"]) == String(observation_a["observation_hash"]), "source observation evidence is preserved")
	_check(not bool(entry_a["canonical_species_declared"]), "entry explicitly refuses canonical species declaration")
	_check(not bool(single["canonical_species_declared"]), "catalog explicitly refuses canonical species declaration")
	_check(String(single["species_concept"]) == SpeciesCatalog.SPECIES_CONCEPT, "research species concept is explicit")
	_check(String(single["parent_p2_7_accepted_aggregate"]) == SpeciesCatalog.PARENT_P2_7_ACCEPTED_AGGREGATE, "accepted P2.7 parent identity is pinned")
	_check(String(single["source_run_hash"]) == SOURCE_RUN_HASH, "catalog preserves explicit source provenance digest")

	var multi_ab := SpeciesCatalog.build([observation_a, observation_b], BAKE_ID, SOURCE_RUN_HASH)
	var multi_ba := SpeciesCatalog.build([observation_b, observation_a], BAKE_ID, SOURCE_RUN_HASH)
	var multi_repeat := SpeciesCatalog.build([observation_a, observation_b], BAKE_ID, SOURCE_RUN_HASH)
	_check(SpeciesCatalog.validate_catalog(multi_ab), "multi-entry catalog validates")
	_check(multi_ab == multi_repeat, "same inputs rebuild byte-semantic-identically")
	_check(multi_ab == multi_ba, "catalog is input-order independent")
	_check(String(multi_ab["catalog_hash"]) == String(multi_ba["catalog_hash"]), "catalog hash is input-order independent")
	var ordered_entries: Array = multi_ab["entries"]
	var first_entry: Dictionary = ordered_entries[0]
	var second_entry: Dictionary = ordered_entries[1]
	_check(String(first_entry["research_species_id"]) < String(second_entry["research_species_id"]), "entries are in canonical species-id order")

	var alpha_later := SpeciesCatalog.build([observation_a_later], BAKE_ID, SOURCE_RUN_HASH)
	_check(SpeciesCatalog.validate_catalog(alpha_later), "later snapshot of same lineage validates")
	var later_entry: Dictionary = Array(alpha_later["entries"])[0]
	_check(String(later_entry["research_species_id"]) == String(entry_a["research_species_id"]), "same lineage keeps stable research species identity")
	_check(String(later_entry["entry_hash"]) != String(entry_a["entry_hash"]), "changed lineage snapshot changes entry evidence hash")
	_check(String(alpha_later["catalog_hash"]) != String(single["catalog_hash"]), "changed lineage snapshot changes catalog hash")

	var beta_entry := SpeciesCatalog.create_entry(observation_b)
	_check(SpeciesCatalog.validate_entry(beta_entry), "beta entry validates independently")
	_check(String(beta_entry["research_species_id"]) != String(entry_a["research_species_id"]), "distinct lineages receive distinct research species ids")
	_check(SpeciesCatalog.research_species_id("eco-lineage/e2-alpha") == String(entry_a["research_species_id"]), "identity function reproduces entry id")
	_check(SpeciesCatalog.research_species_id(" bad ").is_empty(), "non-canonical lineage id fails closed")

	_check(observation_a == source_a_before, "catalog build does not mutate alpha source observation")
	_check(observation_b == source_b_before, "catalog build does not mutate beta source observation")

	var malformed_observation := observation_a.duplicate(true)
	malformed_observation["observation_hash"] = "0".repeat(64)
	_check(SpeciesCatalog.build([malformed_observation], BAKE_ID, SOURCE_RUN_HASH).is_empty(), "tampered source observation fails closed")
	var extra_field_observation := observation_a.duplicate(true)
	extra_field_observation["unexpected"] = "hidden-source-state"
	_check(DivergenceDiagnostics.validate_observation(extra_field_observation), "P2.7 validator demonstrates legacy tolerance for an extra source field")
	_check(SpeciesCatalog.build([extra_field_observation], BAKE_ID, SOURCE_RUN_HASH).is_empty(), "E2.1 rejects extra source observation fields fail closed")
	var float_split_observation := observation_a.duplicate(true)
	float_split_observation["split_year"] = float(observation_a["split_year"])
	_check(DivergenceDiagnostics.validate_observation(float_split_observation), "P2.7 validator demonstrates legacy numeric Variant tolerance")
	_check(SpeciesCatalog.build([float_split_observation], BAKE_ID, SOURCE_RUN_HASH).is_empty(), "E2.1 rejects non-int split_year Variant fail closed")
	_check(SpeciesCatalog.build([observation_a, observation_a], BAKE_ID, SOURCE_RUN_HASH).is_empty(), "duplicate lineage fails closed")
	_check(SpeciesCatalog.build([], BAKE_ID, SOURCE_RUN_HASH).is_empty(), "empty catalog input fails closed")
	_check(SpeciesCatalog.build([observation_a], " bad-bake ", SOURCE_RUN_HASH).is_empty(), "non-canonical bake id fails closed")
	_check(SpeciesCatalog.build([observation_a], BAKE_ID, "bad").is_empty(), "malformed source run hash fails closed")

	var tampered_entry := entry_a.duplicate(true)
	tampered_entry["entry_hash"] = "0".repeat(64)
	_check(not SpeciesCatalog.validate_entry(tampered_entry), "entry hash tamper is rejected")
	tampered_entry = entry_a.duplicate(true)
	tampered_entry["canonical_species_declared"] = true
	tampered_entry["entry_hash"] = SpeciesCatalog.compute_entry_hash(tampered_entry)
	_check(not SpeciesCatalog.validate_entry(tampered_entry), "canonical species promotion is rejected even with recomputed hash")
	tampered_entry = entry_a.duplicate(true)
	tampered_entry["unexpected"] = true
	_check(not SpeciesCatalog.validate_entry(tampered_entry), "unexpected entry field is rejected")
	tampered_entry = entry_a.duplicate(true)
	tampered_entry["observed_patch_ids"] = ["patch-c", "patch-a", "patch-b"]
	tampered_entry["entry_hash"] = SpeciesCatalog.compute_entry_hash(tampered_entry)
	_check(not SpeciesCatalog.validate_entry(tampered_entry), "non-canonical patch ordering is rejected")

	var tampered_catalog := multi_ab.duplicate(true)
	tampered_catalog["catalog_hash"] = "0".repeat(64)
	_check(not SpeciesCatalog.validate_catalog(tampered_catalog), "catalog hash tamper is rejected")
	tampered_catalog = multi_ab.duplicate(true)
	tampered_catalog["canonical_species_declared"] = true
	tampered_catalog["catalog_hash"] = SpeciesCatalog.compute_catalog_hash(tampered_catalog)
	_check(not SpeciesCatalog.validate_catalog(tampered_catalog), "catalog cannot promote research identities to canonical species")
	tampered_catalog = multi_ab.duplicate(true)
	var reversed_entries: Array = Array(tampered_catalog["entries"]).duplicate(true)
	reversed_entries.reverse()
	tampered_catalog["entries"] = reversed_entries
	tampered_catalog["catalog_hash"] = SpeciesCatalog.compute_catalog_hash(tampered_catalog)
	_check(not SpeciesCatalog.validate_catalog(tampered_catalog), "non-canonical entry ordering is rejected")
	tampered_catalog = multi_ab.duplicate(true)
	tampered_catalog["unexpected"] = true
	_check(not SpeciesCatalog.validate_catalog(tampered_catalog), "unexpected catalog field is rejected")

	seed(97531)
	var rng_expected := [randi(), randi(), randi(), randi()]
	seed(97531)
	SpeciesCatalog.build([observation_a, observation_b], BAKE_ID, SOURCE_RUN_HASH)
	var rng_actual := [randi(), randi(), randi(), randi()]
	_check(rng_actual == rng_expected, "SpeciesCatalog build consumes no global RNG")

	var aggregate_hash := (
		String(single["catalog_hash"]) + "\n" +
		String(multi_ab["catalog_hash"]) + "\n" +
		String(alpha_later["catalog_hash"]) + "\n" +
		String(entry_a["research_species_id"])
	).sha256_text()

	if failed:
		quit(1)
		return
	print("ECO.EVO2 E2.1 SpeciesCatalog Contract: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("single_catalog_hash=" + String(single["catalog_hash"]))
	print("multi_catalog_hash=" + String(multi_ab["catalog_hash"]))
	print("alpha_research_species_id=" + String(entry_a["research_species_id"]))
	print("parent_p2_7=" + SpeciesCatalog.PARENT_P2_7_ACCEPTED_AGGREGATE)
	quit(0)


func _observation(
	lineage_id: String,
	ancestry: Array,
	split_year: int,
	genome: Dictionary,
	recruitment_traits: Dictionary,
	patches_by_year: Array,
	base_moisture: float
) -> Dictionary:
	var geography_history: Array = []
	var ecology_history: Array = []
	for index in range(patches_by_year.size()):
		var year := split_year + index + 1
		geography_history.append({
			"year": year,
			"patch_ids": Array(patches_by_year[index]).duplicate(),
		})
		var environment := EnvironmentSample.create(
			float(index) * 10.0,
			float(index) * -7.0,
			12.0 + float(index),
			clampf(base_moisture + 0.02 * float(index), 0.0, 1.0),
			0.70 - 0.03 * float(index),
			0.60 + 0.02 * float(index),
			0.05 * float(index),
			7000 + index,
			"evo2-e2-1-fixture"
		)
		ecology_history.append({"year": year, "environment": environment})
	return DivergenceDiagnostics.create_observation(
		lineage_id,
		ancestry,
		split_year,
		genome,
		recruitment_traits,
		geography_history,
		ecology_history
	)


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.EVO2 E2.1 assertion failed: " + label)
