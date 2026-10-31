extends SceneTree

# Production RESOURCE handler, canonical gameplay + real disk checkpoint/gate.
# Only transport enqueue and the explicit disk failure case are substituted.
const Resolver = preload("res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd")
class RecordingServer:
	extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"
	var messages: Array[Dictionary] = []
	var reject_result := false
	var fail_disk := false
	func _send_on_channel(peer_id: String, message_type: String, data: Dictionary,
			_channel: String, _delivery_mode: String, _flush_after_send: bool = true) -> bool:
		if message_type == "COMMAND_RESULT" and reject_result:
			return false
		messages.append({"peer": peer_id, "type": message_type, "data": data.duplicate(true)})
		return true
	func _persist_checkpoint(operation_id: String, origin_override: String = "", prior_writer_drained: bool = false) -> Dictionary:
		if fail_disk:
			return {"success": false, "error_code": "TEST_DISK_FAILURE"}
		return super._persist_checkpoint(operation_id, origin_override, prior_writer_drained)

var assertions := 0
var failures: Array[String] = []
const PEER := "peer/mining/b"
const SESSION := "transport-session/mining/b/1"
const NODE := "resource/earth/ore-demo/1"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for scenario in ["success", "failed_enqueue", "stale_session", "stale_epoch", "disk_failure"]:
		_scenario(scenario)
	for reason in failures:
		push_error(reason)
	print("PLAYTEST_R1_MINING_DURABLE_ACK: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _scenario(scenario: String) -> void:
	var evidence := OS.get_environment("DWS_TEST_ARTIFACT_ROOT")
	if evidence.is_empty():
		evidence = ProjectSettings.globalize_path("user://test-artifacts")
	var server := RecordingServer.new()
	root.add_child(server)
	var udp := PacketPeerUDP.new()
	_check(udp.bind(0, "127.0.0.1") == OK, scenario + " free port")
	var port := udp.get_local_port()
	udp.close()
	var setup: Dictionary = server.setup({"host": "127.0.0.1", "port": port,
		"world_id": "earth", "playable_sandbox": true, "product_seam_enabled": true,
		"persistence_root": evidence.path_join("mining-%s-%d" % [scenario, Time.get_ticks_usec()])})
	_check(bool(setup.get("success", false)), scenario + " setup")
	if not bool(setup.get("success", false)):
		server.free()
		return
	server.set_process(false)
	server.set("_peer_compatibility", {PEER: {"session_id": SESSION}})
	server.call("_handle_message", PEER, SESSION, {"type": "JOIN", "logical_player_id": "b", "operation_id": "operation/mining/join"})
	var service = server.get("_service")
	var epoch := int(service.get_player("b").get("ownership_epoch", 0))
	_check(epoch == 1, scenario + " joined")
	var resolver = Resolver.new()
	resolver.setup()
	var node: Dictionary = service.get_resource_mining_port().get_node(NODE)
	var target: Dictionary = resolver.resolve_planar(node["spatial"])["details"]["planar_position"]
	for step in range(6):
		var pos: Dictionary = service.get_player("b")["position"]
		var dx := float(target["x"]) - float(pos["x"])
		var dz := float(target["z"]) - float(pos["z"])
		if Vector2(dx, dz).length() < 0.25:
			break
		var moved: Dictionary = service.move_player("b", SESSION, epoch, step + 1,
			clampf(dx, -9.0, 9.0), clampf(dz, -9.0, 9.0), "operation/mining/approach/%d" % step)
		_check(bool(moved.get("success", false)), scenario + " canonical approach " + str(moved))
	var equipped: Dictionary = service.handle_canonical_item_command("b", SESSION, epoch,
		"operation/mining/equip", "item.equip", {"item_id": "item/player/b/p5-mining-tool", "slot_id": "tool/main"})
	_check(bool(equipped.get("success", false)), scenario + " canonical tool")
	server.messages.clear()
	var before: Dictionary = service.create_resource_mining_snapshot()
	var before_items: Dictionary = service.create_canonical_item_graph_snapshot()
	server.reject_result = scenario == "failed_enqueue"
	server.fail_disk = scenario == "disk_failure"
	var payload := {"type": "RESOURCE_COMMAND", "operation_id": "operation/mining/mine",
		"ownership_epoch": epoch + 1 if scenario == "stale_epoch" else epoch,
		"payload": {"resource_node_id": NODE, "requested_units": 1}}
	server.call("_handle_resource_command", PEER, "transport-session/mining/stale" if scenario == "stale_session" else SESSION, payload)
	var after: Dictionary = service.create_resource_mining_snapshot()
	var gate = server.get("_durable_ack_gate")
	if scenario in ["stale_session", "stale_epoch"]:
		_check(after == before, scenario + " no resource mutation")
		_check(service.create_canonical_item_graph_snapshot() == before_items, scenario + " no item mutation")
		_check(_success_count(server) == 0, scenario + " no success ACK")
	elif scenario == "disk_failure":
		_check(bool(server.get("_fatal_persistence_failure")), "disk failure freezes runtime")
		_check(_success_count(server) == 0, "disk failure cannot ACK")
		_check(_publication_count(server) == 0, "disk failure cannot publish")
		_check(not bool(server.call("_gate_can_accept")), "disk failure fences next mutation")
	else:
		_check(after != before, scenario + " canonical resource changed")
		_check(gate.get_report().get("ready_count", -1) == 0, scenario + " ACK escrow released")
		_check(bool(server.call("_gate_can_accept")), scenario + " next mutation allowed")
		_check(not bool(server.get("_fatal_persistence_failure")), scenario + " persistence healthy")
		_check(_success_count(server) == (0 if server.reject_result else 1), scenario + " enqueue outcome")
		if scenario == "failed_enqueue":
			# Rejoin through canonical lifecycle, no rewrite of ownership state.
			server.reject_result = false
			server.call("_handle_disconnect", PEER, SESSION)
			var next_session := "transport-session/mining/b/2"
			server.set("_peer_compatibility", {PEER: {"session_id": next_session}})
			server.call("_handle_message", PEER, next_session, {"type": "JOIN", "logical_player_id": "b", "operation_id": "operation/mining/rejoin"})
			payload["ownership_epoch"] = int(service.get_player("b")["ownership_epoch"])
			_check(payload["ownership_epoch"] > epoch, "fresh session increments ownership")
			server.messages.clear()
			server.call("_handle_resource_command", PEER, next_session, payload)
		else:
			server.messages.clear()
			server.call("_handle_resource_command", PEER, SESSION, payload)
		_check(service.create_resource_mining_snapshot() == after, scenario + " replay does not mine twice")
		_check(_success_count(server) == 1, scenario + " durable replay ACK")
		_check(gate.get_report().get("ready_count", -1) == 0, scenario + " replay does not restage escrow")
	server.fail_disk = false
	server.stop()
	server.free()

func _success_count(server: RecordingServer) -> int:
	var count := 0
	for m in server.messages:
		if m["type"] == "COMMAND_RESULT" and m["data"].get("status", "") == "SUCCEEDED":
			count += 1
	return count

func _publication_count(server: RecordingServer) -> int:
	var count := 0
	for m in server.messages:
		if m["type"] in ["RESOURCE_DELTA", "RESOURCE_SNAPSHOT", "ITEM_GRAPH_DELTA", "GAMEPLAY_SNAPSHOT"]:
			count += 1
	return count

func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)
