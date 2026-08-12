class_name FirstPersonHandAssetRegistry
extends RefCounted

const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const DEFAULT_PROFILE_DIR := "res://config/characters/hand-assets"

var profile_directory := DEFAULT_PROFILE_DIR
var _profiles_by_id: Dictionary = {}
var _profile_paths_by_id: Dictionary = {}
var _load_failures: Array[Dictionary] = []


func load_directory(directory_path: String = DEFAULT_PROFILE_DIR) -> Dictionary:
	profile_directory = directory_path.strip_edges()
	_profiles_by_id.clear()
	_profile_paths_by_id.clear()
	_load_failures.clear()
	var dir := DirAccess.open(profile_directory)
	if dir == null:
		return _failure("FPE_HAND_PROFILE_DIRECTORY_NOT_FOUND", {"directory": profile_directory})
	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.to_lower().ends_with(".json"):
			continue
		var path := "%s/%s" % [profile_directory.trim_suffix("/"), file_name]
		var loaded: Dictionary = ProfileType.load_from_path(path)
		if not bool(loaded.get("success", false)):
			_load_failures.append({
				"path": path,
				"error_code": String(loaded.get("error_code", "FPE_HAND_PROFILE_LOAD_FAILED")),
				"details": Dictionary(loaded.get("details", {})).duplicate(true),
			})
			continue
		var details := Dictionary(loaded.get("details", {}))
		var profile := Dictionary(details.get("profile", {})).duplicate(true)
		var profile_id := String(profile.get("profile_id", "")).strip_edges()
		if _profiles_by_id.has(profile_id):
			_load_failures.append({
				"path": path,
				"error_code": "FPE_HAND_PROFILE_DUPLICATE_ID",
				"details": {"profile_id": profile_id, "existing_path": _profile_paths_by_id.get(profile_id, "")},
			})
			continue
		_profiles_by_id[profile_id] = profile
		_profile_paths_by_id[profile_id] = path
	return _success(create_report())


func resolve(profile_ref: String) -> Dictionary:
	var ref := profile_ref.strip_edges()
	if ref.is_empty():
		return _failure("FPE_HAND_PROFILE_REF_REQUIRED")
	if ref.begins_with("res://"):
		return ProfileType.load_from_path(ref)
	if _profiles_by_id.is_empty():
		var load_result := load_directory(profile_directory)
		if not bool(load_result.get("success", false)):
			return load_result
	if not _profiles_by_id.has(ref):
		return _failure("FPE_HAND_PROFILE_ID_NOT_FOUND", {
			"profile_id": ref,
			"known_profile_ids": list_profile_ids(),
		})
	var profile := Dictionary(_profiles_by_id.get(ref, {})).duplicate(true)
	var path := String(_profile_paths_by_id.get(ref, ""))
	return _success({
		"profile": profile,
		"profile_path": path,
		"report": ProfileType.create_report(profile, path),
	})


func list_profile_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _profiles_by_id.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_hand_asset_registry.v1",
		"directory": profile_directory,
		"profile_count": _profiles_by_id.size(),
		"profile_ids": list_profile_ids(),
		"load_failure_count": _load_failures.size(),
		"load_failures": _load_failures.duplicate(true),
		"drop_in_profile_registration": true,
		"presentation_only": true,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
