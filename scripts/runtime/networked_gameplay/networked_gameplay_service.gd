extends "res://scripts/runtime/networked_gameplay/p3/networked_gameplay_service_p3.gd"

# V0-P4 product composition adapter.
# The gameplay service still owns exactly one canonical M4 Item Graph. The
# current canonical M4 class now layers P3 trusted output + P4 trusted consume;
# this getter is server-composition-only and is never routed from the wire.

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
