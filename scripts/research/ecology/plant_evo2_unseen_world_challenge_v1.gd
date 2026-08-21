extends RefCounted

const Persistence = preload("res://scripts/research/ecology/plant_catalog_persistence_v1.gd")
const Protocol = preload("res://scripts/research/ecology/plant_evo2_unseen_world_protocol_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const MutationKernel = preload("res://scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_final_unseen_world_challenge.v1"
const VERSION := "1.0.0"
const PARENT_E2_8_ACCEPTED_AGGREGATE := "4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061"
const PARENT_E2_8_CODE_UNDER_TEST := "5790de059aaafbfc10434bb2d40124e3c1ceb361"
const ACCEPTED_E2_8_TRANSPORT_SHA256 := "b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1"
const ACCEPTED_E2_8_CONTENT_HASH := "3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e"
const ACCEPTED_E2_8_PROVENANCE_HASH := "a3a2f53107cefc5c96d835bd93327864d45f31e55b123fcd2fe4053fd5495a15"
const ACCEPTED_E2_2_CATALOG_HASH := "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219"
const PARENT_E2_7_ACCEPTED_AGGREGATE := "eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d"
const EPSILON := 0.000000001

static func run(persisted_bytes: PackedByteArray) -> Dictionary:
	if persisted_bytes.is_empty() or Persistence.transport_sha256(persisted_bytes) != ACCEPTED_E2_8_TRANSPORT_SHA256:
		return {}
	var artifact := Persistence.restore(persisted_bytes)
	if artifact.is_empty():
		return {}
	if String(artifact.get("content_hash", "")) != ACCEPTED_E2_8_CONTENT_HASH or String(artifact.get("provenance_hash", "")) != ACCEPTED_E2_8_PROVENANCE_HASH:
		return {}
	var provenance: Dictionary = artifact.get("provenance", {})
	if String(provenance.get("e2_7_accepted_aggregate", "")) != PARENT_E2_7_ACCEPTED_AGGREGATE:
		return {}
	var catalog_value = artifact.get("species_catalog")
	if typeof(catalog_value) != TYPE_DICTIONARY:
		return {}
	var catalog: Dictionary = catalog_value
	if String(catalog.get("catalog_hash", "")) != ACCEPTED_E2_2_CATALOG_HASH:
		return {}
	var protocol := Protocol.build()
	if protocol.is_empty() or not Protocol.validate(protocol):
		return {}
	var entries: Array = Array(catalog.get("entries", []))
	if entries.is_empty():
		return {}
	var catalog_before := catalog.duplicate(true)
	var migrations: Array = []
	var recruited_by_patch := {}
	for patch_value in Array(protocol["target_patches"]):
		var patch: Dictionary = patch_value
		recruited_by_patch[String(patch["patch_id"])] = {}
	for entry_value in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			return {}
		var entry: Dictionary = entry_value
		var species_id := String(entry.get("research_species_id", ""))
		var genome: Dictionary = Dictionary(entry.get("genome", {})).duplicate(true)
		var traits: Dictionary = Dictionary(entry.get("recruitment_traits", {})).duplicate(true)
		var emitted := int(genome.get("seed_count", 0)) * int(protocol["emission_multiplier"])
		var migration := PatchMigration.migrate_reproduction_event(
			Dictionary(protocol["source_patch"]),
			Array(protocol["target_patches"]),
			genome,
			traits,
			species_id,
			"evo2-final|%s|%s" % [String(protocol["world_id"]), species_id],
			Rect2(Dictionary(protocol["source_patch"])["bounds"]).get_center(),
			emitted,
			maxf(float(genome.get("height_m", 0.0)), 0.05),
			Vector2(protocol["transport_vector"]),
			float(protocol["turbulence"])
		)
		if migration.is_empty() or not bool(migration.get("migration_conservation_ok", false)) or not bool(migration.get("target_conservation_ok", false)):
			return {}
		migrations.append({
			"research_species_id": species_id,
			"source_lineage_id": String(entry.get("lineage_id", "")),
			"genome_checksum": String(genome.get("checksum", "")),
			"result_hash": String(migration.get("result_hash", "")),
		})
		for patch_value in Array(protocol["target_patches"]):
			var patch: Dictionary = patch_value
			var patch_id := String(patch["patch_id"])
			var summary := PatchMigration.target_summary(migration, patch_id)
			if summary.is_empty():
				return {}
			Dictionary(recruited_by_patch[patch_id])[species_id] = {
				"recruited": int(summary.get("recruited_seed_count", 0)),
				"banked": int(summary.get("seed_bank_seed_count", 0)),
				"arrived": int(summary.get("arrived_seed_count", 0)),
				"summary_hash": String(summary.get("summary_hash", "")),
			}
	if catalog != catalog_before:
		return {}
	var colonization := _colonization(protocol, entries, recruited_by_patch)
	if colonization.is_empty():
		return {}
	var cells: Array = []
	for patch_id in [Protocol.DRY_PATCH_ID, Protocol.WET_PATCH_ID]:
		var patch := _patch_by_id(protocol, patch_id)
		if patch.is_empty():
			return {}
		var founders := _founders(entries, Dictionary(recruited_by_patch[patch_id]), patch_id, int(protocol["population_size"]))
		if founders.is_empty():
			cells.append(_empty_cell(patch))
			continue
		var control := _run_arm(founders, Dictionary(patch["environment"]), patch_id, "CONTROL", Dictionary(protocol["control_policy"]), entries, protocol)
		var treatment := _run_arm(founders, Dictionary(patch["environment"]), patch_id, "TREATMENT", Dictionary(protocol["treatment_policy"]), entries, protocol)
		if control.is_empty() or treatment.is_empty():
			return {}
		var initial_counts: Dictionary = Dictionary(control["initial"]["lineage_counts"])
		var sorting_detected := Dictionary(control["final"]["lineage_counts"]) != initial_counts
		var adaptation_gain := float(treatment["final"]["average_net_resource_balance"]) - float(control["final"]["average_net_resource_balance"])
		var novel := int(treatment["final"]["novel_genome_count"])
		var adaptation_detected := novel > 0 and adaptation_gain > EPSILON
		var classification := _classification(sorting_detected, novel, adaptation_gain)
		var cell := {
			"patch_id": patch_id,
			"environment_checksum": String(Dictionary(patch["environment"])["checksum"]),
			"initial_lineage_counts": initial_counts.duplicate(true),
			"control": control,
			"treatment": treatment,
			"sorting_detected": sorting_detected,
			"adaptation_detected": adaptation_detected,
			"adaptation_gain": adaptation_gain,
			"classification": classification,
		}
		cell["cell_hash"] = _cell_hash(cell)
		cells.append(cell)
	var reachable_colonized := 0
	var isolated_no_colonization := false
	var unique_recruited := {}
	for value in colonization:
		var record: Dictionary = value
		var patch_id := String(record["patch_id"])
		if patch_id in [Protocol.DRY_PATCH_ID, Protocol.WET_PATCH_ID] and bool(record["colonized"]):
			reachable_colonized += 1
		if patch_id == Protocol.ISOLATED_PATCH_ID:
			isolated_no_colonization = not bool(record["colonized"])
		for species_id in Array(record["recruited_species_ids"]):
			unique_recruited[String(species_id)] = true
	var sorting_cells := 0
	var adaptation_positive_cells := 0
	for value in cells:
		var cell: Dictionary = value
		if bool(cell.get("sorting_detected", false)):
			sorting_cells += 1
		if String(cell.get("classification", "")) == "ADAPTATION_POSITIVE":
			adaptation_positive_cells += 1
	var challenge_passed := (
		reachable_colonized >= int(protocol["min_reachable_colonized_patches"])
		and unique_recruited.size() >= int(protocol["min_unique_recruited_species"])
		and (not bool(protocol["require_isolated_no_colonization"]) or isolated_no_colonization)
		and sorting_cells >= int(protocol["min_sorting_observed_cells"])
		and adaptation_positive_cells >= int(protocol["min_adaptation_positive_cells"])
	)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_e2_8_accepted_aggregate": PARENT_E2_8_ACCEPTED_AGGREGATE,
		"parent_e2_8_code_under_test": PARENT_E2_8_CODE_UNDER_TEST,
		"input_transport_sha256": ACCEPTED_E2_8_TRANSPORT_SHA256,
		"restored_content_hash": String(artifact["content_hash"]),
		"restored_provenance_hash": String(artifact["provenance_hash"]),
		"catalog_hash": String(catalog["catalog_hash"]),
		"protocol_hash": String(protocol["protocol_hash"]),
		"world_id": String(protocol["world_id"]),
		"catalog_entry_count": entries.size(),
		"migration_count": migrations.size(),
		"migrations": migrations,
		"colonization": colonization,
		"cells": cells,
		"reachable_colonized_patches": reachable_colonized,
		"unique_recruited_species": unique_recruited.size(),
		"isolated_no_colonization": isolated_no_colonization,
		"sorting_observed_cells": sorting_cells,
		"adaptation_positive_cells": adaptation_positive_cells,
		"null_reversal_censored": false,
		"rebake_used": false,
		"target_aware_species_filter_used": false,
		"biome_species_table_used": false,
		"production_authority_claimed": false,
		"challenge_passed": challenge_passed,
	}
	result["evidence_hash"] = compute_evidence_hash(result)
	return result

