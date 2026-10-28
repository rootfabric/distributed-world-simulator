extends SceneTree

# R3C — no failed reconnect JOIN under M6 backpressure, even with duplicate
# packets. Real JOIN happens only after the pending writer fence is clear.
const Runtime = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")

const PEER := "peer/r3c/join/a"
const SESSION := "transport-session/r3c/join/a/1"
const OP := "operation/r3c/join/a/1"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r3c-queued-join-%d" % Time.get_ticks_usec())
	var server = Runtime.new()
	get_root().add_child(server)
	var configured: Dictionary = server.setup({
		"host": "127.0.0.1", "port": _port(), "playable_sandbox": true,
		"persistence_root": root_path, "product_seam_enabled": true,
		"r3c_async_admission_canary": true,
	})
	check(_ok(configured), "V0 USER1 product + real M6 setup")
	if not _ok(configured):
		server.free()
		_finish()
		return
	server.set_process(false)
	var service = server.get("_service")
	check(service.has_method("requires_immediate_join_persistence")
		and not service.requires_immediate_join_persistence(),
		"USER1 transport JOIN does not require new fsync")
	server.set("_peer_compatibility", {PEER: {"session_id": SESSION}})
	# A pending older ITEM/LEAVE hides full canonical data and fences JOIN.
	# No fake durable completion or actor ledger mutation is injected.
	server.set("_p1b_item_pending", {"operation_id": "operation/r3c/other",
		"kind": "ITEM"})
	var before_revision := int(service.get_report().get("revision", -1))
	var request := {"logical_player_id": "a", "operation_id": OP}
	server.call("_handle_join", PEER, SESSION, request)
	server.call("_handle_join", PEER, SESSION, request)
	var pending: Array = server.get("_r3c_deferred_admissions")
	check(pending.size() == 1, "same operation retried once in bounded queue")
	check(int(server.get("_r3c_queued_joins")) == 1,
		"only one JOIN admission recorded")
	check(service.get_player("a").is_empty(), "queued JOIN cannot mutate canonical state")
	check(not service.has_durable_replay_operation(OP), "no pre-admission durable replay")
	check(int(service.get_report().get("revision", -1)) == before_revision,
		"no speculative JOIN revision")
	check(int(server.get("_checkpoint_generation")) >= 1, "M6 generation intact")
	check(int(server.get("_rejections")) == 0, "backpressure is not JOIN rejection")

	server.set("_p1b_item_pending", {})
	server.call("_r3c_drain_deferred_admissions")
	check(int(server.get("_r3c_deferred_admissions").size()) == 0,
		"admission drained after gate release")
	check(int(server.get("_r3c_admissions_drained")) == 1,
		"one operation retried, no duplicates")
	check(String(server.get("_peer_to_session").get(PEER, "")) == SESSION,
		"join mapped to the exact transport session")
	check(not service.get_player("a").is_empty(), "canonical JOIN applied once")
	check(int(server.get("_joins")) == 1, "only one canonical JOIN outcome")
	check(int(server.get("_legacy_sync_commit_count")) == 0,
		"USER1 fast JOIN never called LEGACY_COMMAND_SYNC")

	# Different session/peer: an abandoned queued request is discarded
	# without touching the durable ledger or the existing joined player.
	var old_peer := "peer/r3c/join/obsolete"
	var old_session := "transport-session/r3c/join/obsolete/1"
	var old_op := "operation/r3c/join/obsolete/1"
	var compatible: Dictionary = server.get("_peer_compatibility")
	compatible[old_peer] = {"session_id": old_session}
	server.set("_peer_compatibility", compatible)
	server.set("_p1b_item_pending", {"operation_id": "operation/r3c/other2",
		"kind": "ITEM"})
	server.call("_handle_join", old_peer, old_session,
		{"logical_player_id": "b", "operation_id": old_op})
	check(server.get("_r3c_deferred_admissions").size() == 1,
		"second peer joins queued behind pending M6")
	server.call("_handle_disconnect", old_peer, old_session)
	check(server.get("_r3c_deferred_admissions").is_empty(),
		"disconnect removes pending JOIN even without mapping")
	check(not server.get("_peer_compatibility").has(old_peer),
		"old handshake cannot drain under replacement session")
	server.set("_p1b_item_pending", {})
	server.call("_r3c_drain_deferred_admissions")
	check(service.get_player("b").is_empty(),
		"stale queued JOIN never creates ghost player")
	check(not service.has_durable_replay_operation(old_op),
		"stale admission has no durable replay/ACK")
	check(int(server.get("_r3c_admissions_dropped")) >= 1,
		"stale-session invalidation counted")

	check(_ok(server.stop()), "runtime persisted and shut down")
	server.free()
	_finish()

func _port() -> int:
	var udp := PacketPeerUDP.new()
	if udp.bind(0, "127.0.0.1") != OK:
		return 0
	var number := udp.get_local_port()
	udp.close()
	return number

func _ok(v: Dictionary) -> bool:
	return bool(v.get("success", false))

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)

func _finish() -> void:
	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH_R3C_QUEUED_JOIN: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
