extends RefCounted

## P6.6 gateway-ready command routing.
##
## Routes player commands through the accepted Edge Gateway Foundation
## transport/session stack so the SAME domain entry points produce identical
## canonical state regardless of whether commands arrive DIRECT or via the
## GATEWAY path proven by EG1-EG5.
##
## This is the PRODUCT-level consumption of EDGE_GATEWAY_FOUNDATION_ACCEPTED:
## the ownership map's GATEWAY_ONLY transport_path invariant becomes real here.

const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")

const SCHEMA := "planet_simulator.p6_gateway_command_route.v1"

var _registry = null
var _ledger = null
var _admission = null
var _adapter = null
var _handler = null
var _counters := {
	"routed": 0,
	"executed": 0,
	"rejected": 0,
	"replayed": 0,
}


func configure(p_registry, p_ledger, p_admission, p_adapter, p_handler) -> Dictionary:
	if p_registry == null or not p_registry.has_method("resolve_by_session"):
		return _failure("INVALID_IDENTITY_REGISTRY", {})
	if p_admission == null or not p_admission.has_method("admit"):
		return _failure("INVALID_ADMISSION", {})
	if p_adapter == null or not p_adapter.has_method("build_closure_view"):
		return _failure("INVALID_CLOSURE_ADAPTER", {})
	if p_handler == null or not p_handler.has_method("execute_command"):
		return _failure("INVALID_HANDLER", {"message": "handler must provide execute_command(command) -> Dictionary"})
	_registry = p_registry
	_ledger = p_ledger
	_admission = p_admission
	_adapter = p_adapter
	_handler = p_handler
	return _success({})


## Route one command from a client session through the full admission
## boundary and execute it on the injected handler if admitted.
func route_command(client_session_id: String, operation_id: String, command: Dictionary) -> Dictionary:
	_counters["routed"] = int(_counters["routed"]) + 1
	var binding: Dictionary = _registry.resolve_by_session(client_session_id)
	if not bool(binding.get("success", false)):
		_counters["rejected"] = int(_counters["rejected"]) + 1
		return _failure(String(binding.get("error_code", "UNKNOWN_SESSION")), {"client_session_id": client_session_id})
	var logical_player_id := String(binding["details"]["binding"]["logical_player_id"])
	var domain_id := String(command.get("domain_id", "p6-domain/outpost-world-state"))
	var admission_result: Dictionary = _admission.admit(logical_player_id, operation_id, domain_id, command)
	if not bool(admission_result.get("success", false)):
		var error_code := String(admission_result.get("error_code", "ADMISSION_FAILED"))
		if error_code == "ALREADY_APPLIED":
			_counters["replayed"] = int(_counters["replayed"]) + 1
			return _success({"result": "ALREADY_APPLIED", "operation_id": operation_id})
		_counters["rejected"] = int(_counters["rejected"]) + 1
		return _failure(error_code, {"operation_id": operation_id})
	_counters["executed"] = int(_counters["executed"]) + 1
	var outcome: Variant = _handler.execute_command(command)
	if typeof(outcome) != TYPE_DICTIONARY:
		return _failure("HANDLER_MALFORMED_OUTCOME", {"operation_id": operation_id})
	var completion: Dictionary = _admission.complete(logical_player_id, operation_id)
	if not bool(completion.get("success", false)):
		return _failure(String(completion.get("error_code", "COMPLETION_FAILED")), {"operation_id": operation_id})
	return _success({
		"result": "EXECUTED",
		"operation_id": operation_id,
		"logical_player_id": logical_player_id,
		"outcome": outcome,
	})


func build_closure(logical_player_id: String) -> Dictionary:
	return _adapter.build_closure_view(logical_player_id)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"counters": _counters.duplicate(true),
	}


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
