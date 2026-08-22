extends RefCounted

## EG4.5 SIM-SIDE synthetic effect journal (tools/network = sim-side only).
##
## One journal per world authority: records SYNTHETIC cross-world interaction
## effects keyed by CWIP operation_id with EXACTLY-ONCE semantics:
##   - first commit of an operation applies the effect and advances the
##     per-authority canonical_effect_revision counter;
##   - any re-commit of the same operation id is an idempotent replay that
##     returns the PRIOR committed result without touching the counter;
##   - a rejected commit records the rejection explicitly and leaves NO
##     partial effect behind.
##
## product_canonical_mutation_allowed=false is ENFORCED here: every stored
## effect payload must carry the synthetic flag set to false (meaning "this
## effect never mutates product canonical truth"), and commits claiming
## otherwise are refused. This journal lives entirely sim-side; the EG4.5
## gateway router never sees or owns it.

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const EffectRequestScript = preload("res://scripts/network/gateway/effect_commit_request.gd")
const EffectResultScript = preload("res://scripts/network/gateway/effect_commit_result.gd")

const SCHEMA := "planet_simulator.eg45_synthetic_effect_journal.v1"
const SYNTHETIC_FLAG_FIELD := "product_canonical_mutation_allowed"

var _authority_id := ""
var _authority_epoch: int = 0
var _next_canonical_effect_revision: int = 1
# operation_id -> {"request": Dict, "effect": Dict, "result": Dict, "canonical_effect_revision": int}
var _committed_by_operation: Dictionary = {}
# operation_id -> {"reason": String, "request_digest": String}
var _rejected_by_operation: Dictionary = {}
# Optional sim-side domain validation hook: Callable(effect_payload) -> {"allowed": bool, "reason": String}
var _domain_validator: Callable = Callable()
var _counters := {
	"commits_received": 0,
	"applied": 0,
	"duplicate_replays": 0,
	"rejected": 0,
}


func configure(authority_id: String, authority_epoch: int) -> Dictionary:
	var id_check: Dictionary = GatewayUtilsScript.require_id(
			{"authority_id": authority_id}, "authority_id", "authority")
	if not bool(id_check.get("success", false)):
		return _failure("INVALID_AUTHORITY_ID", {})
	if authority_epoch < 1:
		return _failure("INVALID_AUTHORITY_EPOCH", {})
	if not _committed_by_operation.is_empty():
		return _failure("ALREADY_CONFIGURED", {})
	_authority_id = authority_id
	_authority_epoch = int(authority_epoch)
	return _success({})


## Optional per-authority domain validation hook (sim-owned): when installed,
## every FIRST-TIME commit payload must pass it before the effect is applied.
func set_domain_validator(validator: Callable) -> void:
	_domain_validator = validator


func authority_id() -> String:
	return _authority_id


func authority_epoch() -> int:
	return _authority_epoch


