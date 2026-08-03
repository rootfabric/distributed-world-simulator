extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const CellAddress = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const BrickSnapshot = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const SummaryNode = preload("res://scripts/simulation/representation/matter/contracts/matter_summary_node.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")

const SCHEMA := "planet_simulator.matter_meshing_source_set.v1"
const MAX_MESH_LOD_LEVEL: int = 2
const SNAPSHOT_FIELDS: Array[String] = [
	"snapshot_id",
	"cell_address",
	"state_revision",
	"checksum",
]
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"target_cell_address",
	"target_scope_id",
	"lod_level",
	"source_snapshot_level",
	"expected_snapshot_count",
	"source_revision",
	"source_summary_checksum",
	"source_summary_authority_epoch",
	"source_summary_revision",
	"snapshots",
	"snapshot_set_hash",
	"checksum",
]


static func create(
	summary_node: Dictionary,
	snapshots: Array,
	grid_profile: Dictionary
) -> Dictionary:
	if not bool(SummaryNode.validate(summary_node).get("success", false)) \
		or not bool(GridProfile.validate(grid_profile).get("success", false)):
		return {}
	var target_address: Dictionary = summary_node["cell_address"]
	if not bool(CellGrid.validate_address(grid_profile, target_address).get("success", false)) \
		or String(summary_node["body_id"]) != String(grid_profile["body_id"]):
		return {}
	var source_level: int = int(grid_profile["max_level"])
	var lod_level: int = source_level - int(target_address["level"])
	if lod_level < 0 or lod_level > MAX_MESH_LOD_LEVEL:
		return {}
	var descriptors: Array = []
	for raw_snapshot in snapshots:
		if typeof(raw_snapshot) != TYPE_DICTIONARY:
			return {}
		var snapshot: Dictionary = raw_snapshot
		if not bool(BrickSnapshot.validate(snapshot).get("success", false)):
			return {}
		var cell_address: Dictionary = snapshot["address"]["cell_address"]
		descriptors.append({
			"snapshot_id": String(snapshot["snapshot_id"]),
			"cell_address": cell_address.duplicate(true),
			"state_revision": int(snapshot["state_revision"]),
			"checksum": String(snapshot["checksum"]),
		})
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_address"]["cell_id"]) < String(b["cell_address"]["cell_id"])
	)
	var source_revision: Dictionary = SummaryNode.to_source_revision(summary_node)
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": String(summary_node["body_id"]),
		"target_cell_address": target_address.duplicate(true),
		"target_scope_id": String(summary_node["scope_id"]),
		"lod_level": lod_level,
		"source_snapshot_level": source_level,
		"expected_snapshot_count": _expected_count(lod_level),
		"source_revision": source_revision,
		"source_summary_checksum": String(summary_node["checksum"]),
		"source_summary_authority_epoch": int(summary_node["authority_epoch"]),
		"source_summary_revision": int(summary_node["summary_revision"]),
		"snapshots": descriptors,
		"snapshot_set_hash": RepresentationUtils.payload_hash(descriptors),
		"checksum": "",
	}
	value["checksum"] = RepresentationUtils.compute_checksum(value)
	return value if bool(validate(value, grid_profile).get("success", false)) else {}