static func validate_result(persisted_bytes: PackedByteArray, result: Dictionary) -> bool:
	var expected := run(persisted_bytes)
	return not expected.is_empty() and expected == result and String(result.get("evidence_hash", "")) == compute_evidence_hash(result)

static func compute_evidence_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, PARENT_E2_8_ACCEPTED_AGGREGATE, PARENT_E2_8_CODE_UNDER_TEST,
		String(result.get("input_transport_sha256", "")), String(result.get("restored_content_hash", "")),
		String(result.get("restored_provenance_hash", "")), String(result.get("catalog_hash", "")),
		String(result.get("protocol_hash", "")), String(result.get("world_id", "")),
		str(int(result.get("reachable_colonized_patches", 0))), str(int(result.get("unique_recruited_species", 0))),
		str(bool(result.get("isolated_no_colonization", false))), str(int(result.get("sorting_observed_cells", 0))),
		str(int(result.get("adaptation_positive_cells", 0))), str(bool(result.get("challenge_passed", false))),
		"boundaries=%s|%s|%s|%s" % [str(bool(result.get("rebake_used", true))), str(bool(result.get("target_aware_species_filter_used", true))), str(bool(result.get("biome_species_table_used", true))), str(bool(result.get("production_authority_claimed", true)))],
	])
	for value in Array(result.get("migrations", [])):
		tokens.append(String(Dictionary(value).get("result_hash", "")))
	for value in Array(result.get("colonization", [])):
		tokens.append(String(Dictionary(value).get("record_hash", "")))
	for value in Array(result.get("cells", [])):
		tokens.append(String(Dictionary(value).get("cell_hash", "")))
	return "\n".join(tokens).sha256_text()

