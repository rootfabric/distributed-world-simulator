extends SceneTree

# NET-SMOOTH1 R4.2 R3C.2 R2 repair falsifier.
#
# Production reproduction (3/3 r3-slow-item canaries on the Windows double):
# the drain-time final checkpoint was rejected with
# SAME_REVISION_AUTHORITATIVE_MUTATION at
# $.domain_components.networked_gameplay_state.ownership.server_tick
# and escalated to PERSISTENCE_FATAL, so the server never wrote END.
#
# Root cause: the durable gameplay export embeds the moving fixed tick as
# ownership.server_tick, while state_revision only advances on canonical
# mutations. server_tick is a tick-derived field exactly like the top-level
# server_tick and spatial_ref.sample_time_s, which the same-revision semantic
# projection already excludes. This test pins that boundary:
#   - ownership.server_tick alone may advance at a constant state_revision;
#   - ownership.revision or ownership.players still reject at the same
#     state_revision (no semantic mutation slips through).

const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Snapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

const BASE_TICK := 500
const NEXT_TICK := 520
const BASE_REVISION := 11
const OWNERSHIP_REVISION := 3
const CHECKSUM_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const CHECKSUM_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var baseline: Dictionary = _checkpoint(1, 0, BASE_REVISION, BASE_TICK, OWNERSHIP_REVISION, BASE_TICK)
	_assert_ok(Checkpoint.validate(baseline), "Baseline ownership checkpoint validates")

	# RED/GREEN subject: only ownership.server_tick advanced between two
	# captures of the same canonical revision. This is the exact drain
	# signature from the canary PERSISTENCE_FATAL reports.
	var ownership_tick_only: Dictionary = baseline.duplicate(true)
	ownership_tick_only["checkpoint_id"] = "checkpoint/r3c2-ownership-tick/2"
	ownership_tick_only["generation"] = 2
	ownership_tick_only["previous_generation"] = 1
	ownership_tick_only["server_tick"] = NEXT_TICK
	ownership_tick_only["committed_at_tick"] = NEXT_TICK
	ownership_tick_only["authority_state"]["server_tick"] = NEXT_TICK
	var tick_snapshot: Dictionary = ownership_tick_only["authority_state"]["current_snapshot"]
	tick_snapshot["snapshot_id"] = "snapshot/r3c2-ownership-tick/%d/%d" % [BASE_REVISION, NEXT_TICK]
	tick_snapshot["server_tick"] = NEXT_TICK
	tick_snapshot["spatial_ref"]["sample_time_s"] = float(NEXT_TICK)
	var gameplay: Dictionary = tick_snapshot["domain_components"]["networked_gameplay_state"]
	gameplay["server_tick"] = NEXT_TICK
	gameplay["ownership"]["server_tick"] = NEXT_TICK
	gameplay["checksum"] = CHECKSUM_B
	tick_snapshot["domain_components"]["durable_state_checksum"] = CHECKSUM_B
	tick_snapshot["checksum"] = Snapshot.compute_checksum(tick_snapshot)
	ownership_tick_only["checksum"] = Checkpoint.compute_checksum(ownership_tick_only)
	_assert_ok(Checkpoint.validate(ownership_tick_only), "Ownership tick-only checkpoint validates")
	_assert_ok(
		Checkpoint.validate_progression(ownership_tick_only, baseline),
		"Same-revision ownership.server_tick-only progression is accepted"
	)

	# The invariant must keep failing closed for real semantic mutations.
	var ownership_revision_mutation: Dictionary = ownership_tick_only.duplicate(true)
	ownership_revision_mutation["checkpoint_id"] = "checkpoint/r3c2-ownership-tick/revision"
	ownership_revision_mutation["authority_state"]["current_snapshot"]["domain_components"]["networked_gameplay_state"]["ownership"]["revision"] = OWNERSHIP_REVISION + 1
	ownership_revision_mutation["authority_state"]["current_snapshot"]["checksum"] = Snapshot.compute_checksum(
		ownership_revision_mutation["authority_state"]["current_snapshot"]
	)
	ownership_revision_mutation["checksum"] = Checkpoint.compute_checksum(ownership_revision_mutation)
	_assert_error(
		Checkpoint.validate_progression(ownership_revision_mutation, baseline),
		"SAME_REVISION_AUTHORITATIVE_MUTATION",
		"Same-revision ownership.revision mutation remains rejected"
	)

	var ownership_players_mutation: Dictionary = ownership_tick_only.duplicate(true)
	ownership_players_mutation["checkpoint_id"] = "checkpoint/r3c2-ownership-tick/players"
	ownership_players_mutation["authority_state"]["current_snapshot"]["domain_components"]["networked_gameplay_state"]["ownership"]["players"] = [{"logical_player_id": "intruder"}]
	ownership_players_mutation["authority_state"]["current_snapshot"]["checksum"] = Snapshot.compute_checksum(
		ownership_players_mutation["authority_state"]["current_snapshot"]
	)
	ownership_players_mutation["checksum"] = Checkpoint.compute_checksum(ownership_players_mutation)
	_assert_error(
		Checkpoint.validate_progression(ownership_players_mutation, baseline),
		"SAME_REVISION_AUTHORITATIVE_MUTATION",
		"Same-revision ownership.players mutation remains rejected"
	)

	var gameplay_players_mutation: Dictionary = ownership_tick_only.duplicate(true)
	gameplay_players_mutation["checkpoint_id"] = "checkpoint/r3c2-ownership-tick/gameplay-players"
	gameplay_players_mutation["authority_state"]["current_snapshot"]["domain_components"]["networked_gameplay_state"]["players"] = {"count": 1}
	gameplay_players_mutation["authority_state"]["current_snapshot"]["checksum"] = Snapshot.compute_checksum(
		gameplay_players_mutation["authority_state"]["current_snapshot"]
	)
	gameplay_players_mutation["checksum"] = Checkpoint.compute_checksum(gameplay_players_mutation)
	_assert_error(
		Checkpoint.validate_progression(gameplay_players_mutation, baseline),
		"SAME_REVISION_AUTHORITATIVE_MUTATION",
		"Same-revision gameplay players mutation remains rejected"
	)

	_finish()


