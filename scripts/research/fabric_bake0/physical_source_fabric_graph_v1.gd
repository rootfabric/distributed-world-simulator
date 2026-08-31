extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceView = preload("res://scripts/research/fabric_bake0/physical_source_view_v1.gd")

const KIND := "BRIDGE1_PHYSICAL_SOURCE_FABRIC_GRAPH"
const FABRIC0_16_EXACT_EXECUTABLE := "3307d553c1c3c79cd9c15a5c565af7fef3f0400c"
const FABRIC0_18_REVIEWED_CLOSURE := "b9f4a11cb7c31e47884d12eaad2985811e0b6563"
const COMPILER_VERSION := "FABRIC-BAKE/BRIDGE-1-PHYSICAL-SOURCE-GRAPH-R1"
const CONSTRUCTION_FIELDS: Array[String] = ["construct_id", "parts", "bonds", "boundary_anchors"]

static func compile(view: Dictionary) -> Dictionary:
	if not bool(view.get("success", false)) or String(view.get("kind", "")) != SourceView.KIND:
		return Utils.failure("BRIDGE1_BAD_PHYSICAL_SOURCE_VIEW")
	var frontier: Dictionary = view["frontier"]
	var construction_source: Dictionary = {}
	for source in frontier["sources"]:
		if String(source["source_domain"]) == "CONSTRUCTION":
			if not construction_source.is_empty():
				return Utils.failure("BRIDGE1_MULTIPLE_CONSTRUCTION_SOURCES_UNSUPPORTED")
			construction_source = source
	if construction_source.is_empty():
		return Utils.failure("BRIDGE1_CONSTRUCTION_SOURCE_REQUIRED")
	var construction := SourceView.payload(view, "CONSTRUCTION", String(construction_source["source_id"]))
	if construction.is_empty():
		return Utils.failure("BRIDGE1_CONSTRUCTION_PAYLOAD_MISSING")
	var checked := Utils.validate_exact_fields(construction, CONSTRUCTION_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(construction.get("construct_id"), 2):
		return Utils.failure("BRIDGE1_INVALID_CONSTRUCT_ID")
	for field in ["parts", "bonds", "boundary_anchors"]:
		if typeof(construction.get(field)) != TYPE_ARRAY:
			return Utils.failure("BRIDGE1_INVALID_CONSTRUCTION_COLLECTION", {"field": field})

	var parts := Utils.sorted_dicts(construction["parts"], "part_id")
	var bonds := Utils.sorted_dicts(construction["bonds"], "bond_id")
	var anchors := Utils.sorted_dicts(construction["boundary_anchors"], "anchor_id")
	var part_ids: Array = []
	var topology_parts: Array = []
	for part in parts:
		var part_id := String(part.get("part_id", ""))
		if not Utils.is_canonical_id(part_id, 2):
			return Utils.failure("BRIDGE1_INVALID_GRAPH_PART_ID")
		part_ids.append(part_id)
		topology_parts.append({"part_id": part_id, "region_id": String(part.get("region_id", ""))})
	var topology_bonds: Array = []
	for bond in bonds:
		topology_bonds.append({
			"bond_id": String(bond.get("bond_id", "")),
			"part_a": String(bond.get("part_a", "")),
			"part_b": String(bond.get("part_b", "")),
			"rigid": bool(bond.get("rigid", false)),
		})
	var topology_anchors: Array = []
	for anchor in anchors:
		topology_anchors.append({
			"anchor_id": String(anchor.get("anchor_id", "")),
			"part_id": String(anchor.get("part_id", "")),
		})
	var topology_hash := Utils.canonical_hash({
		"construct_id": construction["construct_id"],
		"parts": topology_parts,
		"bonds": topology_bonds,
		"anchors": topology_anchors,
	})
	var graph_payload := {
		"schema": "planet_simulator.fabric_bake_bridge1_physical_source_graph.v1",
		"source_frontier_hash": frontier["frontier_hash"],
		"construct_id": construction["construct_id"],
		"part_ids": part_ids,
		"bond_ids": bonds.map(func(x): return String(x.get("bond_id", ""))),
		"anchor_ids": anchors.map(func(x): return String(x.get("anchor_id", ""))),
		"topology_hash": topology_hash,
		"physical_core_minimum_dependency": FABRIC0_16_EXACT_EXECUTABLE,
		"reviewed_physical_core_frontier": FABRIC0_18_REVIEWED_CLOSURE,
		"compiler_version": COMPILER_VERSION,
	}
	return {
		"success": true,
		"kind": KIND,
		"graph": graph_payload,
		"graph_hash": Utils.canonical_hash(graph_payload),
		"topology_hash": topology_hash,
		"construction_payload": construction,
	}
