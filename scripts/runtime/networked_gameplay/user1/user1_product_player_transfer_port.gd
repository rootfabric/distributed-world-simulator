extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_live_player_transfer_port.gd"

# USER1-SEM1 product specialization of the accepted MVP3 player handoff port.
#
# Only player registry + ownership + player replay move between movement
# authorities. The product's canonical M4 Item Graph / ResourceMining /
# Construction remain on the primary product service and are never copied.
# SM1 remains the sole movement-authority decision owner.

const ProductUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProductGate = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_live_player_gate.gd"
)
const PRODUCT_SCHEMA := "distributed_world_simulator.user1_product_player_export.v1"
const PRODUCT_ITEM_POLICY := "USER1_EXTERNAL_GLOBAL_M4"

# The transport packet is JSON-canonicalized before attestation. Native source
# rows must be retired against the exact frozen native checksums captured
# before that wire canonicalization; otherwise ordinary trig-generated double
# values can compare unequal after a JSON round trip even though the source
# row never changed.
var _source_record_checksums: Dictionary = {}


func configure(
	owner,
	registry,
	ownership,
	_items_unused,
	authority: String,
	backend_epoch: int
) -> Dictionary:
	if (
		_owner_ref != null
		or owner == null
		or registry == null
		or ownership == null
		or authority.strip_edges().is_empty()
		or backend_epoch < 1
	):
		return _product_failure("LIVE_TRANSFER_PORT_CONFIGURATION_INVALID")
	_owner_ref = weakref(owner)
	_registry = registry
	_ownership = ownership
	_items = null
	_authority = authority.strip_edges()
	_backend_epoch = backend_epoch
	return _product_success({
		"movement_only_item_policy": PRODUCT_ITEM_POLICY,
		"item_graph_bound": false,
	})


func bind_player(
	logical_id: String,
	session: String,
	ownership_epoch: int,
	coordinator
) -> Dictionary:
	if _owner_ref == null or _owner_ref.get_ref() == null or coordinator == null:
		return _product_failure("LIVE_TRANSFER_OWNER_REQUIRED")
	if _gates.has(logical_id):
		return _product_failure("LIVE_PLAYER_GATE_REBIND_FORBIDDEN")
	var existing: Dictionary = _registry.get_player(logical_id)
	var binding: Dictionary = _ownership.get_player(logical_id)
	if existing.is_empty() != binding.is_empty():
		return _product_failure("LIVE_PLAYER_OWNER_ROWS_DIVERGED")
	var decision: Dictionary = coordinator.snapshot()
	var ready_epoch := 0
	if not existing.is_empty():
		if (
			String(decision.get("state", "")) != "ACTIVE"
			or String(decision.get("active_authority_id", "")) != _authority
		):
			return _product_failure("LIVE_TARGET_EXISTING_PLAYER_COLLISION")
		ready_epoch = int(decision.get("authority_epoch", 0))
	var gate = ProductGate.new()
	var configured: Dictionary = gate.configure(
		coordinator,
		_authority,
		logical_id,
		session,
		ownership_epoch,
		ready_epoch
	)
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
		_registry.release_live_player_gate(logical_id, gate)
		return ownership_binding
	_gates[logical_id] = gate
	return _product_success({"gate": gate.get_report()})


