extends Node3D

const Adapter = preload("res://scripts/labs/t1/ts0/ts0_large_structural_proxy_adapter.gd")
const Controller = preload("res://scripts/construction/proxies/construction_proxy_streaming_controller.gd")
const HierarchyCompiler = preload("res://scripts/labs/t1/ts0/ts0_hierarchical_cluster_compiler.gd")
const HierarchyRuntime = preload("res://scripts/labs/t1/ts0/ts0_hierarchical_runtime_node.gd")

const SCALE_CONFIG_PATH := "res://config/construction/ts0-100k-hierarchical-scale-gate.v1.json"
const PROFILES: Array[String] = ["CUBE_100K", "PYRAMID_100K"]

@export var auto_boot: bool = true
@export var default_profile: String = "CUBE_100K"
@export var default_mode: String = Adapter.MODE_FAR

var _controller
var _runtime
var _hierarchy_runtime
var _camera: Camera3D
var _hud_label: Label
var _hud_panel: PanelContainer

var _scale_config: Dictionary = {}
var _current_profile := ""
var _current_mode := Adapter.MODE_FAR
var _manifest: Dictionary = {}
var _compile_stats: Dictionary = {}
var _hierarchy: Dictionary = {}
var _compile_ms := 0
var _hierarchy_compile_ms := 0
var _present_ms := 0
var _observer_distance_m := 0.0
var _hierarchy_active := false
var _mouse_look := false
var _camera_speed := 35.0
var _yaw := 0.0
var _pitch := -0.25
var _last_error := ""

func _ready() -> void:
	initialize_lab()
	if auto_boot:
		var launch := _launch_options()
		var profile_id := String(launch.get("profile", default_profile))
		_current_mode = String(launch.get("mode", default_mode))
		var loaded: Dictionary = load_profile(profile_id)
		if not bool(loaded.get("success", false)):
			_set_error("Load failed: %s" % String(loaded.get("error_code", "UNKNOWN")))

func initialize_lab() -> void:
	if _scale_config.is_empty():
		var loaded := _load_scale_config()
		if bool(loaded.get("success", false)):
			_scale_config = loaded["config"]
		else:
			_set_error(String(loaded.get("error_code", "TS0_2_CONFIG_LOAD_FAILED")))
	if _controller == null:
		_controller = Controller.new()
		_controller.name = "TS0ScaleProxyStreamingController"
		add_child(_controller)
	if _hierarchy_runtime == null:
		_hierarchy_runtime = HierarchyRuntime.new(_controller.get_mesh_cache())
		_hierarchy_runtime.name = "TS0HierarchicalRuntime"
		add_child(_hierarchy_runtime)
	if _camera == null:
		_setup_environment()
		_setup_camera()
		_setup_hud()
		_update_hud()