static func _colonization(protocol: Dictionary, entries: Array, recruited_by_patch: Dictionary) -> Array:
	var result: Array = []
	for patch_value in Array(protocol["target_patches"]):
		var patch: Dictionary = patch_value
		var patch_id := String(patch["patch_id"])
		var total_recruited := 0
		var total_banked := 0
		var recruited_ids: Array = []
		var species_records: Array = []
		for entry_value in entries:
			var entry: Dictionary = entry_value
			var species_id := String(entry["research_species_id"])
			var counts: Dictionary = Dictionary(Dictionary(recruited_by_patch[patch_id]).get(species_id, {}))
			var recruited := int(counts.get("recruited", 0))
			var banked := int(counts.get("banked", 0))
			total_recruited += recruited
			total_banked += banked
			if recruited > 0:
				recruited_ids.append(species_id)
			species_records.append({
				"research_species_id": species_id,
				"source_lineage_id": String(entry["lineage_id"]),
				"genome_checksum": String(entry["genome_checksum"]),
				"recruited": recruited,
				"banked": banked,
				"arrived": int(counts.get("arrived", 0)),
				"migration_summary_hash": String(counts.get("summary_hash", "")),
			})
		var record := {
			"patch_id": patch_id,
			"environment_checksum": String(Dictionary(patch["environment"])["checksum"]),
			"species": species_records,
			"recruited_species_ids": recruited_ids,
			"total_recruited": total_recruited,
			"total_banked": total_banked,
			"colonized": total_recruited > 0,
		}
		record["record_hash"] = _colonization_hash(record)
		result.append(record)
	return result

