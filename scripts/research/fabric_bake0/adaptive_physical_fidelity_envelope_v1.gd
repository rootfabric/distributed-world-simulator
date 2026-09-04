extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_adaptive_physical_fidelity_envelope.v1"
const LEVELS: Array[String] = [
	"FULL_FABRIC",
	"STRUCTURAL_BAKE",
	"DYNAMIC_ROM",
	"HYBRID_BAKE",
	"DORMANT",
]
const CANDIDATE_FIELDS: Array[String] = [
	"fidelity_id",
	"available",
	"source_fresh",
	"reconstruction_ready",
	"passive_stable",
	"error_bound",
	"allowed_error_bound",
	"validity_margin",
	"guard_margin",
	"pending_refinement_guards",
	"causal_dependencies",
	"dormancy_certified",
	"estimated_cost",
]
const ENVELOPE_FIELDS: Array[String] = [
	"schema",
	"current_fidelity",
	"levels",
	"admissible_fidelities",
	"minimum_safe_fidelity",
	"raw_admissibility",
	"estimated_cost",
	"error_bound",
	"validity_margin",
	"guard_margin",
	"pending_refinement_guards",
	"causal_dependencies",
	"safety_hash",
	"checksum",
]

static func compile(current_fidelity: String, candidates: Array) -> Dictionary:
	var checked := _validate_candidates(current_fidelity, candidates)
	if not bool(checked.get("success", false)):
		return checked

	var raw_rows: Array = []
	var admissible: Array = []
	var cost_by_level: Dictionary = {}
	var error_by_level: Dictionary = {}
	var validity_by_level: Dictionary = {}
	var guard_by_level: Dictionary = {}
	var pending_by_level: Dictionary = {}
	var causal_by_level: Dictionary = {}
	var unsafe_barrier := false

	for index in range(LEVELS.size()):
		var fidelity_id := LEVELS[index]
		var candidate: Dictionary = candidates[index]
		var reasons := _raw_rejection_reasons(index, candidate)
		var raw_safe := reasons.is_empty()
		var effective_reasons: Array = reasons.duplicate()
		if unsafe_barrier and raw_safe:
			effective_reasons.append("CHEAPER_THAN_UNSAFE_BARRIER")
		var effective_safe := raw_safe and not unsafe_barrier
		if not raw_safe:
			unsafe_barrier = true
		if effective_safe:
			admissible.append(fidelity_id)
		raw_rows.append({
			"fidelity_id": fidelity_id,
			"raw_safe": raw_safe,
			"effective_safe": effective_safe,
			"rejection_reasons": effective_reasons,
		})
		cost_by_level[fidelity_id] = float(candidate["estimated_cost"])
		error_by_level[fidelity_id] = float(candidate["error_bound"])
		validity_by_level[fidelity_id] = float(candidate["validity_margin"])
		guard_by_level[fidelity_id] = float(candidate["guard_margin"])
		pending_by_level[fidelity_id] = candidate["pending_refinement_guards"].duplicate()
		causal_by_level[fidelity_id] = candidate["causal_dependencies"].duplicate()

	if admissible.is_empty() or String(admissible[0]) != "FULL_FABRIC":
		return Utils.failure("NO_SAFE_PHYSICAL_FIDELITY", {
			"current_fidelity": current_fidelity,
			"raw_admissibility": raw_rows,
		})

	var minimum_safe_fidelity := String(admissible[admissible.size() - 1])
	var safety_payload := {
		"schema": SCHEMA,
		"current_fidelity": current_fidelity,
		"levels": LEVELS.duplicate(),
		"admissible_fidelities": admissible.duplicate(),
		"minimum_safe_fidelity": minimum_safe_fidelity,
		"raw_admissibility": raw_rows,
		"error_bound": error_by_level,
		"validity_margin": validity_by_level,
		"guard_margin": guard_by_level,
		"pending_refinement_guards": pending_by_level,
		"causal_dependencies": causal_by_level,
	}
	var envelope: Dictionary = safety_payload.duplicate(true)
	envelope["estimated_cost"] = cost_by_level
	envelope["safety_hash"] = Utils.canonical_hash(safety_payload)
	envelope["checksum"] = ""
	envelope["checksum"] = Utils.compute_checksum(envelope)
	checked = validate_envelope(envelope)
	if not bool(checked.get("success", false)):
		return checked
	return Utils.success({"envelope": envelope})

