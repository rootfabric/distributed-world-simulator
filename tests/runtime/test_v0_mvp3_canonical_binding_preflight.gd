extends SceneTree

# Real canonical owner API characterization, NOT a seamless demo or product PASS.
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const M3Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Coordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const SESSION_PREFIX := "transport-session/mvp3/"

var assertions := 0
var failures: Array[String] = []
var report: Dictionary = {}
var services: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	assertions += 1
	if not ok:
		failures.append(description)
		push_error(description)


func _new_service(owner: String, epoch: int):
	var value = Service.new()
	services.append(value)
	var result: Dictionary = value.setup(owner, epoch, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/mvp3/canonical-binding-preflight",
	})
	_check(bool(result.get("success", false)), "real Service setup: %s/%d" % [owner, epoch])
	return value


func _declared_methods(value) -> Dictionary:
	var result: Dictionary = {}
	var script = value.get_script()
	while script != null:
		var methods: Array[String] = []
		for method in script.get_script_method_list():
			methods.append(str(method.get("name", "")))
		methods.sort()
		result[script.resource_path] = methods
		script = script.get_base_script()
	return result


func _save_and_exit() -> void:
	for value in services:
		value.shutdown()
	report["assertions"] = assertions
	report["failures"] = failures.duplicate()
	report["diagnostic_status"] = "GAPS_REPRODUCED" if failures.is_empty() else "DIAGNOSTIC_FAILED"
	report["conclusion"] = "TESTED_RESTART_AND_UNBOUND_COORDINATOR_PATHS_DO_NOT_IMPLEMENT_LIVE_PER_PLAYER_HANDOFF" if failures.is_empty() else "NO_PRODUCT_CONCLUSION_FROM_FAILED_DIAGNOSTIC"
	var written: Dictionary = AtomicJson.write_dictionary(OS.get_environment("DWS_MVP3_PREFLIGHT_OUTPUT"), report)
	print("MVP3_CANONICAL_BINDING_PREFLIGHT assertions=%d failures=%d diagnostic=%s product_verified=false" % [assertions, failures.size(), report["diagnostic_status"]])
	quit(0 if failures.is_empty() and bool(written.get("success", false)) else 1)


