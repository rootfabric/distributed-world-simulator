class_name WorldFillLocalMemory
extends RefCounted

## WF0.8 Local World Memory (WORLD FILL train).
##
## A purely local "I was here" layer for the player, stored under
## user://world_memory/. Crumbs are derived from OBSERVED events and local
## actions only. Server persistence is explicitly out of scope until
## canonically authorized: nothing here is replicated, synced or authored
## as world truth, and losing every crumb cannot change any outcome.
##
## Guarantees:
## - LOCAL-ONLY: storage is user://world_memory/<memory_id>.json.
## - BUDGETED: at most MAX_CRUMBS crumbs; oldest evicted first.
## - EVENT-DERIVED: crumbs originate from observed events/local notes.
## - FAIL-SOFT: unknown observed events are ignored; a missing file loads
##   as an empty memory; corrupted files reset to empty rather than erroring
##   the caller.

const SCHEMA := "world_fill.local_memory_report.v1"
const MAX_CRUMBS := 128
const MAX_NOTE_LENGTH := 120
const STORAGE_ROOT := "user://world_memory"

## Observed/local event type -> crumb type.
const EVENT_CRUMBS := {
	"DIG_SUCCESS": "dug_here",
	"HANDOFF_OBSERVED": "observed_handoff",
	"VISIT": "visited",
	"PHOTO_CAPTURED": "photo_bookmark",
}

const NOTE_EVENT := "LOCAL_NOTE"

var _memory_id := "default"
var _crumbs: Array[Dictionary] = []


func configure_storage(memory_id: String) -> void:
	_memory_id = memory_id


func storage_path() -> String:
	return "%s/%s.json" % [STORAGE_ROOT, _memory_id]


func record_observed(event: Dictionary, observed_tick: int) -> Dictionary:
	var event_type := String(event.get("type", ""))
	var crumb_type := ""
	var payload := {}
	if event_type == NOTE_EVENT:
		crumb_type = "local_note"
		payload["text"] = _sanitize_note(String(event.get("text", "")))
	elif EVENT_CRUMBS.has(event_type):
		crumb_type = String(EVENT_CRUMBS[event_type])
	if crumb_type == "":
		return memory_report()
	if event.has("position"):
		payload["position"] = event.get("position")
	var crumb := {
		"crumb": crumb_type,
		"observed_tick": observed_tick,
		"payload": payload,
	}
	_crumbs.append(crumb)
	while _crumbs.size() > MAX_CRUMBS:
		_crumbs.pop_front()
	return memory_report()


func save() -> bool:
	DirAccess.make_dir_recursive_absolute(STORAGE_ROOT)
	var file := FileAccess.open(storage_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema": SCHEMA,
		"memory_id": _memory_id,
		"crumbs": _crumbs,
	}))
	file.close()
	return true


func load_memory() -> bool:
	_crumbs.clear()
	if not FileAccess.file_exists(storage_path()):
		return false
	var file := FileAccess.open(storage_path(), FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var raw_crumbs: Variant = parsed.get("crumbs", [])
	if typeof(raw_crumbs) != TYPE_ARRAY:
		return false
	for crumb in raw_crumbs:
		if typeof(crumb) == TYPE_DICTIONARY:
			_crumbs.append(crumb)
	while _crumbs.size() > MAX_CRUMBS:
		_crumbs.pop_front()
	return true


func clear_storage() -> void:
	_crumbs.clear()
	if FileAccess.file_exists(storage_path()):
		DirAccess.remove_absolute(storage_path())


func memory_report() -> Dictionary:
	var by_type := {}
	for crumb in _crumbs:
		var crumb_type := String(crumb.get("crumb", ""))
		by_type[crumb_type] = int(by_type.get(crumb_type, 0)) + 1
	return {
		"schema": SCHEMA,
		"memory_id": _memory_id,
		"active": _crumbs.size(),
		"max_crumbs": MAX_CRUMBS,
		"by_type": by_type,
		"storage": storage_path(),
		"server_synced": false,
	}


func _sanitize_note(text: String) -> String:
	var flattened := text.replace("\n", " ").replace("\r", " ")
	if flattened.length() > MAX_NOTE_LENGTH:
		flattened = flattened.substr(0, MAX_NOTE_LENGTH)
	return flattened
