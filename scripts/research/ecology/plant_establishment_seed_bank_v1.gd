extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_establishment_seed_bank.v1"
const RECRUITMENT_COHORT_SCHEMA := SCHEMA + ".recruitment_cohort"
const SEED_BANK_COHORT_SCHEMA := SCHEMA + ".seed_bank_cohort"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001
const LN2 := 0.6931471805599453

static func settle_packet(
	packet: Dictionary,
	genome: Dictionary,
	recruitment_traits: Dictionary,
	environment: Dictionary,
	years_elapsed: float = 0.0
) -> Dictionary:
	if not _valid_packet(packet):
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not RecruitmentTraits.validate(recruitment_traits):
		return {}
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not is_finite(years_elapsed) or years_elapsed < 0.0 or years_elapsed > 1000.0:
		return {}
	if String(packet.get("genome_checksum", "")) != String(genome.get("checksum", "")):
		return {}

	var seed_count := int(packet["seed_count"])
	var identity := {
		"lineage_id": String(packet["lineage_id"]),
		"genome_checksum": String(packet["genome_checksum"]),
		"reproduction_event": String(packet["reproduction_event"]),
		"position": Vector2(packet["destination_position"]),
		"source_hash": String(packet["packet_hash"]),
	}
	if bool(packet["outside_domain"]):
		return _export_result(seed_count, identity, recruitment_traits, environment)
	return _process_seed_count(seed_count, 0.0, years_elapsed, identity, genome, recruitment_traits, environment)

static func advance_seed_bank(
	cohort: Dictionary,
	genome: Dictionary,
	recruitment_traits: Dictionary,
	environment: Dictionary,
	delta_years: float
) -> Dictionary:
	if not _valid_bank_cohort(cohort):
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not RecruitmentTraits.validate(recruitment_traits):
		return {}
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if not is_finite(delta_years) or delta_years <= 0.0 or delta_years > 1000.0:
		return {}
	if String(cohort.get("genome_checksum", "")) != String(genome.get("checksum", "")):
		return {}
	if String(cohort.get("recruitment_traits_checksum", "")) != String(recruitment_traits.get("checksum", "")):
		return {}
	var identity := {
		"lineage_id": String(cohort["lineage_id"]),
		"genome_checksum": String(cohort["genome_checksum"]),
		"reproduction_event": String(cohort["reproduction_event"]),
		"position": Vector2(cohort["position"]),
		"source_hash": String(cohort["cohort_hash"]),
	}
	return _process_seed_count(
		int(cohort["seed_count"]),
		float(cohort["age_years"]),
		delta_years,
		identity,
		genome,
		recruitment_traits,
		environment
	)

static func _process_seed_count(
	input_seed_count: int,
	age_before_years: float,
	delta_years: float,
	identity: Dictionary,
	genome: Dictionary,
	recruitment_traits: Dictionary,
	environment: Dictionary
) -> Dictionary:
	if input_seed_count <= 0:
		return {}
	var resource := ResourceModel.evaluate(environment, genome, 0.01)
	if resource.is_empty():
		return {}

	var half_life := float(recruitment_traits["seed_bank_half_life_years"])
	var survival_fraction := exp(-LN2 * delta_years / half_life)
	var viable_after_decay := _deterministic_count(
		input_seed_count,
		survival_fraction,
		String(identity["source_hash"]) + "|bank-survival|%.12f" % delta_years
	)
	var decayed_count := input_seed_count - viable_after_decay

	# Seed-stage water matching deliberately does not grant adult root-depth access.
	var water_preference := float(genome["water_preference"])
	var water_width := float(genome["water_tolerance_width"])
	var water_z := (float(environment["soil_moisture"]) - water_preference) / maxf(water_width, EPSILON)
	var seed_water_response := exp(-0.5 * water_z * water_z)
	var temperature_response := float(resource["temperature_response"])
	var germination_activation := sqrt(maxf(seed_water_response * temperature_response, 0.0))
	var dormancy_fraction := float(recruitment_traits["dormancy_fraction"])
	var germination_fraction := clampf(germination_activation * (1.0 - dormancy_fraction), 0.0, 1.0)

	var germinated_count := _deterministic_count(
		viable_after_decay,
		germination_fraction,
		String(identity["source_hash"]) + "|germination|" + String(environment["checksum"])
	)
	var flood_survival := clampf(1.0 - float(environment["flood_frequency"]), 0.0, 1.0)
	var establishment_product := maxf(
		float(resource["light_response"]) * float(resource["nutrient_response"]) * flood_survival,
		0.0
	)
	var establishment_fraction := clampf(pow(establishment_product, 1.0 / 3.0), 0.0, 1.0)
	var recruited_count := _deterministic_count(
		germinated_count,
		establishment_fraction,
		String(identity["source_hash"]) + "|establishment|" + String(environment["checksum"])
	)
	var failed_germination_count := germinated_count - recruited_count
	var bank_count := viable_after_decay - germinated_count
	var age_after := age_before_years + delta_years

	var recruitment_cohort := _make_recruitment_cohort(identity, recruitment_traits, environment, recruited_count, age_after)
	var seed_bank_cohort := _make_seed_bank_cohort(identity, recruitment_traits, environment, bank_count, age_after)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"source_hash": String(identity["source_hash"]),
		"lineage_id": String(identity["lineage_id"]),
		"genome_checksum": String(identity["genome_checksum"]),
		"reproduction_event": String(identity["reproduction_event"]),
		"position": Vector2(identity["position"]),
		"recruitment_traits_checksum": String(recruitment_traits["checksum"]),
		"environment_checksum": String(environment["checksum"]),
		"age_before_years": age_before_years,
		"delta_years": delta_years,
		"age_after_years": age_after,
		"input_seed_count": input_seed_count,
		"exported_seed_count": 0,
		"decayed_seed_count": decayed_count,
		"viable_after_decay_count": viable_after_decay,
		"germinated_seed_count": germinated_count,
		"recruited_seed_count": recruited_count,
		"failed_germination_count": failed_germination_count,
		"seed_bank_seed_count": bank_count,
		"bank_survival_fraction": survival_fraction,
		"seed_water_response": seed_water_response,
		"temperature_response": temperature_response,
		"germination_activation": germination_activation,
		"germination_fraction": germination_fraction,
		"light_response": float(resource["light_response"]),
		"nutrient_response": float(resource["nutrient_response"]),
		"flood_survival": flood_survival,
		"establishment_fraction": establishment_fraction,
		"recruitment_cohort": recruitment_cohort,
		"seed_bank_cohort": seed_bank_cohort,
	}
	result["conservation_ok"] = _conservation_ok(result)
	result["result_hash"] = _result_hash(result)
	return result

