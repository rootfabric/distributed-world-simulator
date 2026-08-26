extends RefCounted

## ECO.EVO7 LS2.1 — read-only divergence observer.
##
## Consumes LS1/LS2 snapshots only. It never mutates plants, never samples or
## writes the world directly, never reproduces, and owns no persistence/network/
## XFER authority. The observer exists to separate three things that are easy to
## confuse visually:
##   1. environmental heterogeneity;
##   2. plastic phenotype differences under one heritable population;
##   3. heritable population divergence caused by selection over generations.

const SCHEMA := "distributed_world_simulator.ecology.evo7_ls21_divergence_observer.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS2.1.1"
const MODE := "READ_ONLY_MEASUREMENT"
const TRAIT_KEYS := [
	"mean_water_satisfaction",
	"mean_lai",
	"mean_root_depth_m",
	"mean_height_m",
	"mean_crown_radius_m",
	"mean_crown_density",
	"mean_root_shoot_ratio",
	"mean_structural_investment",
]

static func observe(initial_snapshot: Dictionary, current_snapshot: Dictionary) -> Dictionary:
	if initial_snapshot.is_empty() or current_snapshot.is_empty():
		return {}
	var initial_zones := Array(initial_snapshot.get("zones", []))
	var current_zones := Array(current_snapshot.get("zones", []))
	if initial_zones.size() < 2 or current_zones.size() != initial_zones.size():
		return {}

	var initial_population_hashes := {}
	for zone_value in initial_zones:
		var zone: Dictionary = zone_value
		var population_hash := String(zone.get("population_hash", ""))
		if population_hash.is_empty():
			return {}
		initial_population_hashes[population_hash] = true

	var zone_metrics: Array[Dictionary] = []
	var population_hashes := {}
	var dominant_lineages := {}
	var moisture_min := INF
	var moisture_max := -INF
	var sunlight_min := INF
	var sunlight_max := -INF
	var temperature_min := INF
	var temperature_max := -INF

	for zone_value in current_zones:
		var zone: Dictionary = zone_value
		var population_hash := String(zone.get("population_hash", ""))
		if population_hash.is_empty():
			return {}
		population_hashes[population_hash] = true
		var dominant_lineage := String(zone.get("dominant_lineage", ""))
		if not dominant_lineage.is_empty():
			dominant_lineages[dominant_lineage] = true

		var members := Array(zone.get("members", []))
		var phenotype_hashes := {}
		var lineage_ids := {}
		for member_value in members:
			var member: Dictionary = member_value
			var phenotype_hash := String(member.get("phenotype_hash", ""))
			if not phenotype_hash.is_empty():
				phenotype_hashes[phenotype_hash] = true
			var lineage_id := String(member.get("lineage_id", ""))
			if not lineage_id.is_empty():
				lineage_ids[lineage_id] = true

		var moisture := float(zone.get("moisture", 0.0))
		var sunlight := float(zone.get("sunlight", 0.0))
		var temperature_c := float(zone.get("temperature_c", 0.0))
		moisture_min = minf(moisture_min, moisture)
		moisture_max = maxf(moisture_max, moisture)
		sunlight_min = minf(sunlight_min, sunlight)
		sunlight_max = maxf(sunlight_max, sunlight)
		temperature_min = minf(temperature_min, temperature_c)
		temperature_max = maxf(temperature_max, temperature_c)

		var metric := {
			"zone_index": int(zone.get("zone_index", zone_metrics.size())),
			"label": String(zone.get("label", "ZONE")),
			"population_hash": population_hash,
			"dominant_lineage": dominant_lineage,
			"dominant_lineage_count": int(zone.get("dominant_lineage_count", 0)),
			"lineage_richness": lineage_ids.size(),
			"phenotype_richness": phenotype_hashes.size(),
			"moisture": moisture,
			"sunlight": sunlight,
			"temperature_c": temperature_c,
		}
		for trait_key in TRAIT_KEYS:
			metric[trait_key] = float(zone.get(trait_key, 0.0))
		zone_metrics.append(metric)

	var pairwise: Array[Dictionary] = []
	var trait_distance_sum := 0.0
	var max_trait_distance := 0.0
	var population_diverged_pairs := 0
	for a in range(zone_metrics.size()):
		for b in range(a + 1, zone_metrics.size()):
			var za: Dictionary = zone_metrics[a]
			var zb: Dictionary = zone_metrics[b]
			var trait_distance := _trait_distance(za, zb)
			var population_equal := String(za["population_hash"]) == String(zb["population_hash"])
			if not population_equal:
				population_diverged_pairs += 1
			trait_distance_sum += trait_distance
			max_trait_distance = maxf(max_trait_distance, trait_distance)
			pairwise.append({
				"a": int(za["zone_index"]),
				"b": int(zb["zone_index"]),
				"population_equal": population_equal,
				"trait_distance": trait_distance,
				"moisture_delta": absf(float(za["moisture"]) - float(zb["moisture"])),
				"sunlight_delta": absf(float(za["sunlight"]) - float(zb["sunlight"])),
			})

	var candidate_pool_hashes := Array(current_snapshot.get("first_candidate_pool_hashes", []))
	var candidate_pool_identity_observed := candidate_pool_hashes.size() == current_zones.size()
	var candidate_pool_identity_equal := candidate_pool_identity_observed and _all_strings_equal(candidate_pool_hashes)
	var mean_trait_distance := trait_distance_sum / float(pairwise.size()) if not pairwise.is_empty() else 0.0

	var report := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"generation": int(current_snapshot.get("generation", -1)),
		"evolution_enabled": bool(current_snapshot.get("evolution_enabled", false)),
		"initial_common_population": initial_population_hashes.size() == 1,
		"candidate_pool_identity_observed": candidate_pool_identity_observed,
		"candidate_pool_identity_equal": candidate_pool_identity_equal,
		"distinct_population_count": population_hashes.size(),
		"distinct_dominant_lineage_count": dominant_lineages.size(),
		"population_diverged_pair_count": population_diverged_pairs,
		"heritable_population_diverged": population_hashes.size() >= 2,
		"mean_pairwise_trait_distance": mean_trait_distance,
		"max_pairwise_trait_distance": max_trait_distance,
		"realized_trait_diverged": max_trait_distance > 1e-9,
		"environment": {
			"moisture_min": moisture_min,
			"moisture_max": moisture_max,
			"moisture_span": moisture_max - moisture_min,
			"sunlight_min": sunlight_min,
			"sunlight_max": sunlight_max,
			"sunlight_span": sunlight_max - sunlight_min,
			"temperature_min_c": temperature_min,
			"temperature_max_c": temperature_max,
			"temperature_span_c": temperature_max - temperature_min,
		},
		"zones": zone_metrics,
		"pairwise": pairwise,
		"authority": {
			"world_write": false,
			"ecology_write": false,
			"persistence_write": false,
			"network_replication_write": false,
			"xfer_authority": false,
			"mutation_authority": false,
		},
	}
	report["report_hash"] = _report_hash(report)
	return report

