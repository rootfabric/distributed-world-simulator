class_name QuaterniusSkinnedGarmentLab
extends "res://scripts/characters/lab/quaternius_equipment_lab.gd"

const OUTFIT_ITEM_ID := "lab.item.outfit.peasant_male.001"
const OUTFIT_PROFILE_ID := "equipment.outfit.peasant_male.prototype"
const OUTFIT_PRESENTATION_ID := "wearable.outfit.peasant_male"
const OUTFIT_SCENE_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"
const BASE_ASSET_ROOT := "res://assets/external/quaternius/base_characters"
const BODY_REPLACEMENT_REGIONS := [
	"body.region.torso",
	"body.region.arms",
	"body.region.legs",
	"body.region.feet",
]

var outfit_available := false
var outfit_last_result: Dictionary = {}
var body_replacement_available := false
var body_replacement_path := ""


func _ready() -> void:
	print("CH7.8 garment lab runtime: phase=super_ready_begin")
	super._ready()
	print("CH7.8 garment lab runtime: phase=super_ready_end")
	_setup_skinned_outfit()
	print(
		"CH7.8 garment lab runtime: phase=outfit_setup_end available=%s replacement=%s"
		% [outfit_available, body_replacement_available]
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
	body_replacement_available = false
	body_replacement_path = ""
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

	print("CH7.8 garment lab runtime: phase=head_variant_probe_begin")
	body_replacement_path = _find_compatible_head_scene()
	var replacement_scene: PackedScene = null
	if not body_replacement_path.is_empty():
		var loaded_replacement = load(body_replacement_path)
		if loaded_replacement is PackedScene:
			replacement_scene = loaded_replacement as PackedScene
			body_replacement_available = true
	print(
		"CH7.8 garment lab runtime: phase=head_variant_probe_end path=%s available=%s"
		% [body_replacement_path, body_replacement_available]
	)

	var hidden_regions: Array = []
	if body_replacement_available:
		hidden_regions = BODY_REPLACEMENT_REGIONS.duplicate()
	outfit_last_result = wearable_catalog.register_scene(
		OUTFIT_PRESENTATION_ID,
		equipment_rig_adapter.rig_profile_id,
		WearableCatalog.STRATEGY_SKINNED_GARMENT,
		loaded as PackedScene,
		hidden_regions,
		Transform3D.IDENTITY,
		replacement_scene,
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
			"body_replacement_available": body_replacement_available,
			"body_replacement_path": body_replacement_path,
			"hide_body_regions": hidden_regions,
		}
	}


func _find_compatible_head_scene() -> String:
	if avatar == null:
		return ""
	var avatar_report: Dictionary = avatar.create_report()
	var source_model_path := String(avatar_report.get("model_path", ""))
	if source_model_path.is_empty():
		return ""

	var source_name := source_model_path.get_file()
	var direct_name := source_name
	for full_body_token in ["_FullBody", "_Fullbody", "_fullbody"]:
		if direct_name.contains(String(full_body_token)):
			direct_name = direct_name.replace(String(full_body_token), "_Head")
			break
	if direct_name != source_name:
		var direct_path := source_model_path.get_base_dir().path_join(direct_name)
		if ResourceLoader.exists(direct_path):
			return direct_path

	var candidates: Array[String] = []
	_collect_scene_files(BASE_ASSET_ROOT, candidates)
	var best_path := ""
	var best_score := -100000
	for candidate_path in candidates:
		var score := _score_head_scene(candidate_path, source_model_path)
		if score > best_score:
			best_score = score
			best_path = candidate_path
	return best_path if best_score > 0 else ""


func _score_head_scene(candidate_path: String, source_model_path: String) -> int:
	var candidate_name := candidate_path.get_file().get_basename().to_lower()
	if not candidate_name.contains("head") or candidate_name.contains("fullbody"):
		return -100000

	var source_name := source_model_path.get_file().get_basename().to_lower()
	var source_prefix := source_name.replace("_fullbody", "")
	var score := 0
	if candidate_path.get_base_dir() == source_model_path.get_base_dir():
		score += 80
	if candidate_name == source_prefix + "_head":
		score += 500
	elif candidate_name.begins_with(source_prefix) and candidate_name.contains("head"):
		score += 300
	if candidate_name.contains("male") and not candidate_name.contains("female"):
		score += 80
	if candidate_name.contains("female"):
		score -= 500
	if candidate_name.ends_with("head") or candidate_name.contains("headonly"):
		score += 100
	if candidate_path.to_lower().ends_with(".gltf"):
		score += 20
	for token in source_prefix.split("_", false):
		if String(token).length() >= 4 and candidate_name.contains(String(token)):
			score += 30
	for unwanted in ["hair", "beard", "helmet", "outfit", "animation", "upperbody"]:
		if candidate_name.contains(String(unwanted)):
			score -= 150
	return score


func _collect_scene_files(root_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(root_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			_collect_scene_files(path, output)
		elif entry.to_lower().ends_with(".gltf") or entry.to_lower().ends_with(".glb"):
			output.append(path)
	directory.list_dir_end()


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var state := "UNAVAILABLE"
	if outfit_available and equipment_source != null:
		state = "ON" if equipment_source.has_item(OUTFIT_ITEM_ID) else "OFF"
	var replacement_state := "READY" if body_replacement_available else "FALLBACK_LAYERED"
	status_label.text += (
		"\n\nCH7.8 — Skinned Garment\n"
		+ ("O — Peasant Male outfit | state: %s\n" % state)
		+ ("strategy: SKINNED_GARMENT | body replacement: %s\n" % replacement_state)
		+ ("head: %s" % body_replacement_path.get_file())
	)


func _outfit_failure(code: String, details: Dictionary = {}) -> Dictionary:
	outfit_last_result = {"success": false, "code": code, "details": details.duplicate(true)}
	return outfit_last_result
