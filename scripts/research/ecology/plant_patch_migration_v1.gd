extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const RecruitmentTraits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd")
const Establishment = preload("res://scripts/research/ecology/plant_establishment_seed_bank_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo1_p2_4_patch_migration.v1"
const PATCH_SCHEMA := SCHEMA + ".patch"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001

static func create_patch(patch_id: String, bounds: Rect2, environment: Dictionary) -> Dictionary:
	if patch_id.is_empty() or patch_id != patch_id.strip_edges():
		return {}
	if bounds.size.x <= EPSILON or bounds.size.y <= EPSILON:
		return {}
	if not _finite_vector(bounds.position) or not _finite_vector(bounds.size):
		return {}
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	var patch := {
		"schema": PATCH_SCHEMA,
		"version": VERSION,
		"patch_id": patch_id,
		"bounds": bounds,
		"environment": environment,
	}
	patch["checksum"] = _patch_checksum(patch)
	return patch

static func validate_patch(patch: Dictionary) -> bool:
	if String(patch.get("schema", "")) != PATCH_SCHEMA or String(patch.get("version", "")) != VERSION:
		return false
	var patch_id := String(patch.get("patch_id", ""))
	var bounds := Rect2(patch.get("bounds", Rect2()))
	if patch_id.is_empty() or bounds.size.x <= EPSILON or bounds.size.y <= EPSILON:
		return false
	if not _finite_vector(bounds.position) or not _finite_vector(bounds.size):
		return false
	if not bool(EnvironmentSample.validate(Dictionary(patch.get("environment", {}))).get("success", false)):
		return false
	return String(patch.get("checksum", "")) == _patch_checksum(patch)

static func migrate_reproduction_event(
	source_patch: Dictionary,
	target_patches: Array,
	genome: Dictionary,
	recruitment_traits: Dictionary,
	lineage_id: String,
	reproduction_event: String,
	source_position: Vector2,
	emitted_seed_count: int,
	release_height_m: float,
	transport_vector: Vector2,
	turbulence: float
) -> Dictionary:
	if not validate_patch(source_patch):
		return {}
	if not bool(PlantGenome.validate(genome).get("success", false)):
		return {}
	if not RecruitmentTraits.validate(recruitment_traits):
		return {}
	if lineage_id.is_empty() or reproduction_event.is_empty():
		return {}
	var source_bounds := Rect2(source_patch["bounds"])
	if not source_bounds.has_point(source_position):
		return {}

	var target_by_id := {}
	for target_value in target_patches:
		var target: Dictionary = target_value
		if not validate_patch(target):
			return {}
		var target_id := String(target["patch_id"])
		if target_id == String(source_patch["patch_id"]) or target_by_id.has(target_id):
			return {}
		var target_bounds := Rect2(target["bounds"])
		if source_bounds.intersects(target_bounds):
			return {}
		for existing_value in target_by_id.values():
			var existing: Dictionary = existing_value
			if Rect2(existing["bounds"]).intersects(target_bounds):
				return {}
		target_by_id[target_id] = target

	var context := Dispersal.create_context(transport_vector, turbulence, source_bounds)
	if context.is_empty():
		return {}
	var dispersed := Dispersal.disperse(
		genome,
		lineage_id,
		reproduction_event,
		source_position,
		emitted_seed_count,
		release_height_m,
		context
	)
	if dispersed.is_empty():
		return {}

	var source_retained := 0
	var routed := 0
	var unresolved := 0
	var migration_records: Array = []
	var target_totals := {}
	for target_id in _sorted_keys(target_by_id):
		target_totals[target_id] = _empty_target_total(target_id, lineage_id)

	for packet_value in Array(dispersed["packets"]):
		var packet: Dictionary = packet_value
		var seed_count := int(packet["seed_count"])
		if not bool(packet["outside_domain"]):
			source_retained += seed_count
			continue
		var destination := Vector2(packet["destination_position"])
		var target_id := _target_for_position(destination, target_by_id)
		if target_id.is_empty():
			unresolved += seed_count
			continue
		var target: Dictionary = target_by_id[target_id]
		var arrival_packet := _arrival_packet(packet)
		var outcome := Establishment.settle_packet(
			arrival_packet,
			genome,
			recruitment_traits,
			Dictionary(target["environment"]),
			0.0
		)
		if outcome.is_empty() or not bool(outcome.get("conservation_ok", false)):
			return {}
		if int(outcome.get("exported_seed_count", -1)) != 0:
			return {}
		routed += seed_count
		var total: Dictionary = target_totals[target_id]
		total["arrived_seed_count"] = int(total["arrived_seed_count"]) + seed_count
		total["recruited_seed_count"] = int(total["recruited_seed_count"]) + int(outcome["recruited_seed_count"])
		total["seed_bank_seed_count"] = int(total["seed_bank_seed_count"]) + int(outcome["seed_bank_seed_count"])
		total["failed_seed_count"] = int(total["failed_seed_count"]) + int(outcome["failed_germination_count"]) + int(outcome["decayed_seed_count"])
		target_totals[target_id] = total
		var record := {
			"source_patch_id": String(source_patch["patch_id"]),
			"target_patch_id": target_id,
			"lineage_id": lineage_id,
			"seed_count": seed_count,
			"destination_position": destination,
			"distance_m": float(packet["distance_m"]),
			"long_tail": bool(packet["long_tail"]),
			"source_packet_hash": String(packet["packet_hash"]),
			"arrival_packet_hash": String(arrival_packet["packet_hash"]),
			"settlement_hash": String(outcome["result_hash"]),
		}
		record["record_hash"] = _migration_record_hash(record)
		migration_records.append(record)

	var summaries: Array = []
	for target_id in _sorted_keys(target_totals):
		var total: Dictionary = target_totals[target_id]
		total["colonized"] = int(total["recruited_seed_count"]) > 0
		total["summary_hash"] = _target_summary_hash(total)
		summaries.append(total)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"source_patch_id": String(source_patch["patch_id"]),
		"source_patch_checksum": String(source_patch["checksum"]),
		"lineage_id": lineage_id,
		"genome_checksum": String(genome["checksum"]),
		"recruitment_traits_checksum": String(recruitment_traits["checksum"]),
		"reproduction_event": reproduction_event,
		"emitted_seed_count": emitted_seed_count,
		"source_retained_seed_count": source_retained,
		"routed_seed_count": routed,
		"unresolved_export_seed_count": unresolved,
		"migration_record_count": migration_records.size(),
		"migration_records": migration_records,
		"target_summaries": summaries,
		"dispersal_hash": String(dispersed["result_hash"]),
	}
	result["migration_conservation_ok"] = emitted_seed_count == source_retained + routed + unresolved
	result["target_conservation_ok"] = _target_conservation_ok(summaries)
	result["result_hash"] = _result_hash(result)
	return result

