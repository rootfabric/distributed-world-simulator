extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p5.gd"

# The ONE existing M4 owner. Legacy setup/commands remain unchanged unless
# trusted startup explicitly opts in. SM1 gates decide authority; these tables
# stage only this owner's bounded actor closure, never a second inventory.
const LIVE_CARRY_SCHEMA6 := "distributed_world_simulator.native_item_carry.v1"
const MAX_LIVE_ACTORS6 := 64
const MAX_CARRY_ITEMS6 := 128
const MAX_CARRY_REPLAY6 := 1024
const MAX_CARRY_BYTES6 := 524288
var _live_enabled6 := false
var _live_spatial6 := false
var _live_fixture_owner6 := true
var _live_gates6: Dictionary = {}
var _live_ports6: Dictionary = {}
var _live_exports6: Dictionary = {}
var _live_stages6: Dictionary = {}
var _live_retired6: Dictionary = {}
var _live_installed6: Dictionary = {}

func configure_live_items(fixture_owner: bool, spatial_validation: bool = true) -> Dictionary:
	if not _configured or _live_enabled6 or _sandbox_mode or not _inventories.is_empty() or not _ledger.is_empty() or _revision != 0:
		return _failure("LIVE_ITEM_TRUSTED_BOOTSTRAP_REQUIRED")
	_live_enabled6 = true
	_live_spatial6 = spatial_validation
	_live_fixture_owner6 = fixture_owner
	if not fixture_owner:
		_items.clear()
		_containers.clear()
		_mounts.clear()
	else:
		# Same canonical fixture identities, on exactly one region owner. No
		# sandbox inventory/tool seeding is enabled merely to get spatial checks.
		for spec in [["item/shared/beacon/1", Vector3(1.2, 0.4, -3.4)], ["item/shared/ore/1", Vector3(-1.5, 0.35, -2.8)], ["item/shared/crate/1", Vector3(3.0, 0.8, -2.0)]]:
			_items[spec[0]]["transform"] = PlayableStateCodec.create_transform_dto(Transform3D(Basis.IDENTITY, spec[1]))
	return _success()

func bind_live_item_actor(actor: String, gate, trusted_port) -> Dictionary:
	if not _live_enabled6 or actor.is_empty() or actor != actor.strip_edges().to_lower() or gate == null or trusted_port == null:
		return _failure("LIVE_ITEM_BINDING_INVALID")
	if not gate.has_method("check_transfer_phase") or not gate.has_method("is_locally_ready") or not gate.has_method("get_report") or not trusted_port.has_method("attested_item_carry") or not trusted_port.has_method("attested_item_retirement"):
		return _failure("LIVE_ITEM_TRUSTED_PORT_REQUIRED")
	if _live_gates6.has(actor):
		return _success({"replay": true}) if _live_gates6[actor] == gate and _live_ports6[actor].get_ref() == trusted_port else _failure("LIVE_ITEM_REBIND_FORBIDDEN")
	if _live_gates6.size() >= MAX_LIVE_ACTORS6:
		return _failure("LIVE_ITEM_ACTOR_BUDGET")
	_live_gates6[actor] = gate
	_live_ports6[actor] = weakref(trusted_port)
	return _success()

func _live_admission6(actor: String) -> Dictionary:
	if not _live_enabled6:
		return _success()
	if not _live_gates6.has(actor) or not _live_gates6[actor].is_locally_ready():
		return _failure("LIVE_ITEM_AUTHORITY_NOT_READY")
	return _success()

func _live_epoch_admission6(actor: String, epoch: int, kind: String) -> Dictionary:
	var admitted := _live_admission6(actor)
	if not bool(admitted.get("success", false)) or not _live_enabled6: return admitted
	# Player ownership and backend authority are different epochs. Native
	# server output/consume use the latter; client item commands use the former.
	var expected := _authority_epoch
	if kind not in [TRUSTED_SERVER_OUTPUT_COMMAND_TYPE, TRUSTED_CONSTRUCTION_CONSUME_COMMAND_TYPE]:
		expected = int(_live_gates6[actor].get_report().get("ownership_epoch", -1))
	return _success() if epoch == expected else _failure("LIVE_ITEM_OWNERSHIP_EPOCH_INVALID")

