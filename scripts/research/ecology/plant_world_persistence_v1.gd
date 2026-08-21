extends RefCounted

const Biogeography = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const DisturbanceRecovery = preload("res://scripts/research/ecology/plant_disturbance_recovery_v1.gd")

const WORLD_SCHEMA := "distributed_world_simulator.ecology.evo1_p2_8_plant_world_state.v1"
const CHECKPOINT_SCHEMA := "distributed_world_simulator.ecology.evo1_p2_8_plant_world_checkpoint.v1"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001

static func create_world(
	patch_states: Array,
	strategies: Dictionary,
	total_years: int,
	source_patch_ids: Array,
	transport_schedule: Array,
	disturbance_schedule: Dictionary,
	lineage_diagnostics: Dictionary = {}
) -> Dictionary:
	if patch_states.is_empty() or patch_states.size() > Biogeography.MAX_PATCHES or total_years <= 0 or total_years > Biogeography.MAX_YEARS:
		return {}
	if not Biogeography._valid_strategies(strategies) or not Biogeography._validate_transport_schedule(transport_schedule):
		return {}
	var patches := {}
	var states := {}
	for value in patch_states:
		var entry: Dictionary = value
		var patch: Dictionary = Dictionary(entry.get("patch", {}))
		var state: Dictionary = Dictionary(entry.get("state", {}))
		if not PatchMigration.validate_patch(patch) or not DisturbanceRecovery._valid_state(state, strategies):
			return {}
		var patch_id := String(patch.get("patch_id", ""))
		if patch_id.is_empty() or patches.has(patch_id):
			return {}
		patches[patch_id] = patch.duplicate(true)
		states[patch_id] = Biogeography._copy_state(state)
	var source_ids: Array = []
	for source_value in source_patch_ids:
		var source_id := String(source_value)
		if not patches.has(source_id) or source_id in source_ids:
			return {}
		source_ids.append(source_id)
	source_ids.sort()
	if source_ids.is_empty():
		return {}
	var indexed := Biogeography._index_disturbances(disturbance_schedule, patches, total_years)
	if indexed.is_empty() and not disturbance_schedule.is_empty():
		return {}
	var initial_summary := Biogeography._regional_summary(0, patches, states, strategies)
	if initial_summary.is_empty():
		return {}
	var initial_occupancy := Biogeography._adult_occupancy_map(initial_summary, strategies)
	var world := {
		"schema": WORLD_SCHEMA,
		"version": VERSION,
		"current_year": 0,
		"total_years": total_years,
		"patches": patches,
		"states": states,
		"strategies": strategies.duplicate(true),
		"source_patch_ids": source_ids,
		"transport_schedule": transport_schedule.duplicate(true),
		"disturbance_schedule": disturbance_schedule.duplicate(true),
		"history": [initial_summary],
		"transition_log": [],
		"migration_log": [],
		"disturbance_log": [],
		"cumulative_emitted_seed_count": 0,
		"cumulative_routed_seed_count": 0,
		"cumulative_unresolved_export_seed_count": 0,
		"cumulative_recruited_seed_count": 0,
		"cumulative_seed_bank_arrival_count": 0,
		"cumulative_reactivated_seed_count": 0,
		"migration_all_conserve": true,
		"disturbance_all_conserve": true,
		"max_adult_cohorts": int(initial_summary.get("total_adult_cohorts", 0)),
		"max_bank_cohorts": int(initial_summary.get("total_bank_cohorts", 0)),
		"previous_occupancy": initial_occupancy,
		"ever_occupied": initial_occupancy.duplicate(true),
		"lineage_diagnostics": lineage_diagnostics.duplicate(true),
	}
	return world if validate_world(world) else {}

