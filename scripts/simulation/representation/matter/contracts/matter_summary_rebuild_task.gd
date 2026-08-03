extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")

const SCHEMA := "planet_simulator.matter_summary_rebuild_task.v1"
const FIELDS: Array[String] = [
	"schema", "task_id", "body_id", "cell_address", "scope_id",
	"target_authority_epoch", "target_source_revision", "reason",
	"dirty_bounds_m", "enqueue_revision", "priority_level", "checksum",
]


static func create(
	task_id: String,
	body_id: String,
	cell_address: Dictionary,
	target_authority_epoch: int,
	target_source_revision: int,
	reason: String,
	dirty_bounds_m: Array,
	enqueue_revision: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"task_id": task_id,
		"body_id": body_id,
		"cell_address": cell_address.duplicate(true),
		"scope_id": SummaryNode.scope_id_for(body_id, cell_address),
		"target_authority_epoch": target_authority_epoch,
		"target_source_revision": target_source_revision,
		"reason": reason,
		"dirty_bounds_m": dirty_bounds_m.duplicate(true),
		"enqueue_revision": enqueue_revision,
		"priority_level": int(cell_address.get("level", -1)),
		"checksum": "",
	}
	value["checksum"] = RepresentationUtils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = RepresentationUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return RepresentationUtils.failure("UNSUPPORTED_MATTER_SUMMARY_REBUILD_TASK_SCHEMA")
	if not MatterUtils.is_canonical_id(value.get("task_id"), 2) \
		or not MatterUtils.is_canonical_id(value.get("body_id"), 2):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REBUILD_TASK_ID")
	if typeof(value.get("cell_address")) != TYPE_DICTIONARY \
		or not bool(CellAddress.validate(value["cell_address"]).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REBUILD_CELL")
	if String(value.get("scope_id", "")) != SummaryNode.scope_id_for(String(value["body_id"]), value["cell_address"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_SCOPE_MISMATCH")
	for field in ["target_authority_epoch", "target_source_revision", "enqueue_revision", "priority_level"]:
		if not RepresentationUtils.is_json_integer(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REBUILD_INTEGER", {"field": field})
	if int(value["target_authority_epoch"]) < 1 or int(value["target_source_revision"]) < 0 \
		or int(value["enqueue_revision"]) < 1:
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REBUILD_FRONTIER")
	if int(value["priority_level"]) != int(value["cell_address"]["level"]):
		return RepresentationUtils.failure("MATTER_SUMMARY_REBUILD_PRIORITY_MISMATCH")
	if typeof(value.get("reason")) != TYPE_STRING \
		or not RepresentationUtils.INVALIDATION_REASONS.has(String(value["reason"])):
		return RepresentationUtils.failure("INVALID_MATTER_SUMMARY_REBUILD_REASON")
	checked = RepresentationUtils.validate_bounds_m(value.get("dirty_bounds_m"))
	if not bool(checked.get("success", false)):
		return checked
	return RepresentationUtils.validate_checksum(value)
