extends Node3D
class_name V0MVPSharedGraphicalScene

const CHECKPOINT: String = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
const PREDICATE: String = "MVP_SHARED_GRAPHICAL_SCENE"
const SCENE_PATH: String = "res://scenes/labs/mvp/v0_mvp_shared_graphical_scene.tscn"
const ACCEPTED_P7_SCENE_PATH: String = "res://scenes/labs/p7/p7_7_digging_playground.tscn"

@onready var accepted_p7_digging_slice: Node = get_node("AcceptedP7DiggingSlice")


func composition_contract() -> Dictionary:
	return {
		"checkpoint": CHECKPOINT,
		"declared_predicate": PREDICATE,
		"scene_path": SCENE_PATH,
		"accepted_p7_scene_path": ACCEPTED_P7_SCENE_PATH,
		"composition_only": true,
		"creates_canonical_foundation": false,
		"canonical_matter_truth": "MW4_MW10_EXISTING_CANONICAL_FOUNDATION",
		"canonical_item_truth": "CANONICAL_ITEM_GRAPH",
		"authority_route": "SM1_MW8_MW9_EXISTING_ROUTE",
		"persistence_truth": "EXISTING_PERSISTENCE_OWNER",
		"network_baseline": "SERVER_PREDICTED",
	}


func accepted_product_slice() -> Node:
	return accepted_p7_digging_slice