static func validate_world(world: Dictionary) -> bool:
	if String(world.get("schema", "")) != WORLD_SCHEMA or String(world.get("version", "")) != VERSION:
		return false
	var current_year := int(world.get("current_year", -1))
	var total_years := int(world.get("total_years", -1))
	if current_year < 0 or total_years <= 0 or total_years > Biogeography.MAX_YEARS or current_year > total_years:
		return false
	var patches: Dictionary = world.get("patches", {})
	var states: Dictionary = world.get("states", {})
	var strategies: Dictionary = world.get("strategies", {})
	if patches.is_empty() or patches.size() > Biogeography.MAX_PATCHES or states.size() != patches.size():
		return false
	if not Biogeography._valid_strategies(strategies):
		return false
	for patch_id in Biogeography._sorted_keys(patches):
		if not states.has(patch_id):
			return false
		if not PatchMigration.validate_patch(Dictionary(patches[patch_id])):
			return false
		if not DisturbanceRecovery._valid_state(Dictionary(states[patch_id]), strategies):
			return false
	var source_ids: Array = Array(world.get("source_patch_ids", []))
	if source_ids.is_empty():
		return false
	var seen_sources := {}
	for source_value in source_ids:
		var source_id := String(source_value)
		if not patches.has(source_id) or seen_sources.has(source_id):
			return false
		seen_sources[source_id] = true
	var transport_schedule: Array = Array(world.get("transport_schedule", []))
	if not Biogeography._validate_transport_schedule(transport_schedule):
		return false
	var disturbance_schedule: Dictionary = world.get("disturbance_schedule", {})
	var indexed := Biogeography._index_disturbances(disturbance_schedule, patches, total_years)
	if indexed.is_empty() and not disturbance_schedule.is_empty():
		return false
	for field_name in ["history", "transition_log", "migration_log", "disturbance_log"]:
		if typeof(world.get(field_name)) != TYPE_ARRAY:
			return false
	var history: Array = world["history"]
	if history.size() != current_year + 1 or history.is_empty():
		return false
	if int(Dictionary(history[history.size() - 1]).get("year", -1)) != current_year:
		return false
	if typeof(world.get("previous_occupancy")) != TYPE_DICTIONARY or typeof(world.get("ever_occupied")) != TYPE_DICTIONARY or typeof(world.get("lineage_diagnostics")) != TYPE_DICTIONARY:
		return false
	for field_name in ["cumulative_emitted_seed_count", "cumulative_routed_seed_count", "cumulative_unresolved_export_seed_count", "cumulative_recruited_seed_count", "cumulative_seed_bank_arrival_count", "cumulative_reactivated_seed_count", "max_adult_cohorts", "max_bank_cohorts"]:
		if int(world.get(field_name, -1)) < 0:
			return false
	return true

