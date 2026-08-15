extends SceneTree

const Fingerprint = preload("res://scripts/runtime/networked_gameplay/v0/v0_canonical_state_fingerprint.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var gameplay := _gameplay_snapshot()
	var item_graph := {"revision": 7, "tick": 11, "checksum": "a".repeat(64)}
	var construction := {"server_generation": 3, "checksum": "b".repeat(64)}
	var first: Dictionary = Fingerprint.create("EARTH", gameplay, item_graph, construction)
	_assert(bool(first.get("success", false)), "composite fingerprint builds from canonical components")
	if not bool(first.get("success", false)):
		_finish()
		return
	var checksum := String(first.get("details", {}).get("checksum", ""))
	_assert(checksum.length() == 64, "composite fingerprint emits SHA-256 checksum")
	var projection: Dictionary = first.get("details", {}).get("fingerprint", {})
	_assert(String(projection.get("world_id", "")) == "earth", "world id is canonicalized")
	_assert(Array(projection.get("players", [])).size() == 2, "both canonical players are projected")
	_assert(String(Array(projection.get("players", []))[0].get("logical_player_id", "")) == "a", "player order is deterministic")
	_assert(not JSON.stringify(projection).contains("transport-session"), "transport session identity is excluded")
	_assert(not projection.has("server_tick"), "transient server clock is excluded")

	var reordered := gameplay.duplicate(true)
	var reversed_players: Array = Array(reordered.get("players", [])).duplicate(true)
	reversed_players.reverse()
	reordered["players"] = reversed_players
	var second: Dictionary = Fingerprint.create("earth", reordered, item_graph, construction)
	_assert(String(second.get("details", {}).get("checksum", "")) == checksum, "input player order does not affect fingerprint")

	var transport_changed := gameplay.duplicate(true)
	var transport_players: Array = Array(transport_changed.get("players", [])).duplicate(true)
	var player_b: Dictionary = Dictionary(transport_players[1]).duplicate(true)
	player_b["transport_session_id"] = "transport-session/m3/b/new"
	transport_players[1] = player_b
	transport_changed["players"] = transport_players
	var transport_result: Dictionary = Fingerprint.create("earth", transport_changed, item_graph, construction)
	_assert(String(transport_result.get("details", {}).get("checksum", "")) == checksum, "transport churn does not affect canonical fingerprint")

	var moved := gameplay.duplicate(true)
	var moved_players: Array = Array(moved.get("players", [])).duplicate(true)
	var moved_a: Dictionary = Dictionary(moved_players[0]).duplicate(true)
	moved_a["position"] = {"x": 9.0, "y": 0.0, "z": -4.0}
	moved_players[0] = moved_a
	moved["players"] = moved_players
	_assert(_checksum(moved, item_graph, construction) != checksum, "authoritative transform changes fingerprint")

	var epoch_changed := gameplay.duplicate(true)
	var epoch_players: Array = Array(epoch_changed.get("players", [])).duplicate(true)
	var epoch_b: Dictionary = Dictionary(epoch_players[1]).duplicate(true)
	epoch_b["ownership_epoch"] = 2
	epoch_players[1] = epoch_b
	epoch_changed["players"] = epoch_players
	_assert(_checksum(epoch_changed, item_graph, construction) != checksum, "ownership epoch changes fingerprint")

	var item_changed := item_graph.duplicate(true)
	item_changed["revision"] = 8
	item_changed["tick"] = 12
	item_changed["checksum"] = "c".repeat(64)
	_assert(_checksum(gameplay, item_changed, construction) != checksum, "Item Graph mutation changes fingerprint")

	var construction_changed := construction.duplicate(true)
	construction_changed["server_generation"] = 4
	construction_changed["checksum"] = "d".repeat(64)
	_assert(_checksum(gameplay, item_graph, construction_changed) != checksum, "Construction mutation changes fingerprint")

	_assert(not bool(Fingerprint.create("earth", gameplay, {}, construction).get("success", true)), "missing Item Graph is rejected")
	_assert(not bool(Fingerprint.create("earth", gameplay, item_graph, {}).get("success", true)), "missing Construction bundle is rejected")
	_finish()


func _checksum(gameplay: Dictionary, item_graph: Dictionary, construction: Dictionary) -> String:
	var result: Dictionary = Fingerprint.create("earth", gameplay, item_graph, construction)
	return String(result.get("details", {}).get("checksum", "")) if bool(result.get("success", false)) else ""


func _gameplay_snapshot() -> Dictionary:
	return {
		"players": [
			{
				"logical_player_id": "a",
				"player_entity_id": "player/a",
				"transport_session_id": "transport-session/m3/a/old",
				"ownership_epoch": 1,
				"connected": true,
				"state_revision": 4,
				"position": {"x": 1.0, "y": 0.0, "z": 2.0},
				"orientation_yaw": 0.2,
			},
			{
				"logical_player_id": "b",
				"player_entity_id": "player/b",
				"transport_session_id": "transport-session/m3/b/old",
				"ownership_epoch": 1,
				"connected": true,
				"state_revision": 3,
				"position": {"x": -1.0, "y": 0.0, "z": 3.0},
				"orientation_yaw": -0.4,
			},
		],
		"server_tick": 999,
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P2 canonical state fingerprint: %d assertions, 0 failures" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-P2 canonical state fingerprint: %d assertions, %d failures" % [assertions, failures.size()])
	quit(1)
