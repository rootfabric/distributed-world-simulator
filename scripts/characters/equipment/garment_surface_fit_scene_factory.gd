class_name GarmentSurfaceFitSceneFactory
extends RefCounted

const MAX_GROW_M := 0.05


static func create(source_scene: PackedScene, grow_amount_m: float) -> Dictionary:
	if source_scene == null:
		return _result(false, "MISSING_GARMENT_SCENE")
	if not is_finite(grow_amount_m) or grow_amount_m <= 0.0 or grow_amount_m > MAX_GROW_M:
		return _result(false, "INVALID_GARMENT_GROW_AMOUNT", {
			"grow_amount_m": grow_amount_m,
			"max_grow_m": MAX_GROW_M,
		})

	var instance = source_scene.instantiate()
	if not instance is Node3D:
		if instance is Node:
			(instance as Node).free()
		return _result(false, "GARMENT_ROOT_NOT_NODE3D")
	var root := instance as Node3D

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	if meshes.is_empty():
		root.free()
		return _result(false, "GARMENT_SURFACE_FIT_HAS_NO_MESHES")

	var fitted_surfaces := 0
	for mesh in meshes:
		if mesh.mesh == null:
			root.free()
			return _result(false, "GARMENT_SURFACE_FIT_MESH_RESOURCE_MISSING", {
				"mesh_name": String(mesh.name),
			})

		# Prefer an existing mesh-wide override when present. Otherwise create
		# independent per-surface overrides so imported/shared materials are never
		# mutated by presentation fitting.
		if mesh.material_override != null:
			if not mesh.material_override is BaseMaterial3D:
				root.free()
				return _result(false, "GARMENT_SURFACE_FIT_MATERIAL_UNSUPPORTED", {
					"mesh_name": String(mesh.name),
					"material_class": mesh.material_override.get_class(),
				})
			var fitted_override := (mesh.material_override as BaseMaterial3D).duplicate() as BaseMaterial3D
			fitted_override.set_grow_enabled(true)
			fitted_override.set_grow(grow_amount_m)
			mesh.material_override = fitted_override
			fitted_surfaces += max(1, mesh.mesh.get_surface_count())
			continue

		for surface_index in range(mesh.mesh.get_surface_count()):
			var source_material: Material = mesh.get_surface_override_material(surface_index)
			if source_material == null:
				source_material = mesh.mesh.surface_get_material(surface_index)
			if not source_material is BaseMaterial3D:
				root.free()
				return _result(false, "GARMENT_SURFACE_FIT_MATERIAL_UNSUPPORTED", {
					"mesh_name": String(mesh.name),
					"surface_index": surface_index,
					"material_class": source_material.get_class() if source_material != null else "",
				})
			var fitted := (source_material as BaseMaterial3D).duplicate() as BaseMaterial3D
			fitted.set_grow_enabled(true)
			fitted.set_grow(grow_amount_m)
			mesh.set_surface_override_material(surface_index, fitted)
			fitted_surfaces += 1

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	if pack_error != OK:
		return _result(false, "GARMENT_SURFACE_FIT_PACK_FAILED", {"error": int(pack_error)})

	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"scene": packed,
		"grow_amount_m": grow_amount_m,
		"mesh_count": meshes.size(),
		"fitted_surface_count": fitted_surfaces,
		"mutates_source_scene": false,
		"moves_gameplay_body": false,
		"owns_network_state": false,
	})


static func _collect_meshes(root_node: Node, output: Array[MeshInstance3D]) -> void:
	if root_node is MeshInstance3D:
		output.append(root_node as MeshInstance3D)
	for child in root_node.get_children():
		_collect_meshes(child, output)


static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
