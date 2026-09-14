extends RefCounted

# Existing M3 Service's live orchestration port. Only the native registry,
# ownership and Service hooks write canonical data; SM1 remains decision owner.
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Gate = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_live_player_gate.gd")
const Carry = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd")
const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const Shadow = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const SCHEMA := "distributed_world_simulator.mvp3_live_player_export.v1"
const MAX_REPLAY_RECORDS := 1024

var _owner_ref: WeakRef
var _registry = null
var _ownership = null
var _items = null
var _authority := ""
var _backend_epoch := 0
var _peers: Dictionary = {}
var _gates: Dictionary = {}
var _prepared: Dictionary = {}
var _staged: Dictionary = {}
var _retired: Dictionary = {}
var _installing: Dictionary = {}


func configure(owner, registry, ownership, items, authority: String, backend_epoch: int) -> Dictionary:
	if _owner_ref != null or owner == null or registry == null or ownership == null or items == null:
		return _failure("LIVE_TRANSFER_PORT_CONFIGURATION_INVALID")
	_owner_ref = weakref(owner)
	_registry = registry
	_ownership = ownership
	_items = items
	_authority = authority
	_backend_epoch = backend_epoch
	return _success()


func register_peer(authority: String, peer) -> Dictionary:
	# Trusted bootstrap capability, NEVER a client-supplied endpoint or object.
	if peer == null or not peer.has_method("get_prepared_export") or not peer.has_method("get_retirement_receipt") or authority == _authority:
		return _failure("LIVE_TRANSFER_PEER_INVALID")
	if _peers.has(authority):
		return _success({"replay": true}) if _peers[authority].get_ref() == peer else _failure("LIVE_TRANSFER_PEER_REBIND_FORBIDDEN")
	if not _gates.is_empty():
		return _failure("LIVE_TRANSFER_PEERS_ALREADY_FROZEN")
	_peers[authority] = weakref(peer)
	return _success()


func bind_player(logical_id: String, session: String, ownership_epoch: int, coordinator) -> Dictionary:
	if _owner_ref == null or _owner_ref.get_ref() == null or coordinator == null:
		return _failure("LIVE_TRANSFER_OWNER_REQUIRED")
	if _gates.has(logical_id):
		return _failure("LIVE_PLAYER_GATE_REBIND_FORBIDDEN")
	var existing: Dictionary = _registry.get_player(logical_id)
	var binding: Dictionary = _ownership.get_player(logical_id)
	if existing.is_empty() != binding.is_empty():
		return _failure("LIVE_PLAYER_OWNER_ROWS_DIVERGED")
	var decision: Dictionary = coordinator.snapshot()
	var ready_epoch := 0
	if not existing.is_empty():
		if decision.get("state") != "ACTIVE" or decision.get("active_authority_id") != _authority:
			return _failure("LIVE_TARGET_EXISTING_PLAYER_COLLISION")
		ready_epoch = int(decision.get("authority_epoch", 0))
	var gate = Gate.new()
	var configured: Dictionary = gate.configure(coordinator, _authority, logical_id, session, ownership_epoch, ready_epoch)
	if not bool(configured.get("success", false)):
		return configured
	if not existing.is_empty():
		for row in [existing, binding]:
			var identity: Dictionary = gate.validate_record_identity(row)
			if not bool(identity.get("success", false)):
				return identity
	var registry_binding: Dictionary = _registry.bind_live_player_gate(logical_id, gate)
	if not bool(registry_binding.get("success", false)):
		return registry_binding
	var ownership_binding: Dictionary = _ownership.bind_live_player_gate(logical_id, gate)
	if not bool(ownership_binding.get("success", false)):
		return ownership_binding
	_gates[logical_id] = gate
	return _success({"gate": gate.get_report()})


func has_bindings() -> bool:
	return not _gates.is_empty()


func actor_ready(logical_id: String) -> bool:
	return _gates.has(logical_id) and _gates[logical_id].is_locally_ready()


