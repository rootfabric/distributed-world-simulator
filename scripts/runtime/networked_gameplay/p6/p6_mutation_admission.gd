extends RefCounted

## P6 mutation admission boundary.
##
## This boundary owns no canonical gameplay state and no durable replay truth.
## Its local ledger is only a fail-closed admission guard until the canonical
## owner records completion. A PENDING reservation is never re-admitted: the
## only safe recovery path is explicit completion/reconciliation, not another
## handler invocation.

const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")

const SCHEMA := "planet_simulator.p6_mutation_admission.v1"
const FORBIDDEN_COMMANDS: Array[String] = [
	"DIRECT_CANONICAL_OVERWRITE",
	"PERSISTENCE_BYPASS_WRITE",
	"GATEWAY_STATE_MUTATION",
]

var _registry = null
var _ledger = null
var _counters := {
	"admissions": 0,
	"admitted": 0,
	"replays": 0,
	"pending_rejections": 0,
	"forbidden_writes": 0,
	"unknown_players": 0,
	"undeclared_domains": 0,
}


func configure(p_registry, p_ledger) -> Dictionary:
	if p_registry == null or not p_registry.has_method("resolve"):
		return {"success": false, "error_code": "INVALID_IDENTITY_REGISTRY", "details": {}}
	if (
		p_ledger == null
		or not p_ledger.has_method("record_pending")
		or not p_ledger.has_method("complete_pending")
		or not p_ledger.has_method("is_applied")
		or not p_ledger.has_method("is_pending")
	):
		return {"success": false, "error_code": "INVALID_OPERATION_LEDGER", "details": {}}
	_registry = p_registry
	_ledger = p_ledger
	return {"success": true, "details": {}}


func admit(logical_player_id: String, operation_id: String, domain_id: String, command: Dictionary) -> Dictionary:
	_counters["admissions"] = int(_counters["admissions"]) + 1
	if _registry == null or _ledger == null:
		return _decision(false, "ADMISSION_NOT_CONFIGURED", {})
	if logical_player_id.is_empty() or operation_id.is_empty():
		return _decision(false, "INVALID_OPERATION_IDENTITY", {})

	# 1. identity gate
	var binding: Dictionary = _registry.resolve(logical_player_id)
	if not bool(binding.get("success", false)):
		_counters["unknown_players"] = int(_counters["unknown_players"]) + 1
		return _decision(false, "UNKNOWN_PLAYER", {"logical_player_id": logical_player_id})

	# 2. terminal replay gate
	if _ledger.is_applied(logical_player_id, operation_id):
		_counters["replays"] = int(_counters["replays"]) + 1
		return _decision(false, "ALREADY_APPLIED", {"operation_id": operation_id})

	# 3. in-flight gate. This is the critical crash-window rule: PENDING must
	# never flow back to a handler. Recovery/reconciliation is a separate path.
	if _ledger.is_pending(logical_player_id, operation_id):
		_counters["pending_rejections"] = int(_counters["pending_rejections"]) + 1
		return _decision(false, "OPERATION_PENDING", {"operation_id": operation_id})

	# 4. ownership gate
	var domain: Dictionary = OwnershipMapScript.find_domain(domain_id)
	if domain.is_empty():
		_counters["undeclared_domains"] = int(_counters["undeclared_domains"]) + 1
		return _decision(false, "UNDECLARED_DOMAIN", {"domain_id": domain_id})
	if String(domain.get("transport_path", "")) != "GATEWAY_ONLY":
		return _decision(false, "NON_GATEWAY_TRANSPORT_DOMAIN", {"domain_id": domain_id})
	if String(domain.get("write_authority", "")) != "SERVER_ONLY":
		return _decision(false, "NON_SERVER_WRITE_DOMAIN", {"domain_id": domain_id})

	# 5. forbidden-write gate
	var command_kind := String(command.get("command_kind", ""))
	if FORBIDDEN_COMMANDS.has(command_kind):
		_counters["forbidden_writes"] = int(_counters["forbidden_writes"]) + 1
		return _decision(false, "FORBIDDEN_WRITE", {"command_kind": command_kind})

	# 6. reserve the crash window before execution.
	var pending: Dictionary = _ledger.record_pending(logical_player_id, operation_id)
	if not bool(pending.get("success", false)):
		return _decision(false, String(pending.get("error_code", "PENDING_FAILED")), Dictionary(pending.get("details", {})))
	var pending_result := String(pending.get("details", {}).get("result", ""))
	if pending_result == "ALREADY_APPLIED":
		_counters["replays"] = int(_counters["replays"]) + 1
		return _decision(false, "ALREADY_APPLIED", {"operation_id": operation_id})
	if bool(pending.get("details", {}).get("existing", false)):
		_counters["pending_rejections"] = int(_counters["pending_rejections"]) + 1
		return _decision(false, "OPERATION_PENDING", {"operation_id": operation_id})

	_counters["admitted"] = int(_counters["admitted"]) + 1
	return _decision(true, "ADMITTED", {
		"logical_player_id": logical_player_id,
		"operation_id": operation_id,
		"domain_id": domain_id,
	})


## Explicit reconciliation path. Calling this is appropriate only after the
## canonical mutation owner has established that the operation committed.
func complete(logical_player_id: String, operation_id: String) -> Dictionary:
	if _ledger == null:
		return {"success": false, "error_code": "ADMISSION_NOT_CONFIGURED", "details": {}}
	return _ledger.complete_pending(logical_player_id, operation_id)


func applied_digest(logical_player_id: String, operation_id: String) -> String:
	if _ledger == null or not _ledger.has_method("get_applied_digest"):
		return ""
	return String(_ledger.get_applied_digest(logical_player_id, operation_id))


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"forbidden_commands": FORBIDDEN_COMMANDS.duplicate(true),
		"pending_policy": "FAIL_CLOSED_NO_REEXECUTION",
		"counters": _counters.duplicate(true),
	}


func _decision(success: bool, code: String, details: Dictionary) -> Dictionary:
	return {
		"success": success,
		"error_code": "" if success else code,
		"details": details,
	}
