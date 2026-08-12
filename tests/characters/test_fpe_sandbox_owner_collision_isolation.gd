extends SceneTree

const EmbodimentType = preload("res://scripts/characters/presentation/owner_collision_isolated_two_hand_first_person_embodiment.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var player := CharacterBody3D.new()
	player.name = "Player"
	root.add_child(player)

	var embodiment = EmbodimentType.new()
	player.add_child(embodiment)
	embodiment.player = player
	embodiment.right_held_root = Node3D.new()
	embodiment.right_held_root.name = "RightGrip"
	player.add_child(embodiment.right_held_root)

	var body := RigidBody3D.new()
	body.name = "SandboxBody"
	body.collision_layer = 4
	body.collision_mask = 7
	body.gravity_scale = 0.75
	root.add_child(body)

	var attach: Dictionary = embodiment._attach_local_sandbox_target("right", body)
	_assert(bool(attach.get("success", false)), "sandbox collision-isolated attach failed")
	_assert(bool(attach.get("details", {}).get("owner_collision_isolated", false)), "attach did not disclose owner collision isolation")
	_assert(body.freeze, "held sandbox body was not frozen")
	_assert(body.get_parent() == embodiment.right_held_root, "held sandbox body did not move to right grip")
	_assert(_has_exception(body, player), "held sandbox body still collides with owner player")
	_assert(_has_exception(player, body), "owner player still collides with held sandbox body")
	_assert(body.collision_layer == 4, "owner isolation changed sandbox world collision layer")
	_assert(body.collision_mask == 7, "owner isolation changed sandbox world collision mask")

	var active_report: Dictionary = embodiment.get_owner_collision_isolation_report()
	_assert(int(active_report.get("active", 0)) == 1, "owner isolation report did not show one active held body")
	_assert(bool(active_report.get("owner_only_exception", false)), "owner isolation report lost owner-only policy")
	_assert(bool(active_report.get("world_collisions_preserved", false)), "owner isolation report does not preserve world collisions")

	var release: Dictionary = embodiment._release_local_sandbox_target("right")
	_assert(bool(release.get("success", false)), "sandbox collision-isolated release failed")
	_assert(bool(release.get("details", {}).get("owner_collision_restore_scheduled", false)), "release did not schedule owner collision restore")
	_assert(body.get_parent() == root, "released sandbox body did not return to original parent")
	_assert(not body.freeze, "released sandbox body did not restore freeze state")
	_assert(is_equal_approx(body.gravity_scale, 0.75), "released sandbox body did not restore gravity scale")
	_assert(_has_exception(body, player), "owner collision exception disappeared before release grace elapsed")
	_assert(_has_exception(player, body), "reciprocal owner collision exception disappeared before release grace elapsed")

	await create_timer(0.25).timeout
	_assert(not _has_exception(body, player), "sandbox body owner collision exception survived release grace")
	_assert(not _has_exception(player, body), "player reciprocal collision exception survived release grace")
	var released_report: Dictionary = embodiment.get_owner_collision_isolation_report()
	_assert(int(released_report.get("active", -1)) == 0, "owner isolation report retained released body")
	_assert(int(released_report.get("restores", 0)) >= 1, "owner isolation restore counter did not advance")

	# Existing collision policy must survive a local hold/release cycle. The FPE
	# layer may only remove exceptions that it introduced itself.
	var persistent := RigidBody3D.new()
	persistent.name = "PreExcludedSandboxBody"
	root.add_child(persistent)
	persistent.add_collision_exception_with(player)
	player.add_collision_exception_with(persistent)
	var persistent_attach: Dictionary = embodiment._attach_local_sandbox_target("right", persistent)
	_assert(bool(persistent_attach.get("success", false)), "pre-excluded sandbox attach failed")
	var persistent_release: Dictionary = embodiment._release_local_sandbox_target("right")
	_assert(bool(persistent_release.get("success", false)), "pre-excluded sandbox release failed")
	await create_timer(0.25).timeout
	_assert(_has_exception(persistent, player), "FPE removed a pre-existing body collision exception")
	_assert(_has_exception(player, persistent), "FPE removed a pre-existing player collision exception")

	var final_report: Dictionary = embodiment.get_owner_collision_isolation_report()
	_assert(bool(final_report.get("presentation_sandbox_only", false)), "owner collision isolation is not scoped to presentation sandbox")
	_assert(not bool(final_report.get("owns_item_state", true)), "owner collision isolation claims item ownership")
	_assert(not bool(final_report.get("owns_network_state", true)), "owner collision isolation claims network ownership")
	_assert(not bool(final_report.get("owns_gameplay_transform", true)), "owner collision isolation claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _has_exception(source: PhysicsBody3D, other: PhysicsBody3D) -> bool:
	for exception in source.get_collision_exceptions():
		if exception == other:
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE sandbox owner collision isolation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE sandbox owner collision isolation: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
