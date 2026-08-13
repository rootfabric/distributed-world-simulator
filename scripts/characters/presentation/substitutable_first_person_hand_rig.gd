class_name SubstitutableFirstPersonHandRig
extends "res://scripts/characters/presentation/articulated_first_person_hand_rig.gd"

const DefaultVisualProviderType = preload("res://scripts/characters/presentation/first_person_hand_visual_provider.gd")
const SKELETON_SCHEMA := "planet_simulator.fpe_hand_skeleton.v1"

var visual_provider
var _visual_provider_result: Dictionary = {}
var _visual_provider_report: Dictionary = {}
var _visual_provider_pose_sync_result: Dictionary = {}


func configure_visual_provider(provider) -> Dictionary:
	if _configured:
		return _failure("FPE_S6_PROVIDER_CONFIGURATION_AFTER_SETUP")
	if provider == null or not provider.has_method("install_visuals"):
		return _failure("FPE_S6_HAND_VISUAL_PROVIDER_REQUIRED")
	visual_provider = provider
	return _success({"configured": true})


func setup(
	p_hand_id: String,
	p_viewmodel_layer_index: int = DEFAULT_VIEWMODEL_LAYER,
	p_visual_provider: Variant = null
) -> Dictionary:
	if p_visual_provider != null:
		var provider_config: Dictionary = configure_visual_provider(p_visual_provider)
		if not bool(provider_config.get("success", false)):
			return provider_config
	if visual_provider == null:
		visual_provider = DefaultVisualProviderType.new()
	_visual_provider_result.clear()
	_visual_provider_report.clear()
	_visual_provider_pose_sync_result.clear()

	var inherited_result: Dictionary = super.setup(p_hand_id, p_viewmodel_layer_index)
	var provider_ok := bool(_visual_provider_result.get("success", false))
	var skeleton_ok := skeleton != null and skeleton.get_bone_count() >= 17
	var visuals_ok := not _visual_segments.is_empty()
	_configured = skeleton_ok and provider_ok and visuals_ok
	if not _configured:
		return _failure("FPE_S6_SUBSTITUTABLE_HAND_SETUP_FAILED", {
			"inherited": inherited_result,
			"provider": _visual_provider_result,
			"skeleton_ok": skeleton_ok,
			"visuals_ok": visuals_ok,
		})
	_sync_visual_provider_pose()
	return _success(create_report())


func _build_visuals() -> void:
	_visual_segments.clear()
	if visual_provider == null or not visual_provider.has_method("install_visuals"):
		_visual_provider_result = _failure("FPE_S6_HAND_VISUAL_PROVIDER_REQUIRED")
		return
	var value: Variant = visual_provider.call(
		"install_visuals",
		skeleton,
		hand_id,
		viewmodel_layer_index
	)
	if not value is Dictionary:
		_visual_provider_result = _failure("FPE_S6_HAND_VISUAL_PROVIDER_RESULT_INVALID")
		return
	_visual_provider_result = Dictionary(value)
	if not bool(_visual_provider_result.get("success", false)):
		return

	var details: Dictionary = Dictionary(_visual_provider_result.get("details", {}))
	var raw_visuals: Variant = details.get("visuals", [])
	if raw_visuals is Array:
		for raw_visual in raw_visuals:
			if raw_visual is MeshInstance3D and is_instance_valid(raw_visual):
				_visual_segments.append(raw_visual)
	var raw_report: Variant = details.get("report", {})
	if raw_report is Dictionary:
		_visual_provider_report = Dictionary(raw_report).duplicate(true)
	else:
		_visual_provider_report = {}
	if _visual_provider_report.is_empty():
		_refresh_visual_provider_report()


func _apply_transition(weight: float) -> void:
	super._apply_transition(weight)
	_sync_visual_provider_pose()


func _sync_visual_provider_pose() -> void:
	if visual_provider == null or skeleton == null:
		return
	if not visual_provider.has_method("sync_pose_from_canonical"):
		return
	var value: Variant = visual_provider.call("sync_pose_from_canonical", skeleton, hand_id)
	if value is Dictionary:
		_visual_provider_pose_sync_result = Dictionary(value).duplicate(true)
	else:
		_visual_provider_pose_sync_result = _failure("FPE_S6_VISUAL_PROVIDER_POSE_SYNC_RESULT_INVALID")
	_refresh_visual_provider_report()


func _refresh_visual_provider_report() -> void:
	if visual_provider == null:
		return
	var report_value: Variant = null
	if visual_provider.has_method("create_live_report"):
		report_value = visual_provider.call("create_live_report", _visual_segments.size())
	elif visual_provider.has_method("create_report"):
		report_value = visual_provider.call("create_report", _visual_segments.size())
	if report_value is Dictionary:
		_visual_provider_report = Dictionary(report_value).duplicate(true)


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["schema"] = "planet_simulator.substitutable_first_person_hand_rig.v1"
	report["visual_provider"] = _visual_provider_report.duplicate(true)
	report["visual_provider_present"] = visual_provider != null
	report["visual_provider_mode"] = String(_visual_provider_report.get("mode", "UNAVAILABLE"))
	report["visual_provider_id"] = String(_visual_provider_report.get("provider_id", ""))
	report["compatible_skeleton_schema"] = String(
		_visual_provider_report.get("compatible_skeleton_schema", SKELETON_SCHEMA)
	)
	report["visual_provider_substitutable"] = true
	report["pose_logic_independent_of_visual_provider"] = true
	report["visual_provider_pose_sync_supported"] = visual_provider != null and visual_provider.has_method("sync_pose_from_canonical")
	report["visual_provider_pose_sync"] = _visual_provider_pose_sync_result.duplicate(true)
	return report
