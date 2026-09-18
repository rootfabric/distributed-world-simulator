extends RefCounted
## A10 R1 selective binding layer. It does not own or mutate production world state.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Body = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MatterQuery = preload("res://scripts/simulation/matter/query/matter_query_result.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const DamageRecord = preload("res://scripts/construction/damage/construction_damage_record.gd")

const SITE_SCHEMA := "dws.ecology.a10-world-site-binding.v1"
const DAMAGE_SCHEMA := "dws.ecology.a10-construction-damage-event.v1"
const CURSOR_FIELDS := ["entity_id", "region_id", "owner_id", "owner_epoch", "revision", "clock", "ecology_step"]
const ACTIVE_REGION_STATES := ["WARM", "ACTIVE"]

static func bind_matter_site(query: Dictionary, region: Dictionary, cursor: Dictionary) -> Dictionary:
	var qcheck: Dictionary = MatterQuery.validate(query)
	if not bool(qcheck.get("success", false)):
		return _fail("A10_MATTER_QUERY_INVALID")
	var rcheck: Dictionary = Region.validate(region)
	if not bool(rcheck.get("success", false)):
		return _fail("A10_REGION_INVALID")
	var cursor_error := _cursor_error(cursor, region)
	if not cursor_error.is_empty():
		return _fail(cursor_error)
	var cell: Dictionary = query["cell_address"]
	if String(cell.get("universe_id", "")) != String(region["universe_id"]) \
	or String(cell.get("instance_id", "")) != String(region["instance_id"]) \
	or String(cell.get("space_id", "")) != String(region["space_id"]):
		return _fail("A10_WORLD_SPACE_MISMATCH")
	if not _selector_contains_cell(region["selector"], String(cell["cell_id"])):
		return _fail("A10_REGION_SELECTOR_EXCLUDES_CELL")
	var sample: Dictionary = query["sample"]
	var value := {
		"schema": SITE_SCHEMA,
		"entity_id": String(cursor["entity_id"]),
		"body_id": String(query["body_id"]),
		"body_frame_id": String(query["body_frame_id"]),
		"region_id": String(region["region_id"]),
		"owner_node_id": String(region["owner_node_id"]),
		"authority_epoch": int(region["authority_epoch"]),
		"region_descriptor_revision": int(region["descriptor_revision"]),
		"query_id": String(query["query_id"]),
		"query_source": String(query["source"]),
		"matter_state_revision": int(query["state_revision"]),
		"cell_id": String(cell["cell_id"]),
		"brick_id": String(query["brick_address"]["address_id"]),
		"local_position_m": Array(query["local_position_m"]).duplicate(),
		"physical_sample": {
			"signed_distance_m": float(sample["signed_distance_m"]),
			"occupancy_ratio": float(sample["occupancy_ratio"]),
			"density_kg_m3": float(sample["density_kg_m3"]),
			"composition": Dictionary(sample["composition"]).duplicate(true),
			"integrity_ratio": float(sample["integrity_ratio"]),
			"temperature_k": float(sample["temperature_k"]),
			"porosity_ratio": float(sample["porosity_ratio"]),
			"flags": Array(sample["flags"]).duplicate(),
		},
		"resource_stock_authority": "NOT_DERIVED_FROM_POINT_SAMPLE",
		"binding_hash": "",
	}
	value["binding_hash"] = _hash_without(value, "binding_hash")
	if String(value["binding_hash"]).is_empty():
		return _fail("A10_BINDING_HASH")
	return {"success": true, "binding": value}

