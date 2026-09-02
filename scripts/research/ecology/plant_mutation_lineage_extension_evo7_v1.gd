extends RefCounted

## ECO.EVO7 FFF2 - versioned additive extension of the SINGLE mutation lineage authority.
## Spec: docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md sections 12.1, 12.2, 19 (FFF2).
##
## AUTHORITY DISCIPLINE (G13):
##   Genome heredity is delegated 1:1 to plant_mutation_lineage_kernel_v1.reproduce(...)
##   - the v1 kernel is NOT modified and stays the only genome mutator.
##   This extension adds the FFF0-proven morphology axes (PH0 subset + EVO7 extension
##   traits) to the SAME lineage event: one reproduce entry point, one mutation seed,
##   one lineage chain (the v1 LineageRecord), keyed deterministic rolls
##   (mutation_seed | layer | axis) in canonical axis order. No RNG primitives.
##   A parallel "fast EVO7 mutator" is forbidden by the spec.

const Kernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Extension = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_mutation_lineage_extension_evo7.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-FFF2.1"

## Canonical axis order (frozen for R1): layer "ph0" bounds live in Traits.BOUNDS,
## layer "ext" bounds live in Extension.BOUNDS.
const AXES: Array[Dictionary] = [
	{"layer": "ph0", "name": "max_height_m", "step_key": "step_ph0_max_height_m"},
	{"layer": "ph0", "name": "crown_spread_m", "step_key": "step_ph0_crown_spread_m"},
	{"layer": "ph0", "name": "apical_dominance", "step_key": "step_ph0_apical_dominance"},
	{"layer": "ext", "name": "foliage_density", "step_key": "step_ext_foliage_density"},
	{"layer": "ext", "name": "leaf_economics_proxy", "step_key": "step_ext_leaf_economics_proxy"},
	{"layer": "ext", "name": "structural_investment", "step_key": "step_ext_structural_investment"},
	{"layer": "ext", "name": "root_spread_m", "step_key": "step_ext_root_spread_m"},
	{"layer": "ext", "name": "root_shoot_ratio", "step_key": "step_ext_root_shoot_ratio"},
]
const AXIS_NAMES: Array[String] = [
	"ph0:max_height_m", "ph0:crown_spread_m", "ph0:apical_dominance",
	"ext:foliage_density", "ext:leaf_economics_proxy", "ext:structural_investment",
	"ext:root_spread_m", "ext:root_shoot_ratio",
]

static func default_policy() -> Dictionary:
	var policy := {
		"genome_policy": Kernel.default_policy(),
		"morphology_probability": 0.42,
		"step_ph0_max_height_m": 0.45,
		"step_ph0_crown_spread_m": 0.45,
		"step_ph0_apical_dominance": 0.06,
		"step_ext_foliage_density": 0.06,
		"step_ext_leaf_economics_proxy": 0.06,
		"step_ext_structural_investment": 0.06,
		"step_ext_root_spread_m": 0.45,
		"step_ext_root_shoot_ratio": 0.04,
	}
	return policy

static func validate_policy(policy: Dictionary) -> Dictionary:
	if not policy.has("genome_policy"):
		return _failure("ECO_EVO7_POLICY_MISSING_GENOME_POLICY")
	if not bool(Kernel.validate_policy(policy["genome_policy"]).get("success", false)):
		return _failure("ECO_EVO7_POLICY_GENOME_POLICY_INVALID")
	var expected_keys := PackedStringArray(["genome_policy", "morphology_probability"])
	for axis in AXES:
		expected_keys.append(String(axis["step_key"]))
		if not policy.has(String(axis["step_key"])):
			return _failure("ECO_EVO7_POLICY_MISSING_STEP", {"axis": String(axis["name"])})
	if policy.keys().size() != expected_keys.size():
		return _failure("ECO_EVO7_POLICY_FIELD_COUNT")
	var probability = policy.get("morphology_probability")
	if typeof(probability) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(probability)) or float(probability) < 0.0 or float(probability) > 1.0:
		return _failure("ECO_EVO7_POLICY_PROBABILITY_RANGE")
	for axis in AXES:
		var step = policy.get(String(axis["step_key"]))
		if typeof(step) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(step)) or float(step) < 0.0:
			return _failure("ECO_EVO7_POLICY_NEGATIVE_STEP", {"axis": String(axis["name"])})
		var bounds := _bounds(axis)
		if float(step) > float(bounds[1]) - float(bounds[0]):
			return _failure("ECO_EVO7_POLICY_STEP_RANGE", {"axis": String(axis["name"])})
	return _success()

