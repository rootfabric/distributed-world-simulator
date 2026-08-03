extends SceneTree

const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Snapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")

const BASE_TICK := 100
const NEXT_TICK := 101
const BASE_REVISION := 7
const CHECKSUM_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const CHECKSUM_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var baseline: Dictionary = _checkpoint(1, 0, BASE_REVISION, BASE_TICK)
	_assert_ok(Checkpoint.validate(baseline), "Baseline checkpoint validates")

	var tick_only: Dictionary = baseline.duplicate(true)
	tick_only["checkpoint_id"] = "checkpoint/tick-progression/2"
	tick_only["generation"] = 2
	tick_only["previous_generation"] = 1
	tick_only["server_tick"] = NEXT_TICK
	tick_only["committed_at_tick"] = NEXT_TICK
	tick_only["authority_state"]["server_tick"] = NEXT_TICK
	var tick_snapshot: Dictionary = tick_only["authority_state"]["current_snapshot"]
	tick_snapshot["snapshot_id"] = "snapshot/tick-progression/7/101"
	tick_snapshot["server_tick"] = NEXT_TICK
	tick_snapshot["spatial_ref"]["sample_time_s"] = float(NEXT_TICK)
	tick_snapshot["domain_components"]["networked_gameplay_state"]["server_tick"] = NEXT_TICK
	tick_snapshot["domain_components"]["networked_gameplay_state"]["checksum"] = CHECKSUM_B
	tick_snapshot["domain_components"]["durable_state_checksum"] = CHECKSUM_B
	tick_snapshot["checksum"] = Snapshot.compute_checksum(tick_snapshot)
	tick_only["checksum"] = Checkpoint.compute_checksum(tick_only)
	_assert_ok(Checkpoint.validate(tick_only), "Tick-only checkpoint validates")
	_assert_ok(
		Checkpoint.validate_progression(tick_only, baseline),
		"Same-revision tick-only progression is accepted"
	)
	_assert(int(tick_only["server_tick"]) > int(baseline["server_tick"]), "Tick-only candidate advances server tick")

	var semantic_mutation: Dictionary = tick_only.duplicate(true)
	semantic_mutation["checkpoint_id"] = "checkpoint/tick-progression/semantic"
	semantic_mutation["authority_state"]["current_snapshot"]["domain_components"]["networked_gameplay_state"]["players"] = {"count": 1}
	semantic_mutation["authority_state"]["current_snapshot"]["checksum"] = Snapshot.compute_checksum(
		semantic_mutation["authority_state"]["current_snapshot"]
	)
	semantic_mutation["checksum"] = Checkpoint.compute_checksum(semantic_mutation)
	_assert_ok(Checkpoint.validate(semantic_mutation), "Same-revision semantic mutation fixture validates")
	_assert_error(
		Checkpoint.validate_progression(semantic_mutation, baseline),
		"SAME_REVISION_AUTHORITATIVE_MUTATION",
		"Same-revision domain mutation remains rejected"
	)

	var physics_mutation: Dictionary = tick_only.duplicate(true)
	physics_mutation["checkpoint_id"] = "checkpoint/tick-progression/physics"
	physics_mutation["authority_state"]["current_snapshot"]["physics_state"] = {"sleeping": true}
	physics_mutation["authority_state"]["current_snapshot"]["checksum"] = Snapshot.compute_checksum(
		physics_mutation["authority_state"]["current_snapshot"]
	)
	physics_mutation["checksum"] = Checkpoint.compute_checksum(physics_mutation)
	_assert_ok(Checkpoint.validate(physics_mutation), "Same-revision physics mutation fixture validates")
	_assert_error(
		Checkpoint.validate_progression(physics_mutation, baseline),
		"SAME_REVISION_AUTHORITATIVE_MUTATION",
		"Same-revision physics mutation remains rejected"
	)

	var tick_rollback: Dictionary = baseline.duplicate(true)
	tick_rollback["checkpoint_id"] = "checkpoint/tick-progression/rollback"
	tick_rollback["generation"] = 2
	tick_rollback["previous_generation"] = 1
	tick_rollback["server_tick"] = BASE_TICK - 1
	tick_rollback["committed_at_tick"] = BASE_TICK - 1
	tick_rollback["authority_state"]["server_tick"] = BASE_TICK - 1
	tick_rollback["authority_state"]["current_snapshot"]["server_tick"] = BASE_TICK - 1
	tick_rollback["authority_state"]["current_snapshot"]["spatial_ref"]["sample_time_s"] = float(BASE_TICK - 1)
	tick_rollback["authority_state"]["current_snapshot"]["checksum"] = Snapshot.compute_checksum(
		tick_rollback["authority_state"]["current_snapshot"]
	)
	tick_rollback["checksum"] = Checkpoint.compute_checksum(tick_rollback)
	_assert_ok(Checkpoint.validate(tick_rollback), "Tick rollback fixture validates")
	_assert_error(
		Checkpoint.validate_progression(tick_rollback, baseline),
		"AUTHORITATIVE_TICK_ROLLBACK",
		"Server tick rollback remains rejected"
	)

	var revision_advance: Dictionary = semantic_mutation.duplicate(true)
	revision_advance["checkpoint_id"] = "checkpoint/tick-progression/revision-8"
	revision_advance["state_revision"] = BASE_REVISION + 1
	revision_advance["authority_state"]["current_snapshot"]["state_revision"] = BASE_REVISION + 1
	revision_advance["authority_state"]["current_snapshot"]["domain_components"]["networked_gameplay_state"]["revision"] = BASE_REVISION + 1
	revision_advance["authority_state"]["current_snapshot"]["checksum"] = Snapshot.compute_checksum(
		revision_advance["authority_state"]["current_snapshot"]
	)
	revision_advance["checksum"] = Checkpoint.compute_checksum(revision_advance)
	_assert_ok(Checkpoint.validate(revision_advance), "Revision-advance mutation fixture validates")
	_assert_ok(
		Checkpoint.validate_progression(revision_advance, baseline),
		"Semantic mutation is accepted after revision advances"
	)

	_finish()


