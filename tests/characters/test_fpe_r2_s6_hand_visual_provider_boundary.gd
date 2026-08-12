extends SceneTree

const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const SyntheticProviderType = preload("res://tests/characters/fpe_s6_synthetic_hand_visual_provider.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var default_rig = RigType.new()
	root.add_child(default_rig)
	var default_setup: Dictionary = default_rig.setup("right", 19)
	_assert(bool(default_setup.get("success", false)), "S6 default provider rig setup failed")
	var default_report: Dictionary = default_rig.create_report()
	var default_provider: Dictionary = Dictionary(default_report.get("visual_provider", {}))
	_assert(int(default_report.get("bone_count", 0)) == 17, "S6 default rig lost canonical 17-bone skeleton")
	_assert(int(default_report.get("visual_segments", 0)) == 16, "S6 default provider did not reproduce 16 procedural visuals")
	_assert(String(default_report.get("visual_provider_mode", "")) == "PROCEDURAL_SEGMENTS", "S6 default provider mode mismatch")
	_assert(String(default_report.get("visual_provider_id", "")) == "procedural_segments_v1", "S6 default provider id mismatch")
	_assert(String(default_report.get("compatible_skeleton_schema", "")) == "planet_simulator.fpe_hand_skeleton.v1", "S6 default provider skeleton schema mismatch")
	_assert(bool(default_report.get("visual_provider_substitutable", false)), "S6 default rig did not expose visual substitution boundary")
	_assert(bool(default_report.get("pose_logic_independent_of_visual_provider", false)), "S6 rig does not declare pose/visual separation")
	_assert(bool(default_provider.get("presentation_only", false)), "S6 default provider is not presentation-only")
	_assert(not bool(default_provider.get("owns_item_state", true)), "S6 default provider claims item ownership")
	_assert(not bool(default_provider.get("owns_network_state", true)), "S6 default provider claims network ownership")
	_assert(not bool(default_provider.get("owns_gameplay_transform", true)), "S6 default provider claims gameplay transform ownership")

	var default_layers_ok := true
	for visual in default_rig._visual_segments:
		if visual == null or not visual.get_layer_mask_value(19) or visual.get_layer_mask_value(1):
			default_layers_ok = false
			break
	_assert(default_layers_ok, "S6 default provider leaked hand visuals outside viewmodel layer")

	var synthetic_provider = SyntheticProviderType.new()
	var synthetic_rig = RigType.new()
	root.add_child(synthetic_rig)
	var provider_config: Dictionary = synthetic_rig.configure_visual_provider(synthetic_provider)
	_assert(bool(provider_config.get("success", false)), "S6 compatible provider configuration failed")
	var synthetic_setup: Dictionary = synthetic_rig.setup("left", 19)
	_assert(bool(synthetic_setup.get("success", false)), "S6 compatible provider substitution failed")
	var synthetic_report: Dictionary = synthetic_rig.create_report()
	var synthetic_provider_report: Dictionary = Dictionary(synthetic_report.get("visual_provider", {}))
	_assert(int(synthetic_report.get("bone_count", 0)) == 17, "S6 compatible provider changed pose skeleton")
	_assert(int(synthetic_report.get("visual_segments", 0)) == 1, "S6 compatible provider visual count mismatch")
	_assert(String(synthetic_report.get("visual_provider_mode", "")) == "SYNTHETIC_COMPATIBLE", "S6 compatible provider mode was not surfaced")
	_assert(String(synthetic_report.get("visual_provider_id", "")) == "synthetic_compatible_visual_v1", "S6 compatible provider id was not surfaced")
	_assert(int(synthetic_provider.install_calls) == 1, "S6 compatible provider was not installed exactly once")
	_assert(String(synthetic_provider.last_hand_id) == "left", "S6 compatible provider received wrong hand identity")
	_assert(int(synthetic_provider.last_bone_count) == 17, "S6 compatible provider did not receive canonical skeleton")
	_assert(int(synthetic_provider.last_layer) == 19, "S6 compatible provider received wrong render layer")
	_assert(bool(synthetic_provider_report.get("substitutable", false)), "S6 compatible provider did not declare substitution contract")

	var synthetic_visual = synthetic_rig._visual_segments[0] if not synthetic_rig._visual_segments.is_empty() else null
	_assert(synthetic_visual is MeshInstance3D, "S6 compatible provider did not install a MeshInstance3D")
	if synthetic_visual is MeshInstance3D:
		_assert(synthetic_visual.get_layer_mask_value(19), "S6 compatible provider visual missed viewmodel layer")
		_assert(not synthetic_visual.get_layer_mask_value(1), "S6 compatible provider visual leaked to default layer")

	var poses = PoseCatalogType.new()
	var pose_result: Dictionary = synthetic_rig.apply_pose(poses.get_pose("support_cradle"))
	_assert(bool(pose_result.get("success", false)), "S6 pose application failed after visual provider substitution")
	synthetic_rig._process(0.2)
	var posed_report: Dictionary = synthetic_rig.create_report()
	_assert(String(posed_report.get("settled_pose_id", "")) == "support_cradle", "S6 substituted visuals broke pose settling")
	_assert(not bool(posed_report.get("transitioning", true)), "S6 substituted visual rig kept processing after pose settled")
	_assert(not bool(posed_report.get("owns_item_state", true)), "S6 substituted rig claims item ownership")
	_assert(not bool(posed_report.get("owns_network_state", true)), "S6 substituted rig claims network ownership")
	_assert(not bool(posed_report.get("owns_gameplay_transform", true)), "S6 substituted rig claims gameplay transform ownership")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S6 hand visual provider boundary: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S6 hand visual provider boundary: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
