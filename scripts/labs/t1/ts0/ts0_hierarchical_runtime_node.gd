extends Node3D

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")

var _mesh_cache
var _nodes: Array = []
var _detail_mode := ""
var _metrics: Dictionary = {}

func _init(mesh_cache = null) -> void:
	_mesh_cache = mesh_cache
	_reset_metrics()

func apply_mid(hierarchy: Dictionary) -> Dictionary:
	if _mesh_cache == null:
		return C.failure("TS0_HIERARCHY_MESH_CACHE_REQUIRED")
	clear_presentation()
	var coverage: Dictionary = {}
	var cluster_meshes := 0
	for cluster_value in hierarchy.get("clusters", []):
		var cluster: Dictionary = cluster_value
		for section_id in cluster.get("section_ids", []):
			coverage[String(section_id)] = true
		var added: Dictionary = _append_artifact(
			cluster["artifact"],
			"CLUSTER",
			String(cluster["cluster_id"])
		)
		if not bool(added.get("success", false)):
			return added
		if bool(added.get("node_created", false)):
			cluster_meshes += 1
	_detail_mode = "SECTION_HLOD"
	_finalize_metrics(
		hierarchy,
		coverage,
		cluster_meshes,
		0,
		0,
		"ALL_COARSE_CLUSTERS"
	)
	return C.success({"metrics": get_metrics()})

func apply_near(
	hierarchy: Dictionary,
	artifact_cache,
	focus_local_m: Array,
	refined_cluster_count: int = 1
) -> Dictionary:
	if _mesh_cache == null:
		return C.failure("TS0_HIERARCHY_MESH_CACHE_REQUIRED")
	if artifact_cache == null:
		return C.failure("TS0_HIERARCHY_ARTIFACT_CACHE_REQUIRED")
	if focus_local_m.size() != 3:
		return C.failure("TS0_HIERARCHY_INVALID_FOCUS")
	clear_presentation()

	var refined_ids := _nearest_cluster_ids(
		hierarchy.get("clusters", []),
		focus_local_m,
		maxi(refined_cluster_count, 1)
	)
	var coverage: Dictionary = {}
	var cluster_meshes := 0
	var section_meshes := 0
	var refined_clusters := 0

	for cluster_value in hierarchy.get("clusters", []):
		var cluster: Dictionary = cluster_value
		var cluster_id := String(cluster["cluster_id"])
		for section_id in cluster.get("section_ids", []):
			coverage[String(section_id)] = true
		if refined_ids.has(cluster_id):
			refined_clusters += 1
			for section_id_value in cluster.get("section_ids", []):
				var section_id := String(section_id_value)
				var artifact_id := String(
					Dictionary(hierarchy.get("section_artifact_ids", {})).get(section_id, "")
				)
				if artifact_id.is_empty():
					return C.failure("TS0_HIERARCHY_SECTION_ARTIFACT_ID_MISSING")
				var section_artifact: Dictionary = artifact_cache.get_artifact(artifact_id)
				if section_artifact.is_empty():
					return C.failure("TS0_HIERARCHY_SECTION_ARTIFACT_MISSING")
				var added: Dictionary = _append_artifact(
					section_artifact,
					"SECTION_REFINEMENT",
					section_id
				)
				if not bool(added.get("success", false)):
					return added
				if bool(added.get("node_created", false)):
					section_meshes += 1
		else:
			var added: Dictionary = _append_artifact(
				cluster["artifact"],
				"CLUSTER",
				cluster_id
			)
			if not bool(added.get("success", false)):
				return added
			if bool(added.get("node_created", false)):
				cluster_meshes += 1

	_detail_mode = "LOCAL_EXTERIOR"
	_finalize_metrics(
		hierarchy,
		coverage,
		cluster_meshes,
		section_meshes,
		refined_clusters,
		"LOCAL_CLUSTER_REFINEMENT_PLUS_COARSE_REMAINDER"
	)
	_metrics["refined_cluster_ids"] = refined_ids
	return C.success({"metrics": get_metrics()})

func clear_presentation() -> void:
	for node_value in _nodes:
		if is_instance_valid(node_value):
			remove_child(node_value)
			node_value.free()
	_nodes.clear()
	_detail_mode = ""
	_reset_metrics()

func get_metrics() -> Dictionary:
	return _metrics.duplicate(true)

func get_detail_mode() -> String:
	return _detail_mode

func get_proxy_mesh_instances() -> Array:
	return _nodes.duplicate(false)