static func _founders(entries: Array, recruited: Dictionary, patch_id: String, population_size: int) -> Array:
	var eligible: Array = []
	var total := 0
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var species_id := String(entry["research_species_id"])
		var count := int(Dictionary(recruited.get(species_id, {})).get("recruited", 0))
		if count <= 0:
			continue
		eligible.append({"entry": entry, "count": count})
		total += count
	if total <= 0:
		return []
	var founders: Array = []
	for index in range(population_size):
		var target := ((2 * index + 1) * total) / (2 * population_size)
		var cumulative := 0
		var chosen: Dictionary = Dictionary(eligible[eligible.size() - 1])["entry"]
		for value in eligible:
			var item: Dictionary = value
			cumulative += int(item["count"])
			if cumulative > target:
				chosen = Dictionary(item["entry"])
				break
		var genome: Dictionary = Dictionary(chosen["genome"]).duplicate(true)
		var species_id := String(chosen["research_species_id"])
		var lineage := MutationKernel.create_ancestor(genome, _stable_seed("founder|%s|%s|%d" % [patch_id, species_id, index]))
		if lineage.is_empty():
			return []
		founders.append({
			"research_species_id": species_id,
			"source_lineage_id": String(chosen["lineage_id"]),
			"frozen_genome_checksum": String(chosen["genome_checksum"]),
			"genome": genome,
			"lineage": lineage,
		})
	return founders