func ensure_player(actor: String) -> void:
	if _live_enabled6 and _live_gates6.has(actor) and not _live_gates6[actor].is_locally_ready():
		return
	super.ensure_player(actor)

func lookup_replay(actor: String, epoch: int, operation: String, kind: String, payload: Dictionary) -> Dictionary:
	var admitted := _live_epoch_admission6(actor, epoch, kind)
	if not bool(admitted.get("success", false)):
		return {"found": true, "conflict": false, "result": admitted}
	return super.lookup_replay(actor, epoch, operation, kind, payload)

func execute(actor: String, epoch: int, operation: String, kind: String, payload: Dictionary, context: Dictionary = {}) -> Dictionary:
	var admitted := _live_epoch_admission6(actor, epoch, kind)
	if not bool(admitted.get("success", false)): return admitted
	var existed := _ledger.has(operation)
	var result: Dictionary = super.execute(actor, epoch, operation, kind, payload, context)
	_tag_live_replay6(actor, operation, existed)
	return result

func preflight_server_output(operation: String, actor: String, definition: String, quantity: int, source: String = "") -> Dictionary:
	var admitted := _live_admission6(actor)
	if not bool(admitted.get("success", false)): return admitted
	return super.preflight_server_output(operation, actor, definition, quantity, source)

func apply_server_output(operation: String, actor: String, definition: String, quantity: int, source: String = "") -> Dictionary:
	var admitted := _live_admission6(actor)
	if not bool(admitted.get("success", false)): return admitted
	var key := operation.strip_edges()
	var existed := _ledger.has(key)
	var result: Dictionary = super.apply_server_output(operation, actor, definition, quantity, source)
	_tag_live_replay6(actor, key, existed)
	return result

func preflight_server_construction_consume(operation: String, actor: String, allocations: Array, revision: int, tick: int, checksum: String, plan_checksum: String) -> Dictionary:
	var admitted := _live_admission6(actor)
	if not bool(admitted.get("success", false)): return admitted
	return super.preflight_server_construction_consume(operation, actor, allocations, revision, tick, checksum, plan_checksum)

func apply_server_construction_consume(operation: String, actor: String, allocations: Array, revision: int, tick: int, checksum: String, plan_checksum: String) -> Dictionary:
	var admitted := _live_admission6(actor)
	if not bool(admitted.get("success", false)): return admitted
	var key := operation.strip_edges()
	var existed := _ledger.has(key)
	var result: Dictionary = super.apply_server_construction_consume(operation, actor, allocations, revision, tick, checksum, plan_checksum)
	_tag_live_replay6(actor, key, existed)
	return result

func _tag_live_replay6(actor: String, operation: String, existed: bool) -> void:
	# Only the first native insertion establishes attribution. A conflict or
	# exact replay must never rewrite another actor's pre-existing ledger row.
	if _live_enabled6 and not existed and _ledger.has(operation):
		_ledger[operation]["live_player_id"] = actor

func _live_phase6(actor: String, gate, transfer: String, purpose: String, token: String = "") -> Dictionary:
	if not _live_enabled6 or gate == null or _live_gates6.get(actor) != gate:
		return _failure("LIVE_ITEM_GATE_MISMATCH")
	return gate.check_transfer_phase(transfer, purpose, token)