static func policy_hash(policy: Dictionary) -> String:
	if not bool(validate_policy(policy).get("success", false)):
		return ""
	var tokens := PackedStringArray([SCHEMA, VERSION, REVISION, Kernel.policy_hash(policy["genome_policy"])])
	tokens.append("morphology_probability=%.9f" % float(policy["morphology_probability"]))
	for axis in AXES:
		tokens.append("%s=%.9f" % [String(axis["step_key"]), float(policy[String(axis["step_key"])])])
	return "|".join(tokens).sha256_text()


## PERF2.4 R8 optimized preparation seam. The same canonical reproduce_bundle()
## remains the only mutation implementation. This prepares the frozen default
## policy and both canonical policy hashes once during executor setup.
static func prepare_default_reproduction_context() -> Dictionary:
	var policy := default_policy()
	if not bool(validate_policy(policy).get("success", false)):
		return {}
	var kernel_context := Kernel.prepare_default_policy_context()
	if kernel_context.is_empty():
		return {}
	var evo7_policy_id := policy_hash(policy)
	if not _is_lower_hex_64(evo7_policy_id):
		return {}
	return {
		"policy": policy,
		"evo7_policy_hash": evo7_policy_id,
		"kernel_context": kernel_context,
	}



## Ancestor bundle: one deterministic individual carrying genome v1 + PH0 traits +
## EVO7 extension traits under a single v1 lineage record.
static func create_ancestor_bundle(genome: Dictionary, dev_traits: Dictionary, ext_traits: Dictionary, lineage_seed: int) -> Dictionary:
	if not bool(Genome.validate(genome).get("success", false)):
		return {}
	if not bool(Traits.validate(dev_traits).get("success", false)):
		return {}
	if not bool(Extension.validate(ext_traits).get("success", false)):
		return {}
	var lineage := Kernel.create_ancestor(genome, lineage_seed)
	if lineage.is_empty():
		return {}
	var individual_seed := Contract.derive_individual_seed(
		String(lineage["lineage_id"]), "evo7-ancestor", 0, String(genome["version"]))
	var bundle := _bundle(genome, dev_traits, ext_traits, lineage, individual_seed)
	return bundle

