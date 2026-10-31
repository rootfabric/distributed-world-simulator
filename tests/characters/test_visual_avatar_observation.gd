extends SceneTree

const AvatarEngine = preload("res://scripts/characters/providers/quaternius_avatar_engine.gd")
var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var avatar = AvatarEngine.new()
	get_root().add_child(avatar)
	check(bool(avatar.setup().get("success", false)), "provider setup")
	check(avatar.asset_mode in ["QUATERNIUS_RETARGET", "QUATERNIUS_EMBEDDED"], "real rig required")
	for speed in [0.0, 2.7, 12.0]:
		avatar.apply_motion(Vector3(speed, 0, 0))
		await create_timer(.15).timeout
		var before: Dictionary = avatar.create_visual_observation()
		var repeated: Dictionary = avatar.create_visual_observation()
		check(before == repeated, "observation does not mutate pose/clock")
		await create_timer(.13).timeout
		var after: Dictionary = avatar.create_visual_observation()
		check(after.get("semantic") == ("idle" if speed == 0 else ("walk" if speed < 5 else "run")), "semantic matches motion")
		check(bool(after.get("animation_playing", false)), "animation playing")
		check(int(after.get("target_bone_count", 0)) > 0, "target skeleton sampled")
		check(before.get("target_pose_sha256") != after.get("target_pose_sha256"), "target pose changes")
		check(before.get("animation_position_seconds") != after.get("animation_position_seconds"), "clock advances")
	avatar.free()
	for failure in failures:
		push_error(failure)
	print("VISUAL_AVATAR_OBSERVATION: %s assertions=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