func _carry_slice6(actor: String) -> Dictionary:
	if not _inventories.has(actor): return _failure("LIVE_ITEM_SOURCE_INVENTORY_MISSING")
	var ids: Dictionary = {}
	for id_value in _inventories[actor].get("inventory", []): ids[String(id_value)] = true
	var containers: Dictionary = {}
	var mounts: Dictionary = {}
	var changed := true
	while changed:
		changed = false
		if ids.size() > MAX_CARRY_ITEMS6: return _failure("LIVE_ITEM_CLOSURE_BUDGET")
		for id_value in _containers:
			var row: Dictionary = _containers[id_value]
			if not ids.has(String(row.get("owner_item_id", ""))): continue
			containers[id_value] = row.duplicate(true)
			for child in row.get("slots", []):
				if not ids.has(String(child)):
					ids[String(child)] = true
					changed = true
		for id_value in _mounts:
			var row: Dictionary = _mounts[id_value]
			if not ids.has(String(row.get("parent_item_id", ""))): continue
			mounts[id_value] = row.duplicate(true)
			var child := String(row.get("item_id", ""))
			if not child.is_empty() and not ids.has(child):
				ids[child] = true
				changed = true
	var items: Dictionary = {}
	for id_value in ids:
		if not _items.has(id_value): return _failure("LIVE_ITEM_CLOSURE_REFERENCE_MISSING")
		items[id_value] = Dictionary(_items[id_value]).duplicate(true)
	for item_value in _items.values():
		var location: Dictionary = item_value.get("location", {})
		if location.get("kind") == "MOUNT" and location.get("owner_player_id") == actor and not ids.has(item_value["item_id"]):
			return _failure("LIVE_ITEM_EXTERNAL_MOUNT_REQUIRES_DETACH")
	for other in _open_containers:
		if other != actor and containers.has(_open_containers[other]):
			return _failure("LIVE_ITEM_CARRIED_CONTAINER_IN_USE")
	var records: Dictionary = {}
	for operation in _ledger:
		var row: Dictionary = _ledger[operation]
		if row.get("live_player_id") != actor: continue
		var copy := row.duplicate(true)
		# Replay receipts remain in the native ledger. Do not transfer unrelated
		# world snapshots captured by historical command responses.
		copy["result"].erase("snapshot")
		if copy["result"].get("details") is Dictionary: copy["result"]["details"].erase("snapshot")
		records[operation] = copy
	if records.size() > MAX_CARRY_REPLAY6: return _failure("LIVE_ITEM_REPLAY_BUDGET")
	return _success({"inventory": Dictionary(_inventories[actor]).duplicate(true), "items": _sorted_values(items), "containers": _sorted_values(containers), "mounts": _sorted_values(mounts), "replay": records})

func prepare_live_item_carry(actor: String, gate, transfer: String) -> Dictionary:
	var phase := _live_phase6(actor, gate, transfer, "SOURCE_EXPORT")
	if not bool(phase.get("success", false)): return phase
	var slice := _carry_slice6(actor)
	if not bool(slice.get("success", false)): return slice
	var tuple: Dictionary = phase["details"]["transfer"]
	var packet := {"schema": LIVE_CARRY_SCHEMA6, "logical_player_id": actor, "transfer_id": transfer, "source_authority_id": _authority_owner_id, "target_authority_id": tuple["target_authority_id"], "source_epoch": tuple["source_epoch"], "target_epoch": tuple["target_epoch"], "backend_authority_epoch": _authority_epoch, "slice": slice["details"]}
	packet = Utils.finalize_json_checksum(packet)
	if packet.is_empty() or Utils.canonical_json(packet).to_utf8_buffer().size() > MAX_CARRY_BYTES6:
		return _failure("LIVE_ITEM_PACKET_BUDGET")
	var checked := _validate_live_packet6(actor, packet)
	if not bool(checked.get("success", false)): return checked
	var previous: Dictionary = _live_exports6.get(actor, {})
	if previous.get("transfer_id") == transfer and previous.get("checksum") != packet["checksum"]:
		return _failure("LIVE_ITEM_FROZEN_EXPORT_CHANGED")
	_live_exports6[actor] = packet.duplicate(true)
	return _success({"packet": packet})