func prepare_export(logical_id: String, transfer_id: String, carrying_manifest: Dictionary) -> Dictionary:
	if not _gates.has(logical_id):
		return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var check: Dictionary = gate.check_transfer_phase(transfer_id, "SOURCE_EXPORT")
	if not bool(check.get("success", false)):
		return check
	var transfer: Dictionary = check["details"]["transfer"]
	var capture: Dictionary = _registry.capture_live_player(logical_id, gate, transfer_id)
	var ownership_capture: Dictionary = _ownership.capture_live_player(logical_id, gate, transfer_id)
	if not bool(capture.get("success", false)):
		return capture
	if not bool(ownership_capture.get("success", false)):
		return ownership_capture
	var player: Dictionary = capture["details"]["player"]
	var binding: Dictionary = ownership_capture["details"]["player"]
	for row in [player, binding]:
		var identity: Dictionary = gate.validate_record_identity(row)
		if not bool(identity.get("success", false)):
			return identity
	var graph: Dictionary = _items.create_snapshot()
	var inventory: Dictionary = graph.get("inventories", {}).get(logical_id, {})
	if not player.get("inventory", []).is_empty() or not inventory.get("inventory", []).is_empty() or not inventory.get("hotbar", []).is_empty():
		return _failure("MVP3_ITEM_CARRY_REQUIRES_MVP4")
	var replay: Dictionary = _owner_ref.get_ref().export_live_player_replay(logical_id)
	if replay.size() > MAX_REPLAY_RECORDS:
		return _failure("LIVE_PLAYER_REPLAY_BUDGET_EXCEEDED")
	var manifest_check := _validate_carry_manifest(logical_id, player, transfer, carrying_manifest, replay)
	if not bool(manifest_check.get("success", false)):
		return manifest_check
	# Hash canonical JSON without a JSON parse/serialize round trip: native
	# actor counter types must not be changed while preparing a frozen packet.
	var packet := {"schema": SCHEMA, "transfer_id": transfer_id, "logical_player_id": logical_id, "source_authority_id": _authority, "target_authority_id": transfer["target_authority_id"], "source_epoch": transfer["source_epoch"], "target_epoch": transfer["target_epoch"], "backend_authority_epoch": _backend_epoch, "player": player, "ownership": binding, "replay": replay, "carrying_manifest": carrying_manifest.duplicate(true), "item_payload_policy": "MVP3_EMPTY_CARRY_ONLY"}
	# Freeze the packet in its exact transport-canonical JSON form before
	# hashing. Godot's full-precision double formatting is not idempotent
	# across a JSON parse for accumulated fixed-tick movement doubles: the
	# first round trip can shorten a value, so a checksum bound to
	# pre-transport natives would reject the byte-identical packet at the
	# target attestation gate. Canonicalizing to a round-trip fixed point
	# binds the checksum to the exact bytes that travel; stale, forged, or
	# divergent values still fail the target attestation comparisons.
	var canonical: Dictionary = packet
	var stable := false
	for _attempt in range(3):
		var round_trip: Dictionary = Utils.json_round_trip(canonical)
		if not bool(round_trip.get("success", false)) or not round_trip.get("value") is Dictionary:
			return _failure("LIVE_PLAYER_EXPORT_CANONICALIZATION_FAILED")
		var candidate: Dictionary = round_trip["value"]
		if Utils.payload_hash(candidate) == Utils.payload_hash(canonical):
			stable = true
			break
		canonical = candidate
	if not stable:
		return _failure("LIVE_PLAYER_EXPORT_CANONICALIZATION_UNSTABLE")
	packet = canonical
	packet["checksum"] = Utils.payload_hash(packet)
	if _prepared.has(logical_id) and _prepared[logical_id].get("transfer_id") == transfer_id:
		if _prepared[logical_id].get("checksum") != packet["checksum"]:
			return _failure("LIVE_PLAYER_FROZEN_EXPORT_CHANGED")
	else:
		_prepared[logical_id] = packet
	return _success({"packet": packet.duplicate(true)})


func get_prepared_export(logical_id: String, transfer_id: String) -> Dictionary:
	if not _gates.has(logical_id) or not bool(_gates[logical_id].check_transfer_phase(transfer_id, "SOURCE_EXPORT").get("success", false)):
		return {}
	var packet: Dictionary = _prepared.get(logical_id, {})
	return packet.duplicate(true) if packet.get("transfer_id") == transfer_id else {}


