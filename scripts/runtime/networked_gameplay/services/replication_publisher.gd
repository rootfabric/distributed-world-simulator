extends RefCounted

const Snapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const Delta = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd")
const SCHEMA := "planet_simulator.replication_publisher.v1"
var _snapshots := 0
var _deltas := 0

func create_snapshot(authority_owner_id: String, authority_epoch: int, revision: int, server_tick: int, region_id: String, players: Array, shared_item: Dictionary) -> Dictionary:
	_snapshots += 1
	return Snapshot.create(authority_owner_id, authority_epoch, revision, server_tick, region_id, players, shared_item)

func create_delta(authority_owner_id: String, authority_epoch: int, base_revision: int, target_revision: int, server_tick: int, event_type: String, player: Dictionary, shared_item: Dictionary, target_snapshot: Dictionary) -> Dictionary:
	_deltas += 1
	return Delta.create(authority_owner_id, authority_epoch, base_revision, target_revision, server_tick, event_type, player, shared_item, String(target_snapshot.get("checksum", "")))

func get_report() -> Dictionary: return {"schema": SCHEMA, "snapshots": _snapshots, "deltas": _deltas}