static func target_summary(result: Dictionary, target_patch_id: String) -> Dictionary:
	for value in Array(result.get("target_summaries", [])):
		var summary: Dictionary = value
		if String(summary.get("target_patch_id", "")) == target_patch_id:
			return summary
	return {}

static func _target_for_position(position: Vector2, target_by_id: Dictionary) -> String:
	for target_id in _sorted_keys(target_by_id):
		var target: Dictionary = target_by_id[target_id]
		if Rect2(target["bounds"]).has_point(position):
			return target_id
	return ""

static func _arrival_packet(source_packet: Dictionary) -> Dictionary:
	var packet := source_packet.duplicate(true)
	packet["outside_domain"] = false
	packet["packet_hash"] = _p2_1_packet_hash(packet)
	return packet

static func _p2_1_packet_hash(packet: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(packet.get("schema", "")),
		String(packet.get("version", "")),
		str(int(packet.get("packet_index", -1))),
		str(int(packet.get("seed_count", 0))),
		String(packet.get("lineage_id", "")),
		String(packet.get("genome_checksum", "")),
		String(packet.get("reproduction_event", "")),
		_vector_token(Vector2(packet.get("source_position", Vector2.ZERO))),
		_vector_token(Vector2(packet.get("destination_position", Vector2.ZERO))),
		"%.12f" % float(packet.get("distance_m", 0.0)),
		str(bool(packet.get("long_tail", false))),
		str(bool(packet.get("outside_domain", false))),
	])).sha256_text()

