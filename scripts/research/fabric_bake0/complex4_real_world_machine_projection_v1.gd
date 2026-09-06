extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v1.gd")

const DOMAIN := "electrical_like"
const POWER_LINK_KIND := "POWER_LINK"
const META_FUNCTIONAL_ROLE := "functional_role"
const ROLE_SOURCE := "power_source"
const ROLE_LOAD := "power_load"
const EPSILON := 1.0e-9

static func solve(snapshot: Dictionary) -> Dictionary:
	var checked := Snapshot.validate(snapshot)
	if not bool(checked.get("success", false)):
		return Utils.failure("COMPLEX4_CONSTRUCTION_SNAPSHOT_INVALID", {"cause": checked.get("error_code", "")})
	var part_by_id: Dictionary = {}
	var source_parts: Array = []
	var load_parts: Array = []
	for raw_part in snapshot["parts"]:
		var part: Dictionary = raw_part
		part_by_id[String(part["part_id"])] = part
		var role := String(Dictionary(part["metadata"]).get(META_FUNCTIONAL_ROLE, ""))
		if role == ROLE_SOURCE:
			source_parts.append(part)
		elif role == ROLE_LOAD:
			load_parts.append(part)
	if source_parts.size() != 1 or load_parts.size() != 1:
		return Utils.failure("COMPLEX4_FUNCTIONAL_CARDINALITY_INVALID", {"sources": source_parts.size(), "loads": load_parts.size()})
	var source: Dictionary = source_parts[0]
	var load: Dictionary = load_parts[0]
	var source_common := float(Dictionary(source["metadata"]).get("source_common", 0.0))
	var load_gain := float(Dictionary(load["metadata"]).get("load_gain", 0.0))
	var on_threshold := float(Dictionary(load["metadata"]).get("on_power_threshold_w", 0.0))
	if not is_finite(source_common) or not is_finite(load_gain) or not is_finite(on_threshold) or load_gain <= 0.0 or on_threshold <= 0.0:
		return Utils.failure("COMPLEX4_FUNCTIONAL_PARAMETERS_INVALID")

	var bond_by_id: Dictionary = {}
	for raw_bond in snapshot["bonds"]:
		var bond: Dictionary = raw_bond
		bond_by_id[String(bond["bond_id"])] = bond
	var active_links: Array = []
	var disabled_links: Array = []
	var link_rows: Array = []
	for raw_bond in snapshot["bonds"]:
		var bond: Dictionary = raw_bond
		if String(bond["bond_kind"]) != POWER_LINK_KIND:
			continue
		if String(bond["part_a_id"]) != String(source["part_id"]) or String(bond["part_b_id"]) != String(load["part_id"]):
			return Utils.failure("COMPLEX4_POWER_LINK_ENDPOINT_INVALID", {"bond_id": bond["bond_id"]})
		var support_ids = Dictionary(bond["metadata"]).get("support_bond_ids", [])
		if typeof(support_ids) != TYPE_ARRAY or support_ids.is_empty():
			return Utils.failure("COMPLEX4_FUNCTIONAL_SUPPORT_INVALID", {"bond_id": bond["bond_id"]})
		var canonical_supports: Array = []
		var supported := String(bond["state"]) != "BROKEN"
		for raw_support in support_ids:
			var support_id := String(raw_support)
			if not bond_by_id.has(support_id) or String(bond_by_id[support_id]["bond_kind"]) == POWER_LINK_KIND:
				return Utils.failure("COMPLEX4_FUNCTIONAL_SUPPORT_UNKNOWN", {"bond_id": bond["bond_id"], "support_bond_id": support_id})
			canonical_supports.append(support_id)
			if String(bond_by_id[support_id]["state"]) == "BROKEN":
				supported = false
		canonical_supports.sort()
		var row := {"bond_id": String(bond["bond_id"]), "support_bond_ids": canonical_supports, "active": supported}
		link_rows.append(row)
		if supported:
			active_links.append(String(bond["bond_id"]))
		else:
			disabled_links.append(String(bond["bond_id"]))
	active_links.sort(); disabled_links.sort()
	link_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["bond_id"]) < String(b["bond_id"]))
	if link_rows.is_empty():
		return Utils.failure("COMPLEX4_FUNCTIONAL_LINKS_MISSING")

	var network := Fabric.new_network()
	if not Fabric.register_domain(network, DOMAIN, "voltage", "current", "V", "A"):
		return Utils.failure("COMPLEX4_DOMAIN_REGISTRATION_FAILED")
	if not Fabric.add_element(network, Fabric.ideal_common_constraint(String(source["part_id"]), DOMAIN, source_common)):
		return Utils.failure("COMPLEX4_SOURCE_ADD_FAILED")
	if not Fabric.add_element(network, Fabric.equilibrium_terminal(String(load["part_id"]), DOMAIN, 0.0, load_gain)):
		return Utils.failure("COMPLEX4_LOAD_ADD_FAILED")
	for row in link_rows:
		if not bool(row["active"]):
			continue
		if not Fabric.link_ports(network, String(row["bond_id"]), String(source["part_id"]), "p", String(load["part_id"]), "p"):
			return Utils.failure("COMPLEX4_FUNCTIONAL_LINK_FAILED", {"bond_id": row["bond_id"]})
	var result := Fabric.solve(network)
	if not bool(result.get("ok", false)):
		return Utils.failure("COMPLEX4_FUNCTIONAL_SOLVE_FAILED", {"diagnostics": result.get("diagnostics", [])})
	var load_state := Fabric.read_port_state(network, String(load["part_id"]), "p")
	var absorbed_power := Fabric.read_element_absorbed_power(network, String(load["part_id"]))
	var machine_state := "ON" if absf(absorbed_power) >= on_threshold else "OFF"
	var details := {
		"construct_id": snapshot["construct_id"],
		"construct_revision": snapshot["state_revision"],
		"construct_checksum": snapshot["checksum"],
		"source_part_id": source["part_id"],
		"load_part_id": load["part_id"],
		"active_power_link_ids": active_links,
		"disabled_power_link_ids": disabled_links,
		"link_rows": link_rows,
		"source_common": source_common,
		"load_common": float(load_state.get("common", 0.0)),
		"load_balance": float(load_state.get("balance", 0.0)),
		"load_absorbed_power": absorbed_power,
		"machine_state": machine_state,
		"max_balance_residual": Fabric.max_balance_residual(network),
		"max_power_residual": Fabric.max_power_residual(network),
		"network_hash": Fabric.state_hash(network),
		"projection_hash": "",
	}
	details["projection_hash"] = Utils.canonical_hash(details)
	return Utils.success(details)
