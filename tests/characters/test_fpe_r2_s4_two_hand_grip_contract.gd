extends SceneTree

const ViewmodelCatalogType = preload("res://scripts/characters/presentation/item_viewmodel_catalog.gd")
const GripCatalogType = preload("res://scripts/characters/presentation/held_item_grip_profile_catalog.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var visuals = ViewmodelCatalogType.new()
	var grips = GripCatalogType.new()

	var beacon_visual: Dictionary = visuals.resolve("survey_beacon", ["beacon", "mountable", "electronic"], {}, "", Color(1.0, 0.3, 0.05, 1.0))
	var beacon_grip: Dictionary = grips.resolve("survey_beacon", beacon_visual, ["beacon", "mountable", "electronic"], {})
	var beacon_two: Dictionary = Dictionary(beacon_grip.get("two_hand", {}))
	_assert(not bool(beacon_two.get("required", true)), "S4 beacon unexpectedly requires two hands")
	_assert(String(beacon_two.get("secondary_hand", "")) == "left", "S4 one-hand contract lost deterministic secondary-hand identity")

	# Match the actual M7 replica identity instead of the canonical server id.
	# `beacon_mount_base` contains `beacon`, which is exactly the precedence case
	# that previously made graphical slot 2 keep beacon_pinch and one-hand mode.
	var mount_visual: Dictionary = visuals.resolve(
		"beacon_mount_base",
		["assembly_root", "placeable", "mount_socket"],
		{},
		"",
		Color(0.15, 0.45, 0.65, 1.0)
	)
	var mount_grip: Dictionary = grips.resolve(
		"beacon_mount_base",
		mount_visual,
		["assembly_root", "placeable", "mount_socket"],
		{}
	)
	var mount_two: Dictionary = Dictionary(mount_grip.get("two_hand", {}))
	_assert(bool(mount_two.get("required", false)), "S4 playable mount-base did not resolve as two-hand demonstration item")
	_assert(String(mount_grip.get("profile_id", "")) == "mount_base_two_hand", "S4 mount-base grip profile mismatch")
	_assert(String(mount_two.get("primary_hand", "")) == "right", "S4 primary hand is not right")
	_assert(String(mount_two.get("secondary_hand", "")) == "left", "S4 secondary hand is not left")
	_assert(String(mount_two.get("secondary_pose_id", "")) == "support_cradle", "S4 mount-base secondary pose mismatch")
	var mount_anchor: Dictionary = Dictionary(mount_two.get("secondary_anchor", {}))
	_assert(Array(mount_anchor.get("position", [])).size() == 3, "S4 secondary anchor position is malformed")
	_assert(Array(mount_anchor.get("rotation_deg", [])).size() == 3, "S4 secondary anchor rotation is malformed")
	_assert(bool(mount_two.get("presentation_only", false)), "S4 secondary grip contract is not presentation-only")

	var forced_one: Dictionary = grips.resolve(
		"beacon_mount_base",
		mount_visual,
		["assembly_root", "placeable", "mount_socket"],
		{"held_two_hand": false}
	)
	_assert(not bool(Dictionary(forced_one.get("two_hand", {})).get("required", true)), "S4 metadata could not explicitly disable two-hand support")

	var forced_two: Dictionary = grips.resolve(
		"survey_beacon",
		beacon_visual,
		["beacon", "mountable", "electronic"],
		{
			"held_two_hand": true,
			"held_secondary_pose": "support_wrap",
			"held_secondary_anchor_position": [-0.25, 0.02, 0.01],
		}
	)
	var forced_two_contract: Dictionary = Dictionary(forced_two.get("two_hand", {}))
	_assert(bool(forced_two_contract.get("required", false)), "S4 metadata could not enable two-hand support")
	_assert(String(forced_two_contract.get("secondary_pose_id", "")) == "support_wrap", "S4 metadata secondary pose override failed")
	var forced_anchor: Dictionary = Dictionary(forced_two_contract.get("secondary_anchor", {}))
	var forced_position: Array = Array(forced_anchor.get("position", []))
	_assert(forced_position.size() == 3, "S4 metadata secondary anchor position malformed")
	if forced_position.size() == 3:
		_assert(absf(float(forced_position[0]) + 0.25) < 0.0001, "S4 metadata secondary anchor X override failed")

	_assert(String(mount_grip.get("schema", "")) == "planet_simulator.held_item_grip_profile.v2", "S4 grip profile schema did not advance to v2")
	_assert(bool(mount_grip.get("presentation_only", false)), "S4 grip profile is not presentation-only")
	_assert(not bool(mount_grip.get("owns_item_state", true)), "S4 grip profile claims item ownership")
	_assert(not bool(mount_grip.get("owns_network_state", true)), "S4 grip profile claims network ownership")
	_assert(not bool(mount_grip.get("owns_gameplay_transform", true)), "S4 grip profile claims gameplay transform ownership")

	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S4 two-hand grip contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S4 two-hand grip contract: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
