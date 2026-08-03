extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RequestScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const ConstructDescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_descriptor.gd")
const PartDescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_part_descriptor.gd")
const OpeningDescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_opening_descriptor.gd")

static func compile(request: Dictionary) -> Dictionary:
	var checked := RequestScript.validate(request)
	if not bool(checked.get("success", false)): return checked
	var snapshot: Dictionary = request["construct_snapshot"]
	var projections := _projection_map(request["item_projections"])
	if not bool(projections.get("success", false)): return projections
	var part_descriptors: Array = []
	var total_mass := 0.0
	var visible_count := 0
	var collision_count := 0
	for part in snapshot["parts"]:
		var compiled := _compile_part(part, projections["items"])
		if not bool(compiled.get("success", false)): return compiled
		var descriptor: Dictionary = compiled["descriptor"]
		part_descriptors.append(descriptor)
		if String(descriptor["condition"]) != "DESTROYED": total_mass += float(descriptor["mass_kg"])
		if bool(descriptor["visible"]): visible_count += 1
		if bool(descriptor["collision_enabled"]): collision_count += 1
	var body_kind := "STATIC"
	var frozen := true
	var mobility_state := ""
	var mobile_profile: Dictionary = request["mobile_profile"]
	if not mobile_profile.is_empty():
		body_kind = "RIGID"
		mobility_state = String(mobile_profile["mobility_state"])
		frozen = mobility_state == "IMMOBILE" or String(snapshot["build_state"]) in ["PLANNED", "PARTIAL", "DECONSTRUCTION"]
	var opening_descriptors: Array = []
	var spatial_profile: Dictionary = request["spatial_profile"]
	if not spatial_profile.is_empty():
		for opening in spatial_profile["opening_states"]:
			var status := String(opening["status"])
			var angle := PI * 0.5 if status == "OPEN" and String(opening["opening_kind"]) == "DOOR" else 0.0
			var collision_enabled := status not in ["BREACHED", "INACTIVE"]
			var descriptor := OpeningDescriptorScript.create(String(opening["opening_id"]), String(opening["closure_part_id"]), status, angle, collision_enabled, String(opening["checksum"]))
			checked = OpeningDescriptorScript.validate(descriptor); if not bool(checked.get("success", false)): return checked
			opening_descriptors.append(descriptor)
	if total_mass <= 0.0: total_mass = 0.001
	var descriptor := ConstructDescriptorScript.create(snapshot, body_kind, frozen, request["world_origin_m"], request["world_rotation_quaternion"], int(request["collision_layer"]), int(request["collision_mask"]), total_mass, mobility_state, part_descriptors, opening_descriptors, {
		"request_checksum": String(request["checksum"]),
		"part_count": part_descriptors.size(),
		"visible_part_count": visible_count,
		"collision_part_count": collision_count,
		"opening_count": opening_descriptors.size(),
		"projection_compiler": "construction-runtime-projection-compiler",
		"projection_compiler_version": 1,
	})
	checked = ConstructDescriptorScript.validate(descriptor)
	return _success({"descriptor": descriptor}) if bool(checked.get("success", false)) else checked

static func _projection_map(projections: Array) -> Dictionary:
	var items := {}
	for projection in projections:
		var item_id := String(projection["item_instance_id"])
		if items.has(item_id): return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_ITEM_PROJECTION")
		items[item_id] = Dictionary(projection).duplicate(true)
	return _success({"items": items})

