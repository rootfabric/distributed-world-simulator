extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_patch_colonization_experiment_v1.gd")

var assertions := 0

func _init() -> void:
	var first := Experiment.run()
	var second := Experiment.run()
	_check(not first.is_empty(), "experiment result exists")
	_check(not second.is_empty(), "repeat result exists")
	if first.is_empty() or second.is_empty():
		_finish(false)
		return

	_check(String(first.get("aggregate_hash", "")) == String(second.get("aggregate_hash", "")), "same-process aggregate deterministic")
	_check(String(first.get("aggregate_hash", "")).length() == 64, "aggregate hash shape")
	_check(String(first.get("p2_3_parent_hash", "")) == Experiment.ACCEPTED_P2_3_HASH, "accepted P2.3 parent exact")
	_check(int(first.get("total_emitted", 0)) == 2560, "expected eastward emitted seed cardinality")
	_check(int(first["total_emitted"]) == int(first["total_retained"]) + int(first["total_routed"]) + int(first["total_unresolved"]), "network migration conservation exact")

	_check(int(first["near_short_arrived"]) > 0, "near patch receives short disperser")
	_check(int(first["near_long_arrived"]) > 0, "near patch receives long disperser")
	_check(int(first["far_short_arrived"]) == 0, "far isolated patch excludes short disperser")
	_check(int(first["far_long_arrived"]) > 0, "far isolated patch receives long disperser")
	_check(int(first["near_short_recruited"]) > 0, "short disperser establishes in near patch")
	_check(int(first["near_long_recruited"]) > 0, "long disperser establishes in near patch")
	_check(int(first["far_long_recruited"]) > 0, "long disperser establishes in far patch")
	_check(int(first["far_short_recruited"]) == 0, "short disperser cannot recruit without arrival")
	_check(int(first["near_colonized_lineages"]) == 2, "near patch colonized by both causal strategies")
	_check(int(first["far_colonized_lineages"]) == 1, "far patch colonized by one dispersal-capable strategy")
	_check(int(first["near_recruited"]) > int(first["far_recruited"]), "isolation reduces total recruitment")
	_check(float(first["far_long_share"]) > float(first["near_long_share"]), "isolation filters community toward long disperser")
	_check(int(first["west_routed"]) == 0, "opposed transport direction prevents east-target migration")
	_check(int(first["total_routed"]) > int(first["west_routed"]), "migration responds to transport direction")

	var totals: Dictionary = first["totals"]
	for patch_id in [Experiment.NEAR, Experiment.FAR]:
		var patch_totals: Dictionary = totals[patch_id]
		for lineage in [Experiment.SHORT, Experiment.LONG]:
			var counts: Dictionary = patch_totals[lineage]
			_check(int(counts["arrived"]) == int(counts["recruited"]) + int(counts["bank"]) + int(counts["failed"]), "target settlement conservation exact")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_patch_migration_v1.gd")
	_check(source.find("biome") == -1, "no biome lookup in migration kernel")
	_check(source.find("species_table") == -1, "no species placement table in migration kernel")
	_check(source.find("disturbance_event") == -1, "no P2.5 disturbance scheduler")

	print("ECO.EVO1-P2.4 near_arrived=%d far_arrived=%d near_recruited=%d far_recruited=%d" % [int(first["near_arrived"]), int(first["far_arrived"]), int(first["near_recruited"]), int(first["far_recruited"])])
	print("ECO.EVO1-P2.4 near_short=%d near_long=%d far_short=%d far_long=%d" % [int(first["near_short_recruited"]), int(first["near_long_recruited"]), int(first["far_short_recruited"]), int(first["far_long_recruited"])])
	print("ECO.EVO1-P2.4 near_long_share=%.12f far_long_share=%.12f near_lineages=%d far_lineages=%d west_routed=%d" % [float(first["near_long_share"]), float(first["far_long_share"]), int(first["near_colonized_lineages"]), int(first["far_colonized_lineages"]), int(first["west_routed"])])
	print("ECO.EVO1-P2.4 Patch Colonization / Isolation / Migration: PASS (%d assertions) aggregate_hash=%s p2_3=%s" % [assertions, String(first["aggregate_hash"]), String(first["p2_3_parent_hash"])])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.4 assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)
