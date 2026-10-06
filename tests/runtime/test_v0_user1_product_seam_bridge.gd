extends SceneTree

const SeamService = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
)
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const PLAYER := "user1-seam-player"
const SESSION_A := "transport-session/user1-seam/a"
const SESSION_B := "transport-session/user1-seam/b"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = SeamService.new()
	var setup: Dictionary = service.setup(
		"authority/product/user1-test",
		1,
		0,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	_ok(setup, "product seam service setup")

	var join: Dictionary = service.join(
		PLAYER,
		SESSION_A,
		"operation/user1/seam/join-a"
	)
	_ok(join, "ordinary product join")
	var first_player: Dictionary = service.get_player(PLAYER)
	_check(not first_player.is_empty(), "joined player is visible")
	var player_entity_id := String(first_player.get("player_entity_id", ""))
	var ownership_epoch := int(first_player.get("ownership_epoch", 0))
	_check(player_entity_id == "player/%s" % PLAYER, "product player entity identity is canonical")
	_check(ownership_epoch == 1, "first product ownership epoch is one")

	var graph_before: Dictionary = service.create_canonical_item_graph_snapshot()
	var resource_before: Dictionary = service.create_resource_mining_snapshot()
	_check(not graph_before.is_empty(), "primary M4 snapshot exists")
	_check(not resource_before.is_empty(), "primary ResourceMining snapshot exists")
	var graph_checksum := String(graph_before.get("checksum", ""))
	var resource_checksum := String(resource_before.get("checksum", ""))

	var tick := 0
	var sequence := 0
	var saw_secondary := false
	var frozen_mutation_checked := false
	var reached_roundtrip := false
	for _step in range(900):
		tick += 1
		var advanced: Dictionary = service.advance_fixed_server_tick(tick)
		if not bool(advanced.get("success", false)):
			_fail("fixed tick advance failed: %s" % String(advanced.get("error_code", "")))
			break
		var seam: Dictionary = service.get_product_seam_state(PLAYER)
		var on_secondary := String(seam.get("region_id", "")) == "region/user1/b"
		var move_x := -1.0 if on_secondary else 1.0
		sequence += 1
		var moved: Dictionary = service.simulate_fixed_movement_tick(
			PLAYER,
			SESSION_A,
			ownership_epoch,
			sequence,
			{
				"move_x": move_x,
				"move_z": 0.0,
				"look_yaw": 0.0,
				"look_pitch": 0.0,
				"jump_pressed": false,
				"sprint": true,
				"delta_seconds": 1.0 / 60.0,
			},
			1.0 / 60.0
		)
		if not bool(moved.get("success", false)):
			_fail("fixed movement failed: %s" % String(moved.get("error_code", "")))
			break

		seam = service.get_product_seam_state(PLAYER)
		if String(seam.get("region_id", "")) == "region/user1/b":
			saw_secondary = true
			if not frozen_mutation_checked:
				_check(not service.product_mutation_allowed(PLAYER), "non-movement product mutation is fenced on B")
				var blocked: Dictionary = service.handle_canonical_item_command(
					PLAYER,
					SESSION_A,
					ownership_epoch,
					"operation/user1/seam/blocked-item",
					"inventory.select_hotbar",
					{"selected_hotbar_index": 0}
				)
				_check(
					not bool(blocked.get("success", false))
					and String(blocked.get("error_code", "")) == "USER1_SEAM_GAMEPLAY_MUTATION_FROZEN",
					"item mutation fails closed while movement owner is B"
				)
				frozen_mutation_checked = true
		if int(seam.get("roundtrips", 0)) >= 1:
			reached_roundtrip = true
			break

	_check(saw_secondary, "player was really owned by secondary authority B")
	_check(reached_roundtrip, "player completed real A→B→A SM1 roundtrip")
	var final_seam: Dictionary = service.get_product_seam_state(PLAYER)
	_check(String(final_seam.get("region_id", "")) == "region/user1/a", "roundtrip returns player to product region A")
	_check(int(final_seam.get("crossings", 0)) == 2, "roundtrip contains exactly two ownership crossings")
	_check(int(final_seam.get("roundtrips", 0)) == 1, "roundtrip evidence increments once")
	_check(service.can_persist_product_state(), "temporary seam gates are released after roundtrip")
	_check(service.product_mutation_allowed(PLAYER), "product mutation resumes after roundtrip")

	var after_player: Dictionary = service.get_player(PLAYER)
	_check(String(after_player.get("player_entity_id", "")) == player_entity_id, "player entity survives seam")
	_check(String(after_player.get("transport_session_id", "")) == SESSION_A, "transport session survives seam")
	_check(int(after_player.get("ownership_epoch", 0)) == ownership_epoch, "client ownership epoch survives seam")
	_check(int(after_player.get("last_input_sequence", 0)) == sequence, "input sequence survives seam")

	var graph_after: Dictionary = service.create_canonical_item_graph_snapshot()
	var resource_after: Dictionary = service.create_resource_mining_snapshot()
	_check(String(graph_after.get("checksum", "")) == graph_checksum, "global M4 Item Graph is not copied or mutated by movement seam")
	_check(String(resource_after.get("checksum", "")) == resource_checksum, "ResourceMining owner is unchanged by movement seam")

	var aggregate: Dictionary = service.create_snapshot()
	var aggregate_copy := aggregate.duplicate(true)
	var aggregate_checksum := String(aggregate_copy.get("checksum", ""))
	aggregate_copy.erase("checksum")
	_check(
		aggregate_checksum == NetworkUtils.payload_hash(aggregate_copy),
		"aggregate gameplay snapshot checksum remains canonical"
	)

	var durable: Dictionary = service.export_durable_state()
	_check(not durable.is_empty(), "ordinary durable export works after seam gates release")
	_ok(service.validate_durable_state(durable), "post-seam durable state validates")

	var left: Dictionary = service.leave(
		PLAYER,
		SESSION_A,
		"operation/user1/seam/leave-a"
	)
	_ok(left, "ordinary leave works after seam")
	var rejoin: Dictionary = service.join(
		PLAYER,
		SESSION_B,
		"operation/user1/seam/join-b"
	)
	_ok(rejoin, "ordinary reconnect join works after seam")
	var rejoined: Dictionary = service.get_player(PLAYER)
	_check(String(rejoined.get("player_entity_id", "")) == player_entity_id, "reconnect preserves player entity after seam")
	_check(String(rejoined.get("transport_session_id", "")) == SESSION_B, "reconnect installs new transport session")
	_check(int(rejoined.get("ownership_epoch", 0)) == ownership_epoch + 1, "reconnect advances ownership epoch once")

	var report: Dictionary = service.get_report()
	var seam_report: Dictionary = Dictionary(report.get("user1_product_seam", {}))
	_check(not bool(seam_report.get("canonical_state_owned", true)), "seam composition owns no canonical gameplay state")
	var secondary_report: Dictionary = Dictionary(seam_report.get("secondary", {}))
	_check(bool(secondary_report.get("movement_only", false)), "secondary authority is movement-only")
	_check(int(secondary_report.get("canonical_domain_count", -1)) == 0, "secondary creates zero canonical gameplay domains")
	_check(not bool(secondary_report.get("canonical_item_graph_ready", true)), "secondary has no M4 Item Graph owner")
	_check(not bool(secondary_report.get("resource_mining_ready", true)), "secondary has no ResourceMining owner")
	_check(not bool(secondary_report.get("shared_item_ready", true)), "secondary has no shared-item owner")
	_check(int(seam_report.get("active_binding_count", -1)) == 0, "no live handoff gates remain after roundtrip")
	_check(int(seam_report.get("transfer_failures", -1)) == 0, "no seam transfer failure occurred")
	_check(Array(seam_report.get("transfers", [])).size() == 2, "two SM1 transfer receipts are retained as bounded evidence")

	service.shutdown()
	_test_two_player_visibility_roundtrip()
	if failures.is_empty():
		print("USER1 PRODUCT SEAM BRIDGE: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("USER1 PRODUCT SEAM BRIDGE: FAIL (%d assertions, %d failures)" % [
		assertions,
		failures.size(),
	])
	quit(1)


