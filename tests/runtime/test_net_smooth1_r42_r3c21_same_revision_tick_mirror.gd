extends SceneTree

# NET-SMOOTH1 R4.2 R3C21 R2 regression: same-revision checkpoint progression
# must tolerate ownership.server_tick mirroring (and its derived checksum).
#
# RED (pre-fix): two authoritative checkpoints at the same state_revision whose
#   networked_gameplay_state differs ONLY by the mirrored ownership.server_tick
#   (and therefore the derived ownership.checksum) are rejected with
#   SAME_REVISION_AUTHORITATIVE_MUTATION -> shutdown-final checkpoint fails
#   with M6_CHECKPOINT_PERSIST_FAILED / PERSISTENCE_FATAL on the r3-slow-item
#   canary when no movement command advances the revision after the last
#   periodic checkpoint.
# GREEN (post-fix): the semantic projection erases the mirrored
#   ownership.server_tick together with its derived ownership.checksum; any
#   real canonical mutation (player row or ownership revision) is still
#   rejected.

const CheckpointScript = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const EntitySnapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

var _failures := 0
var _assertions := 0


func _check(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		printerr("FAIL: %s" % message)


func _ownership_state(server_tick: int, ownership_revision: int, player_left_tick: int) -> Dictionary:
	return UtilsScript.finalize_json_checksum({
		"schema": "planet_simulator.player_ownership_state.v1",
		"authority_owner_id": "smooth-server-test",
		"authority_epoch": 1,
		"revision": ownership_revision,
		"server_tick": server_tick,
		"players": [
			{
				"connected": false, "joined_tick": 1, "left_tick": 0,
				"logical_player_id": "a", "ownership_epoch": 1,
				"player_entity_id": "player/a", "transport_session_id": "",
			},
			{
				"connected": false, "joined_tick": 4, "left_tick": player_left_tick,
				"logical_player_id": "b", "ownership_epoch": 2,
				"player_entity_id": "player/b", "transport_session_id": "",
			},
		],
		"checksum": "",
	})


func _gameplay_durable_state(server_tick: int, state_revision: int, ownership: Dictionary) -> Dictionary:
	return UtilsScript.finalize_json_checksum({
		"schema": "planet_simulator.networked_gameplay_durable_state.v2",
		"authority_owner_id": "smooth-server-test",
		"authority_epoch": 1,
		"revision": state_revision,
		"server_tick": server_tick,
		"region_id": "region/earth/default",
		"topology_adapter": "topology/earth/default",
		"profile": "profile/default",
		"players": {"schema": "planet_simulator.player_registry_state.v1", "players": [], "checksum": ""},
		"ownership": ownership,
		"shared_item": {"schema": "planet_simulator.shared_item_fixture_state.v1", "items": [], "checksum": ""},
		"canonical_item_graph": {"schema": "planet_simulator.canonical_multiplayer_item_graph.v1", "items": [], "checksum": ""},
		"checksum": "",
	})


func _authority_state(server_tick: int, state_revision: int, ownership: Dictionary) -> Dictionary:
	var gameplay: Dictionary = _gameplay_durable_state(server_tick, state_revision, ownership)
	var snapshot: Dictionary = EntitySnapshot.normalize(EntitySnapshot.create(
		"snapshot/m6/dedicated/%d" % state_revision,
		"aggregate/m6/dedicated-gameplay",
		"networked_gameplay_runtime",
		state_revision,
		"smooth-server-test",
		1,
		server_tick,
		{
			"schema": EntitySnapshot.SPATIAL_REF_SCHEMA,
			"universe_id": "planet-simulator",
			"instance_id": "m6-dedicated",
			"space_id": "networked-gameplay",
			"frame_id": "frame/m6/dedicated",
			"position_m": [0.0, 0.0, 0.0],
			"rotation_xyzw": [0.0, 0.0, 0.0, 1.0],
			"linear_velocity_mps": [0.0, 0.0, 0.0],
			"angular_velocity_rps": [0.0, 0.0, 0.0],
			"sample_time_s": float(server_tick),
		},
		{"region_id": "region/earth/default"},
		{},
		{
			"networked_gameplay_state": gameplay,
			"durable_state_checksum": String(gameplay.get("checksum", "")),
		}
	))
	return {
		"schema": "planet_simulator.m6_dedicated_gameplay_authority_adapter.v1",
		"authority_owner_id": "smooth-server-test",
		"authority_epoch": 1,
		"server_tick": server_tick,
		"session_id": "session/m6/dedicated",
		"current_snapshot": snapshot,
		"durable_state_checksum": String(gameplay.get("checksum", "")),
	}


func _checkpoint(generation: int, previous_generation: int, server_tick: int, state_revision: int, ownership: Dictionary) -> Dictionary:
	return CheckpointScript.create(
		"checkpoint/m6/dedicated/%d" % generation,
		generation,
		previous_generation,
		_authority_state(server_tick, state_revision, ownership),
		{"schema": "planet_simulator.replay_outbox.v1", "records": []},
		"operation/test/seed",
		server_tick
	)


func _init() -> void:
	# Baseline shape mirrors the observed canary failure exactly: same
	# state_revision, later fixed tick, ownership rows and revision unchanged,
	# only the mirrored ownership.server_tick (and derived checksum) advanced.
	var current: Dictionary = _checkpoint(59, 58, 5726, 5408, _ownership_state(5726, 6, 5))
	var candidate_tick_mirror: Dictionary = _checkpoint(60, 59, 5773, 5408, _ownership_state(5773, 6, 5))

	var mirror_result: Dictionary = CheckpointScript.validate_progression(candidate_tick_mirror, current)
	_check(
		bool(mirror_result.get("success", false)),
		"same-revision ownership tick mirroring must not fail progression: %s" % String(mirror_result.get("message", ""))
	)

	# A real canonical mutation (player row changed) must stay rejected.
	var candidate_row_mutation: Dictionary = _checkpoint(61, 60, 5800, 5408, _ownership_state(5800, 6, 7))
	var row_result: Dictionary = CheckpointScript.validate_progression(candidate_row_mutation, candidate_tick_mirror)
	_check(
		not bool(row_result.get("success", false)),
		"same-revision player row mutation must stay rejected"
	)
	_check(
		String(row_result.get("error_code", "")) == "SAME_REVISION_AUTHORITATIVE_MUTATION"
		or String(row_result.get("error_code", "")) == "AUTHORITATIVE_CHECKPOINT_ROLLBACK",
		"row mutation rejection keeps the canonical error code: %s" % String(row_result.get("error_code", ""))
	)

	# A real canonical mutation (ownership revision advanced) must stay rejected.
	var candidate_ownership_revision: Dictionary = _checkpoint(61, 60, 5800, 5408, _ownership_state(5800, 7, 5))
	var revision_result: Dictionary = CheckpointScript.validate_progression(candidate_ownership_revision, candidate_tick_mirror)
	_check(
		not bool(revision_result.get("success", false)),
		"same-revision ownership revision mutation must stay rejected"
	)

	# Revision progression still accepted.
	var candidate_advanced: Dictionary = _checkpoint(61, 60, 5800, 5412, _ownership_state(5800, 7, 5))
	var advanced_result: Dictionary = CheckpointScript.validate_progression(candidate_advanced, candidate_tick_mirror)
	_check(
		bool(advanced_result.get("success", false)),
		"higher state_revision progression must stay accepted: %s" % String(advanced_result.get("message", ""))
	)

	if _failures == 0:
		print("NET_SMOOTH_R3C21_SAME_REVISION_TICK_MIRROR PASS assertions=%d failures=0" % _assertions)
		quit(0)
	else:
		printerr("NET_SMOOTH_R3C21_SAME_REVISION_TICK_MIRROR FAIL assertions=%d failures=%d" % [_assertions, _failures])
		quit(1)
