extends SceneTree
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Skeleton = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const EXPECTED_HASH := "6470722b770afee48def9ee06cc44a36640734abc9fc362a2fed6eb648779451"
func _init() -> void:
	var graph := Skeleton.build(Traits.create_default(), 959597643576420676)
	var failures := 0
	var assertions := 4
	if graph.is_empty(): failures += 1
	if String(graph.get("graph_hash", "")) != EXPECTED_HASH: failures += 1
	if not bool(graph.get("derived_representation", false)): failures += 1
	if int(graph.get("metrics", {}).get("segment_count", 0)) <= 0: failures += 1
	if failures == 0:
		print("ECO.PH1 Restart Replay: PASS (%d assertions) graph=%s" % [assertions, EXPECTED_HASH]); quit(0); return
	push_error("ECO.PH1 Restart Replay: FAIL (%d/%d) actual=%s" % [failures, assertions, String(graph.get("graph_hash", ""))]); quit(1)
