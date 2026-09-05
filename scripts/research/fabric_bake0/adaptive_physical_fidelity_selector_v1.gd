extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Envelope = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_envelope_v1.gd")
const SCHEMA := "planet_simulator.fabric_bake_adaptive_fidelity_decision.v1"
const POLICIES: Array[String] = ["SAFEST", "CHEAPEST_SAFE", "HOLD_IF_SAFE"]
const FIELDS: Array[String] = ["schema", "current_fidelity", "policy", "target_fidelity",
	"reason", "safety_hash", "envelope_checksum", "decision_hash", "checksum"]

static func select(envelope: Dictionary, current_fidelity: String, policy: String) -> Dictionary:
	var checked := Envelope.validate_envelope(envelope)
	if not checked.get("success", false):
		return checked
	if not POLICIES.has(policy):
		return Utils.failure("UNKNOWN_ADAPTIVE_FIDELITY_POLICY")
	if not Envelope.LEVELS.has(current_fidelity) or current_fidelity != envelope["current_fidelity"]:
		return Utils.failure("ADAPTIVE_FIDELITY_CURRENT_MISMATCH")
	var admissible: Array = envelope["admissible_fidelities"]
	var target: String = admissible[0]
	var reason := "SAFEST_AVAILABLE"
	match policy:
		"CHEAPEST_SAFE":
			# Strict comparison preserves the fixed physical-order tie break.
			for level in admissible:
				if float(envelope["estimated_cost"][level]) < float(envelope["estimated_cost"][target]):
					target = level
			reason = "LOWEST_SAFE_ESTIMATED_COST"
		"HOLD_IF_SAFE":
			if admissible.has(current_fidelity):
				target = current_fidelity
				reason = "CURRENT_REMAINS_SAFE"
			else:
				target = admissible.back()
				reason = "NEAREST_SUFFICIENT_SAFER_FIDELITY"
	if not admissible.has(target):
		return Utils.failure("UNSAFE_ADAPTIVE_FIDELITY_SELECTION")
	var decision := {"schema": SCHEMA, "current_fidelity": current_fidelity,
		"policy": policy, "target_fidelity": target, "reason": reason,
		"safety_hash": envelope["safety_hash"], "envelope_checksum": envelope["checksum"]}
	decision["decision_hash"] = Utils.canonical_hash(decision)
	decision["checksum"] = Utils.compute_checksum(decision)
	return Utils.success({"decision": decision})

static func validate_decision(decision: Dictionary, envelope: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(decision, FIELDS)
	if not checked.get("success", false):
		return checked
	for field in FIELDS:
		if typeof(decision.get(field)) != TYPE_STRING:
			return Utils.failure("INVALID_ADAPTIVE_FIDELITY_DECISION_FIELD", {"field": field})
	checked = select(envelope, decision["current_fidelity"], decision["policy"])
	if not checked.get("success", false):
		return checked
	if decision != checked["details"]["decision"]:
		return Utils.failure("ADAPTIVE_FIDELITY_DECISION_MISMATCH")
	return Utils.success()
