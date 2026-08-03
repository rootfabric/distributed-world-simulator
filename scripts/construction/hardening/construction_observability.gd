extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const STATE_SCHEMA := "planet_simulator.construction_observability_state.v1"
const STATE_FIELDS: Array[String] = ["schema", "counters", "gauges", "audit", "checksum"]
const ALLOWED_COUNTERS: Array[String] = [
	"operations_accepted", "operations_denied", "operations_rate_limited",
	"operations_replayed", "operations_failed", "checkpoints_recovered",
]
const ALLOWED_GAUGES: Array[String] = ["replay_entries", "audit_events", "rate_limit_subjects"]
const AUDIT_DECISIONS: Array[String] = ["ACCEPT", "DENY", "FAIL", "RATE_LIMIT", "REPLAY"]
const MAX_SAFE_JSON_INTEGER := 9007199254740991
const AUDIT_FIELDS: Array[String] = [
	"event_index", "operation_id", "subject_id", "construct_id", "action",
	"decision", "error_code", "tick", "previous_hash", "checksum",
]

var _counters: Dictionary = {}
var _gauges: Dictionary = {}
var _audit: Array = []

func _init() -> void:
	for name in ALLOWED_COUNTERS:
		_counters[name] = 0
	for name in ALLOWED_GAUGES:
		_gauges[name] = 0

func increment(name: String, amount: int = 1) -> Dictionary:
	if not ALLOWED_COUNTERS.has(name) or not H.is_non_negative_integer(amount):
		return H.failure("INVALID_CONSTRUCTION_METRIC_COUNTER")
	if int(_counters[name]) > MAX_SAFE_JSON_INTEGER - amount:
		return H.failure("INVALID_CONSTRUCTION_METRIC_COUNTER")
	_counters[name] = int(_counters[name]) + amount
	return H.success()

func set_gauge(name: String, value: int) -> Dictionary:
	if not ALLOWED_GAUGES.has(name) or not H.is_non_negative_integer(value):
		return H.failure("INVALID_CONSTRUCTION_METRIC_GAUGE")
	_gauges[name] = value
	return H.success()

func append_audit(operation: Dictionary, decision: String, error_code: String, tick: int) -> Dictionary:
	if not AUDIT_DECISIONS.has(decision) or not H.is_non_negative_integer(tick):
		return H.failure("INVALID_CONSTRUCTION_AUDIT_EVENT")
	if not H.is_path_id(operation.get("operation_id"), "operation/") or not H.is_path_id(operation.get("subject_id"), "subject/") or not H.is_path_id(operation.get("construct_id"), "construct/") or not H.is_token(operation.get("action")):
		return H.failure("INVALID_CONSTRUCTION_AUDIT_EVENT")
	if not error_code.is_empty() and not H.is_token(error_code):
		return H.failure("INVALID_CONSTRUCTION_AUDIT_ERROR_CODE")
	var previous_hash := ""
	if not _audit.is_empty():
		previous_hash = String(_audit.back()["checksum"])
	var event := {
		"event_index": _audit.size(),
		"operation_id": String(operation.get("operation_id", "operation/invalid")),
		"subject_id": String(operation.get("subject_id", "subject/invalid")),
		"construct_id": String(operation.get("construct_id", "construct/invalid")),
		"action": String(operation.get("action", "invalid")),
		"decision": decision,
		"error_code": error_code,
		"tick": tick,
		"previous_hash": previous_hash,
		"checksum": "",
	}
	event["checksum"] = H.checksum(event)
	_audit.append(event)
	_gauges["audit_events"] = _audit.size()
	return H.success({"event": event.duplicate(true)})

func get_counter(name: String) -> int:
	return int(_counters.get(name, 0))

func get_gauge(name: String) -> int:
	return int(_gauges.get(name, 0))

func get_audit_events() -> Array:
	return _audit.duplicate(true)