func _validate_live_packet6(actor: String, packet: Dictionary) -> Dictionary:
	if packet.get("schema") != LIVE_CARRY_SCHEMA6 or packet.get("logical_player_id") != actor or packet.get("checksum") != _state_checksum(packet) or not packet.get("slice") is Dictionary:
		return _failure("LIVE_ITEM_PACKET_INVALID")
	if Utils.canonical_json(packet).to_utf8_buffer().size() > MAX_CARRY_BYTES6:
		return _failure("LIVE_ITEM_PACKET_BUDGET")
	var slice: Dictionary = packet["slice"]
	for field in ["items", "containers", "mounts"]:
		if not slice.get(field) is Array: return _failure("LIVE_ITEM_CLOSURE_INVALID")
	if not slice.get("inventory") is Dictionary or not slice.get("replay") is Dictionary or slice["items"].size() > MAX_CARRY_ITEMS6 or slice["replay"].size() > MAX_CARRY_REPLAY6:
		return _failure("LIVE_ITEM_CLOSURE_INVALID")
	var snapshot := {"schema": CURRENT_SNAPSHOT_SCHEMA, "authority_owner_id": packet["source_authority_id"], "authority_epoch": packet["backend_authority_epoch"], "revision": 0, "tick": 0, "items": slice["items"], "inventories": {actor: slice["inventory"]}, "containers": slice["containers"], "mounts": slice["mounts"], "open_containers": {}}
	snapshot = Utils.finalize_json_checksum(snapshot)
	var durable := Utils.finalize_json_checksum({"schema": DURABLE_SCHEMA, "snapshot": snapshot})
	var valid: Dictionary = validate_durable_state(durable)
	if not bool(valid.get("success", false)): return valid
	for item in slice["items"]:
		if item.get("location", {}).get("kind") == "WORLD": return _failure("LIVE_ITEM_FOREIGN_WORLD_CARRY_FORBIDDEN")
	for operation in slice["replay"]:
		var row = slice["replay"][operation]
		if not row is Dictionary or row.get("live_player_id") != actor or not row.get("result") is Dictionary or row["result"].has("snapshot") or String(row.get("fingerprint", "")).length() != 64:
			return _failure("LIVE_ITEM_FOREIGN_REPLAY_FORBIDDEN")
	return _success()

func _target_clear6(actor: String, packet: Dictionary) -> Dictionary:
	var slice: Dictionary = packet["slice"]
	if _inventories.has(actor) and (not _inventories[actor].get("inventory", []).is_empty() or not _inventories[actor].get("hotbar", []).is_empty()):
		return _failure("LIVE_ITEM_TARGET_INVENTORY_COLLISION")
	for row in slice["items"]:
		if _items.has(row["item_id"]): return _failure("LIVE_ITEM_TARGET_ID_COLLISION")
	for row in slice["containers"]:
		if _containers.has(row["container_id"]): return _failure("LIVE_ITEM_TARGET_CONTAINER_COLLISION")
	for row in slice["mounts"]:
		if _mounts.has(row["mount_id"]): return _failure("LIVE_ITEM_TARGET_MOUNT_COLLISION")
	for operation in slice["replay"]:
		if _ledger.has(operation): return _failure("LIVE_ITEM_TARGET_REPLAY_COLLISION")
	return _success()

func stage_live_item_carry(actor: String, gate, packet: Dictionary) -> Dictionary:
	var transfer := String(packet.get("transfer_id", ""))
	var phase := _live_phase6(actor, gate, transfer, "TARGET_STAGE")
	if not bool(phase.get("success", false)): return phase
	var tuple: Dictionary = phase["details"]["transfer"]
	for field in ["source_authority_id", "target_authority_id", "source_epoch", "target_epoch"]:
		if packet.get(field) != tuple.get(field): return _failure("LIVE_ITEM_TRANSFER_TUPLE_MISMATCH")
	if packet.get("target_authority_id") != _authority_owner_id or packet.get("backend_authority_epoch") != _authority_epoch:
		return _failure("LIVE_ITEM_BACKEND_BINDING_INVALID")
	var port = _live_ports6[actor].get_ref()
	if port == null: return _failure("LIVE_ITEM_ATTESTOR_UNAVAILABLE")
	var attested: Dictionary = port.attested_item_carry(actor, transfer, String(packet["source_authority_id"]))
	if attested.is_empty() or Utils.payload_hash(attested) != Utils.payload_hash(packet):
		return _failure("LIVE_ITEM_SOURCE_ATTESTATION_MISMATCH")
	var valid := _validate_live_packet6(actor, packet)
	if not bool(valid.get("success", false)): return valid
	if _live_stages6.has(actor):
		return _success({"replay": true}) if _live_stages6[actor].get("checksum") == packet.get("checksum") else _failure("LIVE_ITEM_STAGE_CONFLICT")
	var clear := _target_clear6(actor, packet)
	if not bool(clear.get("success", false)): return clear
	_live_stages6[actor] = packet.duplicate(true)
	return _success({"item_carry_checksum": packet["checksum"]})

