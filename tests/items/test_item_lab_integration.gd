extends SceneTree

const LAB_SCENE_PATH := "res://scenes/items/item_system_lab.tscn"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var packed = load(LAB_SCENE_PATH)
	_assert(
		packed is PackedScene,
		"Item laboratory scene must load as PackedScene"
	)
	if not packed is PackedScene:
		_finish()
		return

	var lab = packed.instantiate()
	get_root().add_child(lab)
	await process_frame
	await process_frame

	var initial: Dictionary = lab.get_debug_snapshot()
	_assert(
		initial.rock_relation == "WORLD",
		"Rock must initially be in WORLD"
	)
	_assert(
		initial.crate_relation == "WORLD",
		"Filled crate must initially be in WORLD"
	)
	_assert(
		initial.crate_rocks_relation == "CONTAINER",
		"Crate contents must remain in its inner container"
	)
	_assert(
		initial.lidar_relation == "WORLD",
		"Lidar must initially be in WORLD"
	)
	_assert(
		bool(initial.rock_world_body),
		"WORLD rock must have RigidBody3D"
	)
	_assert(
		bool(initial.crate_world_body),
		"WORLD crate must have RigidBody3D"
	)
	_assert(
		bool(initial.lidar_world_body),
		"WORLD lidar must have RigidBody3D"
	)
	_assert(
		bool(initial.rock_has_texture),
		"Rock world presentation must load its albedo texture"
	)
	_assert(
		not bool(initial.chassis_world_body),
		"Externally presented chassis must not be duplicated"
	)
	_assert(
		bool(initial.graph_valid),
		"Initial item relation graph must be valid"
	)

	var pickup_rock: Dictionary = lab.run_lab_action(
		"pickup_rock"
	)
	_assert_success(
		pickup_rock,
		"Rock pickup action must succeed"
	)
	var after_pickup_rock: Dictionary = lab.get_debug_snapshot()
	_assert(
		after_pickup_rock.rock_relation == "CONTAINER",
		"Picked rock must move to CONTAINER"
	)
	_assert(
		not bool(after_pickup_rock.rock_world_body),
		"Picked rock must lose world physics"
	)
	_assert(
		after_pickup_rock.backpack_item_ids.has(
			after_pickup_rock.rock_id
		),
		"Backpack must contain picked rock instance"
	)

	var drop_rock: Dictionary = lab.run_lab_action(
		"drop_rock"
	)
	_assert_success(
		drop_rock,
		"Rock drop action must succeed"
	)
	var after_drop_rock: Dictionary = lab.get_debug_snapshot()
	_assert(
		after_drop_rock.rock_relation == "WORLD",
		"Dropped rock must return to WORLD"
	)
	_assert(
		bool(after_drop_rock.rock_world_body),
		"Dropped rock must restore RigidBody3D"
	)
	_assert(
		after_drop_rock.rock_id == initial.rock_id,
		"World-container roundtrip must preserve rock identity"
	)

	var original_crate_contents: Array = (
		initial.crate_item_ids.duplicate()
	)
	var pickup_crate: Dictionary = lab.run_lab_action(
		"pickup_crate"
	)
	_assert_success(
		pickup_crate,
		"Filled crate pickup must succeed"
	)
	var after_pickup_crate: Dictionary = lab.get_debug_snapshot()
	_assert(
		after_pickup_crate.crate_relation == "CONTAINER",
		"Picked crate must move to backpack"
	)
	_assert(
		not bool(after_pickup_crate.crate_world_body),
		"Picked crate must lose world physics"
	)
	_assert(
		after_pickup_crate.crate_item_ids == original_crate_contents,
		"Picking filled crate must preserve exact contents"
	)
	_assert(
		after_pickup_crate.crate_rocks_relation == "CONTAINER",
		"Contained rock relation must not be rewritten"
	)

	var pickup_lidar: Dictionary = lab.run_lab_action(
		"pickup_lidar"
	)
	_assert_success(
		pickup_lidar,
		"Lidar pickup must succeed"
	)
	var attach_lidar: Dictionary = lab.run_lab_action(
		"attach_lidar"
	)
	_assert_success(
		attach_lidar,
		"Lidar attachment must succeed"
	)
	var after_attach: Dictionary = lab.get_debug_snapshot()
	_assert(
		after_attach.lidar_relation == "ATTACHMENT",
		"Attached lidar must use ATTACHMENT relation"
	)
	_assert(
		not bool(after_attach.lidar_world_body),
		"Attached lidar must not keep independent world physics"
	)
	_assert(
		bool(after_attach.lidar_attached_node),
		"Attached lidar must have assembly presentation"
	)
	_assert(
		after_attach.socket_item_id == after_attach.lidar_id,
		"Rover socket must reference attached lidar instance"
	)

	var detach_lidar: Dictionary = lab.run_lab_action(
		"detach_lidar"
	)
	_assert_success(
		detach_lidar,
		"Lidar detachment must succeed"
	)
	var after_detach: Dictionary = lab.get_debug_snapshot()
	_assert(
		after_detach.lidar_relation == "CONTAINER",
		"Detached lidar must move back to backpack"
	)
	_assert(
		not bool(after_detach.lidar_attached_node),
		"Detached lidar presentation must be removed"
	)
	_assert(
		after_detach.socket_item_id.is_empty(),
		"Socket must become empty after detachment"
	)
	_assert(
		after_detach.lidar_id == initial.lidar_id,
		"Attachment roundtrip must preserve lidar identity"
	)
	_assert(
		bool(after_detach.graph_valid),
		"Graph must remain valid after all lab actions"
	)

	lab.queue_free()
	await process_frame
	_finish()


func _assert_success(
	result: Dictionary,
	message: String
) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s; result=%s" % [message, str(result)]
	)


func _assert(
	condition: bool,
	message: String
) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print(
			"Item laboratory integration: PASS (%d assertions)"
			% assertions
		)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"Item laboratory integration: FAIL "
		+ "(%d failures, %d assertions)"
		% [failures.size(), assertions]
	)
	quit(1)