static func advance_to(world: Dictionary, target_year: int) -> Dictionary:
	if not validate_world(world):
		return {}
	var current_year := int(world["current_year"])
	var total_years := int(world["total_years"])
	if target_year < current_year or target_year > total_years:
		return {}
	var next := world.duplicate(true)
	var patches: Dictionary = next["patches"]
	var states: Dictionary = next["states"]
	var strategies: Dictionary = next["strategies"]
	var source_ids: Array = next["source_patch_ids"]
	var transport_schedule: Array = next["transport_schedule"]
	var disturbance_schedule: Dictionary = next["disturbance_schedule"]
	var events_by_patch_year := Biogeography._index_disturbances(disturbance_schedule, patches, total_years)
	if events_by_patch_year.is_empty() and not disturbance_schedule.is_empty():
		return {}
	var history: Array = next["history"]
	var transition_log: Array = next["transition_log"]
	var migration_log: Array = next["migration_log"]
	var disturbance_log: Array = next["disturbance_log"]
	var previous_occupancy: Dictionary = next["previous_occupancy"]
	var ever_occupied: Dictionary = next["ever_occupied"]
	for year in range(current_year + 1, target_year + 1):
		var transport := Biogeography._transport_for_year(transport_schedule, year)
		if transport.is_empty():
			return {}
		var target_patch_array: Array = []
		for patch_id in Biogeography._sorted_keys(patches):
			target_patch_array.append(patches[patch_id])
		for source_value in source_ids:
			var source_id := String(source_value)
			var source_patch: Dictionary = patches[source_id]
			var source_state: Dictionary = states[source_id]
			var aggregates := Biogeography._lineage_aggregates(Array(source_state["adults"]), strategies)
			if aggregates.is_empty():
				continue
			var targets: Array = []
			for target_value in target_patch_array:
				var target: Dictionary = target_value
				if String(target["patch_id"]) != source_id:
					targets.append(target)
			var environment: Dictionary = source_patch["environment"]
			var total_source_biomass := Biogeography._total_biomass(Array(source_state["adults"]))
			for lineage in Biogeography._sorted_keys(aggregates):
				var aggregate: Dictionary = aggregates[lineage]
				var strategy: Dictionary = strategies[lineage]
				var genome: Dictionary = strategy["genome"]
				var emitted := Biogeography._emitted_seed_count(lineage, year, aggregate, genome, environment, total_source_biomass)
				if emitted <= 0:
					continue
				var bounds := Rect2(source_patch["bounds"])
				var source_position := bounds.position + bounds.size * 0.5
				var migration := PatchMigration.migrate_reproduction_event(
					source_patch,
					targets,
					genome,
					strategy["recruitment_traits"],
					lineage,
					"p2-6/year/%d/%s/%s" % [year, source_id, lineage],
					source_position,
					emitted,
					maxf(float(aggregate["mean_height_m"]), 0.05),
					Vector2(transport["transport_vector"]),
					float(transport["turbulence"])
				)
				if migration.is_empty():
					return {}
				next["migration_all_conserve"] = bool(next["migration_all_conserve"]) and bool(migration.get("migration_conservation_ok", false)) and bool(migration.get("target_conservation_ok", false))
				next["cumulative_emitted_seed_count"] = int(next["cumulative_emitted_seed_count"]) + int(migration["emitted_seed_count"])
				next["cumulative_routed_seed_count"] = int(next["cumulative_routed_seed_count"]) + int(migration["routed_seed_count"])
				next["cumulative_unresolved_export_seed_count"] = int(next["cumulative_unresolved_export_seed_count"]) + int(migration["unresolved_export_seed_count"])
				var migration_record := {
					"year": year,
					"source_patch_id": source_id,
					"lineage_id": lineage,
					"emitted": int(migration["emitted_seed_count"]),
					"routed": int(migration["routed_seed_count"]),
					"unresolved": int(migration["unresolved_export_seed_count"]),
					"migration_hash": String(migration["result_hash"]),
				}
				migration_record["record_hash"] = Biogeography._migration_record_hash(migration_record)
				migration_log.append(migration_record)
				for target_value in targets:
					var target: Dictionary = target_value
					var target_id := String(target["patch_id"])
					var target_summary := PatchMigration.target_summary(migration, target_id)
					if target_summary.is_empty():
						return {}
					var recruited := int(target_summary["recruited_seed_count"])
					var banked := int(target_summary["seed_bank_seed_count"])
					if recruited <= 0 and banked <= 0:
						continue
					var arrival := Biogeography._apply_arrival(states[target_id], target, strategy, lineage, year, recruited, banked, String(migration["result_hash"]))
					if arrival.is_empty():
						return {}
					states[target_id] = arrival["state"]
					next["cumulative_recruited_seed_count"] = int(next["cumulative_recruited_seed_count"]) + recruited
					next["cumulative_seed_bank_arrival_count"] = int(next["cumulative_seed_bank_arrival_count"]) + banked
		for patch_id in Biogeography._sorted_keys(patches):
			var event_key := "%s|%d" % [patch_id, year]
			if not events_by_patch_year.has(event_key):
				continue
			var applied := DisturbanceRecovery.apply_event(states[patch_id], strategies, Dictionary(patches[patch_id])["environment"], events_by_patch_year[event_key])
			if applied.is_empty():
				return {}
			states[patch_id] = applied["state"]
			var record: Dictionary = applied["event_record"]
			next["disturbance_all_conserve"] = bool(next["disturbance_all_conserve"]) and bool(record.get("adult_conservation_ok", false)) and bool(record.get("seed_bank_conservation_ok", false))
			var logged := record.duplicate(true)
			logged["patch_id"] = patch_id
			disturbance_log.append(logged)
		for patch_id in Biogeography._sorted_keys(patches):
			var annual := DisturbanceRecovery.advance_year(states[patch_id], strategies, Dictionary(patches[patch_id])["environment"], year)
			if annual.is_empty():
				return {}
			states[patch_id] = annual["state"]
			next["cumulative_reactivated_seed_count"] = int(next["cumulative_reactivated_seed_count"]) + int(annual["reactivated_seed_count"])
		var summary := Biogeography._regional_summary(year, patches, states, strategies)
		if summary.is_empty():
			return {}
		var current_occupancy := Biogeography._adult_occupancy_map(summary, strategies)
		for key in Biogeography._sorted_keys(current_occupancy):
			var before := bool(previous_occupancy.get(key, false))
			var after := bool(current_occupancy[key])
			if before == after:
				continue
			var transition_type := "LOCAL_ADULT_EXTINCTION"
			if after:
				transition_type = "RECOLONIZATION" if bool(ever_occupied.get(key, false)) else "COLONIZATION"
				ever_occupied[key] = true
			var parts := key.split("|", false, 1)
			var transition := {"year": year, "patch_id": String(parts[0]), "lineage_id": String(parts[1]), "transition": transition_type}
			transition["transition_hash"] = Biogeography._transition_hash(transition)
			transition_log.append(transition)
		previous_occupancy = current_occupancy
		history.append(summary)
		next["max_adult_cohorts"] = maxi(int(next["max_adult_cohorts"]), int(summary["total_adult_cohorts"]))
		next["max_bank_cohorts"] = maxi(int(next["max_bank_cohorts"]), int(summary["total_bank_cohorts"]))
		next["current_year"] = year
		next["states"] = states
		next["history"] = history
		next["transition_log"] = transition_log
		next["migration_log"] = migration_log
		next["disturbance_log"] = disturbance_log
		next["previous_occupancy"] = previous_occupancy
		next["ever_occupied"] = ever_occupied
	return next if validate_world(next) else {}

