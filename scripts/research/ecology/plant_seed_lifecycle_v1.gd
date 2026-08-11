extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PH2 = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const PH3 = preload("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd")
const Profile = preload("res://scripts/research/ecology/plant_seed_lifecycle_profile_v1.gd")

const SEED_PAYLOAD_SCHEMA := "distributed_world_simulator.ecology.plant_seed_payload.v1"
const STATE_SCHEMA := "distributed_world_simulator.ecology.plant_seed_lifecycle_state.v1"
const RUN_SCHEMA := "distributed_world_simulator.ecology.plant_seed_lifecycle_run.v1"
const VERSION := "1.0.0"

const STAGE_SEED := "SEED"
const STAGE_DORMANT := "DORMANT_SEED"
const STAGE_GERMINATED := "GERMINATED"
const STAGE_JUVENILE := "JUVENILE"
const STAGE_ADULT := "ADULT"
const STAGE_REPRODUCTIVE := "REPRODUCTIVE"
const STAGE_SENESCENT := "SENESCENT"
const VALID_STAGES: Array[String] = [
	STAGE_SEED, STAGE_DORMANT, STAGE_GERMINATED, STAGE_JUVENILE,
	STAGE_ADULT, STAGE_REPRODUCTIVE, STAGE_SENESCENT,
]

static func create_founder_payload(genome: Dictionary, inherited_traits: Dictionary, lineage_id: String, reproduction_event: String = "founder/ph4", seed_index: int = 0, stored_energy: float = 1.0) -> Dictionary:
	if lineage_id.is_empty():
		return {}
	var envelope := Contract.create_seed_envelope(genome, inherited_traits, lineage_id, reproduction_event, seed_index, stored_energy)
	if envelope.is_empty():
		return {}
	return _payload(genome, inherited_traits, envelope, lineage_id, 0, -1)

static func create_offspring_payload(parent_payload: Dictionary, reproduction_event: String, seed_index: int, stored_energy: float) -> Dictionary:
	if not bool(validate_payload(parent_payload).get("success", false)):
		return {}
	var genome: Dictionary = parent_payload["genome"]
	var inherited: Dictionary = parent_payload["inherited_development_traits"]
	var parent_seed := int(parent_payload["envelope"]["individual_seed"])
	var lineage_id := String(parent_payload["lineage_id"])
	var envelope := Contract.create_seed_envelope(genome, inherited, "%s/parent/%d" % [lineage_id, parent_seed], reproduction_event, seed_index, stored_energy)
	if envelope.is_empty():
		return {}
	return _payload(genome, inherited, envelope, lineage_id, int(parent_payload["generation"]) + 1, parent_seed)

static func validate_payload(payload: Dictionary) -> Dictionary:
	if String(payload.get("schema", "")) != SEED_PAYLOAD_SCHEMA or String(payload.get("version", "")) != VERSION:
		return _failure("ECO_PH4_PAYLOAD_SCHEMA_VERSION_MISMATCH")
	var genome: Dictionary = payload.get("genome", {})
	var inherited: Dictionary = payload.get("inherited_development_traits", {})
	var envelope: Dictionary = payload.get("envelope", {})
	if not bool(Genome.validate(genome).get("success", false)):
		return _failure("ECO_PH4_PAYLOAD_INVALID_GENOME")
	if not bool(Traits.validate(inherited).get("success", false)):
		return _failure("ECO_PH4_PAYLOAD_INVALID_DEVELOPMENT_TRAITS")
	if String(envelope.get("schema", "")) != Contract.SEED_ENVELOPE_SCHEMA:
		return _failure("ECO_PH4_PAYLOAD_INVALID_ENVELOPE")
	if String(envelope.get("genome_checksum", "")) != String(genome.get("checksum", "")):
		return _failure("ECO_PH4_PAYLOAD_GENOME_CHECKSUM_MISMATCH")
	if String(envelope.get("development_traits_checksum", "")) != String(inherited.get("checksum", "")):
		return _failure("ECO_PH4_PAYLOAD_TRAITS_CHECKSUM_MISMATCH")
	if String(payload.get("lineage_id", "")).is_empty() or int(payload.get("generation", -1)) < 0:
		return _failure("ECO_PH4_PAYLOAD_INVALID_LINEAGE")
	if int(envelope.get("individual_seed", -1)) < 0:
		return _failure("ECO_PH4_PAYLOAD_INVALID_INDIVIDUAL_SEED")
	var payload_hash := String(payload.get("payload_hash", ""))
	if payload_hash.length() != 64 or payload_hash != compute_payload_hash(payload):
		return _failure("ECO_PH4_PAYLOAD_HASH_MISMATCH")
	return _success()

