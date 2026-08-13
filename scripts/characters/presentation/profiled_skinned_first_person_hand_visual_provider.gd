class_name ProfiledSkinnedFirstPersonHandVisualProvider
extends "res://scripts/characters/presentation/skinned_first_person_hand_visual_provider.gd"

const ProfileType = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const REST_AUTO_CANONICAL_REBIND := "AUTO_CANONICAL_REBIND"
const LAYOUT_PAIRED_SINGLE_MESH := "PAIRED_SINGLE_MESH"
const SPLIT_SKIN_BIND_SUFFIX := "SKIN_BIND_SUFFIX"
const WEIGHT_EPSILON := 0.00001

var hand_asset_profile: Dictionary = {}
var hand_asset_profile_path := ""
var _source_scene: PackedScene
var _source_resource_path := ""
var _last_adaptation_report: Dictionary = {}


func setup_profiled(
	p_scene: PackedScene,
	p_profile: Dictionary,
	p_profile_path: String = "",
	p_resource_path: String = ""
) -> Dictionary:
	var validation: Dictionary = ProfileType.validate(p_profile)
	if not bool(validation.get("success", false)):
		return validation
	if p_scene == null:
		return _failure("FPE_HAND_PROFILE_SCENE_REQUIRED")
	var provider_kind := String(p_profile.get("provider", "")).strip_edges().to_upper()
	if provider_kind != ProfileType.PROVIDER_SKINNED_NAMED_BIND:
		return _failure("FPE_HAND_PROFILE_PROVIDER_NOT_SKINNED", {"provider": provider_kind})
	var retarget := Dictionary(p_profile.get("retarget", {}))
	var rest_policy := String(retarget.get("rest_space_policy", "")).strip_edges().to_upper()
	if rest_policy not in [REST_SPACE_POLICY, REST_AUTO_CANONICAL_REBIND]:
		return _failure("FPE_HAND_PROFILE_REST_SPACE_NOT_CALIBRATED", {
			"profile_id": String(p_profile.get("profile_id", "")),
			"actual": rest_policy,
			"required": [REST_SPACE_POLICY, REST_AUTO_CANONICAL_REBIND],
		})
	var common_map := Dictionary(retarget.get("bone_map", {}))
	var by_hand_value: Variant = retarget.get("bone_map_by_hand", {})
	var by_hand := Dictionary(by_hand_value) if by_hand_value is Dictionary else {}
	if common_map.is_empty() and by_hand.is_empty():
		return _failure("FPE_HAND_PROFILE_BONE_MAP_REQUIRED", {
			"profile_id": String(p_profile.get("profile_id", "")),
		})

	hand_asset_profile = p_profile.duplicate(true)
	hand_asset_profile_path = p_profile_path.strip_edges()
	_source_scene = p_scene
	_source_resource_path = p_resource_path.strip_edges()
	return _success({
		"profile_id": String(hand_asset_profile.get("profile_id", "")),
		"profile_path": hand_asset_profile_path,
		"resource_path": _source_resource_path,
		"portable_profile": true,
		"paired_single_mesh_supported": true,
		"auto_canonical_rebind_supported": true,
	})