static func _export_result(
	seed_count: int,
	identity: Dictionary,
	recruitment_traits: Dictionary,
	environment: Dictionary
) -> Dictionary:
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"source_hash": String(identity["source_hash"]),
		"lineage_id": String(identity["lineage_id"]),
		"genome_checksum": String(identity["genome_checksum"]),
		"reproduction_event": String(identity["reproduction_event"]),
		"position": Vector2(identity["position"]),
		"recruitment_traits_checksum": String(recruitment_traits["checksum"]),
		"environment_checksum": String(environment["checksum"]),
		"age_before_years": 0.0,
		"delta_years": 0.0,
		"age_after_years": 0.0,
		"input_seed_count": seed_count,
		"exported_seed_count": seed_count,
		"decayed_seed_count": 0,
		"viable_after_decay_count": 0,
		"germinated_seed_count": 0,
		"recruited_seed_count": 0,
		"failed_germination_count": 0,
		"seed_bank_seed_count": 0,
		"bank_survival_fraction": 1.0,
		"seed_water_response": 0.0,
		"temperature_response": 0.0,
		"germination_activation": 0.0,
		"germination_fraction": 0.0,
		"light_response": 0.0,
		"nutrient_response": 0.0,
		"flood_survival": 0.0,
		"establishment_fraction": 0.0,
		"recruitment_cohort": {},
		"seed_bank_cohort": {},
	}
	result["conservation_ok"] = _conservation_ok(result)
	result["result_hash"] = _result_hash(result)
	return result

static func _make_recruitment_cohort(
	identity: Dictionary,
	recruitment_traits: Dictionary,
	environment: Dictionary,
	seed_count: int,
	age_years: float
) -> Dictionary:
	if seed_count <= 0:
		return {}
	var cohort := {
		"schema": RECRUITMENT_COHORT_SCHEMA,
		"version": VERSION,
		"seed_count": seed_count,
		"lineage_id": String(identity["lineage_id"]),
		"genome_checksum": String(identity["genome_checksum"]),
		"reproduction_event": String(identity["reproduction_event"]),
		"position": Vector2(identity["position"]),
		"recruitment_traits_checksum": String(recruitment_traits["checksum"]),
		"environment_checksum": String(environment["checksum"]),
		"source_hash": String(identity["source_hash"]),
		"seed_age_years": age_years,
	}
	cohort["cohort_hash"] = _cohort_hash(cohort)
	return cohort

static func _make_seed_bank_cohort(
	identity: Dictionary,
	recruitment_traits: Dictionary,
	environment: Dictionary,
	seed_count: int,
	age_years: float
) -> Dictionary:
	if seed_count <= 0:
		return {}
	var cohort := {
		"schema": SEED_BANK_COHORT_SCHEMA,
		"version": VERSION,
		"seed_count": seed_count,
		"lineage_id": String(identity["lineage_id"]),
		"genome_checksum": String(identity["genome_checksum"]),
		"reproduction_event": String(identity["reproduction_event"]),
		"position": Vector2(identity["position"]),
		"recruitment_traits_checksum": String(recruitment_traits["checksum"]),
		"last_environment_checksum": String(environment["checksum"]),
		"source_hash": String(identity["source_hash"]),
		"age_years": age_years,
	}
	cohort["cohort_hash"] = _cohort_hash(cohort)
	return cohort