static func _run_arm(founders: Array, environment: Dictionary, patch_id: String, arm_id: String, policy: Dictionary, entries: Array, protocol: Dictionary) -> Dictionary:
	if not bool(MutationKernel.validate_policy(policy).get("success", false)):
		return {}
	var frozen := {}
	for entry_value in entries:
		frozen[String(Dictionary(entry_value)["genome_checksum"])] = true
	var population := founders.duplicate(true)
	var initial := _summary(population, environment, 0, frozen, protocol)
	if initial.is_empty():
		return {}
	var history: Array = [initial]
	var selected_event_hashes: Array = []
	for generation in range(1, int(protocol["generations"]) + 1):
		var candidates: Array = []
		for parent_index in range(population.size()):
			var parent: Dictionary = population[parent_index]
			for child_index in range(int(protocol["offspring_per_parent"])):
				var offspring_index := parent_index * int(protocol["offspring_per_parent"]) + child_index
				var seed_key := "%s|%s|%s|%d|%d|%s" % [String(protocol["world_id"]), patch_id, arm_id, generation, offspring_index, String(Dictionary(parent["lineage"])["checksum"])]
				var reproduction := MutationKernel.reproduce(Dictionary(parent["genome"]), Dictionary(parent["lineage"]), _stable_seed(seed_key), offspring_index, policy)
				if reproduction.is_empty() or not bool(MutationKernel.validate_result(reproduction).get("success", false)):
					return {}
				var balance := ResourceModel.evaluate(environment, Dictionary(reproduction["genome"]), float(protocol["evaluation_biomass_kg_m2"]))
				if balance.is_empty():
					return {}
				candidates.append({
					"research_species_id": String(parent["research_species_id"]),
					"source_lineage_id": String(parent["source_lineage_id"]),
					"frozen_genome_checksum": String(parent["frozen_genome_checksum"]),
					"genome": Dictionary(reproduction["genome"]),
					"lineage": Dictionary(reproduction["lineage"]),
					"net": float(balance["net_resource_balance"]),
					"mutation_event_hash": String(reproduction["mutation_event_hash"]),
				})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if absf(float(a["net"]) - float(b["net"])) > EPSILON:
				return float(a["net"]) > float(b["net"])
			if String(a["research_species_id"]) != String(b["research_species_id"]):
				return String(a["research_species_id"]) < String(b["research_species_id"])
			if String(Dictionary(a["genome"])["checksum"]) != String(Dictionary(b["genome"])["checksum"]):
				return String(Dictionary(a["genome"])["checksum"]) < String(Dictionary(b["genome"])["checksum"])
			return String(Dictionary(a["lineage"])["checksum"]) < String(Dictionary(b["lineage"])["checksum"])
		)
		population = []
		for index in range(mini(int(protocol["population_size"]), candidates.size())):
			var chosen: Dictionary = candidates[index]
			population.append({
				"research_species_id": String(chosen["research_species_id"]),
				"source_lineage_id": String(chosen["source_lineage_id"]),
				"frozen_genome_checksum": String(chosen["frozen_genome_checksum"]),
				"genome": Dictionary(chosen["genome"]).duplicate(true),
				"lineage": Dictionary(chosen["lineage"]).duplicate(true),
			})
			selected_event_hashes.append(String(chosen["mutation_event_hash"]))
		var summary := _summary(population, environment, generation, frozen, protocol)
		if summary.is_empty():
			return {}
		history.append(summary)
	var result := {
		"arm": arm_id,
		"adaptation_enabled": float(policy["mutation_probability"]) > 0.0,
		"policy_hash": MutationKernel.policy_hash(policy),
		"initial": initial,
		"final": history[history.size() - 1],
		"history_hash": _history_hash(history),
		"selected_event_hashes": selected_event_hashes,
		"final_population_hash": _population_hash(population),
	}
	result["arm_hash"] = _arm_hash(result)
	return result

static func _summary(population: Array, environment: Dictionary, generation: int, frozen: Dictionary, protocol: Dictionary) -> Dictionary:
	if population.is_empty():
		return {}
	var total := 0.0
	var best := -INF
	var counts := {}
	var unique := {}
	var novel := {}
	for value in population:
		var individual: Dictionary = value
		var genome: Dictionary = individual["genome"]
		var balance := ResourceModel.evaluate(environment, genome, float(protocol["evaluation_biomass_kg_m2"]))
		if balance.is_empty():
			return {}
		var net := float(balance["net_resource_balance"])
		total += net
		best = maxf(best, net)
		var species_id := String(individual["research_species_id"])
		counts[species_id] = int(counts.get(species_id, 0)) + 1
		var checksum := String(genome["checksum"])
		unique[checksum] = true
		if not frozen.has(checksum):
			novel[checksum] = true
	return {
		"generation": generation,
		"average_net_resource_balance": total / float(population.size()),
		"best_net_resource_balance": best,
		"lineage_counts": _sorted_int_dict(counts),
		"unique_genome_count": unique.size(),
		"novel_genome_count": novel.size(),
		"population_hash": _population_hash(population),
	}