static func _empty_target_total(target_id: String, lineage_id: String) -> Dictionary:
	return {
		"target_patch_id": target_id,
		"lineage_id": lineage_id,
		"arrived_seed_count": 0,
		"recruited_seed_count": 0,
		"seed_bank_seed_count": 0,
		"failed_seed_count": 0,
	}

static func _target_conservation_ok(summaries: Array) -> bool:
	for value in summaries:
		var summary: Dictionary = value
		if int(summary["arrived_seed_count"]) != int(summary["recruited_seed_count"]) + int(summary["seed_bank_seed_count"]) + int(summary["failed_seed_count"]):
			return false
	return true

static func _migration_record_hash(record: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(record.get("source_patch_id", "")),
		String(record.get("target_patch_id", "")),
		String(record.get("lineage_id", "")),
		str(int(record.get("seed_count", 0))),
		_vector_token(Vector2(record.get("destination_position", Vector2.ZERO))),
		"%.12f" % float(record.get("distance_m", 0.0)),
		str(bool(record.get("long_tail", false))),
		String(record.get("source_packet_hash", "")),
		String(record.get("arrival_packet_hash", "")),
		String(record.get("settlement_hash", "")),
	])).sha256_text()

static func _target_summary_hash(summary: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(summary.get("target_patch_id", "")),
		String(summary.get("lineage_id", "")),
		str(int(summary.get("arrived_seed_count", 0))),
		str(int(summary.get("recruited_seed_count", 0))),
		str(int(summary.get("seed_bank_seed_count", 0))),
		str(int(summary.get("failed_seed_count", 0))),
		str(bool(summary.get("colonized", false))),
	])).sha256_text()

static func _result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		String(result.get("source_patch_id", "")),
		String(result.get("source_patch_checksum", "")),
		String(result.get("lineage_id", "")),
		String(result.get("genome_checksum", "")),
		String(result.get("recruitment_traits_checksum", "")),
		String(result.get("reproduction_event", "")),
		str(int(result.get("emitted_seed_count", 0))),
		str(int(result.get("source_retained_seed_count", 0))),
		str(int(result.get("routed_seed_count", 0))),
		str(int(result.get("unresolved_export_seed_count", 0))),
		String(result.get("dispersal_hash", "")),
	])
	for value in Array(result.get("migration_records", [])):
		tokens.append(String(Dictionary(value).get("record_hash", "")))
	for value in Array(result.get("target_summaries", [])):
		tokens.append(String(Dictionary(value).get("summary_hash", "")))
	return "\n".join(tokens).sha256_text()

static func _patch_checksum(patch: Dictionary) -> String:
	var bounds := Rect2(patch.get("bounds", Rect2()))
	return "|".join(PackedStringArray([
		PATCH_SCHEMA,
		VERSION,
		String(patch.get("patch_id", "")),
		_vector_token(bounds.position),
		_vector_token(bounds.size),
		String(Dictionary(patch.get("environment", {})).get("checksum", "")),
	])).sha256_text()

static func _sorted_keys(values: Dictionary) -> Array:
	var keys := values.keys()
	keys.sort()
	return keys

static func _vector_token(value: Vector2) -> String:
	return "%.12f,%.12f" % [value.x, value.y]

static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)
