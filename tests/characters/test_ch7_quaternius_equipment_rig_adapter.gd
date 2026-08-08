extends SceneTree

const AvatarPresenter = preload("res://scripts/characters/presentation/quaternius_grounded_avatar_presenter.gd")
const RigAdapter = preload("res://scripts/characters/equipment/quaternius_equipment_rig_adapter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)

	var presenter = AvatarPresenter.new()
	host.add_child(presenter)
	var setup_result: Dictionary = presenter.setup({
		"model_path": "res://tests/fixtures/ch5_synthetic_quaternius_base.tscn",
		"animation_path": "res://tests/fixtures/ch5_synthetic_quaternius_animation.tscn",
		"crouch_ground_offset_m": 0.35,
	})
	_assert(bool(setup_result.get("success", false)), "Synthetic Quaternius presenter setup failed")
	await process_frame

	var adapter = RigAdapter.new()
	var bind_result: Dictionary = adapter.bind_presenter(presenter)
	_assert(bool(bind_result.get("success", false)), "Quaternius equipment rig adapter bind failed")
	var report: Dictionary = adapter.create_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.quaternius_equipment_rig_adapter.v1", "Unexpected Quaternius equipment adapter schema")
	_assert(String(report.get("rig_profile_id", "")) == "quaternius.ual1.humanoid", "Unexpected Quaternius equipment rig profile ID")
	_assert(String(report.get("mode", "")) == "SKELETON", "Synthetic Quaternius equipment adapter did not select skeleton mode")
	_assert(bool(report.get("target_skeleton", false)), "Synthetic Quaternius target skeleton missing")
	_assert(adapter.supports_anchor("body.head"), "Quaternius semantic head anchor missing")
	_assert(adapter.supports_anchor("gear.back"), "Quaternius semantic back anchor missing")
	_assert(adapter.supports_anchor("hand.left"), "Quaternius semantic left hand anchor missing")
	_assert(adapter.supports_anchor("hand.right"), "Quaternius semantic right hand anchor missing")

	var head_anchor: Node3D = adapter.resolve_anchor(presenter, "body.head")
	var back_anchor: Node3D = adapter.resolve_anchor(presenter, "gear.back")
	var left_hand_anchor: Node3D = adapter.resolve_anchor(presenter, "hand.left")
	var right_hand_anchor: Node3D = adapter.resolve_anchor(presenter, "hand.right")
	_assert(head_anchor is BoneAttachment3D, "Skeleton head anchor is not BoneAttachment3D")
	_assert(back_anchor is BoneAttachment3D, "Skeleton back anchor is not BoneAttachment3D")
	_assert(left_hand_anchor is BoneAttachment3D, "Skeleton left hand anchor is not BoneAttachment3D")
	_assert(right_hand_anchor is BoneAttachment3D, "Skeleton right hand anchor is not BoneAttachment3D")
	_assert(String((head_anchor as BoneAttachment3D).bone_name) == "head", "Head semantic mapped to wrong bone")
	_assert(String((back_anchor as BoneAttachment3D).bone_name) == "spine", "Back semantic mapped to wrong synthetic bone")
	_assert(String((left_hand_anchor as BoneAttachment3D).bone_name) == "hand_l", "Left hand semantic mapped to wrong bone")
	_assert(String((right_hand_anchor as BoneAttachment3D).bone_name) == "hand_r", "Right hand semantic mapped to wrong bone")
	_assert(adapter.resolve_anchor(presenter, "body.head") == head_anchor, "Repeated head anchor resolution created a duplicate attachment")
	_assert(int(adapter.create_report().get("attachment_count", 0)) == 4, "Unexpected BoneAttachment3D cache size")

	var yaw_root: Node3D = presenter.get_node_or_null("AvatarYawRoot") as Node3D
	_assert(yaw_root != null, "AvatarYawRoot missing")
	var standing_y: float = yaw_root.position.y
	presenter.apply_motion(Vector3.ZERO, Vector3.UP, Vector3.FORWARD, {"grounded": true, "crouching": true})
	presenter.call("_update_ground_compensation", 1.0)
	_assert(is_equal_approx(yaw_root.position.y, -0.35), "Quaternius crouch presentation root did not reach -0.35 m")
	_assert(not is_equal_approx(yaw_root.position.y, standing_y), "Crouch did not alter presentation root")
	_assert(_has_ancestor(head_anchor, yaw_root), "Equipment bone anchor is outside crouch-compensated presentation hierarchy")
	_assert(_has_ancestor(back_anchor, yaw_root), "Back equipment anchor is outside crouch-compensated presentation hierarchy")
	_assert(not bool(adapter.create_report().get("moves_gameplay_body", true)), "Rig adapter claims gameplay movement authority")
	_assert(not bool(adapter.create_report().get("reads_input", true)), "Rig adapter claims input authority")
	_assert(not bool(adapter.create_report().get("owns_network_state", true)), "Rig adapter claims network authority")

	var fallback_host := Node3D.new()
	root.add_child(fallback_host)
	var fallback_presenter = AvatarPresenter.new()
	fallback_host.add_child(fallback_presenter)
	_assert(bool(fallback_presenter.setup({"force_fallback": true}).get("success", false)), "Fallback presenter setup failed")
	await process_frame
	var fallback_adapter = RigAdapter.new()
	_assert(bool(fallback_adapter.bind_presenter(fallback_presenter).get("success", false)), "Fallback equipment rig adapter bind failed")
	var fallback_report: Dictionary = fallback_adapter.create_report()
	_assert(String(fallback_report.get("mode", "")) == "FALLBACK", "Fallback equipment adapter did not select fallback mode")
	var fallback_head: Node3D = fallback_adapter.resolve_anchor(fallback_presenter, "body.head")
	var fallback_back: Node3D = fallback_adapter.resolve_anchor(fallback_presenter, "gear.back")
	_assert(fallback_head is Node3D and String(fallback_head.name) == "Head", "Fallback head semantic did not resolve to Head pivot")
	_assert(fallback_back is Node3D and String(fallback_back.name) == "Torso", "Fallback back semantic did not resolve to Torso pivot")
	_assert(not (fallback_head is BoneAttachment3D), "Fallback path unexpectedly created a bone attachment")

	var source: String = FileAccess.get_file_as_string("res://scripts/characters/equipment/quaternius_equipment_rig_adapter.gd")
	for forbidden in ["CharacterBody3D", "Input.", "multiplayer", "@rpc", "rpc(", "ItemGraph"]:
		_assert(not source.contains(forbidden), "Quaternius equipment adapter gained forbidden gameplay/runtime dependency: %s" % forbidden)

	host.queue_free()
	fallback_host.queue_free()
	_finish()


func _has_ancestor(node: Node, expected_ancestor: Node) -> bool:
	var current: Node = node
	while current != null:
		if current == expected_ancestor:
			return true
		current = current.get_parent()
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH7 Quaternius equipment rig adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH7 Quaternius equipment rig adapter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
