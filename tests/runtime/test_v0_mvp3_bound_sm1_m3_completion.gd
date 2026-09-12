extends "res://tests/runtime/test_v0_mvp3_bound_sm1_m3_route.gd"

# R6 extends the complete real-route probe with commit-aware completion.
# Existing P6/SM1 code and the canonical M3 owner are not modified.
var _primary_handler = null
var _failure_case_exercised := false


class CanonicalCompletion:
	extends RefCounted
	var delegate
	var service
	var canonical_player := ""
	var p6_player_alias := ""

	func admit(player: String, operation: String, domain: String, value: Dictionary) -> Dictionary:
		return delegate.admit(player, operation, domain, value)

	func complete(player: String, operation: String) -> Dictionary:
		# Read the actual mutation owner's receipt, never the route's outer PASS.
		var receipt: Dictionary = service.export_replay_state().get("service_operation_ledger", {}).get(operation, {})
		var result: Dictionary = receipt.get("result", {})
		var actor: Dictionary = result.get("details", {}).get("player", {})
		if player != p6_player_alias or not bool(result.get("success", false)) or actor.get("logical_player_id") != canonical_player or actor.get("player_entity_id") != "player/" + canonical_player:
			return {"success": false, "error_code": "MVP3_CANONICAL_COMMIT_NOT_PROVEN"}
		return delegate.complete(player, operation)


func adapter(service, coordinator, registry, ledger, admission, closure, player: String, authority: String):
	var completion := CanonicalCompletion.new()
	completion.delegate = admission
	completion.service = service
	completion.canonical_player = player
	completion.p6_player_alias = "player/mvp3/" + player
	var handler = super.adapter(service, coordinator, registry, ledger, completion, closure, player, authority)
	if player == "a" and authority == "authority/a":
		_primary_handler = handler
	return handler


func send(pivot, player: String, value: Dictionary) -> Dictionary:
	var result: Dictionary = super.send(pivot, player, value)
	# After the safe pre-commit abort, A's second command succeeds. Inject an
	# actual stale-sequence rejection only then, so the earlier carry scenario
	# is not contaminated by this intentionally pending failed operation.
	if not _failure_case_exercised and player == "a" and value.get("input_sequence") == 2 and bool(result.get("success", false)):
		_failure_case_exercised = true
		var handler = _primary_handler
		var owner = handler.service
		var before: Dictionary = owner.create_snapshot()
		var rejected := command("a", 2)
		rejected["operation_id"] = "operation/mvp3/rejected-stale-sequence"
		var rejection: Dictionary = super.send(pivot, "a", rejected)
		check(not bool(rejection.get("success", false)), "rejected canonical command cannot become a successful route receipt")
		check(rejection.get("error_code") == "MVP3_CANONICAL_COMMIT_NOT_PROVEN", "commit-aware P6 completion refuses M3 rejection")
		var canonical_receipt: Dictionary = owner.export_replay_state().get("service_operation_ledger", {}).get(rejected["operation_id"], {})
		check(canonical_receipt.get("result", {}).get("success") == false, "real M3 owner recorded rejection, not a successful mutation")
		check(owner.create_snapshot() == before, "handler rejection did not mutate canonical player state")
		var closure: Dictionary = handler.p6_route.build_closure("player/mvp3/a")
		check(bool(closure.get("success", false)), "accepted P6 closure remains inspectable")
		check(not closure.get("details", {}).get("view", {}).get("carried_operations", []).has(rejected["operation_id"]), "failed operation is excluded from carrying applied operations")
		var retry: Dictionary = super.send(pivot, "a", rejected)
		check(not bool(retry.get("success", false)), "rejected operation replay does not become ALREADY_APPLIED")
		check(owner.create_snapshot() == before, "rejected retry does not execute canonical movement")
		evidence["handler_rejection_control"] = {"rejection": rejection, "canonical_receipt": canonical_receipt, "closure": closure, "retry": retry, "canonical_state_unchanged": owner.create_snapshot() == before, "completion_source": "REAL_M3_SERVICE_REPLAY_RECEIPT", "p6_or_m3_production_changed": false}
	return result


func _run() -> void:
	super._run()
	_primary_handler = null
