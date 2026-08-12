extends RefCounted

const PROVIDER_ID := "synthetic_compatible_visual_v1"
const MODE := "SYNTHETIC_COMPATIBLE"
const SKELETON_SCHEMA := "planet_simulator.fpe_hand_skeleton.v1"

var install_calls := 0
var last_hand_id := ""
var last_bone_count := 0
var last_layer := -1


func install_visuals(
	skeleton: Skeleton3D,
	hand_id: String,
	viewmodel_layer_index: int
) -> Dictionary:
	install_calls += 1
	last_hand_id = hand_id
	last_bone_count = skeleton.get_bone_count() if skeleton != null else 0
	last_layer = viewmodel_layer_index
	if skeleton == null or last_bone_count < 17:
		return {
			"success": false,
			"error_code": "SYNTHETIC_SKELETON_INCOMPATIBLE",
			"details": {},
		}

	var visual := MeshInstance3D.new()
	visual.name = "SyntheticCompatibleHandVisual"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.05, 0.18)
	visual.mesh = mesh
	visual.layers = 0
	visual.set_layer_mask_value(viewmodel_layer_index, true)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(visual)
	return {
		"success": true,
		"error_code": "",
		"details": {
			"visuals": [visual],
			"report": create_report(1),
		},
	}


func create_report(installed_visual_count: int = 0) -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_hand_visual_provider.v1",
		"provider_id": PROVIDER_ID,
		"mode": MODE,
		"compatible_skeleton_schema": SKELETON_SCHEMA,
		"installed_visual_count": installed_visual_count,
		"bone_driven": true,
		"substitutable": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}