static func _compile_part(part: Dictionary, projections: Dictionary) -> Dictionary:
	var metadata: Dictionary = Dictionary(part["metadata"]).duplicate(true)
	var item_id := String(part["item_instance_id"])
	var projection: Dictionary = Dictionary(projections.get(item_id, {}))
	var instance: Dictionary = {}
	if not projection.is_empty():
		var components = projection.get("components", {})
		if typeof(components) == TYPE_DICTIONARY and typeof(Dictionary(components).get("parametric_member", {})) == TYPE_DICTIONARY:
			instance = Dictionary(components["parametric_member"]).duplicate(true)
	var geometry: Dictionary = Dictionary(metadata.get("geometry", {})).duplicate(true)
	if geometry.is_empty() and not instance.is_empty(): geometry = Dictionary(instance.get("geometry", {})).duplicate(true)
	if not instance.is_empty() and metadata.has("parametric_member_checksum") and String(metadata["parametric_member_checksum"]) != String(instance.get("checksum", "")):
		return _failure("CONSTRUCTION_RUNTIME_PARAMETRIC_MEMBER_CHECKSUM_MISMATCH")
	var local_state: Dictionary = Dictionary(metadata.get("local_geometry_edit_state", {})).duplicate(true)
	if local_state.is_empty() and not instance.is_empty():
		var provenance = instance.get("provenance", {})
		if typeof(provenance) == TYPE_DICTIONARY and Dictionary(provenance).has("local_geometry_edit_state") and typeof(Dictionary(provenance).get("local_geometry_edit_state")) == TYPE_DICTIONARY:
			local_state = Dictionary(provenance["local_geometry_edit_state"]).duplicate(true)
	var path_points: Array = []
	if not local_state.is_empty() and typeof(local_state.get("control_points")) == TYPE_ARRAY:
		for point in local_state["control_points"]:
			if typeof(point) == TYPE_DICTIONARY and typeof(point.get("position_m")) == TYPE_ARRAY: path_points.append(Array(point["position_m"]).duplicate(true))
	var part_kind := String(part["part_kind"])
	var member_kind := String(instance.get("member_kind", part_kind))
	var geometry_kind := "BOX"
	if path_points.size() >= 2:
		geometry_kind = "PATH_BOXES"
	elif member_kind in ["PIPE", "CABLE"] or part_kind == "WHEEL":
		geometry_kind = "CYLINDER"
	var dimensions := _dimensions(geometry, member_kind, part_kind, String(part["role"]), geometry_kind)
	var condition := String(metadata.get("condition", "INTACT"))
	if not PartDescriptorScript.CONDITIONS.has(condition): return _failure("INVALID_CONSTRUCTION_RUNTIME_SOURCE_PART_CONDITION")
	var visible := condition != "DESTROYED"
	var collision_enabled := visible and String(part["role"]) not in ["sensor", "utility"]
	if metadata.has("presentation_collision_enabled"):
		if typeof(metadata["presentation_collision_enabled"]) != TYPE_BOOL: return _failure("INVALID_CONSTRUCTION_RUNTIME_COLLISION_OVERRIDE")
		collision_enabled = visible and bool(metadata["presentation_collision_enabled"])
	var rotation: Array = Array(metadata.get("local_rotation_quaternion", [0.0, 0.0, 0.0, 1.0])).duplicate(true)
	var source_payload := {
		"part": part,
		"parametric_checksum": String(instance.get("checksum", "")),
		"geometry": geometry,
		"local_geometry_state": local_state,
	}
	var source_checksum := UtilsScript.payload_hash(source_payload)
	var descriptor := PartDescriptorScript.create(String(part["part_id"]), item_id, part_kind, String(part["role"]), geometry_kind, dimensions, path_points if geometry_kind == "PATH_BOXES" else [], Array(part["local_position_m"]).duplicate(true), rotation, float(part["mass_kg"]), condition, visible, collision_enabled, source_checksum)
	var checked := PartDescriptorScript.validate(descriptor)
	return _success({"descriptor": descriptor}) if bool(checked.get("success", false)) else checked

static func _dimensions(geometry: Dictionary, member_kind: String, part_kind: String, role: String, geometry_kind: String) -> Array:
	var bounds = geometry.get("bounding_box_m", [])
	if typeof(bounds) == TYPE_ARRAY and Array(bounds).size() == 3:
		var result: Array = []
		for raw in bounds: result.append(maxf(absf(float(raw)), 0.02))
		if geometry_kind == "PATH_BOXES":
			var thickness_y := maxf(float(geometry.get("height_m", geometry.get("diameter_m", geometry.get("outer_diameter_m", result[1])))), 0.02)
			var thickness_z := maxf(float(geometry.get("width_m", geometry.get("diameter_m", geometry.get("outer_diameter_m", result[2])))), 0.02)
			return [0.02, thickness_y, thickness_z]
		return result
	if member_kind == "PIPE": return [maxf(float(geometry.get("length_m", 1.0)), 0.02), maxf(float(geometry.get("outer_diameter_m", 0.1)), 0.02), maxf(float(geometry.get("outer_diameter_m", 0.1)), 0.02)]
	if member_kind == "CABLE": return [maxf(float(geometry.get("length_m", 1.0)), 0.02), maxf(float(geometry.get("diameter_m", 0.02)), 0.02), maxf(float(geometry.get("diameter_m", 0.02)), 0.02)]
	match part_kind:
		"WHEEL": return [0.22, 0.55, 0.55]
		"WALL_PANEL": return [0.18, 2.5, 4.0]
		"ROOF_PANEL", "FLOOR_PANEL": return [4.0, 0.18, 4.0]
		"FOUNDATION": return [4.2, 0.6, 4.2]
		"DOOR_PANEL": return [1.0, 2.0, 0.08]
		"DOOR_FRAME": return [1.15, 2.15, 0.12]
		"WINDOW_PANEL", "WINDOW_FRAME": return [1.1, 1.0, 0.08]
		"FRAME": return [1.6, 0.45, 1.4]
		"POWER_STORAGE": return [0.7, 0.35, 0.45]
		"CONTROL_UNIT", "POWER_PANEL", "DATA_ROUTER": return [0.35, 0.35, 0.25]
		"SENSOR_ARRAY": return [0.28, 0.28, 0.28]
		_:
			if role == "wall": return [0.18, 2.5, 4.0]
			return [0.5, 0.5, 0.5]

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
