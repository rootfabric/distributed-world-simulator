class_name QuaterniusSkinnedGarmentLab
extends "res://scripts/characters/lab/quaternius_equipment_lab.gd"

const OUTFIT_ITEM_ID := "lab.item.outfit.peasant_male.001"
const OUTFIT_PROFILE_ID := "equipment.outfit.peasant_male.prototype"
const OUTFIT_PRESENTATION_ID := "wearable.outfit.peasant_male"
const OUTFIT_SCENE_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"
const BODY_REPLACEMENT_REGIONS := [
	"body.region.torso",
	"body.region.arms",
	"body.region.legs",
	"body.region.feet",
]

var outfit_available := false
var outfit_last_result: Dictionary = {}
var body_suppression_available := false
var body_suppression_mode := ""
var head_clip_local_y := 0.0


func _ready() -> void:
	print("CH7.8 garment lab runtime: phase=super_ready_begin")
	super._ready()
	print("CH7.8 garment lab runtime: phase=super_ready_end")
	_setup_skinned_outfit()
	print(
		"CH7.8 garment lab runtime: phase=outfit_setup_end available=%s suppression=%s mode=%s clip_y=%.4f"
		% [outfit_available, body_suppression_available, body_suppression_mode, head_clip_local_y]
	)
	_refresh_status()
	print("CH7.8 garment lab runtime: phase=ready_end")


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		toggle_outfit()


func toggle_outfit() -> Dictionary:
	if not outfit_available:
		return _outfit_failure("OUTFIT_ASSET_NOT_READY")
	return _set_item_equipped(
		OUTFIT_ITEM_ID,
		OUTFIT_PROFILE_ID,
		not equipment_source.has_item(OUTFIT_ITEM_ID)
	)


func set_outfit_equipped(enabled: bool) -> Dictionary:
	if not outfit_available:
		return _outfit_failure("OUTFIT_ASSET_NOT_READY")
	return _set_item_equipped(OUTFIT_ITEM_ID, OUTFIT_PROFILE_ID, enabled)


func _setup_skinned_outfit() -> void:
	print("CH7.8 garment lab runtime: phase=outfit_setup_begin")
	outfit_available = false
	body_suppression_available = false
	body_suppression_mode = ""
	head_clip_local_y = 0.0
	if equipment_source == null or wearable_catalog == null or equipment_rig_adapter == null:
		outfit_last_result = _outfit_failure("RIGID_EQUIPMENT_BASE_NOT_READY")
		return
	print("CH7.8 garment lab runtime: phase=resource_exists_check")
	if not ResourceLoader.exists(OUTFIT_SCENE_PATH):
		outfit_last_result = _outfit_failure("OUTFIT_RESOURCE_MISSING", {"path": OUTFIT_SCENE_PATH})
		return

	var profile := EquipmentDomain.Profile.new(
		OUTFIT_PROFILE_ID,
		OUTFIT_PRESENTATION_ID,
		"body.root",
		["body.torso.outer", "body.arms.outer", "body.legs.outer", "body.feet"],
		[],
		[],
		["equipment.clothing"]
	)
	outfit_last_result = equipment_source.register_profile(profile)
	if not bool(outfit_last_result.get("success", false)):
		push_error("CH7.8 outfit profile registration failed: %s" % JSON.stringify(outfit_last_result))
		return

	print("CH7.8 garment lab runtime: phase=resource_load_begin")
	var loaded = load(OUTFIT_SCENE_PATH)
	print("CH7.8 garment lab runtime: phase=resource_load_end")
	if not loaded is PackedScene:
		outfit_last_result = _outfit_failure("OUTFIT_RESOURCE_NOT_PACKED_SCENE", {"path": OUTFIT_SCENE_PATH})
		push_error("CH7.8 outfit scene failed to load: %s" % OUTFIT_SCENE_PATH)
		return

	print("CH7.8 garment lab runtime: phase=body_suppression_probe_begin")
	var suppression_targets: Array[Dictionary] = equipment_rig_adapter.resolve_body_region_suppression_targets(
		avatar,
		String(BODY_REPLACEMENT_REGIONS[0])
	)
	if suppression_targets.is_empty():
		var failed_report: Dictionary = equipment_rig_adapter.create_report()
		outfit_last_result = _outfit_failure("BODY_SUPPRESSION_UNAVAILABLE", failed_report)
		push_error("CH7.8 fused-body suppression is unavailable: %s" % JSON.stringify(failed_report))
		return
	var suppression_target: Dictionary = suppression_targets[0]
	body_suppression_mode = String(suppression_target.get("mode", ""))
	var suppression_debug: Dictionary = suppression_target.get("debug", {})
	head_clip_local_y = float(suppression_debug.get("clip_local_y", 0.0))
	body_suppression_available = true
	print(
		"CH7.8 garment lab runtime: phase=body_suppression_probe_end mode=%s clip_y=%.4f mesh=%s"
		% [body_suppression_mode, head_clip_local_y, String(suppression_debug.get("mesh_name", ""))]
	)

	var hidden_regions: Array = BODY_REPLACEMENT_REGIONS.duplicate()
	outfit_last_result = wearable_catalog.register_scene(
		OUTFIT_PRESENTATION_ID,
		equipment_rig_adapter.rig_profile_id,
		WearableCatalog.STRATEGY_SKINNED_GARMENT,
		loaded as PackedScene,
		hidden_regions,
		Transform3D.IDENTITY,
		null,
		Transform3D.IDENTITY
	)
	if not bool(outfit_last_result.get("success", false)):
		push_error("CH7.8 outfit presentation registration failed: %s" % JSON.stringify(outfit_last_result))
		return

	outfit_available = true
	outfit_last_result = {
		"success": true,
		"code": EquipmentDomain.RESULT_OK,
		"details": {
			"path": OUTFIT_SCENE_PATH,
			"strategy": WearableCatalog.STRATEGY_SKINNED_GARMENT,
			"body_suppression_available": body_suppression_available,
			"body_suppression_mode": body_suppression_mode,
			"head_clip_local_y": head_clip_local_y,
			"hide_body_regions": hidden_regions,
		}
	}


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var state := "UNAVAILABLE"
	if outfit_available and equipment_source != null:
		state = "ON" if equipment_source.has_item(OUTFIT_ITEM_ID) else "OFF"
	var suppression_state := "READY" if body_suppression_available else "UNAVAILABLE"
	status_label.text += (
		"\n\nCH7.8 — Skinned Garment\n"
		+ ("O — Peasant Male outfit | state: %s\n" % state)
		+ ("strategy: SKINNED_GARMENT | fused-body suppression: %s\n" % suppression_state)
		+ ("mode: %s | head clip Y: %.3f m" % [body_suppression_mode, head_clip_local_y])
	)


func _outfit_failure(code: String, details: Dictionary = {}) -> Dictionary:
	outfit_last_result = {"success": false, "code": code, "details": details.duplicate(true)}
	return outfit_last_result
