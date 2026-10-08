class_name QuaterniusAvatarPresenter
extends Node3D

const BASE_ASSET_ROOT := "res://assets/external/quaternius/base_characters"
const ANIMATION_ASSET_ROOT := "res://assets/external/quaternius/animation_library"
const IDLE_SPEED_MPS := 0.12
const DEFAULT_RUN_THRESHOLD_MPS := 5.0
const FACING_RESPONSE := 12.0

const SEMANTIC_CANDIDATES := {
	"idle": ["idle", "idle01", "idle1", "standingidle"],
	"walk": ["walk", "walkforward", "walking", "walkfwd"],
	"run": ["run", "runforward", "running", "jog", "jogforward", "sprint"],
}

var asset_mode := "UNINITIALIZED"
var model_path := ""
var animation_path := ""
var current_semantic := "idle"
var current_animation := ""
var run_threshold_mps := DEFAULT_RUN_THRESHOLD_MPS
var model_yaw_offset_rad := 0.0
var matched_bones := 0
var root_motion_applied := false

var _visual_yaw := 0.0
var _target_visual_yaw := 0.0
var _motion_time := 0.0
var _model_yaw_root: Node3D
var _model_root: Node3D
var _animation_source_root: Node3D
var _target_skeleton: Skeleton3D
var _source_skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _bone_map: Array[Vector2i] = []
var _fallback_parts: Dictionary = {}


func setup(options: Dictionary = {}) -> Dictionary:
	run_threshold_mps = maxf(0.5, float(options.get("run_threshold_mps", DEFAULT_RUN_THRESHOLD_MPS)))
	model_yaw_offset_rad = deg_to_rad(float(options.get("model_yaw_offset_deg", 0.0)))
	_model_yaw_root = Node3D.new()
	_model_yaw_root.name = "AvatarYawRoot"
	add_child(_model_yaw_root)
	var force_fallback := bool(options.get("force_fallback", false))
	if not force_fallback and _try_load_quaternius(options):
		return _success(create_report())
	_build_fallback_humanoid()
	asset_mode = "FALLBACK"
	return _success(create_report())


func apply_motion(
	velocity: Vector3,
	up: Vector3 = Vector3.UP,
	facing_direction: Vector3 = Vector3.ZERO
) -> Dictionary:
	var safe_up := up.normalized() if up.length_squared() > 0.000001 else Vector3.UP
	var horizontal_velocity := velocity - safe_up * velocity.dot(safe_up)
	var speed := horizontal_velocity.length()
	var semantic := "idle"
	if speed > IDLE_SPEED_MPS:
		semantic = "run" if speed >= run_threshold_mps else "walk"
	var direction := facing_direction - safe_up * facing_direction.dot(safe_up)
	if direction.length_squared() <= 0.000001:
		direction = horizontal_velocity
	if direction.length_squared() > 0.000001:
		var local_direction := direction.normalized()
		if get_parent() is Node3D:
			local_direction = (get_parent() as Node3D).global_transform.basis.inverse() * local_direction
		_target_visual_yaw = atan2(local_direction.x, local_direction.z)
	if semantic != current_semantic:
		current_semantic = semantic
		_play_semantic(current_semantic)
	return _success({
		"semantic": current_semantic,
		"speed_mps": speed,
		"animation": current_animation,
	})


func set_model_yaw_offset_degrees(value: float) -> void:
	model_yaw_offset_rad = deg_to_rad(value)


func _process(delta: float) -> void:
	_motion_time += delta
	_visual_yaw = lerp_angle(
		_visual_yaw,
		_target_visual_yaw,
		clampf(delta * FACING_RESPONSE, 0.0, 1.0)
	)
	if _model_yaw_root != null:
		_model_yaw_root.rotation.y = _visual_yaw + model_yaw_offset_rad
	if _source_skeleton != null and _target_skeleton != null and _source_skeleton != _target_skeleton:
		_copy_animation_pose()
	if asset_mode == "FALLBACK":
		_animate_fallback()


