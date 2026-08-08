extends SceneTree

const ShadowProxy = preload("res://scripts/characters/presentation/controllable_shadow_proxy.gd")
const PresentationProfile = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_skinned_world_proxy()
	await process_frame
	_test_custom_proxy_restore()
	await process_frame
	_finish()


func _test_skinned_world_proxy() -> void:
	var host := Node3D.new()
	host.name = "SkinnedHost"
	root.add_child(host)

	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	host.add_child(skeleton)
	skeleton.add_bone("root")

	var source := MeshInstance3D.new()
	source.name = "SkinnedBody"
	source.mesh = BoxMesh.new()
	source.skin = Skin.new()
	host.add_child(source)
	source.skeleton = source.get_path_to(skeleton)

	var manager = ShadowProxy.new()
	host.add_child(manager)
	var shadow_mask := 1 << 17
	var result: Dictionary = manager.configure(
		host,
		null,
		PresentationProfile.FirstPersonShadowPolicy.WORLD_PROXY,
		shadow_mask
	)
	_assert(bool(result.get("success", false)), "Skinned WORLD_PROXY configure failed")
	manager.set_active(true)
	var report: Dictionary = manager.create_report()
	_assert(int(report.get("proxy_count", 0)) == 1, "Skinned WORLD_PROXY count mismatch")
	_assert(int(report.get("skinned_proxy_count", 0)) == 1, "Skinned source was not recognized")
	_assert(int(report.get("skeleton_bound_proxy_count", 0)) == 1, "Shadow proxy did not bind the source Skeleton3D")
	_assert(int(report.get("shared_mesh_resource_count", 0)) == 1, "Skinned shadow proxy duplicated its Mesh resource")
	var proxies: Array = manager.get_generated_proxies()
	_assert(proxies.size() == 1, "Skinned generated proxy list mismatch")
	if proxies.size() == 1:
		var proxy: MeshInstance3D = proxies[0]
		_assert(proxy.mesh == source.mesh, "Skinned proxy is not sharing the source Mesh")
		_assert(proxy.skin == source.skin, "Skinned proxy is not sharing the source Skin")
		_assert(proxy.get_node_or_null(proxy.skeleton) == skeleton, "Skinned proxy NodePath does not resolve to the source Skeleton3D")
		_assert(proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Skinned proxy is not SHADOWS_ONLY")
		_assert(proxy.layers == shadow_mask, "Skinned proxy is on the wrong render layer")
		_assert(proxy.visible, "Skinned proxy did not activate")

	host.queue_free()


func _test_custom_proxy_restore() -> void:
	var host := Node3D.new()
	host.name = "CustomHost"
	root.add_child(host)

	var world_root := Node3D.new()
	world_root.name = "WorldVisual"
	host.add_child(world_root)
	var world_mesh := MeshInstance3D.new()
	world_mesh.mesh = BoxMesh.new()
	world_root.add_child(world_mesh)

	var custom_root := Node3D.new()
	custom_root.name = "CustomShadowRoot"
	host.add_child(custom_root)
	var custom_mesh := MeshInstance3D.new()
	custom_mesh.mesh = SphereMesh.new()
	custom_mesh.layers = 1 << 4
	custom_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	custom_root.add_child(custom_mesh)
	var original_layers := custom_mesh.layers
	var original_cast_shadow := custom_mesh.cast_shadow
	var original_visible := custom_root.visible

	var manager = ShadowProxy.new()
	host.add_child(manager)
	var shadow_mask := 1 << 17
	var result: Dictionary = manager.configure(
		world_root,
		custom_root,
		PresentationProfile.FirstPersonShadowPolicy.CUSTOM_PROXY,
		shadow_mask
	)
	_assert(bool(result.get("success", false)), "CUSTOM_PROXY configure failed")
	var report: Dictionary = manager.create_report()
	_assert(int(report.get("custom_proxy_count", 0)) == 1, "CUSTOM_PROXY geometry was not captured")
	_assert(not custom_root.visible, "CUSTOM_PROXY root should start inactive")
	_assert(custom_mesh.layers == shadow_mask, "CUSTOM_PROXY layer was not assigned")
	_assert(custom_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "CUSTOM_PROXY is not SHADOWS_ONLY")

	manager.set_active(true)
	_assert(custom_root.visible, "CUSTOM_PROXY did not activate")
	manager.clear()
	_assert(custom_root.visible == original_visible, "CUSTOM_PROXY root visibility was not restored")
	_assert(custom_mesh.layers == original_layers, "CUSTOM_PROXY original layer was not restored")
	_assert(custom_mesh.cast_shadow == original_cast_shadow, "CUSTOM_PROXY original cast_shadow was not restored")

	host.queue_free()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH6 shadow proxy contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH6 shadow proxy contract: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