func _checkpoint(
	generation: int,
	previous_generation: int,
	revision: int,
	server_tick: int,
	ownership_revision: int,
	ownership_server_tick: int
) -> Dictionary:
	var snapshot: Dictionary = Snapshot.normalize(Snapshot.create(
		"snapshot/r3c2-ownership-tick/%d/%d" % [revision, server_tick],
		"aggregate/r3c2-ownership-tick",
		"networked_gameplay_runtime",
		revision,
		"simulation/r3c2-ownership-tick",
		1,
		server_tick,
		{
			"schema": Snapshot.SPATIAL_REF_SCHEMA,
			"universe_id": "planet-simulator",
			"instance_id": "r3c2-ownership-tick",
			"space_id": "networked-gameplay",
			"frame_id": "frame/r3c2-ownership-tick",
			"position_m": [0.0, 0.0, 0.0],
			"rotation_xyzw": [0.0, 0.0, 0.0, 1.0],
			"linear_velocity_mps": [0.0, 0.0, 0.0],
			"angular_velocity_rps": [0.0, 0.0, 0.0],
			"sample_time_s": float(server_tick),
		},
		{"region_id": "region/r3c2-ownership-tick"},
		{},
		{
			"networked_gameplay_state": {
				"schema": "planet_simulator.networked_gameplay_state.v1",
				"revision": revision,
				"server_tick": server_tick,
				"players": {"count": 0},
				"ownership": {
					"schema": "planet_simulator.player_ownership_state.v1",
					"authority_owner_id": "simulation/r3c2-ownership-tick",
					"authority_epoch": 1,
					"revision": ownership_revision,
					"server_tick": ownership_server_tick,
					"players": [],
					"checksum": CHECKSUM_A,
				},
				"checksum": CHECKSUM_A,
			},
			"durable_state_checksum": CHECKSUM_A,
		}
	))
	var authority_state: Dictionary = {
		"schema": "planet_simulator.r3c2_ownership_tick_authority.v1",
		"authority_owner_id": "simulation/r3c2-ownership-tick",
		"authority_epoch": 1,
		"server_tick": server_tick,
		"session_id": "session/r3c2-ownership-tick",
		"current_snapshot": snapshot,
	}
	return Checkpoint.create(
		"checkpoint/r3c2-ownership-tick/%d" % generation,
		generation,
		previous_generation,
		authority_state,
		{"schema": "r3c2-ownership-tick-replay.v1", "records": []},
		"",
		server_tick
	)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, JSON.stringify(result)])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code,
		"%s: %s" % [message, JSON.stringify(result)]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("R3C2 ownership tick progression: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"R3C2 ownership tick progression: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