func stage_export(logical_id: String, packet: Dictionary) -> Dictionary:
	if not _gates.has(logical_id):
		return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var transfer_id := String(packet.get("transfer_id", ""))
	var phase: Dictionary = gate.check_transfer_phase(transfer_id, "TARGET_STAGE")
	if not bool(phase.get("success", false)):
		return phase
	var transfer: Dictionary = phase["details"]["transfer"]
	if packet.get("schema") != SCHEMA or packet.get("logical_player_id") != logical_id or packet.get("target_authority_id") != _authority or packet.get("source_authority_id") != transfer.get("source_authority_id") or packet.get("source_epoch") != transfer.get("source_epoch") or packet.get("target_epoch") != transfer.get("target_epoch") or packet.get("backend_authority_epoch") != _backend_epoch or packet.get("item_payload_policy") != "MVP3_EMPTY_CARRY_ONLY":
		return _failure("LIVE_PLAYER_EXPORT_TUPLE_MISMATCH")
	var source := String(packet["source_authority_id"])
	if not _peers.has(source) or _peers[source].get_ref() == null:
		return _failure("LIVE_TRANSFER_TRUSTED_SOURCE_REQUIRED")
	var attested: Dictionary = _peers[source].get_ref().get_prepared_export(logical_id, transfer_id)
	# A recomputed caller checksum is insufficient. This compares with the
	# frozen native-source receipt through a pre-bound trusted server port.
	if attested.is_empty():
		return _failure("LIVE_PLAYER_SOURCE_ATTESTATION_ABSENT")
	if packet.get("checksum") != _checksum(packet):
		return _failure("LIVE_PLAYER_SOURCE_CHECKSUM_INVALID")
	if Utils.payload_hash(packet) != Utils.payload_hash(attested):
		return _failure("LIVE_PLAYER_SOURCE_PACKET_DIVERGED")
	for field in ["player", "ownership", "replay", "carrying_manifest"]:
		if not packet.get(field) is Dictionary:
			return _failure("LIVE_PLAYER_EXPORT_SECTION_INVALID")
	var player: Dictionary = packet["player"]
	var binding: Dictionary = packet["ownership"]
	for row in [player, binding]:
		var identity: Dictionary = gate.validate_record_identity(row)
		if not bool(identity.get("success", false)):
			return identity
	var validations: Array[Dictionary] = [_registry.validate_live_player_record(player), _ownership.validate_live_binding_record(binding), _owner_ref.get_ref().validate_live_player_replay(logical_id, packet["replay"])]
	for validation in validations:
		if not bool(validation.get("success", false)):
			return validation
	if _staged.has(logical_id) and _staged[logical_id]["packet"].get("checksum") != packet["checksum"]:
		return _failure("LIVE_PLAYER_STAGE_CONFLICT")
	# Incoming JSON numbers are normalized ONLY after validation and source
	# attestation. This preserves canonical integer counters across transport.
	player = Gate.normalize_live_record(player)
	binding = Gate.normalize_live_record(binding)
	var registry_check: Dictionary = _registry.stage_live_player(logical_id, gate, transfer_id, player)
	if not bool(registry_check.get("success", false)):
		return registry_check
	var ownership_check: Dictionary = _ownership.stage_live_player(logical_id, gate, transfer_id, binding)
	if not bool(ownership_check.get("success", false)):
		_registry.discard_live_player_stage(logical_id, gate, transfer_id)
		return ownership_check
	var projection = ProjectionScript.new()
	var projected: Dictionary = projection.configure_from_canonical_sources({"gameplay": {"live_actor_export_checksum": packet["checksum"], "player": player, "ownership": binding}, "item_graph": {"transferred": false}, "construction": {}})
	if not bool(projected.get("success", false)):
		return projected
	var shadow = Shadow.new()
	var shadow_setup: Dictionary = shadow.configure(projection)
	if not bool(shadow_setup.get("success", false)):
		return shadow_setup
	var shadow_report: Dictionary = shadow.get_report()
	_staged[logical_id] = {"packet": packet.duplicate(true), "shadow_report": shadow_report}
	return _success({"stage_checksum": packet["checksum"], "shadow_report": shadow_report.duplicate(true), "canonical_state_owned": false})