static func to_biogeography_result(world: Dictionary) -> Dictionary:
	if not validate_world(world) or int(world["current_year"]) != int(world["total_years"]):
		return {}
	var history: Array = world["history"]
	var result := {
		"schema": Biogeography.SCHEMA,
		"version": Biogeography.VERSION,
		"years": int(world["total_years"]),
		"patch_count": Dictionary(world["patches"]).size(),
		"source_patch_ids": Array(world["source_patch_ids"]).duplicate(true),
		"history": history.duplicate(true),
		"transition_log": Array(world["transition_log"]).duplicate(true),
		"migration_log": Array(world["migration_log"]).duplicate(true),
		"disturbance_log": Array(world["disturbance_log"]).duplicate(true),
		"final_states": Dictionary(world["states"]).duplicate(true),
		"final_summary": Dictionary(history[history.size() - 1]).duplicate(true),
		"cumulative_emitted_seed_count": int(world["cumulative_emitted_seed_count"]),
		"cumulative_routed_seed_count": int(world["cumulative_routed_seed_count"]),
		"cumulative_unresolved_export_seed_count": int(world["cumulative_unresolved_export_seed_count"]),
		"cumulative_recruited_seed_count": int(world["cumulative_recruited_seed_count"]),
		"cumulative_seed_bank_arrival_count": int(world["cumulative_seed_bank_arrival_count"]),
		"cumulative_reactivated_seed_count": int(world["cumulative_reactivated_seed_count"]),
		"migration_all_conserve": bool(world["migration_all_conserve"]),
		"disturbance_all_conserve": bool(world["disturbance_all_conserve"]),
		"max_adult_cohorts": int(world["max_adult_cohorts"]),
		"max_bank_cohorts": int(world["max_bank_cohorts"]),
	}
	result["result_hash"] = Biogeography._result_hash(result)
	return result

static func world_hash(world: Dictionary) -> String:
	if not validate_world(world):
		return ""
	return _canonical_value(world).sha256_text()

static func value_hash(value) -> String:
	return _canonical_value(value).sha256_text()

static func serialize_checkpoint(world: Dictionary, evidence_context: Dictionary = {}) -> String:
	if not validate_world(world):
		return ""
	var document := {
		"schema": CHECKPOINT_SCHEMA,
		"version": VERSION,
		"world": world.duplicate(true),
		"world_hash": world_hash(world),
		"evidence_context": evidence_context.duplicate(true),
		"evidence_hash": value_hash(evidence_context),
	}
	document["checkpoint_hash"] = _checkpoint_hash(document)
	var encoded = _encode_value(document)
	if encoded == null:
		return ""
	return JSON.stringify(encoded, "", true, true)

