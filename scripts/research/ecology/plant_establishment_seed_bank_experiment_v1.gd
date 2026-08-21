extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const Establishment = preload("res://scripts/research/ecology/plant_establishment_seed_bank_v1.gd")
const P2_1 = preload("res://scripts/research/ecology/plant_seed_dispersal_experiment_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_2_establishment_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.2.1"
const ACCEPTED_P2_1_HASH := "cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6"

const CASE_ORDER: Array[String] = [
	"FAVOURABLE_DEFAULT",
	"DRY_DEFAULT",
	"FLOODED_DEFAULT",
	"LOW_DORMANCY",
	"HIGH_DORMANCY",
	"BANK_SHORT_2Y",
	"BANK_LONG_2Y",
	"BANK_REACTIVATION",
	"BOUNDARY_EXPORT",
]

static func run() -> Dictionary:
	var parent := P2_1.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_P2_1_HASH:
		return {}
	var genome := Genome.create_default()
	var default_traits := RecruitmentTraits.create_default()
	var low_dormancy := RecruitmentTraits.create("recruitment-traits/p2-2-low-dormancy", 0.10, 3.0)
	var high_dormancy := RecruitmentTraits.create("recruitment-traits/p2-2-high-dormancy", 0.85, 3.0)
	var short_bank := RecruitmentTraits.create("recruitment-traits/p2-2-short-bank", 0.85, 0.50)
	var long_bank := RecruitmentTraits.create("recruitment-traits/p2-2-long-bank", 0.85, 5.0)
	for traits in [default_traits, low_dormancy, high_dormancy, short_bank, long_bank]:
		if Dictionary(traits).is_empty():
			return {}

	var favourable := _environment("favourable", 0.58, 0.78, 0.78, 0.05, 17.0)
	var dry := _environment("dry", 0.05, 0.78, 0.78, 0.05, 17.0)
	var flooded := _environment("flooded", 0.58, 0.78, 0.78, 0.85, 17.0)
	var dormant := _environment("dormant", 0.05, 0.35, 0.60, 0.05, -20.0)
	for environment in [favourable, dry, flooded, dormant]:
		if Dictionary(environment).is_empty():
			return {}

	var base_packets: Array = parent["cases"]["BASE_STILL"]["packets"]
	var boundary_packets: Array = parent["cases"]["BOUNDARY_EAST"]["packets"]
	var favourable_default := _settle_case(base_packets, genome, default_traits, favourable)
	var dry_default := _settle_case(base_packets, genome, default_traits, dry)
	var flooded_default := _settle_case(base_packets, genome, default_traits, flooded)
	var low_dormancy_case := _settle_case(base_packets, genome, low_dormancy, favourable)
	var high_dormancy_case := _settle_case(base_packets, genome, high_dormancy, favourable)
	var short_initial := _settle_case(base_packets, genome, short_bank, dormant)
	var long_initial := _settle_case(base_packets, genome, long_bank, dormant)
	var reactivation_initial := _settle_case(base_packets, genome, default_traits, dormant)
	if short_initial.is_empty() or long_initial.is_empty() or reactivation_initial.is_empty():
		return {}
	var short_aged := _advance_case(Array(short_initial["seed_bank_cohorts"]), genome, short_bank, dormant, 2.0)
	var long_aged := _advance_case(Array(long_initial["seed_bank_cohorts"]), genome, long_bank, dormant, 2.0)
	var reactivated := _advance_case(Array(reactivation_initial["seed_bank_cohorts"]), genome, default_traits, favourable, 1.0)
	var boundary_export := _settle_case(boundary_packets, genome, default_traits, favourable)

	var cases := {
		"FAVOURABLE_DEFAULT": favourable_default,
		"DRY_DEFAULT": dry_default,
		"FLOODED_DEFAULT": flooded_default,
		"LOW_DORMANCY": low_dormancy_case,
		"HIGH_DORMANCY": high_dormancy_case,
		"BANK_SHORT_2Y": short_aged,
		"BANK_LONG_2Y": long_aged,
		"BANK_REACTIVATION": reactivated,
		"BOUNDARY_EXPORT": boundary_export,
	}
	for case_id in CASE_ORDER:
		if not cases.has(case_id) or Dictionary(cases[case_id]).is_empty():
			return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_1_parent_hash": ACCEPTED_P2_1_HASH,
		"case_order": CASE_ORDER.duplicate(),
		"cases": cases,
		"favourable_recruited": int(favourable_default["recruited_seed_count"]),
		"dry_recruited": int(dry_default["recruited_seed_count"]),
		"flooded_recruited": int(flooded_default["recruited_seed_count"]),
		"low_dormancy_recruited": int(low_dormancy_case["recruited_seed_count"]),
		"high_dormancy_recruited": int(high_dormancy_case["recruited_seed_count"]),
		"low_dormancy_bank": int(low_dormancy_case["seed_bank_seed_count"]),
		"high_dormancy_bank": int(high_dormancy_case["seed_bank_seed_count"]),
		"short_bank_remaining": int(short_aged["seed_bank_seed_count"]),
		"long_bank_remaining": int(long_aged["seed_bank_seed_count"]),
		"reactivation_recruited": int(reactivated["recruited_seed_count"]),
		"boundary_exported": int(boundary_export["exported_seed_count"]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _settle_case(packets: Array, genome: Dictionary, traits: Dictionary, environment: Dictionary) -> Dictionary:
	var results: Array = []
	var bank_cohorts: Array = []
	for packet_value in packets:
		var packet: Dictionary = packet_value
		var outcome := Establishment.settle_packet(packet, genome, traits, environment, 0.0)
		if outcome.is_empty() or not bool(outcome.get("conservation_ok", false)):
			return {}
		results.append(outcome)
		var bank := Dictionary(outcome.get("seed_bank_cohort", {}))
		if not bank.is_empty():
			bank_cohorts.append(bank)
	return _aggregate_outcomes(results, bank_cohorts)

static func _advance_case(bank_cohorts: Array, genome: Dictionary, traits: Dictionary, environment: Dictionary, delta_years: float) -> Dictionary:
	if bank_cohorts.is_empty():
		return {}
	var results: Array = []
	var next_bank: Array = []
	for cohort_value in bank_cohorts:
		var cohort: Dictionary = cohort_value
		var outcome := Establishment.advance_seed_bank(cohort, genome, traits, environment, delta_years)
		if outcome.is_empty() or not bool(outcome.get("conservation_ok", false)):
			return {}
		results.append(outcome)
		var bank := Dictionary(outcome.get("seed_bank_cohort", {}))
		if not bank.is_empty():
			next_bank.append(bank)
	return _aggregate_outcomes(results, next_bank)

static func _aggregate_outcomes(results: Array, bank_cohorts: Array) -> Dictionary:
	if results.is_empty():
		return {}
	var totals := {
		"input_seed_count": 0,
		"exported_seed_count": 0,
		"decayed_seed_count": 0,
		"germinated_seed_count": 0,
		"recruited_seed_count": 0,
		"failed_germination_count": 0,
		"seed_bank_seed_count": 0,
	}
	var result_hashes := PackedStringArray()
	var recruitment_cohort_count := 0
	for outcome_value in results:
		var outcome: Dictionary = outcome_value
		for field_name in totals.keys():
			totals[field_name] = int(totals[field_name]) + int(outcome.get(field_name, 0))
		if not Dictionary(outcome.get("recruitment_cohort", {})).is_empty():
			recruitment_cohort_count += 1
		result_hashes.append(String(outcome["result_hash"]))
	var conservation := int(totals["input_seed_count"]) == (
		int(totals["exported_seed_count"]) + int(totals["decayed_seed_count"])
		+ int(totals["failed_germination_count"]) + int(totals["recruited_seed_count"])
		+ int(totals["seed_bank_seed_count"])
	)
	var result := totals.duplicate(true)
	result["packet_outcome_count"] = results.size()
	result["recruitment_cohort_count"] = recruitment_cohort_count
	result["seed_bank_cohort_count"] = bank_cohorts.size()
	result["seed_bank_cohorts"] = bank_cohorts
	result["conservation_ok"] = conservation
	result["case_hash"] = "\n".join(result_hashes).sha256_text()
	return result

static func _environment(id: String, moisture: float, sunlight: float, nutrients: float, flood: float, temperature_c: float) -> Dictionary:
	return EnvironmentSample.create(0.0, 0.0, temperature_c, moisture, sunlight, nutrients, flood, 22021, "eco-evo1-p2-2/" + id)

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("p2_1_parent_hash", "")),
	])
	var cases: Dictionary = result["cases"]
	for case_id in CASE_ORDER:
		tokens.append("%s|%s" % [case_id, String(cases[case_id]["case_hash"])])
	for field_name in [
		"favourable_recruited", "dry_recruited", "flooded_recruited",
		"low_dormancy_recruited", "high_dormancy_recruited",
		"low_dormancy_bank", "high_dormancy_bank",
		"short_bank_remaining", "long_bank_remaining",
		"reactivation_recruited", "boundary_exported"
	]:
		tokens.append("%s=%d" % [field_name, int(result.get(field_name, 0))])
	return "\n".join(tokens).sha256_text()
