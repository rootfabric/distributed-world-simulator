extends SceneTree

# R3 Windows independent failure reproduction: both submit() and the
# M6 proof's submit_owned() MUST freeze nested caller Dictionaries before
# posting to the worker. Expected SHA is computed before caller mutation.
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Writer = preload("res://scripts/persistence/async_checkpoint_writer.gd")
const Checkpoint = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("DWS_NET_SMOOTH_TEST_HOOKS", "1")
	var root_path := ProjectSettings.globalize_path(
		"res://artifacts/net-smooth1/r42-r3-writer-alias-%d" % Time.get_ticks_usec())
	var service = Service.new()
	var configured: Dictionary = service.setup("simulation/net-smooth-r3-alias", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/net-smooth/r3-writer-alias"
	})
	check(_ok(configured), "canonical service configured")
	if not _ok(configured):
		_finish()
		return
	check(_ok(service.join("a", "transport-session/net-r3/alias/a/1",
		"operation/net-r3/alias/join")), "canonical player joined")
	var adapter = Adapter.new()
	var outbox = Outbox.new()
	check(_ok(adapter.setup(service)), "M6 adapter configured")
	check(_ok(outbox.setup(service)), "M6 replay outbox configured")
	var writer = Writer.new()
	var setup: Dictionary = writer.setup(root_path)
	check(_ok(setup), "real repository writer started")
	if not _ok(setup):
		service.shutdown()
		_finish()
		return
	check(_ok(writer.configure_test_command_delay_ms(400)), "deterministic writer delay on worker thread")
	var repository = Repository.new()
	check(_ok(repository.configure(root_path)), "independent repository reader")

	for generation in [1, 2]:
		var authority: Dictionary = adapter.export_recovery_state()
		var replay: Dictionary = outbox.to_dict()
		check(not authority.is_empty() and not replay.is_empty(),
			"canonical detached M6 state captured")
		var checkpoint_id := "checkpoint/m6/dedicated/%d" % generation
		var operation_id := "operation/net-r3/nested-alias/%d" % generation
		var reference: Dictionary = Checkpoint.create(
			checkpoint_id, generation, generation - 1,
			authority, replay, operation_id,
			int(authority.get("server_tick", -1))
		)
		check(_ok(Checkpoint.validate(reference)), "pre-submit reference checkpoint is valid")
		var submitted: Dictionary = (
			writer.submit_owned(authority, replay, checkpoint_id,
				generation, generation - 1, operation_id)
			if generation == 1
			else writer.submit(authority, replay, checkpoint_id,
				generation, generation - 1, operation_id)
		)
		check(_ok(submitted),
			"single writer accepted %s submission" % (
				"submit_owned" if generation == 1 else "submit"
			))
		if not _ok(submitted):
			break
		# Neither a nested durable-state edit nor a full replay dictionary
		# clear after submit may influence the worker's frozen checkpoint.
		authority["session_id"] = "tampered/after-submit"
		var snapshot: Dictionary = Dictionary(authority.get("current_snapshot", {}))
		var domain: Dictionary = Dictionary(snapshot.get("domain_components", {}))
		var nested: Dictionary = Dictionary(domain.get("networked_gameplay_state", {}))
		nested["revision"] = 999999
		replay.clear()
		var completion: Dictionary = writer.wait_completed()  # standalone test ONLY
		check(_ok(completion), "worker completed atomic checkpoint")
		var saved: Dictionary = repository.load_committed()
		check(_ok(saved), "independent repository read passed")
		var checkpoint: Dictionary = Dictionary(saved.get("details", {}).get("checkpoint", {}))
		check(int(checkpoint.get("generation", -1)) == generation,
			"durable generation and previous generation remain ordered")
		check(String(checkpoint.get("checksum", "")) == String(reference.get("checksum", "!")),
			"worker SHA equals immutable pre-submit nested snapshot and replay")
		check(String(checkpoint.get("logical_session_id", "")) ==
			String(reference.get("logical_session_id", "")),
			"post-submit session tampering never reaches disk")
		check(_ok(Checkpoint.validate(checkpoint)),
			"real committed checkpoint independently validates")

	check(_ok(writer.stop()) or writer.stop().is_empty(),
		"writer thread stops without a pending generation")
	service.shutdown()
	_finish()


func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))


func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	for reason in failures:
		push_error(reason)
	print("NET_SMOOTH1_R42_R3_WRITER_ALIAS: %s assertions=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
