extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Envelope = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_envelope_v1.gd")
const Selector = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_selector_v1.gd")
const Controller = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_controller_v1.gd")
const SCHEMA := "planet_simulator.fabric_bake_adaptive_fidelity_continuity_capsule.v1"
const FIELDS: Array[String] = ["schema", "canonical", "derived", "discardable", "phase",
	"source_binding", "state", "checksum"]

static func capture(state: Dictionary) -> Dictionary:
	var checked := Controller.validate_state(state)
	if not checked.get("success", false):
		return checked
	var capsule := {"schema": SCHEMA, "canonical": false, "derived": true,
		"discardable": true, "phase": "COMMITTED", "source_binding": state["source_revision"]["checksum"],
		"state": state.duplicate(true)}
	capsule["checksum"] = Utils.compute_checksum(capsule)
	return Utils.success({"capsule": capsule})

static func validate_capsule(capsule: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(capsule, FIELDS)
	if not checked.get("success", false):
		return checked
	if typeof(capsule.get("schema")) != TYPE_STRING or capsule["schema"] != SCHEMA:
		return Utils.failure("UNSUPPORTED_ADAPTIVE_FIDELITY_CAPSULE_SCHEMA")
	for field in ["canonical", "derived", "discardable"]:
		if typeof(capsule.get(field)) != TYPE_BOOL or capsule[field] != (field != "canonical"):
			return Utils.failure("ADAPTIVE_FIDELITY_CAPSULE_MUST_BE_DISCARDABLE_DERIVED")
	if typeof(capsule.get("phase")) != TYPE_STRING or capsule["phase"] != "COMMITTED":
		return Utils.failure("UNCOMMITTED_ADAPTIVE_FIDELITY_CAPSULE")
	if typeof(capsule.get("state")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_CAPSULE_STATE")
	checked = Controller.validate_state(capsule["state"])
	if not checked.get("success", false):
		return checked
	if not Utils.is_lower_hex_64(capsule.get("source_binding")) or capsule["source_binding"] != capsule["state"]["source_revision"]["checksum"]:
		return Utils.failure("ADAPTIVE_FIDELITY_CAPSULE_SOURCE_BINDING_MISMATCH")
	return Utils.validate_checksum(capsule)

# Source and evaluation tick come from the authoritative caller; never advance or
# restore canonical revisions/epochs from this disposable optimization cache.
static func recover(source: Dictionary, candidates: Array, policy: String, config: Dictionary, tick, capsule: Dictionary = {}) -> Dictionary:
	var checked := Utils.validate_source_revision(source)
	if not checked.get("success", false):
		return checked
	if not Utils.is_json_integer(tick) or int(tick) < 1:
		return Utils.failure("INVALID_ADAPTIVE_FIDELITY_RECOVERY_TICK")
	checked = Controller.create(source, "FULL_FABRIC", config, int(tick) - 1)
	if not checked.get("success", false):
		return checked
	var state: Dictionary = checked["details"]["state"]
	checked = Envelope.compile("FULL_FABRIC", candidates)
	if not checked.get("success", false):
		return checked
	var envelope: Dictionary = checked["details"]["envelope"]
	var status := "COLD_REBUILT"
	var discard_reason := "NO_CAPSULE"
	if not capsule.is_empty():
		checked = validate_capsule(capsule)
		discard_reason = str(checked.get("error_code", ""))
		if checked.get("success", false):
			var saved: Dictionary = capsule["state"]
			if capsule["source_binding"] != source["checksum"]:
				discard_reason = "SOURCE_OR_DEPENDENCY_CHANGED"
			elif Utils.canonical_hash(saved["configuration"]) != Utils.canonical_hash(config):
				discard_reason = "HYSTERESIS_CONFIGURATION_CHANGED"
			elif not envelope["admissible_fidelities"].has(saved["current_fidelity"]):
				discard_reason = "SAVED_FIDELITY_NO_LONGER_SAFE"
			elif saved["last_evaluation_tick"] >= tick:
				discard_reason = "CAPSULE_NOT_BEFORE_AUTHORITATIVE_TICK"
			else:
				state = Controller.seal(saved)
				status = "WARM_VALIDATED"
				discard_reason = ""
		if status != "WARM_VALIDATED":
			status = "CAPSULE_DISCARDED_REBUILT"
	checked = Envelope.compile(state["current_fidelity"], candidates)
	if not checked.get("success", false):
		return checked
	envelope = checked["details"]["envelope"]
	checked = Selector.select(envelope, state["current_fidelity"], policy)
	if not checked.get("success", false):
		return checked
	var decision: Dictionary = checked["details"]["decision"]
	checked = Controller.evaluate(state, envelope, decision, tick, source)
	if not checked.get("success", false):
		return checked
	var result := {"state": checked["details"]["state"], "transition": checked["details"]["transition"],
		"envelope": envelope, "decision": decision, "capsule_status": status, "discard_reason": discard_reason}
	result["recovery_hash"] = Utils.canonical_hash(result)
	return Utils.success(result)

static func recover_json(source: Dictionary, candidates: Array, policy: String, config: Dictionary, tick, encoded: String) -> Dictionary:
	var parser := JSON.new()
	var capsule := {"corrupt_json": true}
	if parser.parse(encoded) == OK and typeof(parser.data) == TYPE_DICTIONARY:
		capsule = parser.data
	return recover(source, candidates, policy, config, tick, capsule)
