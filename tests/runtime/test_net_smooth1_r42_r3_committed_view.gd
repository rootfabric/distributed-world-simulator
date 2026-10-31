extends SceneTree

# R3.1 standalone pure-wire falsifier. Real slow-writer traffic is a separate gate.
const View = preload("res://scripts/runtime/networked_gameplay/contracts/committed_movement_view.gd")
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Compact = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player: Dictionary = _player("a", "transport-session/r3/a/1")
	var committed: Dictionary = Full.create(
		"simulation/test", 1, 42, 100, "region/user1/a", [player],
		{"item_id": "item/shared/beacon/1", "available": true,
		"owner_player_entity_id": "", "revision": 7}
	)
	check(_ok(Full.validate(committed)), "committed fixture valid")
	var live: Dictionary = player.duplicate(true)
	live["position"] = {"x": 2.0, "y": 0.0, "z": 4.0}
	live["velocity"] = {"x": 1.0, "y": 0.0, "z": -1.0}
	live["orientation_yaw"] = 0.6
	live["last_input_sequence"] = 88
	live["state_revision"] = 9009
	live["inventory"] = ["item/speculative/not-committed"]
	var built: Dictionary = View.project(committed, [live, _player("b", "transport-session/r3/b/1")], 103)
	check(_ok(built), "committed view successfully built")
	if _ok(built):
		var frame: Dictionary = built["details"]["snapshot"]
		var row: Dictionary = frame["players"][0]
		check(int(frame["revision"]) == 42 and int(frame["server_tick"]) == 103, "only server_tick advanced")
		check(int(frame["shared_item"]["revision"]) == 7 and frame["shared_item"]["available"], "committed shared item retained")
		check(Array(row["inventory"]).is_empty() and int(row["state_revision"]) == 1, "no speculative item or state revision")
		check(float(row["position"]["x"]) == 2.0 and int(row["last_input_sequence"]) == 88, "live movement and sequence")
		check(float(row["orientation_yaw"]) == 0.6, "live facing orientation")
		check(Array(frame["players"]).size() == 1, "no speculative join included")
		check(_ok(Full.validate(frame)), "full hybrid checksum valid")
		var encoded: Dictionary = Compact.encode(frame)
		check(_ok(encoded), "compact projection encoded")
		if _ok(encoded):
			check(_ok(Compact.decode(encoded["details"]["snapshot"])), "nested full checksum valid after decode")
			var tampered: Dictionary = encoded["details"]["snapshot"].duplicate(true)
			tampered["p"][0]["n"] = ["item/poison"]
			check(not _ok(Compact.decode(tampered)), "tampered compact inventory detected")
		check(View.peer_is_fenced(frame, "a", "transport-session/r3/a/1"), "correct session eligible")
		check(not View.peer_is_fenced(frame, "a", "transport-session/r3/a/2"), "stale session rejected")
		check(not View.peer_is_fenced(frame, "b", "transport-session/r3/b/1"), "new player rejected")
		row["position"]["x"] = 999.0
		check(float(committed["players"][0]["position"]["x"]) == 0.0, "committed DTO not mutated")
	for field in ["transport_session_id", "ownership_epoch", "player_entity_id", "connected"]:
		var changed: Dictionary = live.duplicate(true)
		match field:
			"transport_session_id": changed[field] = "transport-session/r3/a/2"
			"ownership_epoch": changed[field] = 2
			"player_entity_id": changed[field] = "player/b"
			"connected": changed[field] = false
		var held: Dictionary = View.project(committed, [changed], 104)
		check(_ok(held), "safe projection after changed "+field)
		if _ok(held):
			check(float(held["details"]["snapshot"]["players"][0]["position"]["x"]) == 0.0, "epoch/session mismatch cannot move committed row "+field)
	var frames := 0
	for tick in range(103, 133, 3):
		var projected: Dictionary = View.project(committed, [live], tick)
		if _ok(projected):
			var wire: Dictionary = Compact.encode(projected["details"]["snapshot"])
			check(_ok(wire) and _ok(Compact.decode(wire["details"]["snapshot"])), "50ms frame checksum %d" % tick)
			frames += 1
	check(frames == 10, "10 proof-safe 20Hz movement samples")
	for failure in failures:
		push_error(failure)
	print("NET_SMOOTH1_R42_R3_COMMITTED_VIEW: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _player(id: String, session: String) -> Dictionary:
	return {"logical_player_id": id, "player_entity_id": "player/" + id,
		"transport_session_id": session, "ownership_epoch": 1, "connected": true,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}, "inventory": [],
		"last_input_sequence": 0, "state_revision": 1,
		"orientation_yaw": 0.0, "flashlight_enabled": false}

func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))

func check(good: bool, label: String) -> void:
	assertions += 1
	if not good:
		failures.append(label)
