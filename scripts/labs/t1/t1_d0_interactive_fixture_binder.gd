extends RefCounted

const T1A3Script = preload("res://scripts/labs/t1/t1_d0_item_graph_materializer.gd")
const FactoryScript = preload("res://scripts/items/services/item_domain_factory.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const ContainerStateScript = preload("res://scripts/containers/container_state.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const AdapterScript = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const BridgeScript = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const PlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")
const UtilityNodeScript = preload("res://scripts/construction/utilities/construction_utility_node_definition.gd")
const UtilityLinkScript = preload("res://scripts/construction/utilities/construction_utility_link_definition.gd")
const UtilityNetworkScript = preload("res://scripts/construction/utilities/construction_utility_network_definition.gd")
const UtilityDemandScript = preload("res://scripts/construction/utilities/construction_utility_demand.gd")
const UtilityStorageScript = preload("res://scripts/construction/utilities/construction_utility_storage_state.gd")
const UtilitySimulatorScript = preload("res://scripts/construction/utilities/construction_utility_simulator.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.t1a4_interactive_fixture_binding.v1"
const CONSTRUCT_ID := "construct/t1/lunar-outpost/d0"
const STORAGE_CONTAINER_ID := "container/t1/d0/storage-main"
const PLAN_ID := "plan/t1a4/d0/materialize-bound"
const OPERATION_ID := "operation/t1a4/d0/materialize-bound"
const AUTHORITY_OWNER_ID := "authority/t1a4/d0"
const POWER_NETWORK_ID := "utility-network/power/t1a4/d0"
const DATA_NETWORK_ID := "utility-network/data/t1a4/d0"

const HOST_PARTS := {
	"DOOR": "part/t1/d0/p0025",
	"CONTAINER": "part/t1/d0/p0026",
	"GENERATOR": "part/t1/d0/p0027",
	"BATTERY": "part/t1/d0/p0028",
	"LAMP": "part/t1/d0/p0029",
	"CONSOLE": "part/t1/d0/p0030",
}

static func materialize_bound(m0_root: String, reuse_existing_m0: bool = false) -> Dictionary:
	if m0_root.strip_edges().is_empty():
		return _failure("T1A4_M0_ROOT_REQUIRED")
	var resolved: Dictionary = T1A3Script.build_resolved_snapshot()
	if not bool(resolved.get("success", false)):
		return resolved
	var domain: Dictionary = FactoryScript.create()
	T1A3Script._register_definitions(domain)
	var added: Dictionary = T1A3Script._add_source_items(domain, resolved)
	if not bool(added.get("success", false)):
		return _failure("T1A4_SOURCE_ITEM_GRAPH_BUILD_FAILED", {"cause": added})

	var bindings_result := _compile_bindings(resolved)
	if not bool(bindings_result.get("success", false)):
		return bindings_result
	var bindings: Dictionary = bindings_result["bindings"]
	var behavior: Dictionary = bindings_result["behavior"]
	var bind_result := _apply_binding_components(domain, bindings)
	if not bool(bind_result.get("success", false)):
		return bind_result
	var container_result := _materialize_storage_container(domain, bindings)
	if not bool(container_result.get("success", false)):
		return container_result
	var initial_validation: Dictionary = domain.validator.validate_graph()
	if not bool(initial_validation.get("success", false)):
		return _failure("T1A4_BOUND_SOURCE_ITEM_GRAPH_INVALID", {"cause": initial_validation})

	var constructs = ConstructStoreScript.new()
	var bridge = BridgeScript.new()
	var bridge_setup: Dictionary = bridge.setup(m0_root)
	if not bool(bridge_setup.get("success", false)):
		return _failure("T1A4_M0_BRIDGE_SETUP_FAILED", {"cause": bridge_setup})
	var adapter = AdapterScript.new()
	var adapter_setup: Dictionary = adapter.setup(
		domain.items, domain.containers, domain.validator, domain.mass, domain.operations,
		constructs, bridge, AUTHORITY_OWNER_ID, 1, 0, 0, 0, {}
	)
	if not bool(adapter_setup.get("success", false)):
		return _failure("T1A4_AUTHORITATIVE_ADAPTER_SETUP_FAILED", {"cause": adapter_setup})

	var snapshot: Dictionary = Dictionary(resolved["snapshot"])
	var plan: Dictionary = {}
	var applied: Dictionary = {}
	var reused_existing_m0: bool = false
	var existing_snapshot: Dictionary = adapter.get_construct_snapshot(CONSTRUCT_ID)
	if reuse_existing_m0 and not existing_snapshot.is_empty():
		if UtilsScript.canonical_json(existing_snapshot) != UtilsScript.canonical_json(snapshot):
			return _failure("T1A4_EXISTING_CONSTRUCT_MISMATCH", {
				"expected_checksum": String(snapshot.get("checksum", "")),
				"actual_checksum": String(existing_snapshot.get("checksum", "")),
			})
		applied = adapter.get_operation_result(OPERATION_ID)
		if applied.is_empty():
			return _failure("T1A4_EXISTING_CONSTRUCT_OPERATION_RESULT_MISSING")
		reused_existing_m0 = true
	else:
		var root_projection := PlannerScript.create_root_projection(
			String(resolved["root_item_id"]), CONSTRUCT_ID, "T1 D0 Lunar Outpost", RelationsScript.world()
		)
		var part_sources: Array = []
		for part_value in snapshot.get("parts", []):
			var part: Dictionary = Dictionary(part_value)
			var projection: Dictionary = adapter.get_item_projection(String(part["item_instance_id"]))
			if projection.is_empty():
				return _failure("T1A4_PART_SOURCE_PROJECTION_MISSING", {"part_id": String(part["part_id"])})
			part_sources.append(projection)
		var plan_result := PlannerScript.build_assembly_plan(
			PLAN_ID, OPERATION_ID, snapshot, root_projection, part_sources, {}
		)
		if not bool(plan_result.get("success", false)):
			return _failure("T1A4_ASSEMBLY_PLAN_FAILED", {"cause": plan_result})
		plan = plan_result["plan"]
		applied = adapter.apply_plan(plan)
		if not bool(applied.get("success", false)):
			return _failure("T1A4_AUTHORITATIVE_COMMIT_FAILED", {"cause": applied})
	var final_validation: Dictionary = domain.validator.validate_graph()
	if not bool(final_validation.get("success", false)):
		return _failure("T1A4_FINAL_ITEM_GRAPH_INVALID", {"cause": final_validation})

	var utility_result := _compile_utilities(resolved, bindings)
	if not bool(utility_result.get("success", false)):
		return utility_result
	var profile := {
		"schema": SCHEMA,
		"construct_id": CONSTRUCT_ID,
		"construct_checksum": String(snapshot.get("checksum", "")),
		"bindings": _sorted_binding_rows(bindings),
		"behavior_capabilities": behavior["capabilities"],
		"behavior_affordances": behavior["affordances"],
		"power_network": utility_result["power_network"],
		"power_demands": utility_result["power_demands"],
		"power_storage": utility_result["power_storage"],
		"power_execution_profile": utility_result["power_execution_profile"],
		"data_network": utility_result["data_network"],
		"data_demands": utility_result["data_demands"],
		"data_execution_profile": utility_result["data_execution_profile"],
		"checksum": "",
	}
	profile["checksum"] = _profile_checksum(profile)
	return {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"resolved": resolved,
		"domain": domain,
		"constructs": constructs,
		"bridge": bridge,
		"adapter": adapter,
		"plan": plan,
		"apply_result": applied,
		"reused_existing_m0": reused_existing_m0,
		"binding_profile": profile,
		"authority_report": adapter.get_authority_report(),
	}

static func _compile_bindings(resolved: Dictionary) -> Dictionary:
	var inverse: Dictionary = Dictionary(resolved.get("global_to_semantic_item_ids", {}))
	var bindings: Dictionary = {}
	var capabilities: Array = []
	var affordances: Array = []
	for item_id_value in resolved.get("interactive_item_ids", []):
		var item_id := String(item_id_value)
		var semantic := String(inverse.get(item_id, ""))
		var kind := _kind_from_semantic(semantic)
		if not HOST_PARTS.has(kind):
			return _failure("T1A4_UNKNOWN_INTERACTIVE_KIND", {"semantic_item_reference": semantic})
		var host_part := String(HOST_PARTS[kind])
		var capability_id := "capability/t1a4/d0/%s" % kind.to_lower()
		var capability := CapabilityScript.create(
			capability_id, _capability_kind(kind), [host_part], [],
			{"fixture_item_id": item_id, "semantic_item_reference": semantic}
		)
		var checked := CapabilityScript.validate(capability)
		if not bool(checked.get("success", false)):
			return _failure("T1A4_CAPABILITY_INVALID", {"kind": kind, "cause": checked})
		capabilities.append(capability)
		var item_affordances: Array = []
		for action in _actions_for_kind(kind):
			var affordance := AffordanceScript.create(
				"affordance/t1a4/d0/%s/%s" % [kind.to_lower(), String(action).to_lower()],
				String(action), capability_id, host_part, "", ["INTERACT"],
				{"fixture_item_id": item_id, "semantic_item_reference": semantic}, _priority_for_kind(kind)
			)
			var affordance_checked := AffordanceScript.validate(affordance)
			if not bool(affordance_checked.get("success", false)):
				return _failure("T1A4_AFFORDANCE_INVALID", {"kind": kind, "action": action, "cause": affordance_checked})
			affordances.append(affordance)
			item_affordances.append(String(affordance["affordance_id"]))
		bindings[kind] = {
			"kind": kind,
			"item_id": item_id,
			"semantic_item_reference": semantic,
			"host_part_id": host_part,
			"capability_id": capability_id,
			"affordance_ids": item_affordances,
			"container_id": STORAGE_CONTAINER_ID if kind == "CONTAINER" else "",
			"utility_node_ids": _utility_node_ids(kind),
		}
	capabilities.sort_custom(func(a, b): return String(a["capability_id"]) < String(b["capability_id"]))
	affordances.sort_custom(func(a, b): return String(a["affordance_id"]) < String(b["affordance_id"]))
	return {"success": true, "bindings": bindings, "behavior": {"capabilities": capabilities, "affordances": affordances}}

static func _apply_binding_components(domain: Dictionary, bindings: Dictionary) -> Dictionary:
	for kind in bindings:
		var binding: Dictionary = bindings[kind]
		var item = domain.items.get_item(String(binding["item_id"]))
		if item == null:
			return _failure("T1A4_BOUND_ITEM_MISSING", {"kind": kind})
		var fixture: Dictionary = Dictionary(item.components.get("t1_fixture", {})).duplicate(true)
		fixture["gameplay_semantics_materialized"] = true
		item.components["t1_fixture"] = fixture
		item.components["fixture_binding"] = {
			"schema": "planet_simulator.t1_fixture_binding_component.v1",
			"construct_id": CONSTRUCT_ID,
			"kind": String(kind),
			"host_part_id": String(binding["host_part_id"]),
			"capability_id": String(binding["capability_id"]),
			"affordance_ids": Array(binding["affordance_ids"]).duplicate(true),
			"utility_node_ids": Array(binding["utility_node_ids"]).duplicate(true),
			"container_id": String(binding["container_id"]),
		}
	return {"success": true, "error_code": ""}

static func _materialize_storage_container(domain: Dictionary, bindings: Dictionary) -> Dictionary:
	var storage_binding: Dictionary = bindings.get("CONTAINER", {})
	if storage_binding.is_empty():
		return _failure("T1A4_STORAGE_BINDING_MISSING")
	var storage_item = domain.items.get_item(String(storage_binding["item_id"]))
	if storage_item == null:
		return _failure("T1A4_STORAGE_ITEM_MISSING")
	storage_item.components["container"] = {"container_id": STORAGE_CONTAINER_ID}
	var container = ContainerStateScript.new({
		"container_id": STORAGE_CONTAINER_ID,
		"owner_kind": "ITEM_INSTANCE",
		"owner_id": String(storage_binding["item_id"]),
		"storage_mode": ContainerStateScript.STORAGE_SLOTS,
		"slot_count": 24,
		"maximum_mass_kg": 2000.0,
		"maximum_volume_l": 2400.0,
		"allow_nested_containers": true,
		"maximum_nested_depth": 8,
	})
	if not domain.containers.add_container(container):
		return _failure("T1A4_STORAGE_CONTAINER_ADD_FAILED")
	return {"success": true, "error_code": "", "container_id": STORAGE_CONTAINER_ID}

static func _compile_utilities(resolved: Dictionary, bindings: Dictionary) -> Dictionary:
	var snapshot: Dictionary = Dictionary(resolved["snapshot"])
	var revision := int(snapshot.get("state_revision", 0))
	var checksum := String(snapshot.get("checksum", ""))
	var power_nodes := [
		UtilityNodeScript.create(_power_node("generator"), POWER_NETWORK_ID, "POWER", "SOURCE", CONSTRUCT_ID, _host(bindings, "GENERATOR"), 100.0, 900, {"online": true, "fixture_item_id": _item(bindings, "GENERATOR"), "source_kind": "GENERATOR"}),
		UtilityNodeScript.create(_power_node("battery"), POWER_NETWORK_ID, "POWER", "STORAGE", CONSTRUCT_ID, _host(bindings, "BATTERY"), 25.0, 700, {"storage_capacity": 100.0, "max_charge_per_tick": 25.0, "max_discharge_per_tick": 25.0, "charge_efficiency": 0.95, "discharge_efficiency": 0.95, "fixture_item_id": _item(bindings, "BATTERY")}),
		UtilityNodeScript.create(_power_node("bus"), POWER_NETWORK_ID, "POWER", "JUNCTION", CONSTRUCT_ID, "part/t1/d0/p0031", 0.0, 100, {"binding": "T1A4"}),
		UtilityNodeScript.create(_power_node("door"), POWER_NETWORK_ID, "POWER", "CONSUMER", CONSTRUCT_ID, _host(bindings, "DOOR"), 0.0, 900, {"fixture_item_id": _item(bindings, "DOOR")}),
		UtilityNodeScript.create(_power_node("lamp"), POWER_NETWORK_ID, "POWER", "CONSUMER", CONSTRUCT_ID, _host(bindings, "LAMP"), 0.0, 500, {"fixture_item_id": _item(bindings, "LAMP")}),
		UtilityNodeScript.create(_power_node("console"), POWER_NETWORK_ID, "POWER", "CONSUMER", CONSTRUCT_ID, _host(bindings, "CONSOLE"), 0.0, 700, {"fixture_item_id": _item(bindings, "CONSOLE")}),
	]
	var power_links := [
		UtilityLinkScript.create("utility-link/power/t1a4/d0/battery-bus", POWER_NETWORK_ID, "POWER", _power_node("battery"), _power_node("bus"), 50.0, 0.01),
		UtilityLinkScript.create("utility-link/power/t1a4/d0/generator-bus", POWER_NETWORK_ID, "POWER", _power_node("generator"), _power_node("bus"), 100.0, 0.01),
		UtilityLinkScript.create("utility-link/power/t1a4/d0/bus-door", POWER_NETWORK_ID, "POWER", _power_node("bus"), _power_node("door"), 20.0, 0.01),
		UtilityLinkScript.create("utility-link/power/t1a4/d0/bus-lamp", POWER_NETWORK_ID, "POWER", _power_node("bus"), _power_node("lamp"), 30.0, 0.02),
		UtilityLinkScript.create("utility-link/power/t1a4/d0/bus-console", POWER_NETWORK_ID, "POWER", _power_node("bus"), _power_node("console"), 30.0, 0.02),
	]
	var power_network := UtilityNetworkScript.create(POWER_NETWORK_ID, "POWER", CONSTRUCT_ID, revision, checksum, power_nodes, power_links, {"voltage_v": 400.0, "binding_stage": "T1A4"})
	var checked := UtilityNetworkScript.validate(power_network)
	if not bool(checked.get("success", false)):
		return _failure("T1A4_POWER_NETWORK_INVALID", {"cause": checked})
	var power_demands := [
		UtilityDemandScript.create("utility-demand/power/t1a4/d0/door", POWER_NETWORK_ID, _power_node("door"), 5.0, 2.0, 900, "critical-access", {"fixture_item_id": _item(bindings, "DOOR")}),
		UtilityDemandScript.create("utility-demand/power/t1a4/d0/lamp", POWER_NETWORK_ID, _power_node("lamp"), 10.0, 5.0, 500, "lighting", {"fixture_item_id": _item(bindings, "LAMP")}),
		UtilityDemandScript.create("utility-demand/power/t1a4/d0/console", POWER_NETWORK_ID, _power_node("console"), 15.0, 10.0, 700, "control", {"fixture_item_id": _item(bindings, "CONSOLE")}),
	]
	var power_storage := UtilityStorageScript.create(POWER_NETWORK_ID, _power_node("battery"), 0, 0, 50.0, 100.0)
	var power_step := UtilitySimulatorScript.step(power_network, power_demands, [power_storage], 1)
	if not bool(power_step.get("success", false)):
		return _failure("T1A4_POWER_SIMULATION_FAILED", {"cause": power_step})

	var data_nodes := [
		UtilityNodeScript.create(_data_node("console"), DATA_NETWORK_ID, "DATA", "SOURCE", CONSTRUCT_ID, _host(bindings, "CONSOLE"), 100.0, 900, {"online": true, "fixture_item_id": _item(bindings, "CONSOLE"), "source_kind": "CONTROL_CONSOLE"}),
		UtilityNodeScript.create(_data_node("door"), DATA_NETWORK_ID, "DATA", "CONSUMER", CONSTRUCT_ID, _host(bindings, "DOOR"), 0.0, 800, {"fixture_item_id": _item(bindings, "DOOR")}),
		UtilityNodeScript.create(_data_node("storage"), DATA_NETWORK_ID, "DATA", "CONSUMER", CONSTRUCT_ID, _host(bindings, "CONTAINER"), 0.0, 400, {"fixture_item_id": _item(bindings, "CONTAINER")}),
	]
	var data_links := [
		UtilityLinkScript.create("utility-link/data/t1a4/d0/console-door", DATA_NETWORK_ID, "DATA", _data_node("console"), _data_node("door"), 50.0, 0.0),
		UtilityLinkScript.create("utility-link/data/t1a4/d0/console-storage", DATA_NETWORK_ID, "DATA", _data_node("console"), _data_node("storage"), 50.0, 0.0),
	]
	var data_network := UtilityNetworkScript.create(DATA_NETWORK_ID, "DATA", CONSTRUCT_ID, revision, checksum, data_nodes, data_links, {"binding_stage": "T1A4"})
	checked = UtilityNetworkScript.validate(data_network)
	if not bool(checked.get("success", false)):
		return _failure("T1A4_DATA_NETWORK_INVALID", {"cause": checked})
	var data_demands := [
		UtilityDemandScript.create("utility-demand/data/t1a4/d0/door", DATA_NETWORK_ID, _data_node("door"), 5.0, 2.0, 800, "access-control", {"fixture_item_id": _item(bindings, "DOOR")}),
		UtilityDemandScript.create("utility-demand/data/t1a4/d0/storage", DATA_NETWORK_ID, _data_node("storage"), 5.0, 1.0, 400, "storage-telemetry", {"fixture_item_id": _item(bindings, "CONTAINER")}),
	]
	var data_step := UtilitySimulatorScript.step(data_network, data_demands, [], 1)
	if not bool(data_step.get("success", false)):
		return _failure("T1A4_DATA_SIMULATION_FAILED", {"cause": data_step})
	return {
		"success": true,
		"power_network": power_network,
		"power_demands": power_demands,
		"power_storage": power_storage,
		"power_execution_profile": power_step["profile"],
		"data_network": data_network,
		"data_demands": data_demands,
		"data_execution_profile": data_step["profile"],
	}

static func validate_binding_profile(profile: Dictionary) -> Dictionary:
	if String(profile.get("schema", "")) != SCHEMA:
		return _failure("T1A4_BINDING_PROFILE_SCHEMA_MISMATCH")
	if String(profile.get("construct_id", "")) != CONSTRUCT_ID:
		return _failure("T1A4_BINDING_PROFILE_CONSTRUCT_MISMATCH")
	if typeof(profile.get("bindings")) != TYPE_ARRAY or Array(profile["bindings"]).size() != 6:
		return _failure("T1A4_BINDING_PROFILE_CARDINALITY_MISMATCH")
	for capability in profile.get("behavior_capabilities", []):
		var checked := CapabilityScript.validate(capability)
		if not bool(checked.get("success", false)): return checked
	for affordance in profile.get("behavior_affordances", []):
		var checked := AffordanceScript.validate(affordance)
		if not bool(checked.get("success", false)): return checked
	for network_key in ["power_network", "data_network"]:
		var checked := UtilityNetworkScript.validate(Dictionary(profile.get(network_key, {})))
		if not bool(checked.get("success", false)): return checked
	if String(profile.get("checksum", "")) != _profile_checksum(profile):
		return _failure("T1A4_BINDING_PROFILE_CHECKSUM_MISMATCH")
	return {"success": true, "error_code": ""}

static func _profile_checksum(profile: Dictionary) -> String:
	var payload := profile.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _sorted_binding_rows(bindings: Dictionary) -> Array:
	var rows: Array = []
	for kind in bindings:
		rows.append(Dictionary(bindings[kind]).duplicate(true))
	rows.sort_custom(func(a, b): return String(a["kind"]) < String(b["kind"]))
	return rows

static func _kind_from_semantic(value: String) -> String:
	for kind in ["door", "container", "generator", "battery", "lamp", "console"]:
		if value.contains("/%s/" % kind): return kind.to_upper()
	return ""

static func _capability_kind(kind: String) -> String:
	match kind:
		"DOOR": return "DOOR_CONTROL"
		"CONTAINER": return "CONTAINER"
		"GENERATOR": return "POWER_SOURCE"
		"BATTERY": return "POWER_STORAGE"
		"LAMP": return "LIGHTING"
		"CONSOLE": return "WORKSTATION"
	return "INTERACTIVE_FIXTURE"

static func _actions_for_kind(kind: String) -> Array:
	match kind:
		"DOOR": return ["CLOSE_DOOR", "OPEN_DOOR"]
		"CONTAINER": return ["OPEN_CONTAINER", "STORE_ITEM", "TAKE_ITEM"]
		"GENERATOR": return ["START_GENERATOR", "STOP_GENERATOR"]
		"BATTERY": return ["INSPECT_BATTERY"]
		"LAMP": return ["TOGGLE_LIGHT"]
		"CONSOLE": return ["USE_WORKSTATION"]
	return ["INTERACT"]

static func _priority_for_kind(kind: String) -> int:
	return 900 if kind == "DOOR" else 700 if kind in ["GENERATOR", "CONSOLE"] else 500

static func _utility_node_ids(kind: String) -> Array:
	match kind:
		"DOOR": return [_data_node("door"), _power_node("door")]
		"CONTAINER": return [_data_node("storage")]
		"GENERATOR": return [_power_node("generator")]
		"BATTERY": return [_power_node("battery")]
		"LAMP": return [_power_node("lamp")]
		"CONSOLE": return [_data_node("console"), _power_node("console")]
	return []

static func _power_node(name: String) -> String: return "utility-node/power/t1a4/d0/%s" % name
static func _data_node(name: String) -> String: return "utility-node/data/t1a4/d0/%s" % name
static func _host(bindings: Dictionary, kind: String) -> String: return String(Dictionary(bindings[kind])["host_part_id"])
static func _item(bindings: Dictionary, kind: String) -> String: return String(Dictionary(bindings[kind])["item_id"])

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result := {"success": false, "error_code": code}
	for key in details: result[key] = details[key]
	return result