## Single reproduction entry for EVO7 bundles. Genome heredity is delegated to the
## v1 kernel; morphology axes mutate inside the same lineage event via keyed rolls.
static func reproduce_bundle(
	parent_bundle: Dictionary,
	mutation_seed: int,
	offspring_index: int,
	policy: Dictionary = {},
	prepared_context: Dictionary = {}
) -> Dictionary:
	if offspring_index < 0:
		return {}
	if not bool(_validate_bundle(parent_bundle).get("success", false)):
		return {}
	var using_prepared_context := not prepared_context.is_empty()
	var effective_policy: Dictionary = (
		Dictionary(prepared_context.get("policy", {}))
		if using_prepared_context
		else (default_policy() if policy.is_empty() else policy.duplicate(true))
	)
	## Prepared mode still runs canonical validation every offspring. R8 removes
	## repeated policy creation/deep-copy and repeated canonical SHA work only.
	if not bool(validate_policy(effective_policy).get("success", false)):
		return {}

	var kernel_context: Dictionary = {}
	var evo7_policy_id := ""
	if using_prepared_context:
		kernel_context = Dictionary(prepared_context.get("kernel_context", {}))
		evo7_policy_id = String(prepared_context.get("evo7_policy_hash", ""))
		if kernel_context.is_empty() or not _is_lower_hex_64(evo7_policy_id):
			return {}

	var genome_result := Kernel.reproduce(
		parent_bundle["genome"], parent_bundle["lineage"], mutation_seed, offspring_index,
		effective_policy["genome_policy"], kernel_context)
	if genome_result.is_empty():
		return {}
	var child_genome: Dictionary = genome_result["genome"]
	var child_lineage: Dictionary = genome_result["lineage"]

	if not using_prepared_context:
		evo7_policy_id = policy_hash(effective_policy)
	var event_context := "%s|%s|%d|%d|%s" % [
		REVISION,
		String(parent_bundle["lineage"]["lineage_id"]),
		mutation_seed,
		offspring_index,
		evo7_policy_id,
	]
	var child_dev_traits: Dictionary = parent_bundle["dev_traits"].duplicate(true)
	var child_ext_traits: Dictionary = parent_bundle["ext_traits"].duplicate(true)
	var morphology_events: Array[Dictionary] = []
	var morphology_mutation_count := 0
	for axis in AXES:
		var layer := String(axis["layer"])
		var axis_name := String(axis["name"])
		var before := _axis_value(parent_bundle, layer, axis_name)
		var gate := _unit01("%s|%s|%s|gate" % [event_context, layer, axis_name])
		var signed_unit := _unit01("%s|%s|%s|delta" % [event_context, layer, axis_name]) * 2.0 - 1.0
		var step := float(effective_policy[String(axis["step_key"])])
		var mutation_selected := gate < float(effective_policy["morphology_probability"]) and step > 0.0
		var requested_delta := signed_unit * step if mutation_selected else 0.0
		var bounds := _bounds(axis)
		var after := clampf(before + requested_delta, float(bounds[0]), float(bounds[1]))
		var actual_delta := after - before
		var mutated := mutation_selected and absf(actual_delta) > 0.000000000001
		if mutated:
			morphology_mutation_count += 1
			if layer == "ph0":
				child_dev_traits[axis_name] = after
				child_dev_traits["traits_id"] = _stable_id(String(child_dev_traits["traits_id"]))
				child_dev_traits["checksum"] = Traits.compute_checksum(child_dev_traits)
			else:
				child_ext_traits[axis_name] = after
				child_ext_traits["extension_id"] = _stable_id(String(child_ext_traits["extension_id"]))
				child_ext_traits["checksum"] = Extension.compute_checksum(child_ext_traits)
		morphology_events.append({
			"layer": layer,
			"axis": axis_name,
			"mutated": mutated,
			"before": before,
			"delta": actual_delta,
			"after": after,
		})

	if not bool(Traits.validate(child_dev_traits).get("success", false)):
		return {}
	if not bool(Extension.validate(child_ext_traits).get("success", false)):
		return {}
	var child_individual_seed := Contract.derive_individual_seed(
		String(child_lineage["lineage_id"]), "evo7-repro|%d" % mutation_seed, offspring_index, String(child_genome["version"]))
	var child_bundle := _bundle(child_genome, child_dev_traits, child_ext_traits, child_lineage, child_individual_seed)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"offspring_index": offspring_index,
		"mutation_seed": mutation_seed,
		"evo7_policy_hash": evo7_policy_id,
		"kernel_result_hash": String(genome_result["result_hash"]),
		"kernel_mutation_count": int(genome_result["mutation_count"]),
		"morphology_events": morphology_events,
		"morphology_mutation_count": morphology_mutation_count,
		"parent_bundle_checksum": String(parent_bundle["bundle_checksum"]),
		"child_bundle_checksum": String(child_bundle["bundle_checksum"]),
		"bundle": child_bundle,
	}
	result["result_hash"] = _compute_result_hash(result)
	return result

