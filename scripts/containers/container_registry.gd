extends RefCounted

const ContainerStateScript = preload("res://scripts/containers/container_state.gd")

var containers: Dictionary = {}


func add_container(container) -> bool:
	if container == null or String(container.container_id).is_empty():
		return false
	if containers.has(container.container_id):
		return false
	containers[container.container_id] = container
	return true


func get_container(container_id: String) -> Variant:
	return containers.get(container_id)


func remove_container(container_id: String) -> bool:
	var container = get_container(container_id)
	if container == null or not container.item_ids.is_empty():
		return false
	return containers.erase(container_id)


func to_dict() -> Dictionary:
	var rows: Array = []
	for container in containers.values():
		rows.append(container.to_dict())
	return {"containers": rows}


func load_dict(data: Dictionary) -> void:
	containers.clear()
	for row in data.get("containers", []):
		var container = ContainerStateScript.new(Dictionary(row))
		containers[container.container_id] = container