static func project_construction_damage(
	request: Dictionary,
	record: Dictionary,
	source_snapshot: Dictionary,
	body_modules: Array,
	part_to_module: Dictionary
) -> Dictionary:
	var qcheck: Dictionary = DamageRequest.validate(request)
	if not bool(qcheck.get("success", false)):
		return _fail("A10_DAMAGE_REQUEST_INVALID")
	var rcheck: Dictionary = DamageRecord.validate(record)
	if not bool(rcheck.get("success", false)):
		return _fail("A10_DAMAGE_RECORD_INVALID")
	var scheck: Dictionary = Snapshot.validate(source_snapshot)
	if not bool(scheck.get("success", false)):
		return _fail("A10_DAMAGE_SOURCE_SNAPSHOT_INVALID")
	var body_error := Body.validate(body_modules)
	if not body_error.is_empty():
		return _fail("A10_DAMAGE_BODY_INVALID")
	if String(source_snapshot["construct_id"]) != String(request["construct_id"]) \
	or String(source_snapshot["checksum"]) != String(request["source_snapshot_checksum"]):
		return _fail("A10_DAMAGE_SOURCE_SNAPSHOT_MISMATCH")
	if String(record["status"]) != "APPLIED":
		return _fail("A10_DAMAGE_RECORD_NOT_APPLIED")
	if String(record["damage_id"]) != String(request["damage_id"]) \
	or String(record["request_checksum"]) != String(request["checksum"]):
		return _fail("A10_DAMAGE_REQUEST_RECORD_MISMATCH")
	var repair_plan: Dictionary = record["repair_plan"]
	if String(repair_plan.get("damage_id", "")) != String(request["damage_id"]) \
	or String(repair_plan.get("damage_request_checksum", "")) != String(request["checksum"]):
		return _fail("A10_DAMAGE_REPAIR_BINDING_MISMATCH")
	var target_snapshot: Dictionary = repair_plan.get("target_snapshot", {})
	if String(target_snapshot.get("construct_id", "")) != String(request["construct_id"]):
		return _fail("A10_DAMAGE_TARGET_CONSTRUCT_MISMATCH")
	var source_part_ids := {}
	for raw_part in source_snapshot["parts"]:
		source_part_ids[String(raw_part["part_id"])] = true
	if not source_part_ids.has(String(request["retained_part_id"])):
		return _fail("A10_DAMAGE_RETAINED_PART_NOT_IN_SOURCE")
	var map_error := _part_map_error(part_to_module, body_modules, source_part_ids)
	if not map_error.is_empty():
		return _fail(map_error)
	var events: Array = []
	var affected: Array = request["part_conditions"].keys()
	affected.sort()
	for raw_part_id in affected:
		var part_id := String(raw_part_id)
		if not source_part_ids.has(part_id):
			return _fail("A10_DAMAGE_PART_NOT_IN_SOURCE")
		var condition := String(request["part_conditions"][raw_part_id])
		if condition == "INTACT":
			continue
		if not part_to_module.has(part_id):
			return _fail("A10_DAMAGE_PART_UNBOUND")
		var module_id := String(part_to_module[part_id])
		events.append({
			"part_id": part_id,
			"module_id": module_id,
			"condition": condition,
			"severity_milli": 500 if condition == "DEGRADED" else 1000,
		})
	var value := {
		"schema": DAMAGE_SCHEMA,
		"damage_id": String(request["damage_id"]),
		"construct_id": String(request["construct_id"]),
		"source_snapshot_checksum": String(source_snapshot["checksum"]),
		"body_hash": C.digest(body_modules),
		"request_checksum": String(request["checksum"]),
		"record_checksum": String(record["checksum"]),
		"applied_generation": int(record["applied_generation"]),
		"events": events,
		"binding_hash": "",
	}
	value["binding_hash"] = _hash_without(value, "binding_hash")
	if String(value["body_hash"]).is_empty() or String(value["binding_hash"]).is_empty():
		return _fail("A10_DAMAGE_BINDING_HASH")
	return {"success": true, "event": value}

static func admit_cursor(cursor: Dictionary, region: Dictionary) -> Dictionary:
	var rcheck: Dictionary = Region.validate(region)
	if not bool(rcheck.get("success", false)):
		return _fail("A10_REGION_INVALID")
	var error := _cursor_error(cursor, region)
	return {"success": true} if error.is_empty() else _fail(error)

static func _cursor_error(cursor: Dictionary, region: Dictionary) -> String:
	if not C.keys(cursor, CURSOR_FIELDS):
		return "A10_CURSOR_SCHEMA"
	for field in ["entity_id", "region_id", "owner_id"]:
		if not C.identifier(cursor.get(field, "")):
			return "A10_CURSOR_IDENTITY"
	for field in ["owner_epoch", "revision", "clock", "ecology_step"]:
		if not C.integer(cursor.get(field), 0 if field != "owner_epoch" else 1, C.MAX_INT):
			return "A10_CURSOR_VERSION"
	if not ACTIVE_REGION_STATES.has(String(region["lifecycle_state"])):
		return "A10_REGION_NOT_EXECUTABLE"
	if String(cursor["region_id"]) != String(region["region_id"]):
		return "A10_CURSOR_REGION_MISMATCH"
	if String(cursor["owner_id"]) != String(region["owner_node_id"]):
		return "A10_CURSOR_OWNER_MISMATCH"
	if int(cursor["owner_epoch"]) != int(region["authority_epoch"]):
		return "A10_CURSOR_EPOCH_MISMATCH"
	return ""

static func _selector_contains_cell(selector: Dictionary, cell_id: String) -> bool:
	match String(selector.get("kind", "")):
		"GLOBAL_SPACE":
			return true
		"CHUNK_SET":
			return Array(selector.get("chunk_ids", [])).has(cell_id)
		"PARTITION_PREFIX":
			return cell_id.begins_with(String(selector.get("partition_prefix", "")))
		_:
			return false

static func _part_map_error(part_to_module: Dictionary, body_modules: Array, source_part_ids: Dictionary) -> String:
	var valid_modules := {}
	for module in body_modules:
		valid_modules[String(module["id"])] = true
	var module_ids := {}
	for raw_part in part_to_module.keys():
		if not raw_part is String or not String(raw_part).begins_with("part/"):
			return "A10_PART_BINDING_ID"
		if not source_part_ids.has(String(raw_part)):
			return "A10_PART_BINDING_UNKNOWN_SOURCE"
		var module_id = part_to_module[raw_part]
		if not module_id is String or not C.identifier(module_id):
			return "A10_MODULE_BINDING_ID"
		if not valid_modules.has(String(module_id)):
			return "A10_MODULE_BINDING_UNKNOWN"
		if module_ids.has(module_id):
			return "A10_MODULE_BINDING_NOT_ONE_TO_ONE"
		module_ids[module_id] = true
	return ""

static func _hash_without(value: Dictionary, field: String) -> String:
	var payload := value.duplicate(true)
	payload[field] = ""
	return MatterUtils.payload_hash(payload)

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
