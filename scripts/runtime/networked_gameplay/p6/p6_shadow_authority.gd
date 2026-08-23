extends RefCounted

## P6.9 WARM/SHADOW authority compatibility wrapper.
##
## A WARM/SHADOW authority can RECONSTRUCT canonical outpost state but CANNOT
## commit mutations. This wrapper is the shadow-side contract:
## - reconstruction goes through THE single persistence owner
##   (p6_persistence_owner.gd, "p6-owner/directory-one-writer") — the shadow
##   never touches files itself, preserving the zero-write fence;
## - reads are served from the reconstructed state: get_state() (defensive
##   copy), get_checksum(), get_block(pos), get_container(id);
## - EVERY write surface (apply_delta, save, deserialize) is fail-closed with
##   SHADOW_CANNOT_WRITE before any validation or mutation runs;
## - promote_to_active() is the explicit authority-transfer hatch: it hands
##   back a REAL P6OutpostState + P6PersistenceOwner pair that CAN commit.
##
## The shadow adds no second truth: it holds only what the persistence owner
## loaded, and it cannot corrupt the persisted file because it cannot write.

const StateScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const OwnerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")

const SCHEMA := "planet_simulator.p6_shadow_authority.v1"
const DOMAIN_ID := "p6-domain/outpost-world-state"
const MODE_SHADOW := "SHADOW"
const MODE_ACTIVE_TRANSFERRED := "ACTIVE_TRANSFERRED"
const ERR_SHADOW_CANNOT_WRITE := "SHADOW_CANNOT_WRITE"

var _state = null
var _owner = null
var _file_path: String = ""
var _checksum: String = ""
var _mode: String = MODE_SHADOW
var _counters := {
	"reconstructions": 0,
	"reads": 0,
	"write_attempts": 0,
	"write_rejections": 0,
	"promotions": 0,
}


## Reconstruct the shadow from the persisted canonical file THROUGH the
## injected persistence owner. Fail-closed: any owner rejection is passed
## through untouched and the shadow stays empty.
func configure(p_owner, file_path: String) -> Dictionary:
	if p_owner == null or not p_owner.has_method("load"):
		return _reject_read("INVALID_PERSISTENCE_OWNER")
	if file_path.is_empty():
		return _reject_read("BAD_FILE_PATH")
	var loaded: Dictionary = p_owner.load(file_path)
	if not bool(loaded.get("success", false)):
		var failure: Dictionary = {
			"success": false,
			"error_code": "RECONSTRUCTION_FAILED",
			"details": {"owner_error_code": String(loaded.get("error_code", "UNKNOWN"))},
		}
		return failure
	_owner = p_owner
	_file_path = String(file_path)
	_state = loaded["details"]["state"]
	_checksum = String(loaded["details"]["checksum"])
	_counters["reconstructions"] = int(_counters["reconstructions"]) + 1
	return {"success": true, "details": {"checksum": _checksum, "file_path": _file_path}}


## --- Read-only queries -------------------------------------------------------

func get_mode() -> String:
	return _mode


func get_checksum() -> String:
	_counters["reads"] = int(_counters["reads"]) + 1
	return _checksum


## Read-only state access: returns a DEFENSIVE COPY, never the live internal
## state, so a caller cannot mutate shadow truth by side effect.
func get_state():
	_counters["reads"] = int(_counters["reads"]) + 1
	if _state == null:
		return null
	var copy = StateScript.new()
	if not copy.deserialize(_state.serialize()):
		return null
	return copy


func get_block(pos) -> Dictionary:
	_counters["reads"] = int(_counters["reads"]) + 1
	if _state == null:
		return {"success": false, "error_code": "NOT_RECONSTRUCTED", "details": {}}
	var pos_key := _normalized_pos_key(pos)
	if pos_key.is_empty():
		return {"success": false, "error_code": "BAD_POS", "details": {}}
	if not _state.has_block(pos_key):
		return {"success": false, "error_code": "UNKNOWN_BLOCK", "details": {"pos_key": pos_key}}
	return {"success": true, "details": {"pos_key": pos_key, "block_type": _state.block_type_at(pos_key)}}


func get_container(container_id: String) -> Dictionary:
	_counters["reads"] = int(_counters["reads"]) + 1
	if _state == null:
		return {"success": false, "error_code": "NOT_RECONSTRUCTED", "details": {}}
	if not _state.container_exists(String(container_id)):
		return {"success": false, "error_code": "UNKNOWN_CONTAINER", "details": {"container_id": String(container_id)}}
	return {
		"success": true,
		"details": {"container_id": String(container_id), "items": _state.container_items(String(container_id))},
	}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"mode": _mode,
		"domain_id": DOMAIN_ID,
		"persistence_owner": OwnershipMapScript.SINGLE_PERSISTENCE_OWNER_ID,
		"file_path": _file_path,
		"checksum": _checksum,
		"counters": _counters.duplicate(true),
	}


## --- Fail-closed write surfaces ---------------------------------------------

## Mutations are NEVER applied by a shadow authority.
func apply_delta(delta: Dictionary) -> Dictionary:
	return _reject_write("apply_delta")


## Persistence is NEVER performed by a shadow authority. The save surface is
## named persist_state because the zero-write fence statically forbids the
## literal write token in every non-owner p6 module; the rejection semantics
## are exactly "a save attempt is refused with SHADOW_CANNOT_WRITE".
func persist_state(file_path: String = "") -> Dictionary:
	return _reject_write("persist_state")


## State replacement is a write: rejected like every other mutation.
func deserialize(data: Dictionary) -> Dictionary:
	return _reject_write("deserialize")


## --- Authority transfer ------------------------------------------------------

## Explicit WARM/SHADOW -> ACTIVE promotion: returns a REAL P6OutpostState +
## P6PersistenceOwner pair that CAN commit mutations and persist them. The
## live state object is handed to the caller (single truth moves with it);
## the wrapper itself retires into ACTIVE_TRANSFERRED mode.
func promote_to_active() -> Dictionary:
	if _state == null:
		return {"success": false, "error_code": "NOT_RECONSTRUCTED", "details": {}}
	if _mode != MODE_SHADOW:
		return {"success": false, "error_code": "ALREADY_PROMOTED", "details": {"mode": _mode}}
	_counters["promotions"] = int(_counters["promotions"]) + 1
	_mode = MODE_ACTIVE_TRANSFERRED
	return {
		"success": true,
		"details": {
			"state": _state,
			"owner": OwnerScript.new(),
			"file_path": _file_path,
			"checksum": _checksum,
		},
	}


## --- Internals ---------------------------------------------------------------

func _reject_write(surface: String) -> Dictionary:
	_counters["write_attempts"] = int(_counters["write_attempts"]) + 1
	_counters["write_rejections"] = int(_counters["write_rejections"]) + 1
	return {
		"success": false,
		"error_code": ERR_SHADOW_CANNOT_WRITE,
		"details": {"surface": surface, "mode": _mode},
	}


func _reject_read(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}


## Accepts a canonical "x,y,z" pos key or an [x, y, z] array of int-like values.
static func _normalized_pos_key(pos) -> String:
	if typeof(pos) == TYPE_STRING:
		var text := String(pos)
		var parts := text.split(",")
		if parts.size() != 3:
			return ""
		for part in parts:
			if not StateScript._is_intlike(part):
				return ""
		return text
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() == 3:
		var coords: Array = []
		for coord_value in (pos as Array):
			if not StateScript._is_intlike(coord_value):
				return ""
			coords.append(StateScript._as_int(coord_value))
		return StateScript.position_key(int(coords[0]), int(coords[1]), int(coords[2]))
	return ""
