extends RefCounted

## ECO.EVO7 VIS4.8 — Diversity Evidence.
##
## Read-only quantitative evidence over already-published Descriptor V2 records.
## Live diversity is deliberately morphology-only: lineage, seed, yaw and VIS4.6
## scatter never count as biological/morphological diversity.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_8_diversity_evidence.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.8.R1"

const PRESENTATION_ONLY := true
const ECOLOGY_AUTHORITY := false
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false

const RENDERER_GATE := "CONTROLLED_ACCEPTANCE_ONLY"
const LIVE_STATUS_SUFFICIENT := "LIVE_DIVERSITY_SUFFICIENT"
const LIVE_STATUS_INSUFFICIENT := "LIVE_DIVERSITY_INSUFFICIENT"

const MIN_POPULATION := 8
const MIN_CLUSTER_COUNT := 3
const MIN_VARYING_FIELDS := 4
const MIN_RELATIVE_SPREAD := 0.05

# Fixed evidence bins. These are presentation-analysis bins, not taxa.
const METRICS := [
	{"name": "realized_height_m", "section": "functional_morphology", "bin": 0.25},
	{"name": "realized_crown_radius_m", "section": "functional_morphology", "bin": 0.10},
	{"name": "realized_crown_density", "section": "functional_morphology", "bin": 0.05},
	{"name": "leaf_area_index_proxy", "section": "functional_morphology", "bin": 0.10},
	{"name": "structural_investment", "section": "functional_morphology", "bin": 0.05},
	{"name": "realized_root_depth_m", "section": "functional_morphology", "bin": 0.10},
	{"name": "realized_root_spread_m", "section": "functional_morphology", "bin": 0.10},
	{"name": "apical_dominance", "section": "realized_topology", "bin": 0.05},
	{"name": "branch_probability", "section": "realized_topology", "bin": 0.05},
	{"name": "branch_angle_deg", "section": "realized_topology", "bin": 2.0},
	{"name": "branch_length_ratio", "section": "realized_topology", "bin": 0.05},
	{"name": "branching_depth", "section": "realized_topology", "bin": 1.0},
	{"name": "crown_spread_m", "section": "realized_topology", "bin": 0.10},
	{"name": "foliage_density", "section": "potential_morphology", "bin": 0.05},
]

