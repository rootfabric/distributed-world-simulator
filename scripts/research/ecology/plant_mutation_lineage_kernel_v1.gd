extends RefCounted

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const LineageRecord = preload("res://scripts/research/ecology/plant_lineage_record_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_mutation_lineage_kernel.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1B-S1.1"
const MUTABLE_TRAITS: Array[String] = [
	"water_preference",
	"root_depth_m",
	"growth_rate",
	"shade_tolerance",
	"seed_dispersal_distance_m",
]
const POLICY_KEYS: Array[String] = [
	"mutation_probability",
	"water_preference_step",
	"root_depth_m_step",
	"growth_rate_step",
	"shade_tolerance_step",
	"seed_dispersal_distance_m_step",
]
const TRAIT_MIN := {
	"water_preference": 0.0,
	"root_depth_m": 0.05,
	"growth_rate": 0.0,
	"shade_tolerance": 0.0,
	"seed_dispersal_distance_m": 0.0,
}
const TRAIT_MAX := {
	"water_preference": 1.0,
	"root_depth_m": 20.0,
	"growth_rate": 1.0,
	"shade_tolerance": 1.0,
	"seed_dispersal_distance_m": 100000.0,
}
const TRAIT_STEP_KEY := {
	"water_preference": "water_preference_step",
	"root_depth_m": "root_depth_m_step",
	"growth_rate": "growth_rate_step",
	"shade_tolerance": "shade_tolerance_step",
	"seed_dispersal_distance_m": "seed_dispersal_distance_m_step",
}
const RESULT_FIELDS: Array[String] = [
	"schema",
	"version",
	"experiment_revision",
	"offspring_index",
	"mutation_seed",
	"policy_hash",
	"parent_genome_checksum",
	"child_genome_checksum",
	"parent_lineage_checksum",
	"child_lineage_checksum",
	"mutation_event_hash",
	"mutation_count",
	"events",
	"genome",
	"lineage",
	"result_hash",
]


static func default_policy() -> Dictionary:
	return {
		"mutation_probability": 0.42,
		"water_preference_step": 0.08,
		"root_depth_m_step": 0.30,
		"growth_rate_step": 0.08,
		"shade_tolerance_step": 0.08,
		"seed_dispersal_distance_m_step": 3.0,
	}


static func validate_policy(policy: Dictionary) -> Dictionary:
	if policy.keys().size() != POLICY_KEYS.size():
		return _failure("ECO_P1B_MUTATION_POLICY_FIELD_COUNT")
	for key in POLICY_KEYS:
		if not policy.has(key):
			return _failure("ECO_P1B_MUTATION_POLICY_MISSING", {"field": key})
		if typeof(policy[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(policy[key])):
			return _failure("ECO_P1B_MUTATION_POLICY_NON_FINITE", {"field": key})
	var probability := float(policy["mutation_probability"])
	if probability < 0.0 or probability > 1.0:
		return _failure("ECO_P1B_MUTATION_POLICY_PROBABILITY_RANGE")
	for key in POLICY_KEYS:
		if key == "mutation_probability":
			continue
		if float(policy[key]) < 0.0:
			return _failure("ECO_P1B_MUTATION_POLICY_NEGATIVE_STEP", {"field": key})
	var step_limits := {
		"water_preference_step": 1.0,
		"root_depth_m_step": 20.0,
		"growth_rate_step": 1.0,
		"shade_tolerance_step": 1.0,
		"seed_dispersal_distance_m_step": 100000.0,
	}
	for key in step_limits.keys():
		if float(policy[key]) > float(step_limits[key]):
			return _failure("ECO_P1B_MUTATION_POLICY_STEP_RANGE", {"field": key})
	return _success()


static func policy_hash(policy: Dictionary) -> String:
	if not bool(validate_policy(policy).get("success", false)):
		return ""
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION])
	for key in POLICY_KEYS:
		tokens.append("%s=%s" % [key, _format_float(float(policy[key]))])
	return "|".join(tokens).sha256_text()


static func create_ancestor(genome: Dictionary, lineage_seed: int) -> Dictionary:
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	return LineageRecord.create_ancestor(genome, lineage_seed)


