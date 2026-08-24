extends SceneTree

const IdentityRegistry = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const OperationLedger = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const MutationAdmission = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const ClosureAdapter = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const P6GatewayRoute = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const ShadowScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const TransferCoordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const PlayerCarryingDomain = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd")
const GatewayRoutePivot = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_gateway_route_pivot.gd")

const SESSION := "client-session/sm1/a"
const PLAYER := "player/sm1-a"
const ENTITY := "entity/sm1-a"
const GATEWAY_ENDPOINT := "gateway/edge-primary"
const AUTHORITY_A := "authority/a"
const AUTHORITY_B := "authority/b"

var assertions := 0
var failures: Array[String] = []


class AuthorityHandler:
	extends RefCounted
	var executions: int = 0

	func execute_command(_command: Dictionary) -> Dictionary:
		executions += 1
		return {"accepted": true, "execution_index": executions}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[sm1-carry-route][FAIL] %s" % message)


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _command(sequence: int) -> Dictionary:
	return {
		"domain_id": "p6-domain/outpost-world-state",
		"command_kind": "PLAYER_INTERACTION",
		"input_sequence": sequence,
	}


func _make_shadow():
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources({
		"gameplay": {"revision": 31, "player": PLAYER},
		"item_graph": {"revision": 17, "items": ["item/ore/1"]},
		"construction": {"revision": 9, "constructs": ["construct/outpost/1"]},
	})
	_assert(_ok(configured), "P6 projection setup failed")
	var shadow = ShadowScript.new()
	_assert(_ok(shadow.configure(projection)), "P6 shadow setup failed")
	return shadow


func _complete_transfer(coordinator, carrying, shadow, transfer_id: String, source_id: String, target_id: String, source_epoch: int, target_epoch: int) -> Dictionary:
	var begin: Dictionary = coordinator.begin_transfer(transfer_id, source_id, target_id, source_epoch)
	_assert(_ok(begin), "%s begin failed" % transfer_id)
	var warm_pack: Dictionary = carrying.build_composite_warm_report(transfer_id, shadow.get_report())
	_assert(_ok(warm_pack), "%s composite WARM report failed" % transfer_id)
	var warm_report: Dictionary = Dictionary(warm_pack.get("details", {}).get("warm_report", {}))
	_assert(not String(warm_report.get("carrying_manifest_checksum", "")).is_empty(), "%s carrying checksum missing" % transfer_id)
	_assert(not String(warm_report.get("p6_shadow_checksum", "")).is_empty(), "%s P6 shadow checksum missing" % transfer_id)
	_assert(_ok(coordinator.validate_warm_target(transfer_id, target_id, warm_report)), "%s WARM validation failed" % transfer_id)
	var committed: Dictionary = coordinator.commit_ownership(transfer_id, source_id, target_id, source_epoch, target_epoch)
	_assert(_ok(committed), "%s ownership commit failed" % transfer_id)
	var token := String(committed.get("details", {}).get("commit_token", ""))
	_assert(not token.is_empty(), "%s commit token missing" % transfer_id)
	_assert(_ok(coordinator.retire_source(transfer_id, source_id, token)), "%s source retire failed" % transfer_id)
	_assert(_ok(coordinator.activate_target(transfer_id, target_id, target_epoch, token)), "%s target activate failed" % transfer_id)
	return committed


