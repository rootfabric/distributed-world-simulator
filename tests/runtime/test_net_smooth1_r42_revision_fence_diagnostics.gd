extends SceneTree

# R4.2-P0: exercise the REAL M6 checkpoint + repository progression contract.
# No shadow validator, checksum bypass, or guessed production cause.
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")

const OWNER := "simulation/net-smooth1-r42"
const SESSION := "transport-session/net-smooth1-r42/a/1"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = Service.new()
	var setup: Dictionary = service.setup(OWNER, 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/net-smooth1-r42",
	})
	check(_ok(setup), "real gameplay service configured")
	if not _ok(setup):
		_finish()
		return
	var joined: Dictionary = service.join(
		"a", SESSION, "operation/net-smooth1-r42/a/join/1"
	)
	check(_ok(joined), "real join establishes durable baseline")
	var adapter = Adapter.new()
	check(_ok(adapter.setup(service, "session/net-smooth1-r42")), "M6 authority adapter configured")
	var baseline_state: Dictionary = adapter.export_recovery_state()
	check(not baseline_state.is_empty(), "M6 authority export present")
	if baseline_state.is_empty():
		service.shutdown()
		_finish()
		return
	var baseline_revision: int = int(baseline_state.get("current_snapshot", {}).get("state_revision", -1))
	var baseline: Dictionary = _checkpoint("checkpoint/net-smooth1-r42/1", 1, 0, baseline_state)
	check(_ok(Checkpoint.validate(baseline)), "baseline cryptographic checkpoint validates")
	var same_state: Dictionary = _checkpoint(
		"checkpoint/net-smooth1-r42/2", 2, 1, adapter.export_recovery_state()
	)
	check(_ok(Checkpoint.validate_progression(same_state, baseline)), "same revision and same semantic state is allowed")
	var moved: Dictionary = service.move_player(
		"a", SESSION, 1, 1, 1.25, -0.5, "operation/net-smooth1-r42/a/move/1"
	)
	check(_ok(moved), "real authority move mutates player state")
	var moved_state: Dictionary = adapter.export_recovery_state()
	check(int(moved_state.get("current_snapshot", {}).get("state_revision", -1)) > baseline_revision,
		"real gameplay mutation increments authoritative revision")
	var good_next: Dictionary = _checkpoint("checkpoint/net-smooth1-r42/2", 2, 1, moved_state)
	check(_ok(Checkpoint.validate_progression(good_next, baseline)), "advanced revision commits")

	# Deliberately simulate the reported BUG CLASS (mutation without revision).
	# This does not claim to explain the durable-r2 incident; it locks the fence.
	service.set("_revision", baseline_revision)
	var conflict_state: Dictionary = adapter.export_recovery_state()
	var conflict: Dictionary = _checkpoint("checkpoint/net-smooth1-r42/2", 2, 1, conflict_state)
	check(_ok(Checkpoint.validate(conflict)), "same-revision candidate independently checksum-valid")
	var rejected: Dictionary = Checkpoint.validate_progression(conflict, baseline)
	check(not _ok(rejected) and String(rejected.get("error_code", "")) == "SAME_REVISION_AUTHORITATIVE_MUTATION",
		"same-revision semantic mutation remains fail-closed")
	var reason: String = String(rejected.get("message", ""))
	check(reason.contains("first_changed_path=$.domain_components."),
		"failed progression names structured schema path")
	check(not reason.contains(SESSION) and not reason.contains("1.25") and reason.length() < 260,
		"diagnostics contain no snapshot values or session identifiers")
	check(String(Checkpoint.validate_progression(conflict, baseline).get("message", "")) == reason,
		"diagnostic path stable across repeated validation")

	var root: String = ProjectSettings.globalize_path(
		"user://net-smooth1-r42-revision-fence-%d" % Time.get_ticks_usec()
	)
	var repository = Repository.new()
	check(_ok(repository.configure(root)), "real M6 repository configured")
	check(_ok(repository.save_atomic(baseline)), "baseline atomic generation committed")
	var disk_rejected: Dictionary = repository.save_atomic(conflict)
	check(not _ok(disk_rejected) and String(disk_rejected.get("error_code", "")) == "SAME_REVISION_AUTHORITATIVE_MUTATION",
		"real repository rejects checksum-valid invalid revision progression")
	check(String(disk_rejected.get("details", {}).get("message", "")).contains("first_changed_path="),
		"real repository error retains diagnostic path")
	var durable: Dictionary = repository.load_committed()
	check(_ok(durable) and int(durable.get("details", {}).get("checkpoint", {}).get("generation", -1)) == 1,
		"failed generation does not replace prior durable checkpoint")
	check(_ok(repository.save_atomic(good_next)), "valid newer revision can commit after failure")
	var advanced: Dictionary = repository.load_committed()
	check(_ok(advanced) and int(advanced.get("details", {}).get("checkpoint", {}).get("generation", -1)) == 2,
		"successful retry preserves monotonic checkpoint generation")
	service.shutdown()
	_cleanup(root)
	_finish()


func _checkpoint(checkpoint_id: String, generation: int, previous: int, state: Dictionary) -> Dictionary:
	return Checkpoint.create(
		checkpoint_id, generation, previous, state, {}, "", int(state.get("server_tick", 0))
	)


func _cleanup(root: String) -> void:
	if not DirAccess.dir_exists_absolute(root):
		return
	var directory := DirAccess.open(root)
	if directory == null:
		return
	for name in directory.get_files():
		DirAccess.remove_absolute(root.path_join(name))
	DirAccess.remove_absolute(root)


func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("R42 FAIL: " + label)


func _finish() -> void:
	for failure in failures:
		print("R42 failure: ", failure)
	print("NET_SMOOTH1_R42_REVISION_FENCE: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()
	])
	quit(0 if failures.is_empty() else 1)