static func reproduce(
	parent_genome: Dictionary,
	parent_lineage: Dictionary,
	mutation_seed: int,
	offspring_index: int,
	policy: Dictionary = {}
) -> Dictionary:
	var effective_policy := default_policy() if policy.is_empty() else policy.duplicate(true)
	if offspring_index < 0:
		return {}
	if not bool(PlantGenome.validate(parent_genome).get("success", false)):
		return {}
	if not bool(LineageRecord.validate(parent_lineage).get("success", false)):
		return {}
	if String(parent_lineage.get("genome_checksum", "")) != String(parent_genome.get("checksum", "")):
		return {}
	if not bool(validate_policy(effective_policy).get("success", false)):
		return {}

	var policy_id := policy_hash(effective_policy)
	var generation := int(parent_lineage.get("generation", 0)) + 1
	var event_context := "%s|%s|%s|%d|%d|%d|%s" % [
		EXPERIMENT_REVISION,
		String(parent_lineage.get("lineage_id", "")),
		String(parent_lineage.get("individual_id", "")),
		generation,
		offspring_index,
		mutation_seed,
		policy_id,
	]
	var traits := _trait_snapshot(parent_genome)
	var events: Array[Dictionary] = []
	var mutation_count := 0
	for trait_name in MUTABLE_TRAITS:
		var before := float(traits[trait_name])
		var gate := _unit01("%s|%s|gate" % [event_context, trait_name])
		var signed_unit := _unit01("%s|%s|delta" % [event_context, trait_name]) * 2.0 - 1.0
		var step := float(effective_policy[TRAIT_STEP_KEY[trait_name]])
		var mutation_selected := gate < float(effective_policy["mutation_probability"]) and step > 0.0
		var requested_delta := signed_unit * step if mutation_selected else 0.0
		var after := clampf(before + requested_delta, float(TRAIT_MIN[trait_name]), float(TRAIT_MAX[trait_name]))
		var actual_delta := after - before
		var mutated := mutation_selected and absf(actual_delta) > 0.000000000001
		if mutated:
			mutation_count += 1
		traits[trait_name] = after
		events.append({
			"trait": trait_name,
			"mutated": mutated,
			"before": before,
			"delta": actual_delta,
			"after": after,
		})

	var event_hash := _mutation_event_hash(event_context, events)
	var child_genome := parent_genome.duplicate(true)
	if mutation_count > 0:
		child_genome = _build_genome_from_traits(parent_genome, traits)
	if not bool(PlantGenome.validate(child_genome).get("success", false)):
		return {}
	var child_lineage := LineageRecord.create_descendant(
		parent_lineage,
		String(child_genome.get("checksum", "")),
		offspring_index,
		mutation_seed,
		event_hash
	)
	if not bool(LineageRecord.validate(child_lineage).get("success", false)):
		return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"offspring_index": offspring_index,
		"mutation_seed": mutation_seed,
		"policy_hash": policy_id,
		"parent_genome_checksum": String(parent_genome.get("checksum", "")),
		"child_genome_checksum": String(child_genome.get("checksum", "")),
		"parent_lineage_checksum": String(parent_lineage.get("checksum", "")),
		"child_lineage_checksum": String(child_lineage.get("checksum", "")),
		"mutation_event_hash": event_hash,
		"mutation_count": mutation_count,
		"events": events,
		"genome": child_genome,
		"lineage": child_lineage,
	}
	result["result_hash"] = compute_result_hash(result)
	return result


