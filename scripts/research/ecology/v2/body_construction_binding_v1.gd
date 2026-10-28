extends RefCounted
## A10 R4 persistent world damage overlay over immutable historical A5 BodyGraph state.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")

const BINDING_SCHEMA := "dws.ecology.a10-body-construction-binding.v1"
const OVERLAY_SCHEMA := "dws.ecology.a10-body-damage-overlay.v1"
const FUNCTION_SCHEMA := "dws.ecology.a10-effective-body-function.v1"

static func create_binding(body_modules: Array, source_snapshot: Dictionary, part_to_module: Dictionary) -> Dictionary:
	if not Body.validate(body_modules).is_empty():
		return {}
	if not bool(Snapshot.validate(source_snapshot).get("success", false)):
		return {}
	var part_ids := {}
	for part in source_snapshot["parts"]:
		part_ids[String(part["part_id"])] = true
	var module_ids := {}
	for module in body_modules:
		module_ids[String(module["id"])] = true
	var normalized := {}
	var used_modules := {}
	var keys: Array = part_to_module.keys()
	keys.sort()
	for raw_part in keys:
		if not raw_part is String:
			return {}
		var part_id := String(raw_part)
		var module_id = part_to_module[raw_part]
		if not module_id is String or not part_ids.has(part_id) or not module_ids.has(String(module_id)):
			return {}
		if used_modules.has(module_id):
			return {}
		normalized[part_id] = String(module_id)
		used_modules[module_id] = true
	var mapped: Array = used_modules.keys()
	mapped.sort()
	var unmapped: Array = []
	for module in body_modules:
		var module_id := String(module["id"])
		if not used_modules.has(module_id):
			unmapped.append(module_id)
	unmapped.sort()
	var value := {
		"schema": BINDING_SCHEMA,
		"scope": "PARTIAL_PHYSICAL_PROXY",
		"body_hash": C.digest(body_modules),
		"construct_id": String(source_snapshot["construct_id"]),
		"source_snapshot_checksum": String(source_snapshot["checksum"]),
		"part_to_module": normalized,
		"mapped_module_ids": mapped,
		"unmapped_module_ids": unmapped,
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value if validate_binding(value, body_modules, source_snapshot).is_empty() else {}

static func validate_binding(binding: Dictionary, body_modules: Array, source_snapshot: Dictionary) -> String:
	if not Body.validate(body_modules).is_empty():
		return "A10_R4_BODY_INVALID"
	if not bool(Snapshot.validate(source_snapshot).get("success", false)):
		return "A10_R4_SNAPSHOT_INVALID"
	var fields: Array[String] = [
		"schema", "scope", "body_hash", "construct_id", "source_snapshot_checksum",
		"part_to_module", "mapped_module_ids", "unmapped_module_ids", "checksum",
	]
	var exact := MatterUtils.validate_exact_fields(binding, fields)
	if not bool(exact.get("success", false)):
		return "A10_R4_BINDING_FIELDS"
	if binding.get("schema") != BINDING_SCHEMA or binding.get("scope") != "PARTIAL_PHYSICAL_PROXY":
		return "A10_R4_BINDING_SCHEMA"
	if String(binding.get("body_hash", "")) != C.digest(body_modules):
		return "A10_R4_BODY_HASH"
	if String(binding.get("construct_id", "")) != String(source_snapshot["construct_id"]) \
	or String(binding.get("source_snapshot_checksum", "")) != String(source_snapshot["checksum"]):
		return "A10_R4_SNAPSHOT_BINDING"
	if not binding.get("part_to_module") is Dictionary:
		return "A10_R4_MAPPING"
	var expected := create_binding_unchecked(body_modules, source_snapshot, binding["part_to_module"])
	if expected.is_empty():
		return "A10_R4_MAPPING"
	for field in ["body_hash", "construct_id", "source_snapshot_checksum", "part_to_module", "mapped_module_ids", "unmapped_module_ids"]:
		if binding[field] != expected[field]:
			return "A10_R4_BINDING_DERIVED"
	if String(binding.get("checksum", "")) != MatterUtils.compute_checksum(binding):
		return "A10_R4_BINDING_CHECKSUM"
	return ""

static func create_overlay(binding: Dictionary, body_modules: Array, source_snapshot: Dictionary) -> Dictionary:
	if not validate_binding(binding, body_modules, source_snapshot).is_empty():
		return {}
	var value := {
		"schema": OVERLAY_SCHEMA,
		"binding_checksum": String(binding["checksum"]),
		"body_hash": String(binding["body_hash"]),
		"construct_id": String(binding["construct_id"]),
		"source_snapshot_checksum": String(binding["source_snapshot_checksum"]),
		"revision": 0,
		"degraded_modules": [],
		"destroyed_modules": [],
		"disabled_modules": [],
		"applied_damage": {},
		"checksum": "",
	}
	value["checksum"] = MatterUtils.compute_checksum(value)
	return value

static func apply_damage(binding: Dictionary, overlay: Dictionary, body_modules: Array, source_snapshot: Dictionary, event: Dictionary, expected_event_binding_hash: String) -> Dictionary:
	var binding_error := validate_binding(binding, body_modules, source_snapshot)
	if not binding_error.is_empty():
		return _fail(binding_error)
	var overlay_error := validate_overlay(overlay, binding, body_modules, source_snapshot)
	if not overlay_error.is_empty():
		return _fail(overlay_error)
	var event_error := _event_error(event, binding)
	if not event_error.is_empty():
		return _fail(event_error)
	if not MatterUtils.is_lower_hex_64(expected_event_binding_hash) \
	or String(event.get("binding_hash", "")) != expected_event_binding_hash:
		return _fail("A10_R4_EVENT_EXTERNAL_ANCHOR")
	var event_hash := MatterUtils.payload_hash(event)
	var damage_id := String(event["damage_id"])
	if overlay["applied_damage"].has(damage_id):
		if String(overlay["applied_damage"][damage_id]) != event_hash:
			return _fail("A10_R4_DAMAGE_ID_CONFLICT")
		return {"success": true, "replay": true, "overlay": overlay.duplicate(true)}
	var degraded := _set_from_array(overlay["degraded_modules"])
	var destroyed := _set_from_array(overlay["destroyed_modules"])
	var disabled := _set_from_array(overlay["disabled_modules"])
	for row in event["events"]:
		var module_id := String(row["module_id"])
		if String(row["condition"]) == "DESTROYED":
			destroyed[module_id] = true
			disabled[module_id] = true
			for descendant in _descendants(body_modules, module_id):
				disabled[descendant] = true
		else:
			if not disabled.has(module_id):
				degraded[module_id] = true
	for module_id in disabled.keys():
		degraded.erase(module_id)
	var next := overlay.duplicate(true)
	next["revision"] = int(overlay["revision"]) + 1
	next["degraded_modules"] = _sorted_keys(degraded)
	next["destroyed_modules"] = _sorted_keys(destroyed)
	next["disabled_modules"] = _sorted_keys(disabled)
	var receipts: Dictionary = overlay["applied_damage"].duplicate(true)
	receipts[damage_id] = event_hash
	next["applied_damage"] = _sorted_dictionary(receipts)
	next["checksum"] = MatterUtils.compute_checksum(next)
	var error := validate_overlay(next, binding, body_modules, source_snapshot)
	if not error.is_empty():
		return _fail(error)
	return {"success": true, "replay": false, "overlay": next}

static func validate_overlay(overlay: Dictionary, binding: Dictionary, body_modules: Array, source_snapshot: Dictionary) -> String:
	var binding_error := validate_binding(binding, body_modules, source_snapshot)
	if not binding_error.is_empty():
		return binding_error
	var fields: Array[String] = [
		"schema", "binding_checksum", "body_hash", "construct_id", "source_snapshot_checksum",
		"revision", "degraded_modules", "destroyed_modules", "disabled_modules",
		"applied_damage", "checksum",
	]
	var exact := MatterUtils.validate_exact_fields(overlay, fields)
	if not bool(exact.get("success", false)):
		return "A10_R4_OVERLAY_FIELDS"
	if overlay.get("schema") != OVERLAY_SCHEMA:
		return "A10_R4_OVERLAY_SCHEMA"
	for field in ["binding_checksum", "body_hash", "construct_id", "source_snapshot_checksum"]:
		var expected = {
			"binding_checksum": binding["checksum"],
			"body_hash": binding["body_hash"],
			"construct_id": binding["construct_id"],
			"source_snapshot_checksum": binding["source_snapshot_checksum"],
		}[field]
		if overlay.get(field) != expected:
			return "A10_R4_OVERLAY_BINDING"
	if not MatterUtils.is_json_integer(overlay.get("revision")) or int(overlay["revision"]) < 0:
		return "A10_R4_OVERLAY_REVISION"
	var module_ids := {}
	for module in body_modules:
		module_ids[String(module["id"])] = true
	for field in ["degraded_modules", "destroyed_modules", "disabled_modules"]:
		if not overlay.get(field) is Array or overlay[field] != _sorted_unique(overlay[field]):
			return "A10_R4_OVERLAY_MODULE_SET"
		for module_id in overlay[field]:
			if not module_id is String or not module_ids.has(String(module_id)):
				return "A10_R4_OVERLAY_UNKNOWN_MODULE"
	var disabled := _set_from_array(overlay["disabled_modules"])
	var expected_disabled := {}
	for module_id in overlay["destroyed_modules"]:
		expected_disabled[String(module_id)] = true
		for descendant in _descendants(body_modules, String(module_id)):
			expected_disabled[String(descendant)] = true
	if _sorted_keys(expected_disabled) != overlay["disabled_modules"]:
		return "A10_R4_DISABLED_CLOSURE"
	for module_id in overlay["degraded_modules"]:
		if disabled.has(module_id):
			return "A10_R4_DEGRADED_DISABLED_CONFLICT"
	if not overlay.get("applied_damage") is Dictionary:
		return "A10_R4_DAMAGE_RECEIPTS"
	if overlay["applied_damage"].size() != int(overlay["revision"]):
		return "A10_R4_DAMAGE_REVISION"
	for damage_id in overlay["applied_damage"]:
		if not damage_id is String or not String(damage_id).begins_with("damage/") \
		or not MatterUtils.is_lower_hex_64(overlay["applied_damage"][damage_id]):
			return "A10_R4_DAMAGE_RECEIPT"
	if String(overlay.get("checksum", "")) != MatterUtils.compute_checksum(overlay):
		return "A10_R4_OVERLAY_CHECKSUM"
	return ""

static func admit_overlay(
	overlay: Dictionary,
	binding: Dictionary,
	body_modules: Array,
	source_snapshot: Dictionary,
	expected_overlay_checksum: String
) -> Dictionary:
	if not MatterUtils.is_lower_hex_64(expected_overlay_checksum) \
	or String(overlay.get("checksum", "")) != expected_overlay_checksum:
		return _fail("A10_R4_OVERLAY_EXTERNAL_ANCHOR")
	var error := validate_overlay(overlay, binding, body_modules, source_snapshot)
	if not error.is_empty():
		return _fail(error)
	return {"success": true, "overlay": overlay.duplicate(true)}

static func effective_function(binding: Dictionary, overlay: Dictionary, body_modules: Array, source_snapshot: Dictionary) -> Dictionary:
	if not validate_overlay(overlay, binding, body_modules, source_snapshot).is_empty():
		return {}
	var disabled := _set_from_array(overlay["disabled_modules"])
	var active_ids: Array = []
	var collector_area := 0
	var absorber_reach := 0
	var support_material := 0
	for module in body_modules:
		var module_id := String(module["id"])
		if disabled.has(module_id):
			continue
		active_ids.append(module_id)
		if String(module["role"]) == "collector":
			collector_area += int(module["area_mm2"])
		if String(module["role"]) == "absorber":
			absorber_reach += int(module["reach_mm"])
		if String(module["role"]) in ["support", "transport"]:
			support_material += int(module["cost"]["material_mg"])
	var result := {
		"schema": FUNCTION_SCHEMA,
		"body_hash": String(binding["body_hash"]),
		"overlay_checksum": String(overlay["checksum"]),
		"active_module_ids": active_ids,
		"active_module_count": active_ids.size(),
		"collector_area_mm2": collector_area,
		"absorber_reach_mm": absorber_reach,
		"support_material_proxy_mg": support_material,
		"degraded_modules": Array(overlay["degraded_modules"]).duplicate(),
		"destroyed_modules": Array(overlay["destroyed_modules"]).duplicate(),
		"disabled_modules": Array(overlay["disabled_modules"]).duplicate(),
		"functional_hash": "",
	}
	result["functional_hash"] = _hash_without(result, "functional_hash")
	return result

static func create_binding_unchecked(body_modules: Array, source_snapshot: Dictionary, part_to_module: Dictionary) -> Dictionary:
	var part_ids := {}
	for part in source_snapshot["parts"]:
		part_ids[String(part["part_id"])] = true
	var module_ids := {}
	for module in body_modules:
		module_ids[String(module["id"])] = true
	var normalized := {}
	var used := {}
	var keys: Array = part_to_module.keys()
	keys.sort()
	for raw_part in keys:
		if not raw_part is String:
			return {}
		var part_id := String(raw_part)
		var module_id = part_to_module[raw_part]
		if not module_id is String or not part_ids.has(part_id) or not module_ids.has(String(module_id)) or used.has(module_id):
			return {}
		normalized[part_id] = String(module_id)
		used[module_id] = true
	var mapped: Array = used.keys()
	mapped.sort()
	var unmapped: Array = []
	for module in body_modules:
		if not used.has(String(module["id"])):
			unmapped.append(String(module["id"]))
	unmapped.sort()
	return {
		"schema": BINDING_SCHEMA, "scope": "PARTIAL_PHYSICAL_PROXY",
		"body_hash": C.digest(body_modules), "construct_id": String(source_snapshot["construct_id"]),
		"source_snapshot_checksum": String(source_snapshot["checksum"]), "part_to_module": normalized,
		"mapped_module_ids": mapped, "unmapped_module_ids": unmapped, "checksum": "",
	}

static func _binding_record_valid(binding: Dictionary) -> bool:
	var fields: Array[String] = [
		"schema", "scope", "body_hash", "construct_id", "source_snapshot_checksum",
		"part_to_module", "mapped_module_ids", "unmapped_module_ids", "checksum",
	]
	var exact := MatterUtils.validate_exact_fields(binding, fields)
	return bool(exact.get("success", false)) \
		and binding.get("schema") == BINDING_SCHEMA \
		and binding.get("scope") == "PARTIAL_PHYSICAL_PROXY" \
		and MatterUtils.is_lower_hex_64(binding.get("body_hash")) \
		and MatterUtils.is_lower_hex_64(binding.get("source_snapshot_checksum")) \
		and MatterUtils.is_lower_hex_64(binding.get("checksum")) \
		and String(binding["checksum"]) == MatterUtils.compute_checksum(binding)

static func _event_error(event: Dictionary, binding: Dictionary) -> String:
	var fields: Array[String] = [
		"schema", "damage_id", "construct_id", "source_snapshot_checksum", "body_hash",
		"request_checksum", "record_checksum", "applied_generation", "events", "binding_hash",
	]
	var exact := MatterUtils.validate_exact_fields(event, fields)
	if not bool(exact.get("success", false)):
		return "A10_R4_EVENT_FIELDS"
	if event.get("schema") != "dws.ecology.a10-construction-damage-event.v1":
		return "A10_R4_EVENT_SCHEMA"
	if not String(event.get("damage_id", "")).begins_with("damage/"):
		return "A10_R4_EVENT_ID"
	for checksum_field in ["request_checksum", "record_checksum", "binding_hash"]:
		if not MatterUtils.is_lower_hex_64(event.get(checksum_field)):
			return "A10_R4_EVENT_CHECKSUM"
	if not MatterUtils.is_json_integer(event.get("applied_generation")) or int(event["applied_generation"]) < 0:
		return "A10_R4_EVENT_GENERATION"
	if String(event.get("construct_id", "")) != String(binding["construct_id"]) \
	or String(event.get("source_snapshot_checksum", "")) != String(binding["source_snapshot_checksum"]) \
	or String(event.get("body_hash", "")) != String(binding["body_hash"]):
		return "A10_R4_EVENT_BINDING"
	var expected_hash := _hash_without(event, "binding_hash")
	if String(event.get("binding_hash", "")) != expected_hash:
		return "A10_R4_EVENT_HASH"
	if not event.get("events") is Array or event["events"].is_empty():
		return "A10_R4_EVENT_EMPTY"
	for row in event["events"]:
		if not row is Dictionary or row.keys().size() != 4:
			return "A10_R4_EVENT_ROW"
		for field in ["part_id", "module_id", "condition", "severity_milli"]:
			if not row.has(field):
				return "A10_R4_EVENT_ROW"
		var part_id := String(row["part_id"])
		var module_id := String(row["module_id"])
		if not binding["part_to_module"].has(part_id) or String(binding["part_to_module"][part_id]) != module_id:
			return "A10_R4_EVENT_MAPPING"
		var condition := String(row["condition"])
		if condition not in ["DEGRADED", "DESTROYED"]:
			return "A10_R4_EVENT_CONDITION"
		var expected_severity := 500 if condition == "DEGRADED" else 1000
		if not MatterUtils.is_json_integer(row["severity_milli"]) or int(row["severity_milli"]) != expected_severity:
			return "A10_R4_EVENT_SEVERITY"
	return ""

static func _descendants(body_modules: Array, root_id: String) -> Array:
	var descendants := {}
	var frontier: Array = [root_id]
	while not frontier.is_empty():
		var current = frontier.pop_back()
		for module in body_modules:
			var module_id := String(module["id"])
			if String(module["parent"]) == String(current) and not descendants.has(module_id):
				descendants[module_id] = true
				frontier.append(module_id)
	return _sorted_keys(descendants)

static func _set_from_array(values: Array) -> Dictionary:
	var out := {}
	for value in values:
		out[String(value)] = true
	return out

static func _sorted_keys(value: Dictionary) -> Array:
	var out: Array = value.keys()
	out.sort()
	return out

static func _sorted_unique(values: Array) -> Array:
	var set := _set_from_array(values)
	return _sorted_keys(set)

static func _sorted_dictionary(value: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = value.keys()
	keys.sort()
	for key in keys:
		out[key] = value[key]
	return out

static func _hash_without(value: Dictionary, field: String) -> String:
	var payload := value.duplicate(true)
	payload[field] = ""
	return MatterUtils.payload_hash(payload)

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
