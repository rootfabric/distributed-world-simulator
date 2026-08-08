extends SceneTree

const SOURCE_PATH := "res://assets/external/quaternius/base_characters/Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf"

var mesh_count := 0
var surface_count := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("CH7.8 fullbody structure probe: source=%s" % SOURCE_PATH)
	if not ResourceLoader.exists(SOURCE_PATH):
		push_error("CH7.8 fullbody structure probe: source missing")
		quit(2)
		return
	var packed = load(SOURCE_PATH)
	if not packed is PackedScene:
		push_error("CH7.8 fullbody structure probe: source is not PackedScene")
		quit(2)
		return
	var instance = (packed as PackedScene).instantiate()
	if not instance is Node:
		push_error("CH7.8 fullbody structure probe: source did not instantiate")
		quit(2)
		return
	_print_node(instance as Node, instance as Node, 0)
	print("CH7.8 fullbody structure probe: mesh_count=%d surface_count=%d" % [mesh_count, surface_count])
	(instance as Node).free()
	print("CH7.8 Quaternius fullbody mesh structure probe: PASS")
	quit(0)

func _print_node(root_node: Node, node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		print("%sNODE Skeleton3D name=%s path=%s bones=%d" % [indent, node.name, root_node.get_path_to(node), skeleton.get_bone_count()])
	elif node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_count += 1
		var mesh: Mesh = mesh_instance.mesh
		var surfaces := mesh.get_surface_count() if mesh != null else 0
		surface_count += surfaces
		var aabb := mesh_instance.get_aabb()
		print("%sNODE MeshInstance3D name=%s path=%s visible=%s skin=%s skeleton=%s surfaces=%d aabb_pos=%s aabb_size=%s" % [
			indent,
			node.name,
			root_node.get_path_to(node),
			mesh_instance.visible,
			mesh_instance.skin != null,
			String(mesh_instance.skeleton),
			surfaces,
			str(aabb.position),
			str(aabb.size),
		])
		if mesh != null:
			for surface_index in range(surfaces):
				var material: Material = mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.surface_get_material(surface_index)
				var material_name := ""
				var material_class := ""
				if material != null:
					material_name = String(material.resource_name)
					material_class = material.get_class()
				print("%s  SURFACE index=%d name=%s material=%s class=%s" % [
					indent,
					surface_index,
					mesh.surface_get_name(surface_index),
					material_name,
					material_class,
				])
	else:
		print("%sNODE %s name=%s path=%s" % [indent, node.get_class(), node.name, root_node.get_path_to(node)])
	for child in node.get_children():
		_print_node(root_node, child, depth + 1)
