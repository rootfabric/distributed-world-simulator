extends SceneTree

const SCENE := "res://scenes/labs/fabric/complex4_playable_physical_lab.tscn"
const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://tests/research/fabric1/complex4_real_world_machine_fixture_v1.gd")

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	var packed := load(SCENE)
	_assert(packed is PackedScene, "VIS1 scene did not load")
	var scene = (packed as PackedScene).instantiate()
	_assert(scene != null, "VIS1 scene did not instantiate")
	_assert(String(scene.name) == "COMPLEX4VIS1PlayablePhysicalLab", "VIS1 scene name drift")
	scene._ready()
	_assert(bool(scene.get_meta("complex4_vis1_ready", false)), "VIS1 scene not ready")
	_assert(String(scene.get_meta("complex4_vis1_schema", "")) == "planet_simulator.fabric_complex4_vis1_playable_lab.v1", "VIS1 schema drift")

	var initial: Dictionary = scene.visual_state()
	_assert(initial["revision"] == 0, "initial revision wrong")
	_assert(initial["mode"] == "BAKED", "initial mode wrong")
	_assert(initial["machine_state"] == "ON", "initial machine not ON")
	_assert(initial["active_power_link_ids"] == [Fixture.POWER_A, Fixture.POWER_B], "initial redundancy missing")
	_assert(absf(float(initial["load_power_w"]) - 36.0) <= 1.0e-9, "initial load power wrong")
	_assert(initial["support_a_state"] == "INTACT" and initial["support_b_state"] == "INTACT", "initial support state wrong")
	_assert(initial["canonical_writes"] == 0, "visual lab gained canonical authority")

	_assert(scene.propose_support_failure(Fixture.SUPPORT_A, "event/complex4-vis1/test-primary"), "primary proposal failed")
	var proposal_a: Dictionary = scene.visual_state()
	_assert(proposal_a["revision"] == 0, "primary proposal mutated canonical revision")
	_assert(proposal_a["mode"] == "FULL", "primary proposal did not refine FULL")
	_assert(proposal_a["machine_state"] == "ON", "primary proposal changed function early")
	_assert(proposal_a["pending_support_id"] == Fixture.SUPPORT_A, "primary proposal pending support wrong")
	_assert(scene.apply_pending_canonical_failure(), "primary canonical apply failed")
	var after_a: Dictionary = scene.visual_state()
	_assert(after_a["revision"] == 1, "primary revision wrong")
	_assert(after_a["mode"] == "BAKED", "primary did not rebake")
	_assert(after_a["machine_state"] == "ON", "backup did not keep machine ON")
	_assert(after_a["active_power_link_ids"] == [Fixture.POWER_B], "primary path still active")
	_assert(after_a["support_a_state"] == "BROKEN" and after_a["support_b_state"] == "INTACT", "primary support visual state wrong")
	_assert(absf(float(after_a["load_power_w"]) - 36.0) <= 1.0e-9, "primary failure changed load power")

	_assert(scene.propose_support_failure(Fixture.SUPPORT_B, "event/complex4-vis1/test-backup"), "backup proposal failed")
	var proposal_b: Dictionary = scene.visual_state()
	_assert(proposal_b["revision"] == 1, "backup proposal mutated canonical revision")
	_assert(proposal_b["mode"] == "FULL", "backup proposal did not refine FULL")
	_assert(scene.apply_pending_canonical_failure(), "backup canonical apply failed")
	var after_b: Dictionary = scene.visual_state()
	_assert(after_b["revision"] == 2, "backup revision wrong")
	_assert(after_b["mode"] == "BAKED", "backup did not rebake")
	_assert(after_b["machine_state"] == "OFF", "machine did not turn OFF")
	_assert(after_b["active_power_link_ids"].is_empty(), "power path survived both failures")
	_assert(after_b["support_a_state"] == "BROKEN" and after_b["support_b_state"] == "BROKEN", "support visual state after both failures wrong")
	_assert(absf(float(after_b["load_power_w"])) <= 1.0e-9, "OFF machine still powered")
	_assert(after_b["functional_event_count"] == 2, "functional event count wrong")
	_assert(after_b["canonical_writes"] == 0, "visual lab wrote canonical state")
	_assert(not bool(scene.get_node("MachineLoadLight").visible), "lamp light remained visible while OFF")
	_assert(Array(scene.get_meta("complex4_vis1_active_paths", [])).is_empty(), "scene metadata active paths wrong")

	_assert(scene.restart_from_authority(), "VIS1 restart failed")
	var restarted: Dictionary = scene.visual_state()
	_assert(restarted["revision"] == 2 and restarted["machine_state"] == "OFF", "restart did not preserve authoritative OFF state")
	_assert(restarted["canonical_writes"] == 0, "restart gained canonical authority")

	_assert(scene.reset_lab(), "VIS1 reset failed")
	var reset: Dictionary = scene.visual_state()
	_assert(reset["revision"] == 0 and reset["machine_state"] == "ON", "reset did not return baseline")
	_assert(reset["active_power_link_ids"] == [Fixture.POWER_A, Fixture.POWER_B], "reset did not restore redundancy")
	_assert(bool(scene.get_node("MachineLoadLight").visible), "lamp light did not restore after reset")

	var packed_again := load(SCENE)
	_assert(packed_again is PackedScene, "VIS1 scene second load failed")
	var visual_hash := Utils.canonical_hash({
		"initial": initial,
		"proposal_a": proposal_a,
		"after_a": after_a,
		"proposal_b": proposal_b,
		"after_b": after_b,
		"restarted": restarted,
		"reset": reset,
	})
	print("COMPLEX4_VIS1_HASH=%s" % visual_hash)
	scene.queue_free()
	_finish()

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("FABRIC COMPLEX4-VIS1 Playable Physical Lab: PASS (%d assertions) ON->ON->OFF + restart" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FABRIC COMPLEX4-VIS1 Playable Physical Lab: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
