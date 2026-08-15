extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p1.gd"

# V0-P2 canonical read/recovery adapter.
#
# The P1 slot/transfer implementation is preserved byte-for-byte in the
# compatibility parent. This current canonical path owns only the P2 recovery
# boundary: snapshots/exports are pure reads, while legacy slot normalization
# happens exactly once after a successful durable restore and is revisioned.

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const CURRENT_SNAPSHOT_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1"


func create_snapshot() -> Dictionary:
	var body: Dictionary = {
		"schema": CURRENT_SNAPSHOT_SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"tick": _tick,
		"items": _sorted_values(_items),
		"inventories": _sorted_map(_inventories),
		"containers": _sorted_values(_containers),
		"mounts": _sorted_values(_mounts),
		"open_containers": _sorted_map(_open_containers),
	}
	if _sandbox_mode:
		body["playable_sandbox"] = true
	body["checksum"] = NetworkUtils.payload_hash(body)
	return body


func restore_durable_state(value: Dictionary) -> Dictionary:
	var restored: Dictionary = super.restore_durable_state(value)
	if not bool(restored.get("success", false)):
		return restored

	var before_revision := _revision
	var before_tick := _tick
	var before_snapshot: Dictionary = create_snapshot()

	# This is the one explicit compatibility migration boundary. Canonical read
	# APIs must never call normalization after this point.
	_normalize_slot_locations()
	var normalized_snapshot: Dictionary = create_snapshot()
	var migrated := (
		String(before_snapshot.get("checksum", ""))
		!= String(normalized_snapshot.get("checksum", ""))
	)
	var migration_summary := _build_slot_migration_summary(
		before_snapshot,
		normalized_snapshot
	)

	if migrated:
		_revision += 1
		_tick += 1

	var final_snapshot: Dictionary = create_snapshot()
	var details: Dictionary = Dictionary(restored.get("details", {})).duplicate(true)
	details["revision"] = _revision
	details["tick"] = _tick
	details["snapshot_checksum"] = String(final_snapshot.get("checksum", ""))
	details["slot_migration"] = {
		"migrated": migrated,
		"before_revision": before_revision,
		"before_tick": before_tick,
		"after_revision": _revision,
		"after_tick": _tick,
		"before_checksum": String(before_snapshot.get("checksum", "")),
		"normalized_checksum": String(normalized_snapshot.get("checksum", "")),
		"final_checksum": String(final_snapshot.get("checksum", "")),
		"changed_item_count": int(migration_summary.get("changed_item_count", 0)),
		"changed_owner_count": int(migration_summary.get("changed_owner_count", 0)),
	}
	restored["details"] = details
	return restored


func _build_slot_migration_summary(
	before_snapshot: Dictionary,
	after_snapshot: Dictionary
) -> Dictionary:
	var before_items := _snapshot_items_by_id(before_snapshot)
	var after_items := _snapshot_items_by_id(after_snapshot)
	var changed_items := 0
	var changed_owners: Dictionary = {}
	for item_id_value in after_items.keys():
		var item_id := String(item_id_value)
		if not before_items.has(item_id):
			continue
		var before_location: Dictionary = Dictionary(
			Dictionary(before_items[item_id]).get("location", {})
		)
		var after_location: Dictionary = Dictionary(
			Dictionary(after_items[item_id]).get("location", {})
		)
		if before_location == after_location:
			continue
		changed_items += 1
		var owner_key := _slot_owner_key(after_location)
		if owner_key.is_empty():
			owner_key = _slot_owner_key(before_location)
		if not owner_key.is_empty():
			changed_owners[owner_key] = true
	return {
		"changed_item_count": changed_items,
		"changed_owner_count": changed_owners.size(),
	}


func _snapshot_items_by_id(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var item_id := String(item.get("item_id", ""))
		if not item_id.is_empty():
			result[item_id] = item.duplicate(true)
	return result


func _slot_owner_key(location: Dictionary) -> String:
	match String(location.get("kind", "")):
		"INVENTORY":
			var player_id := String(location.get("player_id", ""))
			return "inventory/%s" % player_id if not player_id.is_empty() else ""
		"CONTAINER":
			return String(location.get("container_id", ""))
	return ""