func preflight_live_item_retire(actor: String, gate, transfer: String, token: String) -> Dictionary:
	var phase := _live_phase6(actor, gate, transfer, "SOURCE_RETIRE", token)
	if not bool(phase.get("success", false)): return phase
	var packet: Dictionary = _live_exports6.get(actor, {})
	if packet.get("transfer_id") != transfer: return _failure("LIVE_ITEM_EXPORT_REQUIRED")
	var previous: Dictionary = _live_retired6.get(actor, {})
	if previous.get("transfer_id") == transfer:
		return _success({"replay": true}) if previous.get("commit_token") == token else _failure("LIVE_ITEM_RETIRE_CONFLICT")
	var current := _carry_slice6(actor)
	if not bool(current.get("success", false)): return current
	if Utils.payload_hash(current["details"]) != Utils.payload_hash(packet["slice"]):
		return _failure("LIVE_ITEM_SOURCE_CHANGED_AFTER_FREEZE")
	return _success()

func retire_live_item_carry(actor: String, gate, transfer: String, token: String) -> Dictionary:
	var preflight := preflight_live_item_retire(actor, gate, transfer, token)
	if not bool(preflight.get("success", false)) or preflight.get("details", {}).get("replay") == true: return preflight
	var packet: Dictionary = _live_exports6[actor]
	var slice: Dictionary = packet["slice"]
	for row in slice["items"]: _items.erase(row["item_id"])
	for row in slice["containers"]: _containers.erase(row["container_id"])
	for row in slice["mounts"]: _mounts.erase(row["mount_id"])
	for operation in slice["replay"]: _ledger.erase(operation)
	_inventories.erase(actor)
	_open_containers.erase(actor)
	_live_installed6.erase(actor)
	_live_retired6[actor] = {"transfer_id": transfer, "commit_token": token, "item_carry_checksum": packet["checksum"], "item_retired": true}
	_revision += 1
	_tick += 1
	return _success(_live_retired6[actor])

func preflight_live_item_install(actor: String, gate, transfer: String, token: String) -> Dictionary:
	var phase := _live_phase6(actor, gate, transfer, "TARGET_INSTALL", token)
	if not bool(phase.get("success", false)): return phase
	if not _live_stages6.has(actor):
		return _success({"replay": true}) if _live_installed6.get(actor) == transfer and gate.is_locally_ready() else _failure("LIVE_ITEM_STAGE_REQUIRED")
	var packet: Dictionary = _live_stages6[actor]
	if packet.get("transfer_id") != transfer: return _failure("LIVE_ITEM_STAGE_CONFLICT")
	var port = _live_ports6[actor].get_ref()
	if port == null: return _failure("LIVE_ITEM_ATTESTOR_UNAVAILABLE")
	var retired: Dictionary = port.attested_item_retirement(actor, transfer, String(packet["source_authority_id"]))
	if retired.get("commit_token") != token or retired.get("item_carry_checksum") != packet["checksum"] or retired.get("item_retired") != true or retired.get("source_locally_fenced") != true:
		return _failure("LIVE_ITEM_SOURCE_RETIREMENT_REQUIRED")
	return _target_clear6(actor, packet)

