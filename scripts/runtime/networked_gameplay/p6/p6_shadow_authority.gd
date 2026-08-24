extends RefCounted

## P6 R3 WARM/SHADOW read model.
##
## The shadow consumes an already reconstructed P6 read-only projection. It
## owns neither persistence nor authority transfer. Promotion is intentionally
## refused here: a real ACTIVE transition belongs to the canonical authority /
## Directory transfer protocol (post-P6 SM1), not to a P6 helper.

const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")

const SCHEMA := "planet_simulator.p6_shadow_authority.v2"
const MODE_SHADOW := "SHADOW"
const ERR_SHADOW_CANNOT_WRITE := "SHADOW_CANNOT_WRITE"
const ERR_PROMOTION_REQUIRES_CANONICAL_TRANSFER := "SHADOW_PROMOTION_REQUIRES_CANONICAL_AUTHORITY_TRANSFER"

var _projection = null
var _checksum: String = ""
var _counters := {
	"reconstructions": 0,
	"reads": 0,
	"write_attempts": 0,
	"write_rejections": 0,
	"promotion_rejections": 0,
}


func configure(projection) -> Dictionary:
	if projection == null or not projection.has_method("serialize") or not projection.has_method("compute_checksum"):
		return {"success": false, "error_code": "INVALID_CANONICAL_PROJECTION", "details": {}}
	var snapshot: Variant = projection.serialize()
	if not snapshot is Dictionary:
		return {"success": false, "error_code": "INVALID_CANONICAL_PROJECTION", "details": {}}
	var copy = ProjectionScript.new()
	if not copy.deserialize(Dictionary(snapshot)):
		return {"success": false, "error_code": "PROJECTION_RECONSTRUCTION_FAILED", "details": {}}
	_projection = copy
	_checksum = copy.compute_checksum()
	_counters["reconstructions"] += 1
	return {"success": true, "details": {"checksum": _checksum, "mode": MODE_SHADOW}}


func get_mode() -> String:
	return MODE_SHADOW


func get_checksum() -> String:
	_counters["reads"] += 1
	return _checksum


func get_projection():
	_counters["reads"] += 1
	if _projection == null:
		return null
	var copy = ProjectionScript.new()
	return copy if copy.deserialize(_projection.serialize()) else null


func get_source(source_name: String) -> Dictionary:
	_counters["reads"] += 1
	if _projection == null:
		return {}
	return _projection.get_source(source_name)


func apply_delta(_delta: Dictionary) -> Dictionary:
	return _reject_write("apply_delta")


func persist_state() -> Dictionary:
	return _reject_write("persist_state")


func deserialize(_data: Dictionary) -> Dictionary:
	return _reject_write("deserialize")


func promote_to_active() -> Dictionary:
	_counters["promotion_rejections"] += 1
	return {
		"success": false,
		"error_code": ERR_PROMOTION_REQUIRES_CANONICAL_TRANSFER,
		"details": {"mode": MODE_SHADOW},
	}


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"mode": MODE_SHADOW,
		"checksum": _checksum,
		"persistence_owner": "EXTERNAL",
		"promotion_owner": "CANONICAL_AUTHORITY_TRANSFER",
		"private_canonical_truth": false,
		"counters": _counters.duplicate(true),
	}


func _reject_write(surface: String) -> Dictionary:
	_counters["write_attempts"] += 1
	_counters["write_rejections"] += 1
	return {
		"success": false,
		"error_code": ERR_SHADOW_CANNOT_WRITE,
		"details": {"surface": surface, "mode": MODE_SHADOW},
	}