## Commit one validated-or-not EffectCommitRequest. Fail-closed on contract
## violations; idempotent on repeated operation ids (prior result wins).
func commit(request: Dictionary) -> Dictionary:
	_counters["commits_received"] = int(_counters["commits_received"]) + 1
	var request_check: Dictionary = EffectRequestScript.validate(request)
	if not bool(request_check.get("success", false)):
		return _failure("CONTRACT_VIOLATION", {
			"underlying_error": String(request_check.get("error_code", "")),
			"message": String(request_check.get("message", "")),
		})
	var operation_id := String(request.get("operation_id"))
	if String(request.get("target_authority")) != _authority_id:
		return _failure("WRONG_JOURNAL", {
			"expected": _authority_id,
			"received": String(request.get("target_authority")),
		})
	# Exactly-once: a known operation ALWAYS replays its prior outcome.
	if _committed_by_operation.has(operation_id):
		var entry: Dictionary = _committed_by_operation[operation_id]
		_counters["duplicate_replays"] = int(_counters["duplicate_replays"]) + 1
		return _success({
			"status": "DUPLICATE_REPLAY",
			"result": Dictionary(entry["result"]).duplicate(true),
			"canonical_effect_revision": int(entry["canonical_effect_revision"]),
			"applied_now": false,
		})
	var effect_payload_value: Variant = request.get("effect_payload")
	if typeof(effect_payload_value) != TYPE_DICTIONARY:
		return _failure("CONTRACT_VIOLATION", {"underlying_error": "INVALID_PAYLOAD"})
	var effect_payload: Dictionary = Dictionary(effect_payload_value).duplicate(true)
	var synthetic_flag: Variant = effect_payload.get(SYNTHETIC_FLAG_FIELD)
	if typeof(synthetic_flag) != TYPE_BOOL or bool(synthetic_flag):
		_counters["rejected"] = int(_counters["rejected"]) + 1
		_rejected_by_operation[operation_id] = {
			"reason": "SYNTHETIC_FLAG_REQUIRED",
			"request_digest": String(NetworkUtilsScript.payload_hash(request)),
		}
		return _failure("SYNTHETIC_FLAG_REQUIRED", {
			"detail": "%s must be exactly false on every synthetic effect commit" % SYNTHETIC_FLAG_FIELD,
		})
	if _domain_validator.is_valid():
		var verdict: Dictionary = Dictionary(_domain_validator.call(effect_payload))
		if not bool(verdict.get("allowed", false)):
			var reason := String(verdict.get("reason", "DOMAIN_VALIDATION_REJECTED"))
			_counters["rejected"] = int(_counters["rejected"]) + 1
			_rejected_by_operation[operation_id] = {
				"reason": reason,
				"request_digest": String(NetworkUtilsScript.payload_hash(request)),
			}
			return _failure(reason, {"detail": "target authority domain validation refused the effect"})
	var canonical_effect_revision := _next_canonical_effect_revision
	var result: Dictionary = EffectResultScript.create(
			String(request.get("interaction_id")),
			operation_id,
			"COMMITTED",
			canonical_effect_revision,
			_authority_epoch)
	var result_check: Dictionary = EffectResultScript.validate(result)
	if not bool(result_check.get("success", false)):
		return _failure(String(result_check.get("error_code", "INVALID_RESULT")), {})
	_committed_by_operation[operation_id] = {
		"request": request.duplicate(true),
		"effect": effect_payload,
		"result": result.duplicate(true),
		"canonical_effect_revision": canonical_effect_revision,
	}
	_next_canonical_effect_revision += 1
	_counters["applied"] = int(_counters["applied"]) + 1
	return _success({
		"status": "APPLIED",
		"result": result.duplicate(true),
		"canonical_effect_revision": canonical_effect_revision,
		"applied_now": true,
	})


## Build the REJECTED EffectCommitResult shape for an explicit refusal so the
## gateway can relay a well-formed negative result (no partial effect exists).
func build_rejected_result(interaction_id: String, operation_id: String) -> Dictionary:
	return EffectResultScript.create(interaction_id, operation_id, "REJECTED", null, _authority_epoch)


func has_effect(operation_id: String) -> bool:
	return _committed_by_operation.has(operation_id)


func effect(operation_id: String) -> Dictionary:
	var entry_value: Variant = _committed_by_operation.get(operation_id, {})
	var entry: Dictionary = entry_value if entry_value is Dictionary else {}
	return Dictionary(entry.get("effect", {})).duplicate(true)


func result_for(operation_id: String) -> Dictionary:
	var entry_value: Variant = _committed_by_operation.get(operation_id, {})
	var entry: Dictionary = entry_value if entry_value is Dictionary else {}
	return Dictionary(entry.get("result", {})).duplicate(true)


func effect_count() -> int:
	return _committed_by_operation.size()


func applied_operations() -> Array[String]:
	var output: Array[String] = []
	for key in _committed_by_operation.keys():
		output.append(String(key))
	output.sort()
	return output


func rejection_reason(operation_id: String) -> String:
	var entry_value: Variant = _rejected_by_operation.get(operation_id, {})
	var entry: Dictionary = entry_value if entry_value is Dictionary else {}
	return String(entry.get("reason", ""))


func next_canonical_effect_revision() -> int:
	return _next_canonical_effect_revision


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"synthetic_only": true,
		"effect_count": _committed_by_operation.size(),
		"applied_operations": applied_operations(),
		"rejected_operations": _rejected_by_operation.keys().size(),
		"counters": _counters.duplicate(true),
	}


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	var envelope := {"success": false, "error_code": error_code, "details": details}
	return envelope