func install_visuals(
	skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	if _source_scene == null or hand_asset_profile.is_empty():
		return _failure("FPE_HAND_PROFILE_PROVIDER_NOT_CONFIGURED")
	var adapted_result := _build_adapted_scene(hand_id, skeleton)
	if not bool(adapted_result.get("success", false)):
		return adapted_result
	var adapted_details := Dictionary(adapted_result.get("details", {}))
	var adapted_value: Variant = adapted_details.get("scene")
	if not adapted_value is PackedScene:
		return _failure("FPE_HAND_PROFILE_ADAPTED_SCENE_INVALID")
	_last_adaptation_report = Dictionary(adapted_details.get("adaptation_report", {})).duplicate(true)
	var adapted_scene := adapted_value as PackedScene
	var parent_setup: Dictionary = super.setup(adapted_scene, _source_resource_path)
	if not bool(parent_setup.get("success", false)):
		return parent_setup
	var result: Dictionary = super.install_visuals(skeleton, hand_id, viewmodel_layer_index)
	if bool(result.get("success", false)):
		var details := Dictionary(result.get("details", {}))
		var report := Dictionary(details.get("report", {})).duplicate(true)
		report["profile_id"] = String(hand_asset_profile.get("profile_id", ""))
		report["profile_path"] = hand_asset_profile_path
		report["profiled_external_asset"] = bool(Dictionary(hand_asset_profile.get("asset", {})).get("external", false))
		report["portable_profile"] = true
		report["source_license"] = String(Dictionary(hand_asset_profile.get("license", {})).get("spdx", ""))
		report["adaptation"] = _last_adaptation_report.duplicate(true)
		report["paired_single_mesh_split"] = bool(_last_adaptation_report.get("paired_single_mesh_split", false))
		report["auto_canonical_rebind"] = bool(_last_adaptation_report.get("auto_canonical_rebind", false))
		details["report"] = report
		result["details"] = details
	return result


func _build_adapted_scene(hand_id: String, target_skeleton: Skeleton3D) -> Dictionary:
	var normalized_hand := hand_id.strip_edges().to_lower()
	if normalized_hand not in ["left", "right"]:
		return _failure("FPE_HAND_PROFILE_INVALID_HAND", {"hand_id": hand_id})
	if target_skeleton == null:
		return _failure("FPE_HAND_PROFILE_TARGET_SKELETON_REQUIRED")
	var source_instance: Node = _source_scene.instantiate()
	if not source_instance is Node3D:
		if source_instance != null:
			source_instance.free()
		return _failure("FPE_HAND_PROFILE_SOURCE_ROOT_NOT_NODE3D")
	var source_root := source_instance as Node3D
	var selection := Dictionary(hand_asset_profile.get("selection", {}))
	var selected := _select_skinned_meshes(source_root, selection, normalized_hand)
	if selected.is_empty():
		source_root.free()
		return _failure("FPE_HAND_PROFILE_NO_SKINNED_MESH_SELECTED", {
			"profile_id": String(hand_asset_profile.get("profile_id", "")),
			"hand_id": normalized_hand,
		})

	var wrapper := Node3D.new()
	wrapper.name = "ProfiledHandAsset"
	wrapper.set_meta("fpe_hand_visual_schema", ASSET_SCHEMA)
	wrapper.set_meta("fpe_compatible_skeleton_schema", SKELETON_SCHEMA)
	wrapper.set_meta("fpe_rest_space_policy", REST_SPACE_POLICY)
	wrapper.set_meta("fpe_hand", normalized_hand)
	wrapper.set_meta("fpe_provider_id", String(hand_asset_profile.get("profile_id", "profiled_hand")))
	var retarget := Dictionary(hand_asset_profile.get("retarget", {}))
	var rest_policy := String(retarget.get("rest_space_policy", "")).strip_edges().to_upper()
	var effective_bone_map := _effective_bone_map(retarget, normalized_hand)
	var presentation_transform := _profile_transform(Dictionary(hand_asset_profile.get("presentation", {})))
	var layout := String(hand_asset_profile.get("hand_layout", "")).strip_edges().to_upper()
	var installed_meshes := 0
	var kept_faces := 0
	var dropped_faces := 0
	var compact_bind_count := 0
	var calibration_scale := 1.0

	for source_mesh in selected:
		var relative := _relative_transform_to_root(source_mesh, source_root)
		var candidate: MeshInstance3D = source_mesh
		if layout == LAYOUT_PAIRED_SINGLE_MESH:
			var split_result := _split_paired_single_mesh(source_mesh, normalized_hand, selection)
			if not bool(split_result.get("success", false)):
				wrapper.free()
				source_root.free()
				return split_result
			var split_details := Dictionary(split_result.get("details", {}))
			var candidate_value: Variant = split_details.get("mesh_instance")
			if not candidate_value is MeshInstance3D:
				wrapper.free()
				source_root.free()
				return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_RESULT_INVALID")
			candidate = candidate_value as MeshInstance3D
			kept_faces += int(split_details.get("kept_faces", 0))
			dropped_faces += int(split_details.get("dropped_faces", 0))
			compact_bind_count += int(split_details.get("compact_bind_count", 0))
		else:
			var parent := source_mesh.get_parent()
			if parent != null:
				parent.remove_child(source_mesh)

		var calibration := Transform3D.IDENTITY
		if rest_policy == REST_AUTO_CANONICAL_REBIND:
			var calibration_result := _auto_calibration_transform(
				source_mesh,
				source_root,
				target_skeleton,
				normalized_hand,
				retarget
			)
			if not bool(calibration_result.get("success", false)):
				candidate.free()
				wrapper.free()
				source_root.free()
				return calibration_result
			var calibration_details := Dictionary(calibration_result.get("details", {}))
			calibration = calibration_details.get("transform", Transform3D.IDENTITY) as Transform3D
			calibration_scale = float(calibration_details.get("uniform_scale", 1.0))
			var rebind_result := _rebind_skin_to_canonical_rest(
				candidate,
				target_skeleton,
				effective_bone_map,
				normalized_hand,
				retarget
			)
			if not bool(rebind_result.get("success", false)):
				candidate.free()
				wrapper.free()
				source_root.free()
				return rebind_result
			effective_bone_map = Dictionary(Dictionary(rebind_result.get("details", {})).get("effective_bone_map", effective_bone_map)).duplicate(true)

		wrapper.add_child(candidate)
		candidate.transform = presentation_transform * calibration * relative
		_set_owner_recursive(candidate, wrapper)
		installed_meshes += 1

	wrapper.set_meta("fpe_bone_map", effective_bone_map.duplicate(true))
	source_root.free()
	var packed := PackedScene.new()
	var pack_error := packed.pack(wrapper)
	wrapper.free()
	if pack_error != OK:
		return _failure("FPE_HAND_PROFILE_PACK_ADAPTED_SCENE_FAILED", {"error": int(pack_error)})
	var adaptation_report := {
		"schema": "planet_simulator.fpe_hand_asset_adaptation.v2",
		"profile_id": String(hand_asset_profile.get("profile_id", "")),
		"hand_id": normalized_hand,
		"source_layout": layout,
		"paired_single_mesh_split": layout == LAYOUT_PAIRED_SINGLE_MESH,
		"auto_canonical_rebind": rest_policy == REST_AUTO_CANONICAL_REBIND,
		"installed_mesh_count": installed_meshes,
		"kept_faces": kept_faces,
		"dropped_faces": dropped_faces,
		"compact_bind_count": compact_bind_count,
		"effective_bone_map_count": effective_bone_map.size(),
		"calibration_scale": calibration_scale,
	}
	return _success({
		"scene": packed,
		"selected_mesh_count": selected.size(),
		"profile_id": String(hand_asset_profile.get("profile_id", "")),
		"adaptation_report": adaptation_report,
	})


func _split_paired_single_mesh(
	source_mesh: MeshInstance3D,
	hand_id: String,
	selection: Dictionary
) -> Dictionary:
	if source_mesh == null or not source_mesh.mesh is ArrayMesh or source_mesh.skin == null:
		return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_REQUIRES_ARRAY_MESH_AND_SKIN")
	var split := Dictionary(selection.get("paired_split", {}))
	var strategy := String(split.get("strategy", "")).strip_edges().to_upper()
	if strategy != SPLIT_SKIN_BIND_SUFFIX:
		return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_STRATEGY_UNSUPPORTED", {"strategy": strategy})
	var suffixes := Dictionary(split.get("suffix_by_hand", {}))
	var desired_suffix := String(suffixes.get(hand_id, ""))
	var opposite_hand := "right" if hand_id == "left" else "left"
	var opposite_suffix := String(suffixes.get(opposite_hand, ""))
	if desired_suffix.is_empty() or opposite_suffix.is_empty():
		return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_SUFFIX_REQUIRED", {"hand_id": hand_id})
	var shared_names: Array = split.get("shared_bind_names", []) if split.get("shared_bind_names", []) is Array else []
	var source_array_mesh := source_mesh.mesh as ArrayMesh
	var source_skin := source_mesh.skin
	var surface_kept_faces: Dictionary = {}
	var used_bind_indices: Dictionary = {}
	var kept_faces := 0
	var dropped_faces := 0

	for surface_index in range(source_array_mesh.get_surface_count()):
		if source_array_mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_TRIANGLES_REQUIRED", {"surface": surface_index})
		var mdt := MeshDataTool.new()
		var create_error := mdt.create_from_surface(source_array_mesh, surface_index)
		if create_error != OK:
			return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_MDT_FAILED", {"surface": surface_index, "error": int(create_error)})
		var kept: Array[int] = []
		for face_index in range(mdt.get_face_count()):
			var score := _face_side_score(mdt, face_index, source_skin, desired_suffix, opposite_suffix)
			if score.x > score.y and score.x > WEIGHT_EPSILON:
				kept.append(face_index)
				kept_faces += 1
				for corner in range(3):
					var vertex_index := mdt.get_face_vertex(face_index, corner)
					_collect_kept_vertex_binds(
						mdt,
						vertex_index,
						source_skin,
						desired_suffix,
						opposite_suffix,
						shared_names,
						used_bind_indices
					)
			else:
				dropped_faces += 1
		surface_kept_faces[surface_index] = kept

	if kept_faces <= 0 or used_bind_indices.is_empty():
		return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_EMPTY_SIDE", {"hand_id": hand_id})

	var old_indices: Array[int] = []
	for raw_index in used_bind_indices.keys():
		old_indices.append(int(raw_index))
	old_indices.sort()
	var old_to_new: Dictionary = {}
	var compact_skin := Skin.new()
	compact_skin.set_bind_count(old_indices.size())
	for new_index in range(old_indices.size()):
		var old_index := old_indices[new_index]
		old_to_new[old_index] = new_index
		compact_skin.set_bind_name(new_index, source_skin.get_bind_name(old_index))
		compact_skin.set_bind_bone(new_index, source_skin.get_bind_bone(old_index))
		compact_skin.set_bind_pose(new_index, source_skin.get_bind_pose(old_index))

	var output_mesh := ArrayMesh.new()
	for surface_index in range(source_array_mesh.get_surface_count()):
		var kept_value: Variant = surface_kept_faces.get(surface_index, [])
		var kept: Array = kept_value if kept_value is Array else []
		if kept.is_empty():
			continue
		var mdt := MeshDataTool.new()
		var create_error := mdt.create_from_surface(source_array_mesh, surface_index)
		if create_error != OK:
			return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_MDT_FAILED", {"surface": surface_index, "error": int(create_error)})
		var format := source_array_mesh.surface_get_format(surface_index)
		if (format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0:
			return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_8_WEIGHTS_NOT_YET_SUPPORTED", {"surface": surface_index})
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(source_array_mesh.surface_get_material(surface_index))
		for raw_face_index in kept:
			var face_index := int(raw_face_index)
			for corner in range(3):
				var vertex_index := mdt.get_face_vertex(face_index, corner)
				var influences := _filtered_vertex_influences(
					mdt,
					vertex_index,
					source_skin,
					desired_suffix,
					opposite_suffix,
					shared_names,
					old_to_new
				)
				if not bool(influences.get("success", false)):
					return influences
				var influence_details := Dictionary(influences.get("details", {}))
				st.set_bones(influence_details.get("bones", PackedInt32Array()) as PackedInt32Array)
				st.set_weights(influence_details.get("weights", PackedFloat32Array()) as PackedFloat32Array)
				if (format & Mesh.ARRAY_FORMAT_NORMAL) != 0:
					st.set_normal(mdt.get_vertex_normal(vertex_index))
				if (format & Mesh.ARRAY_FORMAT_TANGENT) != 0:
					st.set_tangent(mdt.get_vertex_tangent(vertex_index))
				if (format & Mesh.ARRAY_FORMAT_COLOR) != 0:
					st.set_color(mdt.get_vertex_color(vertex_index))
				if (format & Mesh.ARRAY_FORMAT_TEX_UV) != 0:
					st.set_uv(mdt.get_vertex_uv(vertex_index))
				if (format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0:
					st.set_uv2(mdt.get_vertex_uv2(vertex_index))
				st.add_vertex(mdt.get_vertex(vertex_index))
		st.index()
		st.commit(output_mesh)

	if output_mesh.get_surface_count() <= 0:
		return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_NO_OUTPUT_SURFACES", {"hand_id": hand_id})
	var output := MeshInstance3D.new()
	output.name = "%s_%s" % [source_mesh.name, hand_id]
	output.mesh = output_mesh
	output.skin = compact_skin
	output.material_override = source_mesh.material_override
	return _success({
		"mesh_instance": output,
		"kept_faces": kept_faces,
		"dropped_faces": dropped_faces,
		"compact_bind_count": compact_skin.get_bind_count(),
	})


func _face_side_score(
	mdt: MeshDataTool,
	face_index: int,
	skin: Skin,
	desired_suffix: String,
	opposite_suffix: String
) -> Vector2:
	var desired := 0.0
	var opposite := 0.0
	for corner in range(3):
		var vertex_index := mdt.get_face_vertex(face_index, corner)
		var bones := mdt.get_vertex_bones(vertex_index)
		var weights := mdt.get_vertex_weights(vertex_index)
		for influence_index in range(mini(bones.size(), weights.size())):
			var weight := float(weights[influence_index])
			if weight <= WEIGHT_EPSILON:
				continue
			var bind_index := int(bones[influence_index])
			if bind_index < 0 or bind_index >= skin.get_bind_count():
				continue
			var bind_name := String(skin.get_bind_name(bind_index))
			if bind_name.ends_with(desired_suffix):
				desired += weight
			elif bind_name.ends_with(opposite_suffix):
				opposite += weight
	return Vector2(desired, opposite)


func _collect_kept_vertex_binds(
	mdt: MeshDataTool,
	vertex_index: int,
	skin: Skin,
	desired_suffix: String,
	opposite_suffix: String,
	shared_names: Array,
	output: Dictionary
) -> void:
	var bones := mdt.get_vertex_bones(vertex_index)
	var weights := mdt.get_vertex_weights(vertex_index)
	for influence_index in range(mini(bones.size(), weights.size())):
		var weight := float(weights[influence_index])
		if weight <= WEIGHT_EPSILON:
			continue
		var bind_index := int(bones[influence_index])
		if bind_index < 0 or bind_index >= skin.get_bind_count():
			continue
		var bind_name := String(skin.get_bind_name(bind_index))
		if bind_name.ends_with(desired_suffix) or bind_name in shared_names:
			output[bind_index] = true
		elif not bind_name.ends_with(opposite_suffix) and bind_name in shared_names:
			output[bind_index] = true


func _filtered_vertex_influences(
	mdt: MeshDataTool,
	vertex_index: int,
	skin: Skin,
	desired_suffix: String,
	opposite_suffix: String,
	shared_names: Array,
	old_to_new: Dictionary
) -> Dictionary:
	var source_bones := mdt.get_vertex_bones(vertex_index)
	var source_weights := mdt.get_vertex_weights(vertex_index)
	if source_bones.size() != 4 or source_weights.size() != 4:
		return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_REQUIRES_4_WEIGHTS", {
			"bone_count": source_bones.size(),
			"weight_count": source_weights.size(),
		})
	var kept_old: Array[int] = []
	var kept_weights: Array[float] = []
	var total := 0.0
	for influence_index in range(4):
		var weight := float(source_weights[influence_index])
		if weight <= WEIGHT_EPSILON:
			continue
		var old_bind := int(source_bones[influence_index])
		if old_bind < 0 or old_bind >= skin.get_bind_count():
			continue
		var bind_name := String(skin.get_bind_name(old_bind))
		if bind_name.ends_with(opposite_suffix) and not bind_name in shared_names:
			continue
		if not bind_name.ends_with(desired_suffix) and not bind_name in shared_names:
			continue
		if not old_to_new.has(old_bind):
			continue
		kept_old.append(old_bind)
		kept_weights.append(weight)
		total += weight
	if kept_old.is_empty() or total <= WEIGHT_EPSILON:
		return _failure("FPE_HAND_PROFILE_PAIRED_SPLIT_VERTEX_LOST_ALL_WEIGHTS", {"vertex": vertex_index})
	var output_bones := PackedInt32Array([0, 0, 0, 0])
	var output_weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for output_index in range(mini(kept_old.size(), 4)):
		output_bones[output_index] = int(old_to_new.get(kept_old[output_index], 0))
		output_weights[output_index] = float(kept_weights[output_index]) / total
	return _success({"bones": output_bones, "weights": output_weights})


func _auto_calibration_transform(
	source_mesh: MeshInstance3D,
	source_root: Node3D,
	target_skeleton: Skeleton3D,
	hand_id: String,
	retarget: Dictionary
) -> Dictionary:
	var source_skeleton := _resolve_source_skeleton(source_mesh)
	if source_skeleton == null:
		return _failure("FPE_HAND_PROFILE_AUTO_REBIND_SOURCE_SKELETON_REQUIRED")
	var calibration := Dictionary(retarget.get("auto_calibration", {}))
	var source_anchor_by_hand := Dictionary(calibration.get("source_anchor_by_hand", {}))
	var source_reference_by_hand := Dictionary(calibration.get("source_scale_reference_by_hand", {}))
	var source_anchor_name := String(source_anchor_by_hand.get(hand_id, ""))
	var source_reference_name := String(source_reference_by_hand.get(hand_id, ""))
	var target_anchor_name := String(calibration.get("target_anchor", "Palm"))
	var target_reference_name := String(calibration.get("target_scale_reference", "MiddleProximal"))
	var multiplier := float(calibration.get("uniform_scale_multiplier", 1.0))
	var source_anchor_index := source_skeleton.find_bone(source_anchor_name)
	var source_reference_index := source_skeleton.find_bone(source_reference_name)
	var target_anchor_index := target_skeleton.find_bone(target_anchor_name)
	var target_reference_index := target_skeleton.find_bone(target_reference_name)
	if source_anchor_index < 0 or source_reference_index < 0:
		return _failure("FPE_HAND_PROFILE_AUTO_REBIND_SOURCE_ANCHOR_MISSING", {
			"anchor": source_anchor_name,
			"reference": source_reference_name,
		})
	if target_anchor_index < 0 or target_reference_index < 0:
		return _failure("FPE_HAND_PROFILE_AUTO_REBIND_TARGET_ANCHOR_MISSING", {
			"anchor": target_anchor_name,
			"reference": target_reference_name,
		})
	var source_skeleton_to_root := _relative_transform_to_root(source_skeleton, source_root)
	var source_anchor := source_skeleton_to_root * source_skeleton.get_bone_global_rest(source_anchor_index)
	var source_reference := source_skeleton_to_root * source_skeleton.get_bone_global_rest(source_reference_index)
	var target_anchor := target_skeleton.get_bone_global_rest(target_anchor_index)
	var target_reference := target_skeleton.get_bone_global_rest(target_reference_index)
	var source_span := source_anchor.origin.distance_to(source_reference.origin)
	var target_span := target_anchor.origin.distance_to(target_reference.origin)
	if source_span <= 0.000001 or target_span <= 0.000001:
		return _failure("FPE_HAND_PROFILE_AUTO_REBIND_SCALE_REFERENCE_DEGENERATE", {
			"source_span": source_span,
			"target_span": target_span,
		})
	var uniform_scale := target_span / source_span * multiplier
	var source_basis := source_anchor.basis.orthonormalized()
	var target_basis := target_anchor.basis.orthonormalized()
	var calibrated_basis := (target_basis * source_basis.inverse()).scaled(Vector3.ONE * uniform_scale)
	var calibrated_origin := target_anchor.origin - calibrated_basis * source_anchor.origin
	return _success({
		"transform": Transform3D(calibrated_basis, calibrated_origin),
		"uniform_scale": uniform_scale,
		"source_anchor": source_anchor_name,
		"source_reference": source_reference_name,
		"target_anchor": target_anchor_name,
		"target_reference": target_reference_name,
	})


func _rebind_skin_to_canonical_rest(
	mesh_instance: MeshInstance3D,
	target_skeleton: Skeleton3D,
	bone_map: Dictionary,
	hand_id: String,
	retarget: Dictionary
) -> Dictionary:
	if mesh_instance.skin == null:
		return _failure("FPE_HAND_PROFILE_AUTO_REBIND_SKIN_REQUIRED")
	var effective := bone_map.duplicate(true)
	var fallback_value: Variant = retarget.get("unmapped_used_bind_target_by_hand", {})
	var fallback_by_hand := Dictionary(fallback_value) if fallback_value is Dictionary else {}
	var fallback_target := String(fallback_by_hand.get(hand_id, "")).strip_edges()
	var skin := mesh_instance.skin
	for bind_index in range(skin.get_bind_count()):
		var source_name := String(skin.get_bind_name(bind_index)).strip_edges()
		var canonical_name := String(effective.get(source_name, "")).strip_edges()
		if canonical_name.is_empty() and not fallback_target.is_empty():
			canonical_name = fallback_target
			effective[source_name] = canonical_name
		if canonical_name.is_empty():
			return _failure("FPE_HAND_PROFILE_AUTO_REBIND_TARGET_UNRESOLVED", {"source_bone": source_name})
		var canonical_index := target_skeleton.find_bone(canonical_name)
		if canonical_index < 0:
			return _failure("FPE_HAND_PROFILE_AUTO_REBIND_TARGET_MISSING", {
				"source_bone": source_name,
				"canonical_bone": canonical_name,
			})
		skin.set_bind_pose(bind_index, target_skeleton.get_bone_global_rest(canonical_index).affine_inverse())
	return _success({"effective_bone_map": effective})


func _effective_bone_map(retarget: Dictionary, hand_id: String) -> Dictionary:
	var result := Dictionary(retarget.get("bone_map", {})).duplicate(true)
	var by_hand_value: Variant = retarget.get("bone_map_by_hand", {})
	if by_hand_value is Dictionary:
		var hand_value: Variant = Dictionary(by_hand_value).get(hand_id, {})
		if hand_value is Dictionary:
			for source_name in Dictionary(hand_value).keys():
				result[source_name] = Dictionary(hand_value).get(source_name)
	return result


func _resolve_source_skeleton(mesh_instance: MeshInstance3D) -> Skeleton3D:
	if mesh_instance == null:
		return null
	if not mesh_instance.skeleton.is_empty():
		var node := mesh_instance.get_node_or_null(mesh_instance.skeleton)
		if node is Skeleton3D:
			return node as Skeleton3D
	var parent := mesh_instance.get_parent()
	return parent as Skeleton3D if parent is Skeleton3D else null


func _select_skinned_meshes(
	root: Node3D,
	selection: Dictionary,
	hand_id: String
) -> Array[MeshInstance3D]:
	var selected: Array[MeshInstance3D] = []
	var by_hand_value: Variant = selection.get("mesh_node_paths_by_hand", {})
	var explicit_paths: Array = []
	if by_hand_value is Dictionary:
		var hand_value: Variant = Dictionary(by_hand_value).get(hand_id, [])
		if hand_value is Array:
			explicit_paths = hand_value
	if explicit_paths.is_empty():
		var common_value: Variant = selection.get("mesh_node_paths", [])
		if common_value is Array:
			explicit_paths = common_value
	if not explicit_paths.is_empty():
		for raw_path in explicit_paths:
			var node := root.get_node_or_null(NodePath(String(raw_path)))
			if node is MeshInstance3D:
				var mesh_instance := node as MeshInstance3D
				if mesh_instance.mesh != null and mesh_instance.skin != null:
					selected.append(mesh_instance)
		return selected
	if bool(selection.get("recursive_mesh_discovery", true)):
		_collect_skinned_recursive(root, selected)
	return selected


func _collect_skinned_recursive(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.skin != null:
			output.append(mesh_instance)
	for child in node.get_children():
		_collect_skinned_recursive(child, output)


func _relative_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			chain.push_front((current as Node3D).transform)
		current = current.get_parent()
	var result := Transform3D.IDENTITY
	for transform in chain:
		result = result * transform
	return result


func _profile_transform(presentation: Dictionary) -> Transform3D:
	var position := _vector3_from_array(presentation.get("position", []), Vector3.ZERO)
	var rotation_deg := _vector3_from_array(presentation.get("rotation_degrees", []), Vector3.ZERO)
	var scale := _vector3_from_array(presentation.get("scale", []), Vector3.ONE)
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(rotation_deg.x),
		deg_to_rad(rotation_deg.y),
		deg_to_rad(rotation_deg.z)
	)).scaled(scale)
	return Transform3D(basis, position)


func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)