static func bundle_checksum(genome: Dictionary, dev_traits: Dictionary, ext_traits: Dictionary, lineage: Dictionary, individual_seed: int) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION,
		String(genome["checksum"]), String(dev_traits["checksum"]), String(ext_traits["checksum"]),
		String(lineage["checksum"]), str(int(individual_seed)),
	])).sha256_text()

static func _bundle(genome: Dictionary, dev_traits: Dictionary, ext_traits: Dictionary, lineage: Dictionary, individual_seed: int) -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"genome": genome,
		"dev_traits": dev_traits,
		"ext_traits": ext_traits,
		"lineage": lineage,
		"individual_seed": individual_seed,
		"bundle_checksum": bundle_checksum(genome, dev_traits, ext_traits, lineage, individual_seed),
	}

static func _validate_bundle(bundle: Dictionary) -> Dictionary:
	for key in ["genome", "dev_traits", "ext_traits", "lineage", "individual_seed", "bundle_checksum"]:
		if not bundle.has(key):
			return _failure("ECO_EVO7_BUNDLE_MISSING_FIELD", {"field": key})
	if String(bundle.get("schema", "")) != SCHEMA:
		return _failure("ECO_EVO7_BUNDLE_SCHEMA_MISMATCH")
	if not bool(Genome.validate(bundle["genome"]).get("success", false)):
		return _failure("ECO_EVO7_BUNDLE_GENOME_INVALID")
	if not bool(Traits.validate(bundle["dev_traits"]).get("success", false)):
		return _failure("ECO_EVO7_BUNDLE_TRAITS_INVALID")
	if not bool(Extension.validate(bundle["ext_traits"]).get("success", false)):
		return _failure("ECO_EVO7_BUNDLE_EXTENSION_INVALID")
	var expected := bundle_checksum(bundle["genome"], bundle["dev_traits"], bundle["ext_traits"], bundle["lineage"], int(bundle["individual_seed"]))
	if String(bundle["bundle_checksum"]) != expected:
		return _failure("ECO_EVO7_BUNDLE_CHECKSUM_MISMATCH")
	return _success()

static func _axis_value(bundle: Dictionary, layer: String, axis_name: String) -> float:
	var source: Dictionary = bundle["dev_traits"] if layer == "ph0" else bundle["ext_traits"]
	return float(source[axis_name])

static func _bounds(axis: Dictionary) -> Array:
	var source: Dictionary = Traits.BOUNDS if String(axis["layer"]) == "ph0" else Extension.BOUNDS
	return source[String(axis["name"])]

## Keeps ids stable across generations: one "/e7" marker at most (checksums carry
## the real identity; ids only stay readable).
static func _stable_id(current_id: String) -> String:
	var base := current_id.split("/e7")[0]
	return base + "/e7"

static func _compute_result_hash(result: Dictionary) -> String:
	var event_tokens := PackedStringArray()
	for raw_event in Array(result.get("morphology_events", [])):
		var event: Dictionary = raw_event
		event_tokens.append("%s:%s:%s:%s:%s:%s" % [
			String(event.get("layer", "")),
			String(event.get("axis", "")),
			"1" if bool(event.get("mutated", false)) else "0",
			"%.9f" % float(event.get("before", 0.0)),
			"%.9f" % float(event.get("delta", 0.0)),
			"%.9f" % float(event.get("after", 0.0)),
		])
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, String(result.get("revision", "")),
		str(int(result.get("offspring_index", 0))),
		str(int(result.get("mutation_seed", 0))),
		String(result.get("evo7_policy_hash", "")),
		String(result.get("kernel_result_hash", "")),
		String(result.get("parent_bundle_checksum", "")),
		String(result.get("child_bundle_checksum", "")),
		str(int(result.get("morphology_mutation_count", 0))),
		";".join(event_tokens),
	])).sha256_text()

## Same keyed-roll discipline as the v1 kernel and the growth graph skeleton.
static func _unit01(key: String) -> float:
	var prefix := key.sha256_text().substr(0, 12)
	return float(prefix.hex_to_int()) / 281474976710655.0

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
