extends SceneTree

const PlaygroundScene = preload(
	"res://scenes/labs/p7/p7_7_digging_playground.tscn"
)
const Router = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_seam_multi_region_composition.gd"
)

var assertions := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var playground = PlaygroundScene.instantiate()
	root.add_child(playground)
	await process_frame

	var before: Dictionary = playground.playground_report()
	_assert(bool(before.get("configured", false)), "Digging Playground configured")
	_assert(bool(before.get("tool_equipped", false)), "canonical mining tool equipped")
	_assert(not String(before.get("tool_id", "")).is_empty(), "canonical tool id available")
	_assert(not String(before.get("matter_store_hash", "")).is_empty(), "Matter store hash available")
	_assert(not String(before.get("item_graph_checksum", "")).is_empty(), "Item Graph checksum available")
	_assert(int(before.get("presenter_count", 0)) > 0, "canonical Matter presenter built")

	var after: Dictionary = playground.execute_single_region_dig_for_test()
	await process_frame
	after = playground.playground_report()

	var result: Dictionary = Dictionary(after.get("last_dig_result", {}))
	_assert(bool(result.get("success", false)), "P7.7-A live dig succeeds")
	var details: Dictionary = Dictionary(result.get("details", {}))
	_assert(
		String(details.get("route", "")) == Router.ROUTE_SINGLE_REGION,
		"live dig uses P7.6 single-region route"
	)
	_assert(not bool(details.get("mw10_invoked", true)), "live P7.7-A never invokes MW10")
	_assert(int(details.get("changed_brick_count", 0)) > 0, "canonical MW4 changes Matter bricks")
	_assert(float(details.get("removed_mass_kg", 0.0)) > 0.0, "canonical MW4 removes physical mass")
	_assert(
		String(details.get("visible_hole_source", "")) == "CANONICAL_MATTER_RESULT",
		"visible hole derives from canonical Matter result"
	)
	_assert(
		String(details.get("inventory_source", "")) == "CANONICAL_ITEM_GRAPH",
		"material lands in canonical Item Graph"
	)
	var material: Dictionary = Dictionary(details.get("material_delivery", {}))
	var delivery: Dictionary = Dictionary(material.get("delivery", {}))
	_assert(int(delivery.get("output_quantity", 0)) > 0, "excavated material produces Item Graph output")
	_assert(not bool(delivery.get("replay", true)), "first material delivery is fresh")
	var invalidation: Dictionary = Dictionary(details.get("representation_invalidation", {}))
	_assert(int(invalidation.get("presenter_count", 0)) > 0, "visible presenter rebuilt after canonical mutation")

	_assert(
		String(after.get("matter_store_hash", "")) != String(before.get("matter_store_hash", "")),
		"canonical Matter store hash changes after dig"
	)
	_assert(
		String(after.get("item_graph_checksum", "")) != String(before.get("item_graph_checksum", "")),
		"canonical Item Graph checksum changes after material delivery"
	)
	_assert(
		int(after.get("item_graph_revision", -1)) > int(before.get("item_graph_revision", -1)),
		"canonical Item Graph revision advances"
	)
	_assert(int(after.get("presenter_count", 0)) > 0, "visible canonical Matter presenter remains active")

	playground.queue_free()
	await process_frame
	if failures.is_empty():
		print("V0-P7.7-A Digging Playground: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("V0-P7.7-A Digging Playground: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size()
		])
		quit(1)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failures.append(message)