func install_live_item_carry(actor: String, gate, transfer: String, token: String) -> Dictionary:
	var preflight := preflight_live_item_install(actor, gate, transfer, token)
	if not bool(preflight.get("success", false)) or preflight.get("details", {}).get("replay") == true: return preflight
	var normalized: Dictionary = Utils.canonicalize(_live_stages6[actor]["slice"])
	if not bool(normalized.get("success", false)): return _failure("LIVE_ITEM_NATIVE_NORMALIZATION_FAILED")
	var slice: Dictionary = normalized["value"]
	# No callbacks or await during native commit. The shared gate is still
	# unready and is published by the player port only after ALL stores commit.
	_inventories[actor] = Dictionary(slice["inventory"]).duplicate(true)
	for row in slice["items"]: _items[row["item_id"]] = Dictionary(row).duplicate(true)
	for row in slice["containers"]: _containers[row["container_id"]] = Dictionary(row).duplicate(true)
	for row in slice["mounts"]: _mounts[row["mount_id"]] = Dictionary(row).duplicate(true)
	for operation in slice["replay"]: _ledger[operation] = Dictionary(slice["replay"][operation]).duplicate(true)
	_open_containers.erase(actor)
	_live_stages6.erase(actor)
	_live_installed6[actor] = transfer
	_revision += 1
	_tick += 1
	return _success({"item_count": slice["items"].size()})

func discard_live_item_stage(actor: String, gate, transfer: String) -> Dictionary:
	if _live_gates6.get(actor) != gate: return _failure("LIVE_ITEM_GATE_MISMATCH")
	var packet: Dictionary = _live_stages6.get(actor, {})
	if packet.is_empty(): return _success({"replay": true})
	var state: Dictionary = gate.decision_snapshot()
	if packet.get("transfer_id") != transfer or state.get("state") != "ACTIVE" or state.get("active_authority_id") != packet.get("source_authority_id") or state.get("authority_epoch") != packet.get("source_epoch"):
		return _failure("LIVE_ITEM_ABORT_NOT_PROVEN")
	_live_stages6.erase(actor)
	return _success()

func rollback_live_item_stage(actor: String, gate, transfer: String) -> Dictionary:
	# Only before SM1 commit, when a sibling player/ownership stage failed.
	var phase := _live_phase6(actor, gate, transfer, "TARGET_STAGE")
	if not bool(phase.get("success", false)): return phase
	var packet: Dictionary = _live_stages6.get(actor, {})
	if not packet.is_empty() and packet.get("transfer_id") != transfer: return _failure("LIVE_ITEM_STAGE_CONFLICT")
	_live_stages6.erase(actor)
	return _success()

func _execute(actor: String, kind: String, payload: Dictionary, context: Dictionary) -> Dictionary:
	if _live_enabled6:
		# WORLD -> inventory must use the spatially validated pickup entrypoint.
		var item_id := String(payload.get("item_id", ""))
		if kind in ["item.transfer", "item.move_to_inventory", "item.move_to_container"] and _items.get(item_id, {}).get("location", {}).get("kind") == "WORLD":
			return _failure("LIVE_ITEM_WORLD_PICKUP_REQUIRED")
		var container_ids: Array[String] = []
		for field in ["container_id", "target_container_id"]:
			var id_value := String(payload.get(field, ""))
			if id_value.begins_with("container/") and id_value not in container_ids: container_ids.append(id_value)
		var location: Dictionary = _items.get(item_id, {}).get("location", {})
		if location.get("kind") == "CONTAINER": container_ids.append(String(location.get("container_id", "")))
		if _live_spatial6 and kind != "container.close":
			for container_id in container_ids:
				if not _containers.has(container_id): return _failure("CONTAINER_NOT_FOUND")
				var owner_item: Dictionary = _items.get(_containers[container_id].get("owner_item_id", ""), {})
				if owner_item.get("location", {}).get("kind") != "WORLD": return _failure("LIVE_ITEM_CONTAINER_WORLD_BINDING_REQUIRED")
				var spatial := _validate_world_item_interaction(owner_item, context, SANDBOX_INTERACTION_RANGE_M)
				if not bool(spatial.get("success", false)): return spatial
	return super._execute(actor, kind, payload, context)

