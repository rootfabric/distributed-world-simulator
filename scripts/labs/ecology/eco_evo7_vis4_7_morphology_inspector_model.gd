extends RefCounted

## ECO.EVO7 VIS4.7 — read-only Morphology Inspector model.
##
## This module only joins already-published Descriptor V2 facts with already-
## materialized PH5 presentation identities. It performs no biology, ecology,
## selection, mutation, persistence or network work.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_7_morphology_inspector.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.7.R1"

const PRESENTATION_ONLY := true
const ECOLOGY_AUTHORITY := false
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false

const POTENTIAL_FIELDS: Array[String] = [
	"max_height_m",
	"internode_length_m",
	"apical_dominance",
	"branch_probability",
	"branch_angle_deg",
	"branch_length_ratio",
	"branching_depth",
	"crown_spread_m",
	"foliage_density",
	"leaf_economics_proxy",
	"structural_investment",
	"root_depth_m",
	"root_spread_m",
	"root_shoot_ratio",
]

const TOPOLOGY_FIELDS: Array[String] = [
	"max_height_m",
	"internode_length_m",
	"apical_dominance",
	"branch_probability",
	"branch_angle_deg",
	"branch_length_ratio",
	"branching_depth",
	"crown_spread_m",
]

const FUNCTIONAL_FIELDS: Array[String] = [
	"realized_height_m",
	"realized_crown_radius_m",
	"realized_crown_density",
	"leaf_area_index_proxy",
	"leaf_size_proxy",
	"leaf_conservative_strategy",
	"structural_investment",
	"realized_root_depth_m",
	"realized_root_spread_m",
	"root_shoot_ratio",
]

const COMPETITION_FIELDS: Array[String] = [
	"water_satisfaction",
	"effective_light",
	"realized_resource_balance",
]


static func build(
	generation: int,
	source_ecology_hash: String,
	descriptor: Dictionary,
	render_identity: Dictionary,
	grid_appearance: Dictionary
) -> Dictionary:
	if generation < 1 or source_ecology_hash.length() != 64:
		return {}
	if descriptor.is_empty() or render_identity.is_empty() or grid_appearance.is_empty():
		return {}

	var record_id := String(descriptor.get("record_id", ""))
	var descriptor_hash := String(descriptor.get("descriptor_hash", ""))
	var growth_graph_hash := String(descriptor.get("growth_graph_hash", ""))
	if record_id.is_empty() or descriptor_hash.length() != 64 or growth_graph_hash.length() != 64:
		return {}
	if String(render_identity.get("record_id", "")) != record_id:
		return {}
	if String(render_identity.get("source_descriptor_hash", "")) != descriptor_hash:
		return {}
	if String(render_identity.get("source_growth_graph_hash", "")) != growth_graph_hash:
		return {}
	if String(grid_appearance.get("record_id", "")) != record_id:
		return {}
	if String(grid_appearance.get("source_descriptor_hash", "")) != descriptor_hash:
		return {}

	var potential_value = descriptor.get("potential_morphology")
	var topology_value = descriptor.get("realized_topology")
	var functional_value = descriptor.get("functional_morphology")
	var competition_value = descriptor.get("competition_context")
	if not potential_value is Dictionary:
		return {}
	if not topology_value is Dictionary:
		return {}
	if not functional_value is Dictionary:
		return {}
	if not competition_value is Dictionary:
		return {}

	var potential: Dictionary = Dictionary(potential_value).duplicate(true)
	var topology: Dictionary = Dictionary(topology_value).duplicate(true)
	var functional: Dictionary = Dictionary(functional_value).duplicate(true)
	var competition: Dictionary = Dictionary(competition_value).duplicate(true)
	if not _has_fields(potential, POTENTIAL_FIELDS):
		return {}
	if not _has_fields(topology, TOPOLOGY_FIELDS):
		return {}
	if not _has_fields(functional, FUNCTIONAL_FIELDS):
		return {}
	if not _has_fields(competition, COMPETITION_FIELDS):
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"ecology_authority": ECOLOGY_AUTHORITY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"generation": generation,
		"source_ecology_hash": source_ecology_hash,
		"record_id": record_id,
		"cell_index": int(descriptor.get("cell_index", -1)),
		"lineage_id": String(descriptor.get("lineage_id", "")),
		"hereditary_individual_seed": int(descriptor.get("hereditary_individual_seed", -1)),
		"development_individual_seed": int(descriptor.get("development_individual_seed", -1)),
		"evidence_level": String(descriptor.get("evidence_level", "")),
		"descriptor_hash": descriptor_hash,
		"phenotype_hash": String(descriptor.get("phenotype_hash", "")),
		"plasticity_phenotype_hash": String(descriptor.get("plasticity_phenotype_hash", "")),
		"growth_graph_hash": growth_graph_hash,
		"source_evidence_record_hash": String(descriptor.get("source_evidence_record_hash", "")),
		"source_evaluation_hash": String(descriptor.get("source_evaluation_hash", "")),
		"potential_morphology": potential,
		"realized_topology": topology,
		"functional_morphology": functional,
		"competition_context": competition,
		"orientation_yaw_deg": float(render_identity.get("orientation_yaw_deg", NAN)),
		"individuality_hash": String(render_identity.get("individuality_hash", "")),
		"render_description_hash": String(render_identity.get("render_description_hash", "")),
		"representation_hash": String(render_identity.get("representation_hash", "")),
		"materialization_hash": String(render_identity.get("materialization_hash", "")),
		"tier": String(render_identity.get("tier", "")),
		"appearance_hash": String(grid_appearance.get("appearance_hash", "")),
		"canonical_world": Vector3(grid_appearance.get("canonical_world", Vector3.ZERO)),
		"visual_world": Vector3(grid_appearance.get("visual_world", Vector3.ZERO)),
		"visual_offset_is_canonical": false,
	}
	result["inspector_hash"] = compute_hash(result)
	return result if validate(result) else {}