func export_state() -> Dictionary:
	var state := {
		"schema": STATE_SCHEMA,
		"counters": _counters.duplicate(true),
		"gauges": _gauges.duplicate(true),
		"audit": _audit.duplicate(true),
		"checksum": "",
	}
	state["checksum"] = H.checksum(state)
	return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state)
	if not bool(checked.get("success", false)):
		return checked
	_counters = Dictionary(state["counters"]).duplicate(true)
	_gauges = Dictionary(state["gauges"]).duplicate(true)
	_audit = Array(state["audit"]).duplicate(true)
	return H.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := H.exact_fields(state, STATE_FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_OBSERVABILITY_STATE_FIELDS")
	if state.get("schema") != STATE_SCHEMA or typeof(state.get("counters")) != TYPE_DICTIONARY or typeof(state.get("gauges")) != TYPE_DICTIONARY or typeof(state.get("audit")) != TYPE_ARRAY:
		return H.failure("INVALID_CONSTRUCTION_OBSERVABILITY_STATE")
	if state["counters"].keys().size() != ALLOWED_COUNTERS.size() or state["gauges"].keys().size() != ALLOWED_GAUGES.size():
		return H.failure("INVALID_CONSTRUCTION_METRIC_CARDINALITY")
	for name in ALLOWED_COUNTERS:
		if not H.is_non_negative_integer(state["counters"].get(name)):
			return H.failure("INVALID_CONSTRUCTION_METRIC_COUNTER")
	for name in ALLOWED_GAUGES:
		if not H.is_non_negative_integer(state["gauges"].get(name)):
			return H.failure("INVALID_CONSTRUCTION_METRIC_GAUGE")
	if int(state["gauges"]["audit_events"]) != state["audit"].size():
		return H.failure("INCONSISTENT_CONSTRUCTION_AUDIT_GAUGE")
	var previous_hash := ""
	for index in range(state["audit"].size()):
		var raw_event = state["audit"][index]
		if typeof(raw_event) != TYPE_DICTIONARY:
			return H.failure("INVALID_CONSTRUCTION_AUDIT_EVENT")
		var event: Dictionary = raw_event
		if not bool(H.exact_fields(event, AUDIT_FIELDS).get("success", false)):
			return H.failure("INVALID_CONSTRUCTION_AUDIT_FIELDS")
		if not H.is_non_negative_integer(event.get("event_index")) or int(event["event_index"]) != index or String(event.get("previous_hash", "")) != previous_hash:
			return H.failure("BROKEN_CONSTRUCTION_AUDIT_CHAIN")
		if not H.is_path_id(event.get("operation_id"), "operation/") or not H.is_path_id(event.get("subject_id"), "subject/") or not H.is_path_id(event.get("construct_id"), "construct/"):
			return H.failure("INVALID_CONSTRUCTION_AUDIT_IDENTITY")
		if not H.is_token(event.get("action")) or not AUDIT_DECISIONS.has(String(event.get("decision", ""))):
			return H.failure("INVALID_CONSTRUCTION_AUDIT_EVENT")
		if typeof(event.get("error_code")) != TYPE_STRING or (not String(event["error_code"]).is_empty() and not H.is_token(event["error_code"])):
			return H.failure("INVALID_CONSTRUCTION_AUDIT_ERROR_CODE")
		var expected_previous := String(event.get("previous_hash", "")).is_empty()
		if index > 0:
			expected_previous = H.is_hash(event.get("previous_hash"))
		if not expected_previous:
			return H.failure("INVALID_CONSTRUCTION_AUDIT_PREVIOUS_HASH")
		if not H.is_non_negative_integer(event.get("tick")) or not H.is_hash(event.get("checksum")) or String(event["checksum"]) != H.checksum(event):
			return H.failure("CONSTRUCTION_AUDIT_CHECKSUM_MISMATCH")
		previous_hash = String(event["checksum"])
	return H.validate_checksum(state, "CONSTRUCTION_OBSERVABILITY_STATE_CHECKSUM_MISMATCH")