static func deserialize_checkpoint(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var decoded = _decode_value(parsed)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {}
	var document: Dictionary = decoded
	if String(document.get("schema", "")) != CHECKPOINT_SCHEMA or String(document.get("version", "")) != VERSION:
		return {}
	if typeof(document.get("world")) != TYPE_DICTIONARY or typeof(document.get("evidence_context")) != TYPE_DICTIONARY:
		return {}
	var world: Dictionary = document["world"]
	var evidence: Dictionary = document["evidence_context"]
	if not validate_world(world):
		return {}
	if String(document.get("world_hash", "")) != world_hash(world):
		return {}
	if String(document.get("evidence_hash", "")) != value_hash(evidence):
		return {}
	if String(document.get("checkpoint_hash", "")) != _checkpoint_hash(document):
		return {}
	return document

static func write_checkpoint(path: String, serialized: String) -> bool:
	if path.is_empty() or deserialize_checkpoint(serialized).is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(serialized)
	file.close()
	return true

static func read_checkpoint(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	return deserialize_checkpoint(text)

static func serialized_checkpoint_hash(text: String) -> String:
	var document := deserialize_checkpoint(text)
	return "" if document.is_empty() else String(document.get("checkpoint_hash", ""))

static func _checkpoint_hash(document: Dictionary) -> String:
	var copy := document.duplicate(true)
	copy.erase("checkpoint_hash")
	return _canonical_value(copy).sha256_text()

static func _canonical_value(value) -> String:
	match typeof(value):
		TYPE_NIL:
			return "N"
		TYPE_BOOL:
			return "B1" if bool(value) else "B0"
		TYPE_INT:
			return "I" + str(int(value))
		TYPE_FLOAT:
			return "F%.17f" % float(value)
		TYPE_STRING, TYPE_STRING_NAME:
			var text := String(value)
			return "S%d:%s" % [text.length(), text]
		TYPE_VECTOR2:
			var vector := Vector2(value)
			return "V2(%.17f,%.17f)" % [vector.x, vector.y]
		TYPE_RECT2:
			var rect := Rect2(value)
			return "R2(%.17f,%.17f,%.17f,%.17f)" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		TYPE_PACKED_STRING_ARRAY:
			var packed := PackedStringArray(value)
			var tokens := PackedStringArray(["PSA", str(packed.size())])
			for item in packed:
				tokens.append(_canonical_value(String(item)))
			return "|".join(tokens)
		TYPE_ARRAY:
			var array: Array = value
			var tokens := PackedStringArray(["A", str(array.size())])
			for item in array:
				tokens.append(_canonical_value(item))
			return "|".join(tokens)
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var keys: Array[String] = []
			for key_value in dictionary.keys():
				keys.append(String(key_value))
			keys.sort()
			var tokens := PackedStringArray(["D", str(keys.size())])
			for key in keys:
				tokens.append(_canonical_value(key))
				tokens.append(_canonical_value(dictionary[key]))
			return "|".join(tokens)
		_:
			return "UNSUPPORTED:" + str(typeof(value))

static func _encode_value(value):
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_INT:
			return {"__eco_type": "Int", "value": int(value)}
		TYPE_FLOAT:
			return _encode_variant_bytes("Float64", float(value))
		TYPE_STRING_NAME:
			return {"__eco_type": "StringName", "value": String(value)}
		TYPE_VECTOR2:
			return _encode_variant_bytes("Vector2", Vector2(value))
		TYPE_RECT2:
			return _encode_variant_bytes("Rect2", Rect2(value))
		TYPE_PACKED_STRING_ARRAY:
			var values: Array = []
			for item in PackedStringArray(value):
				values.append(String(item))
			return {"__eco_type": "PackedStringArray", "values": values}
		TYPE_ARRAY:
			var encoded_values: Array = []
			for item in Array(value):
				var encoded = _encode_value(item)
				if encoded == null and item != null:
					return null
				encoded_values.append(encoded)
			return {"__eco_type": "Array", "values": encoded_values}
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var keys: Array[String] = []
			for key_value in dictionary.keys():
				if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
					return null
				keys.append(String(key_value))
			keys.sort()
			var entries: Array = []
			for key in keys:
				var encoded = _encode_value(dictionary[key])
				if encoded == null and dictionary[key] != null:
					return null
				entries.append([key, encoded])
			return {"__eco_type": "Dictionary", "entries": entries}
		_:
			return null

static func _decode_value(value):
	if typeof(value) != TYPE_DICTIONARY:
		return value
	var wrapper: Dictionary = value
	var type_name := String(wrapper.get("__eco_type", ""))
	match type_name:
		"Int":
			return int(wrapper.get("value", 0))
		"Float64":
			return _decode_variant_bytes(wrapper, TYPE_FLOAT)
		"StringName":
			return StringName(String(wrapper.get("value", "")))
		"Vector2":
			return _decode_variant_bytes(wrapper, TYPE_VECTOR2)
		"Rect2":
			return _decode_variant_bytes(wrapper, TYPE_RECT2)
		"PackedStringArray":
			var packed := PackedStringArray()
			for item in Array(wrapper.get("values", [])):
				packed.append(String(item))
			return packed
		"Array":
			var array: Array = []
			for item in Array(wrapper.get("values", [])):
				array.append(_decode_value(item))
			return array
		"Dictionary":
			var dictionary := {}
			for entry_value in Array(wrapper.get("entries", [])):
				var entry: Array = entry_value
				if entry.size() != 2:
					return null
				dictionary[String(entry[0])] = _decode_value(entry[1])
			return dictionary
		_:
			return null

static func _encode_variant_bytes(type_name: String, value) -> Dictionary:
	return {"__eco_type": type_name, "value": Marshalls.raw_to_base64(var_to_bytes(value))}

static func _decode_variant_bytes(wrapper: Dictionary, expected_type: int):
	var encoded := String(wrapper.get("value", ""))
	if encoded.is_empty():
		return null
	var raw := Marshalls.base64_to_raw(encoded)
	if raw.is_empty():
		return null
	var decoded = bytes_to_var(raw)
	return decoded if typeof(decoded) == expected_type else null
