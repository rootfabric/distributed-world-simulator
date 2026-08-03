extends RefCounted

const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const RuntimeRequest = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const CompileRequest = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const InteriorCell = preload("res://scripts/construction/proxies/construction_proxy_interior_cell.gd")
const Portal = preload("res://scripts/construction/proxies/construction_proxy_portal.gd")
const Interest = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")

const CONSTRUCT_ID := "construct/c22/large-station"
const ROOT_ITEM_ID := "item/c22/large-station"
const OBSERVER_ID := "observer/c22/player"
const COMPILER_SERVER := "server/c22/proxy-compiler"
const CELL_BRIDGE := "interior-cell/c22/bridge"
const CELL_ENGINEERING := "interior-cell/c22/engineering"

static func compile_request(dim_x: int = 20, dim_y: int = 10, dim_z: int = 50, revision: int = 1, authority_epoch: int = 1, authority_mode: String = CompileRequest.READ_ONLY) -> Dictionary:
	var parts: Array = []
	var bridge_parts: Array = []
	var engineering_parts: Array = []
	var index := 0
	for z in range(dim_z):
		for y in range(dim_y):
			for x in range(dim_x):
				var part_id := "part/c22/block-%06d" % index
				var metadata := {"geometry": {"bounding_box_m": [1.0, 1.0, 1.0]}, "condition": "INTACT", "proxy_material_key": "hull" if y in [0, dim_y - 1] else "structure"}
				if x in [maxi(dim_x / 2 - 1, 0), dim_x / 2] and y in [maxi(dim_y / 2 - 1, 0), dim_y / 2] and z in [maxi(dim_z / 2 - 1, 0), dim_z / 2]:
					metadata["proxy_interactive"] = true; metadata["proxy_interior_cell_id"] = CELL_BRIDGE; bridge_parts.append(part_id)
				elif x in [1, 2] and y in [1, 2] and z in [1, 2]:
					metadata["proxy_interactive"] = true; metadata["proxy_interior_cell_id"] = CELL_ENGINEERING; engineering_parts.append(part_id)
				parts.append(Part.create(part_id, "item/c22/block-%06d" % index, "HULL_BLOCK", "hull", 10.0, [float(x), float(y), float(z)], metadata))
				index += 1
	var snapshot := Snapshot.create(CONSTRUCT_ID, ROOT_ITEM_ID, revision, "OPERATIONAL", parts, [], {"proxy_source": "c22-fixture"})
	var runtime := RuntimeRequest.create(snapshot, [], {}, {}, [1000.0, 2000.0, -500.0], [0.0, 0.0, 0.0, 1.0], 1, 1)
	var bridge_min := [float(maxi(dim_x / 2 - 2, 0)), float(maxi(dim_y / 2 - 2, 0)), float(maxi(dim_z / 2 - 2, 0))]
	var bridge_max := [float(mini(dim_x / 2 + 3, dim_x)), float(mini(dim_y / 2 + 3, dim_y)), float(mini(dim_z / 2 + 3, dim_z))]
	var cells := [InteriorCell.create(CELL_BRIDGE, bridge_min, bridge_max, bridge_parts), InteriorCell.create(CELL_ENGINEERING, [0.5, 0.5, 0.5], [3.5, 3.5, 3.5], engineering_parts)]
	var portals := [Portal.create("portal/c22/bridge-engineering", CELL_BRIDGE, CELL_ENGINEERING, [3.0, 2.0, 3.0], true)]
	return CompileRequest.create(runtime, authority_epoch, authority_mode, COMPILER_SERVER, 5.0, 80.0, 250.0, 1000.0, cells, portals)

static func damaged_request(original: Dictionary, part_id: String) -> Dictionary:
	var runtime: Dictionary = original["runtime_projection_request"]
	var old_snapshot: Dictionary = runtime["construct_snapshot"]
	var parts: Array = old_snapshot["parts"].duplicate(true)
	for index in range(parts.size()):
		if String(parts[index]["part_id"]) == part_id:
			parts[index] = parts[index].duplicate(true); parts[index]["metadata"] = Dictionary(parts[index]["metadata"]).duplicate(true); parts[index]["metadata"]["condition"] = "DESTROYED"; break
	var snapshot := Snapshot.create(String(old_snapshot["construct_id"]), String(old_snapshot["root_item_instance_id"]), int(old_snapshot["state_revision"]) + 1, "DAMAGED", parts, old_snapshot["bonds"], old_snapshot["compiled_facets"])
	var next_runtime := RuntimeRequest.create(snapshot, runtime["item_projections"], runtime["mobile_profile"], runtime["spatial_profile"], runtime["world_origin_m"], runtime["world_rotation_quaternion"], int(runtime["collision_layer"]), int(runtime["collision_mask"]))
	return CompileRequest.create(next_runtime, int(original["authority_epoch"]), String(original["authority_mode"]), String(original["compiler_node_id"]), float(original["section_size_m"]), float(original["local_distance_m"]), float(original["section_distance_m"]), float(original["shell_distance_m"]), original["interior_cells"], original["portals"])

static func far_interest(request: Dictionary) -> Dictionary: return Interest.create(OBSERVER_ID, CONSTRUCT_ID, int(request["authority_epoch"]), 5000.0, [10.0, 5.0, 25.0], "", [], 1048576, 12, 32)
static func section_interest(request: Dictionary) -> Dictionary: return Interest.create(OBSERVER_ID, CONSTRUCT_ID, int(request["authority_epoch"]), 600.0, [10.0, 5.0, 25.0], "", [], 1048576, 12, 32)
static func local_interest(request: Dictionary) -> Dictionary: return Interest.create(OBSERVER_ID, CONSTRUCT_ID, int(request["authority_epoch"]), 60.0, [10.0, 5.0, 25.0], "", [], 1048576, 8, 16)
static func interior_interest(request: Dictionary) -> Dictionary: return Interest.create(OBSERVER_ID, CONSTRUCT_ID, int(request["authority_epoch"]), 20.0, [10.0, 5.0, 25.0], CELL_BRIDGE, [], 1048576, 6, 16)

class MemoryStore extends RefCounted:
	var values := {}
	func save_state(key: String, state: Dictionary) -> Dictionary: values[key] = state.duplicate(true); return {"success": true, "error_code": "", "message": ""}
	func load_state(key: String) -> Dictionary:
		if not values.has(key): return {"success": false, "error_code": "NOT_FOUND", "message": "NOT_FOUND"}
		return {"success": true, "error_code": "", "message": "", "state": values[key].duplicate(true)}
