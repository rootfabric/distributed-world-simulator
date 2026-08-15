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
const EXPECTED_ECOLOGY_GENERATION_STEPS := REGION_COUNT
const SERVERS: Array[String] = ["server-a", "server-b", "server-c"]

var assertions := 0
var failed := false

func _init() -> void:
	seed(424242)
	var rng_expected := [randi(), randi(), randi()]
	seed(424242)
	var forward := _run_soak(false)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_expected == rng_after, "accelerated soak consumes no global RNG")
	var reverse := _run_soak(true)

	_check(not forward.is_empty() and not reverse.is_empty(), "both processing orders complete")
	_check(String(forward.get("soak_hash", "")) == String(reverse.get("soak_hash", "")), "region processing order converges to identical soak hash")
	_check(String(forward.get("final_interest_hash", "")) == String(reverse.get("final_interest_hash", "")), "region processing order converges to identical interest projection")
	_check(int(forward.get("handoff_count", -1)) == int(reverse.get("handoff_count", -2)), "handoff count order-independent")
	_check(int(forward.get("ecology_generation_steps", -1)) == int(reverse.get("ecology_generation_steps", -2)), "deep ecology generation count order-independent")
	_check(int(forward.get("ecology_generation_steps", -1)) == EXPECTED_ECOLOGY_GENERATION_STEPS, "every region executes exactly one real ecology generation")
	_check(int(forward.get("save_load_count", -1)) == REGION_COUNT * CYCLE_COUNT, "every region persists each cycle")
	_check(int(forward.get("client_update_count", -1)) == REGION_COUNT * CYCLE_COUNT, "every region updates client cache each cycle")
	_check(int(forward.get("interest_projection_count", -1)) == CYCLE_COUNT, "one bounded interest projection per cycle")
	_check(int(forward.get("max_remaining_due_steps", 999999)) <= 8, "catch-up debt stays bounded")
	_check(int(forward.get("final_region_count", -1)) == REGION_COUNT, "canonical region count remains bounded")

	if failed:
		quit(1)
		return
	print("ECO.P4.7 Accelerated Production Integration Soak: PASS (%d assertions)" % assertions)
	print("soak_hash=" + String(forward["soak_hash"]))
	print("final_interest_hash=" + String(forward["final_interest_hash"]))
	print("handoff_count=" + str(forward["handoff_count"]))
	print("ecology_generation_steps=" + str(forward["ecology_generation_steps"]))
	print("save_load_count=" + str(forward["save_load_count"]))
	print("client_update_count=" + str(forward["client_update_count"]))
	print("interest_projection_count=" + str(forward["interest_projection_count"]))
	print("max_remaining_due_steps=" + str(forward["max_remaining_due_steps"]))
	print("region_count=" + str(forward["final_region_count"]))
	print("cycles=" + str(CYCLE_COUNT))
	print("parent_p4_6=" + ReadModel.PARENT_P4_5_AGGREGATE)
	quit(0)

