class_name QuaterniusSkinnedGarmentLab
extends "res://scripts/characters/lab/quaternius_equipment_lab.gd"

const EquipmentDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const WearableCatalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")

const OUTFIT_ITEM_ID := "lab.item.outfit.peasant_male.001"
const OUTFIT_PROFILE_ID := "equipment.outfit.peasant_male.prototype"
const OUTFIT_PRESENTATION_ID := "wearable.outfit.peasant_male"
const OUTFIT_SCENE_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"

var outfit_available := false
var outfit_last_result: Dictionary = {}


func _ready() -> void:
	super._ready()
	_setup_skinned_outfit()
	_refresh_status()


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
	outfit_available = false
	if equipment_source == null or wearable_catalog == null or equipment_rig_adapter == null:
		outfit_last_result = _outfit_failure("RIGID_EQUIPMENT_BASE_NOT_READY")
		return
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

	var loaded = load(OUTFIT_SCENE_PATH)
	if not loaded is PackedScene:
		outfit_last_result = _outfit_failure("OUTFIT_RESOURCE_NOT_PACKED_SCENE", {"path": OUTFIT_SCENE_PATH})
		push_error("CH7.8 outfit scene failed to load: %s" % OUTFIT_SCENE_PATH)
		return

	outfit_last_result = wearable_catalog.register_scene(
		OUTFIT_PRESENTATION_ID,
		equipment_rig_adapter.rig_profile_id,
		WearableCatalog.STRATEGY_SKINNED_GARMENT,
		loaded as PackedScene,
		[],
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
		}
	}


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var state := "UNAVAILABLE"
	if outfit_available and equipment_source != null:
		state = "ON" if equipment_source.has_item(OUTFIT_ITEM_ID) else "OFF"
	status_label.text += (
		"\n\nCH7.8 — Skinned Garment\n"
		+ "O — Peasant Male outfit | state: %s\n"
		+ "strategy: SKINNED_GARMENT | body hiding: not yet enabled"
		% state
	)


func _outfit_failure(code: String, details: Dictionary = {}) -> Dictionary:
	outfit_last_result = {"success": false, "code": code, "details": details.duplicate(true)}
	return outfit_last_result