static func validate(value: Dictionary, grid_profile: Dictionary) -> Dictionary:
	var checked: Dictionary = RepresentationUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return RepresentationUtils.failure("UNSUPPORTED_MATTER_MESHING_SOURCE_SET_SCHEMA")
	if not bool(GridProfile.validate(grid_profile).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_MESHING_GRID_PROFILE")
	if String(value.get("body_id", "")) != String(grid_profile["body_id"]):
		return RepresentationUtils.failure("MATTER_MESHING_SOURCE_BODY_MISMATCH")
	if typeof(value.get("target_cell_address")) != TYPE_DICTIONARY:
		return RepresentationUtils.failure("INVALID_MATTER_MESHING_TARGET_CELL")
	var target_address: Dictionary = value["target_cell_address"]
	if not bool(CellGrid.validate_address(grid_profile, target_address).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_MESHING_TARGET_CELL")
	if String(value.get("target_scope_id", "")) != SummaryNode.scope_id_for(
		String(value["body_id"]), target_address
	):
		return RepresentationUtils.failure("MATTER_MESHING_TARGET_SCOPE_MISMATCH")
	for field in ["lod_level", "source_snapshot_level", "expected_snapshot_count"]:
		if not RepresentationUtils.is_json_integer(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_SOURCE_INTEGER", {"field": field})
	var lod_level: int = int(value["lod_level"])
	var source_level: int = int(value["source_snapshot_level"])
	if lod_level < 0 or lod_level > MAX_MESH_LOD_LEVEL:
		return RepresentationUtils.failure("INVALID_MATTER_MESHING_LOD_LEVEL")
	if source_level != int(grid_profile["max_level"]) \
		or int(target_address["level"]) + lod_level != source_level:
		return RepresentationUtils.failure("MATTER_MESHING_SOURCE_LEVEL_MISMATCH")
	var expected_count: int = _expected_count(lod_level)
	if int(value["expected_snapshot_count"]) != expected_count:
		return RepresentationUtils.failure("MATTER_MESHING_EXPECTED_COUNT_MISMATCH")
	if typeof(value.get("source_revision")) != TYPE_DICTIONARY:
		return RepresentationUtils.failure("INVALID_MATTER_MESHING_SOURCE_REVISION")
	var source_revision: Dictionary = value["source_revision"]
	checked = SourceRevision.validate(source_revision)
	if not bool(checked.get("success", false)):
		return checked
	if String(source_revision["source_domain"]) != "MATTER" \
		or String(source_revision["source_id"]) != String(value["body_id"]):
		return RepresentationUtils.failure("MATTER_MESHING_SOURCE_REVISION_MISMATCH")
	if not RepresentationUtils.is_lower_hex_64(value.get("source_summary_checksum")) \
		or String(value["source_summary_checksum"]) != String(source_revision["source_hash"]):
		return RepresentationUtils.failure("MATTER_MESHING_SUMMARY_CHECKSUM_MISMATCH")
	for field in ["source_summary_authority_epoch", "source_summary_revision"]:
		if not RepresentationUtils.is_json_integer(value.get(field)):
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_SUMMARY_FRONTIER", {"field": field})
	if int(value["source_summary_authority_epoch"]) != int(source_revision["authority_epoch"]) \
		or int(value["source_summary_revision"]) != int(source_revision["source_revision"]):
		return RepresentationUtils.failure("MATTER_MESHING_SUMMARY_FRONTIER_MISMATCH")
	if typeof(value.get("snapshots")) != TYPE_ARRAY \
		or value["snapshots"].size() != expected_count:
		return RepresentationUtils.failure("MATTER_MESHING_SNAPSHOT_COUNT_MISMATCH")
	var expected_addresses: Array = _descendants_at_level(target_address, source_level)
	if expected_addresses.size() != expected_count:
		return RepresentationUtils.failure("MATTER_MESHING_EXPECTED_DESCENDANTS_FAILED")
	var previous_cell_id: String = ""
	for index in range(value["snapshots"].size()):
		var raw_descriptor = value["snapshots"][index]
		if typeof(raw_descriptor) != TYPE_DICTIONARY:
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_SNAPSHOT_DESCRIPTOR", {"index": index})
		var descriptor: Dictionary = raw_descriptor
		checked = RepresentationUtils.validate_exact_fields(descriptor, SNAPSHOT_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not MatterUtils.is_canonical_id(descriptor.get("snapshot_id"), 2):
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_SNAPSHOT_ID", {"index": index})
		if typeof(descriptor.get("cell_address")) != TYPE_DICTIONARY \
			or not bool(CellGrid.validate_address(grid_profile, descriptor["cell_address"]).get("success", false)):
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_SNAPSHOT_CELL", {"index": index})
		var cell_address: Dictionary = descriptor["cell_address"]
		var cell_id: String = String(cell_address["cell_id"])
		if index > 0 and cell_id <= previous_cell_id:
			return RepresentationUtils.failure("MATTER_MESHING_SNAPSHOTS_NOT_SORTED_UNIQUE", {"index": index})
		if cell_address != expected_addresses[index]:
			return RepresentationUtils.failure("MATTER_MESHING_SNAPSHOT_COVERAGE_MISMATCH", {"index": index})
		if not RepresentationUtils.is_json_integer(descriptor.get("state_revision")) \
			or int(descriptor["state_revision"]) < 0 \
			or int(descriptor["state_revision"]) > int(source_revision["source_revision"]):
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_SNAPSHOT_REVISION", {"index": index})
		if not RepresentationUtils.is_lower_hex_64(descriptor.get("checksum")):
			return RepresentationUtils.failure("INVALID_MATTER_MESHING_SNAPSHOT_CHECKSUM", {"index": index})
		previous_cell_id = cell_id
	if not RepresentationUtils.is_lower_hex_64(value.get("snapshot_set_hash")) \
		or String(value["snapshot_set_hash"]) != RepresentationUtils.payload_hash(value["snapshots"]):
		return RepresentationUtils.failure("MATTER_MESHING_SNAPSHOT_SET_HASH_MISMATCH")
	return RepresentationUtils.validate_checksum(value)


static func _expected_count(lod_level: int) -> int:
	var count: int = 1
	for _index in range(lod_level):
		count *= 8
	return count


static func _descendants_at_level(root: Dictionary, target_level: int) -> Array:
	if not bool(CellAddress.validate(root).get("success", false)) \
		or target_level < int(root["level"]):
		return []
	var frontier: Array = [root.duplicate(true)]
	while not frontier.is_empty() and int(frontier[0]["level"]) < target_level:
		var next_frontier: Array = []
		for raw_address in frontier:
			var address: Dictionary = raw_address
			for child_index in range(8):
				var child: Dictionary = CellAddress.child(address, child_index)
				if child.is_empty():
					return []
				next_frontier.append(child)
		frontier = next_frontier
	frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_id"]) < String(b["cell_id"])
	)
	return frontier
