extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")
const RebuildTask = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_rebuild_task.gd")
const RebuildQueue = preload("res://scripts/simulation/representation/matter/matter_summary_rebuild_queue.gd")
const DirtyPropagator = preload("res://scripts/simulation/representation/matter/matter_summary_dirty_propagator.gd")
const PersistenceManifest = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_persistence_manifest.gd")

var _grid_profile: Dictionary = {}
var _body_id: String = ""
var _region_root_address: Dictionary = {}
var _authority_epoch: int = 0
var _source_revision: Dictionary = {}
var _nodes_by_cell_id: Dictionary = {}
var _dirty_by_cell_id: Dictionary = {}
var _queue := RebuildQueue.new()
var _event_revision: int = 0


func setup(
	grid_profile: Dictionary,
	region_root_address: Dictionary,
	source_revision: Dictionary,
	rebuild_queue_capacity: int
) -> Dictionary:
	if not bool(GridProfile.validate(grid_profile).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_GRID_PROFILE")
	if not bool(CellGrid.validate_address(grid_profile, region_root_address).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REGION_ROOT")
	var source_checked: Dictionary = SourceRevision.validate(source_revision)
	if not bool(source_checked.get("success", false)):
		return source_checked
	if String(source_revision["source_domain"]) != "MATTER" \
		or String(source_revision["source_id"]) != String(grid_profile["body_id"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_SOURCE_MISMATCH")
	var queue_setup: Dictionary = _queue.setup(rebuild_queue_capacity)
	if not bool(queue_setup.get("success", false)):
		return queue_setup
	_grid_profile = grid_profile.duplicate(true)
	_body_id = String(grid_profile["body_id"])
	_region_root_address = region_root_address.duplicate(true)
	_authority_epoch = int(source_revision["authority_epoch"])
	_source_revision = source_revision.duplicate(true)
	_nodes_by_cell_id.clear()
	_dirty_by_cell_id.clear()
	_event_revision = 0
	return RepresentationUtils.success({
		"body_id": _body_id,
		"region_root_cell_id": String(_region_root_address["cell_id"]),
		"authority_epoch": _authority_epoch,
		"source_revision_checksum": String(_source_revision["checksum"]),
	})


func body_id() -> String:
	return _body_id


func authority_epoch() -> int:
	return _authority_epoch


func source_revision() -> Dictionary:
	return _source_revision.duplicate(true)


func region_root_address() -> Dictionary:
	return _region_root_address.duplicate(true)


func summary_count() -> int:
	return _nodes_by_cell_id.size()


func dirty_count() -> int:
	return _dirty_by_cell_id.size()


func queue_size() -> int:
	return _queue.size()


func register_summary(summary: Dictionary) -> Dictionary:
	var checked: Dictionary = _validate_summary_for_region(summary)
	if not bool(checked.get("success", false)):
		return checked
	if int(summary["authority_epoch"]) != _authority_epoch:
		return RepresentationUtils.failure("MATTER_SUMMARY_AUTHORITY_EPOCH_MISMATCH")
	if int(summary["summary_revision"]) > int(_source_revision["source_revision"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_SOURCE_REVISION_AHEAD")
	var cell_id: String = String(summary["cell_address"]["cell_id"])
	if _dirty_by_cell_id.has(cell_id):
		var dirty: Dictionary = _dirty_by_cell_id[cell_id]
		if int(summary["authority_epoch"]) < int(dirty["target_authority_epoch"]) \
			or int(summary["summary_revision"]) < int(dirty["target_source_revision"]):
			return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_BEHIND_DIRTY_FRONTIER")
	if _nodes_by_cell_id.has(cell_id):
		var previous: Dictionary = _nodes_by_cell_id[cell_id]
		var previous_epoch: int = int(previous["authority_epoch"])
		var current_epoch: int = int(summary["authority_epoch"])
		var previous_revision: int = int(previous["summary_revision"])
		var current_revision: int = int(summary["summary_revision"])
		if current_epoch < previous_epoch \
			or (current_epoch == previous_epoch and current_revision < previous_revision) \
			or (current_epoch > previous_epoch and current_revision < previous_revision):
			return RepresentationUtils.failure("MATTER_SUMMARY_FRONTIER_ROLLBACK")
		if current_epoch == previous_epoch and current_revision == previous_revision:
			if String(previous["checksum"]) == String(summary["checksum"]):
				return RepresentationUtils.success({"replay": true, "cell_id": cell_id})
			return RepresentationUtils.failure("MATTER_SUMMARY_SAME_REVISION_MUTATION")
	_nodes_by_cell_id[cell_id] = summary.duplicate(true)
	_dirty_by_cell_id.erase(cell_id)
	_queue.remove(cell_id)
	return RepresentationUtils.success({"replay": false, "cell_id": cell_id})


func get_summary(cell_id: String) -> Dictionary:
	return Dictionary(_nodes_by_cell_id.get(cell_id, {})).duplicate(true)


func get_ready_summary(cell_id: String) -> Dictionary:
	if _dirty_by_cell_id.has(cell_id):
		return {}
	var summary: Dictionary = get_summary(cell_id)
	if summary.is_empty() or int(summary["authority_epoch"]) != _authority_epoch:
		return {}
	return summary


func all_summaries() -> Array:
	var result: Array = []
	for summary in _nodes_by_cell_id.values():
		result.append(Dictionary(summary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_address"]["cell_id"]) < String(b["cell_address"]["cell_id"])
	)
	return result


func is_dirty(cell_id: String) -> bool:
	return _dirty_by_cell_id.has(cell_id)


func dirty_record(cell_id: String) -> Dictionary:
	return Dictionary(_dirty_by_cell_id.get(cell_id, {})).duplicate(true)


func queued_tasks() -> Array:
	return _queue.snapshot()


func next_rebuild_task() -> Dictionary:
	return _queue.peek()


func invalidate_mutation(
	invalidation_id: String,
	previous_source_revision: Dictionary,
	new_source_revision: Dictionary,
	changed_cell_address: Dictionary,
	dirty_bounds_m: Array,
	created_tick: int
) -> Dictionary:
	var source_check: Dictionary = _validate_source_transition(
		previous_source_revision, new_source_revision, false
	)
	if not bool(source_check.get("success", false)):
		return source_check
	if not _contains_region_cell(changed_cell_address):
		return RepresentationUtils.failure("MATTER_SUMMARY_MUTATION_OUTSIDE_REGION")
	var addresses: Array = DirtyPropagator.mutation_chain(changed_cell_address, _region_root_address)
	if addresses.is_empty():
		return RepresentationUtils.failure("MATTER_SUMMARY_DIRTY_CHAIN_EMPTY")
	return _apply_invalidation(
		invalidation_id,
		previous_source_revision,
		new_source_revision,
		dirty_bounds_m,
		"MUTATION",
		created_tick,
		addresses,
		false
	)


func invalidate_handoff(
	invalidation_id: String,
	previous_source_revision: Dictionary,
	new_source_revision: Dictionary,
	dirty_bounds_m: Array,
	created_tick: int
) -> Dictionary:
	var source_check: Dictionary = _validate_source_transition(
		previous_source_revision, new_source_revision, true
	)
	if not bool(source_check.get("success", false)):
		return source_check
	var addresses: Array = DirtyPropagator.handoff_cells(_region_root_address, all_summaries())
	if addresses.is_empty():
		return RepresentationUtils.failure("MATTER_SUMMARY_HANDOFF_SCOPE_EMPTY")
	return _apply_invalidation(
		invalidation_id,
		previous_source_revision,
		new_source_revision,
		dirty_bounds_m,
		"HANDOFF",
		created_tick,
		addresses,
		true
	)


func export_persistence_manifest(manifest_id: String, manifest_revision: int) -> Dictionary:
	var ready: Array = []
	for summary in all_summaries():
		var cell_id: String = String(summary["cell_address"]["cell_id"])
		if not _dirty_by_cell_id.has(cell_id) and int(summary["authority_epoch"]) == _authority_epoch:
			ready.append(summary)
	if ready.is_empty():
		return {}
	var root_cell_id: String = String(_region_root_address["cell_id"])
	var has_root: bool = false
	for summary in ready:
		if String(summary["cell_address"]["cell_id"]) == root_cell_id:
			has_root = true
			break
	if not has_root:
		return {}
	return PersistenceManifest.create(
		manifest_id,
		_body_id,
		_region_root_address,
		GridProfile.content_hash(_grid_profile),
		_source_revision,
		manifest_revision,
		ready
	)


func _apply_invalidation(
	invalidation_id: String,
	previous_source_revision: Dictionary,
	new_source_revision: Dictionary,
	dirty_bounds_m: Array,
	reason: String,
	created_tick: int,
	addresses: Array,
	advance_authority: bool
) -> Dictionary:
	var scope_ids: Array = DirtyPropagator.sorted_scope_ids(_body_id, addresses)
	if scope_ids.is_empty():
		return RepresentationUtils.failure("MATTER_SUMMARY_INVALIDATION_SCOPES_EMPTY")
	var invalidation: Dictionary = Invalidation.create(
		invalidation_id,
		previous_source_revision,
		new_source_revision,
		dirty_bounds_m,
		reason,
		scope_ids,
		created_tick
	)
	if invalidation.is_empty():
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REPRESENTATION_INVALIDATION")
	var next_event_revision: int = _event_revision + 1
	var tasks: Array = []
	for address in addresses:
		var task_hash: String = RepresentationUtils.payload_hash({
			"body_id": _body_id,
			"cell_id": String(address["cell_id"]),
			"authority_epoch": int(new_source_revision["authority_epoch"]),
			"source_revision": int(new_source_revision["source_revision"]),
			"event_revision": next_event_revision,
		})
		var task: Dictionary = RebuildTask.create(
			"matter-summary-rebuild/%s" % task_hash,
			_body_id,
			address,
			int(new_source_revision["authority_epoch"]),
			int(new_source_revision["source_revision"]),
			reason,
			dirty_bounds_m,
			next_event_revision
		)
		if task.is_empty():
			return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_TASK_CREATION_FAILED")
		tasks.append(task)
	var queued: Dictionary = _queue.enqueue_many(tasks)
	if not bool(queued.get("success", false)):
		return queued
	var staged_dirty: Dictionary = _dirty_by_cell_id.duplicate(true)
	for task in tasks:
		var cell_id: String = String(task["cell_address"]["cell_id"])
		var queued_task: Dictionary = _queue.get_task(cell_id)
		if queued_task.is_empty():
			return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_QUEUE_DESYNCHRONIZED")
		staged_dirty[cell_id] = {
			"target_authority_epoch": int(queued_task["target_authority_epoch"]),
			"target_source_revision": int(queued_task["target_source_revision"]),
			"reason": String(queued_task["reason"]),
			"dirty_bounds_m": Array(queued_task["dirty_bounds_m"]).duplicate(true),
			"invalidation_checksum": String(invalidation["checksum"]),
		}
	_dirty_by_cell_id = staged_dirty
	_event_revision = next_event_revision
	_source_revision = new_source_revision.duplicate(true)
	if advance_authority:
		_authority_epoch = int(new_source_revision["authority_epoch"])
	var dirty_cell_ids: Array = []
	for address in addresses:
		dirty_cell_ids.append(String(address["cell_id"]))
	dirty_cell_ids.sort()
	return RepresentationUtils.success({
		"invalidation": invalidation,
		"dirty_cell_ids": dirty_cell_ids,
		"queue_size": _queue.size(),
		"event_revision": _event_revision,
	})


func _validate_summary_for_region(summary: Dictionary) -> Dictionary:
	var checked: Dictionary = SummaryNode.validate(summary)
	if not bool(checked.get("success", false)):
		return checked
	if _grid_profile.is_empty():
		return RepresentationUtils.failure("MATTER_SUMMARY_PYRAMID_NOT_INITIALIZED")
	if String(summary["body_id"]) != _body_id:
		return RepresentationUtils.failure("MATTER_SUMMARY_BODY_MISMATCH")
	if not bool(CellGrid.validate_address(_grid_profile, summary["cell_address"]).get("success", false)):
		return RepresentationUtils.failure("MATTER_SUMMARY_GRID_MISMATCH")
	if not _contains_region_cell(summary["cell_address"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_OUTSIDE_REGION")
	var bounds: Dictionary = CellGrid.bounds(_grid_profile, summary["cell_address"])
	var expected: Array = [
		float(bounds["minimum_m"][0]), float(bounds["minimum_m"][1]), float(bounds["minimum_m"][2]),
		float(bounds["maximum_m"][0]), float(bounds["maximum_m"][1]), float(bounds["maximum_m"][2]),
	]
	if not _bounds_equal(summary["bounds_m"], expected):
		return RepresentationUtils.failure("MATTER_SUMMARY_BOUNDS_MISMATCH")
	return RepresentationUtils.success()


func _validate_source_transition(
	previous_source_revision: Dictionary,
	new_source_revision: Dictionary,
	require_epoch_advance: bool
) -> Dictionary:
	var checked: Dictionary = SourceRevision.validate(previous_source_revision)
	if not bool(checked.get("success", false)):
		return checked
	checked = SourceRevision.validate(new_source_revision)
	if not bool(checked.get("success", false)):
		return checked
	for source in [previous_source_revision, new_source_revision]:
		if String(source["source_domain"]) != "MATTER" or String(source["source_id"]) != _body_id:
			return RepresentationUtils.failure("MATTER_SUMMARY_SOURCE_MISMATCH")
	if int(previous_source_revision["authority_epoch"]) != _authority_epoch:
		return RepresentationUtils.failure("MATTER_SUMMARY_PREVIOUS_AUTHORITY_EPOCH_MISMATCH")
	if String(previous_source_revision["checksum"]) != String(_source_revision["checksum"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_PREVIOUS_SOURCE_REVISION_MISMATCH")
	if require_epoch_advance:
		if int(new_source_revision["authority_epoch"]) <= _authority_epoch:
			return RepresentationUtils.failure("MATTER_SUMMARY_HANDOFF_EPOCH_NOT_ADVANCED")
	else:
		if int(new_source_revision["authority_epoch"]) != _authority_epoch:
			return RepresentationUtils.failure("MATTER_SUMMARY_MUTATION_AUTHORITY_CHANGED")
	return RepresentationUtils.success()


func _contains_region_cell(cell_address: Dictionary) -> bool:
	if not bool(CellAddress.validate(cell_address).get("success", false)):
		return false
	if cell_address == _region_root_address:
		return true
	return CellAddress.is_ancestor(_region_root_address, cell_address)


func _bounds_equal(a: Array, b: Array) -> bool:
	if a.size() != 6 or b.size() != 6:
		return false
	for index in range(6):
		if not MatterUtils.approximately_equal(float(a[index]), float(b[index])):
			return false
	return true