static func build(
	generation: int,
	source_ecology_hash: String,
	descriptor_snapshot: Dictionary,
	render_identities: Array
) -> Dictionary:
	if generation < 1 or source_ecology_hash.length() != 64:
		return {}
	if int(descriptor_snapshot.get("generation", -1)) != generation:
		return {}
	if String(descriptor_snapshot.get("source_ecology_state_hash", "")) != source_ecology_hash:
		return {}
	var descriptor_values = descriptor_snapshot.get("descriptors")
	if not descriptor_values is Array:
		return {}
	var descriptors: Array = descriptor_values
	if int(descriptor_snapshot.get("descriptor_count", -1)) != descriptors.size():
		return {}
	if descriptors.is_empty() or render_identities.size() != descriptors.size():
		return {}

	var metric_values := {}
	for spec in METRICS:
		metric_values[String(spec["name"])] = []

	var cluster_counts := {}
	var unique_growth_graphs := {}
	var unique_render_descriptions := {}
	var unique_descriptor_hashes := {}
	var unique_lineages := {}

	for index in range(descriptors.size()):
		if not descriptors[index] is Dictionary or not render_identities[index] is Dictionary:
			return {}
		var descriptor: Dictionary = descriptors[index]
		var render_identity: Dictionary = render_identities[index]
		if not _validate_binding(descriptor, render_identity):
			return {}

		var signature_tokens := PackedStringArray()
		for spec in METRICS:
			var name := String(spec["name"])
			var value := _metric_value(descriptor, spec)
			if not is_finite(value):
				return {}
			Array(metric_values[name]).append(value)
			var bin_width := float(spec["bin"])
			var quantized := int(round(value / bin_width))
			signature_tokens.append("%s=%d" % [name, quantized])

		var cluster_signature := "|".join(signature_tokens).sha256_text()
		cluster_counts[cluster_signature] = int(cluster_counts.get(cluster_signature, 0)) + 1
		unique_growth_graphs[String(descriptor.get("growth_graph_hash", ""))] = true
		unique_render_descriptions[String(render_identity.get("render_description_hash", ""))] = true
		unique_descriptor_hashes[String(descriptor.get("descriptor_hash", ""))] = true
		unique_lineages[String(descriptor.get("lineage_id", ""))] = true

	var stats := {}
	var varying_field_count := 0
	for spec in METRICS:
		var name := String(spec["name"])
		var values: Array = metric_values[name]
		var field_stats := _stats(values, float(spec["bin"]))
		if field_stats.is_empty():
			return {}
		stats[name] = field_stats
		if bool(field_stats.get("varying", false)):
			varying_field_count += 1

	var sorted_clusters: Array = cluster_counts.keys()
	sorted_clusters.sort()
	var cluster_histogram: Array[Dictionary] = []
	for signature in sorted_clusters:
		cluster_histogram.append({
			"signature": String(signature),
			"count": int(cluster_counts[signature]),
		})

	var sufficient := (
		descriptors.size() >= MIN_POPULATION
		and cluster_counts.size() >= MIN_CLUSTER_COUNT
		and varying_field_count >= MIN_VARYING_FIELDS
	)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"ecology_authority": ECOLOGY_AUTHORITY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"generation": generation,
		"source_ecology_hash": source_ecology_hash,
		"source_descriptor_adapter_hash": String(descriptor_snapshot.get("adapter_hash", "")),
		"population": descriptors.size(),
		"metric_count": METRICS.size(),
		"metrics": stats,
		"varying_field_count": varying_field_count,
		"cluster_count": cluster_counts.size(),
		"cluster_histogram": cluster_histogram,
		"unique_descriptor_count": unique_descriptor_hashes.size(),
		"unique_growth_graph_count": unique_growth_graphs.size(),
		"unique_render_description_count": unique_render_descriptions.size(),
		"lineage_count_diagnostic_only": unique_lineages.size(),
		"renderer_fidelity_gate": RENDERER_GATE,
		"live_diversity_status": LIVE_STATUS_SUFFICIENT if sufficient else LIVE_STATUS_INSUFFICIENT,
		"thresholds": {
			"min_population": MIN_POPULATION,
			"min_cluster_count": MIN_CLUSTER_COUNT,
			"min_varying_fields": MIN_VARYING_FIELDS,
			"min_relative_spread": MIN_RELATIVE_SPREAD,
		},
		"archetype_classification": false,
		"lineage_counts_as_morphology": false,
		"seed_counts_as_morphology": false,
		"yaw_counts_as_morphology": false,
		"scatter_counts_as_morphology": false,
	}
	result["evidence_hash"] = compute_hash(result)
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
	if int(value.get("generation", -1)) < 1 or String(value.get("source_ecology_hash", "")).length() != 64:
		return false
	if int(value.get("population", 0)) <= 0 or int(value.get("metric_count", -1)) != METRICS.size():
		return false
	if not value.get("metrics") is Dictionary or not value.get("cluster_histogram") is Array:
		return false
	if String(value.get("renderer_fidelity_gate", "")) != RENDERER_GATE:
		return false
	if String(value.get("live_diversity_status", "")) not in [LIVE_STATUS_SUFFICIENT, LIVE_STATUS_INSUFFICIENT]:
		return false
	if bool(value.get("archetype_classification", true)):
		return false
	for key in [
		"lineage_counts_as_morphology",
		"seed_counts_as_morphology",
		"yaw_counts_as_morphology",
		"scatter_counts_as_morphology",
	]:
		if bool(value.get(key, true)):
			return false
	var metrics: Dictionary = value["metrics"]
	for spec in METRICS:
		var name := String(spec["name"])
		if not metrics.get(name) is Dictionary:
			return false
		var stat: Dictionary = metrics[name]
		for key in ["mean", "variance", "stddev", "min", "max", "range", "relative_spread", "bin_width"]:
			if not is_finite(float(stat.get(key, NAN))):
				return false
	return String(value.get("evidence_hash", "")) == compute_hash(value)


static func format_text(value: Dictionary) -> String:
	if not validate(value):
		return "VIS4.8 DIVERSITY EVIDENCE\nINVALID / UNAVAILABLE"
	var lines := PackedStringArray([
		"VIS4.8 DIVERSITY EVIDENCE",
		"generation: %d    population: %d" % [
			int(value["generation"]),
			int(value["population"]),
		],
		"renderer fidelity: CONTROLLED ACCEPTANCE GATE",
		"live diversity: %s" % String(value["live_diversity_status"]),
		"clusters: %d    varying fields: %d / %d" % [
			int(value["cluster_count"]),
			int(value["varying_field_count"]),
			int(value["metric_count"]),
		],
		"descriptor/growth/render descriptions: %d / %d / %d" % [
			int(value["unique_descriptor_count"]),
			int(value["unique_growth_graph_count"]),
			int(value["unique_render_description_count"]),
		],
		"lineages: %d (diagnostic only; NOT morphology evidence)" % int(value["lineage_count_diagnostic_only"]),
		"",
		"MORPHOLOGY VARIANCE",
	])
	var metrics: Dictionary = value["metrics"]
	for spec in METRICS:
		var name := String(spec["name"])
		var stat: Dictionary = metrics[name]
		lines.append("%s  mean %.4f  sd %.4f  range %.4f  rel %.3f  %s" % [
			name,
			float(stat["mean"]),
			float(stat["stddev"]),
			float(stat["range"]),
			float(stat["relative_spread"]),
			"VARIES" if bool(stat["varying"]) else "flat",
		])
	lines.append("")
	lines.append("NO TREE/BUSH/GRASS ARCHETYPES")
	lines.append("lineage / seed / yaw / visual scatter are excluded from morphology diversity")
	lines.append("evidence: %s" % String(value["evidence_hash"]))
	return "\n".join(lines)


