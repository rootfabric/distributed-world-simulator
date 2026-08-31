extends RefCounted

## ECO.EVO7 VIS4.9 — Performance / LOD evidence.
##
## Read-only presentation diagnostics over accepted PH5 counters + PLAY0 frame
## observations. Wall-clock timings and FPS are explicitly observational and are
## excluded from the deterministic structural evidence hash.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_9_performance_lod_evidence.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.9.R1"

const PRESENTATION_ONLY := true
const ECOLOGY_AUTHORITY := false
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false

const PERF2_CONVERGENCE_REQUIRED := true

const TIER_ORDER: Array[String] = [
	"TIER_0_FULL",
	"TIER_1_REDUCED",
	"TIER_2_CANOPY",
	"TIER_3_IMPOSTOR",
	"TIER_4_POPULATION_ONLY",
]


static func build(renderer_perf: Dictionary, frame_perf: Dictionary) -> Dictionary:
	if renderer_perf.is_empty() or frame_perf.is_empty():
		return {}
	var generation := int(renderer_perf.get("generation", -1))
	var source_ecology_hash := String(renderer_perf.get("source_ecology_hash", ""))
	if generation < 1 or source_ecology_hash.length() != 64:
		return {}
	if not bool(renderer_perf.get("presentation_only", false)):
		return {}
	if not bool(renderer_perf.get("timings_diagnostic_only", false)):
		return {}
	if not bool(renderer_perf.get("draw_calls_are_proxy", false)):
		return {}

	var tier_value = renderer_perf.get("tier_counts")
	if not tier_value is Dictionary:
		return {}
	var tier_counts: Dictionary = Dictionary(tier_value).duplicate(true)
	var tier_total := 0
	for tier in TIER_ORDER:
		var count := int(tier_counts.get(tier, -1))
		if count < 0:
			return {}
		tier_total += count
	if tier_total != int(renderer_perf.get("record_count", -1)):
		return {}

	for key in [
		"visible_individual_count",
		"materialization_cache_entries",
		"materialization_cache_lookup_entries",
		"materialization_cache_eviction_count",
		"materialization_cache_hit_count",
		"materialization_cache_miss_count",
		"materialization_build_count",
		"snapshot_apply_count",
		"lod_update_count",
		"lod_switch_count",
		"bridge_chain_build_count",
		"branch_primitive_count",
		"foliage_instance_count",
		"far_primitive_count",
		"cost_units",
		"draw_call_proxy",
	]:
		if int(renderer_perf.get(key, -1)) < 0:
			return {}

	for key in [
		"materialization_cache_hit_rate",
		"materialization_total_ms",
		"materialization_avg_ms",
		"materialization_max_ms",
		"snapshot_apply_total_ms",
		"snapshot_apply_avg_ms",
		"snapshot_apply_max_ms",
		"lod_update_total_ms",
		"lod_update_avg_ms",
		"lod_update_max_ms",
		"growth_graph_ms",
		"render_description_ms",
		"representation_ms",
		"bridge_materializer_ms",
	]:
		var value := float(renderer_perf.get(key, NAN))
		if not is_finite(value) or value < 0.0:
			return {}

	for key in ["sample_count", "average_frame_ms", "min_frame_ms", "max_frame_ms", "estimated_fps"]:
		var value := float(frame_perf.get(key, NAN))
		if not is_finite(value) or value < 0.0:
			return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"ecology_authority": ECOLOGY_AUTHORITY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"perf2_convergence_required": PERF2_CONVERGENCE_REQUIRED,
		"generation": generation,
		"source_ecology_hash": source_ecology_hash,
		"record_count": int(renderer_perf["record_count"]),
		"visible_individual_count": int(renderer_perf["visible_individual_count"]),
		"tier_counts": tier_counts,
		"materialization_cache_entries": int(renderer_perf["materialization_cache_entries"]),
		"materialization_cache_lookup_entries": int(renderer_perf["materialization_cache_lookup_entries"]),
		"materialization_cache_eviction_count": int(renderer_perf["materialization_cache_eviction_count"]),
		"materialization_cache_hit_count": int(renderer_perf["materialization_cache_hit_count"]),
		"materialization_cache_miss_count": int(renderer_perf["materialization_cache_miss_count"]),
		"materialization_cache_hit_rate": float(renderer_perf["materialization_cache_hit_rate"]),
		"materialization_build_count": int(renderer_perf["materialization_build_count"]),
		"materialization_total_ms": float(renderer_perf["materialization_total_ms"]),
		"materialization_avg_ms": float(renderer_perf["materialization_avg_ms"]),
		"materialization_max_ms": float(renderer_perf["materialization_max_ms"]),
		"snapshot_apply_count": int(renderer_perf["snapshot_apply_count"]),
		"snapshot_apply_total_ms": float(renderer_perf["snapshot_apply_total_ms"]),
		"snapshot_apply_avg_ms": float(renderer_perf["snapshot_apply_avg_ms"]),
		"snapshot_apply_max_ms": float(renderer_perf["snapshot_apply_max_ms"]),
		"lod_update_count": int(renderer_perf["lod_update_count"]),
		"lod_update_total_ms": float(renderer_perf["lod_update_total_ms"]),
		"lod_update_avg_ms": float(renderer_perf["lod_update_avg_ms"]),
		"lod_update_max_ms": float(renderer_perf["lod_update_max_ms"]),
		"lod_switch_count": int(renderer_perf["lod_switch_count"]),
		"bridge_chain_build_count": int(renderer_perf["bridge_chain_build_count"]),
		"growth_graph_ms": float(renderer_perf["growth_graph_ms"]),
		"render_description_ms": float(renderer_perf["render_description_ms"]),
		"representation_ms": float(renderer_perf["representation_ms"]),
		"bridge_materializer_ms": float(renderer_perf["bridge_materializer_ms"]),
		"branch_primitive_count": int(renderer_perf["branch_primitive_count"]),
		"foliage_instance_count": int(renderer_perf["foliage_instance_count"]),
		"far_primitive_count": int(renderer_perf["far_primitive_count"]),
		"cost_units": int(renderer_perf["cost_units"]),
		"draw_call_proxy": int(renderer_perf["draw_call_proxy"]),
		"draw_calls_are_proxy": true,
		"timings_diagnostic_only": true,
		"fps_observational_only": true,
		"frame_sample_count": int(frame_perf.get("sample_count", 0)),
		"average_frame_ms": float(frame_perf.get("average_frame_ms", 0.0)),
		"min_frame_ms": float(frame_perf.get("min_frame_ms", 0.0)),
		"max_frame_ms": float(frame_perf.get("max_frame_ms", 0.0)),
		"estimated_fps": float(frame_perf.get("estimated_fps", 0.0)),
	}
	result["structural_evidence_hash"] = compute_structural_hash(result)
	return result if validate(result) else {}


