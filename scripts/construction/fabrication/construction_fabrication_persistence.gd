extends RefCounted
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CatalogScript = preload("res://scripts/construction/fabrication/construction_fabrication_catalog.gd")
const QueueScript = preload("res://scripts/construction/fabrication/construction_fabrication_queue_store.gd")
const SCHEMA := "planet_simulator.construction_fabrication_state.v1"
const FIELDS: Array[String] = ["schema", "catalog", "queue", "checksum"]
var _catalog; var _queue; var _store; var _state_key := "construction-fabrication"
func setup(catalog, queue_store, state_store, state_key: String = "construction-fabrication") -> Dictionary:
	if catalog == null or not catalog.has_method("to_dict") or queue_store == null or not queue_store.has_method("to_dict"): return _failure("CONSTRUCTION_FABRICATION_PERSISTENCE_DOMAIN_REQUIRED")
	if state_store == null or not state_store.has_method("save_state") or not state_store.has_method("load_state"): return _failure("CONSTRUCTION_FABRICATION_STATE_STORE_REQUIRED")
	_catalog = catalog; _queue = queue_store; _store = state_store; _state_key = state_key; return _success()
func save() -> Dictionary:
	var state := create_state(_catalog.to_dict(), _queue.to_dict()); var result: Dictionary = _store.save_state(_state_key, state)
	if not bool(result.get("success", false)): return result
	return _success({"checksum": String(state["checksum"]), "state": state})
func load() -> Dictionary:
	var loaded: Dictionary = _store.load_state(_state_key); if not bool(loaded.get("success", false)): return loaded
	var state = loaded.get("state", {}); if typeof(state) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_FABRICATION_PERSISTED_STATE")
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var candidate_catalog = CatalogScript.new(); candidate_catalog.setup(); var catalog_load := candidate_catalog.load_dict(state["catalog"]); if not bool(catalog_load.get("success", false)): return catalog_load
	var candidate_queue = QueueScript.new(); candidate_queue.setup(); var queue_load := candidate_queue.load_dict(state["queue"]); if not bool(queue_load.get("success", false)): return queue_load
	var live_catalog: Dictionary = _catalog.load_dict(candidate_catalog.to_dict()); if not bool(live_catalog.get("success", false)): return live_catalog
	var live_queue: Dictionary = _queue.load_dict(candidate_queue.to_dict()); if not bool(live_queue.get("success", false)): return live_queue
	return _success({"checksum": String(state["checksum"])})
static func create_state(catalog: Dictionary, queue: Dictionary) -> Dictionary:
	var value := {"schema": SCHEMA, "catalog": catalog.duplicate(true), "queue": queue.duplicate(true), "checksum": ""}; value["checksum"] = compute_checksum(value); return value
static func validate_state(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_FABRICATION_STATE_SCHEMA")
	if typeof(value.get("catalog")) != TYPE_DICTIONARY or typeof(value.get("queue")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_FABRICATION_STATE_SECTIONS")
	var checked := CatalogScript.validate_state(value["catalog"]); if not bool(checked.get("success", false)): return checked
	checked = QueueScript.validate_state(value["queue"]); if not bool(checked.get("success", false)): return checked
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("CONSTRUCTION_FABRICATION_STATE_CHECKSUM_MISMATCH")
	return _success()
static func compute_checksum(value: Dictionary) -> String: var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