func retire_source(logical_id: String, transfer_id: String, token: String) -> Dictionary:
	if not _gates.has(logical_id):
		return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var phase: Dictionary = gate.check_transfer_phase(transfer_id, "SOURCE_RETIRE", token)
	if not bool(phase.get("success", false)):
		return phase
	var packet: Dictionary = _prepared.get(logical_id, {})
	if packet.get("transfer_id") != transfer_id:
		return _failure("LIVE_PLAYER_SOURCE_EXPORT_REQUIRED")
	var previous: Dictionary = _retired.get(logical_id, {})
	if previous.get("transfer_id") == transfer_id:
		return _success({"replay": true, "receipt": previous.duplicate(true)}) if previous.get("commit_token") == token and previous.get("packet_checksum") == packet["checksum"] else _failure("LIVE_PLAYER_RETIRE_REPLAY_CONFLICT")
	var retired: Dictionary = gate.mark_retired(transfer_id, token)
	if not bool(retired.get("success", false)):
		return retired
	_retired[logical_id] = {"transfer_id": transfer_id, "packet_checksum": packet["checksum"], "commit_token": token, "source_authority_id": _authority, "source_locally_fenced": true}
	_owner_ref.get_ref().note_live_player_install()
	return _success({"receipt": _retired[logical_id].duplicate(true)})


func get_retirement_receipt(logical_id: String, transfer_id: String) -> Dictionary:
	var receipt: Dictionary = _retired.get(logical_id, {})
	if receipt.get("transfer_id") != transfer_id or not _gates.has(logical_id) or _gates[logical_id].is_locally_ready():
		return {}
	return receipt.duplicate(true)


func activate_target(logical_id: String, transfer_id: String, token: String) -> Dictionary:
	if not _gates.has(logical_id):
		return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var phase: Dictionary = gate.check_transfer_phase(transfer_id, "TARGET_INSTALL", token)
	if not bool(phase.get("success", false)):
		return phase
	var completed: Dictionary = phase["details"]["transfer"]
	if not _staged.has(logical_id):
		var report: Dictionary = gate.get_report()
		return _success({"replay": true}) if report.get("installed_transfer") == transfer_id and gate.is_locally_ready() else _failure("LIVE_PLAYER_STAGE_REQUIRED")
	var stage: Dictionary = _staged[logical_id]
	var packet: Dictionary = stage["packet"]
	if packet.get("transfer_id") != transfer_id:
		return _failure("LIVE_PLAYER_STAGE_CONFLICT")
	var source := String(packet["source_authority_id"])
	if not _peers.has(source) or _peers[source].get_ref() == null:
		return _failure("LIVE_TRANSFER_TRUSTED_SOURCE_REQUIRED")
	var retired: Dictionary = _peers[source].get_ref().get_retirement_receipt(logical_id, transfer_id)
	if retired.get("commit_token") != token or retired.get("packet_checksum") != packet["checksum"] or retired.get("source_locally_fenced") != true:
		return _failure("LIVE_PLAYER_SOURCE_RETIREMENT_REQUIRED")
	var warm: Dictionary = completed.get("warm_report", {})
	var manifest_checksum := String(packet["carrying_manifest"].get("manifest_checksum", ""))
	var shadow_checksum := String(stage["shadow_report"].get("checksum", ""))
	var composite := Utils.payload_hash({"schema": Carry.WARM_SCHEMA, "transfer_id": transfer_id, "p6_shadow_checksum": shadow_checksum, "carrying_manifest_checksum": manifest_checksum})
	if warm.get("p6_shadow_checksum") != shadow_checksum or warm.get("carrying_manifest_checksum") != manifest_checksum or warm.get("checksum") != composite or completed.get("warm_checksum") != composite:
		return _failure("LIVE_PLAYER_WARM_STAGE_BINDING_MISMATCH")
	var checks: Array[Dictionary] = [_registry.preflight_live_player_install(logical_id, gate, transfer_id, token), _ownership.preflight_live_player_install(logical_id, gate, transfer_id, token), _owner_ref.get_ref().validate_live_player_replay(logical_id, packet["replay"])]
	for check in checks:
		if not bool(check.get("success", false)):
			return check
	# No await/user callback during local install; readiness stays false until
	# registry, ownership and actor replay state have all been installed.
	_installing = {"logical_id": logical_id, "gate": gate, "replay_checksum": Utils.payload_hash(packet["replay"])}
	var replay_result: Dictionary = _owner_ref.get_ref().install_live_player_replay(logical_id, packet["replay"], gate)
	_installing = {}
	if not bool(replay_result.get("success", false)):
		return replay_result
	var installed_registry: Dictionary = _registry.install_live_player(logical_id, gate, transfer_id, token)
	if not bool(installed_registry.get("success", false)):
		return installed_registry
	var installed_ownership: Dictionary = _ownership.install_live_player(logical_id, gate, transfer_id, token)
	if not bool(installed_ownership.get("success", false)):
		return installed_ownership
	var ready: Dictionary = gate.mark_installed(transfer_id, token)
	if not bool(ready.get("success", false)):
		return ready
	_staged.erase(logical_id)
	_owner_ref.get_ref().note_live_player_install()
	return _success({"player": _registry.get_player(logical_id), "ownership": _ownership.get_player(logical_id), "authority_epoch": completed["target_epoch"], "backend_authority_epoch": _backend_epoch})