static func validate(value: Dictionary) -> bool:
	if String(value.get("schema", "")) != SCHEMA:
		return false
	if String(value.get("version", "")) != VERSION or String(value.get("revision", "")) != REVISION:
		return false
	if not bool(value.get("presentation_only", false)):
		return false
	if bool(value.get("ecology_authority", true)):
		return false
	if bool(value.get("network_authority", true)) or bool(value.get("persistence_authority", true)):
		return false
	if int(value.get("generation", -1)) < 1:
		return false
	if String(value.get("source_ecology_hash", "")).length() != 64:
		return false
	if String(value.get("record_id", "")).is_empty() or int(value.get("cell_index", -1)) < 0:
		return false
	if String(value.get("lineage_id", "")).is_empty():
		return false
	if int(value.get("hereditary_individual_seed", -1)) < 0:
		return false
	if int(value.get("development_individual_seed", -1)) < 0:
		return false
	for key in [
		"descriptor_hash",
		"phenotype_hash",
		"plasticity_phenotype_hash",
		"growth_graph_hash",
		"source_evidence_record_hash",
		"source_evaluation_hash",
		"individuality_hash",
		"render_description_hash",
		"representation_hash",
		"materialization_hash",
		"appearance_hash",
	]:
		if String(value.get(key, "")).length() != 64:
			return false
	var potential_value = value.get("potential_morphology")
	var topology_value = value.get("realized_topology")
	var functional_value = value.get("functional_morphology")
	var competition_value = value.get("competition_context")
	if not potential_value is Dictionary or not topology_value is Dictionary:
		return false
	if not functional_value is Dictionary or not competition_value is Dictionary:
		return false
	if not _has_fields(Dictionary(potential_value), POTENTIAL_FIELDS):
		return false
	if not _has_fields(Dictionary(topology_value), TOPOLOGY_FIELDS):
		return false
	if not _has_fields(Dictionary(functional_value), FUNCTIONAL_FIELDS):
		return false
	if not _has_fields(Dictionary(competition_value), COMPETITION_FIELDS):
		return false
	var yaw := float(value.get("orientation_yaw_deg", NAN))
	if not is_finite(yaw) or yaw < 0.0 or yaw >= 360.0:
		return false
	if bool(value.get("visual_offset_is_canonical", true)):
		return false
	return String(value.get("inspector_hash", "")) == compute_hash(value)


