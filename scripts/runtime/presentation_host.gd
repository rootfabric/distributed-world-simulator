extends Node

const SCHEMA: String = "planet_simulator.presentation_host.v1"

var enabled: bool = true
var registered_nodes: Array[Node] = []


func setup(enabled_value: bool = true) -> void:
	enabled = enabled_value
	process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func attach_presentation(node: Node) -> Dictionary:
	if not enabled:
		return {"success": false, "error_code": "PRESENTATION_DISABLED"}
	if node == null:
		return {"success": false, "error_code": "PRESENTATION_NODE_REQUIRED"}
	add_child(node)
	registered_nodes.append(node)
	return {"success": true, "node_name": node.name}


func detach_all() -> int:
	var detached: int = 0
	for node in registered_nodes.duplicate():
		if node != null and is_instance_valid(node) and node.get_parent() == self:
			remove_child(node)
			detached += 1
	registered_nodes.clear()
	return detached


func create_snapshot() -> Dictionary:
	var active: int = 0
	for node in registered_nodes:
		if node != null and is_instance_valid(node) and node.get_parent() == self:
			active += 1
	return {
		"schema": SCHEMA,
		"enabled": enabled,
		"active_node_count": active,
	}
