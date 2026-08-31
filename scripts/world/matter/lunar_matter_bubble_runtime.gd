extends Node3D

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BubbleScript = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const LegacyAdapterScript = preload(
	"res://scripts/world/matter/legacy_moon_surface_adapter.gd"
)
const PresenterScript = preload(
	"res://scripts/world/matter/lunar_matter_bubble_presenter.gd"
)

var _configured := false
var _moon_world = null
var _bubble = null
var _legacy_adapter = null
var _presenter = null


func configure(moon_world, data: Dictionary = {}) -> Dictionary:
	if _configured:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_RUNTIME_ALREADY_CONFIGURED")
	if moon_world == null 		or not moon_world.has_method("get_moon_radius") 		or not moon_world.has_method("get_coarse_surface_height") 		or not moon_world.has_method("set_matter_surface_adapter") 		or not moon_world.has_method("prepare_surface_region"):
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_RUNTIME_MOON_WORLD_INVALID")
	var anchor_value = data.get("anchor_direction", [0.0, 1.0, 0.0])
	if typeof(anchor_value) != TYPE_ARRAY or Array(anchor_value).size() != 3:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_RUNTIME_ANCHOR_INVALID")
	var anchor := Vector3(
		float(anchor_value[0]), float(anchor_value[1]), float(anchor_value[2])
	)
	if anchor.length_squared() <= 0.000000000001:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_RUNTIME_ANCHOR_INVALID")
	anchor = anchor.normalized()
	var canonical_surface_radius_m := float(data.get(
		"canonical_surface_radius_m",
		float(moon_world.get_moon_radius())
			+ float(moon_world.get_coarse_surface_height(anchor))
	))
	var bubble = BubbleScript.new()
	var bubble_data := data.duplicate(true)
	bubble_data["anchor_direction"] = [anchor.x, anchor.y, anchor.z]
	bubble_data["canonical_surface_radius_m"] = canonical_surface_radius_m
	var bubble_setup: Dictionary = bubble.configure(bubble_data)
	if not bool(bubble_setup.get("success", false)):
		return bubble_setup
	var adapter = LegacyAdapterScript.new()
	var adapter_setup := adapter.configure(
		bubble,
		float(data.get("legacy_seam_clearance_m", 0.02))
	)
	if not bool(adapter_setup.get("success", false)):
		return adapter_setup
	var adapter_install: Dictionary = moon_world.set_matter_surface_adapter(adapter)
	if not bool(adapter_install.get("success", false)):
		return adapter_install

	var presenter = PresenterScript.new()
	presenter.name = "P7LunarMatterBubblePresenter"
	add_child(presenter)
	var presenter_setup: Dictionary = presenter.configure(
		bubble,
		moon_world,
		bool(data.get("build_collision", true))
	)
	if not bool(presenter_setup.get("success", false)):
		presenter.queue_free()
		moon_world.set_matter_surface_adapter(null)
		return presenter_setup

	_moon_world = moon_world
	_bubble = bubble
	_legacy_adapter = adapter
	_presenter = presenter
	_configured = true
	if bool(data.get("rebuild_legacy_surface", true)):
		moon_world.prepare_surface_region(anchor, true)
	return MatterUtilsScript.success(contract_report())


func bubble():
	return _bubble


func legacy_adapter():
	return _legacy_adapter


func presenter():
	return _presenter


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"bubble": _bubble.contract_report() if _bubble != null else {},
		"legacy_adapter": _legacy_adapter.contract_report()
			if _legacy_adapter != null else {},
		"presenter": _presenter.contract_report() if _presenter != null else {},
		"canonical_state_owned": false,
		"legacy_outside_preserved": true,
	}


func disable_and_restore_legacy() -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("P7_LUNAR_MATTER_RUNTIME_NOT_CONFIGURED")
	_bubble.set_enabled(false)
	var cleared: Dictionary = _moon_world.set_matter_surface_adapter(null)
	if not bool(cleared.get("success", false)):
		return cleared
	_moon_world.prepare_surface_region(_bubble.anchor_direction(), true)
	if _presenter != null and is_instance_valid(_presenter):
		_presenter.visible = false
	return MatterUtilsScript.success({
		"route": "LEGACY_ONLY",
		"canonical_matter_state_deleted": false,
	})