func _test_two_player_visibility_roundtrip() -> void:
	var service = SeamService.new()
	var setup: Dictionary = service.setup(
		"authority/product/user1-two-player-test",
		1,
		0,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	_ok(setup, "two-player seam service setup")
	if not bool(setup.get("success", false)):
		service.shutdown()
		return

	var players := ["user1-seam-a", "user1-seam-b"]
	var sessions := {
		"user1-seam-a": "transport-session/user1-seam/two/a",
		"user1-seam-b": "transport-session/user1-seam/two/b",
	}
	var sequences := {"user1-seam-a": 0, "user1-seam-b": 0}
	for player_id in players:
		_ok(
			service.join(
				player_id,
				String(sessions[player_id]),
				"operation/user1/seam/two/join/%s" % player_id
			),
			"two-player ordinary join %s" % player_id
		)

	_check(
		_snapshot_has_players(service.create_snapshot(), players),
		"two-player initial snapshot contains both actors"
	)

	var tick := 0
	var both_secondary := false
	var both_returned := false
	for _step in range(1800):
		tick += 1
		var advanced: Dictionary = service.advance_fixed_server_tick(tick)
		if not bool(advanced.get("success", false)):
			_fail(
				"two-player fixed tick failed at %d: %s" % [
					tick,
					String(advanced.get("error_code", "")),
				]
			)
			break

		var states: Dictionary = {}
		for player_id in players:
			states[player_id] = service.get_product_seam_state(player_id)
		var on_b_a := String(Dictionary(states[players[0]]).get("region_id", "")) == "region/user1/b"
		var on_b_b := String(Dictionary(states[players[1]]).get("region_id", "")) == "region/user1/b"
		if on_b_a and on_b_b:
			both_secondary = true
		var direction := -1.0 if both_secondary else 1.0

		for player_id in players:
			sequences[player_id] = int(sequences[player_id]) + 1
			var current: Dictionary = service.get_player(player_id)
			if current.is_empty():
				_fail(
					"two-player actor missing before movement: %s tick=%d report=%s" % [
						player_id,
						tick,
						JSON.stringify(service.get_report()),
					]
				)
				break
			var moved: Dictionary = service.simulate_fixed_movement_tick(
				player_id,
				String(sessions[player_id]),
				int(current.get("ownership_epoch", 0)),
				int(sequences[player_id]),
				{
					"move_x": direction,
					"move_z": 0.0,
					"look_yaw": 0.0,
					"look_pitch": 0.0,
					"jump_pressed": false,
					"sprint": true,
					"delta_seconds": 1.0 / 60.0,
				},
				1.0 / 60.0
			)
			if not bool(moved.get("success", false)):
				_fail(
					"two-player movement/seam failed: player=%s tick=%d code=%s report=%s" % [
						player_id,
						tick,
						String(moved.get("error_code", "")),
						JSON.stringify(service.get_report()),
					]
				)
				break

		var aggregate: Dictionary = service.create_snapshot()
		if not _snapshot_has_players(aggregate, players):
			_fail(
				"two-player aggregate lost actor: tick=%d players=%s report=%s" % [
					tick,
					JSON.stringify(aggregate.get("players", [])),
					JSON.stringify(service.get_report()),
				]
			)
			break

		if both_secondary:
			var seam_a: Dictionary = service.get_product_seam_state(players[0])
			var seam_b: Dictionary = service.get_product_seam_state(players[1])
			if (
				int(seam_a.get("roundtrips", 0)) >= 1
				and int(seam_b.get("roundtrips", 0)) >= 1
			):
				both_returned = true
				break

	_check(both_secondary, "both product players reached secondary authority B")
	_check(both_returned, "both product players completed A-B-A roundtrip")
	_check(
		_snapshot_has_players(service.create_snapshot(), players),
		"two-player final snapshot still contains both actors"
	)
	var report: Dictionary = service.get_report()
	var seam_report: Dictionary = Dictionary(report.get("user1_product_seam", {}))
	_check(
		int(seam_report.get("transfer_failures", -1)) == 0,
		"two-player roundtrip has zero transfer failures"
	)
	_check(
		int(seam_report.get("active_binding_count", -1)) == 0,
		"two-player roundtrip releases all temporary gates"
	)
	service.shutdown()


func _snapshot_has_players(snapshot: Dictionary, expected_ids: Array) -> bool:
	var seen: Dictionary = {}
	for player_value in snapshot.get("players", []):
		if player_value is Dictionary:
			var player: Dictionary = player_value
			if bool(player.get("connected", false)):
				seen[String(player.get("logical_player_id", ""))] = true
	for player_id in expected_ids:
		if not seen.has(String(player_id)):
			return false
	return seen.size() == expected_ids.size()


func _ok(result: Dictionary, message: String) -> void:
	_check(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _fail(message: String) -> void:
	failures.append(message)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