static func format_text(value: Dictionary) -> String:
	if not validate(value):
		return "VIS4.7 Morphology Inspector\nINVALID / UNAVAILABLE"

	var p: Dictionary = value["potential_morphology"]
	var r: Dictionary = value["realized_topology"]
	var f: Dictionary = value["functional_morphology"]
	var c: Dictionary = value["competition_context"]
	var canonical: Vector3 = value["canonical_world"]
	var visual: Vector3 = value["visual_world"]

	return "\n".join(PackedStringArray([
		"VIS4.7 MORPHOLOGY INSPECTOR",
		"record: %s    cell: %d    generation: %d" % [
			String(value["record_id"]),
			int(value["cell_index"]),
			int(value["generation"]),
		],
		"lineage: %s" % String(value["lineage_id"]),
		"seed hereditary: %d    development: %d    yaw: %.2f deg" % [
			int(value["hereditary_individual_seed"]),
			int(value["development_individual_seed"]),
			float(value["orientation_yaw_deg"]),
		],
		"",
		"REALIZED",
		"height %.3f m    crown radius %.3f m    crown density %.3f    LAI %.3f" % [
			float(f["realized_height_m"]),
			float(f["realized_crown_radius_m"]),
			float(f["realized_crown_density"]),
			float(f["leaf_area_index_proxy"]),
		],
		"internode %.3f m    apical %.3f    branch p %.3f    angle %.2f deg" % [
			float(r["internode_length_m"]),
			float(r["apical_dominance"]),
			float(r["branch_probability"]),
			float(r["branch_angle_deg"]),
		],
		"branch length ratio %.3f    depth %d    crown spread %.3f m" % [
			float(r["branch_length_ratio"]),
			int(r["branching_depth"]),
			float(r["crown_spread_m"]),
		],
		"leaf size %.3f    conservative %.3f    structural %.3f" % [
			float(f["leaf_size_proxy"]),
			float(f["leaf_conservative_strategy"]),
			float(f["structural_investment"]),
		],
		"roots depth %.3f m    spread %.3f m    root/shoot %.3f" % [
			float(f["realized_root_depth_m"]),
			float(f["realized_root_spread_m"]),
			float(f["root_shoot_ratio"]),
		],
		"water %.3f    light %.3f    resource balance %.3f" % [
			float(c["water_satisfaction"]),
			float(c["effective_light"]),
			float(c["realized_resource_balance"]),
		],
		"",
		"GENETIC POTENTIAL",
		"height %.3f m    crown spread %.3f m    foliage density %.3f" % [
			float(p["max_height_m"]),
			float(p["crown_spread_m"]),
			float(p["foliage_density"]),
		],
		"internode %.3f m    apical %.3f    branch p %.3f    angle %.2f deg" % [
			float(p["internode_length_m"]),
			float(p["apical_dominance"]),
			float(p["branch_probability"]),
			float(p["branch_angle_deg"]),
		],
		"branch length ratio %.3f    depth %d    leaf economics %.3f" % [
			float(p["branch_length_ratio"]),
			int(p["branching_depth"]),
			float(p["leaf_economics_proxy"]),
		],
		"structural %.3f    root depth %.3f m    root spread %.3f m    root/shoot %.3f" % [
			float(p["structural_investment"]),
			float(p["root_depth_m"]),
			float(p["root_spread_m"]),
			float(p["root_shoot_ratio"]),
		],
		"",
		"PRESENTATION",
		"tier: %s    canonical position: (%.2f, %.2f, %.2f)" % [
			String(value["tier"]), canonical.x, canonical.y, canonical.z,
		],
		"visual position: (%.2f, %.2f, %.2f)    visual offset NONCANONICAL" % [
			visual.x, visual.y, visual.z,
		],
		"",
		"HASHES",
		"ecology: %s" % _short_hash(String(value["source_ecology_hash"])),
		"descriptor: %s    phenotype: %s" % [
			_short_hash(String(value["descriptor_hash"])),
			_short_hash(String(value["phenotype_hash"])),
		],
		"growth graph: %s    individuality: %s" % [
			_short_hash(String(value["growth_graph_hash"])),
			_short_hash(String(value["individuality_hash"])),
		],
		"render description: %s" % _short_hash(String(value["render_description_hash"])),
		"representation: %s    materialization: %s" % [
			_short_hash(String(value["representation_hash"])),
			_short_hash(String(value["materialization_hash"])),
		],
		"appearance: %s    inspector: %s" % [
			_short_hash(String(value["appearance_hash"])),
			_short_hash(String(value["inspector_hash"])),
		],
	]))


static func compute_hash(value: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		str(int(value.get("generation", -1))),
		String(value.get("source_ecology_hash", "")),
		String(value.get("record_id", "")),
		str(int(value.get("cell_index", -1))),
		String(value.get("lineage_id", "")),
		str(int(value.get("hereditary_individual_seed", -1))),
		str(int(value.get("development_individual_seed", -1))),
		String(value.get("descriptor_hash", "")),
		String(value.get("phenotype_hash", "")),
		String(value.get("plasticity_phenotype_hash", "")),
		String(value.get("growth_graph_hash", "")),
		String(value.get("source_evidence_record_hash", "")),
		String(value.get("source_evaluation_hash", "")),
		String(value.get("individuality_hash", "")),
		String(value.get("render_description_hash", "")),
		String(value.get("representation_hash", "")),
		String(value.get("materialization_hash", "")),
		String(value.get("appearance_hash", "")),
		String(value.get("tier", "")),
		"%.9f" % float(value.get("orientation_yaw_deg", 0.0)),
	])
	_append_map(tokens, "P", value.get("potential_morphology", {}), POTENTIAL_FIELDS, ["branching_depth"])
	_append_map(tokens, "R", value.get("realized_topology", {}), TOPOLOGY_FIELDS, ["branching_depth"])
	_append_map(tokens, "F", value.get("functional_morphology", {}), FUNCTIONAL_FIELDS, [])
	_append_map(tokens, "C", value.get("competition_context", {}), COMPETITION_FIELDS, [])
	return "|".join(tokens).sha256_text()


static func _append_map(
	tokens: PackedStringArray,
	prefix: String,
	value,
	fields: Array[String],
	integer_fields: Array[String]
) -> void:
	if not value is Dictionary:
		tokens.append(prefix + ":INVALID")
		return
	var data: Dictionary = value
	for key in fields:
		var token := str(int(data.get(key, 0))) if key in integer_fields else "%.9f" % float(data.get(key, 0.0))
		tokens.append("%s:%s=%s" % [prefix, key, token])


static func _has_fields(value: Dictionary, fields: Array[String]) -> bool:
	for key in fields:
		if not value.has(key):
			return false
		var raw = value.get(key)
		if key == "branching_depth":
			if typeof(raw) != TYPE_INT:
				return false
		elif typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
			return false
	return true


static func _short_hash(value: String) -> String:
	return value.substr(0, 16) + "…" if value.length() >= 16 else value
