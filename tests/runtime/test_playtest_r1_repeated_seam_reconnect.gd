extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd")
const PLAYER := "repeat-player"
var service
var tick := 0
var sequence := 0
var session := "transport-session/repeated-seam/1"
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	service = Service.new()
	check_ok(service.setup("authority/repeated-seam", 1, 0, {
		"profile": "MULTIPLAYER_CORE", "topology_adapter": "ENET",
		"region_id": "region/m3/single-server", "playable_sandbox": true,
		"fixed_tick_authority": true,
	}), "setup")
	check_ok(service.join(PLAYER, session, "operation/repeated-seam/join/1"), "initial JOIN")
	var entity: String = service.get_player(PLAYER).get("player_entity_id", "")
	for round_index in range(3):
		if round_index > 0:
			var old_session := session
			check_ok(service.leave_transport_session(session,
				"operation/repeated-seam/leave/%d" % round_index), "leave after roundtrip")
			session = "transport-session/repeated-seam/%d" % (round_index + 1)
			check_ok(service.join(PLAYER, session,
				"operation/repeated-seam/join/%d" % (round_index + 1)), "reconnect after roundtrip")
			sequence = int(service.get_player(PLAYER).get("last_input_sequence", 0))
			var stale: Dictionary = service.simulate_fixed_movement_tick(PLAYER,
				old_session, round_index, sequence + 1, {}, 1.0 / 60.0)
			check(not bool(stale.get("success", false)), "old transport session remains rejected")
		var player: Dictionary = service.get_player(PLAYER)
		var replay: Dictionary = service.export_live_player_replay(PLAYER)
		check_ok(service.validate_live_player_replay(PLAYER, replay), "historical replay validates")
		if round_index > 0:
			_verify_leave_receipt(replay, "operation/repeated-seam/leave/%d" % round_index)
		check(player.get("player_entity_id", "") == entity, "same entity after JOIN")
		check(int(player.get("ownership_epoch", 0)) == round_index + 1, "new transport ownership epoch")
		if not cross(1.0, "region/user1/b"):
			break
		if not cross(-1.0, "region/user1/a"):
			break
		check(int(service.get_product_seam_state(PLAYER).get("roundtrips", 0)) == round_index + 1,
			"roundtrip counted exactly once")
		check(service.export_live_player_replay(PLAYER) == replay, "roundtrip preserves exact historical receipts")
	service.shutdown()
	for reason in failures:
		push_error(reason)
	print("PLAYTEST_R1_REPEATED_SEAM_RECONNECT: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func cross(direction: float, region: String) -> bool:
	var ownership := int(service.get_player(PLAYER).get("ownership_epoch", 0))
	for _index in range(250):
		tick += 1
		sequence += 1
		var advanced: Dictionary = service.advance_fixed_server_tick(tick)
		if not bool(advanced.get("success", false)):
			check_ok(advanced, "advance tick")
			return false
		var moved: Dictionary = service.simulate_fixed_movement_tick(PLAYER, session,
			ownership, sequence, {"move_x": direction, "move_z": 0.0,
			"look_yaw": 0.0, "look_pitch": 0.0, "sprint": true,
			"jump_pressed": false, "delta_seconds": 1.0 / 60.0}, 1.0 / 60.0)
		if not bool(moved.get("success", false)):
			print("REPEATED_SEAM_DIAGNOSTIC ", JSON.stringify({
				"player": service.get_player(PLAYER),
				"ownership": service.get("_ownership").get_player(PLAYER),
				"result": moved}))
			check_ok(moved, "cross " + region)
			return false
		if service.get_product_seam_state(PLAYER).get("region_id", "") == region:
			check(true, "cross " + region)
			return true
	check(false, "cross timed out: " + region)
	return false

func _verify_leave_receipt(replay: Dictionary, operation: String) -> void:
	check(replay.has(operation), "LEAVE receipt is retained")
	if not replay.has(operation):
		return
	var receipt: Dictionary = replay[operation]
	var record: Dictionary = receipt["result"]["details"]["player"]
	check(record["connected"] == false, "historical LEAVE stays disconnected")
	check(not bool(service.get("_players").validate_live_player_record(record).get("success", false)),
		"disconnected receipt cannot become a live transfer row")
	for field in ["connected", "transport_session_id", "logical_player_id", "position"]:
		var changed: Dictionary = receipt.duplicate(true)
		var actor: Dictionary = changed["result"]["details"]["player"]
		match field:
			"connected": actor[field] = "false"
			"transport_session_id": actor[field] = "invalid-session"
			"logical_player_id": actor[field] = "another-player"
			"position": actor[field] = {"x": INF, "y": 0.0, "z": 0.0}
		var validation: Dictionary = service.validate_live_player_replay(PLAYER, {operation: changed})
		check(not bool(validation.get("success", false)), "invalid historical " + field + " rejected")

func check_ok(result: Dictionary, label: String) -> void:
	check(bool(result.get("success", false)), label + " error=" + String(result.get("error_code", "")))

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