static func compute_hash(value: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		str(int(value.get("generation", -1))),
		String(value.get("source_ecology_hash", "")),
		String(value.get("source_descriptor_adapter_hash", "")),
		str(int(value.get("population", 0))),
		str(int(value.get("metric_count", 0))),
		str(int(value.get("varying_field_count", 0))),
		str(int(value.get("cluster_count", 0))),
		str(int(value.get("unique_descriptor_count", 0))),
		str(int(value.get("unique_growth_graph_count", 0))),
		str(int(value.get("unique_render_description_count", 0))),
		String(value.get("renderer_fidelity_gate", "")),
		String(value.get("live_diversity_status", "")),
	])
	var metrics = value.get("metrics")
	if metrics is Dictionary:
		for spec in METRICS:
			var name := String(spec["name"])
			var stat: Dictionary = Dictionary(metrics.get(name, {}))
			tokens.append("%s|%.9f|%.9f|%.9f|%.9f|%.9f|%d" % [
				name,
				float(stat.get("mean", 0.0)),
				float(stat.get("variance", 0.0)),
				float(stat.get("min", 0.0)),
				float(stat.get("max", 0.0)),
				float(stat.get("relative_spread", 0.0)),
				int(bool(stat.get("varying", false))),
			])
	for item in Array(value.get("cluster_histogram", [])):
		if item is Dictionary:
			tokens.append("%s=%d" % [
				String(Dictionary(item).get("signature", "")),
				int(Dictionary(item).get("count", 0)),
			])
	return "\n".join(tokens).sha256_text()


static func _validate_binding(descriptor: Dictionary, render_identity: Dictionary) -> bool:
	var record_id := String(descriptor.get("record_id", ""))
	var descriptor_hash := String(descriptor.get("descriptor_hash", ""))
	var growth_graph_hash := String(descriptor.get("growth_graph_hash", ""))
	if record_id.is_empty() or descriptor_hash.length() != 64 or growth_graph_hash.length() != 64:
		return false
	if String(render_identity.get("record_id", "")) != record_id:
		return false
	if String(render_identity.get("source_descriptor_hash", "")) != descriptor_hash:
		return false
	if String(render_identity.get("source_growth_graph_hash", "")) != growth_graph_hash:
		return false
	if String(render_identity.get("render_description_hash", "")).length() != 64:
		return false
	for section in ["functional_morphology", "realized_topology", "potential_morphology"]:
		if not descriptor.get(section) is Dictionary:
			return false
	return true


static func _metric_value(descriptor: Dictionary, spec: Dictionary) -> float:
	var section_value = descriptor.get(String(spec["section"]))
	if not section_value is Dictionary:
		return NAN
	var raw = Dictionary(section_value).get(String(spec["name"]))
	if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
		return NAN
	return float(raw)


static func _stats(values: Array, bin_width: float) -> Dictionary:
	if values.is_empty() or bin_width <= 0.0:
		return {}
	var sum := 0.0
	var min_value := INF
	var max_value := -INF
	for raw in values:
		var value := float(raw)
		if not is_finite(value):
			return {}
		sum += value
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)
	var mean := sum / float(values.size())
	var variance_sum := 0.0
	for raw in values:
		var delta := float(raw) - mean
		variance_sum += delta * delta
	var variance := variance_sum / float(values.size())
	var stddev := sqrt(maxf(0.0, variance))
	var range_value := max_value - min_value
	var denominator := maxf(absf(mean), bin_width)
	var relative_spread := range_value / denominator
	var varying := range_value + 0.000000001 >= bin_width and relative_spread >= MIN_RELATIVE_SPREAD
	return {
		"mean": mean,
		"variance": variance,
		"stddev": stddev,
		"min": min_value,
		"max": max_value,
		"range": range_value,
		"relative_spread": relative_spread,
		"bin_width": bin_width,
		"varying": varying,
	}
