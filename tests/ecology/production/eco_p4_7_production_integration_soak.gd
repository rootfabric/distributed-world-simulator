extends SceneTree

const Fixture = preload("res://tests/ecology/production/support/eco_p4_fixture_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")
const RegionState = preload("res://scripts/ecology/production/ecology_region_state_v1.gd")
const EcologyClock = preload("res://scripts/ecology/production/ecology_clock_v1.gd")
const OfflineCatchup = preload("res://scripts/ecology/production/ecology_offline_catchup_v1.gd")
const ProductionPersistence = preload("res://scripts/ecology/production/ecology_region_persistence_v1.gd")
const Ownership = preload("res://scripts/ecology/production/ecology_region_ownership_v1.gd")
const ReadModel = preload("res://scripts/ecology/production/ecology_client_read_model_v1.gd")

const REGION_COUNT := 8
const CYCLE_COUNT := 12
const ORIGIN_WORLD_TIME := 100.0
const ECOLOGY_STEP_INTERVAL := 10.0
const EXPECTED_ECOLOGY_GENERATION_STEPS := 8
const EXPECTED_HANDOFFS := 4
const EXPECTED_SAVE_LOADS := 12
const EXPECTED_CLIENT_UPDATES := 12
const EXPECTED_INTEREST_PROJECTIONS := 14
const EXPECTED_RESTARTS := 3
const MAX_REMAINING_DUE_STEPS := 1
const SERVERS: Array[String] = ["server-a", "server-b", "server-c"]

var assertions := 0
var failed := false

func _init() -> void:
	_progress("start")
	seed(424242)
	var rng_expected := [randi(), randi(), randi()]
	seed(424242)
	var result := _run_soak()
	var rng_after := [randi(), randi(), randi()]
	_check(rng_expected == rng_after, "accelerated soak consumes no global RNG")
	_check(not result.is_empty(), "bounded rotating soak completes")
	_check(int(result.get("ecology_generation_steps", -1)) == EXPECTED_ECOLOGY_GENERATION_STEPS, "one real ecology generation per region")
	_check(int(result.get("handoff_count", -1)) == EXPECTED_HANDOFFS, "handoff count exact")
	_check(int(result.get("save_load_count", -1)) == EXPECTED_SAVE_LOADS, "one persistence round-trip per cycle")
	_check(int(result.get("client_update_count", -1)) == EXPECTED_CLIENT_UPDATES, "one client cache update per cycle")
	_check(int(result.get("interest_projection_count", -1)) == EXPECTED_INTEREST_PROJECTIONS, "active plus full-fanout interest projections exact")
	_check(int(result.get("restart_count", -1)) == EXPECTED_RESTARTS, "restart reconstruction count exact")
	_check(int(result.get("max_remaining_due_steps", 999999)) <= MAX_REMAINING_DUE_STEPS, "catch-up debt stays bounded")
	_check(int(result.get("final_region_count", -1)) == REGION_COUNT, "canonical region count remains bounded")
	_check(String(result.get("forward_interest_hash", "")) == String(result.get("reverse_interest_hash", "")), "full interest projection independent of authoritative input order")

	if failed:
		_progress("failed")
		quit(1)
		return
	_progress("complete")
	print("ECO.P4.7 Bounded Rotating Production Integration Soak: PASS (%d assertions)" % assertions)
	print("soak_hash=" + String(result["soak_hash"]))
	print("final_interest_hash=" + String(result["forward_interest_hash"]))
	print("handoff_count=" + str(result["handoff_count"]))
	print("ecology_generation_steps=" + str(result["ecology_generation_steps"]))
	print("save_load_count=" + str(result["save_load_count"]))
	print("client_update_count=" + str(result["client_update_count"]))
	print("interest_projection_count=" + str(result["interest_projection_count"]))
	print("restart_count=" + str(result["restart_count"]))
	print("max_remaining_due_steps=" + str(result["max_remaining_due_steps"]))
	print("region_count=" + str(result["final_region_count"]))
	print("cycles=" + str(CYCLE_COUNT))
	print("parent_p4_6=" + ReadModel.PARENT_P4_5_AGGREGATE)
	quit(0)