static func validate(value: Dictionary) -> bool:
	if String(value.get("schema", "")) != SCHEMA:
		return false
	if String(value.get("version", "")) != VERSION or String(value.get("revision", "")) != REVISION:
		return false
	if not bool(value.get("presentation_only", false)):
		return false
	if bool(value.get("ecology_authority", true)):
		return false
	if bool(value.get("network_authority", true)) or bool(value.get("persistence_authority", true)):
		return false
	if not bool(value.get("perf2_convergence_required", false)):
		return false
	if not bool(value.get("draw_calls_are_proxy", false)):
		return false
	if not bool(value.get("timings_diagnostic_only", false)) or not bool(value.get("fps_observational_only", false)):
		return false
	if int(value.get("generation", -1)) < 1 or String(value.get("source_ecology_hash", "")).length() != 64:
		return false
	var tier_value = value.get("tier_counts")
	if not tier_value is Dictionary:
		return false
	var tier_counts: Dictionary = tier_value
	var total := 0
	for tier in TIER_ORDER:
		var count := int(tier_counts.get(tier, -1))
		if count < 0:
			return false
		total += count
	if total != int(value.get("record_count", -1)):
		return false
	if int(value.get("visible_individual_count", -1)) < 0 or int(value.get("visible_individual_count", 0)) > total:
		return false
	var expected_visible := total - int(tier_counts.get("TIER_4_POPULATION_ONLY", 0))
	if int(value.get("visible_individual_count", -1)) != expected_visible:
		return false

	for key in [
		"materialization_cache_entries",
		"materialization_cache_lookup_entries",
		"materialization_cache_eviction_count",
		"materialization_cache_hit_count",
		"materialization_cache_miss_count",
		"materialization_build_count",
		"snapshot_apply_count",
		"lod_update_count",
		"lod_switch_count",
		"bridge_chain_build_count",
		"branch_primitive_count",
		"foliage_instance_count",
		"far_primitive_count",
		"cost_units",
		"draw_call_proxy",
		"frame_sample_count",
	]:
		if int(value.get(key, -1)) < 0:
			return false

	var hit_count := int(value.get("materialization_cache_hit_count", 0))
	var miss_count := int(value.get("materialization_cache_miss_count", 0))
	var lookups := hit_count + miss_count
	var expected_hit_rate := float(hit_count) / float(lookups) if lookups > 0 else 0.0
	if not is_equal_approx(float(value.get("materialization_cache_hit_rate", NAN)), expected_hit_rate):
		return false
	if int(value.get("materialization_build_count", -1)) != miss_count:
		return false

	for key in [
		"materialization_total_ms",
		"materialization_avg_ms",
		"materialization_max_ms",
		"snapshot_apply_total_ms",
		"snapshot_apply_avg_ms",
		"snapshot_apply_max_ms",
		"lod_update_total_ms",
		"lod_update_avg_ms",
		"lod_update_max_ms",
		"growth_graph_ms",
		"render_description_ms",
		"representation_ms",
		"bridge_materializer_ms",
		"average_frame_ms",
		"min_frame_ms",
		"max_frame_ms",
		"estimated_fps",
	]:
		var number := float(value.get(key, NAN))
		if not is_finite(number) or number < 0.0:
			return false

	if int(value.get("frame_sample_count", 0)) > 0:
		if float(value.get("average_frame_ms", 0.0)) <= 0.0:
			return false
		if float(value.get("max_frame_ms", 0.0)) < float(value.get("min_frame_ms", 0.0)):
			return false
		if float(value.get("estimated_fps", 0.0)) <= 0.0:
			return false

	return String(value.get("structural_evidence_hash", "")) == compute_structural_hash(value)


