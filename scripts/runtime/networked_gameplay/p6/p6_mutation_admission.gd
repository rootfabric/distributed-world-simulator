extends RefCounted

## P6.4 mutation admission boundary.
##
## The SINGLE decision point every canonical mutation must pass through:
##   1. identity: the logical player must have a LIVE binding (P6.2 registry);
##   2. replay: an already-applied operation short-circuits ALREADY_APPLIED
##      without executing the handler again (P6.3 ledger);
##   3. ownership: the command's target domain must be declared in the P6.1
##      ownership map with SERVER_ONLY write authority;
##   4. forbidden writes: commands on the fail-closed forbidden list are
##      rejected with FORBIDDEN_WRITE before any handler runs;
##   5. crash window: a PENDING intent is recorded BEFORE the handler executes;
##      if this process dies, recovery completes it exactly once (P6.3 ledger).
##
## The handler itself is injected and owned by sim-side code; this boundary
## never implements gameplay.

const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")

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
	"forbidden_writes": 0,
	"unknown_players": 0,
	"undeclared_domains": 0,
}


func configure(p_registry, p_ledger) -> Dictionary:
	if p_registry == null or not p_registry.has_method("resolve"):
		return {"success": false, "error_code": "INVALID_IDENTITY_REGISTRY", "details": {}}
	if p_ledger == null or not p_ledger.has_method("record_applied"):
		return {"success": false, "error_code": "INVALID_OPERATION_LEDGER", "details": {}}
	_registry = p_registry
	_ledger = p_ledger
	return {"success": true, "details": {}}


## Admit one canonical mutation. Returns ADMITTED only when all five gates
## pass; the caller then executes `handler.call(command)` exactly once and
## MUST call complete() with the outcome.
func admit(logical_player_id: String, operation_id: String, domain_id: String, command: Dictionary) -> Dictionary:
	_counters["admissions"] = int(_counters["admissions"]) + 1

	# 1. identity gate
	var binding: Dictionary = _registry.resolve(logical_player_id)
	if not bool(binding.get("success", false)):
		_counters["unknown_players"] = int(_counters["unknown_players"]) + 1
		return _decision(false, "UNKNOWN_PLAYER", {"logical_player_id": logical_player_id})

	# 2. replay gate
	if _ledger.is_applied(logical_player_id, operation_id):
		_counters["replays"] = int(_counters["replays"]) + 1
		return _decision(false, "ALREADY_APPLIED", {"operation_id": operation_id})

	# 3. ownership gate
	var domain: Dictionary = OwnershipMapScript.find_domain(domain_id)
	if domain.is_empty():
		_counters["undeclared_domains"] = int(_counters["undeclared_domains"]) + 1
		return _decision(false, "UNDECLARED_DOMAIN", {"domain_id": domain_id})
	if String(domain.get("transport_path", "")) != "GATEWAY_ONLY":
		return _decision(false, "NON_GATEWAY_TRANSPORT_DOMAIN", {"domain_id": domain_id})

	# 4. forbidden-write gate
	var command_kind := String(command.get("command_kind", ""))
	if FORBIDDEN_COMMANDS.has(command_kind):
		_counters["forbidden_writes"] = int(_counters["forbidden_writes"]) + 1
		return _decision(false, "FORBIDDEN_WRITE", {"command_kind": command_kind})

	# 5. crash window: pending intent recorded before execution
	var pending: Dictionary = _ledger.record_pending(logical_player_id, operation_id)
	if not bool(pending.get("success", false)):
		return _decision(false, String(pending.get("error_code", "PENDING_FAILED")), {})

	_counters["admitted"] = int(_counters["admitted"]) + 1
	return _decision(true, "ADMITTED", {
		"logical_player_id": logical_player_id,
		"operation_id": operation_id,
		"domain_id": domain_id,
	})


## Terminal outcome recording after handler execution. Exactly-once via ledger.
func complete(logical_player_id: String, operation_id: String) -> Dictionary:
	return _ledger.complete_pending(logical_player_id, operation_id)


## Replay surface: prior digest for an applied operation.
func applied_digest(logical_player_id: String, operation_id: String) -> String:
	var record: Dictionary = _ledger.record_applied(logical_player_id, operation_id)
	return String(record.get("details", {}).get("outcome_digest", ""))


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"forbidden_commands": FORBIDDEN_COMMANDS.duplicate(true),
		"counters": _counters.duplicate(true),
	}


func _decision(success: bool, error_code: String, details: Dictionary) -> Dictionary:
	return {
		"success": success,
		"error_code": error_code if success == false else "",
		"details": details,
	}
