extends RefCounted
const Registry = preload("res://scripts/runtime/host_client/player_ownership_registry.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.player_ownership_replica_store.v1"
var _snapshot: Dictionary = {}
var _mutations := 0
var _replays := 0
func accept_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation := Registry.new().validate_snapshot(snapshot)
	if not bool(validation.success): return validation
	if not _snapshot.is_empty():
		if String(snapshot.authority_owner_id) != String(_snapshot.authority_owner_id) or int(snapshot.authority_epoch) != int(_snapshot.authority_epoch): return _failure("OWNERSHIP_AUTHORITY_MISMATCH")
		if int(snapshot.revision) < int(_snapshot.revision): return _failure("OWNERSHIP_REVISION_ROLLBACK")
		if int(snapshot.revision) == int(_snapshot.revision):
			if String(snapshot.checksum) != String(_snapshot.checksum): return _failure("OWNERSHIP_SAME_REVISION_MUTATION")
			_replays += 1; return _success({"replay":true})
	_snapshot = snapshot.duplicate(true); _mutations += 1
	return _success({"replay":false})
func get_player(logical_player_id: String) -> Dictionary:
	for value in _snapshot.get("players", []):
		if String(value.get("logical_player_id", "")) == logical_player_id: return Dictionary(value).duplicate(true)
	return {}
func get_snapshot() -> Dictionary: return _snapshot.duplicate(true)
func get_report() -> Dictionary: return {"schema":SCHEMA,"configured":not _snapshot.is_empty(),"revision":int(_snapshot.get("revision",-1)),"mutations":_mutations,"replays":_replays,"direct_authority_references":0}
func _success(details: Dictionary = {}) -> Dictionary: return {"success":true,"error_code":"","details":details.duplicate(true)}
func _failure(error_code: String) -> Dictionary: return {"success":false,"error_code":error_code,"details":{}}
