extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const CompileRequest = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const Topology = preload("res://scripts/construction/proxies/construction_proxy_section_topology.gd")
const SurfaceExtractor = preload("res://scripts/construction/proxies/construction_exposed_surface_extractor.gd")
const GreedyCompiler = preload("res://scripts/construction/proxies/construction_greedy_mesh_compiler.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
const Manifest = preload("res://scripts/construction/proxies/construction_proxy_manifest.gd")
const PartDescriptor = preload("res://scripts/construction/runtime_projection/construction_runtime_part_descriptor.gd")

static func compile(request: Dictionary, cache) -> Dictionary:
	var checked: Dictionary = CompileRequest.validate(request)
	if not bool(checked.get("success", false)): return checked
	var snapshot: Dictionary = request["runtime_projection_request"]["construct_snapshot"]
	# C22 deliberately does not invoke the full C13 compiler for every child part.
	# It reads the same authoritative geometry metadata, compiles aggregated proxies,
	# and creates exact C13-compatible descriptors only for locally interactive parts.
	var topology_result: Dictionary = Topology.compile(snapshot, float(request["section_size_m"]))
	if not bool(topology_result.get("success", false)): return topology_result
	var topology: Dictionary = topology_result["topology"]
	checked = Topology.validate(topology)
	if not bool(checked.get("success", false)): return checked
	var surface_result: Dictionary = SurfaceExtractor.extract(snapshot, topology)
	if not bool(surface_result.get("success", false)): return surface_result
	var faces: Array = surface_result["faces"]
	var bounds: Array = _construct_bounds(topology["sections"])
	var all_section_ids: Array = []
	for section in topology["sections"]: all_section_ids.append(String(section["section_id"]))
	var shell_result: Dictionary = GreedyCompiler.compile_artifact(String(snapshot["construct_id"]), int(snapshot["state_revision"]), String(snapshot["checksum"]), int(request["authority_epoch"]), Artifact.SHELL, "IMPOSTOR", all_section_ids, bounds[0], bounds[1], snapshot["parts"].size(), faces)
	if not bool(shell_result.get("success", false)): return shell_result
	var shell_artifact: Dictionary = shell_result["artifact"]
	var publish: Dictionary = cache.publish(shell_artifact, "operation/proxy-compile/%s/shell/%s" % [String(snapshot["construct_id"]).trim_prefix("construct/").replace("/", "-"), String(shell_artifact["content_hash"])])
	if not bool(publish.get("success", false)): return publish
	var faces_by_section: Dictionary = {}
	for face in faces:
		var section_id := String(face["section_id"])
		if not faces_by_section.has(section_id): faces_by_section[section_id] = []
		faces_by_section[section_id].append(face)
	var section_artifacts: Array = []
	for section in topology["sections"]:
		var section_id := String(section["section_id"])
		var section_result: Dictionary = GreedyCompiler.compile_artifact(String(snapshot["construct_id"]), int(snapshot["state_revision"]), String(snapshot["checksum"]), int(request["authority_epoch"]), Artifact.SECTION, "SIMPLIFIED", [section_id], section["bounds_min_m"], section["bounds_max_m"], int(section["part_count"]), Array(faces_by_section.get(section_id, [])), section["interactive_part_ids"])
		if not bool(section_result.get("success", false)): return section_result
		var artifact: Dictionary = section_result["artifact"]
		publish = cache.publish(artifact, "operation/proxy-compile/%s/section/%s" % [String(snapshot["construct_id"]).trim_prefix("construct/").replace("/", "-"), String(artifact["content_hash"])])
		if not bool(publish.get("success", false)): return publish
		section_artifacts.append(artifact)
	var interior_artifacts: Array = []
	for cell in request["interior_cells"]:
		var cell_sections: Array = []
		for section in topology["sections"]:
			if _bounds_overlap(section["bounds_min_m"], section["bounds_max_m"], cell["bounds_min_m"], cell["bounds_max_m"]): cell_sections.append(String(section["section_id"]))
		var interior_result: Dictionary = GreedyCompiler.compile_artifact(String(snapshot["construct_id"]), int(snapshot["state_revision"]), String(snapshot["checksum"]), int(request["authority_epoch"]), Artifact.INTERIOR, "FULL", cell_sections, cell["bounds_min_m"], cell["bounds_max_m"], Array(cell["interactive_part_ids"]).size(), [], cell["interactive_part_ids"])
		if not bool(interior_result.get("success", false)): return interior_result
		var interior: Dictionary = interior_result["artifact"]
		publish = cache.publish(interior, "operation/proxy-compile/%s/interior/%s" % [String(snapshot["construct_id"]).trim_prefix("construct/").replace("/", "-"), String(interior["content_hash"])])
		if not bool(publish.get("success", false)): return publish
		interior_artifacts.append({"cell_id": String(cell["cell_id"]), "artifact": interior})
	var estimated_cache_bytes: int = int(shell_artifact["estimated_bytes"])
	for artifact in section_artifacts: estimated_cache_bytes += int(artifact["estimated_bytes"])
	for pair in interior_artifacts: estimated_cache_bytes += int(pair["artifact"]["estimated_bytes"])
	var manifest: Dictionary = Manifest.create(request, topology, shell_artifact, section_artifacts, interior_artifacts, request["portals"], bounds[0], bounds[1], int(surface_result["exposed_face_count"]), estimated_cache_bytes)
	checked = Manifest.validate(manifest)
	if not bool(checked.get("success", false)): return checked
	var interactive_ids: Dictionary = {}
	for section in topology["sections"]:
		for part_id in section["interactive_part_ids"]: interactive_ids[String(part_id)] = true
	var descriptor_by_part: Dictionary = {}
	for part in snapshot["parts"]:
		var part_id := String(part["part_id"])
		if not interactive_ids.has(part_id): continue
		var descriptor_result := _compile_interactive_descriptor(part)
		if not bool(descriptor_result.get("success", false)): return descriptor_result
		descriptor_by_part[part_id] = descriptor_result["descriptor"]
	return C.success({"manifest": manifest, "topology": topology, "descriptor_by_part": descriptor_by_part, "shell_artifact": shell_artifact, "section_artifacts": section_artifacts, "interior_artifacts": interior_artifacts, "stats": {"raw_face_count": int(surface_result["raw_face_count"]), "exposed_face_count": int(surface_result["exposed_face_count"]), "culled_face_count": int(surface_result["culled_face_count"]), "shell_quad_count": int(shell_artifact["merged_quad_count"]), "section_count": section_artifacts.size(), "cache_bytes": estimated_cache_bytes, "exact_descriptor_count": descriptor_by_part.size()}})

static func _compile_interactive_descriptor(part: Dictionary) -> Dictionary:
	var metadata: Dictionary = part["metadata"]
	var condition := String(metadata.get("condition", "INTACT"))
	var rotation: Array = Array(metadata.get("local_rotation_quaternion", [0.0, 0.0, 0.0, 1.0])).duplicate(true)
	var descriptor := PartDescriptor.create(String(part["part_id"]), String(part["item_instance_id"]), String(part["part_kind"]), String(part["role"]), "BOX", Topology.part_dimensions(part), [], part["local_position_m"], rotation, float(part["mass_kg"]), condition, condition != "DESTROYED", condition != "DESTROYED", Utils.payload_hash(part))
	var checked := PartDescriptor.validate(descriptor)
	return C.success({"descriptor": descriptor}) if bool(checked.get("success", false)) else checked
static func _construct_bounds(sections: Array) -> Array:
	var min_v: Array = [INF, INF, INF]; var max_v: Array = [-INF, -INF, -INF]
	for section in sections:
		for axis in range(3):
			min_v[axis] = minf(float(min_v[axis]), float(section["bounds_min_m"][axis]))
			max_v[axis] = maxf(float(max_v[axis]), float(section["bounds_max_m"][axis]))
	return [min_v, max_v]
static func _bounds_overlap(a_min: Array, a_max: Array, b_min: Array, b_max: Array) -> bool:
	for axis in range(3):
		if float(a_max[axis]) < float(b_min[axis]) or float(b_max[axis]) < float(a_min[axis]): return false
	return true
