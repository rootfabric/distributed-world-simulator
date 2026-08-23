extends SceneTree

## P6.9 L0: WARM/SHADOW authority compatibility.
##
## A WARM/SHADOW authority reconstructs canonical outpost state through the
## single persistence owner and serves READS, but every write attempt is
## rejected with SHADOW_CANNOT_WRITE, the persisted file stays untouched, and
## promote_to_active() hands back a REAL state+owner pair that CAN commit.

const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const OwnerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const ShadowScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")

const BASE_DIR := "user://p6_shadow_authority"
const CANONICAL_PATH := BASE_DIR + "/canonical_outpost.json"

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.9-shadow-authority][FAIL] %s" % message)


func _assert_write_rejected(result: Dictionary, surface: String) -> void:
	_assert(not bool(result.get("success", false)), "%s write unexpectedly succeeded" % surface)
	_assert(String(result.get("error_code", "")) == "SHADOW_CANNOT_WRITE", "%s wrong rejection code: %s" % [surface, String(result.get("error_code", ""))])


func _init() -> void:
	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))

	# --- active authority builds and persists shared work --------------------
	var active_state = StateScript.new()
	active_state.set_world_seed(909)
	var active_owner = OwnerScript.new()
	_assert(active_state.apply_delta({"op": "place_block", "pos": [1, 0, 1], "block_type": "stone"}), "active place 1 failed")
	_assert(active_state.apply_delta({"op": "place_block", "pos": [2, 0, 2], "block_type": "wood"}), "active place 2 failed")
	_assert(active_state.apply_delta({"op": "container_create", "container_id": "crate-1"}), "active container create failed")
	_assert(active_state.apply_delta({"op": "container_add_item", "container_id": "crate-1", "item": "axe"}), "active item add failed")
	_assert(active_state.apply_delta({"op": "player_move", "player_id": "player/zed", "pos": [7, 0, 7], "rot": 0.25}), "active move failed")
	var active_checksum: String = active_state.compute_checksum()
	_assert(active_owner.save(active_state, CANONICAL_PATH), "active save failed: %s" % active_owner.get_report()["last_error_code"])

	# --- shadow reconstructs through the persistence owner --------------------
	var shadow = ShadowScript.new()
	var shadow_owner = OwnerScript.new()
	var reconstruction: Dictionary = shadow.configure(shadow_owner, CANONICAL_PATH)
	_assert(bool(reconstruction.get("success", false)), "shadow reconstruction failed: %s" % JSON.stringify(reconstruction))
	_assert(String(shadow.get_mode()) == "SHADOW", "shadow mode wrong")
	_assert(shadow.get_checksum() == active_checksum, "shadow checksum != active checksum")

	# --- read queries ----------------------------------------------------------
	var state_copy = shadow.get_state()
	_assert(state_copy != null, "shadow get_state returned null")
	_assert(state_copy.compute_checksum() == active_checksum, "shadow state copy checksum mismatch")
	# defensive copy: mutating it must not move shadow truth
	_assert(state_copy.apply_delta({"op": "place_block", "pos": [9, 9, 9], "block_type": "sand"}), "copy mutate failed")
	_assert(shadow.get_checksum() == active_checksum, "copy mutation leaked into shadow")
	var block_hit: Dictionary = shadow.get_block("1,0,1")
	_assert(bool(block_hit.get("success", false)) and String(block_hit["details"]["block_type"]) == "stone", "shadow get_block hit wrong")
	var block_hit_array: Dictionary = shadow.get_block([2, 0, 2])
	_assert(bool(block_hit_array.get("success", false)) and String(block_hit_array["details"]["block_type"]) == "wood", "shadow get_block(array) wrong")
	var block_miss: Dictionary = shadow.get_block([5, 5, 5])
	_assert(not bool(block_miss.get("success", false)) and String(block_miss.get("error_code", "")) == "UNKNOWN_BLOCK", "shadow get_block miss wrong")
	var container_hit: Dictionary = shadow.get_container("crate-1")
	_assert(bool(container_hit.get("success", false)) and container_hit["details"]["items"] == ["axe"], "shadow get_container wrong")
	var container_miss: Dictionary = shadow.get_container("ghost-box")
	_assert(not bool(container_miss.get("success", false)) and String(container_miss.get("error_code", "")) == "UNKNOWN_CONTAINER", "shadow get_container miss wrong")

	# --- ALL write attempts rejected with SHADOW_CANNOT_WRITE ------------------
	_assert_write_rejected(shadow.apply_delta({"op": "place_block", "pos": [3, 0, 3], "block_type": "brick"}), "apply_delta(valid)")
	_assert_write_rejected(shadow.apply_delta({"op": "container_add_item", "container_id": "crate-1", "item": "torch"}), "apply_delta(container)")
	_assert_write_rejected(shadow.apply_delta({}), "apply_delta(empty)")
	_assert_write_rejected(shadow.persist_state(CANONICAL_PATH), "persist_state(path)")
	_assert_write_rejected(shadow.persist_state(), "persist_state()")
	_assert_write_rejected(shadow.deserialize(active_state.serialize()), "deserialize")
	_assert(shadow.get_checksum() == active_checksum, "shadow state moved after write attempts")
	_assert(shadow.get_block([3, 0, 3]).get("success", false) == false, "rejected delta mutated shadow truth")
	var report: Dictionary = shadow.get_report()
	_assert(int(report["counters"]["write_attempts"]) == 6 and int(report["counters"]["write_rejections"]) == 6, "shadow write counters wrong")

	# --- shadow cannot corrupt the persisted file ------------------------------
	var reread: Dictionary = shadow_owner.load(CANONICAL_PATH)
	_assert(bool(reread.get("success", false)), "persisted file unreadable after shadow writes")
	if bool(reread.get("success", false)):
		_assert(reread["details"]["state"].compute_checksum() == active_checksum, "persisted file corrupted by shadow")
		_assert(reread["details"]["state"].block_count() == 2, "persisted block count changed")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(CANONICAL_PATH + ".tmp")), "shadow left tmp file behind")

	# --- fail-closed reconstruction --------------------------------------------
	var broken_shadow = ShadowScript.new()
	var missing: Dictionary = broken_shadow.configure(OwnerScript.new(), BASE_DIR + "/missing.json")
	_assert(not bool(missing.get("success", false)) and String(missing["details"]["owner_error_code"]) == "FILE_NOT_FOUND", "missing-file reconstruction not fail-closed")
	var no_owner: Dictionary = ShadowScript.new().configure(null, CANONICAL_PATH)
	_assert(not bool(no_owner.get("success", false)) and String(no_owner.get("error_code", "")) == "INVALID_PERSISTENCE_OWNER", "null owner not rejected")

	# --- promotion: shadow -> ACTIVE pair that CAN commit -----------------------
	var promotion: Dictionary = shadow.promote_to_active()
	_assert(bool(promotion.get("success", false)), "promotion failed")
	_assert(String(shadow.get_mode()) == "ACTIVE_TRANSFERRED", "post-promotion mode wrong")
	var promoted_state = promotion["details"]["state"]
	var promoted_owner = promotion["details"]["owner"]
	_assert(promoted_state != null and promoted_state.has_method("apply_delta"), "promoted state not a real P6OutpostState")
	_assert(promoted_owner != null and promoted_owner.has_method("save") and promoted_owner.has_method("load"), "promoted owner not a real P6PersistenceOwner")
	# the active pair COMMITS: mutate, persist, verify durable
	_assert(promoted_state.apply_delta({"op": "place_block", "pos": [3, 0, 3], "block_type": "brick"}), "promoted commit failed")
	var promoted_checksum: String = promoted_state.compute_checksum()
	_assert(promoted_owner.save(promoted_state, CANONICAL_PATH), "promoted save failed: %s" % promoted_owner.get_report()["last_error_code"])
	var verify: Dictionary = OwnerScript.new().load(CANONICAL_PATH)
	_assert(bool(verify.get("success", false)), "post-promotion reload failed")
	if bool(verify.get("success", false)):
		_assert(verify["details"]["state"].compute_checksum() == promoted_checksum, "post-promotion durable checksum mismatch")
		_assert(verify["details"]["state"].block_count() == 3, "post-promotion block count wrong")
	_assert(promoted_checksum != active_checksum, "promotion did not enable change")
	# double promotion is rejected; shadow writes stay rejected after transfer
	_assert(not bool(shadow.promote_to_active().get("success", false)), "double promotion allowed")
	_assert_write_rejected(shadow.apply_delta({"op": "place_block", "pos": [4, 0, 4], "block_type": "glass"}), "post-promotion apply_delta")

	_dir_recursive_delete(ProjectSettings.globalize_path(BASE_DIR))

	if failures.is_empty():
		print("[p6.9-shadow-authority] all %d assertions passed" % assertions)
		print("[p6.9-shadow-authority][stage] SHADOW_AUTHORITY_PASS")
		quit(0)
	else:
		print("[p6.9-shadow-authority] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)


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