func prepare_export(
	logical_id: String,
	transfer_id: String,
	carrying_manifest: Dictionary
) -> Dictionary:
	if not _gates.has(logical_id):
		return _product_failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var check: Dictionary = gate.check_transfer_phase(transfer_id, "SOURCE_EXPORT")
	if not bool(check.get("success", false)):
		return check
	var transfer: Dictionary = check["details"]["transfer"]
	var capture: Dictionary = _registry.capture_live_player(logical_id, gate, transfer_id)
	var ownership_capture: Dictionary = _ownership.capture_live_player(
		logical_id,
		gate,
		transfer_id
	)
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
	var source_player_checksum := String(
		capture.get("details", {}).get("player_checksum", "")
	)
	var source_ownership_checksum := String(
		ownership_capture.get("details", {}).get("player_checksum", "")
	)
	if source_player_checksum.is_empty() or source_ownership_checksum.is_empty():
		return _product_failure("LIVE_PLAYER_SOURCE_NATIVE_CHECKSUM_REQUIRED")
	var previous_source: Dictionary = Dictionary(
		_source_record_checksums.get(logical_id, {})
	)
	if (
		not previous_source.is_empty()
		and String(previous_source.get("transfer_id", "")) == transfer_id
		and (
			String(previous_source.get("player_checksum", ""))
				!= source_player_checksum
			or String(previous_source.get("ownership_checksum", ""))
				!= source_ownership_checksum
		)
	):
		return _product_failure("LIVE_PLAYER_FROZEN_NATIVE_SOURCE_CHANGED")

	# Unlike the old MVP3 lab port, product players may already carry canonical
	# M4 inventory. That inventory deliberately stays in the global primary M4
	# owner. Only the movement-owned player row crosses this seam.
	var replay: Dictionary = _owner_ref.get_ref().export_live_player_replay(logical_id)
	if replay.size() > MAX_REPLAY_RECORDS:
		return _product_failure("LIVE_PLAYER_REPLAY_BUDGET_EXCEEDED")
	var manifest_check := _validate_carry_manifest(
		logical_id,
		player,
		transfer,
		carrying_manifest,
		replay
	)
	if not bool(manifest_check.get("success", false)):
		return manifest_check

	var packet := {
		"schema": PRODUCT_SCHEMA,
		"transfer_id": transfer_id,
		"logical_player_id": logical_id,
		"source_authority_id": _authority,
		"target_authority_id": transfer["target_authority_id"],
		"source_epoch": transfer["source_epoch"],
		"target_epoch": transfer["target_epoch"],
		"backend_authority_epoch": _backend_epoch,
		"player": player,
		"ownership": binding,
		"replay": replay,
		"carrying_manifest": carrying_manifest.duplicate(true),
		"item_payload_policy": PRODUCT_ITEM_POLICY,
	}

	var canonical: Dictionary = packet
	var stable := false
	for _attempt in range(4):
		var round_trip: Dictionary = ProductUtils.json_round_trip(canonical)
		if (
			not bool(round_trip.get("success", false))
			or not round_trip.get("value") is Dictionary
		):
			return _product_failure("LIVE_PLAYER_EXPORT_CANONICALIZATION_FAILED")
		var candidate: Dictionary = round_trip["value"]
		if ProductUtils.payload_hash(candidate) == ProductUtils.payload_hash(canonical):
			canonical = candidate
			stable = true
			break
		canonical = candidate
	if not stable:
		return _product_failure("LIVE_PLAYER_EXPORT_CANONICALIZATION_UNSTABLE")
	packet = canonical
	packet["checksum"] = ProductUtils.payload_hash(packet)

	var previous: Dictionary = _prepared.get(logical_id, {})
	if (
		not previous.is_empty()
		and previous.get("transfer_id") == transfer_id
		and previous.get("checksum") != packet["checksum"]
	):
		return _product_failure("LIVE_PLAYER_FROZEN_EXPORT_CHANGED")
	_prepared[logical_id] = packet.duplicate(true)
	_source_record_checksums[logical_id] = {
		"transfer_id": transfer_id,
		"player_checksum": source_player_checksum,
		"ownership_checksum": source_ownership_checksum,
	}
	return _product_success({"packet": packet.duplicate(true)})


