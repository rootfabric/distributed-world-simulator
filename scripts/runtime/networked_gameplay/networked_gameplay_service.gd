extends "res://scripts/runtime/networked_gameplay/p5/networked_gameplay_service_p5.gd"

# V0-P5 product composition adapter.
# The live M3 server preloads this stable path. P5 keeps exactly one canonical
# M4 Item Graph, preserves P4 Construction consume support, and selects the P5
# ResourceMining capability gate without changing M3 transport or authority.

func get_canonical_item_graph_port():
	return _canonical_multiplayer_items if _configured else null


# R3C.4 R3.1a: constant-time fence over the REAL owner-native replay ledgers.
# This is provenance for a *derived* cache, never a second authoritative state.
# All counters are bumped on source mutation/restore; fixed movement ticks
# deliberately do not modify replay generations.
func get_r31_replay_source_fence() -> Dictionary:
	if (
		not _configured
		or _ownership == null
		or _canonical_multiplayer_items == null
		or _resource_mining == null
	):
		return {}
	return {
		"schema": "dws.r3c4.r31.replay_source_fence.v1",
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"service_generation": get_service_replay_projection_generation(),
		"ownership_generation": _ownership.get_replay_projection_generation(),
		"item_graph_generation": _canonical_multiplayer_items.get_replay_projection_generation(),
		"resource_generation": _resource_mining.get_replay_projection_generation(),
	}


func get_resource_mining_port():
	return _resource_mining if _configured else null

func get_v0_p4_composition_report() -> Dictionary:
	var graph = get_canonical_item_graph_port()
	return {
		"configured": _configured,
		"canonical_item_graph_ready": graph != null,
		"p4_construction_consume_ready": (
			graph != null
			and graph.has_method("preflight_server_construction_consume")
			and graph.has_method("apply_server_construction_consume")
		),
		"resource_mining_bound": _resource_mining != null,
	}

# P7 production composition seam. Trusted domain output still belongs to the
# existing canonical Item Graph, while this aggregate service remains
# responsible for advancing the enclosing authoritative revision exactly once
# when that canonical graph actually mutates. Replays do not advance it.
func preflight_canonical_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	var graph = get_canonical_item_graph_port()
	if graph == null or not graph.has_method("preflight_server_output"):
		return _failure("CANONICAL_ITEM_GRAPH_NOT_READY")
	return graph.preflight_server_output(
		operation_id, logical_player_id, definition_id, quantity, source_id
	)


func apply_canonical_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	var graph = get_canonical_item_graph_port()
	if graph == null or not graph.has_method("apply_server_output"):
		return _failure("CANONICAL_ITEM_GRAPH_NOT_READY")
	var result: Dictionary = graph.apply_server_output(
		operation_id, logical_player_id, definition_id, quantity, source_id
	)
	if bool(result.get("success", false)) and not bool(result.get("replay", false)):
		_advance()
	return result
