extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Topology = preload("res://scripts/construction/proxies/construction_proxy_section_topology.gd")

static func extract(snapshot: Dictionary, topology: Dictionary) -> Dictionary:
	var section_by_part: Dictionary = topology["part_section_index"]
	var occupancy := {}
	var fallback: Array = []
	var visible_part_count := 0
	for part in snapshot["parts"]:
		var metadata: Dictionary = part["metadata"]
		if String(metadata.get("condition", "INTACT")) == "DESTROYED": continue
		visible_part_count += 1
		var part_id := String(part["part_id"])
		var material := String(metadata.get("proxy_material_key", part["role"]))
		var dimensions: Array = Topology.part_dimensions(part)
		var rotation: Array = Array(metadata.get("local_rotation_quaternion", [0.0, 0.0, 0.0, 1.0])).duplicate(true)
		if _is_unit_axis_box(part["local_position_m"], dimensions, rotation):
			var p: Array = part["local_position_m"]
			var key := _voxel_key(int(round(float(p[0]))), int(round(float(p[1]))), int(round(float(p[2]))))
			if occupancy.has(key): return C.failure("CONSTRUCTION_PROXY_DUPLICATE_VOXEL_OCCUPANCY", {"part_id": part_id})
			occupancy[key] = {"part_id": part_id, "section_id": String(section_by_part[part_id]), "material_key": material, "x": int(round(float(p[0]))), "y": int(round(float(p[1]))), "z": int(round(float(p[2])))}
		else:
			fallback.append({"part_id": part_id, "section_id": String(section_by_part[part_id]), "material_key": material, "position_m": part["local_position_m"].duplicate(true), "dimensions_m": dimensions})
	var faces: Array = []
	var directions := [
		{"axis": "X", "direction": -1, "delta": [-1, 0, 0]}, {"axis": "X", "direction": 1, "delta": [1, 0, 0]},
		{"axis": "Y", "direction": -1, "delta": [0, -1, 0]}, {"axis": "Y", "direction": 1, "delta": [0, 1, 0]},
		{"axis": "Z", "direction": -1, "delta": [0, 0, -1]}, {"axis": "Z", "direction": 1, "delta": [0, 0, 1]},
	]
	var voxel_keys: Array = occupancy.keys(); voxel_keys.sort()
	for key in voxel_keys:
		var voxel: Dictionary = occupancy[key]
		for direction in directions:
			var nx := int(voxel["x"]) + int(direction["delta"][0]); var ny := int(voxel["y"]) + int(direction["delta"][1]); var nz := int(voxel["z"]) + int(direction["delta"][2])
			if occupancy.has(_voxel_key(nx, ny, nz)): continue
			faces.append(_grid_face(voxel, String(direction["axis"]), int(direction["direction"])))
	for item in fallback:
		for direction in directions:
			faces.append({"kind": "FALLBACK", "axis": String(direction["axis"]), "direction": int(direction["direction"]), "part_id": String(item["part_id"]), "section_id": String(item["section_id"]), "material_key": String(item["material_key"]), "position_m": item["position_m"].duplicate(true), "dimensions_m": item["dimensions_m"].duplicate(true)})
	faces.sort_custom(func(a, b): return _face_key(a) < _face_key(b))
	return C.success({"faces": faces, "visible_part_count": visible_part_count, "raw_face_count": visible_part_count * 6, "exposed_face_count": faces.size(), "culled_face_count": visible_part_count * 6 - faces.size()})

static func _is_unit_axis_box(position: Array, dimensions: Array, rotation: Array) -> bool:
	for value in dimensions:
		if absf(float(value) - 1.0) > 0.000001: return false
	if rotation.size() != 4 or absf(float(rotation[0])) > 0.000001 or absf(float(rotation[1])) > 0.000001 or absf(float(rotation[2])) > 0.000001 or absf(float(rotation[3]) - 1.0) > 0.000001: return false
	for value in position:
		if absf(float(value) - round(float(value))) > 0.000001: return false
	return true
static func _grid_face(voxel: Dictionary, axis: String, direction: int) -> Dictionary:
	var x := int(voxel["x"]); var y := int(voxel["y"]); var z := int(voxel["z"]); var plane := 0; var u := 0; var v := 0
	match axis:
		"X": plane = x * 2 + direction; u = y; v = z
		"Y": plane = y * 2 + direction; u = x; v = z
		"Z": plane = z * 2 + direction; u = x; v = y
	return {"kind": "GRID", "axis": axis, "direction": direction, "plane_q2": plane, "u": u, "v": v, "part_id": String(voxel["part_id"]), "section_id": String(voxel["section_id"]), "material_key": String(voxel["material_key"])}
static func _voxel_key(x: int, y: int, z: int) -> String: return "%d,%d,%d" % [x, y, z]
static func _face_key(face: Dictionary) -> String:
	if String(face["kind"]) == "GRID": return "%s/%d/%012d/%012d/%012d/%s/%s" % [face["axis"], int(face["direction"]), int(face["plane_q2"]) + 1000000, int(face["u"]) + 1000000, int(face["v"]) + 1000000, face["material_key"], face["part_id"]]
	return "Z/%s/%s/%s" % [face["section_id"], face["part_id"], face["axis"]]