func stage_export(logical_id: String, packet: Dictionary) -> Dictionary:
	if not _gates.has(logical_id):
		return _product_failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var transfer_id := String(packet.get("transfer_id", ""))
	var phase: Dictionary = gate.check_transfer_phase(transfer_id, "TARGET_STAGE")
	if not bool(phase.get("success", false)):
		return phase
	var transfer: Dictionary = phase["details"]["transfer"]
	if (
		packet.get("schema") != PRODUCT_SCHEMA
		or packet.get("logical_player_id") != logical_id
		or packet.get("target_authority_id") != _authority
		or packet.get("source_authority_id") != transfer.get("source_authority_id")
		or packet.get("source_epoch") != transfer.get("source_epoch")
		or packet.get("target_epoch") != transfer.get("target_epoch")
		or packet.get("backend_authority_epoch") != _backend_epoch
		or packet.get("item_payload_policy") != PRODUCT_ITEM_POLICY
	):
		return _product_failure("LIVE_PLAYER_EXPORT_TUPLE_MISMATCH")

	var source := String(packet["source_authority_id"])
	if not _peers.has(source) or _peers[source].get_ref() == null:
		return _product_failure("LIVE_TRANSFER_TRUSTED_SOURCE_REQUIRED")
	var attested: Dictionary = _peers[source].get_ref().get_prepared_export(
		logical_id,
		transfer_id
	)
	if attested.is_empty():
		return _product_failure("LIVE_PLAYER_SOURCE_ATTESTATION_ABSENT")
	if packet.get("checksum") != _checksum(packet):
		return _product_failure("LIVE_PLAYER_SOURCE_CHECKSUM_INVALID")
	if ProductUtils.payload_hash(packet) != ProductUtils.payload_hash(attested):
		return _product_failure("LIVE_PLAYER_SOURCE_PACKET_DIVERGED")

	for field in ["player", "ownership", "replay", "carrying_manifest"]:
		if not packet.get(field) is Dictionary:
			return _product_failure("LIVE_PLAYER_EXPORT_SECTION_INVALID")
	var player: Dictionary = packet["player"]
	var binding: Dictionary = packet["ownership"]
	for row in [player, binding]:
		var identity: Dictionary = gate.validate_record_identity(row)
		if not bool(identity.get("success", false)):
			return identity

	var validations: Array[Dictionary] = [
		_registry.validate_live_player_record(player),
		_ownership.validate_live_binding_record(binding),
		_owner_ref.get_ref().validate_live_player_replay(logical_id, packet["replay"]),
	]
	for validation in validations:
		if not bool(validation.get("success", false)):
			return validation
	if (
		_staged.has(logical_id)
		and _staged[logical_id]["packet"].get("checksum") != packet["checksum"]
	):
		return _product_failure("LIVE_PLAYER_STAGE_CONFLICT")

	player = ProductGate.normalize_live_record(player)
	binding = ProductGate.normalize_live_record(binding)
	var registry_check: Dictionary = _registry.stage_live_player(
		logical_id,
		gate,
		transfer_id,
		player
	)
	if not bool(registry_check.get("success", false)):
		return registry_check
	var ownership_check: Dictionary = _ownership.stage_live_player(
		logical_id,
		gate,
		transfer_id,
		binding
	)
	if not bool(ownership_check.get("success", false)):
		_registry.discard_live_player_stage(logical_id, gate, transfer_id)
		return ownership_check

	var projection = ProjectionScript.new()
	var projected: Dictionary = projection.configure_from_canonical_sources({
		"gameplay": {
			"live_actor_export_checksum": packet["checksum"],
			"player": player,
			"ownership": binding,
		},
		"item_graph": {
			"transferred": false,
			"owner": "PRIMARY_PRODUCT_M4",
		},
		"construction": {
			"transferred": false,
			"owner": "PRIMARY_PRODUCT_CONSTRUCTION",
		},
	})
	if not bool(projected.get("success", false)):
		_registry.discard_live_player_stage(logical_id, gate, transfer_id)
		_ownership.discard_live_player_stage(logical_id, gate, transfer_id)
		return projected
	var shadow = Shadow.new()
	var shadow_setup: Dictionary = shadow.configure(projection)
	if not bool(shadow_setup.get("success", false)):
		_registry.discard_live_player_stage(logical_id, gate, transfer_id)
		_ownership.discard_live_player_stage(logical_id, gate, transfer_id)
		return shadow_setup
	var shadow_report: Dictionary = shadow.get_report()
	_staged[logical_id] = {
		"packet": packet.duplicate(true),
		"shadow_report": shadow_report,
	}
	return _product_success({
		"stage_checksum": packet["checksum"],
		"shadow_report": shadow_report.duplicate(true),
		"canonical_state_owned": false,
		"item_graph_transferred": false,
	})


