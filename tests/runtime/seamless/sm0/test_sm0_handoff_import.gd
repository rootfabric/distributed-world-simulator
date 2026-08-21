extends SceneTree

const Authority = preload("res://scripts/runtime/host_client/multiplayer_gameplay_authority.gd")

var _assertions := 0
var _failed := false


func _init() -> void:
	var authority = Authority.new()
	_expect_success(authority.setup("authority/sm0/b", 1, 0), "setup")
	var session := "transport-session/sm0/a/b/epoch/2"
	var joined: Dictionary = authority.join("a", session, "operation/sm0/test/import-join")
	_expect_success(joined, "join")
	var before: Dictionary = Dictionary(joined.get("details", {}).get("player", {}))
	_expect_close(float(Dictionary(before.get("position", {})).get("x", 0.0)), -5.0, "fresh target starts at spawn")
	var target_ownership_epoch := int(before.get("ownership_epoch", 0))
	var before_state_revision := int(before.get("state_revision", 0))

	var handoff_state := {
		"player_entity_id": "player/a",
		"position": {"x": 0.0, "y": 0.0, "z": 1.25},
		"velocity": {"x": 0.25, "y": 0.0, "z": -0.125},
		"orientation_yaw": PI / 2.0,
		"last_input_sequence": 36,
		"source_state_revision": 37,
	}
	var imported: Dictionary = authority.import_handoff_player_state(
		"a",
		session,
		target_ownership_epoch,
		handoff_state,
		"operation/sm0/test/import-state"
	)
	_expect_success(imported, "handoff import")
	var player: Dictionary = Dictionary(imported.get("details", {}).get("player", {}))
	_expect(String(player.get("player_entity_id", "")) == "player/a", "player identity preserved")
	_expect(String(player.get("transport_session_id", "")) == session, "target session preserved")
	_expect(int(player.get("ownership_epoch", 0)) == target_ownership_epoch, "target ownership epoch preserved")
	_expect_close(float(Dictionary(player.get("position", {})).get("x", 0.0)), 0.0, "position x imported")
	_expect_close(float(Dictionary(player.get("position", {})).get("z", 0.0)), 1.25, "position z imported")
	_expect_close(float(Dictionary(player.get("velocity", {})).get("x", 0.0)), 0.25, "source velocity x imported")
	_expect_close(float(Dictionary(player.get("velocity", {})).get("z", 0.0)), -0.125, "source velocity z imported")
	_expect(not is_equal_approx(float(Dictionary(player.get("velocity", {})).get("x", 0.0)), 5.0), "relocation distance is not velocity")
	_expect_close(float(player.get("orientation_yaw", 0.0)), PI / 2.0, "source yaw imported")
	_expect(int(player.get("last_input_sequence", -1)) == 36, "source input sequence imported")
	_expect(int(player.get("state_revision", 0)) > before_state_revision, "state revision advances above target record")
	_expect(int(player.get("state_revision", 0)) > 37, "state revision advances above source revision")

	var replay: Dictionary = authority.import_handoff_player_state(
		"a",
		session,
		target_ownership_epoch,
		handoff_state,
		"operation/sm0/test/import-state"
	)
	_expect_success(replay, "exact import replay")
	_expect(bool(replay.get("replay", false)), "exact import is idempotent replay")
	var after_replay: Dictionary = authority.get_player("a")
	_expect_close(float(Dictionary(after_replay.get("velocity", {})).get("x", 0.0)), 0.25, "replay does not mutate velocity")
	_expect(int(after_replay.get("state_revision", 0)) == int(player.get("state_revision", 0)), "replay does not advance state revision")

	var stale_state: Dictionary = handoff_state.duplicate(true)
	stale_state["last_input_sequence"] = 35
	var stale: Dictionary = authority.import_handoff_player_state(
		"a",
		session,
		target_ownership_epoch,
		stale_state,
		"operation/sm0/test/import-state-stale"
	)
	_expect(not bool(stale.get("success", false)), "stale sequence rejected")
	_expect(String(stale.get("error_code", "")) == "STALE_HANDOFF_INPUT_SEQUENCE", "stale sequence error is precise")

	if _failed:
		print("SM0 handoff import: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 handoff import: PASS (%d assertions)" % _assertions)
	quit(0)


func _expect_success(result: Dictionary, label: String) -> void:
	_expect(bool(result.get("success", false)), "%s failed: %s" % [label, result])


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("SM0 handoff import assertion failed: %s" % message)


func _expect_close(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), "%s (expected=%s actual=%s)" % [message, expected, actual])
