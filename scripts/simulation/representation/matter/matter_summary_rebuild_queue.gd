extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const RebuildTask = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_rebuild_task.gd")

const MIN_CAPACITY: int = 1
const MAX_CAPACITY: int = 65536

var _capacity: int = 0
var _tasks_by_cell_id: Dictionary = {}


func setup(capacity: int) -> Dictionary:
	if capacity < MIN_CAPACITY or capacity > MAX_CAPACITY:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REBUILD_QUEUE_CAPACITY")
	_capacity = capacity
	_tasks_by_cell_id.clear()
	return RepresentationUtils.success({"capacity": _capacity})


func capacity() -> int:
	return _capacity


func size() -> int:
	return _tasks_by_cell_id.size()


func is_empty() -> bool:
	return _tasks_by_cell_id.is_empty()


func enqueue(task: Dictionary) -> Dictionary:
	return enqueue_many([task])


func enqueue_many(tasks: Array) -> Dictionary:
	if _capacity < MIN_CAPACITY:
		return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_QUEUE_NOT_INITIALIZED")
	var staged: Dictionary = _tasks_by_cell_id.duplicate(true)
	for raw_task in tasks:
		if typeof(raw_task) != TYPE_DICTIONARY:
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REBUILD_TASK")
		var task: Dictionary = raw_task
		var checked: Dictionary = RebuildTask.validate(task)
		if not bool(checked.get("success", false)):
			return checked
		var cell_id: String = String(task["cell_address"]["cell_id"])
		if staged.has(cell_id):
			var merged: Dictionary = _merge_task(staged[cell_id], task)
			if merged.is_empty():
				return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_FRONTIER_ROLLBACK", {"cell_id": cell_id})
			staged[cell_id] = merged
		else:
			staged[cell_id] = task.duplicate(true)
		if staged.size() > _capacity:
			return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_QUEUE_CAPACITY", {
				"capacity": _capacity,
				"required": staged.size(),
			})
	_tasks_by_cell_id = staged
	return RepresentationUtils.success({"queue_size": size()})


func peek() -> Dictionary:
	var ordered: Array = snapshot()
	return Dictionary(ordered[0]).duplicate(true) if not ordered.is_empty() else {}


func pop() -> Dictionary:
	var task: Dictionary = peek()
	if task.is_empty():
		return {}
	_tasks_by_cell_id.erase(String(task["cell_address"]["cell_id"]))
	return task


func get_task(cell_id: String) -> Dictionary:
	return Dictionary(_tasks_by_cell_id.get(cell_id, {})).duplicate(true)


func remove(cell_id: String) -> bool:
	return _tasks_by_cell_id.erase(cell_id)


func snapshot() -> Array:
	var result: Array = []
	for task in _tasks_by_cell_id.values():
		result.append(Dictionary(task).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a: int = int(a["priority_level"])
		var priority_b: int = int(b["priority_level"])
		if priority_a != priority_b:
			return priority_a > priority_b
		var enqueue_a: int = int(a["enqueue_revision"])
		var enqueue_b: int = int(b["enqueue_revision"])
		if enqueue_a != enqueue_b:
			return enqueue_a < enqueue_b
		return String(a["cell_address"]["cell_id"]) < String(b["cell_address"]["cell_id"])
	)
	return result


func _merge_task(current: Dictionary, incoming: Dictionary) -> Dictionary:
	if String(current["body_id"]) != String(incoming["body_id"]):
		return {}
	var current_epoch: int = int(current["target_authority_epoch"])
	var incoming_epoch: int = int(incoming["target_authority_epoch"])
	var current_revision: int = int(current["target_source_revision"])
	var incoming_revision: int = int(incoming["target_source_revision"])
	if incoming_epoch < current_epoch or (incoming_epoch == current_epoch and incoming_revision < current_revision):
		return {}
	if incoming_epoch > current_epoch and incoming_revision < current_revision:
		return {}
	if incoming_epoch == current_epoch and incoming_revision == current_revision:
		if String(current["checksum"]) == String(incoming["checksum"]):
			return current.duplicate(true)
		var merged_same: Dictionary = incoming.duplicate(true)
		merged_same["dirty_bounds_m"] = _union_bounds(current["dirty_bounds_m"], incoming["dirty_bounds_m"])
		merged_same["enqueue_revision"] = mini(int(current["enqueue_revision"]), int(incoming["enqueue_revision"]))
		merged_same["checksum"] = RepresentationUtils.compute_checksum(merged_same)
		return merged_same if bool(RebuildTask.validate(merged_same).get("success", false)) else {}
	var merged: Dictionary = incoming.duplicate(true)
	merged["dirty_bounds_m"] = _union_bounds(current["dirty_bounds_m"], incoming["dirty_bounds_m"])
	merged["enqueue_revision"] = mini(int(current["enqueue_revision"]), int(incoming["enqueue_revision"]))
	merged["checksum"] = RepresentationUtils.compute_checksum(merged)
	return merged if bool(RebuildTask.validate(merged).get("success", false)) else {}


func _union_bounds(a: Array, b: Array) -> Array:
	return [
		minf(float(a[0]), float(b[0])), minf(float(a[1]), float(b[1])), minf(float(a[2]), float(b[2])),
		maxf(float(a[3]), float(b[3])), maxf(float(a[4]), float(b[4])), maxf(float(a[5]), float(b[5])),
	]