static func _valid_packet(packet: Dictionary) -> bool:
	if String(packet.get("schema", "")) != Dispersal.SCHEMA + ".packet":
		return false
	if int(packet.get("seed_count", 0)) <= 0:
		return false
	if String(packet.get("lineage_id", "")).is_empty() or String(packet.get("genome_checksum", "")).length() != 64:
		return false
	if String(packet.get("reproduction_event", "")).is_empty() or String(packet.get("packet_hash", "")).length() != 64:
		return false
	var position := Vector2(packet.get("destination_position", Vector2(INF, INF)))
	return is_finite(position.x) and is_finite(position.y)

static func _valid_bank_cohort(cohort: Dictionary) -> bool:
	if String(cohort.get("schema", "")) != SEED_BANK_COHORT_SCHEMA or String(cohort.get("version", "")) != VERSION:
		return false
	if int(cohort.get("seed_count", 0)) <= 0 or float(cohort.get("age_years", -1.0)) < 0.0:
		return false
	if String(cohort.get("genome_checksum", "")).length() != 64 or String(cohort.get("recruitment_traits_checksum", "")).length() != 64:
		return false
	return String(cohort.get("cohort_hash", "")) == _cohort_hash(cohort)

static func _deterministic_count(count: int, fraction: float, key: String) -> int:
	if count <= 0:
		return 0
	var bounded := clampf(fraction, 0.0, 1.0)
	var expected := float(count) * bounded
	var lower := int(floor(expected))
	var remainder := expected - float(lower)
	if remainder > EPSILON and _unit_interval(key) < remainder:
		lower += 1
	return clampi(lower, 0, count)

static func _conservation_ok(result: Dictionary) -> bool:
	return int(result.get("input_seed_count", -1)) == (
		int(result.get("exported_seed_count", 0))
		+ int(result.get("decayed_seed_count", 0))
		+ int(result.get("failed_germination_count", 0))
		+ int(result.get("recruited_seed_count", 0))
		+ int(result.get("seed_bank_seed_count", 0))
	)

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("source_hash", "")),
		String(result.get("lineage_id", "")),
		String(result.get("genome_checksum", "")),
		String(result.get("reproduction_event", "")),
		_vector_token(Vector2(result.get("position", Vector2.ZERO))),
		String(result.get("recruitment_traits_checksum", "")),
		String(result.get("environment_checksum", "")),
		"%.12f" % float(result.get("age_before_years", 0.0)),
		"%.12f" % float(result.get("delta_years", 0.0)),
		"%.12f" % float(result.get("age_after_years", 0.0)),
	])
	for field_name in [
		"input_seed_count", "exported_seed_count", "decayed_seed_count", "viable_after_decay_count",
		"germinated_seed_count", "recruited_seed_count", "failed_germination_count", "seed_bank_seed_count"
	]:
		tokens.append(str(int(result.get(field_name, 0))))
	for field_name in [
		"bank_survival_fraction", "seed_water_response", "temperature_response", "germination_activation",
		"germination_fraction", "light_response", "nutrient_response", "flood_survival", "establishment_fraction"
	]:
		tokens.append("%.12f" % float(result.get(field_name, 0.0)))
	tokens.append(str(bool(result.get("conservation_ok", false))))
	var recruitment := Dictionary(result.get("recruitment_cohort", {}))
	var bank := Dictionary(result.get("seed_bank_cohort", {}))
	tokens.append(String(recruitment.get("cohort_hash", "")))
	tokens.append(String(bank.get("cohort_hash", "")))
	return "\n".join(tokens).sha256_text()

static func _cohort_hash(cohort: Dictionary) -> String:
	var age := float(cohort.get("age_years", cohort.get("seed_age_years", 0.0)))
	return "|".join(PackedStringArray([
		String(cohort.get("schema", "")),
		VERSION,
		str(int(cohort.get("seed_count", 0))),
		String(cohort.get("lineage_id", "")),
		String(cohort.get("genome_checksum", "")),
		String(cohort.get("reproduction_event", "")),
		_vector_token(Vector2(cohort.get("position", Vector2.ZERO))),
		String(cohort.get("recruitment_traits_checksum", "")),
		String(cohort.get("environment_checksum", cohort.get("last_environment_checksum", ""))),
		String(cohort.get("source_hash", "")),
		"%.12f" % age,
	])).sha256_text()

static func _unit_interval(key: String) -> float:
	var value := key.sha256_text().substr(0, 12).hex_to_int()
	return float(value) / 281474976710655.0

static func _vector_token(value: Vector2) -> String:
	return "%.12f,%.12f" % [value.x, value.y]