static func format_text(value: Dictionary) -> String:
	if not validate(value):
		return "VIS4.9 PERFORMANCE / LOD\nINVALID / UNAVAILABLE"
	var tiers: Dictionary = value["tier_counts"]
	return "\n".join(PackedStringArray([
		"VIS4.9 PERFORMANCE / LOD",
		"generation: %d    plants: %d    visible: %d" % [
			int(value["generation"]), int(value["record_count"]), int(value["visible_individual_count"]),
		],
		"tiers T0/T1/T2/T3/T4: %d / %d / %d / %d / %d" % [
			int(tiers["TIER_0_FULL"]),
			int(tiers["TIER_1_REDUCED"]),
			int(tiers["TIER_2_CANOPY"]),
			int(tiers["TIER_3_IMPOSTOR"]),
			int(tiers["TIER_4_POPULATION_ONLY"]),
		],
		"",
		"WORKLOAD",
		"branches: %d    foliage instances: %d    far primitives: %d" % [
			int(value["branch_primitive_count"]),
			int(value["foliage_instance_count"]),
			int(value["far_primitive_count"]),
		],
		"cost units: %d    draw-call proxy: %d (PROXY, not renderer draw-call truth)" % [
			int(value["cost_units"]), int(value["draw_call_proxy"]),
		],
		"",
		"CACHE / LOD",
		"cache materializations/lookups: %d / %d    evictions: %d" % [
			int(value["materialization_cache_entries"]),
			int(value["materialization_cache_lookup_entries"]),
			int(value["materialization_cache_eviction_count"]),
		],
		"hits: %d    misses/builds: %d    hit rate: %.3f" % [
			int(value["materialization_cache_hit_count"]),
			int(value["materialization_cache_miss_count"]),
			float(value["materialization_cache_hit_rate"]),
		],
		"LOD updates: %d    switches: %d    avg/max update: %.3f / %.3f ms" % [
			int(value["lod_update_count"]),
			int(value["lod_switch_count"]),
			float(value["lod_update_avg_ms"]),
			float(value["lod_update_max_ms"]),
		],
		"",
		"PH5 BUILD TIMINGS (diagnostic / non-deterministic)",
		"GrowthGraph: %.3f ms    RenderDescription: %.3f ms" % [
			float(value["growth_graph_ms"]), float(value["render_description_ms"]),
		],
		"Representation: %.3f ms    Materializer: %.3f ms" % [
			float(value["representation_ms"]), float(value["bridge_materializer_ms"]),
		],
		"materialization total/avg/max: %.3f / %.3f / %.3f ms" % [
			float(value["materialization_total_ms"]),
			float(value["materialization_avg_ms"]),
			float(value["materialization_max_ms"]),
		],
		"snapshot apply avg/max: %.3f / %.3f ms" % [
			float(value["snapshot_apply_avg_ms"]), float(value["snapshot_apply_max_ms"]),
		],
		"",
		"FRAME OBSERVATION (not PERF2 acceptance)",
		"samples: %d    avg/min/max: %.3f / %.3f / %.3f ms    est FPS: %.1f" % [
			int(value["frame_sample_count"]),
			float(value["average_frame_ms"]),
			float(value["min_frame_ms"]),
			float(value["max_frame_ms"]),
			float(value["estimated_fps"]),
		],
		"",
		"PERF2.CONV STILL REQUIRED FOR PLAY1 ACCEPTANCE",
		"structural evidence: %s" % String(value["structural_evidence_hash"]),
	]))


static func compute_structural_hash(value: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		str(int(value.get("generation", -1))),
		String(value.get("source_ecology_hash", "")),
		str(int(value.get("record_count", 0))),
		str(int(value.get("visible_individual_count", 0))),
	])
	var tiers = value.get("tier_counts")
	if tiers is Dictionary:
		for tier in TIER_ORDER:
			tokens.append("%s=%d" % [tier, int(Dictionary(tiers).get(tier, 0))])
	for key in [
		"materialization_cache_entries",
		"materialization_cache_lookup_entries",
		"materialization_cache_eviction_count",
		"materialization_cache_hit_count",
		"materialization_cache_miss_count",
		"materialization_build_count",
		"snapshot_apply_count",
		"lod_update_count",
		"lod_switch_count",
		"bridge_chain_build_count",
		"branch_primitive_count",
		"foliage_instance_count",
		"far_primitive_count",
		"cost_units",
		"draw_call_proxy",
	]:
		tokens.append("%s=%d" % [key, int(value.get(key, 0))])
	return "|".join(tokens).sha256_text()
