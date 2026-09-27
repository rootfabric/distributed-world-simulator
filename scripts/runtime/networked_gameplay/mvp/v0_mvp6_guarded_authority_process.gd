extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_authority_process.gd"

const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
const Protocol6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")

var _guard6_count := 0
var _guard6_last: Dictionary = {}
var _guard6_restore_count := 0
var _guard6_restore_last: Dictionary = {}
var _guard6_active := false
var _resource_provenance6: Dictionary = {}


func _ensure_ore6(required: int) -> Dictionary:
	# The graphical five-process path must consume the material actually produced
	# by the inherited MVP5 mine -> canonical Item Graph flow. Never mint a local
	# Construction top-up. The MVP5 projection is a pure read of the SAME M4
	# Item Graph and therefore provides the provenance binding for this cut.
	var graph = _graph6()
	if graph == null or _shared_dig4 == null:
		return Protocol6.failure("MVP6_CANONICAL_MINED_ORE_REQUIRED")
	var material: Dictionary = _shared_dig4.material_snapshot("a", Protocol6.session(cfg, "a"))
	if not bool(material.get("success", false)):
		return material
	var material_details: Dictionary = Dictionary(material.get("details", {})).duplicate(true)
	var totals: Dictionary = Dictionary(material_details.get("totals", {}))
	var mined_total := int(totals.get("a", -1))
	var staged: Dictionary = _stage_ore6()
	if not bool(staged.get("success", false)):
		return staged
	var available := _ore6(graph.create_snapshot(), "a")
	_resource_provenance6 = {
		"source": "MVP5_CANONICAL_MINING_OUTPUT",
		"required": required,
		"mined_total": mined_total,
		"ore_available": available,
		"material_digest": String(material_details.get("material_digest", "")),
		"item_graph_checksum": String(material_details.get("item_graph_checksum", "")),
		"item_graph_revision": int(material_details.get("item_graph_revision", -1)),
		"item_graph_tick": int(material_details.get("item_graph_tick", -1)),
		"topup_issued": false,
		"same_canonical_item_graph": available == mined_total,
	}
	if mined_total < required or available < required:
		return Protocol6.failure("MVP6_CONSTRUCTION_ORE_INSUFFICIENT")
	if available != mined_total or String(_resource_provenance6.get("material_digest", "")).length() != 64 or String(_resource_provenance6.get("item_graph_checksum", "")).length() != 64:
		return Protocol6.failure("MVP6_CONSTRUCTION_ORE_PROVENANCE_DIVERGED")
	return Protocol6.success(_resource_provenance6.duplicate(true))


func handle_rpc(body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP6_"):
		return super.handle_rpc(body)
	var guarded: Dictionary = Guard6.apply(boundary, gateway_peer)
	if not bool(guarded.get("success", false)):
		return Protocol6.failure(String(guarded.get("error_code", "MVP6_ENET_GUARD_FAILED")))
	_guard6_count += 1
	_guard6_last = Dictionary(guarded.get("details", {})).duplicate(true)
	_guard6_active = true
	var result: Dictionary = super.handle_rpc(body)
	var restored: Dictionary = Guard6.restore(boundary, gateway_peer)
	if not bool(restored.get("success", false)):
		return Protocol6.failure(String(restored.get("error_code", "MVP6_ENET_GUARD_RESTORE_FAILED")))
	_guard6_restore_count += 1
	_guard6_restore_last = Dictionary(restored.get("details", {})).duplicate(true)
	_guard6_active = false
	return result


func report(passed: bool, phase: String) -> Dictionary:
	var value: Dictionary = super.report(passed, phase)
	var mvp6: Dictionary = Dictionary(value.get("mvp6", {})).duplicate(true)
	mvp6["resource_provenance"] = _resource_provenance6.duplicate(true)
	value["mvp6"] = mvp6
	value["mvp6_transport_guard"] = {
		"apply_count": _guard6_count,
		"last": _guard6_last.duplicate(true),
		"restore_count": _guard6_restore_count,
		"restore_last": _guard6_restore_last.duplicate(true),
		"active": _guard6_active,
		"restored_after_each_rpc": _guard6_count > 0 and _guard6_restore_count == _guard6_count and not _guard6_active,
		"restored_before_finish": _guard6_count > 0 and _guard6_restore_count == _guard6_count and not _guard6_active,
		"shared_transport_changed": false,
		"payload_limit_changed": false,
		"reconnect_policy_changed": false,
	}
	return value
