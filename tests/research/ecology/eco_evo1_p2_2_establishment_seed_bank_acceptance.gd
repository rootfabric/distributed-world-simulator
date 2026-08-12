extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_establishment_seed_bank_experiment_v1.gd")
const P2_1 = preload("res://scripts/research/ecology/plant_seed_dispersal_experiment_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const Establishment = preload("res://scripts/research/ecology/plant_establishment_seed_bank_v1.gd")

const EXPECTED_PARENT := "cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var result := Experiment.run()
	_check(not result.is_empty(), "P2.2 experiment must exist")
	if result.is_empty():
		_finish()
		return

	_check(String(result.get("p2_1_parent_hash", "")) == EXPECTED_PARENT, "accepted P2.1 parent hash must remain exact")
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash must be sha256")
	var repeat := Experiment.run()
	_check(not repeat.is_empty(), "same-process repeat must exist")
	if not repeat.is_empty():
		_check(String(repeat.get("aggregate_hash", "")) == String(result.get("aggregate_hash", "")), "same-process aggregate must be deterministic")

	var cases: Dictionary = result["cases"]
	for case_id in Experiment.CASE_ORDER:
		_check(cases.has(case_id), "case must exist: " + case_id)
		if not cases.has(case_id):
			continue
		var case: Dictionary = cases[case_id]
		_check(bool(case.get("conservation_ok", false)), "case must conserve integer seed counts: " + case_id)
		_check(int(case.get("recruitment_cohort_count", 0)) <= int(case.get("packet_outcome_count", 0)), "recruitment truth must remain cohort-bounded: " + case_id)
		_check(int(case.get("seed_bank_cohort_count", 0)) <= int(case.get("packet_outcome_count", 0)), "seed-bank truth must remain cohort-bounded: " + case_id)

	_check(int(result["favourable_recruited"]) > int(result["dry_recruited"]), "matched favourable environment must recruit more than severe dry mismatch")
	_check(int(result["favourable_recruited"]) > int(result["flooded_recruited"]), "matched favourable environment must recruit more than high flood exposure")
	_check(int(result["low_dormancy_recruited"]) > int(result["high_dormancy_recruited"]), "low dormancy must increase immediate recruitment")
	_check(int(result["high_dormancy_bank"]) > int(result["low_dormancy_bank"]), "high dormancy must retain more viable seeds in bank")
	_check(int(result["long_bank_remaining"]) > int(result["short_bank_remaining"]), "long seed-bank half-life must retain more viable seeds after two years")
	_check(int(result["reactivation_recruited"]) > 0, "persistent seed bank must be able to recruit after environment improves")
	_check(int(result["boundary_exported"]) == 80, "all controlled outside-domain P2.1 seeds must remain explicit export")
	var boundary: Dictionary = cases["BOUNDARY_EXPORT"]
	_check(int(boundary["recruited_seed_count"]) == 0, "outside-domain export must not recruit locally")
	_check(int(boundary["seed_bank_seed_count"]) == 0, "outside-domain export must not enter local seed bank")
	_check(int(boundary["decayed_seed_count"]) == 0, "outside-domain export must not be silently decayed locally")

	# Direct identity and stage-separation probe on one accepted P2.1 packet.
	var parent := P2_1.run()
	var genome := Genome.create_default()
	var traits := RecruitmentTraits.create_default()
	var environment := EnvironmentSample.create(0.0, 0.0, 17.0, 0.58, 0.78, 0.78, 0.05, 22021, "eco-evo1-p2-2/identity")
	_check(not parent.is_empty() and not genome.is_empty() and not traits.is_empty() and not environment.is_empty(), "identity probe prerequisites must exist")
	if not parent.is_empty() and not genome.is_empty() and not traits.is_empty() and not environment.is_empty():
		var packet: Dictionary = parent["cases"]["BASE_STILL"]["packets"][0]
		var outcome := Establishment.settle_packet(packet, genome, traits, environment)
		_check(not outcome.is_empty(), "identity probe outcome must exist")
		if not outcome.is_empty():
			_check(String(outcome["lineage_id"]) == String(packet["lineage_id"]), "lineage identity must survive establishment")
			_check(String(outcome["genome_checksum"]) == String(packet["genome_checksum"]), "genome identity must survive establishment")
			_check(String(outcome["reproduction_event"]) == String(packet["reproduction_event"]), "reproduction-event identity must survive establishment")
			_check(not outcome.has("population_biomass") and not outcome.has("carrying_capacity") and not outcome.has("succession_state"), "P2.2 must not smuggle P2.3 turnover/succession semantics")
			var bank := Dictionary(outcome.get("seed_bank_cohort", {}))
			if not bank.is_empty():
				_check(String(bank["lineage_id"]) == String(packet["lineage_id"]), "seed-bank cohort must preserve lineage")
				_check(String(bank["genome_checksum"]) == String(packet["genome_checksum"]), "seed-bank cohort must preserve genome")

	print("ECO.EVO1-P2.2 favourable=%d dry=%d flooded=%d low_dormancy_recruited=%d high_dormancy_recruited=%d" % [
		int(result["favourable_recruited"]), int(result["dry_recruited"]), int(result["flooded_recruited"]),
		int(result["low_dormancy_recruited"]), int(result["high_dormancy_recruited"])
	])
	print("ECO.EVO1-P2.2 low_dormancy_bank=%d high_dormancy_bank=%d short_bank=%d long_bank=%d reactivation=%d boundary_exported=%d" % [
		int(result["low_dormancy_bank"]), int(result["high_dormancy_bank"]), int(result["short_bank_remaining"]),
		int(result["long_bank_remaining"]), int(result["reactivation_recruited"]), int(result["boundary_exported"])
	])
	print("ECO.EVO1-P2.2 Establishment / Recruitment / Seed Bank: PASS (%d assertions) aggregate_hash=%s p2_1=%s" % [
		assertions, String(result["aggregate_hash"]), String(result["p2_1_parent_hash"])
	])
	_finish()

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		quit(0)
		return
	for message in failures:
		push_error("ECO.EVO1-P2.2 ASSERTION FAILED: " + message)
	print("ECO.EVO1-P2.2 Establishment / Recruitment / Seed Bank: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