func _checkpoint(generation: int, previous_generation: int, revision: int, server_tick: int) -> Dictionary:
	var snapshot: Dictionary = Snapshot.normalize(Snapshot.create(
		"snapshot/tick-progression/%d/%d" % [revision, server_tick],
		"aggregate/tick-progression",
		"networked_gameplay_runtime",
		revision,
		"simulation/tick-progression",
		1,
		server_tick,
		{
			"schema": Snapshot.SPATIAL_REF_SCHEMA,
			"universe_id": "planet-simulator",
			"instance_id": "tick-progression",
			"space_id": "networked-gameplay",
			"frame_id": "frame/tick-progression",
			"position_m": [0.0, 0.0, 0.0],
			"rotation_xyzw": [0.0, 0.0, 0.0, 1.0],
			"linear_velocity_mps": [0.0, 0.0, 0.0],
			"angular_velocity_rps": [0.0, 0.0, 0.0],
			"sample_time_s": float(server_tick),
		},
		{"region_id": "region/tick-progression"},
		{},
		{
			"networked_gameplay_state": {
				"revision": revision,
				"server_tick": server_tick,
				"players": {"count": 0},
				"checksum": CHECKSUM_A,
			},
			"durable_state_checksum": CHECKSUM_A,
		}
	))
	var authority_state: Dictionary = {
		"schema": "planet_simulator.tick_progression_authority.v1",
		"authority_owner_id": "simulation/tick-progression",
		"authority_epoch": 1,
		"server_tick": server_tick,
		"session_id": "session/tick-progression",
		"current_snapshot": snapshot,
	}
	return Checkpoint.create(
		"checkpoint/tick-progression/%d" % generation,
		generation,
		previous_generation,
		authority_state,
		{"schema": "tick-progression-replay.v1", "records": []},
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
		print("Authoritative tick progression: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"Authoritative tick progression: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
