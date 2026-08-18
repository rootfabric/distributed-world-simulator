extends "res://scripts/runtime/networked_gameplay/p5/networked_gameplay_service_p5.gd"

# V0-P5 product composition adapter.
# The live M3 server preloads this stable path. P5 keeps exactly one canonical
# M4 Item Graph, preserves P4 Construction consume support, and selects the P5
# ResourceMining capability gate without changing M3 transport or authority.

func get_canonical_item_graph_port():
	return _canonical_multiplayer_items if _configured else null

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