func _try_load_quaternius(options: Dictionary) -> bool:
	model_path = String(options.get("model_path", "")).strip_edges()
	if model_path.is_empty():
		model_path = _find_best_model_scene(BASE_ASSET_ROOT)
	if model_path.is_empty():
		return false
	var packed_model = load(model_path)
	if not packed_model is PackedScene:
		return false
	var model_instance = (packed_model as PackedScene).instantiate()
	if not model_instance is Node3D:
		model_instance.free()
		return false
	_model_root = model_instance as Node3D
	_model_root.name = "QuaterniusModel"
	_model_yaw_root.add_child(_model_root)
	_target_skeleton = _find_first_skeleton(_model_root)
	if _target_skeleton == null:
		_model_root.queue_free()
		_model_root = null
		return false

	_animation_player = _find_first_animation_player(_model_root)
	if _animation_player != null and _resolve_required_animations():
		_source_skeleton = _target_skeleton
		asset_mode = "QUATERNIUS_EMBEDDED"
		_play_semantic("idle")
		return true

	animation_path = String(options.get("animation_path", "")).strip_edges()
	if animation_path.is_empty():
		animation_path = _find_best_animation_scene(ANIMATION_ASSET_ROOT)
	if animation_path.is_empty():
		asset_mode = "QUATERNIUS_STATIC"
		return true
	var packed_animation = load(animation_path)
	if not packed_animation is PackedScene:
		asset_mode = "QUATERNIUS_STATIC"
		return true
	var animation_instance = (packed_animation as PackedScene).instantiate()
	if not animation_instance is Node3D:
		animation_instance.free()
		asset_mode = "QUATERNIUS_STATIC"
		return true
	_animation_source_root = animation_instance as Node3D
	_animation_source_root.name = "QuaterniusAnimationSource"
	_animation_source_root.visible = false
	add_child(_animation_source_root)
	_source_skeleton = _find_first_skeleton(_animation_source_root)
	_animation_player = _find_first_animation_player(_animation_source_root)
	if _source_skeleton == null or _animation_player == null:
		asset_mode = "QUATERNIUS_STATIC"
		return true
	_build_bone_map()
	if matched_bones < 8 or not _resolve_required_animations():
		asset_mode = "QUATERNIUS_STATIC"
		return true
	asset_mode = "QUATERNIUS_RETARGET"
	_play_semantic("idle")
	return true


func _resolve_required_animations() -> bool:
	if _animation_player == null:
		return false
	for semantic in ["idle", "walk", "run"]:
		if _find_animation_for_semantic(semantic).is_empty():
			return false
	return true


func _play_semantic(semantic: String) -> void:
	if _animation_player == null:
		current_animation = ""
		return
	var animation_name := _find_animation_for_semantic(semantic)
	if animation_name.is_empty():
		current_animation = ""
		return
	if current_animation == animation_name and _animation_player.is_playing():
		return
	current_animation = animation_name
	_animation_player.play(StringName(animation_name), 0.12)


func _find_animation_for_semantic(semantic: String) -> String:
	if _animation_player == null:
		return ""
	var candidates: Array = SEMANTIC_CANDIDATES.get(semantic, [])
	var names := _animation_player.get_animation_list()
	var best_name := ""
	var best_score := -100000
	for raw_name in names:
		var name := String(raw_name)
		if name == "RESET":
			continue
		var normalized := _normalized_token(name)
		var score := 0
		for candidate_value in candidates:
			var candidate := _normalized_token(String(candidate_value))
			if normalized == candidate:
				score = maxi(score, 100)
			elif normalized.ends_with(candidate):
				score = maxi(score, 80)
			elif normalized.contains(candidate):
				score = maxi(score, 60)
		if semantic in ["walk", "run"]:
			for unwanted in ["back", "left", "right", "strafe", "turn", "crouch", "crawl"]:
				if normalized.contains(unwanted):
					score -= 35
		if score > best_score:
			best_score = score
			best_name = name
	return best_name if best_score > 0 else ""


func _build_bone_map() -> void:
	_bone_map.clear()
	matched_bones = 0
	if _source_skeleton == null or _target_skeleton == null:
		return
	var target_by_name: Dictionary = {}
	for target_index in range(_target_skeleton.get_bone_count()):
		target_by_name[_normalized_bone_name(_target_skeleton.get_bone_name(target_index))] = target_index
	for source_index in range(_source_skeleton.get_bone_count()):
		var key := _normalized_bone_name(_source_skeleton.get_bone_name(source_index))
		if target_by_name.has(key):
			_bone_map.append(Vector2i(source_index, int(target_by_name[key])))
	matched_bones = _bone_map.size()


func _copy_animation_pose() -> void:
	for pair in _bone_map:
		var source_index := pair.x
		var target_index := pair.y
		_target_skeleton.set_bone_pose_rotation(
			target_index,
			_source_skeleton.get_bone_pose_rotation(source_index)
		)
		var normalized := _normalized_bone_name(_source_skeleton.get_bone_name(source_index))
		if normalized not in ["root", "hips", "pelvis"]:
			_target_skeleton.set_bone_pose_position(
				target_index,
				_source_skeleton.get_bone_pose_position(source_index)
			)
	root_motion_applied = false


func _find_best_model_scene(root_path: String) -> String:
	var candidates := _collect_scene_files(root_path)
	var best_path := ""
	var best_score := -100000
	for path in candidates:
		var normalized := path.to_lower()
		var score := 0
		if normalized.contains("regular"):
			score += 50
		if normalized.contains("male") and not normalized.contains("female"):
			score += 25
		if normalized.contains("character") or normalized.contains("body"):
			score += 10
		if normalized.ends_with(".glb"):
			score += 5
		for unwanted in ["hair", "animation", "weapon", "outfit", "prop"]:
			if normalized.contains(unwanted):
				score -= 100
		if score > best_score:
			best_score = score
			best_path = path
	return best_path if best_score > -50 else ""


