extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const P2_3 = preload("res://scripts/research/ecology/plant_local_population_succession_experiment_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_4_patch_colonization_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.EVO1-P2.4.1"
const ACCEPTED_P2_3_HASH := "15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e"
const SHORT := "lineage/p2-4-short"
const LONG := "lineage/p2-4-long"
const SOURCE := "patch/source"
const NEAR := "patch/near"
const FAR := "patch/far"
const EVENT_COUNT := 8

static func run() -> Dictionary:
	var parent := P2_3.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_P2_3_HASH:
		return {}

	var environment := EnvironmentSample.create(0.0, 0.0, 17.0, 0.58, 0.95, 0.80, 0.02, 2404, "eco-evo1-p2-4-favourable")
	if environment.is_empty():
		return {}
	var source_patch := PatchMigration.create_patch(SOURCE, Rect2(-10.0, -10.0, 20.0, 20.0), environment)
	var near_patch := PatchMigration.create_patch(NEAR, Rect2(11.0, -20.0, 24.0, 40.0), environment)
	var far_patch := PatchMigration.create_patch(FAR, Rect2(50.0, -40.0, 80.0, 80.0), environment)
	if source_patch.is_empty() or near_patch.is_empty() or far_patch.is_empty():
		return {}
	var targets := [near_patch, far_patch]

	var short_genome := Genome.create("plant-genome/p2-4-short", 1.60, 0.65, 0.85, 0.58, 0.30, 0.45, 160, 5.0, 5.0)
	var long_genome := Genome.create("plant-genome/p2-4-long", 1.60, 0.65, 0.85, 0.58, 0.30, 0.45, 160, 20.0, 5.0)
	var traits := RecruitmentTraits.create("recruitment-traits/p2-4-common", 0.45, 3.0)
	if short_genome.is_empty() or long_genome.is_empty() or traits.is_empty():
		return {}

	var strategies := [
		{"lineage_id": SHORT, "genome": short_genome},
		{"lineage_id": LONG, "genome": long_genome},
	]
	var totals := {
		NEAR: {SHORT: _empty_counts(), LONG: _empty_counts()},
		FAR: {SHORT: _empty_counts(), LONG: _empty_counts()},
	}
	var event_hashes := PackedStringArray()
	var total_emitted := 0
	var total_retained := 0
	var total_routed := 0
	var total_unresolved := 0

	for strategy_value in strategies:
		var strategy: Dictionary = strategy_value
		var lineage := String(strategy["lineage_id"])
		var genome: Dictionary = strategy["genome"]
		for event_index in range(EVENT_COUNT):
			var event_id := "p2-4/east/%s/%d" % [lineage, event_index]
			var result := PatchMigration.migrate_reproduction_event(
				source_patch,
				targets,
				genome,
				traits,
				lineage,
				event_id,
				Vector2.ZERO,
				160,
				1.60,
				Vector2(1.0, 0.0),
				0.20
			)
			if result.is_empty() or not bool(result.get("migration_conservation_ok", false)) or not bool(result.get("target_conservation_ok", false)):
				return {}
			total_emitted += int(result["emitted_seed_count"])
			total_retained += int(result["source_retained_seed_count"])
			total_routed += int(result["routed_seed_count"])
			total_unresolved += int(result["unresolved_export_seed_count"])
			event_hashes.append(String(result["result_hash"]))
			for patch_id in [NEAR, FAR]:
				var summary := PatchMigration.target_summary(result, patch_id)
				if summary.is_empty():
					return {}
				var patch_totals: Dictionary = totals[patch_id]
				var counts: Dictionary = patch_totals[lineage]
				counts["arrived"] = int(counts["arrived"]) + int(summary["arrived_seed_count"])
				counts["recruited"] = int(counts["recruited"]) + int(summary["recruited_seed_count"])
				counts["bank"] = int(counts["bank"]) + int(summary["seed_bank_seed_count"])
				counts["failed"] = int(counts["failed"]) + int(summary["failed_seed_count"])
				patch_totals[lineage] = counts
				totals[patch_id] = patch_totals

	var west_routed := 0
	var west_hashes := PackedStringArray()
	for event_index in range(4):
		var west := PatchMigration.migrate_reproduction_event(
			source_patch,
			targets,
			long_genome,
			traits,
			LONG,
			"p2-4/west/%d" % event_index,
			Vector2.ZERO,
			160,
			1.60,
			Vector2(-1.0, 0.0),
			0.20
		)
		if west.is_empty() or not bool(west.get("migration_conservation_ok", false)):
			return {}
		west_routed += int(west["routed_seed_count"])
		west_hashes.append(String(west["result_hash"]))

	var near_short: Dictionary = Dictionary(totals[NEAR])[SHORT]
	var near_long: Dictionary = Dictionary(totals[NEAR])[LONG]
	var far_short: Dictionary = Dictionary(totals[FAR])[SHORT]
	var far_long: Dictionary = Dictionary(totals[FAR])[LONG]
	var near_recruited := int(near_short["recruited"]) + int(near_long["recruited"])
	var far_recruited := int(far_short["recruited"]) + int(far_long["recruited"])
	var near_arrived := int(near_short["arrived"]) + int(near_long["arrived"])
	var far_arrived := int(far_short["arrived"]) + int(far_long["arrived"])
	var near_long_share := _share(int(near_long["recruited"]), near_recruited)
	var far_long_share := _share(int(far_long["recruited"]), far_recruited)
	var near_colonized_lineages := int(int(near_short["recruited"]) > 0) + int(int(near_long["recruited"]) > 0)
	var far_colonized_lineages := int(int(far_short["recruited"]) > 0) + int(int(far_long["recruited"]) > 0)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"p2_3_parent_hash": ACCEPTED_P2_3_HASH,
		"event_count_per_lineage": EVENT_COUNT,
		"totals": totals,
		"total_emitted": total_emitted,
		"total_retained": total_retained,
		"total_routed": total_routed,
		"total_unresolved": total_unresolved,
		"near_arrived": near_arrived,
		"far_arrived": far_arrived,
		"near_recruited": near_recruited,
		"far_recruited": far_recruited,
		"near_short_arrived": int(near_short["arrived"]),
		"near_long_arrived": int(near_long["arrived"]),
		"far_short_arrived": int(far_short["arrived"]),
		"far_long_arrived": int(far_long["arrived"]),
		"near_short_recruited": int(near_short["recruited"]),
		"near_long_recruited": int(near_long["recruited"]),
		"far_short_recruited": int(far_short["recruited"]),
		"far_long_recruited": int(far_long["recruited"]),
		"near_long_share": near_long_share,
		"far_long_share": far_long_share,
		"near_colonized_lineages": near_colonized_lineages,
		"far_colonized_lineages": far_colonized_lineages,
		"west_routed": west_routed,
		"event_hashes": event_hashes,
		"west_hashes": west_hashes,
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _empty_counts() -> Dictionary:
	return {"arrived": 0, "recruited": 0, "bank": 0, "failed": 0}

static func _share(numerator: int, denominator: int) -> float:
	if denominator <= 0:
		return 0.0
	return float(numerator) / float(denominator)

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("p2_3_parent_hash", "")),
		str(int(result.get("event_count_per_lineage", 0))),
	])
	for field_name in [
		"total_emitted", "total_retained", "total_routed", "total_unresolved",
		"near_arrived", "far_arrived", "near_recruited", "far_recruited",
		"near_short_arrived", "near_long_arrived", "far_short_arrived", "far_long_arrived",
		"near_short_recruited", "near_long_recruited", "far_short_recruited", "far_long_recruited",
		"near_colonized_lineages", "far_colonized_lineages", "west_routed"
	]:
		tokens.append(str(int(result.get(field_name, 0))))
	for field_name in ["near_long_share", "far_long_share"]:
		tokens.append("%.12f" % float(result.get(field_name, 0.0)))
	for value in PackedStringArray(result.get("event_hashes", PackedStringArray())):
		tokens.append(value)
	for value in PackedStringArray(result.get("west_hashes", PackedStringArray())):
		tokens.append(value)
	return "\n".join(tokens).sha256_text()
