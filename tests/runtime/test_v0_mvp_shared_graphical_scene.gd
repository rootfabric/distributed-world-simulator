extends SceneTree

const MVPScene = preload("res://scenes/labs/mvp/v0_mvp_shared_graphical_scene.tscn")
const MVPHost = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_shared_graphical_scene.gd")
const P7Donor = preload("res://scripts/runtime/networked_gameplay/p7/p7_digging_playground.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var instance: Node = MVPScene.instantiate()
	_assert(instance is Node3D, "MVP shared graphical root must be Node3D")
	_assert(instance.get_script() == MVPHost, "MVP scene is not bound to the MVP composition host")
	var donor: Node = instance.get_node_or_null("AcceptedP7DiggingSlice")
	_assert(donor != null, "Accepted P7.7 graphical donor is missing")
	if donor != null:
		_assert(donor.get_script() == P7Donor, "MVP host replaced the accepted P7.7 digging implementation")
	_assert(instance.get_child_count() == 1, "MVP1 introduced another top-level world owner beside the accepted P7.7 slice")
	var contract: Dictionary = instance.call("composition_contract")
	_assert(String(contract.get("checkpoint", "")) == "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE", "Wrong MVP checkpoint identity")
	_assert(String(contract.get("declared_predicate", "")) == "MVP_SHARED_GRAPHICAL_SCENE", "Wrong MVP1 predicate identity")
	_assert(String(contract.get("scene_path", "")) == "res://scenes/labs/mvp/v0_mvp_shared_graphical_scene.tscn", "Wrong canonical MVP scene path")
	_assert(String(contract.get("accepted_p7_scene_path", "")) == "res://scenes/labs/p7/p7_7_digging_playground.tscn", "MVP1 is not bound to the accepted P7.7 scene")
	_assert(bool(contract.get("composition_only", false)), "MVP1 must remain composition-only")
	_assert(not bool(contract.get("creates_canonical_foundation", true)), "MVP1 claims a new canonical foundation")
	_assert(String(contract.get("canonical_matter_truth", "")) == "MW4_MW10_EXISTING_CANONICAL_FOUNDATION", "MVP1 changed canonical Matter truth")
	_assert(String(contract.get("canonical_item_truth", "")) == "CANONICAL_ITEM_GRAPH", "MVP1 changed canonical Item Graph truth")
	_assert(String(contract.get("authority_route", "")) == "SM1_MW8_MW9_EXISTING_ROUTE", "MVP1 changed the seam authority route")
	_assert(String(contract.get("persistence_truth", "")) == "EXISTING_PERSISTENCE_OWNER", "MVP1 changed persistence ownership")
	_assert(String(contract.get("network_baseline", "")) == "SERVER_PREDICTED", "MVP1 changed network baseline")
	instance.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("V0 MVP shared graphical scene: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0 MVP shared graphical scene: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
