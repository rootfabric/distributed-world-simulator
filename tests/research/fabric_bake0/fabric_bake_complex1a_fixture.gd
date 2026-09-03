extends RefCounted

const Fabric = preload("res://scripts/research/fabric0/fabric0_conservation_fabric_v1.gd")

const DOMAIN := "electrical_like"
const SOURCE_ID := "source/battery"
const SOURCE_VOLTAGE := 12.0
const LOAD_GAIN := 0.25
const POWER_ON_THRESHOLD := 1.0
const EPSILON := 1.0e-9

static func single_path(reverse_links: bool = false) -> Dictionary:
	return _subject(
		["support/critical-a", "support/unrelated"],
		["load/lamp-a"],
		[{
			"bond_id": "wire/path-a",
			"a_element": SOURCE_ID,
			"a_port": "p",
			"b_element": "load/lamp-a",
			"b_port": "p",
			"support_bond_ids": ["support/critical-a"],
			"active": true,
		}],
		reverse_links
	)

static func redundant_path(reverse_links: bool = false) -> Dictionary:
	return _subject(
		["support/path-a", "support/path-b", "support/unrelated"],
		["load/lamp-a"],
		[
			{
				"bond_id": "wire/path-a",
				"a_element": SOURCE_ID,
				"a_port": "p",
				"b_element": "load/lamp-a",
				"b_port": "p",
				"support_bond_ids": ["support/path-a"],
				"active": true,
			},
			{
				"bond_id": "wire/path-b",
				"a_element": SOURCE_ID,
				"a_port": "p",
				"b_element": "load/lamp-a",
				"b_port": "p",
				"support_bond_ids": ["support/path-b"],
				"active": true,
			},
		],
		reverse_links
	)

static func two_loads(reverse_links: bool = false) -> Dictionary:
	return _subject(
		["support/branch-a", "support/branch-b", "support/unrelated"],
		["load/lamp-a", "load/lamp-b"],
		[
			{
				"bond_id": "wire/branch-a",
				"a_element": SOURCE_ID,
				"a_port": "p",
				"b_element": "load/lamp-a",
				"b_port": "p",
				"support_bond_ids": ["support/branch-a"],
				"active": true,
			},
			{
				"bond_id": "wire/branch-b",
				"a_element": SOURCE_ID,
				"a_port": "p",
				"b_element": "load/lamp-b",
				"b_port": "p",
				"support_bond_ids": ["support/branch-b"],
				"active": true,
			},
		],
		reverse_links
	)

static func apply_structural_break(subject: Dictionary, structural_bond_id: String, event_id: String) -> Dictionary:
	if event_id.is_empty():
		return {"success": false, "error_code": "COMPLEX1A_INVALID_EVENT_ID"}
	if subject["applied_event_ids"].has(event_id):
		return {"success": false, "error_code": "COMPLEX1A_STRUCTURAL_EVENT_ALREADY_APPLIED"}
	if not subject["structural_bonds"].has(structural_bond_id):
		return {"success": false, "error_code": "COMPLEX1A_STRUCTURAL_BOND_NOT_FOUND"}
	if not bool(subject["structural_bonds"][structural_bond_id]):
		return {"success": false, "error_code": "COMPLEX1A_STRUCTURAL_BOND_ALREADY_BROKEN"}
	var next: Dictionary = subject.duplicate(true)
	next["structural_bonds"][structural_bond_id] = false
	var mutations: Array = []
	for index in range(next["functional_links"].size()):
		var link: Dictionary = next["functional_links"][index]
		if not bool(link["active"]):
			continue
		if structural_bond_id not in link["support_bond_ids"]:
			continue
		link["active"] = false
		next["functional_links"][index] = link
		mutations.append({
			"bond_id": String(link["bond_id"]),
			"reason": "SUPPORT_TOPOLOGY_LOST",
			"support_bond_id": structural_bond_id,
		})
	mutations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["bond_id"]) < String(b["bond_id"]))
	next["applied_event_ids"].append(event_id)
	next["applied_event_ids"].sort()
	return {
		"success": true,
		"subject": next,
		"event_id": event_id,
		"broken_structural_bond_id": structural_bond_id,
		"functional_topology_mutations": mutations,
	}

static func solve(subject: Dictionary) -> Dictionary:
	var network := Fabric.new_network()
	if not Fabric.register_domain(network, DOMAIN, "voltage", "current", "V", "A"):
		return {"success": false, "error_code": "COMPLEX1A_DOMAIN_REGISTRATION_FAILED"}
	if not Fabric.add_element(network, Fabric.ideal_common_constraint(SOURCE_ID, DOMAIN, SOURCE_VOLTAGE)):
		return {"success": false, "error_code": "COMPLEX1A_SOURCE_ADD_FAILED"}
	var load_ids: Array = subject["load_ids"].duplicate()
	load_ids.sort()
	for load_id in load_ids:
		if not Fabric.add_element(network, Fabric.equilibrium_terminal(String(load_id), DOMAIN, 0.0, LOAD_GAIN)):
			return {"success": false, "error_code": "COMPLEX1A_LOAD_ADD_FAILED"}
	for link in subject["functional_links"]:
		if not bool(link["active"]):
			continue
		if not Fabric.link_ports(
			network, String(link["bond_id"]), String(link["a_element"]), String(link["a_port"]),
			String(link["b_element"]), String(link["b_port"])
		):
			return {"success": false, "error_code": "COMPLEX1A_FUNCTIONAL_LINK_FAILED", "bond_id": link["bond_id"]}
	var result := Fabric.solve(network)
	if not bool(result.get("ok", false)):
		return {"success": false, "error_code": "COMPLEX1A_PHYSICAL_SOLVE_FAILED", "details": result}
	var loads: Dictionary = {}
	for load_id in load_ids:
		var state := Fabric.read_port_state(network, String(load_id), "p")
		var power := Fabric.read_element_absorbed_power(network, String(load_id))
		loads[String(load_id)] = {
			"voltage": float(state.get("common", 0.0)),
			"current": float(state.get("balance", 0.0)),
			"absorbed_power": power,
			"on": absf(power) >= POWER_ON_THRESHOLD,
		}
	return {
		"success": true,
		"network": network,
		"network_hash": Fabric.state_hash(network),
		"loads": loads,
		"max_balance_residual": Fabric.max_balance_residual(network),
		"max_power_residual": Fabric.max_power_residual(network),
		"active_functional_bond_ids": _active_link_ids(subject),
	}

static func _subject(structural_bond_ids: Array, load_ids: Array, functional_links: Array, reverse_links: bool) -> Dictionary:
	var structural_bonds: Dictionary = {}
	for bond_id in structural_bond_ids:
		structural_bonds[String(bond_id)] = true
	var links := functional_links.duplicate(true)
	if reverse_links:
		links.reverse()
	return {
		"structural_bonds": structural_bonds,
		"load_ids": load_ids.duplicate(),
		"functional_links": links,
		"applied_event_ids": [],
	}

static func _active_link_ids(subject: Dictionary) -> Array:
	var ids: Array = []
	for link in subject["functional_links"]:
		if bool(link["active"]):
			ids.append(String(link["bond_id"]))
	ids.sort()
	return ids