func _run_soak(reverse_order: bool) -> Dictionary:
	var p3_initial := Persistence.initialize(Fixture.initial_p3_7_result())
	_check(bool(Persistence.validate_state(p3_initial).get("success", false)), "base P3.8 state validates")
	var ownerships := []
	var client_cache := {}
	for index in range(REGION_COUNT):
		var region_id := "planet-01:soak_%02d" % index
		var region := RegionState.create_region_state(region_id, ORIGIN_WORLD_TIME, p3_initial)
		_check(bool(RegionState.validate_region_state(region).get("success", false)), "initial region validates")
		var clock := EcologyClock.create_clock(region, ECOLOGY_STEP_INTERVAL)
		var initial_target := ORIGIN_WORLD_TIME + 0.25 + float(index) * 0.05
		var catchup := OfflineCatchup.create(region, initial_target, clock)
		catchup = OfflineCatchup.advance_batch(catchup, 10)
		_check(bool(OfflineCatchup.validate_state(catchup).get("success", false)), "initial catch-up validates")
		var snapshot := ProductionPersistence.create_snapshot(catchup)
		_check(bool(ProductionPersistence.validate_snapshot(snapshot).get("success", false)), "initial snapshot validates")
		var owner := Ownership.create_ownership(snapshot, SERVERS[index % SERVERS.size()], 0)
		_check(bool(Ownership.validate_ownership(owner).get("success", false)), "initial ownership validates")
		ownerships.append(owner)
		var summary := ReadModel.build_region_summary(owner)
		_check(bool(ReadModel.validate_region_summary(summary).get("success", false)), "initial read summary validates")
		client_cache[region_id] = summary

	var handoff_count := 0
	var ecology_generation_steps := 0
	var save_load_count := 0
	var client_update_count := 0
	var interest_projection_count := 0
	var max_remaining_due_steps := 0
	var final_interest := {}

	for cycle in range(CYCLE_COUNT):
		var order := []
		for index in range(REGION_COUNT):
			order.append(index)
		if reverse_order:
			order.reverse()
		for index_value in order:
			var index := int(index_value)
			var owner: Dictionary = ownerships[index]
			var snapshot: Dictionary = Dictionary(owner["snapshot"])
			var catchup := ProductionPersistence.restore_catchup_state(snapshot)
			_check(bool(OfflineCatchup.validate_state(catchup).get("success", false)), "cycle restore catch-up validates")
			var elapsed := 1.0 + 0.5 * float((cycle + index) % 3)
			catchup = OfflineCatchup.extend_elapsed(catchup, elapsed)
			var before_generation := int(Dictionary(catchup["region_state"])["ecology_generation"])
			var batch_limit := 1 + ((cycle * 2 + index) % 4)
			catchup = OfflineCatchup.advance_batch(catchup, batch_limit)
			_check(bool(OfflineCatchup.validate_state(catchup).get("success", false)), "bounded batch catch-up validates")
			var after_generation := int(Dictionary(catchup["region_state"])["ecology_generation"])
			var generation_delta := after_generation - before_generation
			_check(generation_delta >= 0 and generation_delta <= 1, "bounded soak advances at most one deep ecology generation per region-cycle")
			ecology_generation_steps += generation_delta
			max_remaining_due_steps = max(max_remaining_due_steps, int(catchup["remaining_due_steps"]))

			var next_snapshot := ProductionPersistence.create_snapshot(catchup)
			var bytes := ProductionPersistence.serialize_snapshot(next_snapshot)
			_check(not bytes.is_empty(), "cycle snapshot serializes")
			var decoded := ProductionPersistence.deserialize_snapshot(bytes)
			_check(bool(ProductionPersistence.validate_snapshot(decoded).get("success", false)), "cycle snapshot reload validates")
			save_load_count += 1

			var committed := Ownership.commit_snapshot(owner, String(owner["owner_server_id"]), int(owner["ownership_epoch"]), String(owner["ownership_hash"]), decoded)
			_check(bool(Ownership.validate_ownership(committed).get("success", false)), "owner commits reloaded snapshot")
			owner = committed

			if ((cycle + index) % 3) == 0:
				var current_server_index: int = SERVERS.find(String(owner["owner_server_id"]))
				var target_server: String = SERVERS[(current_server_index + 1) % SERVERS.size()]
				var handoff := Ownership.prepare_handoff(owner, target_server)
				_check(bool(Ownership.validate_handoff(handoff, owner).get("success", false)), "soak handoff validates")
				owner = Ownership.accept_handoff(owner, handoff, target_server)
				_check(bool(Ownership.validate_ownership(owner).get("success", false)), "soak handoff target validates")
				handoff_count += 1

			if cycle == 3 or cycle == 7 or cycle == 11:
				var restart_snapshot := ProductionPersistence.deserialize_snapshot(ProductionPersistence.serialize_snapshot(Dictionary(owner["snapshot"])))
				var restarted := Ownership.create_ownership(restart_snapshot, String(owner["owner_server_id"]), int(owner["ownership_epoch"]))
				_check(bool(Ownership.validate_ownership(restarted).get("success", false)), "restart ownership reconstructs")
				_check(String(restarted["ownership_hash"]) == String(owner["ownership_hash"]), "restart ownership identity exact")
				owner = restarted

			var summary := ReadModel.build_region_summary(owner)
			_check(bool(ReadModel.validate_region_summary(summary).get("success", false)), "cycle read summary validates")
			var region_id := String(owner["region_id"])
			var accepted := ReadModel.accept_client_update(Dictionary(client_cache.get(region_id, {})), summary)
			_check(not accepted.is_empty(), "client cache accepts monotonic cycle summary")
			client_cache[region_id] = accepted
			client_update_count += 1
			ownerships[index] = owner

		var requested := ["planet-01:missing-a", "planet-01:missing-b"]
		for index in range(REGION_COUNT - 1, -1, -1):
			requested.append("planet-01:soak_%02d" % index)
			if index % 2 == 0:
				requested.append("planet-01:soak_%02d" % index)
		final_interest = ReadModel.project_interest(ownerships, requested)
		_check(bool(ReadModel.validate_interest_projection(final_interest).get("success", false)), "cycle interest projection validates")
		_check(int(final_interest["summary_count"]) == REGION_COUNT, "interest summary count bounded")
		_check(int(final_interest["missing_count"]) == 2, "interest missing count exact")
		interest_projection_count += 1

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
		String(final_interest.get("interest_hash", "")),
		handoff_count,
		ecology_generation_steps,
		save_load_count,
		client_update_count,
		interest_projection_count,
		max_remaining_due_steps,
	]
	return {
		"soak_hash": JSON.stringify(canonical).sha256_text(),
		"final_interest_hash": String(final_interest.get("interest_hash", "")),
		"handoff_count": handoff_count,
		"ecology_generation_steps": ecology_generation_steps,
		"save_load_count": save_load_count,
		"client_update_count": client_update_count,
		"interest_projection_count": interest_projection_count,
		"max_remaining_due_steps": max_remaining_due_steps,
		"final_region_count": ownerships.size(),
	}

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.P4.7 SOAK FAIL: " + message)
