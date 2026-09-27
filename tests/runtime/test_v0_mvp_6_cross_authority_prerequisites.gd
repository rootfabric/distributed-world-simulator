extends "res://tests/runtime/test_v0_mvp_6_item_construction_composition.gd"

const EndpointSeam = preload("res://scripts/construction/distributed/construction_authority_server_endpoint.gd")
const DamageRequestSeam = preload("res://scripts/construction/damage/construction_damage_request.gd")
var seam_observations: Dictionary = {}

# Read-through witness for the endpoint's unused transfer interface. No state
# store, mutation, migration or final-snapshot injection. This diagnostic tests
# native submit only; distributed transfer/replication is explicitly NOT proven.
class NativeSnapshotWitness:
	extends RefCounted
	var adapter
	var transfer_calls := 0
	func _init(value):
		adapter = value
	func export_construct_state(construct_id: String) -> Dictionary:
		transfer_calls += 1
		return {"success": false, "error_code": "DIAGNOSTIC_TRANSFER_NOT_EXECUTED", "construct_id": construct_id}
	func import_construct_state(_value: Dictionary, _operations: Array = []) -> Dictionary:
		transfer_calls += 1
		return {"success": false, "error_code": "DIAGNOSTIC_TRANSFER_NOT_EXECUTED"}
	func get_construct_checksum(construct_id: String) -> String:
		return String(adapter.get_construct_snapshot(construct_id).get("checksum", ""))

func contains_native_error(value, expected: String) -> bool:
	if value is Dictionary:
		if value.get("error_code", "") == expected: return true
		for child in value.values():
			if contains_native_error(child, expected): return true
	elif value is Array:
		for child in value:
			if contains_native_error(child, expected): return true
	return false

func fresh_factory_seam(tag: String) -> Dictionary:
	var owner = state["owners"]["authority/a"]
	var graph = owner.get_canonical_item_graph_port()
	var epoch := int(state["coordinators"]["a"].snapshot()["authority_epoch"])
	var path := "user://mvp6-seam-prerequisite/%d-%d-%s" % [OS.get_process_id(), Time.get_ticks_usec(), tag]
	var made: Dictionary = ConstructionAuthority6.create_gateway(graph, "authority/a", epoch, path)
	if not success(made, "fresh native P4 fixture " + tag): return {}
	var detail: Dictionary = made["details"]
	var bridge = ConstructionBridge6.new()
	if not success(bridge.setup(detail["gateway"]), "native M3 bridge " + tag): return {}
	var joined: Dictionary = bridge.connect_player("a", epoch)
	if not success(joined, "authenticated Construction session " + tag): return {}
	return {"bridge": bridge, "session": joined["details"]["session"], "detail": detail, "graph": graph}