func retire_source(
	logical_id: String,
	transfer_id: String,
	token: String
) -> Dictionary:
	if not _gates.has(logical_id):
		return _product_failure("LIVE_PLAYER_GATE_REQUIRED")
	var gate = _gates[logical_id]
	var phase: Dictionary = gate.check_transfer_phase(
		transfer_id,
		"SOURCE_RETIRE",
		token
	)
	if not bool(phase.get("success", false)):
		return phase
	var packet: Dictionary = _prepared.get(logical_id, {})
	if packet.get("transfer_id") != transfer_id:
		return _product_failure("LIVE_PLAYER_SOURCE_EXPORT_REQUIRED")
	var previous: Dictionary = _retired.get(logical_id, {})
	if previous.get("transfer_id") == transfer_id:
		if (
			previous.get("commit_token") == token
			and previous.get("packet_checksum") == packet["checksum"]
		):
			return _product_success({
				"replay": true,
				"receipt": previous.duplicate(true),
			})
		return _product_failure("LIVE_PLAYER_RETIRE_REPLAY_CONFLICT")

	var source_checksums: Dictionary = Dictionary(
		_source_record_checksums.get(logical_id, {})
	)
	if String(source_checksums.get("transfer_id", "")) != transfer_id:
		return _product_failure("LIVE_PLAYER_SOURCE_NATIVE_CHECKSUM_REQUIRED")
	var player_checksum := String(source_checksums.get("player_checksum", ""))
	var ownership_checksum := String(
		source_checksums.get("ownership_checksum", "")
	)
	if player_checksum.is_empty() or ownership_checksum.is_empty():
		return _product_failure("LIVE_PLAYER_SOURCE_NATIVE_CHECKSUM_REQUIRED")
	var registry_preflight: Dictionary = _registry.preflight_live_player_retire(
		logical_id,
		gate,
		transfer_id,
		token,
		player_checksum
	)
	if not bool(registry_preflight.get("success", false)):
		return registry_preflight
	var ownership_preflight: Dictionary = _ownership.preflight_live_player_retire(
		logical_id,
		gate,
		transfer_id,
		token,
		ownership_checksum
	)
	if not bool(ownership_preflight.get("success", false)):
		return ownership_preflight

	# No callback/await between the two owner-native row retirements and the
	# gate transition. The SM1 coordinator is already OWNERSHIP_COMMITTED, so
	# both source rows are fenced throughout this local critical section.
	var registry_retired: Dictionary = _registry.retire_live_player_source(
		logical_id,
		gate,
		transfer_id,
		token,
		player_checksum
	)
	if not bool(registry_retired.get("success", false)):
		return registry_retired
	var ownership_retired: Dictionary = _ownership.retire_live_player_source(
		logical_id,
		gate,
		transfer_id,
		token,
		ownership_checksum
	)
	if not bool(ownership_retired.get("success", false)):
		return ownership_retired
	var retired: Dictionary = gate.mark_retired(transfer_id, token)
	if not bool(retired.get("success", false)):
		return retired

	_retired[logical_id] = {
		"transfer_id": transfer_id,
		"packet_checksum": packet["checksum"],
		"commit_token": token,
		"source_authority_id": _authority,
		"source_locally_fenced": true,
		"player_row_retired": true,
		"item_graph_transferred": false,
	}
	_owner_ref.get_ref().note_live_player_install()
	return _product_success({"receipt": _retired[logical_id].duplicate(true)})