func _append_artifact(
	artifact: Dictionary,
	representation_kind: String,
	source_id: String
) -> Dictionary:
	var materialized: Dictionary = _mesh_cache.materialize(artifact)
	if not bool(materialized.get("success", false)):
		return materialized
	var mesh = materialized["mesh"]
	var descriptor: Dictionary = materialized["descriptor"]
	_metrics["vertices"] = int(_metrics["vertices"]) + int(descriptor.get("vertex_count", 0))
	_metrics["triangles"] = int(_metrics["triangles"]) + int(descriptor.get("triangle_count", 0))
	_metrics["surfaces_draw_calls"] = int(_metrics["surfaces_draw_calls"]) + int(descriptor.get("surface_count", 0))
	if mesh == null or mesh.get_surface_count() == 0:
		return C.success({
			"node_created": false,
			"cache_hit": bool(materialized.get("cache_hit", false)),
		})
	var node := MeshInstance3D.new()
	node.name = "TS0HierarchyMesh_%04d" % _nodes.size()
	node.mesh = mesh
	node.set_meta("ts0_hierarchy_representation", representation_kind)
	node.set_meta("ts0_hierarchy_source_id", source_id)
	node.set_meta("construction_proxy_artifact_id", String(artifact["artifact_id"]))
	node.set_meta("array_mesh_backend", true)
	add_child(node)
	_nodes.append(node)
	return C.success({
		"node_created": true,
		"cache_hit": bool(materialized.get("cache_hit", false)),
	})

func _finalize_metrics(
	hierarchy: Dictionary,
	coverage: Dictionary,
	cluster_meshes: int,
	section_meshes: int,
	refined_clusters: int,
	strategy: String
) -> void:
	var source_sections := int(hierarchy.get("source_section_count", 0))
	_metrics["representation_mode"] = _detail_mode
	_metrics["coverage_strategy"] = strategy
	_metrics["coverage_sections"] = coverage.size()
	_metrics["source_section_count"] = source_sections
	_metrics["coverage_complete"] = coverage.size() == source_sections
	_metrics["cluster_count_total"] = int(hierarchy.get("cluster_count", 0))
	_metrics["cluster_meshes"] = cluster_meshes
	_metrics["section_meshes"] = section_meshes
	_metrics["refined_cluster_count"] = refined_clusters
	_metrics["proxy_meshes"] = cluster_meshes + section_meshes
	_metrics["active_runtime_nodes"] = _nodes.size()
	_metrics["coverage_checksum"] = String(hierarchy.get("coverage_checksum", ""))

func _nearest_cluster_ids(
	clusters: Array,
	focus_local_m: Array,
	count: int
) -> Array:
	var focus := Vector3(
		float(focus_local_m[0]),
		float(focus_local_m[1]),
		float(focus_local_m[2])
	)
	var rows: Array = []
	for cluster_value in clusters:
		var cluster: Dictionary = cluster_value
		var min_v: Array = cluster["bounds_min_m"]
		var max_v: Array = cluster["bounds_max_m"]
		var center := Vector3(
			(float(min_v[0]) + float(max_v[0])) * 0.5,
			(float(min_v[1]) + float(max_v[1])) * 0.5,
			(float(min_v[2]) + float(max_v[2])) * 0.5
		)
		rows.append({
			"cluster_id": String(cluster["cluster_id"]),
			"distance_squared": center.distance_squared_to(focus),
		})
	rows.sort_custom(func(a, b):
		var da := float(a["distance_squared"])
		var db := float(b["distance_squared"])
		if absf(da - db) > 0.000001:
			return da < db
		return String(a["cluster_id"]) < String(b["cluster_id"])
	)
	var result: Array = []
	for index in range(mini(count, rows.size())):
		result.append(String(rows[index]["cluster_id"]))
	return result

func _reset_metrics() -> void:
	_metrics = {
		"representation_mode": "",
		"coverage_strategy": "",
		"coverage_sections": 0,
		"source_section_count": 0,
		"coverage_complete": false,
		"cluster_count_total": 0,
		"cluster_meshes": 0,
		"section_meshes": 0,
		"refined_cluster_count": 0,
		"refined_cluster_ids": [],
		"proxy_meshes": 0,
		"active_runtime_nodes": 0,
		"vertices": 0,
		"triangles": 0,
		"surfaces_draw_calls": 0,
		"coverage_checksum": "",
	}
