extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const NodeScript = preload("res://scripts/construction/utilities/construction_utility_node_definition.gd")
const LinkScript = preload("res://scripts/construction/utilities/construction_utility_link_definition.gd")
const NetworkScript = preload("res://scripts/construction/utilities/construction_utility_network_definition.gd")
const DemandScript = preload("res://scripts/construction/utilities/construction_utility_demand.gd")
const StorageScript = preload("res://scripts/construction/utilities/construction_utility_storage_state.gd")

static func source_checksum(key: String) -> String: return UtilsScript.payload_hash({"construct": key, "revision": 0})
static func kind_slug(kind: String) -> String: return kind.to_lower()

static func direct_network(kind: String, key: String = "direct", source_capacity: float = 20.0, loss_fraction: float = 0.0, source_online: bool = true) -> Dictionary:
	var prefix := "utility-node/%s/%s/" % [kind_slug(kind), key]
	var network_id := "utility-network/%s/%s" % [kind_slug(kind), key]
	var construct_id := "construct/utility/%s/%s" % [kind_slug(kind), key]
	var nodes := [
		NodeScript.create(prefix + "source", network_id, kind, "SOURCE", construct_id, "part/utility/%s/%s/source" % [kind_slug(kind), key], source_capacity, 500, {"online": source_online}),
		NodeScript.create(prefix + "consumer", network_id, kind, "CONSUMER", construct_id, "part/utility/%s/%s/consumer" % [kind_slug(kind), key], 0.0, 100, {}),
	]
	var links := [LinkScript.create("utility-link/%s/%s/direct" % [kind_slug(kind), key], network_id, kind, prefix + "source", prefix + "consumer", source_capacity, loss_fraction)]
	return NetworkScript.create(network_id, kind, construct_id, 0, source_checksum("%s/%s" % [kind, key]), nodes, links, {"fixture": key})

static func direct_demand(kind: String, key: String = "direct", requested: float = 5.0, minimum: float = 5.0, priority: int = 500) -> Dictionary:
	return DemandScript.create("utility-demand/%s/%s/main" % [kind_slug(kind), key], "utility-network/%s/%s" % [kind_slug(kind), key], "utility-node/%s/%s/consumer" % [kind_slug(kind), key], requested, minimum, priority, "main", {"utility_kind": kind})

static func power_network(key: String = "allocation", source_capacity: float = 100.0, source_online: bool = true, storage_capacity: float = 40.0) -> Dictionary:
	var network_id := "utility-network/power/%s" % key
	var construct_id := "construct/utility/power/%s" % key
	var prefix := "utility-node/power/%s/" % key
	var nodes := [
		NodeScript.create(prefix + "generator", network_id, "POWER", "SOURCE", construct_id, "part/utility/power/%s/generator" % key, source_capacity, 900, {"online": source_online, "source_kind": "GENERATOR"}),
		NodeScript.create(prefix + "battery", network_id, "POWER", "STORAGE", construct_id, "part/utility/power/%s/battery" % key, 20.0, 500, {"storage_capacity": storage_capacity, "max_charge_per_tick": 20.0, "max_discharge_per_tick": 20.0, "charge_efficiency": 0.9, "discharge_efficiency": 0.9}),
		NodeScript.create(prefix + "bus", network_id, "POWER", "JUNCTION", construct_id, "part/utility/power/%s/bus" % key, 0.0, 100, {}),
		NodeScript.create(prefix + "machine", network_id, "POWER", "CONSUMER", construct_id, "part/utility/power/%s/machine" % key, 0.0, 100, {}),
		NodeScript.create(prefix + "lights", network_id, "POWER", "CONSUMER", construct_id, "part/utility/power/%s/lights" % key, 0.0, 100, {}),
	]
	var links := [
		LinkScript.create("utility-link/power/%s/battery-bus" % key, network_id, "POWER", prefix + "battery", prefix + "bus", 50.0, 0.02),
		LinkScript.create("utility-link/power/%s/bus-lights" % key, network_id, "POWER", prefix + "bus", prefix + "lights", 60.0, 0.10),
		LinkScript.create("utility-link/power/%s/bus-machine" % key, network_id, "POWER", prefix + "bus", prefix + "machine", 80.0, 0.05),
		LinkScript.create("utility-link/power/%s/generator-bus" % key, network_id, "POWER", prefix + "generator", prefix + "bus", 100.0, 0.05),
	]
	return NetworkScript.create(network_id, "POWER", construct_id, 0, source_checksum("power/%s" % key), nodes, links, {"voltage_v": 400.0})

static func power_storage(key: String = "allocation", stored: float = 20.0, tick: int = 0, revision: int = 0, capacity: float = 40.0) -> Dictionary:
	return StorageScript.create("utility-network/power/%s" % key, "utility-node/power/%s/battery" % key, tick, revision, stored, capacity)

static func machine_demand(key: String = "allocation", requested: float = 70.0, minimum: float = 60.0, priority: int = 900) -> Dictionary:
	return DemandScript.create("utility-demand/power/%s/machine" % key, "utility-network/power/%s" % key, "utility-node/power/%s/machine" % key, requested, minimum, priority, "critical-machines", {"machine": true})
static func lights_demand(key: String = "allocation", requested: float = 50.0, minimum: float = 10.0, priority: int = 100) -> Dictionary:
	return DemandScript.create("utility-demand/power/%s/lights" % key, "utility-network/power/%s" % key, "utility-node/power/%s/lights" % key, requested, minimum, priority, "comfort", {"lighting": true})

static func machine_requirement(key: String, units_per_work_unit: float = 1.0, minimum_ratio: float = 1.0) -> Dictionary:
	return {"utility_kind": "POWER", "network_id": "utility-network/power/%s" % key, "demand_id": "utility-demand/power/%s/machine" % key, "units_per_work_unit": units_per_work_unit, "minimum_ratio": minimum_ratio}