func release_binding(logical_id: String) -> Dictionary:
	if not _gates.has(logical_id):
		return _product_success({"replay": true})
	var gate = _gates[logical_id]
	var decision: Dictionary = gate.decision_snapshot()
	if String(decision.get("state", "")) != "ACTIVE":
		return _product_failure("LIVE_PLAYER_RELEASE_REQUIRES_ACTIVE_DECISION")
	if _staged.has(logical_id) or _installing.get("logical_id", "") == logical_id:
		return _product_failure("LIVE_PLAYER_RELEASE_IN_FLIGHT")

	var registry_preflight: Dictionary = _registry.preflight_live_player_gate_release(
		logical_id,
		gate
	)
	if not bool(registry_preflight.get("success", false)):
		return registry_preflight
	var ownership_preflight: Dictionary = _ownership.preflight_live_player_gate_release(
		logical_id,
		gate
	)
	if not bool(ownership_preflight.get("success", false)):
		return ownership_preflight

	var registry_release: Dictionary = _registry.release_live_player_gate(
		logical_id,
		gate
	)
	if not bool(registry_release.get("success", false)):
		return registry_release
	var ownership_release: Dictionary = _ownership.release_live_player_gate(
		logical_id,
		gate
	)
	if not bool(ownership_release.get("success", false)):
		return ownership_release

	_gates.erase(logical_id)
	_prepared.erase(logical_id)
	_source_record_checksums.erase(logical_id)
	_staged.erase(logical_id)
	_retired.erase(logical_id)
	_installing.erase(logical_id)
	return _product_success({
		"released": true,
		"local_row_retained": bool(
			registry_release.get("details", {}).get("local_row_retained", false)
		),
	})


func binding_count() -> int:
	return _gates.size()


func shutdown() -> void:
	_source_record_checksums.clear()
	super.shutdown()


func _validate_carry_manifest(
	logical_id: String,
	player: Dictionary,
	transfer: Dictionary,
	manifest: Dictionary,
	replay: Dictionary
) -> Dictionary:
	var unsigned := manifest.duplicate(true)
	unsigned.erase("manifest_checksum")
	if (
		manifest.get("manifest_checksum") != ProductUtils.payload_hash(unsigned)
		or manifest.get("logical_player_id") != logical_id
		or manifest.get("player_entity_id") != "player/%s" % logical_id
		or manifest.get("last_input_sequence") != player.get("last_input_sequence")
		or manifest.get("captured_after_source_freeze") != true
	):
		return _product_failure("LIVE_PLAYER_CARRY_MANIFEST_MISMATCH")
	for field in [
		"transfer_id",
		"source_authority_id",
		"target_authority_id",
		"source_epoch",
		"target_epoch",
	]:
		if manifest.get(field) != transfer.get(field):
			return _product_failure("LIVE_PLAYER_CARRY_TUPLE_MISMATCH")
	var last := String(manifest.get("last_operation_id", ""))
	if (
		last.is_empty()
		or not replay.has(last)
		or replay[last].get("result", {}).get("success") != true
	):
		return _product_failure("LIVE_PLAYER_CARRY_COMMIT_NOT_PROVEN")
	var closure: Dictionary = Dictionary(manifest.get("closure_view", {}))
	var operations = closure.get("carried_operations", [])
	if not operations is Array or not operations.has(last):
		return _product_failure("LIVE_PLAYER_CARRY_OPERATIONS_INVALID")
	for operation in operations:
		if (
			not replay.has(operation)
			or replay[operation].get("result", {}).get("success") != true
		):
			return _product_failure("LIVE_PLAYER_UNCOMMITTED_CARRY_OPERATION")
	return _product_success()


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["schema"] = "distributed_world_simulator.user1_product_player_port.v1"
	report["item_carry_scope"] = PRODUCT_ITEM_POLICY
	report["item_graph_owner"] = "PRIMARY_PRODUCT_M4"
	report["resource_owner"] = "PRIMARY_PRODUCT_RESOURCE_MINING"
	report["construction_owner"] = "PRIMARY_PRODUCT_CONSTRUCTION"
	report["binding_count"] = _gates.size()
	report["native_source_checksum_count"] = _source_record_checksums.size()
	return report


static func _product_success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _product_failure(
	error_code: String,
	details: Dictionary = {}
) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}
