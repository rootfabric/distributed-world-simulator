extends SceneTree

# R4.1-P1 F1/F2 falsifiers. Exercise the published server runtime and the
# actual M6 pending-durable ACK kernel, never a mocked ACK permission method.
const Server = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
const Gate = preload("res://scripts/persistence/m6_pending_durable_ack_gate.gd")

class FakeService:
	extends RefCounted
	var leave_calls := 0
	func leave_transport_session(_session_id: String, _operation_id: String) -> Dictionary:
		leave_calls += 1
		return {"success": false, "error_code": "FAKE_SERVICE_MUST_NOT_BE_CALLED"}
	func create_targeted_command_result(_message_id: String, _operation_id: String, result: Dictionary) -> Dictionary:
		return {"status": "COMMITTED" if bool(result.get("success", false)) else "REJECTED",
			"error_code": String(result.get("error_code", "")), "payload": {}, "checksum": ""}

class FakeBoundary:
	extends RefCounted
	var sent: Array[Dictionary] = []
	func get_peer_snapshot(_peer_id: String) -> Dictionary:
		return {"state": "READY"}
	func create_frame_for_peer(_peer_id: String, channel: String, _schema: String, payload: Dictionary, _delivery_mode: String) -> Dictionary:
		return {"success": true, "details": {"frame": {"channel": channel, "payload": payload.duplicate(true)}}}
	func send_to_peer(peer_id: String, frame: Dictionary) -> Dictionary:
		sent.append({"peer_id": peer_id, "frame": frame.duplicate(true)})
		return {"success": true, "details": {}}
	func flush_outbound(_max_frames: int, _peer_id: String) -> Dictionary:
		return {"success": true, "details": {}}

class FakeConstruction:
	extends RefCounted
	var submit_calls := 0
	func submit_player_command(_logical_player_id: String, _command: Dictionary) -> Dictionary:
		submit_calls += 1
		return {"success": false, "error_code": "FAKE_CONSTRUCTION_REJECT"}

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var server = Server.new()
	var gate = Gate.new()
	check(_ok(gate.configure(10, 2)), "configure single canonical generation")
	server._durable_ack_gate = gate
	server._persistence_enabled = true
	var success := {"success": true}
	check(_ok(gate.stage("op/a", "peer/a", "session/a", "player/a", 1, "ITEM", success, 11)), "stage A")
	check(_ok(gate.mark_submitted("op/a", 11)), "submit A")
	check(_ok(gate.complete("op/a", 11, {"success": true, "generation": 11})), "A has durable commit")
	check(server._gate_is_ack_head("op/a", "peer/a", "session/a", "player/a", 1), "A is FIFO head")
	check(not server._gate_is_ack_head("op/b", "peer/b", "session/b", "player/b", 1), "B is not FIFO head")
	check(not server._gate_is_ack_head("op/a", "peer/a", "session/a", "player/a", 2), "stale epoch cannot authorize A")
	check(server._gate_preflight_success_result("op/a", "peer/a", "session/a", "player/a", 1, success), "authorized A before reliable enqueue")
	check(not server._gate_can_accept(), "no overtaking while A ACK unresolved")
	check(not server._gate_after_result_enqueue("op/a", "peer/a", "session/a", "player/a", 1, success, false), "failed enqueue is not delivered")
	check(gate.get_report().get("ready_count", -1) == 0, "undeliverable A quarantined")
	check(gate.get_report().get("generation", -1) == 11, "A still durably committed after failed send")
	check(server._gate_can_accept(), "fence released after A session quarantine")
	check(server._gate_preflight_success_result("op/a", "peer/a", "session/a", "player/a", 1, {"success": true, "replay": true}), "M6 replay of quarantined A is allowed")
	check(server._gate_after_result_enqueue("op/a", "peer/a", "session/a", "player/a", 1, {"success": true, "replay": true}, true), "M6 replay does not re-stage A")
	check(_ok(gate.stage("op/b", "peer/b", "session/b", "player/b", 1, "ITEM", success, 12)), "B uses next exact generation")
	check(_ok(gate.mark_submitted("op/b", 12)), "submit B")
	check(_ok(gate.complete("op/b", 12, {"success": true, "generation": 12})), "B durable")
	check(server._gate_preflight_success_result("op/b", "peer/b", "session/b", "player/b", 1, success), "B authorized before enqueue")
	check(server._gate_after_result_enqueue("op/b", "peer/b", "session/b", "player/b", 1, success, true), "B ACK marked delivered only after enqueue")
	check(gate.get_report().get("ready_count", -1) == 0, "B escrow consumed")

	var service = FakeService.new()
	server._service = service
	check(_ok(gate.stage("op/c", "peer/c", "session/c", "player/c", 1, "ITEM", success, 13)), "stage long in-flight C")
	check(_ok(gate.mark_submitted("op/c", 13)), "submit pending C")
	server._peer_to_player["peer/c"] = "player/c"
	server._peer_to_session["peer/c"] = "session/c"
	server._handle_disconnect("peer/c", "session/c")
	check(service.leave_calls == 0, "disconnect does not mutate during pending generation")
	check(server._deferred_disconnects.size() == 1, "disconnect deferred without losing session")
	server._queue_deferred_disconnect("peer/c", "session/c")
	check(server._deferred_disconnects.size() == 1, "repeat deferred disconnect coalesces")
	check(String(server._peer_to_session.get("peer/c", "")) == "session/c", "authority mapping held pending commit")
	check(_ok(gate.complete("op/c", 13, {"success": true, "generation": 13})), "C commit persists after disconnect")
	check(gate.get_report().get("ready_count", -1) == 0, "C ACK quarantined on disconnect")
	check(server._gate_can_accept(), "C completion releases serial mutation fence")

	server._peer_to_player["peer/reused"] = "player/new"
	server._peer_to_session["peer/reused"] = "session/new"
	server._handle_disconnect("peer/reused", "session/old")
	check(String(server._peer_to_session.get("peer/reused", "")) == "session/new", "stale event cannot evict newer session")
	check(String(server._peer_to_player.get("peer/reused", "")) == "player/new", "stale event cannot evict newer player")
	check(service.leave_calls == 0, "stale disconnect cannot mutate canonical world")
	check(not server._construction_durability_allowed(), "Construction without M6 checkpoint proof fails closed")
	var construction = FakeConstruction.new()
	var boundary = FakeBoundary.new()
	server._construction_bridge = construction
	server._boundary = boundary
	server._peer_to_player["peer/build"] = "player/build"
	server._peer_to_session["peer/build"] = "session/build"
	server._handle_construction_command("peer/build", "session/build", {"operation_id": "op/build", "command": {"action": "place"}})
	check(construction.submit_calls == 0, "persisted Construction never mutates unbound gateway")
	check(boundary.sent.size() == 1, "persisted Construction rejects via normal control reply")
	if boundary.sent.size() == 1:
		var rejected_payload: Dictionary = Dictionary(boundary.sent[0].get("frame", {})).get("payload", {})
		check(String(rejected_payload.get("error_code", "")) == "M3_CONSTRUCTION_DURABILITY_CONTRACT_REQUIRED", "exact persisted Construction error")
	server._persistence_enabled = false
	check(server._construction_durability_allowed(), "nonpersistent construction compatibility remains")
	server._handle_construction_command("peer/build", "session/build", {"operation_id": "op/build/nonpersistent", "command": {"action": "place"}})
	check(construction.submit_calls == 1, "nonpersistent Construction gateway remains callable")
	server.free()

	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH1_R41_P1_FIFO_DISCONNECT: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)

func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
