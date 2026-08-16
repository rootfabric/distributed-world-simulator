extends SceneTree

const Fingerprint = preload("res://scripts/runtime/networked_gameplay/v0/v0_canonical_state_fingerprint.gd")
const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const ConstructionBundle = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var gameplay := _gameplay_snapshot(_players())
	var item_graph := _item_graph(7, 11, "fixture-a")
	var construction := ConstructionBundle.create(3, [], [])
	var first: Dictionary = Fingerprint.create("EARTH", gameplay, item_graph, construction)
	_assert(bool(first.get("success", false)), "composite fingerprint builds from validated canonical components")
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

	var reversed_players := _players(); reversed_players.reverse()
	var reordered := _gameplay_snapshot(reversed_players)
	_assert(_checksum(reordered, item_graph, construction) == checksum, "input player order does not affect fingerprint")

	var transport_players := _players()
	var player_b: Dictionary = Dictionary(transport_players[1]).duplicate(true)
	player_b["transport_session_id"] = "transport-session/m3/b/new"
	transport_players[1] = player_b
	var transport_changed := _gameplay_snapshot(transport_players)
	_assert(_checksum(transport_changed, item_graph, construction) == checksum, "validated transport churn does not affect canonical fingerprint")

	var moved_players := _players()
	var moved_a: Dictionary = Dictionary(moved_players[0]).duplicate(true)
	moved_a["position"] = {"x": 9.0, "y": 0.0, "z": -4.0}
	moved_players[0] = moved_a
	_assert(_checksum(_gameplay_snapshot(moved_players), item_graph, construction) != checksum, "authoritative transform changes fingerprint")

	var epoch_players := _players()
	var epoch_b: Dictionary = Dictionary(epoch_players[1]).duplicate(true)
	epoch_b["ownership_epoch"] = 2
	epoch_players[1] = epoch_b
	_assert(_checksum(_gameplay_snapshot(epoch_players), item_graph, construction) != checksum, "ownership epoch changes fingerprint")

	var item_changed := _item_graph(8, 12, "fixture-b")
	_assert(_checksum(gameplay, item_changed, construction) != checksum, "Item Graph mutation changes fingerprint")

	var construction_changed := ConstructionBundle.create(4, [], [])
	_assert(_checksum(gameplay, item_graph, construction_changed) != checksum, "Construction mutation changes fingerprint")

	var corrupt_item := item_graph.duplicate(true); corrupt_item["checksum"] = "f".repeat(64)
	_assert(not bool(Fingerprint.create("earth", gameplay, corrupt_item, construction).get("success", true)), "fabricated Item Graph checksum is rejected")
	var corrupt_gameplay := gameplay.duplicate(true); corrupt_gameplay["checksum"] = "e".repeat(64)
	_assert(not bool(Fingerprint.create("earth", corrupt_gameplay, item_graph, construction).get("success", true)), "fabricated gameplay checksum is rejected")
	var corrupt_construction := construction.duplicate(true); corrupt_construction["checksum"] = "d".repeat(64)
	_assert(not bool(Fingerprint.create("earth", gameplay, item_graph, corrupt_construction).get("success", true)), "fabricated Construction checksum is rejected")
	_finish()


func _checksum(gameplay: Dictionary, item_graph: Dictionary, construction: Dictionary) -> String:
	var result: Dictionary = Fingerprint.create("earth", gameplay, item_graph, construction)
	return String(result.get("details", {}).get("checksum", "")) if bool(result.get("success", false)) else ""


func _players() -> Array:
	return [
		{
			"logical_player_id": "a", "player_entity_id": "player/a", "transport_session_id": "transport-session/m3/a/old",
			"ownership_epoch": 1, "connected": true, "position": {"x": 1.0, "y": 0.0, "z": 2.0},
			"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}, "inventory": [], "last_input_sequence": 3,
			"state_revision": 4, "orientation_yaw": 0.2, "flashlight_enabled": false,
		},
		{
			"logical_player_id": "b", "player_entity_id": "player/b", "transport_session_id": "transport-session/m3/b/old",
			"ownership_epoch": 1, "connected": true, "position": {"x": -1.0, "y": 0.0, "z": 3.0},
			"velocity": {"x": 0.0, "y": 0.0, "z": 0.0}, "inventory": [], "last_input_sequence": 2,
			"state_revision": 3, "orientation_yaw": -0.4, "flashlight_enabled": false,
		},
	]


func _gameplay_snapshot(players: Array) -> Dictionary:
	return PlayerSnapshot.create(
		"authority/v0-p2/fingerprint", 1, 9, 999, "region/m1/default", players,
		{"item_id": "item/shared/beacon/1", "available": true, "owner_player_entity_id": "", "revision": 0}
	)


func _item_graph(revision: int, tick: int, marker: String) -> Dictionary:
	var snapshot: Dictionary = {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority/v0-p2/fingerprint",
		"authority_epoch": 1,
		"revision": revision,
		"tick": tick,
		"items": [{"marker": marker}],
		"inventories": {}, "containers": [], "mounts": [], "open_containers": {},
	}
	snapshot["checksum"] = Utils.payload_hash(snapshot)
	return snapshot


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