func _run_soak() -> Dictionary:
	_progress("initialize base P3.8 state")
	var p3_initial := Persistence.initialize(Fixture.initial_p3_7_result())
	_check(not p3_initial.is_empty(), "base P3.8 state initializes")
	var ownerships: Array = []
	ownerships.resize(REGION_COUNT)
	var client_cache := {}
	var ecology_generation_steps := 0

	for index in range(REGION_COUNT):
		_progress("initialize region %d/%d" % [index + 1, REGION_COUNT])
		var region_id := "planet-01:soak_%02d" % index
		var region := RegionState.create_region_state(region_id, ORIGIN_WORLD_TIME, p3_initial)
		_check(not region.is_empty(), "initial region creates")
		var clock := EcologyClock.create_clock(region, ECOLOGY_STEP_INTERVAL)
		_check(not clock.is_empty(), "initial clock creates")
		var catchup := OfflineCatchup.create(region, ORIGIN_WORLD_TIME + ECOLOGY_STEP_INTERVAL, clock)
		_check(not catchup.is_empty(), "initial catch-up creates")
		var generation_before := int(Dictionary(catchup["region_state"])["ecology_generation"])
		catchup = OfflineCatchup.advance_batch(catchup, 1)
		_check(not catchup.is_empty(), "initial catch-up advances one bounded step")
		var generation_after := int(Dictionary(catchup["region_state"])["ecology_generation"])
		_check(generation_after == generation_before + 1, "initial catch-up performs exactly one real ecology generation")
		ecology_generation_steps += generation_after - generation_before
		var snapshot := ProductionPersistence.create_snapshot(catchup)
		_check(not snapshot.is_empty(), "initial snapshot creates")
		var owner := Ownership.create_ownership(snapshot, SERVERS[index % SERVERS.size()], 0)
		_check(not owner.is_empty(), "initial ownership creates")
		ownerships[index] = owner
		var summary := ReadModel.build_region_summary(owner)
		_check(not summary.is_empty(), "initial read summary creates")
		client_cache[region_id] = summary

	var handoff_count := 0
	var save_load_count := 0
	var client_update_count := 0
	var interest_projection_count := 0
	var restart_count := 0
	var max_remaining_due_steps := 0

	for cycle in range(CYCLE_COUNT):
		var index := cycle % REGION_COUNT
		_progress("cycle %d/%d active_region=%02d" % [cycle + 1, CYCLE_COUNT, index])
		var owner: Dictionary = ownerships[index]
		var snapshot: Dictionary = Dictionary(owner["snapshot"])
		var catchup := ProductionPersistence.restore_catchup_state(snapshot)
		_check(not catchup.is_empty(), "cycle restores catch-up from production snapshot")

		var elapsed := 0.25 + 0.25 * float((cycle + index) % 3)
		catchup = OfflineCatchup.extend_elapsed(catchup, elapsed)
		_check(not catchup.is_empty(), "cycle extends observed world time")
		var batch_limit := 1 + ((cycle + index) % 4)
		catchup = OfflineCatchup.advance_batch(catchup, batch_limit)
		_check(not catchup.is_empty(), "cycle bounded catch-up returns state")
		max_remaining_due_steps = max(max_remaining_due_steps, int(catchup["remaining_due_steps"]))

		var next_snapshot := ProductionPersistence.create_snapshot(catchup)
		_check(not next_snapshot.is_empty(), "cycle production snapshot creates")
		var bytes := ProductionPersistence.serialize_snapshot(next_snapshot)
		_check(not bytes.is_empty(), "cycle snapshot serializes")
		var decoded := ProductionPersistence.deserialize_snapshot(bytes)
		_check(not decoded.is_empty(), "cycle snapshot deserializes")
		save_load_count += 1

		var committed := Ownership.commit_snapshot(
			owner,
			String(owner["owner_server_id"]),
			int(owner["ownership_epoch"]),
			String(owner["ownership_hash"]),
			decoded
		)
		_check(not committed.is_empty(), "owner CAS-commits reloaded snapshot")
		owner = committed

		if cycle % 3 == 0:
			var current_server_index: int = SERVERS.find(String(owner["owner_server_id"]))
			var target_server: String = SERVERS[(current_server_index + 1) % SERVERS.size()]
			var handoff := Ownership.prepare_handoff(owner, target_server)
			_check(not handoff.is_empty(), "soak handoff package prepares")
			owner = Ownership.accept_handoff(owner, handoff, target_server)
			_check(not owner.is_empty(), "soak handoff target accepts")
			handoff_count += 1

		if cycle == 3 or cycle == 7 or cycle == 11:
			var restart_bytes := ProductionPersistence.serialize_snapshot(Dictionary(owner["snapshot"]))
			var restart_snapshot := ProductionPersistence.deserialize_snapshot(restart_bytes)
			_check(not restart_snapshot.is_empty(), "restart snapshot round-trip succeeds")
			var restarted := Ownership.create_ownership(restart_snapshot, String(owner["owner_server_id"]), int(owner["ownership_epoch"]))
			_check(not restarted.is_empty(), "restart ownership reconstructs")
			_check(String(restarted["ownership_hash"]) == String(owner["ownership_hash"]), "restart ownership identity exact")
			owner = restarted
			restart_count += 1

		var summary := ReadModel.build_region_summary(owner)
		_check(not summary.is_empty(), "cycle read summary builds")
		var region_id := String(owner["region_id"])
		var accepted := ReadModel.accept_client_update(Dictionary(client_cache.get(region_id, {})), summary)
		_check(not accepted.is_empty(), "client cache accepts monotonic cycle summary")
		client_cache[region_id] = accepted
		client_update_count += 1
		ownerships[index] = owner

		var active_requested := [region_id, region_id, "planet-01:missing-active"]
		var active_interest := ReadModel.project_interest([owner], active_requested)
		_check(not active_interest.is_empty(), "active-region interest projection builds")
		_check(int(active_interest["summary_count"]) == 1, "active interest summary count exact")
		_check(int(active_interest["missing_count"]) == 1, "active interest missing count exact")
		interest_projection_count += 1

	var requested := ["planet-01:missing-a", "planet-01:missing-b"]
	for index in range(REGION_COUNT - 1, -1, -1):
		requested.append("planet-01:soak_%02d" % index)
		if index % 2 == 0:
			requested.append("planet-01:soak_%02d" % index)

	_progress("full fanout forward")
	var forward_interest := ReadModel.project_interest(ownerships, requested)
	_check(not forward_interest.is_empty(), "final full-fanout interest projection builds")
	_check(int(forward_interest["summary_count"]) == REGION_COUNT, "final interest summary count bounded")
	_check(int(forward_interest["missing_count"]) == 2, "final interest missing count exact")
	interest_projection_count += 1

	_progress("full fanout reverse")
	var reversed_ownerships := ownerships.duplicate(true)
	reversed_ownerships.reverse()
	var reverse_interest := ReadModel.project_interest(reversed_ownerships, requested)
	_check(not reverse_interest.is_empty(), "reverse-authority full-fanout interest projection builds")
	_check(String(reverse_interest["interest_hash"]) == String(forward_interest["interest_hash"]), "full interest identity independent of authoritative input order")
	interest_projection_count += 1

	_progress("canonicalize final identities")
	var final_entries := []
	for owner_value in ownerships:
		var owner: Dictionary = owner_value
		var summary: Dictionary = client_cache[String(owner["region_id"])]
		var snapshot: Dictionary = Dictionary(owner["snapshot"])
		var catchup: Dictionary = Dictionary(snapshot["catchup_state"])
		var region: Dictionary = Dictionary(catchup["region_state"])
		final_entries.append([
			String(owner["region_id"]),
			String(owner["owner_server_id"]),
			int(owner["ownership_epoch"]),
			String(owner["ownership_hash"]),
			String(owner["snapshot_hash"]),
			int(region["ecology_generation"]),
			int(catchup["remaining_due_steps"]),
			String(summary["summary_hash"]),
		])
	final_entries.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	var canonical := [
		REGION_COUNT,
		CYCLE_COUNT,
		ECOLOGY_STEP_INTERVAL,
		final_entries,
		String(forward_interest["interest_hash"]),
		handoff_count,
		ecology_generation_steps,
		save_load_count,
		client_update_count,
		interest_projection_count,
		restart_count,
		max_remaining_due_steps,
	]
	return {
		"soak_hash": JSON.stringify(canonical).sha256_text(),
		"forward_interest_hash": String(forward_interest["interest_hash"]),
		"reverse_interest_hash": String(reverse_interest["interest_hash"]),
		"handoff_count": handoff_count,
		"ecology_generation_steps": ecology_generation_steps,
		"save_load_count": save_load_count,
		"client_update_count": client_update_count,
		"interest_projection_count": interest_projection_count,
		"restart_count": restart_count,
		"max_remaining_due_steps": max_remaining_due_steps,
		"final_region_count": ownerships.size(),
	}

func _progress(message: String) -> void:
	var path := OS.get_environment("ECO_P4_7_PROGRESS_FILE")
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(message)
	file.flush()
	file.close()

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.P4.7 SOAK FAIL: " + message)