func _validate_world_item_interaction(item: Dictionary, context: Dictionary, maximum_distance: float) -> Dictionary:
	if not _live_spatial6: return super._validate_world_item_interaction(item, context, maximum_distance)
	var valid := _validate_authority_context(context)
	if not bool(valid.get("success", false)): return valid
	var transform_value = item.get("transform")
	if not transform_value is Dictionary or not bool(PlayableStateCodec.validate_transform_dto(transform_value).get("success", false)):
		return _failure("ITEM_WORLD_TRANSFORM_REQUIRED")
	var target: Vector3 = PlayableStateCodec.transform_from_dto(transform_value).origin
	var origin := _context_vector(context, "interaction_origin")
	var view := _context_vector(context, "view_direction").normalized()
	var offset := target - origin
	if offset.length() > maximum_distance: return _failure("ITEM_INTERACTION_OUT_OF_RANGE")
	if offset.length() > 0.000001:
		var horizontal := Vector3(offset.x, 0.0, offset.z)
		var forward := Vector3(view.x, 0.0, view.z)
		if horizontal.length() > 0.25 and (forward.length_squared() <= 0.000001 or forward.normalized().dot(horizontal.normalized()) < SANDBOX_VISIBILITY_DOT_MIN): return _failure("ITEM_NOT_VISIBLE_TO_PLAYER")
		if target.distance_to(origin + view * clampf(offset.dot(view), 0.0, maximum_distance)) > SANDBOX_TARGET_RAY_TOLERANCE_M: return _failure("ITEM_NOT_VISIBLE_TO_PLAYER")
		if _has_world_item_occluder(String(item.get("item_id", "")), origin, target): return _failure("ITEM_INTERACTION_OCCLUDED")
	return _success({"distance_m": offset.length(), "spatially_validated": true})

func _server_world_transform(context: Dictionary, distance: float, ground_height: float) -> Dictionary:
	if not _live_spatial6: return super._server_world_transform(context, distance, ground_height)
	var valid := _validate_authority_context(context)
	if not bool(valid.get("success", false)): return valid
	var position := _context_vector(context, "player_position")
	var view := _context_vector(context, "view_direction")
	view.y = 0.0
	var yaw := float(context.get("orientation_yaw", 0.0))
	if view.length_squared() <= 0.000001 or not is_finite(yaw) or absf(yaw) > PI: return _failure("INVALID_AUTHORITATIVE_VIEW_DIRECTION")
	var target := position + view.normalized() * distance
	target.y = position.y + ground_height
	return _success({"transform": PlayableStateCodec.create_transform_dto(Transform3D(Basis(Vector3.UP, yaw), target)), "source": "SERVER_AUTHORITY"})

func create_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.create_snapshot()
	if _live_enabled6:
		snapshot["live_item_policy"] = {"version": 1, "spatial_validation": _live_spatial6, "fixture_owner": _live_fixture_owner6}
		snapshot.erase("checksum")
		snapshot["checksum"] = Utils.payload_hash(snapshot)
	return snapshot

func restore_durable_state(value: Dictionary) -> Dictionary:
	if not _live_gates6.is_empty(): return _failure("LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED")
	var valid: Dictionary = validate_durable_state(value)
	if not bool(valid.get("success", false)): return valid
	var policy = value.get("snapshot", {}).get("live_item_policy", {})
	if not policy is Dictionary: return _failure("LIVE_ITEM_DURABLE_POLICY_INVALID")
	if not policy.is_empty() and (policy.get("version") != 1 or typeof(policy.get("spatial_validation")) != TYPE_BOOL or typeof(policy.get("fixture_owner")) != TYPE_BOOL): return _failure("LIVE_ITEM_DURABLE_POLICY_INVALID")
	_live_enabled6 = not policy.is_empty()
	_live_spatial6 = bool(policy.get("spatial_validation", false))
	_live_fixture_owner6 = bool(policy.get("fixture_owner", true))
	return super.restore_durable_state(value)

func restore_replay_state(value: Dictionary) -> Dictionary:
	if not _live_gates6.is_empty(): return _failure("LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED")
	return super.restore_replay_state(value)

func get_live_item_report() -> Dictionary:
	return {"enabled": _live_enabled6, "spatial_validation": _live_spatial6, "fixture_owner": _live_fixture_owner6, "actor_count": _live_gates6.size(), "export_count": _live_exports6.size(), "stage_count": _live_stages6.size(), "retired_count": _live_retired6.size(), "installed_count": _live_installed6.size(), "canonical_owner": "EXISTING_M4_ITEM_GRAPH", "decision_owner": "EXISTING_SM1"}