func replay_install_authorized(logical_id: String, replay: Dictionary, gate) -> bool:
	return not _installing.is_empty() and _installing.get("logical_id") == logical_id and _installing.get("gate") == gate and _gates.get(logical_id) == gate and _installing.get("replay_checksum") == Utils.payload_hash(replay)


func discard_aborted_stage(logical_id: String, transfer_id: String) -> Dictionary:
	if not _gates.has(logical_id):
		return _failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var decision: Dictionary = gate.decision_snapshot()
	var stage: Dictionary = _staged.get(logical_id, {})
	if stage.is_empty():
		return _success({"replay": true})
	var packet: Dictionary = stage["packet"]
	if packet.get("transfer_id") != transfer_id or decision.get("state") != "ACTIVE" or decision.get("active_authority_id") != packet.get("source_authority_id") or decision.get("authority_epoch") != packet.get("source_epoch"):
		return _failure("LIVE_PLAYER_ABORT_NOT_PROVEN")
	_registry.discard_live_player_stage(logical_id, gate, transfer_id)
	_ownership.discard_live_player_stage(logical_id, gate, transfer_id)
	_staged.erase(logical_id)
	return _success()


func _validate_carry_manifest(logical_id: String, player: Dictionary, transfer: Dictionary, manifest: Dictionary, replay: Dictionary) -> Dictionary:
	var unsigned := manifest.duplicate(true)
	unsigned.erase("manifest_checksum")
	if manifest.get("manifest_checksum") != Utils.payload_hash(unsigned) or manifest.get("logical_player_id") != "player/mvp3/" + logical_id or manifest.get("player_entity_id") != "entity/mvp3/" + logical_id or manifest.get("last_input_sequence") != player.get("last_input_sequence") or manifest.get("captured_after_source_freeze") != true:
		return _failure("LIVE_PLAYER_CARRY_MANIFEST_MISMATCH")
	for field in ["transfer_id", "source_authority_id", "target_authority_id", "source_epoch", "target_epoch"]:
		if manifest.get(field) != transfer.get(field):
			return _failure("LIVE_PLAYER_CARRY_TUPLE_MISMATCH")
	var last := String(manifest.get("last_operation_id", ""))
	if last.is_empty() or not replay.has(last) or replay[last].get("result", {}).get("success") != true:
		return _failure("LIVE_PLAYER_CARRY_COMMIT_NOT_PROVEN")
	var closure: Dictionary = manifest.get("closure_view", {})
	var operations = closure.get("carried_operations", [])
	if not operations is Array or not operations.has(last):
		return _failure("LIVE_PLAYER_CARRY_OPERATIONS_INVALID")
	for operation in operations:
		if not replay.has(operation) or replay[operation].get("result", {}).get("success") != true:
			return _failure("LIVE_PLAYER_UNCOMMITTED_CARRY_OPERATION")
	return _success()


func get_report() -> Dictionary:
	var gates: Dictionary = {}
	for logical_id in _gates:
		gates[logical_id] = _gates[logical_id].get_report()
	return {"schema": "distributed_world_simulator.mvp3_live_player_port.v1", "canonical_state_owned": false, "local_authority_id": _authority, "backend_authority_epoch": _backend_epoch, "bindings": gates, "prepared_count": _prepared.size(), "staged_count": _staged.size(), "restart_reconciliation_required": has_bindings(), "item_carry_scope": "MVP3_EMPTY_CARRY_ONLY"}


func shutdown() -> void:
	_owner_ref = null
	_registry = null
	_ownership = null
	_items = null
	_peers.clear()
	_prepared.clear()
	_staged.clear()
	_gates.clear()
	_retired.clear()
	_installing.clear()


static func _checksum(value: Dictionary) -> String:
	var unsigned := value.duplicate(true)
	unsigned.erase("checksum")
	return Utils.payload_hash(unsigned)


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
