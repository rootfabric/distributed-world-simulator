extends SceneTree

# Exercise the production dispatcher and deferred admission drain. Only the
# transport enqueue is replaced, so message order and payloads remain observable.
class RecordingServer:
	extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
	var messages: Array[Dictionary] = []
	var reject_ack := false
	func _send_on_channel(peer_id: String, message_type: String, data: Dictionary,
			channel: String, delivery_mode: String, _flush_after_send: bool = true) -> bool:
		if message_type == "JOIN_ACK" and reject_ack:
			return false
		messages.append({"peer": peer_id, "type": message_type,
			"data": data.duplicate(true), "channel": channel, "delivery": delivery_mode})
		return true

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for scenario in ["immediate", "deferred", "ack_failed", "deferred_ack_failed", "invalid", "stale"]:
		_run_scenario(scenario)
	for reason in failures:
		push_error(reason)
	print("PLAYTEST_R1_RESOURCE_JOIN: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _run_scenario(scenario: String) -> void:
	var evidence := OS.get_environment("DWS_TEST_ARTIFACT_ROOT")
	if evidence.is_empty():
		evidence = ProjectSettings.globalize_path("user://test-artifacts")
	var server := RecordingServer.new()
	get_root().add_child(server)
	var udp := PacketPeerUDP.new()
	var bound := udp.bind(0, "127.0.0.1")
	_check(bound == OK, scenario + " allocate port")
	var port := udp.get_local_port()
	udp.close()
	var setup: Dictionary = server.setup({"host": "127.0.0.1", "port": port,
		"playable_sandbox": true, "product_seam_enabled": true,
		"r3c_async_admission_canary": true,
		"persistence_root": evidence.path_join("resource-join-%s-%d" % [scenario, Time.get_ticks_usec()])})
	_check(bool(setup.get("success", false)), scenario + " setup")
	if not bool(setup.get("success", false)):
		server.free()
		return
	server.set_process(false)
	var peer := "peer/resource-join/a"
	var session := "transport-session/resource-join/a/1"
	server.set("_peer_compatibility", {peer: {"session_id": session}})
	server.reject_ack = scenario in ["ack_failed", "deferred_ack_failed"]
	var queued := scenario in ["deferred", "deferred_ack_failed", "stale"]
	if queued:
		server.set("_p1b_item_pending", {"operation_id": "operation/resource-join/pending", "kind": "ITEM"})
	var payload := {"type": "JOIN", "logical_player_id": "a",
		"operation_id": "operation/resource-join/a/1"}
	if scenario == "invalid":
		payload["logical_player_id"] = ""
	server.call("_handle_message", peer, session, payload)
	if queued:
		_check(server.get("_r3c_deferred_admissions").size() == 1, scenario + " JOIN queued")
		_check(_messages(server, "JOIN_ACK").is_empty(), scenario + " no early ACK")
		_check(_messages(server, "RESOURCE_SNAPSHOT").is_empty(), scenario + " no early resource snapshot")
		# Retries must not multiply the post-admission publication.
		server.call("_handle_message", peer, session, payload)
		if scenario == "stale":
			server.call("_handle_disconnect", peer, session)
		server.set("_p1b_item_pending", {})
		server.call("_r3c_drain_deferred_admissions")
		server.call("_r3c_drain_deferred_admissions")
	var snapshots := _messages(server, "RESOURCE_SNAPSHOT")
	if scenario in ["immediate", "deferred"]:
		_check(_messages(server, "JOIN_ACK").size() == 1, scenario + " exactly one ACK")
		_check(snapshots.size() == 1, scenario + " exactly one resource snapshot")
		if snapshots.size() == 1:
			var snapshot: Dictionary = snapshots[0]
			_check(server.messages.find(_messages(server, "JOIN_ACK")[0]) < server.messages.find(snapshot),
				scenario + " resource snapshot follows ACK")
			_check(snapshot["channel"] == "RESYNC" and snapshot["delivery"] == "RELIABLE_ORDERED",
				scenario + " reliable resync channel")
			_check(snapshot["data"]["snapshot"] == server.get("_service").create_resource_mining_snapshot(),
				scenario + " canonical resource payload")
	else:
		_check(snapshots.is_empty(), scenario + " no resource publication without successful JOIN ACK")
	_check(bool(server.stop().get("success", false)), scenario + " shutdown")
	server.free()

func _messages(server: RecordingServer, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for message in server.messages:
		if message["type"] == kind:
			result.append(message)
	return result

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