static func _classification(sorting_detected: bool, novel_genome_count: int, adaptation_gain: float) -> String:
	if novel_genome_count > 0 and adaptation_gain > EPSILON:
		return "ADAPTATION_POSITIVE"
	if novel_genome_count > 0 and adaptation_gain < -EPSILON:
		return "ADAPTATION_REVERSAL"
	if novel_genome_count > 0:
		return "ADAPTATION_NULL"
	if sorting_detected:
		return "SORTING_ONLY"
	return "NO_CHANGE"

static func _empty_cell(patch: Dictionary) -> Dictionary:
	var cell := {
		"patch_id": String(patch["patch_id"]),
		"environment_checksum": String(Dictionary(patch["environment"])["checksum"]),
		"initial_lineage_counts": {},
		"control": {},
		"treatment": {},
		"sorting_detected": false,
		"adaptation_detected": false,
		"adaptation_gain": 0.0,
		"classification": "VALID_NO_COLONIZATION",
	}
	cell["cell_hash"] = _cell_hash(cell)
	return cell

static func _patch_by_id(protocol: Dictionary, patch_id: String) -> Dictionary:
	for value in Array(protocol["target_patches"]):
		var patch: Dictionary = value
		if String(patch["patch_id"]) == patch_id:
			return patch
	return {}

static func _colonization_hash(record: Dictionary) -> String:
	var tokens := PackedStringArray([String(record["patch_id"]), String(record["environment_checksum"]), str(int(record["total_recruited"])), str(int(record["total_banked"])), str(bool(record["colonized"]))])
	for value in Array(record["species"]):
		var item: Dictionary = value
		tokens.append("%s|%s|%s|%d|%d|%d|%s" % [String(item["research_species_id"]), String(item["source_lineage_id"]), String(item["genome_checksum"]), int(item["recruited"]), int(item["banked"]), int(item["arrived"]), String(item["migration_summary_hash"])])
	return "\n".join(tokens).sha256_text()

static func _cell_hash(cell: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		String(cell.get("patch_id", "")), String(cell.get("environment_checksum", "")),
		str(bool(cell.get("sorting_detected", false))), str(bool(cell.get("adaptation_detected", false))),
		"%.12f" % float(cell.get("adaptation_gain", 0.0)), String(cell.get("classification", "")),
		String(Dictionary(cell.get("control", {})).get("arm_hash", "")), String(Dictionary(cell.get("treatment", {})).get("arm_hash", "")),
	])).sha256_text()

static func _history_hash(history: Array) -> String:
	var tokens := PackedStringArray()
	for value in history:
		var summary: Dictionary = value
		tokens.append("%d|%.12f|%.12f|%d|%d|%s" % [int(summary["generation"]), float(summary["average_net_resource_balance"]), float(summary["best_net_resource_balance"]), int(summary["unique_genome_count"]), int(summary["novel_genome_count"]), String(summary["population_hash"])])
	return "\n".join(tokens).sha256_text()

static func _arm_hash(arm: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		String(arm["arm"]), str(bool(arm["adaptation_enabled"])), String(arm["policy_hash"]),
		String(Dictionary(arm["initial"])["population_hash"]), String(Dictionary(arm["final"])["population_hash"]),
		String(arm["history_hash"]), String(arm["final_population_hash"]),
	])).sha256_text()

static func _population_hash(population: Array) -> String:
	var tokens := PackedStringArray()
	for value in population:
		var individual: Dictionary = value
		tokens.append("%s|%s|%s|%s|%s" % [String(individual["research_species_id"]), String(individual["source_lineage_id"]), String(individual["frozen_genome_checksum"]), String(Dictionary(individual["genome"])["checksum"]), String(Dictionary(individual["lineage"])["checksum"])])
	return "\n".join(tokens).sha256_text()

static func _sorted_int_dict(values: Dictionary) -> Dictionary:
	var keys := values.keys()
	keys.sort()
	var result := {}
	for key in keys:
		result[String(key)] = int(values[key])
	return result

static func _stable_seed(key: String) -> int:
	return int(key.sha256_text().substr(0, 12).hex_to_int())