func reproduce_seam_gaps() -> bool:
	if not setup6(): return false
	if not seed6(): return false
	var owner = state["owners"]["authority/a"]
	var graph = owner.get_canonical_item_graph_port()
	if not success(owner.apply_canonical_server_output("operation/mvp6/seam/repro/extra", "a", "item/ore", 3, "source/mvp6/seam/native-fixture"), "eight real native ore units for P4 recipe"): return false
	var ore_id := String(receipts6["a"]["ore"]["details"]["output_item_id"])
	if not success(native_command6("a", "seam-repro-stage-ore", "item.transfer", {"item_id": ore_id, "quantity": 5, "target_container_id": "inventory/a", "target_slot_index": -1}), "native hotbar to inventory, no reissued material"): return false
	if not check(ore6(graph.create_snapshot(), "a") == 8, "exact native ore precondition"): return false

	var negative := fresh_factory_seam("c17-raw")
	if negative.is_empty(): return false
	var before_items: Dictionary = graph.create_snapshot()
	var raw_gateway = negative["detail"]["gateway"]
	var negative_bundle: Dictionary = raw_gateway.get_state_bundle()
	var command := construction_command6(negative["session"], 0, "seam-repro-build-0", 0, negative_bundle)
	if not success(ConstructionCommand6.validate(command), "identical BUILD is a valid canonical command"): return false
	var witness = NativeSnapshotWitness.new(negative["detail"]["authoritative_adapter"])
	var endpoint = EndpointSeam.new()
	if not success(endpoint.setup("server/mvp6/a", "cell/mvp6/a", raw_gateway, witness), "production C17 endpoint setup"): return false
	var rejected: Dictionary = endpoint.submit(command)
	seam_observations["C17_P4_TRUSTED_ACTOR_ROUTE"] = {"command": command, "negative_result": rejected, "items_before": before_items, "items_after_rejection": graph.create_snapshot(), "bundle_before": negative_bundle, "bundle_after_rejection": raw_gateway.get_state_bundle(), "transfer_calls": witness.transfer_calls}
	if not check(not bool(rejected.get("success", false)) and contains_native_error(rejected, "P4_BUILD_PLAYER_CONTEXT_REQUIRED"), "C17 raw route reproduces missing trusted player context"): return false
	if not check(graph.create_snapshot() == before_items and raw_gateway.get_state_bundle() == negative_bundle, "C17 rejection neither spends material nor builds"): return false
	if not check(witness.transfer_calls == 0, "transfer witness never participates in native command execution"): return false

	# New gateway/M0 fixture: do not reuse the first gateway's terminal rejection.
	# Its authenticated session and entire BUILD command must be byte-equivalent.
	var positive := fresh_factory_seam("m3-positive")
	if positive.is_empty(): return false
	var bridge = positive["bridge"]
	var initial: Dictionary = bridge.get_snapshot_packet()["state_bundle"]
	var same_command := construction_command6(positive["session"], 0, "seam-repro-build-0", 0, initial)
	if not check(same_command == command, "positive control receives the identical valid BUILD command"): return false
	var accepted: Dictionary = bridge.submit_player_command("a", same_command)
	seam_observations["C17_P4_TRUSTED_ACTOR_ROUTE"]["positive_result"] = accepted
	if not success(accepted, "existing authenticated M3 path commits the same BUILD"): return false
	if not check(ore6(graph.create_snapshot(), "a") == 6, "positive BUILD really consumes two canonical ore"): return false
	for stage in [1, 2]:
		var current: Dictionary = bridge.get_snapshot_packet()["state_bundle"]
		var next_command := construction_command6(positive["session"], stage, "seam-repro-build-%d" % stage, stage, current)
		if not success(bridge.submit_player_command("a", next_command), "finish canonical P4 stage %d" % stage): return false
	if not check(ore6(graph.create_snapshot(), "a") == 0, "native three-stage recipe consumes exactly eight ore"): return false
	var adapter = positive["detail"]["authoritative_adapter"]
	var snapshot: Dictionary = adapter.get_construct_snapshot(ConstructionAuthority6.CONSTRUCT_ID)
	if not check(snapshot.get("build_state", "") == "OPERATIONAL" and snapshot.get("parts", []).size() == 6, "actual legacy Construction exists before REMOVE diagnostic"): return false
	var permissions = positive["detail"]["gateway"].get_permission_store()
	var grant := ConstructionGrant6.create("permission/mvp6/seam/repro/damage", String(positive["session"]["client_id"]), ConstructionAuthority6.CONSTRUCT_ID, [ConstructionGrant6.ACTION_DAMAGE, ConstructionGrant6.ACTION_READ], int(permissions.get_epoch()))
	if not success(permissions.publish(grant), "server publishes explicit DAMAGE permission"): return false
	var request := DamageRequestSeam.create("damage/mvp6/seam/repro/roof", ConstructionAuthority6.CONSTRUCT_ID, String(snapshot["checksum"]), "part/mvp/outpost/foundation", [], [], {"part/mvp/outpost/roof": "DESTROYED"})
	if not success(DamageRequestSeam.validate(request), "valid canonical non-root leaf REMOVE request"): return false
	var bundle_before: Dictionary = bridge.get_snapshot_packet()["state_bundle"]
	var damage_command := ConstructionCommand6.create("multiplayer-command/mvp6/seam/repro/remove", String(positive["session"]["client_id"]), String(positive["session"]["session_id"]), int(positive["session"]["session_epoch"]), 3, ConstructionGrant6.ACTION_DAMAGE, ConstructionAuthority6.CONSTRUCT_ID, String(snapshot["checksum"]), int(bundle_before["server_generation"]), int(permissions.get_epoch()), {"plan_id": "transaction-plan/mvp6/seam/repro/remove", "operation_id": "operation/mvp6/seam/repro/remove", "request": request, "failure_mode": ""})
	if not success(ConstructionCommand6.validate(damage_command), "valid multiplayer REMOVE envelope"): return false
	var items_before_remove: Dictionary = graph.create_snapshot()
	var removed: Dictionary = bridge.submit_player_command("a", damage_command)
	seam_observations["P4_SEAM_REMOVE"] = {"command": damage_command, "result": removed, "construct_before": snapshot, "construct_after": adapter.get_construct_snapshot(ConstructionAuthority6.CONSTRUCT_ID), "items_before": items_before_remove, "items_after": graph.create_snapshot(), "bundle_before": bundle_before, "bundle_after": bridge.get_snapshot_packet()["state_bundle"]}
	if not check(not bool(removed.get("success", false)) and contains_native_error(removed, "CONSTRUCTION_DAMAGE_PROCESS_NOT_CONFIGURED"), "native REMOVE reproduces unconfigured C9 process, not permission failure"): return false
	if not check(adapter.get_construct_snapshot(ConstructionAuthority6.CONSTRUCT_ID) == snapshot and graph.create_snapshot() == items_before_remove, "failed REMOVE preserves canonical part and item truth"): return false
	if not check(bridge.get_snapshot_packet()["state_bundle"] == bundle_before, "failed REMOVE publishes no mutated bundle"): return false
	return true

func run() -> void:
	var okay := reproduce_seam_gaps()
	var report := {"schema": "distributed_world_simulator.mvp6_seam_prerequisite_diagnostic.v1", "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "diagnostic_passed": okay and failures.is_empty(), "assertions": assertions, "failures": failures, "observations": seam_observations, "fixture_parts": 6, "same_command_positive_control": true, "cross_authority_construction_seam_verified": false, "live_five_process_executed": false, "traversal_executed": false, "mvp6_predicate_verified": false, "independent_verdict": false}
	cleanup6()
	var output := OS.get_environment("MVP6_SEAM_DIAGNOSTIC_RESULT")
	var saved := false
	if not output.is_empty(): saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_SEAM_PREREQUISITE assertions=%d failures=%d diagnostic_passed=%s product_passed=false" % [assertions, failures.size(), str(report["diagnostic_passed"])])
	quit(0 if report["diagnostic_passed"] and saved else 1)
