extends Node3D

# Derived C22/C24 presentation only. Canonical Construction state remains server-owned.
const ControllerScript = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")

var _controller
var _observer_id := "client/mvp/earth"
var _last_construct_id := ""
var _last_checksum := ""
var _last_detail_mode := ""
var _authoritative_bundle: Dictionary = {}


func setup(observer_id: String) -> Dictionary:
	if not observer_id.begins_with("client/"):
		return _failure("INVALID_EARTH_CONSTRUCTION_OBSERVER")
	_observer_id = observer_id
	_controller = ControllerScript.new()
	_controller.name = "C22C24ConstructionPresentation"
	add_child(_controller)
	return _success()


func apply_authoritative_projection(compile_request: Dictionary, interest: Dictionary) -> Dictionary:
	if _controller == null:
		return _failure("EARTH_CONSTRUCTION_PRESENTATION_NOT_READY")
	var compiled: Dictionary = _controller.compile_construct(compile_request)
	if not bool(compiled.get("success", false)):
		return compiled
	var requested_interest := interest.duplicate(true)
	var presented: Dictionary = _controller.present(_observer_id, requested_interest)
	if not bool(presented.get("success", false)):
		return presented
	var packet: Dictionary = presented["packet"]
	_last_construct_id = String(packet.get("construct_id", ""))
	_last_checksum = String(packet.get("source_checksum", ""))
	_last_detail_mode = String(packet.get("detail_mode", ""))
	return _success({
		"construct_id": _last_construct_id,
		"source_checksum": _last_checksum,
		"detail_mode": _last_detail_mode,
		"proxy_mesh_count": int(presented["runtime"].get_proxy_mesh_count()),
		"collision_proxy_count": int(presented["runtime"].get_collision_proxy_count()),
	})


func apply_authoritative_bundle(bundle: Dictionary) -> Dictionary:
	var checked: Dictionary = BundleScript.validate(bundle)
	if not bool(checked.get("success", false)):
		return checked
	_authoritative_bundle = bundle.duplicate(true)
	return _success({
		"server_generation": int(_authoritative_bundle.get("server_generation", 0)),
		"checksum": String(_authoritative_bundle.get("checksum", "")),
	})


func get_report() -> Dictionary:
	return {
		"schema": "planet_simulator.earth_construction_presentation.v1",
		"observer_id": _observer_id,
		"construct_id": _last_construct_id,
		"source_checksum": _last_checksum,
		"detail_mode": _last_detail_mode,
		"authoritative_bundle_checksum": String(_authoritative_bundle.get("checksum", "")),
		"authoritative_bundle_generation": int(_authoritative_bundle.get("server_generation", -1)),
		"direct_authority_references": 0,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
