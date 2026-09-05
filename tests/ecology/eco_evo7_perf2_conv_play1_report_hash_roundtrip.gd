extends SceneTree

const Report = preload("res://scripts/ecology/perf/eco_evo7_perf2_conv_play1_integrated_report_v1.gd")


func _init() -> void:
	var sample := {
		"repetition": 0,
		"initialize_ms": 6971.196,
		"view_sequence_ms": 100.0,
		"lifecycle_ms": 6195.642,
		"initial_surface_rebuild_ms": 489.451,
		"return_surface_rebuild_ms": 481.563,
		"max_view_ms": 25.0,
		"max_bounded_operation_ms": 489.451,
		"source_ecology_hash": "a".repeat(64),
		"composition_hash": "b".repeat(64),
		"macro_bridge_hash": "c".repeat(64),
		"descriptor_adapter_hash": "d".repeat(64),
		"lifecycle_green": true,
		"truth_green": true,
		"ecology_identity_drift": false,
		"macro_records": 63,
		"macro_visible": 62,
		"ground_cover": 4500,
		"rocks": 146,
		"render_recenter_count": 2,
		"earth_rebuild_count": 2,
		"region_roundtrip_count": 1,
		"composite_initialize_timing_observational_only": true,
		"composite_lifecycle_timing_observational_only": true,
	}
	var samples: Array = []
	for i in range(Report.REPETITIONS):
		var current: Dictionary = sample.duplicate(true)
		current["repetition"] = i
		samples.append(current)

	var immutable := {
		"perf2_conv_accepted": true,
		"perf2_conv_runtime_head": Report.PERF2_CONV_RUNTIME_HEAD,
		"perf2_conv_runtime_tree": Report.PERF2_CONV_RUNTIME_TREE,
		"perf2_conv_accepted_control_head": Report.PERF2_CONV_ACCEPTED_CONTROL_HEAD,
		"perf2_conv_report_hash": Report.PERF2_CONV_REPORT_HASH,
		"perf2_conv_p50_ratio": Report.PERF2_CONV_P50_RATIO,
		"perf2_conv_p95_ratio": Report.PERF2_CONV_P95_RATIO,
		"perf2_conv_max_combined_ms": Report.PERF2_CONV_MAX_COMBINED_MS,
		"vis5_5_closed": true,
		"vis5_5_executable_head": Report.VIS5_5_EXECUTABLE_HEAD,
		"vis5_5_executable_tree": Report.VIS5_5_EXECUTABLE_TREE,
		"vis5_5_closure_head": Report.VIS5_5_CLOSURE_HEAD,
		"vis5_5_source_sha256": Report.VIS5_5_SOURCE_SHA256,
		"vis5_5_capture_bundle_hash": Report.VIS5_5_CAPTURE_BUNDLE_HASH,
		"vis5_5_manifest_sha256": Report.VIS5_5_MANIFEST_SHA256,
		"vis5_5_handoff_hash": Report.VIS5_5_HANDOFF_HASH,
	}
	var target := {
		"head": "e".repeat(40),
		"tree": "f".repeat(40),
	}
	var report := Report.build(samples, target, immutable)
	if report.is_empty() or not Report.validate(report):
		push_error("PLAY1 hash regression: initial report invalid")
		quit(1)
		return

	var parsed = JSON.parse_string(JSON.stringify(report, "\t"))
	if not parsed is Dictionary or not Report.validate(parsed):
		push_error("PLAY1 hash regression: JSON round-trip invalid")
		quit(2)
		return

	if String(report["report_hash"]) != Report.compute_hash(parsed):
		push_error("PLAY1 hash regression: hash drift after JSON round-trip")
		quit(3)
		return

	print("ECO.EVO7 PLAY1 REPORT HASH ROUND-TRIP: PASS hash=%s" % String(report["report_hash"]))
	quit(0)