static func _trait_distance(a: Dictionary, b: Dictionary) -> float:
	var total := 0.0
	for trait_key in TRAIT_KEYS:
		var av := float(a.get(trait_key, 0.0))
		var bv := float(b.get(trait_key, 0.0))
		var scale := maxf(1e-9, maxf(absf(av), absf(bv)))
		total += absf(av - bv) / scale
	return total / float(TRAIT_KEYS.size())

static func _all_strings_equal(values: Array) -> bool:
	if values.is_empty():
		return false
	var first := String(values[0])
	if first.is_empty():
		return false
	for index in range(1, values.size()):
		if String(values[index]) != first:
			return false
	return true

static func _report_hash(report: Dictionary) -> String:
	var env: Dictionary = report["environment"]
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		MODE,
		str(int(report["generation"])),
		"evo=1" if bool(report["evolution_enabled"]) else "evo=0",
		"initial_common=1" if bool(report["initial_common_population"]) else "initial_common=0",
		"pool_equal=1" if bool(report["candidate_pool_identity_equal"]) else "pool_equal=0",
		str(int(report["distinct_population_count"])),
		"%.12f" % float(report["mean_pairwise_trait_distance"]),
		"%.12f" % float(report["max_pairwise_trait_distance"]),
		"%.12f" % float(env["moisture_span"]),
		"%.12f" % float(env["sunlight_span"]),
		"%.12f" % float(env["temperature_span_c"]),
	])
	for zone_value in Array(report["zones"]):
		var zone: Dictionary = zone_value
		var zone_token := PackedStringArray([
			str(int(zone["zone_index"])),
			String(zone["label"]),
			String(zone["population_hash"]),
			String(zone["dominant_lineage"]),
			str(int(zone["lineage_richness"])),
			str(int(zone["phenotype_richness"])),
			"%.12f" % float(zone["moisture"]),
			"%.12f" % float(zone["sunlight"]),
			"%.12f" % float(zone["temperature_c"]),
		])
		for trait_key in TRAIT_KEYS:
			zone_token.append("%.12f" % float(zone[trait_key]))
		tokens.append("|".join(zone_token))
	for pair_value in Array(report["pairwise"]):
		var pair: Dictionary = pair_value
		tokens.append("%d>%d|eq=%d|trait=%.12f|moist=%.12f|sun=%.12f" % [
			int(pair["a"]),
			int(pair["b"]),
			1 if bool(pair["population_equal"]) else 0,
			float(pair["trait_distance"]),
			float(pair["moisture_delta"]),
			float(pair["sunlight_delta"]),
		])
	return "\n".join(tokens).sha256_text()
