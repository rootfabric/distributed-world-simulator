extends SceneTree

const PresenterType = preload("res://scripts/characters/presentation/two_hand_catalogued_third_person_held_item_presenter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	world.name = "WorldPresentation"
	get_root().add_child(world)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	world.add_child(skeleton)
	skeleton.add_bone("LeftUpperArm")
	skeleton.add_bone("LeftForeArm")
	skeleton.add_bone("LeftHand")
	skeleton.add_bone("RightHand")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_parent(3, -1)
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(-0.25, 1.45, 0.0)))
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.35, 0.0)))
	skeleton.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.35, 0.0)))
	skeleton.set_bone_rest(3, Transform3D(Basis.IDENTITY, Vector3(0.25, 1.20, 0.0)))

	var presenter = PresenterType.new()
	world.add_child(presenter)
	var setup_result: Dictionary = presenter.setup(world, skeleton, 20)
	_assert(bool(setup_result.get("success", false)), "S5 two-hand third-person presenter setup failed")
	_assert(String(presenter.get_secondary_hand_report().get("mode", "")) == "NATIVE_TWO_BONE_IK", "S5 presenter did not configure native IK support")

	var one_hand_visual := {
		"profile_id": "beacon",
		"visual_kind": "CYLINDER",
		"dimensions": [0.12, 0.30, 0.12],
	}
	var one_hand_grip := {
		"profile_id": "beacon_vertical",
		"third_person": {
			"position": [0.0, -0.04, -0.05],
			"rotation_deg": [0.0, 0.0, 8.0],
			"scale": [1.0, 1.0, 1.0],
		},
		"two_hand": {
			"required": false,
			"primary_hand": "right",
			"secondary_hand": "left",
			"presentation_only": true,
		},
	}
	var one_result: Dictionary = presenter.present_catalogued_item(
		"item/test/beacon",
		"Beacon",
		Color(1.0, 0.3, 0.05, 1.0),
		one_hand_visual,
		one_hand_grip
	)
	_assert(bool(one_result.get("success", false)), "S5 one-hand third-person presentation failed")
	_assert(not bool(presenter.get_secondary_hand_report().get("active", true)), "S5 one-hand item unexpectedly activated secondary world hand")
	_assert(not bool(Dictionary(one_result.get("details", {})).get("secondary_world_hand_required", true)), "S5 one-hand result incorrectly requires secondary world hand")

	var two_hand_visual := {
		"profile_id": "mount_base",
		"visual_kind": "BOX",
		"dimensions": [0.28, 0.22, 0.36],
	}
	var two_hand_grip := {
		"profile_id": "mount_base_two_hand",
		"third_person": {
			"position": [0.0, -0.055, -0.10],
			"rotation_deg": [8.0, 0.0, 78.0],
			"scale": [1.0, 1.0, 1.0],
		},
		"two_hand": {
			"required": true,
			"primary_hand": "right",
			"secondary_hand": "left",
			"secondary_anchor": {
				"position": [-0.20, 0.01, 0.01],
				"rotation_deg": [0.0, 0.0, -8.0],
				"scale": [1.0, 1.0, 1.0],
			},
			"presentation_only": true,
		},
	}
	var two_result: Dictionary = presenter.present_catalogued_item(
		"item/test/mount-base",
		"Mount Base",
		Color(0.15, 0.45, 0.65, 1.0),
		two_hand_visual,
		two_hand_grip
	)
	_assert(bool(two_result.get("success", false)), "S5 two-hand third-person presentation failed")
	var two_details: Dictionary = Dictionary(two_result.get("details", {}))
	_assert(bool(two_details.get("secondary_world_hand_required", false)), "S5 two-hand result did not require secondary world hand")
	_assert(bool(two_details.get("secondary_world_hand_active", false)), "S5 two-hand result did not activate secondary world hand")
	_assert(String(two_details.get("secondary_world_hand_mode", "")) == "NATIVE_TWO_BONE_IK", "S5 two-hand result mode mismatch")
	var active_report: Dictionary = presenter.get_secondary_hand_report()
	_assert(bool(active_report.get("active", false)), "S5 presenter secondary world hand report is not active")
	_assert(String(active_report.get("item_id", "")) == "item/test/mount-base", "S5 presenter secondary active item mismatch")
	_assert(bool(presenter.create_report().get("secondary_target_present", false)), "S5 presenter secondary grip target missing")

	var clear_result: Dictionary = presenter.clear_item()
	_assert(bool(clear_result.get("success", false)), "S5 presenter clear failed")
	_assert(not bool(presenter.get_secondary_hand_report().get("active", true)), "S5 presenter secondary world hand remained active after clear")
	_assert(not bool(presenter.create_report().get("secondary_target_present", true)), "S5 presenter secondary target remained after clear")

	var report: Dictionary = presenter.create_report()
	var secondary: Dictionary = Dictionary(report.get("secondary_hand", {}))
	_assert(bool(secondary.get("presentation_only", false)), "S5 presenter secondary support is not presentation-only")
	_assert(not bool(secondary.get("owns_item_state", true)), "S5 presenter secondary support claims item ownership")
	_assert(not bool(secondary.get("owns_network_state", true)), "S5 presenter secondary support claims network ownership")
	_assert(not bool(secondary.get("owns_gameplay_transform", true)), "S5 presenter secondary support claims gameplay transform ownership")
	_assert(not bool(secondary.get("collision_body_created", true)), "S5 presenter secondary support unexpectedly creates collision body")

	world.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S5 two-hand third-person presenter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S5 two-hand third-person presenter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
