extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")

const STATE_SCHEMA := "planet_simulator.construction_rate_limiter_state.v1"
const STATE_FIELDS: Array[String] = ["schema", "limit", "window_ticks", "subjects", "checksum"]
const MAX_SUBJECT_KEYS := 4096
const MAX_SAFE_JSON_INTEGER := 9007199254740991

var _limit := 1
var _window_ticks := 1
var _subjects: Dictionary = {}

func setup(limit: int, window_ticks: int) -> Dictionary:
	if not H.is_positive_integer(limit) or not H.is_positive_integer(window_ticks):
		return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_CONFIG")
	_limit = limit
	_window_ticks = window_ticks
	return H.success()

func consume(subject_id: String, action: String, tick: int) -> Dictionary:
	if not H.is_path_id(subject_id, "subject/") or not H.is_token(action) or not H.is_non_negative_integer(tick):
		return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_REQUEST")
	if tick > MAX_SAFE_JSON_INTEGER - _window_ticks:
		return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_REQUEST")
	var key := "%s|%s" % [subject_id, action]
	var window_start := tick - (tick % _window_ticks)
	if not _subjects.has(key) and _subjects.size() >= MAX_SUBJECT_KEYS:
		return H.failure("CONSTRUCTION_PRODUCTION_RATE_LIMIT_CAPACITY_EXCEEDED")
	var row: Dictionary = _subjects.get(key, {"window_start": window_start, "count": 0})
	if int(row["window_start"]) != window_start:
		row = {"window_start": window_start, "count": 0}
	if int(row["count"]) >= _limit:
		return H.failure("CONSTRUCTION_PRODUCTION_RATE_LIMITED", {
			"retry_after_tick": window_start + _window_ticks,
			"limit": _limit,
		})
	row["count"] = int(row["count"]) + 1
	_subjects[key] = row
	return H.success({"remaining": _limit - int(row["count"])})

func get_subject_count() -> int:
	return _subjects.size()

func export_state() -> Dictionary:
	var keys: Array = _subjects.keys()
	keys.sort()
	var rows: Array = []
	for key in keys:
		var row: Dictionary = _subjects[key]
		rows.append({"key": key, "window_start": int(row["window_start"]), "count": int(row["count"])})
	var state := {"schema": STATE_SCHEMA, "limit": _limit, "window_ticks": _window_ticks, "subjects": rows, "checksum": ""}
	state["checksum"] = H.checksum(state)
	return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state)
	if not bool(checked.get("success", false)):
		return checked
	var subjects: Dictionary = {}
	for row in state["subjects"]:
		subjects[String(row["key"])] = {"window_start": int(row["window_start"]), "count": int(row["count"])}
	_limit = int(state["limit"])
	_window_ticks = int(state["window_ticks"])
	_subjects = subjects
	return H.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := H.exact_fields(state, STATE_FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_STATE_FIELDS")
	if state.get("schema") != STATE_SCHEMA or not H.is_positive_integer(state.get("limit")) or not H.is_positive_integer(state.get("window_ticks")) or typeof(state.get("subjects")) != TYPE_ARRAY:
		return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_STATE")
	if state["subjects"].size() > MAX_SUBJECT_KEYS:
		return H.failure("CONSTRUCTION_RATE_LIMIT_CAPACITY_EXCEEDED")
	var previous := ""
	for raw_row in state["subjects"]:
		if typeof(raw_row) != TYPE_DICTIONARY:
			return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_ROW")
		var row: Dictionary = raw_row
		if row.keys().size() != 3 or typeof(row.get("key")) != TYPE_STRING:
			return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_ROW")
		var key := String(row["key"])
		var pieces := key.split("|", false)
		if pieces.size() != 2 or not H.is_path_id(pieces[0], "subject/") or not H.is_token(pieces[1]):
			return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_ROW")
		if not previous.is_empty() and key <= previous:
			return H.failure("NON_CANONICAL_CONSTRUCTION_RATE_LIMIT_ROWS")
		if not H.is_non_negative_integer(row.get("window_start")) or not H.is_non_negative_integer(row.get("count")) or int(row["count"]) > int(state["limit"]):
			return H.failure("INVALID_CONSTRUCTION_RATE_LIMIT_ROW")
		previous = key
	return H.validate_checksum(state, "CONSTRUCTION_RATE_LIMIT_STATE_CHECKSUM_MISMATCH")