func load_profile(profile_id: String) -> Dictionary:
	initialize_lab()
	if not PROFILES.has(profile_id):
		return _failure("TS0_2_UNSUPPORTED_PROFILE")
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.visible = false
	if _hierarchy_runtime != null:
		_hierarchy_runtime.clear_presentation()
		_hierarchy_runtime.visible = false
	_hierarchy_active = false

	var prepared: Dictionary = Adapter.create_compile_request(profile_id)
	if not bool(prepared.get("success", false)):
		_set_error(String(prepared.get("error_code", "TS0_2_PREPARE_FAILED")))
		return prepared

	var started := Time.get_ticks_msec()
	var compiled: Dictionary = _controller.compile_construct(prepared["request"])
	_compile_ms = Time.get_ticks_msec() - started
	if not bool(compiled.get("success", false)):
		_set_error(String(compiled.get("error_code", "TS0_2_C22_COMPILE_FAILED")))
		return compiled

	var construct_id := String(prepared["snapshot"]["construct_id"])
	_manifest = _controller.get_manifest(construct_id)
	_compile_stats = Dictionary(compiled.get("stats", {})).duplicate(true)
	var topology: Dictionary = _controller.get_topology(construct_id)

	var policy: Dictionary = _scale_config.get("hierarchical_policy", {})
	var cluster_edge := int(policy.get("cluster_edge_sections", 3))
	started = Time.get_ticks_msec()
	var hierarchy_result: Dictionary = HierarchyCompiler.compile(
		_manifest,
		topology,
		_controller.get_cache(),
		cluster_edge
	)
	_hierarchy_compile_ms = Time.get_ticks_msec() - started
	if not bool(hierarchy_result.get("success", false)):
		_set_error(String(hierarchy_result.get("error_code", "TS0_2_HIERARCHY_COMPILE_FAILED")))
		return hierarchy_result

	var max_clusters := int(policy.get("max_cluster_count", 64))
	if int(hierarchy_result.get("cluster_count", 0)) > max_clusters:
		var failure := _failure("TS0_2_CLUSTER_COUNT_EXCEEDS_LAB_BUDGET")
		failure["details"] = {
			"cluster_count": int(hierarchy_result.get("cluster_count", 0)),
			"max_cluster_count": max_clusters,
		}
		_set_error(String(failure["error_code"]))
		return failure

	_hierarchy = hierarchy_result
	_current_profile = profile_id
	_last_error = ""
	_focus_camera_on_manifest()
	var presented: Dictionary = set_view_mode(_current_mode)
	if not bool(presented.get("success", false)):
		return presented

	return _success({
		"profile_id": _current_profile,
		"manifest": _manifest.duplicate(true),
		"compile_stats": _compile_stats.duplicate(true),
		"hierarchy_stats": get_hierarchy_stats(),
		"compile_ms": _compile_ms,
		"hierarchy_compile_ms": _hierarchy_compile_ms,
		"presentation": presented,
	})

func set_view_mode(mode: String) -> Dictionary:
	initialize_lab()
	if _manifest.is_empty() or _hierarchy.is_empty():
		return _failure("TS0_2_PROFILE_NOT_COMPILED")
	if not Adapter.MODES.has(mode):
		return _failure("TS0_2_INVALID_MODE")

	var started := Time.get_ticks_msec()
	var result: Dictionary = {}
	if mode == Adapter.MODE_FAR:
		_hierarchy_runtime.visible = false
		var prepared: Dictionary = Adapter.create_interest(_manifest, Adapter.MODE_FAR)
		if not bool(prepared.get("success", false)):
			_set_error(String(prepared.get("error_code", "TS0_2_FAR_INTEREST_FAILED")))
			return prepared
		var presented: Dictionary = _controller.present(
			"client/ts0/100k-hierarchical-lab",
			prepared["interest"]
		)
		if not bool(presented.get("success", false)):
			_set_error(String(presented.get("error_code", "TS0_2_FAR_PRESENT_FAILED")))
			return presented
		_runtime = presented["runtime"]
		_runtime.visible = true
		_hierarchy_active = false
		_observer_distance_m = float(prepared["distance_m"])
		result = _success({
			"mode": mode,
			"detail_mode": String(_runtime.get_detail_mode()),
		})
	else:
		if _runtime != null and is_instance_valid(_runtime):
			_runtime.visible = false
		_hierarchy_runtime.visible = true
		var policy: Dictionary = _scale_config.get("hierarchical_policy", {})
		if mode == Adapter.MODE_MID:
			result = _hierarchy_runtime.apply_mid(_hierarchy)
		else:
			result = _hierarchy_runtime.apply_near(
				_hierarchy,
				_controller.get_cache(),
				Adapter.manifest_exterior_focus(_manifest),
				int(policy.get("near_refined_cluster_count", 1))
			)
		if not bool(result.get("success", false)):
			_set_error(String(result.get("error_code", "TS0_2_HIERARCHICAL_PRESENT_FAILED")))
			return result
		_hierarchy_active = true
		_observer_distance_m = _distance_for_mode(mode)

	_present_ms = Time.get_ticks_msec() - started
	_current_mode = mode
	_last_error = ""
	_update_hud()
	return _success({
		"mode": mode,
		"detail_mode": String(get_metrics()["representation_mode"]),
		"distance_m": _observer_distance_m,
		"metrics": get_metrics(),
	})