static func validate_result(result: Dictionary) -> Dictionary:
	if result.keys().size() != RESULT_FIELDS.size():
		return _failure("ECO_P1B_MUTATION_RESULT_FIELD_COUNT")
	for field_name in RESULT_FIELDS:
		if not result.has(field_name):
			return _failure("ECO_P1B_MUTATION_RESULT_MISSING", {"field": field_name})
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION:
		return _failure("ECO_P1B_MUTATION_RESULT_SCHEMA_OR_VERSION")
	if String(result.get("experiment_revision", "")) != EXPERIMENT_REVISION:
		return _failure("ECO_P1B_MUTATION_RESULT_REVISION")
	if typeof(result.get("offspring_index")) != TYPE_INT or int(result.get("offspring_index")) < 0:
		return _failure("ECO_P1B_MUTATION_RESULT_OFFSPRING_INDEX")
	if typeof(result.get("mutation_seed")) != TYPE_INT:
		return _failure("ECO_P1B_MUTATION_RESULT_SEED")
	if typeof(result.get("mutation_count")) != TYPE_INT or int(result.get("mutation_count")) < 0 or int(result.get("mutation_count")) > MUTABLE_TRAITS.size():
		return _failure("ECO_P1B_MUTATION_RESULT_COUNT")
	var genome: Dictionary = result.get("genome", {})
	var lineage: Dictionary = result.get("lineage", {})
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return _failure("ECO_P1B_MUTATION_RESULT_GENOME_INVALID")
	if not bool(LineageRecord.validate(lineage).get("success", false)):
		return _failure("ECO_P1B_MUTATION_RESULT_LINEAGE_INVALID")
	if String(genome.get("checksum", "")) != String(result.get("child_genome_checksum", "")):
		return _failure("ECO_P1B_MUTATION_RESULT_GENOME_CHECKSUM_MISMATCH")
	if String(lineage.get("checksum", "")) != String(result.get("child_lineage_checksum", "")):
		return _failure("ECO_P1B_MUTATION_RESULT_LINEAGE_CHECKSUM_MISMATCH")
	if String(lineage.get("genome_checksum", "")) != String(result.get("child_genome_checksum", "")):
		return _failure("ECO_P1B_MUTATION_RESULT_LINEAGE_GENOME_MISMATCH")
	if String(lineage.get("parent_genome_checksum", "")) != String(result.get("parent_genome_checksum", "")):
		return _failure("ECO_P1B_MUTATION_RESULT_PARENT_GENOME_MISMATCH")
	for hash_field in ["policy_hash", "mutation_event_hash", "result_hash"]:
		if not _is_lower_hex_64(String(result.get(hash_field, ""))):
			return _failure("ECO_P1B_MUTATION_RESULT_INVALID_HASH", {"field": hash_field})
	var events: Array = result.get("events", [])
	if events.size() != MUTABLE_TRAITS.size():
		return _failure("ECO_P1B_MUTATION_RESULT_EVENT_COUNT")
	var counted_mutations := 0
	for index in range(MUTABLE_TRAITS.size()):
		var event: Dictionary = events[index]
		var trait_name := MUTABLE_TRAITS[index]
		if String(event.get("trait", "")) != trait_name:
			return _failure("ECO_P1B_MUTATION_RESULT_EVENT_ORDER")
		for key in ["before", "delta", "after"]:
			if typeof(event.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(event.get(key))):
				return _failure("ECO_P1B_MUTATION_RESULT_EVENT_NUMBER", {"field": key})
		if absf(float(event["before"]) + float(event["delta"]) - float(event["after"])) > 0.000000001:
			return _failure("ECO_P1B_MUTATION_RESULT_EVENT_ARITHMETIC", {"trait": trait_name})
		if float(event["after"]) < float(TRAIT_MIN[trait_name]) - 0.000000001 or float(event["after"]) > float(TRAIT_MAX[trait_name]) + 0.000000001:
			return _failure("ECO_P1B_MUTATION_RESULT_EVENT_RANGE", {"trait": trait_name})
		if bool(event.get("mutated", false)):
			counted_mutations += 1
	if counted_mutations != int(result.get("mutation_count", -1)):
		return _failure("ECO_P1B_MUTATION_RESULT_COUNT_MISMATCH")
	var event_context := "%s|%s|%s|%d|%d|%d|%s" % [
		EXPERIMENT_REVISION,
		String(lineage.get("lineage_id", "")),
		String(lineage.get("parent_individual_id", "")),
		int(lineage.get("generation", 0)),
		int(result.get("offspring_index", 0)),
		int(result.get("mutation_seed", 0)),
		String(result.get("policy_hash", "")),
	]
	if String(result.get("mutation_event_hash", "")) != _mutation_event_hash(event_context, events):
		return _failure("ECO_P1B_MUTATION_RESULT_EVENT_HASH_MISMATCH")
	if String(lineage.get("mutation_event_hash", "")) != String(result.get("mutation_event_hash", "")):
		return _failure("ECO_P1B_MUTATION_RESULT_LINEAGE_EVENT_HASH_MISMATCH")
	if String(result.get("result_hash", "")) != compute_result_hash(result):
		return _failure("ECO_P1B_MUTATION_RESULT_HASH_MISMATCH")
	return _success()