static func validate_envelope(envelope: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(envelope, ENVELOPE_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if envelope.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_ADAPTIVE_FIDELITY_ENVELOPE_SCHEMA")
	if typeof(envelope.get("levels")) != TYPE_ARRAY or Array(envelope["levels"]) != LEVELS:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_LEVELS")
	if typeof(envelope.get("current_fidelity")) != TYPE_STRING or not LEVELS.has(String(envelope["current_fidelity"])):
		return Utils.failure("INVALID_CURRENT_PHYSICAL_FIDELITY")
	if typeof(envelope.get("admissible_fidelities")) != TYPE_ARRAY or envelope["admissible_fidelities"].is_empty():
		return Utils.failure("EMPTY_ADMISSIBLE_PHYSICAL_FIDELITY_SET")
	var admissible: Array = envelope["admissible_fidelities"]
	for index in range(admissible.size()):
		if index >= LEVELS.size() or String(admissible[index]) != LEVELS[index]:
			return Utils.failure("NONCONTIGUOUS_ADMISSIBLE_PHYSICAL_FIDELITY_SET")
	if String(envelope.get("minimum_safe_fidelity", "")) != String(admissible[admissible.size() - 1]):
		return Utils.failure("INVALID_MINIMUM_SAFE_PHYSICAL_FIDELITY")
	if typeof(envelope.get("raw_admissibility")) != TYPE_ARRAY or envelope["raw_admissibility"].size() != LEVELS.size():
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_ADMISSIBILITY_ROWS")
	for index in range(LEVELS.size()):
		var row = envelope["raw_admissibility"][index]
		if typeof(row) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_ADMISSIBILITY_ROW", {"index": index})
		if row.keys().size() != 4 or not row.has_all(["fidelity_id", "raw_safe", "effective_safe", "rejection_reasons"]):
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_ADMISSIBILITY_ROW", {"index": index})
		if String(row["fidelity_id"]) != LEVELS[index] or typeof(row["raw_safe"]) != TYPE_BOOL or typeof(row["effective_safe"]) != TYPE_BOOL:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_ADMISSIBILITY_ROW", {"index": index})
		if typeof(row["rejection_reasons"]) != TYPE_ARRAY:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_ADMISSIBILITY_ROW", {"index": index})
	for field in ["estimated_cost", "error_bound", "validity_margin", "guard_margin", "pending_refinement_guards", "causal_dependencies"]:
		if typeof(envelope.get(field)) != TYPE_DICTIONARY or envelope[field].size() != LEVELS.size():
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_REPORT_FIELD", {"field": field})
		for fidelity_id in LEVELS:
			if not envelope[field].has(fidelity_id):
				return Utils.failure("INVALID_ADAPTIVE_FIDELITY_REPORT_FIELD", {"field": field, "fidelity_id": fidelity_id})
	if not Utils.is_lower_hex_64(envelope.get("safety_hash")):
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_SAFETY_HASH")
	var safety_payload := envelope.duplicate(true)
	safety_payload.erase("estimated_cost")
	safety_payload.erase("safety_hash")
	safety_payload.erase("checksum")
	if String(envelope["safety_hash"]) != Utils.canonical_hash(safety_payload):
		return Utils.failure("ADAPTIVE_FIDELITY_SAFETY_HASH_MISMATCH")
	return Utils.validate_checksum(envelope)

static func _validate_candidates(current_fidelity: String, candidates: Array) -> Dictionary:
	if not LEVELS.has(current_fidelity):
		return Utils.failure("INVALID_CURRENT_PHYSICAL_FIDELITY", {"current_fidelity": current_fidelity})
	if candidates.size() != LEVELS.size():
		return Utils.failure("ADAPTIVE_FIDELITY_COMPLETE_LEVEL_SET_REQUIRED", {"count": candidates.size()})
	for index in range(LEVELS.size()):
		if typeof(candidates[index]) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CANDIDATE", {"index": index})
		var candidate: Dictionary = candidates[index]
		var checked := Utils.validate_exact_fields(candidate, CANDIDATE_FIELDS)
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CANDIDATE", {"index": index, "cause": checked})
		if String(candidate.get("fidelity_id", "")) != LEVELS[index]:
			return Utils.failure("ADAPTIVE_FIDELITY_LEVEL_ORDER_MISMATCH", {
				"index": index,
				"expected": LEVELS[index],
				"actual": candidate.get("fidelity_id"),
			})
		for field in ["available", "source_fresh", "reconstruction_ready", "passive_stable", "dormancy_certified"]:
			if typeof(candidate.get(field)) != TYPE_BOOL:
				return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CANDIDATE_BOOL", {"index": index, "field": field})
		for field in ["error_bound", "allowed_error_bound", "estimated_cost"]:
			if not Utils.is_non_negative_number(candidate.get(field)):
				return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CANDIDATE_NUMBER", {"index": index, "field": field})
		for field in ["validity_margin", "guard_margin"]:
			if not Utils.is_finite_number(candidate.get(field)):
				return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CANDIDATE_NUMBER", {"index": index, "field": field})
		for field in ["pending_refinement_guards", "causal_dependencies"]:
			checked = Utils.validate_sorted_unique_strings(candidate.get(field), true)
			if not bool(checked.get("success", false)):
				return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CANDIDATE_IDS", {"index": index, "field": field, "cause": checked})
			for item_id in candidate[field]:
				if not Utils.is_canonical_id(item_id, 2):
					return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CANDIDATE_ID", {"index": index, "field": field, "id": item_id})
	return Utils.success()

static func _raw_rejection_reasons(level_index: int, candidate: Dictionary) -> Array:
	var reasons: Array = []
	if not bool(candidate["available"]):
		reasons.append("UNAVAILABLE")
	if not bool(candidate["source_fresh"]):
		reasons.append("STALE_SOURCE")
	if level_index == 0:
		return reasons
	if not bool(candidate["reconstruction_ready"]):
		reasons.append("RECONSTRUCTION_NOT_READY")
	if not bool(candidate["passive_stable"]):
		reasons.append("PASSIVITY_UNCERTIFIED")
	if float(candidate["error_bound"]) > float(candidate["allowed_error_bound"]):
		reasons.append("ERROR_BOUND_EXCEEDED")
	if float(candidate["validity_margin"]) <= 0.0:
		reasons.append("VALIDITY_MARGIN_EXHAUSTED")
	if float(candidate["guard_margin"]) <= 0.0:
		reasons.append("GUARD_MARGIN_EXHAUSTED")
	if not candidate["pending_refinement_guards"].is_empty():
		reasons.append("REFINEMENT_GUARD_PENDING")
	if level_index == 4:
		if not bool(candidate["dormancy_certified"]):
			reasons.append("DORMANCY_UNCERTIFIED")
		if not candidate["causal_dependencies"].is_empty():
			reasons.append("CAUSAL_DEPENDENCY_ACTIVE")
	return reasons