static func create_initial_state(payload: Dictionary) -> Dictionary:
	if not bool(validate_payload(payload).get("success", false)):
		return {}
	var state := {
		"schema": STATE_SCHEMA,
		"version": VERSION,
		"payload_hash": String(payload["payload_hash"]),
		"individual_seed": int(payload["envelope"]["individual_seed"]),
		"stage": STAGE_SEED,
		"chronological_age_years": 0.0,
		"development_age_years": 0.0,
		"reserve_energy": float(payload["envelope"].get("stored_energy", 0.0)),
		"germinated": false,
		"reproduction_count": 0,
		"offspring_count": 0,
		"offspring_batch_hash": "",
		"last_environment_checksum": "",
		"last_phenotype_hash": "",
		"last_coupling_hash": "",
		"last_coupled_net": 0.0,
	}
	state["state_hash"] = compute_state_hash(state)
	return state

static func advance(state: Dictionary, payload: Dictionary, environment: Dictionary, delta_years: float, lifecycle_profile: Dictionary = {}) -> Dictionary:
	var profile := Profile.create_default() if lifecycle_profile.is_empty() else lifecycle_profile
	if not bool(validate_payload(payload).get("success", false)):
		return {}
	if not bool(Profile.validate(profile).get("success", false)):
		return {}
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not is_finite(delta_years) or delta_years <= 0.0:
		return {}
	if String(state.get("schema", "")) != STATE_SCHEMA or String(state.get("payload_hash", "")) != String(payload["payload_hash"]):
		return {}
	if not String(state.get("stage", "")) in VALID_STAGES:
		return {}

	var next := state.duplicate(true)
	next["chronological_age_years"] = float(next["chronological_age_years"]) + delta_years
	var genome: Dictionary = payload["genome"]
	var inherited: Dictionary = payload["inherited_development_traits"]
	var phenotype := PH2.realize(payload["envelope"], inherited, environment)
	if phenotype.is_empty():
		return {}
	var coupling := PH3.evaluate(environment, genome, phenotype, float(profile["evaluation_biomass_kg_m2"]))
	if coupling.is_empty():
		return {}
	var coupled_net := float(coupling["coupled_net_resource_balance"])
	next["last_environment_checksum"] = String(environment["checksum"])
	next["last_phenotype_hash"] = String(phenotype["phenotype_hash"])
	next["last_coupling_hash"] = String(coupling["coupling_hash"])
	next["last_coupled_net"] = coupled_net

	var stage := String(next["stage"])
	if stage in [STAGE_SEED, STAGE_DORMANT]:
		var enough_energy := float(next["reserve_energy"]) >= float(profile["germination_min_stored_energy"])
		var viable := coupled_net >= float(profile["germination_min_coupled_net"])
		if enough_energy and viable:
			next["stage"] = STAGE_GERMINATED
			next["germinated"] = true
			next["reserve_energy"] = maxf(0.0, float(next["reserve_energy"]) - float(profile["germination_energy_cost"]))
		else:
			next["stage"] = STAGE_DORMANT
	else:
		next["development_age_years"] = float(next["development_age_years"]) + delta_years
		var lifespan := float(genome["lifespan_years"])
		var juvenile_age := lifespan * float(profile["juvenile_age_fraction"])
		var adult_age := lifespan * float(profile["adult_age_fraction"])
		var reproductive_age := lifespan * float(profile["reproductive_age_fraction"])
		var senescent_age := lifespan * float(profile["senescent_age_fraction"])
		var dev_age := float(next["development_age_years"])
		if dev_age >= senescent_age:
			next["stage"] = STAGE_SENESCENT
		elif dev_age >= reproductive_age and coupled_net >= float(profile["reproduction_min_coupled_net"]):
			next["stage"] = STAGE_REPRODUCTIVE
		elif dev_age >= adult_age:
			next["stage"] = STAGE_ADULT
		elif dev_age >= juvenile_age:
			next["stage"] = STAGE_JUVENILE
		else:
			next["stage"] = STAGE_GERMINATED

	var offspring: Array = []
	if String(next["stage"]) == STAGE_REPRODUCTIVE and int(next["reproduction_count"]) == 0:
		var event := "ph4/reproduction/g%d/i%d" % [int(payload["generation"]), int(payload["envelope"]["individual_seed"])]
		var total := int(genome["seed_count"])
		for index in range(total):
			var child := create_offspring_payload(payload, event, index, float(profile["offspring_stored_energy"]))
			if child.is_empty():
				return {}
			offspring.append(child)
		next["reproduction_count"] = 1
		next["offspring_count"] = offspring.size()
		next["offspring_batch_hash"] = compute_offspring_batch_hash(offspring)

	next["state_hash"] = compute_state_hash(next)
	return {"state": next, "phenotype": phenotype, "coupling": coupling, "offspring": offspring}

