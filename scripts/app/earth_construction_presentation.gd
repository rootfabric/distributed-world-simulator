extends Node3D

# Derived C22/C24 presentation only. Canonical Construction state remains server-owned.
# Spatial authority also stays outside this adapter: Earth runtime supplies a derived
# floating-origin transform from a stable Earth-fixed anchor.
const ControllerScript = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")
const RuntimeRequestScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const CompileRequestScript = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const InterestRequestScript = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")

const MVP_OUTPOST_CONSTRUCT_ID := "construct/mvp/earth-outpost"
const MVP_AUTHORITY_EPOCH := 1

var _controller
var _observer_id := "client/mvp/earth"
var _interest_observer_id := "observer/mvp/earth"
var _last_construct_id := ""
var _last_checksum := ""
var _last_detail_mode := ""
var _authoritative_bundle: Dictionary = {}
var _derived_render_transform := Transform3D.IDENTITY
var _render_transform_updates := 0
var _projection_updates := 0
var _projection_failures := 0


func setup(observer_id: String) -> Dictionary:
	if not observer_id.begins_with("client/"):
		return _failure("INVALID_EARTH_CONSTRUCTION_OBSERVER")
	_observer_id = observer_id
	_interest_observer_id = "observer/%s" % observer_id.trim_prefix("client/")
	_controller = ControllerScript.new()
	_controller.name = "C22C24ConstructionPresentation"
	add_child(_controller)
	return _success()


func set_derived_render_transform(value: Transform3D) -> void:
	_derived_render_transform = Transform3D(
		value.basis.orthonormalized(),
		value.origin
	)
	_render_transform_updates += 1
	_update_runtime_transform()


func apply_authoritative_projection(compile_request: Dictionary, interest: Dictionary) -> Dictionary:
	if _controller == null:
		return _failure("EARTH_CONSTRUCTION_PRESENTATION_NOT_READY")
	var compiled: Dictionary = _controller.compile_construct(compile_request)
	if not bool(compiled.get("success", false)):
		_projection_failures += 1
		return compiled
	var requested_interest := interest.duplicate(true)
	var presented: Dictionary = _controller.present(_observer_id, requested_interest)
	if not bool(presented.get("success", false)):
		_projection_failures += 1
		return presented
	var packet: Dictionary = presented["packet"]
	_last_construct_id = String(packet.get("construct_id", ""))
	_last_checksum = String(packet.get("source_checksum", ""))
	_last_detail_mode = String(packet.get("detail_mode", ""))
	_projection_updates += 1
	_update_runtime_transform()
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
	var snapshot := _find_mvp_outpost_snapshot(_authoritative_bundle)
	if snapshot.is_empty():
		return _success({
			"server_generation": int(_authoritative_bundle.get("server_generation", 0)),
			"checksum": String(_authoritative_bundle.get("checksum", "")),
			"outpost_present": false,
		})

	var runtime_request := RuntimeRequestScript.create(
		snapshot,
		Array(_authoritative_bundle.get("items", [])).duplicate(true),
		{},
		{},
		_world_origin_array(),
		_world_rotation_array(),
		1,
		1
	)
	var compile_request := CompileRequestScript.create(
		runtime_request,
		MVP_AUTHORITY_EPOCH,
		CompileRequestScript.READ_ONLY,
		"server/mvp/c22-client-proxy",
		5.0,
		80.0,
		250.0,
		1000.0,
		[],
		[]
	)
	var interest := InterestRequestScript.create(
		_interest_observer_id,
		MVP_OUTPOST_CONSTRUCT_ID,
		MVP_AUTHORITY_EPOCH,
		12.0,
		[0.0, 1.5, 0.0],
		"",
		[],
		1048576,
		16,
		32
	)
	var projected := apply_authoritative_projection(compile_request, interest)
	if not bool(projected.get("success", false)):
		return projected
	var details: Dictionary = Dictionary(projected.get("details", {})).duplicate(true)
	details["server_generation"] = int(_authoritative_bundle.get("server_generation", 0))
	details["bundle_checksum"] = String(_authoritative_bundle.get("checksum", ""))
	details["outpost_present"] = true
	return _success(details)


func get_report() -> Dictionary:
	var rotation := Quaternion(_derived_render_transform.basis).normalized()
	return {
		"schema": "planet_simulator.earth_construction_presentation.v2",
		"observer_id": _observer_id,
		"construct_id": _last_construct_id,
		"source_checksum": _last_checksum,
		"detail_mode": _last_detail_mode,
		"authoritative_bundle_checksum": String(_authoritative_bundle.get("checksum", "")),
		"authoritative_bundle_generation": int(_authoritative_bundle.get("server_generation", -1)),
		"projection_updates": _projection_updates,
		"projection_failures": _projection_failures,
		"render_transform_updates": _render_transform_updates,
		"derived_render_origin": [
			_derived_render_transform.origin.x,
			_derived_render_transform.origin.y,
			_derived_render_transform.origin.z,
		],
		"derived_render_rotation_xyzw": [rotation.x, rotation.y, rotation.z, rotation.w],
		"spatial_authority": "EXTERNAL_EARTH_FIXED_ANCHOR",
		"direct_authority_references": 0,
	}


func _find_mvp_outpost_snapshot(bundle: Dictionary) -> Dictionary:
	for value in bundle.get("constructs", []):
		if value is Dictionary and String(value.get("construct_id", "")) == MVP_OUTPOST_CONSTRUCT_ID:
			return Dictionary(value).duplicate(true)
	return {}


func _world_origin_array() -> Array:
	var value: Vector3 = _derived_render_transform.origin
	return [value.x, value.y, value.z]


func _world_rotation_array() -> Array:
	var value := Quaternion(_derived_render_transform.basis).normalized()
	return [value.x, value.y, value.z, value.w]


func _update_runtime_transform() -> void:
	if _controller == null or _last_construct_id.is_empty():
		return
	var runtime = _controller.get_runtime(_observer_id, _last_construct_id)
	if runtime == null or not is_instance_valid(runtime):
		return
	runtime.position = _derived_render_transform.origin
	runtime.quaternion = Quaternion(_derived_render_transform.basis).normalized()


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}
