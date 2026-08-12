extends SceneTree

const RigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const ProviderType = preload("res://scripts/characters/presentation/resource_backed_first_person_hand_visual_provider.gd")
const PoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const AuthoredFixture = preload("res://tests/fixtures/fpe_s7_authored_hand_visual.tscn")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	get_root().add_child(root)

	var provider = ProviderType.new()
	var provider_setup: Dictionary = provider.setup(
		AuthoredFixture,
		"res://tests/fixtures/fpe_s7_authored_hand_visual.tscn"
	)
	_assert(bool(provider_setup.get("success", false)), "S7 resource provider setup failed")

	var rig = RigType.new()
	root.add_child(rig)
	var setup_result: Dictionary = rig.setup("right", 19, provider)
	_assert(bool(setup_result.get("success", false)), "S7 resource-backed rig setup failed")
	var report: Dictionary = rig.create_report()
	var provider_report: Dictionary = Dictionary(report.get("visual_provider", {}))
	_assert(int(report.get("bone_count", 0)) == 17, "S7 resource provider changed canonical bone count")
	_assert(int(report.get("visual_segments", 0)) == 3, "S7 authored fixture visual count mismatch")
	_assert(String(report.get("visual_provider_mode", "")) == "RESOURCE_BONE_ATTACHMENTS", "S7 resource provider mode mismatch")
	_assert(String(report.get("visual_provider_id", "")) == "fpe_s7_fixture_authored_hand_v1", "S7 authored provider id mismatch")
	_assert(String(report.get("compatible_skeleton_schema", "")) == "planet_simulator.fpe_hand_skeleton.v1", "S7 skeleton schema mismatch")
	_assert(bool(report.get("visual_provider_substitutable", false)), "S7 rig lost provider substitution boundary")
	_assert(bool(report.get("pose_logic_independent_of_visual_provider", false)), "S7 resource visuals are coupled to pose logic")
	_assert(bool(provider_report.get("resource_backed", false)), "S7 provider did not report resource-backed mode")
	_assert(String(provider_report.get("asset_schema", "")) == "planet_simulator.fpe_hand_visual_asset.v1", "S7 asset schema mismatch")
	_assert(String(provider_report.get("resource_path", "")) == "res://tests/fixtures/fpe_s7_authored_hand_visual.tscn", "S7 resource path was not surfaced")
	_assert(int(provider_report.get("bone_attachment_count", 0)) == 3, "S7 attachment count mismatch")
	_assert(int(provider_report.get("installed_visual_count", 0)) == 3, "S7 installed visual count mismatch")
	_assert(bool(provider_report.get("bone_driven", false)), "S7 authored visuals are not bone-driven")
	_assert(bool(provider_report.get("presentation_only", false)), "S7 provider is not presentation-only")
	_assert(not bool(provider_report.get("owns_item_state", true)), "S7 provider claims item ownership")
	_assert(not bool(provider_report.get("owns_network_state", true)), "S7 provider claims network ownership")
	_assert(not bool(provider_report.get("owns_gameplay_transform", true)), "S7 provider claims gameplay transform ownership")

	var layers_ok := true
	for visual in rig._visual_segments:
		if visual == null or not visual.get_layer_mask_value(19) or visual.get_layer_mask_value(1):
			layers_ok = false
			break
	_assert(layers_ok, "S7 authored visuals leaked outside viewmodel layer")
	_assert(rig.skeleton.get_node_or_null("PalmAttachment") is BoneAttachment3D, "S7 palm attachment was not moved onto canonical skeleton")
	_assert(rig.skeleton.get_node_or_null("IndexAttachment") is BoneAttachment3D, "S7 index attachment was not moved onto canonical skeleton")
	_assert(rig.skeleton.get_node_or_null("ThumbAttachment") is BoneAttachment3D, "S7 thumb attachment was not moved onto canonical skeleton")

	var poses = PoseCatalogType.new()
	var pose_result: Dictionary = rig.apply_pose(poses.get_pose("bulky_carry"))
	_assert(bool(pose_result.get("success", false)), "S7 authored visuals broke pose application")
	rig._process(0.2)
	var posed_report: Dictionary = rig.create_report()
	_assert(String(posed_report.get("settled_pose_id", "")) == "bulky_carry", "S7 authored visuals broke pose settling")
	_assert(not bool(posed_report.get("transitioning", true)), "S7 authored rig kept processing after pose settled")

	var invalid_root := Node3D.new()
	invalid_root.set_meta("fpe_hand_visual_schema", "wrong.schema")
	invalid_root.set_meta("fpe_compatible_skeleton_schema", "planet_simulator.fpe_hand_skeleton.v1")
	var invalid_scene := PackedScene.new()
	var packed_error := invalid_scene.pack(invalid_root)
	_assert(packed_error == OK, "S7 invalid-schema fixture could not be packed")
	invalid_root.free()
	var invalid_provider = ProviderType.new()
	var invalid_provider_setup: Dictionary = invalid_provider.setup(invalid_scene, "memory://invalid_s7_hand")
	_assert(bool(invalid_provider_setup.get("success", false)), "S7 invalid provider setup unexpectedly failed before asset validation")
	var invalid_rig = RigType.new()
	root.add_child(invalid_rig)
	var invalid_result: Dictionary = invalid_rig.setup("left", 19, invalid_provider)
	_assert(not bool(invalid_result.get("success", true)), "S7 incompatible authored resource did not fail closed")
	_assert(String(invalid_result.get("error_code", "")) == "FPE_S6_SUBSTITUTABLE_HAND_SETUP_FAILED", "S7 incompatible resource did not propagate rig setup failure")
	var nested_details: Dictionary = Dictionary(invalid_result.get("details", {}))
	var provider_failure: Dictionary = Dictionary(nested_details.get("provider", {}))
	_assert(String(provider_failure.get("error_code", "")) == "FPE_S7_HAND_VISUAL_ASSET_SCHEMA_MISMATCH", "S7 incompatible resource lost exact schema error")

	root.queue_free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FPE R2 S7 resource-backed hand visual provider: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FPE R2 S7 resource-backed hand visual provider: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