func get_metrics() -> Dictionary:
	var metrics := {
		"profile_id": _current_profile,
		"canonical_part_count": int(_manifest.get("total_part_count", 0)),
		"canonical_revision": int(_manifest.get("source_revision", 0)),
		"canonical_checksum": String(_manifest.get("source_checksum", "")),
		"total_sections": int(_manifest.get("total_section_count", 0)),
		"visible_sections": 0,
		"coverage_sections": 0,
		"coverage_complete": false,
		"coverage_strategy": "",
		"representation_mode": "",
		"observer_distance_m": _observer_distance_m,
		"cluster_count_total": int(_hierarchy.get("cluster_count", 0)),
		"cluster_meshes": 0,
		"section_meshes": 0,
		"refined_cluster_count": 0,
		"proxy_meshes": 0,
		"collision_proxies": 0,
		"active_runtime_nodes": 0,
		"vertices": 0,
		"triangles": 0,
		"surfaces_draw_calls": 0,
		"compile_ms": _compile_ms,
		"hierarchy_compile_ms": _hierarchy_compile_ms,
		"presentation_materialize_ms": _present_ms,
		"artifact_cache_entries": 0,
		"artifact_cache_bytes": 0,
		"mesh_cache_entries": 0,
		"mesh_cache_gpu_bytes": 0,
		"mesh_cache_hits": 0,
		"mesh_cache_misses": 0,
		"mesh_cache_evictions": 0,
		"hierarchy_coverage_checksum": String(_hierarchy.get("coverage_checksum", "")),
		"last_error": _last_error,
	}

	if _controller != null:
		var artifact_cache = _controller.get_cache()
		metrics["artifact_cache_entries"] = artifact_cache.get_artifact_count()
		metrics["artifact_cache_bytes"] = artifact_cache.get_total_bytes()
		var mesh_stats: Dictionary = _controller.get_mesh_cache().get_stats()
		metrics["mesh_cache_entries"] = int(mesh_stats.get("entries", 0))
		metrics["mesh_cache_gpu_bytes"] = int(mesh_stats.get("gpu_bytes", 0))
		metrics["mesh_cache_hits"] = int(mesh_stats.get("hits", 0))
		metrics["mesh_cache_misses"] = int(mesh_stats.get("misses", 0))
		metrics["mesh_cache_evictions"] = int(mesh_stats.get("evictions", 0))

	if _hierarchy_active:
		var h: Dictionary = _hierarchy_runtime.get_metrics()
		for key in [
			"representation_mode",
			"coverage_strategy",
			"coverage_sections",
			"coverage_complete",
			"cluster_count_total",
			"cluster_meshes",
			"section_meshes",
			"refined_cluster_count",
			"proxy_meshes",
			"active_runtime_nodes",
			"vertices",
			"triangles",
			"surfaces_draw_calls",
		]:
			metrics[key] = h.get(key, metrics[key])
		metrics["visible_sections"] = int(h.get("coverage_sections", 0))
	elif _runtime != null and is_instance_valid(_runtime):
		metrics["representation_mode"] = String(_runtime.get_detail_mode())
		metrics["proxy_meshes"] = int(_runtime.get_proxy_mesh_count())
		metrics["collision_proxies"] = int(_runtime.get_collision_proxy_count())
		metrics["active_runtime_nodes"] = int(metrics["proxy_meshes"]) + int(metrics["collision_proxies"])
		metrics["vertices"] = int(_runtime.get_total_proxy_vertex_count())
		metrics["triangles"] = int(_runtime.get_total_proxy_triangle_count())
		metrics["surfaces_draw_calls"] = int(_runtime.get_total_proxy_surface_count())
		metrics["coverage_sections"] = int(_manifest.get("total_section_count", 0))
		metrics["coverage_complete"] = true
		metrics["coverage_strategy"] = "FULL_ROOT_SHELL"
		metrics["visible_sections"] = 0

	return metrics

func get_manifest() -> Dictionary:
	return _manifest.duplicate(true)

func get_compile_stats() -> Dictionary:
	return _compile_stats.duplicate(true)

