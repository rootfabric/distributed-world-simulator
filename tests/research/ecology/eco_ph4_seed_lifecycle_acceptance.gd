extends SceneTree

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Profile = preload("res://scripts/research/ecology/plant_seed_lifecycle_profile_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_seed_lifecycle_v1.gd")
const Probes = preload("res://scripts/research/ecology/plant_seed_lifecycle_probes_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var profile := Profile.create_default()
	_check(bool(Profile.validate(profile).get("success", false)), "default lifecycle profile valid")
	_check(String(profile["checksum"]).length() == 64, "lifecycle profile checksum")

	var genome := Genome.create_default()
	var inherited := Traits.create_default()
	var genome_snapshot := JSON.stringify(genome)
	var inherited_snapshot := JSON.stringify(inherited)
	var payload := Probes.founder_payload()
	_check(bool(Lifecycle.validate_payload(payload).get("success", false)), "founder seed payload valid")
	_check(String(payload["genome"]["checksum"]) == String(genome["checksum"]), "founder payload carries genome truth")
	_check(String(payload["inherited_development_traits"]["checksum"]) == String(inherited["checksum"]), "founder payload carries inherited development truth")
	_check(String(payload["payload_hash"]).length() == 64, "founder payload hash")
	_check(int(payload["generation"]) == 0, "founder generation zero")
	_check(int(payload["parent_individual_seed"]) == -1, "founder has no parent individual")
	_check(not payload.has("growth_graph"), "seed payload does not carry GrowthGraph")
	_check(not payload.has("phenotype"), "seed payload does not carry realized phenotype")
	_check(not payload.has("mesh"), "seed payload does not carry mesh")

	var run := Probes.reference_run()
	_check(not run.is_empty(), "reference lifecycle run exists")
	_check(String(run.get("lifecycle_hash", "")).length() == 64, "reference lifecycle hash")
	var timeline: Array = run["timeline"]
	for stage in [Lifecycle.STAGE_SEED, Lifecycle.STAGE_GERMINATED, Lifecycle.STAGE_JUVENILE, Lifecycle.STAGE_ADULT, Lifecycle.STAGE_REPRODUCTIVE]:
		_check(stage in timeline, "reference lifecycle contains %s" % stage)
	_check(String(run["final_state"]["stage"]) == Lifecycle.STAGE_REPRODUCTIVE, "reference reaches reproductive stage")
	_check(bool(run["final_state"]["germinated"]), "reference germinated")
	_check(int(run["final_state"]["reproduction_count"]) == 1, "reference reproduces once")
	_check(int(run["final_state"]["offspring_count"]) == int(genome["seed_count"]), "offspring count follows genome seed_count")
	_check(run["offspring"].size() == int(genome["seed_count"]), "all offspring payloads materialized in research fixture")
	_check(String(run["final_state"]["offspring_batch_hash"]).length() == 64, "offspring batch hash")

	var individual_ids := {}
	var payload_hashes := {}
	for child_variant in run["offspring"]:
		var child: Dictionary = child_variant
		_check(bool(Lifecycle.validate_payload(child).get("success", false)), "offspring payload valid")
		_check(int(child["generation"]) == 1, "offspring generation increments")
		_check(int(child["parent_individual_seed"]) == int(payload["envelope"]["individual_seed"]), "offspring parent pointer")
		_check(String(child["lineage_id"]) == String(payload["lineage_id"]), "offspring lineage retained")
		_check(String(child["genome"]["checksum"]) == String(payload["genome"]["checksum"]), "offspring genome inherited unchanged")
		_check(String(child["inherited_development_traits"]["checksum"]) == String(payload["inherited_development_traits"]["checksum"]), "offspring development program inherited unchanged")
		_check(not child.has("growth_graph"), "offspring seed carries no GrowthGraph")
		_check(not child.has("phenotype"), "offspring seed carries no phenotype")
		var individual_seed := int(child["envelope"]["individual_seed"])
		individual_ids[individual_seed] = true
		payload_hashes[String(child["payload_hash"])] = true
	_check(individual_ids.size() == int(genome["seed_count"]), "offspring individual seeds unique")
	_check(payload_hashes.size() == int(genome["seed_count"]), "offspring payload hashes unique")

	var replay := Probes.reference_run()
	_check(String(run["lifecycle_hash"]) == String(replay["lifecycle_hash"]), "reference lifecycle exact replay")
	_check(String(run["final_state"]["offspring_batch_hash"]) == String(replay["final_state"]["offspring_batch_hash"]), "offspring batch exact replay")

	var dormancy := Probes.dormancy_then_recovery()
	_check(not dormancy.is_empty(), "dormancy/recovery probe exists")
	var dry_steps: Array = dormancy["dry_steps"]
	_check(dry_steps.size() == 10, "ten dry dormancy steps")
	for dry_state_variant in dry_steps:
		var dry_state: Dictionary = dry_state_variant
		_check(String(dry_state["stage"]) == Lifecycle.STAGE_DORMANT, "dry seed remains dormant")
		_check(float(dry_state["development_age_years"]) == 0.0, "dormancy does not age development program")
	_check(float(dry_steps[dry_steps.size() - 1]["chronological_age_years"]) > 0.9, "dormant seed chronological age advances")
	var recovery: Dictionary = dormancy["recovery"]
	_check(String(recovery["state"]["stage"]) == Lifecycle.STAGE_GERMINATED, "same dormant seed germinates after environment recovery")
	_check(float(recovery["state"]["development_age_years"]) == 0.0, "germination starts development age at zero")
	_check(String(recovery["state"]["payload_hash"]) == String(payload["payload_hash"]), "environment recovery does not replace heredity payload")

	var pair := Probes.offspring_environment_pair()
	_check(not pair.is_empty(), "offspring environment pair exists")
	var child: Dictionary = pair["child"]
	var shade: Dictionary = pair["shade"]
	var sun: Dictionary = pair["sun"]
	_check(String(shade["phenotype"]["genome_checksum"]) == String(sun["phenotype"]["genome_checksum"]), "offspring genome identical across environments")
	_check(String(shade["phenotype"]["inherited_traits_checksum"]) == String(sun["phenotype"]["inherited_traits_checksum"]), "offspring inherited traits identical across environments")
	_check(String(shade["phenotype"]["phenotype_hash"]) != String(sun["phenotype"]["phenotype_hash"]), "same offspring payload realizes different phenotype across environments")
	_check(String(child["payload_hash"]) == String(shade["state"]["payload_hash"]), "shade realization consumes same child payload")
	_check(String(child["payload_hash"]) == String(sun["state"]["payload_hash"]), "sun realization consumes same child payload")

	_check(JSON.stringify(genome) == genome_snapshot, "PH4 does not mutate genome")
	_check(JSON.stringify(inherited) == inherited_snapshot, "PH4 does not mutate inherited development traits")
	_test_source_boundaries()

	print("ECO.PH4 profile_hash=%s" % String(profile["checksum"]))
	print("ECO.PH4 founder_payload_hash=%s" % String(payload["payload_hash"]))
	print("ECO.PH4 lifecycle_hash=%s" % String(run["lifecycle_hash"]))
	print("ECO.PH4 offspring_batch_hash=%s" % String(run["final_state"]["offspring_batch_hash"]))
	print("ECO.PH4 timeline=%s offspring=%d" % [str(run["timeline"]), run["offspring"].size()])
	_finish()

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_seed_lifecycle_v1.gd").to_lower()
	for forbidden in ["treegenerator", "bushgenerator", "grassgenerator", "plant_type", "species", "meshinstance", "multimesh", "camera", "authority", "network", "persistence"]:
		_check(not source.contains(forbidden), "PH4 source excludes %s" % forbidden)
	_check(source.contains("create_seed_envelope"), "PH4 reuses accepted PH0 seed envelope contract")
	_check(source.contains("ph2.realize"), "PH4 regrows phenotype through accepted PH2")
	_check(source.contains("ph3.evaluate"), "PH4 gates lifecycle through accepted PH3 coupling")
	_check(not source.contains("mutation"), "PH4 does not enable mutation before morphology calibration")
	_check(not source.contains("growth_graph\":"), "PH4 seed payload does not serialize GrowthGraph")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.PH4 Seed Development Lifecycle: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.PH4 FAIL: %s" % failure)
	print("ECO.PH4 Seed Development Lifecycle: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