static func compute_result_hash(result: Dictionary) -> String:
	var event_tokens := PackedStringArray()
	for raw_event in Array(result.get("events", [])):
		var event: Dictionary = raw_event
		event_tokens.append("%s:%s:%s:%s:%s" % [
			String(event.get("trait", "")),
			"1" if bool(event.get("mutated", false)) else "0",
			_format_float(float(event.get("before", 0.0))),
			_format_float(float(event.get("delta", 0.0))),
			_format_float(float(event.get("after", 0.0))),
		])
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("experiment_revision", "")),
		str(int(result.get("offspring_index", 0))),
		str(int(result.get("mutation_seed", 0))),
		String(result.get("policy_hash", "")),
		String(result.get("parent_genome_checksum", "")),
		String(result.get("child_genome_checksum", "")),
		String(result.get("parent_lineage_checksum", "")),
		String(result.get("child_lineage_checksum", "")),
		String(result.get("mutation_event_hash", "")),
		str(int(result.get("mutation_count", 0))),
		";".join(event_tokens),
	])).sha256_text()


static func population_hash(results: Array) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, "population"])
	for raw_result in results:
		var result: Dictionary = raw_result
		tokens.append(String(result.get("result_hash", "")))
	return "|".join(tokens).sha256_text()


static func _trait_snapshot(genome: Dictionary) -> Dictionary:
	return {
		"height_m": float(genome.get("height_m", 0.0)),
		"growth_rate": float(genome.get("growth_rate", 0.0)),
		"root_depth_m": float(genome.get("root_depth_m", 0.0)),
		"water_preference": float(genome.get("water_preference", 0.0)),
		"water_tolerance_width": float(genome.get("water_tolerance_width", 0.0)),
		"shade_tolerance": float(genome.get("shade_tolerance", 0.0)),
		"seed_count": int(genome.get("seed_count", 0)),
		"seed_dispersal_distance_m": float(genome.get("seed_dispersal_distance_m", 0.0)),
		"lifespan_years": float(genome.get("lifespan_years", 0.0)),
	}


static func _build_genome_from_traits(parent: Dictionary, traits: Dictionary) -> Dictionary:
	var genotype_payload := "|".join(PackedStringArray([
		EXPERIMENT_REVISION,
		_format_float(float(traits["height_m"])),
		_format_float(float(traits["growth_rate"])),
		_format_float(float(traits["root_depth_m"])),
		_format_float(float(traits["water_preference"])),
		_format_float(float(traits["water_tolerance_width"])),
		_format_float(float(traits["shade_tolerance"])),
		str(int(traits["seed_count"])),
		_format_float(float(traits["seed_dispersal_distance_m"])),
		_format_float(float(traits["lifespan_years"])),
	]))
	var genotype_id := "plant-genome/p1b/%s" % genotype_payload.sha256_text().substr(0, 24)
	return PlantGenome.create(
		genotype_id,
		float(traits["height_m"]),
		float(traits["growth_rate"]),
		float(traits["root_depth_m"]),
		float(traits["water_preference"]),
		float(traits["water_tolerance_width"]),
		float(traits["shade_tolerance"]),
		int(traits["seed_count"]),
		float(traits["seed_dispersal_distance_m"]),
		float(traits["lifespan_years"])
	)


static func _mutation_event_hash(context: String, events: Array[Dictionary]) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, context])
	for event in events:
		tokens.append("%s:%s:%s:%s:%s" % [
			String(event["trait"]),
			"1" if bool(event["mutated"]) else "0",
			_format_float(float(event["before"])),
			_format_float(float(event["delta"])),
			_format_float(float(event["after"])),
		])
	return "|".join(tokens).sha256_text()


static func _unit01(key: String) -> float:
	var prefix := key.sha256_text().substr(0, 12)
	return float(prefix.hex_to_int()) / 281474976710655.0


static func _format_float(value: float) -> String:
	return "%.9f" % value


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in [
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"a", "b", "c", "d", "e", "f",
		]:
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
