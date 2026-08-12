extends SceneTree

const PresenterType = preload("res://scripts/characters/presentation/third_person_held_item_presenter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var avatar := Node3D.new()
	avatar.name = "AvatarPresentation"
	root.add_child(avatar)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	avatar.add_child(skeleton)
	skeleton.add_bone("mixamorig:RightHand")

	var presenter = PresenterType.new()
	root.add_child(presenter)
	var setup_result: Dictionary = presenter.setup(avatar, skeleton, 20)
	_assert(bool(setup_result.get("success", false)), "R2 third-person presenter setup failed")
	var setup_report: Dictionary = presenter.create_report()
	_assert(String(setup_report.get("attachment_mode", "")) == "BONE_RIGHT_HAND", "R2 presenter did not bind the right-hand bone")
	_assert(String(setup_report.get("matched_bone_name", "")) == "mixamorig:RightHand", "R2 presenter matched the wrong hand bone")
	_assert(bool(setup_report.get("source_skeleton_present", false)), "R2 presenter lost its source skeleton")

	var presented: Dictionary = presenter.present_item("item/beacon", "Beacon", Color(0.8, 0.3, 0.1, 1.0))
	_assert(bool(presented.get("success", false)), "R2 third-person item presentation failed")
	var report: Dictionary = presenter.create_report()
	_assert(String(report.get("current_item_id", "")) == "item/beacon", "R2 presenter did not retain item identity")
	_assert(bool(report.get("proxy_present", false)), "R2 presenter did not create a world proxy")
	_assert(int(report.get("world_layer_index", -1)) == 20, "R2 presenter world layer report mismatch")
	_assert(not bool(report.get("owns_item_state", true)), "R2 third-person presenter incorrectly owns item state")
	_assert(not bool(report.get("owns_network_state", true)), "R2 third-person presenter incorrectly owns network state")
	_assert(not bool(report.get("owns_gameplay_transform", true)), "R2 third-person presenter incorrectly owns gameplay transform")
	_assert(presenter._proxy != null, "R2 proxy reference is missing")
	if presenter._proxy != null:
		_assert(presenter._proxy.get_layer_mask_value(20), "R2 world proxy is not on the world render layer")
		_assert(not presenter._proxy.get_layer_mask_value(1), "R2 world proxy leaked onto default render layer 1")

	var cleared: Dictionary = presenter.clear_item()
	_assert(bool(cleared.get("success", false)), "R2 presenter clear failed")
	_assert(String(presenter.create_report().get("current_item_id", "")).is_empty(), "R2 presenter retained stale item after clear")

	# Bone-name discovery is optional for runtime safety. If a skeleton is absent
	# or unknown, the presenter must degrade to an avatar-local anchor rather than
	# touching CharacterBody3D/gameplay transforms or failing the whole scene.
	var fallback_avatar := Node3D.new()
	fallback_avatar.name = "FallbackAvatar"
	root.add_child(fallback_avatar)
	var yaw_root := Node3D.new()
	yaw_root.name = "AvatarYawRoot"
	fallback_avatar.add_child(yaw_root)
	var fallback_presenter = PresenterType.new()
	root.add_child(fallback_presenter)
	var fallback_setup: Dictionary = fallback_presenter.setup(fallback_avatar, null, 20)
	_assert(bool(fallback_setup.get("success", false)), "R2 fallback presenter setup failed")
	_assert(String(fallback_presenter.create_report().get("attachment_mode", "")) == "FALLBACK_AVATAR_ANCHOR", "R2 presenter did not use fallback anchor without a skeleton")
	var fallback_item: Dictionary = fallback_presenter.present_item("item/fallback")
	_assert(bool(fallback_item.get("success", false)), "R2 fallback anchor could not present an item")
	_assert(not bool(fallback_presenter.create_report().get("owns_gameplay_transform", true)), "R2 fallback path incorrectly claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 third-person held-item presenter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 third-person held-item presenter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