func _init() -> void:
	var registry = IdentityRegistry.new()
	var binding: Dictionary = registry.bind(SESSION, PLAYER, ENTITY)
	_assert(_ok(binding), "identity binding failed")
	var binding_row: Dictionary = Dictionary(binding.get("details", {}).get("binding", {}))
	_assert(int(binding_row.get("binding_revision", 0)) == 1, "unexpected initial binding revision")

	var ledger = OperationLedger.new()
	_assert(_ok(ledger.configure(128)), "operation ledger configure failed")
	_assert(_ok(ledger.record_applied(PLAYER, "operation/bootstrap/40")), "bootstrap operation record failed")

	var admission = MutationAdmission.new()
	_assert(_ok(admission.configure(registry, ledger)), "mutation admission configure failed")
	var closure = ClosureAdapter.new()
	_assert(_ok(closure.configure(registry, ledger)), "closure adapter configure failed")
	var carrying = PlayerCarryingDomain.new()
	_assert(_ok(carrying.configure(registry, ledger, closure)), "player carrying domain configure failed")

	var initial_capture: Dictionary = carrying.capture_manifest(SESSION, 40, "operation/bootstrap/40")
	_assert(_ok(initial_capture), "initial carrying manifest capture failed")
	var initial_manifest: Dictionary = Dictionary(initial_capture.get("details", {}).get("manifest", {}))
	_assert(bool(initial_manifest.get("derived_only", false)), "carrying manifest is not marked derived-only")
	_assert(not bool(initial_manifest.get("private_canonical_truth", true)), "carrying manifest claims canonical truth")

	var coordinator = TransferCoordinator.new()
	_assert(_ok(coordinator.configure(AUTHORITY_A, 1, initial_manifest)), "transfer coordinator configure failed")

	var handler_a = AuthorityHandler.new()
	var handler_b = AuthorityHandler.new()
	var route_a = P6GatewayRoute.new()
	var route_b = P6GatewayRoute.new()
	_assert(_ok(route_a.configure(registry, ledger, admission, closure, handler_a)), "P6 route A configure failed")
	_assert(_ok(route_b.configure(registry, ledger, admission, closure, handler_b)), "P6 route B configure failed")

	var pivot = GatewayRoutePivot.new()
	_assert(_ok(pivot.configure({AUTHORITY_A: route_a, AUTHORITY_B: route_b}, coordinator, GATEWAY_ENDPOINT, SESSION)), "SM1 gateway pivot configure failed")
	var client_route_before: Dictionary = pivot.get_client_route_identity()
	_assert(String(client_route_before.get("gateway_endpoint_id", "")) == GATEWAY_ENDPOINT, "initial Gateway endpoint mismatch")
	_assert(String(client_route_before.get("gateway_session_id", "")) == SESSION, "initial Gateway session mismatch")
	_assert(not bool(client_route_before.get("simulation_endpoint_disclosed", true)), "client route disclosed simulation endpoint")
	var internal_before: Dictionary = pivot.get_internal_route_projection()
	_assert(String(internal_before.get("internal_authority_id", "")) == AUTHORITY_A, "initial internal route is not A")

	# Command 41 executes on A through the stable client-facing Gateway route.
	var op41 := "operation/sm1/41"
	var routed_a: Dictionary = pivot.route_command(SESSION, op41, _command(41))
	_assert(_ok(routed_a), "pre-handoff command failed")
	_assert(String(routed_a.get("details", {}).get("result", "")) == "EXECUTED", "pre-handoff command was not executed")
	_assert(handler_a.executions == 1 and handler_b.executions == 0, "pre-handoff command did not execute only on A")
	_assert(ledger.is_applied(PLAYER, op41), "pre-handoff OperationId not durable in shared ledger")

	# Freeze the actual carrying state AFTER the latest acknowledged operation.
	var transfer_ab := "transfer/sm1/a-b/1"
	var prepared_ab: Dictionary = carrying.prepare_transfer(transfer_ab, SESSION, 41, op41)
	_assert(_ok(prepared_ab), "A->B player carry prepare failed")
	var prepared_manifest_ab: Dictionary = Dictionary(prepared_ab.get("details", {}).get("manifest", {}))
	var carried_ops_ab: Array = Dictionary(prepared_manifest_ab.get("closure_view", {})).get("carried_operations", [])
	_assert(carried_ops_ab.has(op41), "A->B carrying manifest omitted latest OperationId")
	_assert(int(prepared_manifest_ab.get("last_input_sequence", -1)) == 41, "A->B carrying manifest lost input sequence")

	var begin_ab: Dictionary = coordinator.begin_transfer(transfer_ab, AUTHORITY_A, AUTHORITY_B, 1)
	_assert(_ok(begin_ab), "A->B begin failed")
	var blocked_during_ab: Dictionary = pivot.route_command(SESSION, "operation/sm1/blocked-ab", _command(42))
	_assert(not _ok(blocked_during_ab) and _err(blocked_during_ab) == "SM1_ROUTE_FROZEN_DURING_AUTHORITY_TRANSFER", "Gateway route did not freeze during A->B")
	_assert(not ledger.is_pending(PLAYER, "operation/sm1/blocked-ab"), "frozen Gateway route leaked command into P6 pending ledger")
	_assert(handler_a.executions == 1 and handler_b.executions == 0, "handler executed during A->B zero-writer gap")

	var shadow = _make_shadow()
	var warm_ab: Dictionary = carrying.build_composite_warm_report(transfer_ab, shadow.get_report())
	_assert(_ok(warm_ab), "A->B composite WARM build failed")
	var warm_report_ab: Dictionary = Dictionary(warm_ab.get("details", {}).get("warm_report", {}))
	_assert(_ok(coordinator.validate_warm_target(transfer_ab, AUTHORITY_B, warm_report_ab)), "A->B WARM validation failed")
	var commit_ab: Dictionary = coordinator.commit_ownership(transfer_ab, AUTHORITY_A, AUTHORITY_B, 1, 2)
	_assert(_ok(commit_ab), "A->B ownership commit failed")
	var token_ab := String(commit_ab.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source(transfer_ab, AUTHORITY_A, token_ab)), "A->B source retirement failed")
	_assert(_ok(coordinator.activate_target(transfer_ab, AUTHORITY_B, 2, token_ab)), "A->B target activation failed")

	var client_route_after_ab: Dictionary = pivot.get_client_route_identity()
	_assert(client_route_after_ab == client_route_before, "client-facing Gateway identity changed on A->B")
	var internal_after_ab: Dictionary = pivot.get_internal_route_projection()
	_assert(String(internal_after_ab.get("internal_authority_id", "")) == AUTHORITY_B, "internal route did not pivot to B")
	_assert(int(internal_after_ab.get("authority_epoch", 0)) == 2, "internal route epoch did not advance to 2")

	# Replay of an A-era operation reaches the shared P6 replay boundary and is
	# not executed on B a second time.
	var replay41: Dictionary = pivot.route_command(SESSION, op41, _command(41))
	_assert(_ok(replay41), "post-handoff replay route failed")
	_assert(String(replay41.get("details", {}).get("result", "")) == "ALREADY_APPLIED", "post-handoff replay did not converge to ALREADY_APPLIED")
	_assert(handler_b.executions == 0, "B re-executed A-era OperationId")

	var op42 := "operation/sm1/42"
	var routed_b: Dictionary = pivot.route_command(SESSION, op42, _command(42))
	_assert(_ok(routed_b) and String(routed_b.get("details", {}).get("result", "")) == "EXECUTED", "post-handoff command did not execute on B")
	_assert(handler_a.executions == 1 and handler_b.executions == 1, "post-handoff command did not execute only on B")
	_assert(String(routed_b.get("details", {}).get("gateway_endpoint_id", "")) == GATEWAY_ENDPOINT, "post-handoff response changed Gateway endpoint")
	_assert(not routed_b.get("details", {}).has("internal_authority_id"), "client response exposed internal authority id")
	_assert(not routed_b.get("details", {}).has("authority_epoch"), "client response exposed authority epoch")
	_assert(not bool(routed_b.get("details", {}).get("simulation_endpoint_disclosed", true)), "client response exposed simulation endpoint")

	var continuity_ab: Dictionary = carrying.validate_after_activation(transfer_ab, SESSION, 42, op42, coordinator)
	_assert(_ok(continuity_ab), "A->B player carrying continuity failed")
	var completed_ab: Dictionary = carrying.get_completed(transfer_ab)
	_assert(not String(completed_ab.get("composite_warm_checksum", "")).is_empty(), "A->B completed carry missing WARM binding")
	_assert(String(completed_ab.get("before", {}).get("logical_player_id", "")) == String(completed_ab.get("after", {}).get("logical_player_id", "")), "logical player changed A->B")
	_assert(String(completed_ab.get("before", {}).get("player_entity_id", "")) == String(completed_ab.get("after", {}).get("player_entity_id", "")), "player entity changed A->B")
	_assert(int(completed_ab.get("after", {}).get("last_input_sequence", -1)) == 42, "input sequence did not continue through A->B")

	# Return B -> A using the SAME client-facing Gateway endpoint/session.
	var transfer_ba := "transfer/sm1/b-a/2"
	_assert(_ok(carrying.prepare_transfer(transfer_ba, SESSION, 42, op42)), "B->A player carry prepare failed")
	var begin_ba: Dictionary = coordinator.begin_transfer(transfer_ba, AUTHORITY_B, AUTHORITY_A, 2)
	_assert(_ok(begin_ba), "B->A begin failed")
	var blocked_during_ba: Dictionary = pivot.route_command(SESSION, "operation/sm1/blocked-ba", _command(43))
	_assert(not _ok(blocked_during_ba) and _err(blocked_during_ba) == "SM1_ROUTE_FROZEN_DURING_AUTHORITY_TRANSFER", "Gateway route did not freeze during B->A")
	var warm_ba: Dictionary = carrying.build_composite_warm_report(transfer_ba, shadow.get_report())
	_assert(_ok(warm_ba), "B->A composite WARM build failed")
	var warm_report_ba: Dictionary = Dictionary(warm_ba.get("details", {}).get("warm_report", {}))
	_assert(_ok(coordinator.validate_warm_target(transfer_ba, AUTHORITY_A, warm_report_ba)), "B->A WARM validation failed")
	var commit_ba: Dictionary = coordinator.commit_ownership(transfer_ba, AUTHORITY_B, AUTHORITY_A, 2, 3)
	_assert(_ok(commit_ba), "B->A ownership commit failed")
	var token_ba := String(commit_ba.get("details", {}).get("commit_token", ""))
	_assert(_ok(coordinator.retire_source(transfer_ba, AUTHORITY_B, token_ba)), "B->A source retirement failed")
	_assert(_ok(coordinator.activate_target(transfer_ba, AUTHORITY_A, 3, token_ba)), "B->A target activation failed")
	_assert(pivot.get_client_route_identity() == client_route_before, "client-facing Gateway identity changed on B->A")
	_assert(String(pivot.get_internal_route_projection().get("internal_authority_id", "")) == AUTHORITY_A, "internal route did not pivot back to A")
	_assert(int(pivot.get_internal_route_projection().get("authority_epoch", 0)) == 3, "internal route epoch did not advance to 3")

	var op43 := "operation/sm1/43"
	var routed_a_return: Dictionary = pivot.route_command(SESSION, op43, _command(43))
	_assert(_ok(routed_a_return) and String(routed_a_return.get("details", {}).get("result", "")) == "EXECUTED", "return command did not execute on A")
	_assert(handler_a.executions == 2 and handler_b.executions == 1, "B->A route executed on wrong authority")
	var continuity_ba: Dictionary = carrying.validate_after_activation(transfer_ba, SESSION, 43, op43, coordinator)
	_assert(_ok(continuity_ba), "B->A player carrying continuity failed")

	# Replay B-era op42 after return to A must still be exactly-once.
	var replay42: Dictionary = pivot.route_command(SESSION, op42, _command(42))
	_assert(_ok(replay42) and String(replay42.get("details", {}).get("result", "")) == "ALREADY_APPLIED", "B-era OperationId replay did not survive B->A")
	_assert(handler_a.executions == 2, "A re-executed B-era OperationId after return")

	var wrong_session: Dictionary = pivot.route_command("client-session/sm1/other", "operation/sm1/wrong-session", _command(44))
	_assert(not _ok(wrong_session) and _err(wrong_session) == "SM1_ROUTE_CLIENT_SESSION_CHANGED", "route accepted a replacement client session")
	var final_binding: Dictionary = registry.resolve_by_session(SESSION)
	_assert(_ok(final_binding), "original client session binding disappeared")
	_assert(int(final_binding.get("details", {}).get("binding", {}).get("binding_revision", 0)) == 1, "ordinary handoff changed identity binding revision")
	_assert(String(final_binding.get("details", {}).get("binding", {}).get("logical_player_id", "")) == PLAYER, "logical player changed in identity registry")
	_assert(String(final_binding.get("details", {}).get("binding", {}).get("player_entity_id", "")) == ENTITY, "player entity changed in identity registry")

	var carry_report: Dictionary = carrying.get_report()
	_assert(int(carry_report.get("completed_count", 0)) == 2, "player carrying domain did not complete both transfers")
	_assert(not bool(carry_report.get("private_canonical_truth", true)), "player carrying domain claims canonical truth")
	var pivot_report: Dictionary = pivot.get_report()
	_assert(not bool(pivot_report.get("gateway_authoritative", true)), "Gateway pivot claims authority")
	_assert(not bool(pivot_report.get("private_ownership_truth", true)), "Gateway pivot claims ownership truth")
	_assert(int(pivot_report.get("counters", {}).get("frozen_during_transfer", 0)) == 2, "Gateway transfer freeze counter mismatch")

	if failures.is_empty():
		print("[sm1-carry-route] all %d assertions passed" % assertions)
		print("[sm1-carry-route][stage] PLAYER_CARRYING_DOMAIN_CONTINUITY_PASS")
		print("[sm1-carry-route][stage] CLIENT_GATEWAY_ENDPOINT_UNCHANGED_PASS")
		print("[sm1-carry-route][stage] OPERATION_ID_CONTINUITY_ACROSS_AUTHORITY_PASS")
		print("[sm1-carry-route][stage] INPUT_SEQUENCE_CONTINUITY_PASS")
		print("[sm1-carry-route][stage] INTERNAL_ROUTE_A_B_A_PASS")
		quit(0)
	else:
		print("[sm1-carry-route] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