static func run_to_first_reproduction(payload: Dictionary, environment: Dictionary, step_years: float = 0.10, max_years: float = 3.0, lifecycle_profile: Dictionary = {}) -> Dictionary:
	var state := create_initial_state(payload)
	if state.is_empty() or step_years <= 0.0 or max_years <= 0.0:
		return {}
	var timeline: Array[String] = [String(state["stage"])]
	var phenotype_hashes: Array[String] = []
	var coupling_hashes: Array[String] = []
	var offspring: Array = []
	var steps := int(ceil(max_years / step_years))
	for _i in range(steps):
		var result := advance(state, payload, environment, step_years, lifecycle_profile)
		if result.is_empty():
			return {}
		state = result["state"]
		var current_stage := String(state["stage"])
		if timeline.is_empty() or timeline[timeline.size() - 1] != current_stage:
			timeline.append(current_stage)
		phenotype_hashes.append(String(result["phenotype"]["phenotype_hash"]))
		coupling_hashes.append(String(result["coupling"]["coupling_hash"]))
		if not result["offspring"].is_empty():
			offspring = result["offspring"]
			break
	var profile := Profile.create_default() if lifecycle_profile.is_empty() else lifecycle_profile
	var run := {
		"schema": RUN_SCHEMA,
		"version": VERSION,
		"payload_hash": String(payload["payload_hash"]),
		"environment_checksum": String(environment["checksum"]),
		"profile_checksum": String(profile["checksum"]),
		"timeline": timeline,
		"final_state": state,
		"offspring": offspring,
		"phenotype_hashes": phenotype_hashes,
		"coupling_hashes": coupling_hashes,
	}
	run["lifecycle_hash"] = compute_run_hash(run)
	return run

static func compute_payload_hash(payload: Dictionary) -> String:
	return "|".join(PackedStringArray([SEED_PAYLOAD_SCHEMA, VERSION, String(payload.get("lineage_id", "")), str(int(payload.get("generation", -1))), str(int(payload.get("parent_individual_seed", -1))), String(payload.get("genome", {}).get("checksum", "")), String(payload.get("inherited_development_traits", {}).get("checksum", "")), String(payload.get("envelope", {}).get("checksum", ""))])).sha256_text()

static func compute_state_hash(state: Dictionary) -> String:
	return "|".join(PackedStringArray([STATE_SCHEMA, VERSION, String(state.get("payload_hash", "")), str(int(state.get("individual_seed", -1))), String(state.get("stage", "")), "%.9f" % float(state.get("chronological_age_years", 0.0)), "%.9f" % float(state.get("development_age_years", 0.0)), "%.9f" % float(state.get("reserve_energy", 0.0)), str(int(bool(state.get("germinated", false)))), str(int(state.get("reproduction_count", 0))), str(int(state.get("offspring_count", 0))), String(state.get("offspring_batch_hash", "")), String(state.get("last_environment_checksum", "")), String(state.get("last_phenotype_hash", "")), String(state.get("last_coupling_hash", "")), "%.9f" % float(state.get("last_coupled_net", 0.0))])).sha256_text()

static func compute_offspring_batch_hash(offspring: Array) -> String:
	var hashes := PackedStringArray()
	for child in offspring:
		hashes.append(String(child.get("payload_hash", "")))
	return "|".join(hashes).sha256_text()

static func compute_run_hash(run: Dictionary) -> String:
	var tokens := PackedStringArray([RUN_SCHEMA, VERSION, String(run.get("payload_hash", "")), String(run.get("environment_checksum", "")), String(run.get("profile_checksum", "")), String(run.get("final_state", {}).get("state_hash", "")), String(run.get("final_state", {}).get("offspring_batch_hash", ""))])
	for stage in run.get("timeline", []):
		tokens.append(String(stage))
	for value in run.get("phenotype_hashes", []):
		tokens.append(String(value))
	for value in run.get("coupling_hashes", []):
		tokens.append(String(value))
	return "|".join(tokens).sha256_text()

static func _payload(genome: Dictionary, inherited_traits: Dictionary, envelope: Dictionary, lineage_id: String, generation: int, parent_individual_seed: int) -> Dictionary:
	var payload := {"schema": SEED_PAYLOAD_SCHEMA, "version": VERSION, "lineage_id": lineage_id, "generation": generation, "parent_individual_seed": parent_individual_seed, "genome": genome.duplicate(true), "inherited_development_traits": inherited_traits.duplicate(true), "envelope": envelope.duplicate(true)}
	payload["payload_hash"] = compute_payload_hash(payload)
	return payload

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