func get_hierarchy_stats() -> Dictionary:
	return {
		"cluster_edge_sections": int(_hierarchy.get("cluster_edge_sections", 0)),
		"source_section_count": int(_hierarchy.get("source_section_count", 0)),
		"cluster_count": int(_hierarchy.get("cluster_count", 0)),
		"nonempty_cluster_count": int(_hierarchy.get("nonempty_cluster_count", 0)),
		"total_cluster_quads": int(_hierarchy.get("total_cluster_quads", 0)),
		"coverage_checksum": String(_hierarchy.get("coverage_checksum", "")),
	}

func get_controller():
	return _controller

func get_runtime():
	return _runtime

func get_hierarchy_runtime():
	return _hierarchy_runtime

func get_current_profile() -> String:
	return _current_profile

func get_current_mode() -> String:
	return _current_mode

func _process(delta: float) -> void:
	if _camera == null:
		return
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): direction -= _camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): direction += _camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): direction -= _camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): direction += _camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_Q): direction -= Vector3.UP
	if Input.is_key_pressed(KEY_E): direction += Vector3.UP
	if direction.length_squared() > 0.0:
		var multiplier := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		_camera.global_position += direction.normalized() * _camera_speed * multiplier * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				load_profile("CUBE_100K")
			KEY_2:
				load_profile("PYRAMID_100K")
			KEY_3:
				set_view_mode(Adapter.MODE_NEAR)
			KEY_4:
				set_view_mode(Adapter.MODE_MID)
			KEY_5:
				set_view_mode(Adapter.MODE_FAR)
			KEY_R:
				_focus_camera_on_manifest()
			KEY_H:
				if _hud_panel != null:
					_hud_panel.visible = not _hud_panel.visible
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_mouse_look = event.pressed
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _mouse_look else Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseMotion and _mouse_look and _camera != null:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)

func _setup_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ReferenceEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.03, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.7, 0.8)
	environment.ambient_light_energy = 0.55
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "ReferenceSun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "ReferenceGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.09, 0.1, 0.12)
	ground_material.roughness = 0.95
	plane.material = ground_material
	ground.mesh = plane
	ground.position.y = -0.51
	add_child(ground)

	_add_reference_box("HumanReference_1_8m", Vector3(0.55, 1.8, 0.35), Vector3(-4.0, 0.4, -4.0), Color(0.95, 0.55, 0.25))
	_add_reference_box("ScaleMast_50m", Vector3(0.35, 50.0, 0.35), Vector3(-10.0, 24.5, -4.0), Color(0.35, 0.7, 0.95))

func _add_reference_box(node_name: String, size: Vector3, position_m: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	mesh.material = material
	node.mesh = mesh
	node.position = position_m
	add_child(node)

func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ObserverCamera"
	_camera.current = true
	_camera.near = 0.05
	_camera.far = 20000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.position = Vector3(120.0, 90.0, 120.0)
	_camera.look_at_from_position(_camera.position, Vector3(25.0, 25.0, 25.0), Vector3.UP)
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_hud_panel = PanelContainer.new()
	_hud_panel.position = Vector2(14.0, 14.0)
	_hud_panel.custom_minimum_size = Vector2(690.0, 0.0)
	layer.add_child(_hud_panel)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 15)
	_hud_panel.add_child(_hud_label)

func _focus_camera_on_manifest() -> void:
	if _camera == null or _manifest.is_empty():
		return
	var center_a := Adapter.manifest_center(_manifest)
	var center := Vector3(float(center_a[0]), float(center_a[1]), float(center_a[2]))
	var span := maxf(Adapter.manifest_span(_manifest), 10.0)
	_camera_speed = maxf(20.0, span * 1.1)
	_camera.position = center + Vector3(span * 1.55, span * 1.15, span * 1.55)
	_camera.look_at_from_position(_camera.position, center, Vector3.UP)
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x

