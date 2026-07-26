extends SceneTree

const SimulationClockScript = preload(
	"res://scripts/simulation/time/simulation_clock.gd"
)

var failures: Array[String] = []


func _init() -> void:
	var clock = SimulationClockScript.new()
	clock.setup({
		"epoch_seconds": 1000.0,
		"initial_time_s": 1000.0,
		"time_scale": 2.0,
		"paused": false,
	})
	_assert(clock.advance(0.5), "Running clock did not advance.")
	_assert(
		absf(clock.get_time_seconds() - 1001.0) < 0.000001,
		"Clock scale was not applied."
	)
	_assert(clock.tick_index == 1, "Clock tick index was not incremented.")

	clock.set_paused(true)
	var paused_time: float = clock.get_time_seconds()
	_assert(not clock.advance(10.0), "Paused clock reported an advance.")
	_assert(
		is_equal_approx(clock.get_time_seconds(), paused_time),
		"Paused clock changed simulation time."
	)
	clock.step(60.0)
	_assert(
		is_equal_approx(clock.get_time_seconds(), paused_time + 60.0),
		"Manual step did not work while paused."
	)
	_assert(clock.tick_index == 2, "Manual step did not increment tick index.")

	var revision_before_scale: int = clock.time_revision
	clock.set_time_scale(3600.0)
	_assert(
		clock.time_revision == revision_before_scale + 1,
		"Time configuration revision did not change."
	)
	var snapshot: Dictionary = clock.create_snapshot()
	_assert(
		String(snapshot.get("schema", ""))
		== "planet_simulator.simulation_clock.v1",
		"Unexpected clock snapshot schema."
	)
	_assert(
		is_equal_approx(float(snapshot.get("epoch_seconds", 0.0)), 1000.0),
		"Clock epoch was not preserved."
	)

	var authoritative_snapshot: Dictionary = snapshot.duplicate(true)
	authoritative_snapshot["authority_id"] = "ephemeris-sol-01"
	authoritative_snapshot["authority_epoch"] = 2
	authoritative_snapshot["simulation_time_s"] = 5000.0
	authoritative_snapshot["tick_index"] = 50
	authoritative_snapshot["time_revision"] = 10
	_assert(
		clock.apply_authoritative_snapshot(authoritative_snapshot),
		"Clock rejected a newer authoritative snapshot."
	)
	_assert(
		clock.authority_id == "ephemeris-sol-01"
		and clock.authority_epoch == 2
		and is_equal_approx(clock.get_time_seconds(), 5000.0),
		"Authoritative clock state was not applied."
	)

	var stale_epoch_snapshot: Dictionary = authoritative_snapshot.duplicate(true)
	stale_epoch_snapshot["authority_id"] = "obsolete-ephemeris"
	stale_epoch_snapshot["authority_epoch"] = 1
	stale_epoch_snapshot["simulation_time_s"] = 9000.0
	_assert(
		not clock.apply_authoritative_snapshot(stale_epoch_snapshot),
		"Clock accepted a snapshot from an obsolete authority epoch."
	)

	var stale_tick_snapshot: Dictionary = authoritative_snapshot.duplicate(true)
	stale_tick_snapshot["tick_index"] = 49
	_assert(
		not clock.apply_authoritative_snapshot(stale_tick_snapshot),
		"Clock accepted an older tick from the current authority."
	)

	if failures.is_empty():
		print("Simulation clock tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Simulation clock tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
