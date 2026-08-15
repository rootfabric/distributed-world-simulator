extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"

# Test-only serializer that intentionally bypasses the P1 compatibility
# normalization in create_snapshot(). This models the P2 pure-read boundary and
# lets P1 tests prove that successful commands already publish complete slot
# identity and that rejected commands do not rely on lazy normalization.

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")


func create_snapshot() -> Dictionary:
	var body := {
		"schema": SNAPSHOT_SCHEMA,
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
	body["checksum"] = Utils.payload_hash(body)
	return body