func _find_best_animation_scene(root_path: String) -> String:
	var candidates := _collect_scene_files(root_path)
	var best_path := ""
	var best_score := -100000
	for path in candidates:
		var normalized := path.to_lower()
		var score := 0
		if normalized.contains("godot"):
			score += 40
		if normalized.contains("animation"):
			score += 25
		if normalized.contains("noroot") or normalized.contains("no_root") or normalized.contains("inplace"):
			score += 40
		if normalized.contains("rootmotion") and not normalized.contains("no"):
			score -= 25
		if normalized.ends_with(".glb"):
			score += 10
		if score > best_score:
			best_score = score
			best_path = path
	return best_path


func _collect_scene_files(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			result.append_array(_collect_scene_files(path))
		elif entry.to_lower().get_extension() in ["glb", "gltf", "fbx", "tscn"]:
			result.append(path)
	directory.list_dir_end()
	result.sort()
	return result


func _find_first_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _find_first_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_first_animation_player(child)
		if found != null:
			return found
	return null


func _normalized_token(value: String) -> String:
	return value.to_lower().replace("_", "").replace("-", "").replace(" ", "").replace("/", "").replace(".", "")


func _normalized_bone_name(value: String) -> String:
	var normalized := _normalized_token(value).replace(":", "")
	for prefix in ["mixamorig", "def", "org", "armature"]:
		if normalized.begins_with(prefix):
			normalized = normalized.trim_prefix(prefix)
	return normalized.replace("left", "l").replace("right", "r")


func _build_fallback_humanoid() -> void:
	_model_root = Node3D.new()
	_model_root.name = "FallbackHumanoid"
	_model_yaw_root.add_child(_model_root)
	var body_material := _material(Color(0.25, 0.48, 0.82))
	var dark_material := _material(Color(0.08, 0.11, 0.18))
	var skin_material := _material(Color(0.72, 0.52, 0.38))
	_add_box_part("Torso", Vector3(0.52, 0.64, 0.28), Vector3(0.0, 1.34, 0.0), body_material)
	_add_box_part("Pelvis", Vector3(0.40, 0.24, 0.26), Vector3(0.0, 0.94, 0.0), dark_material)
	_add_sphere_part("Head", 0.18, Vector3(0.0, 1.84, 0.0), skin_material)
	_add_capsule_part("LeftArm", 0.075, 0.62, Vector3(-0.38, 1.38, 0.0), body_material)
	_add_capsule_part("RightArm", 0.075, 0.62, Vector3(0.38, 1.38, 0.0), body_material)
	_add_capsule_part("LeftLeg", 0.09, 0.78, Vector3(-0.15, 0.52, 0.0), dark_material)
	_add_capsule_part("RightLeg", 0.09, 0.78, Vector3(0.15, 0.52, 0.0), dark_material)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material


func _add_box_part(part_name: String, size: Vector3, position_value: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_fallback_part(part_name, mesh, position_value, material)


func _add_sphere_part(part_name: String, radius: float, position_value: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_add_fallback_part(part_name, mesh, position_value, material)


func _add_capsule_part(part_name: String, radius: float, height: float, position_value: Vector3, material: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	_add_fallback_part(part_name, mesh, position_value, material)


func _add_fallback_part(part_name: String, mesh: PrimitiveMesh, position_value: Vector3, material: Material) -> void:
	var pivot := Node3D.new()
	pivot.name = part_name
	pivot.position = position_value
	_model_root.add_child(pivot)
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	instance.material_override = material
	pivot.add_child(instance)
	_fallback_parts[part_name] = pivot


func _animate_fallback() -> void:
	var amplitude := 0.0
	var frequency := 1.0
	if current_semantic == "walk":
		amplitude = 0.55
		frequency = 7.5
	elif current_semantic == "run":
		amplitude = 0.95
		frequency = 11.0
	var swing := sin(_motion_time * frequency) * amplitude
	for pair in [["LeftArm", swing], ["RightArm", -swing], ["LeftLeg", -swing], ["RightLeg", swing]]:
		var part: Node3D = _fallback_parts.get(String(pair[0]))
		if part != null:
			part.rotation.x = float(pair[1])
	var torso: Node3D = _fallback_parts.get("Torso")
	if torso != null:
		torso.rotation.z = sin(_motion_time * 2.0) * 0.015 if current_semantic == "idle" else 0.0


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.quaternius_avatar_presenter.v1",
		"asset_mode": asset_mode,
		"model_path": model_path,
		"animation_path": animation_path,
		"current_semantic": current_semantic,
		"current_animation": current_animation,
		"run_threshold_mps": run_threshold_mps,
		"matched_bones": matched_bones,
		"target_skeleton": _target_skeleton != null,
		"source_skeleton": _source_skeleton != null,
		"animation_ready": _animation_player != null and _resolve_required_animations(),
		"root_motion_applied": root_motion_applied,
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}