func _run() -> void:
	report = {
		"schema": "distributed_world_simulator.mvp3_canonical_binding_preflight.v1",
		"subject_head": OS.get_environment("EXPECTED_HEAD"),
		"subject_tree": OS.get_environment("EXPECTED_TREE"),
		"process_id": OS.get_process_id(),
		"engine_version": Engine.get_version_info(),
		"diagnostic_status": "RUNNING",
		"mvp3_implemented": false, "mvp3_predicate_verified": false,
		"whole_mvp_acceptance": false, "independent_verdict": false,
		"fixture": {}, "cases": {},
	}
	var source = _new_service("authority/a", 1)
	for id in ["a", "b"]:
		var joined: Dictionary = source.join(id, SESSION_PREFIX + id, "operation/mvp3/join-" + id)
		report["fixture"]["join_" + id] = joined
		_check(bool(joined.get("success", false)), "canonical player joins: " + id)
		if not failures.is_empty():
			_save_and_exit()
			return
		var moved: Dictionary = source.move_player(id, SESSION_PREFIX + id, 1, 1, 0.25 if id == "a" else 0.0, 0.25 if id == "b" else 0.0, "operation/mvp3/initial-" + id)
		report["fixture"]["move_" + id] = moved
		_check(bool(moved.get("success", false)), "independent canonical movement: " + id)
		if not failures.is_empty():
			_save_and_exit()
			return
	var before: Dictionary = source.create_snapshot()
	var source_a: Dictionary = source.get_player("a")
	var durable: Dictionary = source.export_durable_state()
	_check(bool(source.validate_durable_state(durable).get("success", false)), "unmodified canonical durable state validates")
	_check(int(source.get_report().get("connected_count", 0)) == 2, "two real connected players")
	_check(durable.get("canonical_item_graph", {}).get("snapshot", {}).get("inventories", {}).has("b"), "aggregate includes the other player's Item Graph inventory")
	if not failures.is_empty():
		_save_and_exit()
		return
	report["source_live_snapshot"] = before
	report["source_durable_state"] = durable
	report["source_replay_state"] = source.export_replay_state()
	report["service_method_inventory"] = _declared_methods(source)
	var runtime = M3Runtime.new()
	report["m3_method_inventory"] = _declared_methods(runtime)
	runtime.free()

	var sessions_cleared := true
	for section in ["players", "ownership"]:
		for player in durable[section]["players"]:
			sessions_cleared = sessions_cleared and player.get("connected") == false and player.get("transport_session_id") == ""
	_check(sessions_cleared, "restart export intentionally removes live player and ownership sessions")
	report["cases"]["restart_export"] = {"live_session_bindings_removed": sessions_cleared, "source_still_connected": source.get_report().get("connected_count") == 2}

	var different_owner = _new_service("authority/b", 2)
	var wrong_owner_result: Dictionary = different_owner.restore_durable_state(durable)
	_check(not bool(wrong_owner_result.get("success", false)), "cross-owner restart restore rejected")
	_check(wrong_owner_result.get("error_code") == "GAMEPLAY_RECOVERY_OWNER_MISMATCH", "cross-owner rejection is the real canonical guard")
	report["cases"]["cross_owner_restore"] = wrong_owner_result
	var different_epoch = _new_service("authority/a", 2)
	var wrong_epoch_result: Dictionary = different_epoch.restore_durable_state(durable)
	_check(not bool(wrong_epoch_result.get("success", false)), "cross-epoch restart restore rejected")
	_check(wrong_epoch_result.get("error_code") == "GAMEPLAY_RECOVERY_EPOCH_MISMATCH", "cross-epoch rejection is the real canonical guard")
	report["cases"]["cross_epoch_restore"] = wrong_epoch_result

	var restored = _new_service("authority/a", 1)
	var restart_result: Dictionary = restored.restore_durable_state(durable)
	_check(bool(restart_result.get("success", false)), "supported same-owner same-epoch restart restore succeeds")
	if not failures.is_empty():
		_save_and_exit()
		return
	_check(int(restored.get_report().get("connected_count", -1)) == 0, "restart restore leaves both players disconnected")
	var before_rebind: Dictionary = restored.get_player("a")
	_check(before_rebind.get("position") == source_a.get("position"), "restart retains position")
	var unbound_move: Dictionary = restored.move_player("a", SESSION_PREFIX + "a", 1, 2, 0.25, 0.0, "operation/mvp3/unbound-move")
	_check(unbound_move.get("error_code") == "PLAYER_NOT_CONNECTED", "old binding cannot execute after restart restore")
	var rejoin_result: Dictionary = restored.join("a", SESSION_PREFIX + "a", "operation/mvp3/rejoin-a")
	_check(bool(rejoin_result.get("success", false)), "ordinary canonical rejoin is supported")
	var rebound: Dictionary = restored.get_player("a")
	_check(int(rebound.get("ownership_epoch", 0)) == int(source_a.get("ownership_epoch", 0)) + 1, "ordinary rejoin advances client ownership epoch")
	_check(rebound.get("player_entity_id") == before_rebind.get("player_entity_id"), "rejoin keeps entity identity; this is not a respawn")
	_check(rebound.get("position") == before_rebind.get("position"), "rejoin keeps position")
	var old_epoch_move: Dictionary = restored.move_player("a", SESSION_PREFIX + "a", 1, 2, 0.25, 0.0, "operation/mvp3/old-client-epoch")
	_check(old_epoch_move.get("error_code") == "STALE_PLAYER_OWNERSHIP_EPOCH", "unchanged client ownership epoch is not accepted")
	report["cases"]["restart_rebind"] = {"restore": restart_result, "move_before_rejoin": unbound_move, "player_before_rejoin": before_rebind, "rejoin": rejoin_result, "player_after_rejoin": rebound, "old_client_epoch_move": old_epoch_move, "note": "Headless API characterization; no transport disconnect or respawn was executed or inferred."}

	# Recompute checksums on changed sections. The rejection must be semantic.
	var actor_only := durable.duplicate(true)
	for section in ["players", "ownership"]:
		var selected: Array = []
		for player in actor_only[section]["players"]:
			if player["logical_player_id"] == "a":
				selected.append(player)
		actor_only[section]["players"] = selected
		actor_only[section] = Utils.finalize_json_checksum(actor_only[section])
	actor_only = Utils.finalize_json_checksum(actor_only)
	var actor_only_result: Dictionary = source.validate_durable_state(actor_only)
	_check(not bool(actor_only_result.get("success", false)), "whole-world payload is not an actor-only transfer")
	_check(actor_only_result.get("error_code") == "ITEM_GRAPH_INVENTORY_PLAYER_MISSING", "actor-only projection violates cross-domain ownership consistency")
	report["cases"]["actor_only_aggregate"] = {"result": actor_only_result, "canonical_item_graph_unchanged": actor_only["canonical_item_graph"] == durable["canonical_item_graph"], "all_modified_section_checksums_recomputed": true}
	var live_in_restart := durable.duplicate(true)
	live_in_restart["players"]["players"][0]["connected"] = true
	live_in_restart["players"]["players"][0]["transport_session_id"] = SESSION_PREFIX + "a"
	live_in_restart["players"] = Utils.finalize_json_checksum(live_in_restart["players"])
	live_in_restart = Utils.finalize_json_checksum(live_in_restart)
	var live_in_restart_result: Dictionary = source.validate_durable_state(live_in_restart)
	_check(not bool(live_in_restart_result.get("success", false)), "live session cannot be smuggled through restart DTO")
	_check(live_in_restart_result.get("details", {}).get("cause", {}).get("error_code", "") == "DURABLE_PLAYER_SESSION_MUST_BE_DISCONNECTED", "restart session guard rejects live session")
	report["cases"]["live_session_in_restart_dto"] = live_in_restart_result
	_check(source.create_snapshot() == before, "invalid target and projection attempts leave source untouched")

	# A correct SM1 state-machine freeze is not an automatic M3 write fence.
	var coordinator = Coordinator.new()
	var coordinator_player := source_a.duplicate(true)
	coordinator_player["last_operation_id"] = "operation/mvp3/initial-a"
	_check(bool(coordinator.configure("authority/a", 1, coordinator_player).get("success", false)), "real SM1 coordinator configures")
	_check(bool(coordinator.begin_transfer("transfer/mvp3/binding-probe", "authority/a", "authority/b", 1).get("success", false)), "real SM1 freeze begins")
	var admission: Dictionary = coordinator.authorize_write("authority/a", 1)
	_check(admission.get("error_code") == "SM1_AUTHORITY_TRANSFER_WRITE_FENCED", "SM1 admission correctly fences source")
	var unbound_source_move: Dictionary = source.move_player("a", SESSION_PREFIX + "a", 1, 2, 0.25, 0.0, "operation/mvp3/unbound-source-write")
	_check(bool(unbound_source_move.get("success", false)), "unbound M3 service does not automatically consult a separate coordinator")
	_check(source.get_player("a").get("position") != source_a.get("position"), "unbound direct service call really mutates canonical player")
	report["cases"]["unbound_sm1_freeze"] = {"coordinator_admission": admission, "direct_service_call": unbound_source_move, "coordinator_snapshot": coordinator.snapshot(), "source_after": source.create_snapshot(), "note": "Intentionally unbound composition, NOT a defect in SM1. Coordinator-only evidence cannot prove M3 integration."}
	_save_and_exit()
