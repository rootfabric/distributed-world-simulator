extends RefCounted

# Composition port, not a persistence engine or a Construction owner. All
# payloads are native owner exports; M6 stores them with the gameplay cut.
const U = preload("res://scripts/network/contracts/network_contract_utils.gd")
const AuthorityState = preload("res://scripts/construction/authoritative/construction_authoritative_state.gd")
const BuildStore = preload("res://scripts/construction/build/construction_build_plan_store.gd")
const Gateway = preload("res://scripts/construction/multiplayer/construction_multiplayer_gateway.gd")
const SCHEMA := "dws.live3.native_construction_recovery.v1"
const FIELDS: Array[String] = ["schema", "authority", "build_plans", "gateway", "checksum"]

var _authority
var _build
var _store
var _gateway

func bind(bridge, item_graph) -> Dictionary:
	if _gateway != null:
		return _fail("LIVE3_CONSTRUCTION_ALREADY_BOUND")
	if bridge == null or not bridge.has_method("get_snapshot_packet"):
		return _fail("LIVE3_CONSTRUCTION_BRIDGE_REQUIRED")
	# This is the one audited P4/M3 composition seam. It never reaches into a
	# client, and cannot substitute an unrelated Item Graph or a fixture store.
	var gateway = bridge.get("_gateway")
	var executor = gateway.get("_executor") if gateway != null else null
	var port = executor.get("_adapter") if executor != null else null
	var build = executor.get("_build_process") if executor != null else null
	var authority = port.get("_construction_adapter") if port != null else null
	if port == null or not port.has_method("is_bound_to_item_graph") or not port.is_bound_to_item_graph(item_graph):
		return _fail("LIVE3_CONSTRUCTION_ITEM_GRAPH_BINDING_MISMATCH")
	if authority == null or build == null or not build.has_method("get_store"):
		return _fail("LIVE3_NATIVE_CONSTRUCTION_OWNERS_REQUIRED")
	var store = build.get_store()
	if store == null or not store.has_method("load_dict") or not gateway.has_method("load_state"):
		return _fail("LIVE3_NATIVE_CONSTRUCTION_RECOVERY_PORTS_REQUIRED")
	_authority = authority
	_build = build
	_store = store
	_gateway = gateway
	return {"success": true, "error_code": ""}

func export_state() -> Dictionary:
	if _gateway == null:
		return {}
	var state := {
		"schema": SCHEMA,
		"authority": _authority.export_state(),
		"build_plans": _store.to_dict(),
		"gateway": _gateway.export_state(),
		"checksum": "",
	}
	state["checksum"] = checksum(state)
	return state

static func validate_state(state: Dictionary, owner: String, epoch: int) -> Dictionary:
	var checked: Dictionary = U.validate_exact_fields(state, FIELDS)
	if not bool(checked.get("success", false)):
		return _fail("LIVE3_CONSTRUCTION_FIELDS_INVALID", checked)
	if state.get("schema") != SCHEMA or state.get("checksum") != checksum(state):
		return _fail("LIVE3_CONSTRUCTION_CHECKSUM_INVALID")
	for field in ["authority", "build_plans", "gateway"]:
		if not state.get(field) is Dictionary:
			return _fail("LIVE3_CONSTRUCTION_SECTION_INVALID", {"field": field})
	checked = AuthorityState.validate(state["authority"])
	if not bool(checked.get("success", false)):
		return _fail("LIVE3_CONSTRUCTION_AUTHORITY_INVALID", checked)
	if state["authority"].get("authority_owner_id") != owner + "/construction" or int(state["authority"].get("authority_epoch", 0)) != epoch:
		return _fail("LIVE3_CONSTRUCTION_OWNER_MISMATCH")
	checked = BuildStore.validate_state(state["build_plans"])
	if not bool(checked.get("success", false)):
		return _fail("LIVE3_BUILD_PLAN_STATE_INVALID", checked)
	checked = Gateway.validate_state(state["gateway"])
	if not bool(checked.get("success", false)):
		return _fail("LIVE3_CONSTRUCTION_REPLAY_INVALID", checked)
	return {"success": true, "error_code": ""}

func restore_state(state: Dictionary, owner: String, epoch: int) -> Dictionary:
	var checked := validate_state(state, owner, epoch)
	if not bool(checked.get("success", false)):
		return checked
	if _gateway == null:
		return _fail("LIVE3_CONSTRUCTION_NOT_BOUND")
	# P4 already reopened and synchronized the SAME M0 repository. Do not
	# overwrite a newer M0 state with an older gameplay cut. A mismatched cut
	# requires explicit recovery, not fresh seeding or material duplication.
	if U.canonical_json(_authority.export_state()) != U.canonical_json(state["authority"]):
		return _fail("LIVE3_M0_GAMEPLAY_CUT_MISMATCH")
	var old_store: Dictionary = _store.to_dict()
	var old_gateway: Dictionary = _gateway.export_state()
	var loaded: Dictionary = _store.load_dict(state["build_plans"])
	if bool(loaded.get("success", false)):
		loaded = _gateway.load_state(state["gateway"])
	if bool(loaded.get("success", false)):
		for plan in state["build_plans"]["plans"]:
			loaded = _build.reconcile_plan(String(plan["build_plan_id"]))
			if not bool(loaded.get("success", false)):
				break
	if not bool(loaded.get("success", false)) or U.canonical_json(export_state()) != U.canonical_json(state):
		_store.load_dict(old_store)
		_gateway.load_state(old_gateway)
		return _fail("LIVE3_CONSTRUCTION_RESTORE_NOT_EXACT", loaded)
	return {"success": true, "error_code": "", "native_m0_state_unchanged": true}

static func checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true)
	payload["checksum"] = ""
	return U.payload_hash(payload)

static func _fail(code: String, cause: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": {"cause": cause}}
