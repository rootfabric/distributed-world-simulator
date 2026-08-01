extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const BundleScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")
const EventScript = preload("res://scripts/construction/multiplayer/construction_multiplayer_event.gd")

var _bundle: Dictionary = {}
var _last_event_index := -1

func initialize(bundle: Dictionary, last_event_index: int = -1) -> Dictionary:
	var checked := BundleScript.validate(bundle); if not bool(checked.get("success", false)): return checked
	if last_event_index < -1: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_REPLICA_EVENT_INDEX")
	_bundle = bundle.duplicate(true); _last_event_index = last_event_index
	return ParametricUtils.success()

func apply_event(event: Dictionary) -> Dictionary:
	var checked := EventScript.validate(event); if not bool(checked.get("success", false)): return checked
	var index := int(event["event_index"])
	if index == _last_event_index:
		if not _bundle.is_empty() and String(_bundle["checksum"]) == String(event["state_bundle"]["checksum"]): return ParametricUtils.success({"replay": true})
		return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_REPLICA_EVENT_CONFLICT")
	if index != _last_event_index + 1: return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_REPLICA_EVENT_GAP")
	var next_bundle: Dictionary = event["state_bundle"]
	if not _bundle.is_empty() and int(next_bundle["server_generation"]) < int(_bundle["server_generation"]): return ParametricUtils.failure("CONSTRUCTION_MULTIPLAYER_REPLICA_GENERATION_ROLLBACK")
	_bundle = next_bundle.duplicate(true); _last_event_index = index
	return ParametricUtils.success({"replay": false})

func apply_events(events: Array) -> Dictionary:
	for event in events:
		if typeof(event) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_MULTIPLAYER_REPLICA_EVENT")
		var applied := apply_event(event); if not bool(applied.get("success", false)): return applied
	return ParametricUtils.success({"event_count": events.size()})

func get_bundle() -> Dictionary: return _bundle.duplicate(true)
func get_checksum() -> String: return String(_bundle.get("checksum", ""))
func get_last_event_index() -> int: return _last_event_index
func get_construct_snapshot(construct_id: String) -> Dictionary:
	for snapshot in _bundle.get("constructs", []):
		if String(snapshot.get("construct_id", "")) == construct_id: return Dictionary(snapshot).duplicate(true)
	return {}
func converged_with(bundle: Dictionary) -> bool: return bool(BundleScript.validate(bundle).get("success", false)) and String(bundle["checksum"]) == get_checksum()