func _update_hud() -> void:
	if _hud_label == null:
		return
	var m := get_metrics()
	_hud_label.text = "TS0.2 — 100k Hierarchical HLOD Candidate\n" \
		+ "1 CUBE_100K | 2 PYRAMID_100K | 3 NEAR | 4 MID | 5 FAR | RMB look | WASD/QE fly | Shift fast | R reset | H HUD\n\n" \
		+ "profile: %s\n" % String(m["profile_id"]) \
		+ "canonical parts/revision: %d / %d\n" % [int(m["canonical_part_count"]), int(m["canonical_revision"])] \
		+ "canonical checksum: %s\n" % String(m["canonical_checksum"]) \
		+ "detail mode / observer distance: %s / %.1f m\n" % [String(m["representation_mode"]), float(m["observer_distance_m"])] \
		+ "coverage: %d / %d sections | complete=%s | %s\n" % [int(m["coverage_sections"]), int(m["total_sections"]), str(bool(m["coverage_complete"])), String(m["coverage_strategy"])] \
		+ "clusters total/refined: %d / %d | cluster meshes=%d | section meshes=%d\n" % [int(m["cluster_count_total"]), int(m["refined_cluster_count"]), int(m["cluster_meshes"]), int(m["section_meshes"])] \
		+ "runtime proxy/collision nodes: %d / %d (total %d)\n" % [int(m["proxy_meshes"]), int(m["collision_proxies"]), int(m["active_runtime_nodes"])] \
		+ "vertices / triangles / surfaces(draw calls): %d / %d / %d\n" % [int(m["vertices"]), int(m["triangles"]), int(m["surfaces_draw_calls"])] \
		+ "C22 compile / hierarchy compile / present: %d / %d / %d ms\n" % [int(m["compile_ms"]), int(m["hierarchy_compile_ms"]), int(m["presentation_materialize_ms"])] \
		+ "artifact cache: %d entries / %d bytes\n" % [int(m["artifact_cache_entries"]), int(m["artifact_cache_bytes"])] \
		+ "mesh cache: %d entries / %d GPU bytes | hit/miss/evict %d/%d/%d\n" % [int(m["mesh_cache_entries"]), int(m["mesh_cache_gpu_bytes"]), int(m["mesh_cache_hits"]), int(m["mesh_cache_misses"]), int(m["mesh_cache_evictions"])] \
		+ ("ERROR: %s\n" % String(m["last_error"]) if not String(m["last_error"]).is_empty() else "")

func _distance_for_mode(mode: String) -> float:
	var local_distance := float(_manifest.get("local_distance_m", 80.0))
	var section_distance := float(_manifest.get("section_distance_m", 250.0))
	var shell_distance := float(_manifest.get("shell_distance_m", 1000.0))
	match mode:
		Adapter.MODE_NEAR:
			return maxf(0.0, local_distance * 0.5)
		Adapter.MODE_MID:
			return section_distance + (shell_distance - section_distance) * 0.25
		Adapter.MODE_FAR:
			return shell_distance + maxf(100.0, shell_distance * 0.25)
	return shell_distance

func _load_scale_config() -> Dictionary:
	if not FileAccess.file_exists(SCALE_CONFIG_PATH):
		return _failure("TS0_2_CONFIG_NOT_FOUND")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SCALE_CONFIG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("TS0_2_CONFIG_INVALID_JSON")
	var config: Dictionary = parsed
	if String(config.get("schema", "")) != "distributed_world_simulator.ts0_100k_hierarchical_scale_gate.v1":
		return _failure("TS0_2_CONFIG_UNSUPPORTED_SCHEMA")
	return _success({"config": config})

func _set_error(message: String) -> void:
	_last_error = message
	push_error(message)
	_update_hud()

func _launch_options() -> Dictionary:
	var result := {"profile": default_profile, "mode": default_mode}
	for argument in OS.get_cmdline_user_args():
		var value := String(argument)
		if value.begins_with("--ts0-profile="):
			result["profile"] = value.trim_prefix("--ts0-profile=")
		elif value.begins_with("--ts0-mode="):
			var mode := value.trim_prefix("--ts0-mode=").to_upper()
			if Adapter.MODES.has(mode):
				result["mode"] = mode
	return result

func _success(extra: Dictionary = {}) -> Dictionary:
	var value := {"success": true, "error_code": "", "message": ""}
	for key in extra:
		value[key] = extra[key]
	return value

func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
