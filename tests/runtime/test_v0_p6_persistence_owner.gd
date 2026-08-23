extends SceneTree

## P6.7 L0: single persistence owner — save/load round-trip, atomic write
## (tmp cleaned up), file_exists, load from nonexistent -> error, tamper and
## garbage rejection, checksum match after round-trip.

const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const OwnerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")

const BASE_DIR := "user://p6_persistence_owner_l0"

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.7-persistence-owner-l0][FAIL] %s" % message)


func _build_state() -> RefCounted:
	var state = StateScript.new()
	state.set_world_seed(777)
	state.apply_delta({"op": "place_block", "pos": [2, 3, 5], "block_type": "stone"})
	state.apply_delta({"op": "place_block", "pos": [-1, 0, 0], "block_type": "glass"})
	state.apply_delta({"op": "container_create", "container_id": "container/shared"})
	state.apply_delta({"op": "container_add_item", "container_id": "container/shared", "item": "item/torch"})
	state.apply_delta({"op": "player_move", "player_id": "player/alpha", "pos": [4, 1, -9], "rot": 2.0})
	state.apply_delta({"op": "set_tick", "value": 42})
	return state


func _init() -> void:
	var owner = OwnerScript.new()
	var file_path := BASE_DIR + "/outpost_state.json"
	var tmp_path := file_path + ".tmp"
	_cleanup()
	_assert(not owner.file_exists(file_path), "file_exists true before any save")

	# --- save -> load round-trip with checksum match ---
	var state = _build_state()
	var original_checksum: String = state.compute_checksum()
	_assert(owner.save(state, file_path), "save failed: %s" % owner.get_report()["last_error_code"])
	_assert(owner.file_exists(file_path), "file_exists false after save")
	var loaded: Dictionary = owner.load(file_path)
	if not bool(loaded.get("success", false)):
		_assert(false, "load failed: %s" % owner.get_report()["last_error_code"])
	else:
		var restored = loaded["details"]["state"]
		_assert(restored.compute_checksum() == original_checksum, "checksum mismatch after round-trip")
		_assert(restored.serialize().hash() == state.serialize().hash(), "state diverged after round-trip")
		_assert(String(loaded["details"]["checksum"]) == original_checksum, "envelope checksum mismatch")
		_assert(String(loaded["details"]["domain_id"]) == "p6-domain/outpost-world-state", "domain id mismatch")
		_assert(String(loaded["details"]["persistence_owner"]) == "p6-owner/directory-one-writer", "owner id mismatch")

	# --- atomic write: no tmp file remains; stale tmp is replaced ---
	_assert(not owner.file_exists(tmp_path), "tmp file leaked after save")
	var stale := FileAccess.open(tmp_path, FileAccess.WRITE)
	stale.store_string("stale-crash-leftover")
	stale.close()
	_assert(owner.save(state, file_path), "save over stale tmp failed")
	_assert(not owner.file_exists(tmp_path), "stale tmp not cleaned by save")
	var reread: Dictionary = owner.load(file_path)
	_assert(bool(reread.get("success", false)), "load after stale-tmp save failed")

	# --- save into a nested nonexistent directory ---
	var nested_path := BASE_DIR + "/nested/deeper/outpost_state.json"
	_assert(owner.save(state, nested_path), "nested-dir save failed")
	_assert(owner.file_exists(nested_path), "nested save file missing")

	# --- load from nonexistent -> error ---
	var missing: Dictionary = owner.load(BASE_DIR + "/does_not_exist.json")
	_assert(not bool(missing.get("success", false)) and String(missing["error_code"]) == "FILE_NOT_FOUND", "nonexistent load not FILE_NOT_FOUND")

	# --- garbage file -> parse failure ---
	var garbage_path := BASE_DIR + "/garbage.json"
	var garbage := FileAccess.open(garbage_path, FileAccess.WRITE)
	garbage.store_string("{{{ not json at all")
	garbage.close()
	var garbage_load: Dictionary = owner.load(garbage_path)
	_assert(not bool(garbage_load.get("success", false)) and String(garbage_load["error_code"]) == "PARSE_FAILED", "garbage load not rejected")

	# --- tampered state payload -> checksum mismatch (fail-closed) ---
	var tamper_path := BASE_DIR + "/tampered.json"
	var envelope_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	_assert(typeof(envelope_value) == TYPE_DICTIONARY, "canonical envelope did not parse")
	var envelope: Dictionary = envelope_value
	var tampered_state: Dictionary = envelope["state"]
	tampered_state["blocks"]["9,9,9"] = "intruder_block"
	envelope["state"] = tampered_state
	var tamper_file := FileAccess.open(tamper_path, FileAccess.WRITE)
	tamper_file.store_string(JSON.stringify(envelope))
	tamper_file.close()
	var tampered: Dictionary = owner.load(tamper_path)
	_assert(not bool(tampered.get("success", false)) and String(tampered["error_code"]) == "CHECKSUM_MISMATCH", "tampered state accepted")

	# --- wrong persistence owner in envelope -> rejected ---
	var wrong_owner_path := BASE_DIR + "/wrong_owner.json"
	envelope["state"] = state.serialize()
	envelope["persistence_owner"] = "someone-else/rogue-writer"
	var wrong_file := FileAccess.open(wrong_owner_path, FileAccess.WRITE)
	wrong_file.store_string(JSON.stringify(envelope))
	wrong_file.close()
	var wrong: Dictionary = owner.load(wrong_owner_path)
	_assert(not bool(wrong.get("success", false)) and String(wrong["error_code"]) == "WRONG_PERSISTENCE_OWNER", "rogue owner envelope accepted")

	# --- unknown domain in envelope -> rejected ---
	var wrong_domain_path := BASE_DIR + "/wrong_domain.json"
	envelope["persistence_owner"] = "p6-owner/directory-one-writer"
	envelope["domain_id"] = "p6-domain/not-declared"
	var wrong_domain_file := FileAccess.open(wrong_domain_path, FileAccess.WRITE)
	wrong_domain_file.store_string(JSON.stringify(envelope))
	wrong_domain_file.close()
	var wrong_domain: Dictionary = owner.load(wrong_domain_path)
	_assert(not bool(wrong_domain.get("success", false)) and String(wrong_domain["error_code"]) == "UNDECLARED_DOMAIN", "undeclared domain envelope accepted")

	# --- invalid save inputs rejected ---
	_assert(not owner.save(null, file_path), "null state accepted")
	_assert(not owner.save(state, ""), "empty path accepted")

	var report: Dictionary = owner.get_report()
	_assert(int(report["saves"]) >= 3, "save counter wrong")
	_assert(int(report["loads"]) >= 2, "load counter wrong")
	_assert(int(report["save_failures"]) >= 2, "save failure counter wrong")
	_assert(int(report["load_failures"]) >= 4, "load failure counter wrong")

	_cleanup()

	if failures.is_empty():
		print("[p6.7-persistence-owner-l0] all %d assertions passed" % assertions)
		print("[p6.7-persistence-owner-l0][stage] PERSISTENCE_OWNER_PASS")
		quit(0)
	else:
		print("[p6.7-persistence-owner-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)


func _cleanup() -> void:
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))


func _dir_recursive_delete(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_dir_recursive_delete(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
