extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd"

# P6 is a presentation/projection composition layer over the already validated
# P4 authority protocol. It does not change PREWARM, FAST_COMMIT, redirect,
# activation, recovery, or writer ownership. The local authority publishes its
# canonical player as a read-only peer projection while it owns the directory;
# each side then derives one persistent presentation role for player/a:
# canonical -> handoff_hold -> projection, or the reverse.

const P5ProjectionContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd")
const P6ViewContract = preload("res://scripts/runtime/seamless/sm0/sm0_p6_pivot_view_contract.gd")

const P6_PROJECTION_MESSAGE := "P6_PLAYER_PROJECTION"
const P6_VIEW_MESSAGE := "P6_PROJECTION_PIVOT_VIEW"
const P6_PROJECTION_INTERVAL_MS := 50
const P6_VIEW_INTERVAL_MS := 50

var _p6_view_host := "127.0.0.1"
var _p6_view_port := 0
var _p6_view_socket: PacketPeerUDP
var _p6_remote_projection: Dictionary = {}
var _p6_visual_state: Dictionary = {}
var _p6_visual_role := ""
var _p6_last_stable_role := ""
var _p6_view_sequence := 0
var _p6_last_projection_publish_ms := 0
var _p6_last_view_publish_ms := 0
var _p6_last_projection_checksum := ""
var _p6_last_view_signature := ""
var _p6_pivot_count := 0


func setup(config: Dictionary) -> Dictionary:
	_p6_view_host = String(config.get("view_host", "127.0.0.1")).strip_edges()
	_p6_view_port = int(config.get("view_port", 0))
	if _p6_view_host.is_empty() or _p6_view_port < 1:
		return _failure("SM0_P6_VIEW_CONFIGURATION_INVALID")
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)):
		return result
	if not _p4_enabled:
		return _failure("SM0_P6_REQUIRES_P4_FAST_HANDOFF")
	_p6_view_socket = PacketPeerUDP.new()
	_p6_reconcile_visual_state()
	_event("SM0_P6_READY", {
		"view_port": _p6_view_port,
		"projection_interval_ms": P6_PROJECTION_INTERVAL_MS,
		"view_interval_ms": P6_VIEW_INTERVAL_MS,
		"command_channel": false,
		"p4_protocol_unchanged": true,
	})
	_p6_publish_projection(true)
	_p6_publish_view(true)
	return result


func _process(delta: float) -> void:
	super._process(delta)
	if _p6_view_socket == null:
		return
	var now := Time.get_ticks_msec()
	if now - _p6_last_projection_publish_ms >= P6_PROJECTION_INTERVAL_MS:
		_p6_publish_projection(false)
	_p6_reconcile_visual_state()
	if now - _p6_last_view_publish_ms >= P6_VIEW_INTERVAL_MS:
		_p6_publish_view(false)


func _handle_control_message(message: Dictionary, remote_ip: String, remote_port: int) -> void:
	if String(message.get("type", "")) == P6_PROJECTION_MESSAGE:
		_p6_accept_projection(Dictionary(Dictionary(message.get("payload", {})).get("projection", {})))
		return
	super._handle_control_message(message, remote_ip, remote_port)
	# P4 may have committed or converged the directory while processing this
	# packet. Reconcile only derived P6 presentation state after P4 is finished.
	_p6_reconcile_visual_state()
	_p6_publish_view(false)


func _p6_publish_projection(force_event: bool) -> Dictionary:
	_p6_last_projection_publish_ms = Time.get_ticks_msec()
	if String(_directory.get("owner_authority_id", "")) != _authority_id or _authority == null:
		return _success({"published": false, "reason": "not-owner"})
	var player: Dictionary = _authority.get_player("a")
	if player.is_empty() or not bool(player.get("connected", false)):
		return _success({"published": false, "reason": "no-connected-canonical"})
	var projection := P5ProjectionContract.create_from_player(
		player,
		_authority_id,
		_zone_id,
		int(_directory.get("authority_epoch", 0))
	)
	var validation := P5ProjectionContract.validate(projection)
	if not bool(validation.get("success", false)):
		_invariant("SM0_P6_PROJECTION_CREATE_INVALID", {"cause": validation})
		return validation
	_send_control(P6_PROJECTION_MESSAGE, {"projection": projection}, "p6-projection/%d/%d" % [int(_directory.get("authority_epoch", 0)), int(player.get("state_revision", 0))])
	var checksum := String(projection.get("checksum", ""))
	if force_event or checksum != _p6_last_projection_checksum:
		_p6_last_projection_checksum = checksum
		_event("SM0_P6_PROJECTION_PUBLISHED", {
			"player_entity_id": String(projection.get("player_entity_id", "")),
			"authority_epoch": int(projection.get("authority_epoch", 0)),
			"state_revision": int(projection.get("state_revision", 0)),
			"checksum": checksum,
		})
	return _success({"published": true, "projection": projection})


func _p6_accept_projection(projection: Dictionary) -> Dictionary:
	var validation := P5ProjectionContract.validate(projection)
	if not bool(validation.get("success", false)):
		_event("SM0_P6_PROJECTION_REJECTED", {"error_code": String(validation.get("error_code", "SM0_P6_PROJECTION_INVALID"))})
		return validation
	if String(projection.get("logical_player_id", "")) != "a" or String(projection.get("player_entity_id", "")) != "player/a":
		return _p6_projection_rejected("SM0_P6_PROJECTION_IDENTITY_INVALID", projection)
	if String(projection.get("owner_authority_id", "")) != _peer_authority_id:
		return _p6_projection_rejected("SM0_P6_PROJECTION_UNEXPECTED_OWNER", projection)
	var directory_owner := String(_directory.get("owner_authority_id", ""))
	var directory_epoch := int(_directory.get("authority_epoch", 0))
	if String(projection.get("owner_authority_id", "")) != directory_owner or int(projection.get("authority_epoch", 0)) != directory_epoch:
		_event("SM0_P6_STALE_PROJECTION_IGNORED", {
			"projection_owner": String(projection.get("owner_authority_id", "")),
			"projection_epoch": int(projection.get("authority_epoch", 0)),
			"directory_owner": directory_owner,
			"directory_epoch": directory_epoch,
		})
		return _success({"stale": true})
	if not _p6_remote_projection.is_empty():
		var current_epoch := int(_p6_remote_projection.get("authority_epoch", 0))
		var incoming_epoch := int(projection.get("authority_epoch", 0))
		if incoming_epoch < current_epoch:
			return _success({"stale": true})
		if incoming_epoch == current_epoch:
			var current_revision := int(_p6_remote_projection.get("state_revision", 0))
			var incoming_revision := int(projection.get("state_revision", 0))
			if incoming_revision < current_revision:
				return _success({"stale": true})
			if incoming_revision == current_revision:
				if String(projection.get("checksum", "")) == String(_p6_remote_projection.get("checksum", "")):
					return _success({"replay": true})
				return _p6_projection_rejected("SM0_P6_PROJECTION_SAME_REVISION_MUTATION", projection)
	_p6_remote_projection = projection.duplicate(true)
	_event("SM0_P6_PROJECTION_ACCEPTED", {
		"player_entity_id": String(projection.get("player_entity_id", "")),
		"owner_authority_id": String(projection.get("owner_authority_id", "")),
		"authority_epoch": int(projection.get("authority_epoch", 0)),
		"state_revision": int(projection.get("state_revision", 0)),
	})
	_p6_reconcile_visual_state()
	_p6_publish_view(true)
	return _success({"projection": projection})


func _p6_projection_rejected(error_code: String, projection: Dictionary) -> Dictionary:
	_event("SM0_P6_PROJECTION_REJECTED", {
		"error_code": error_code,
		"player_entity_id": String(projection.get("player_entity_id", "")),
		"owner_authority_id": String(projection.get("owner_authority_id", "")),
	})
	return _failure(error_code)


func _p6_reconcile_visual_state() -> void:
	if _authority == null or _directory.is_empty():
		return
	var directory_owner := String(_directory.get("owner_authority_id", ""))
	var directory_epoch := int(_directory.get("authority_epoch", 0))
	var next_role := ""
	var next_state: Dictionary = {}
	if directory_owner == _authority_id:
		var canonical: Dictionary = _authority.get_player("a")
		if not canonical.is_empty() and bool(canonical.get("connected", false)):
			next_role = P6ViewContract.ROLE_CANONICAL
			next_state = _p6_normalize_canonical(canonical)
	elif (
		not _p6_remote_projection.is_empty()
		and String(_p6_remote_projection.get("owner_authority_id", "")) == directory_owner
		and int(_p6_remote_projection.get("authority_epoch", 0)) == directory_epoch
	):
		next_role = P6ViewContract.ROLE_PROJECTION
		next_state = _p6_normalize_projection(_p6_remote_projection)

	if next_state.is_empty() and not _p6_visual_state.is_empty():
		next_role = P6ViewContract.ROLE_HANDOFF_HOLD
		next_state = _p6_visual_state.duplicate(true)
	if next_state.is_empty():
		return
	if String(next_state.get("logical_player_id", "")) != "a" or String(next_state.get("player_entity_id", "")) != "player/a":
		_invariant("SM0_P6_PIVOT_ENTITY_ID_CHANGED", {"state": next_state})
		return
	if not _p6_visual_state.is_empty() and String(_p6_visual_state.get("player_entity_id", "")) != String(next_state.get("player_entity_id", "")):
		_invariant("SM0_P6_PIVOT_ENTITY_ID_CHANGED", {
			"previous": String(_p6_visual_state.get("player_entity_id", "")),
			"incoming": String(next_state.get("player_entity_id", "")),
		})
		return

	var changed := next_role != _p6_visual_role or _p6_state_signature(next_state) != _p6_state_signature(_p6_visual_state)
	_p6_visual_role = next_role
	_p6_visual_state = next_state.duplicate(true)
	if next_role in [P6ViewContract.ROLE_CANONICAL, P6ViewContract.ROLE_PROJECTION]:
		if not _p6_last_stable_role.is_empty() and _p6_last_stable_role != next_role:
			_p6_pivot_count += 1
			_event("SM0_P6_SERVER_ROLE_PIVOT", {
				"pivot_index": _p6_pivot_count,
				"from_role": _p6_last_stable_role,
				"to_role": next_role,
				"player_entity_id": String(next_state.get("player_entity_id", "")),
				"owner_authority_id": directory_owner,
				"authority_epoch": directory_epoch,
				"writer_count": _writer_count(),
			})
		_p6_last_stable_role = next_role
	elif changed:
		_event("SM0_P6_SERVER_HANDOFF_HOLD", {
			"player_entity_id": String(next_state.get("player_entity_id", "")),
			"owner_authority_id": directory_owner,
			"authority_epoch": directory_epoch,
			"writer_count": _writer_count(),
		})
	if changed:
		_p6_publish_view(true)


func _p6_publish_view(force_event: bool) -> Dictionary:
	_p6_last_view_publish_ms = Time.get_ticks_msec()
	if _p6_view_socket == null or _p6_visual_state.is_empty() or _p6_visual_role.is_empty():
		return _success({"published": false})
	_p6_view_sequence += 1
	var view := P6ViewContract.create(
		_authority_id,
		_zone_id,
		_p6_view_sequence,
		_directory,
		_p6_visual_role,
		_p6_visual_state
	)
	var validation := P6ViewContract.validate(view)
	if not bool(validation.get("success", false)):
		_invariant("SM0_P6_VIEW_INVALID_BEFORE_SEND", {"cause": validation, "role": _p6_visual_role})
		return validation
	if _p6_view_socket.set_dest_address(_p6_view_host, _p6_view_port) != OK:
		return _failure("SM0_P6_VIEW_DESTINATION_FAILED")
	var message := Contracts.create_message(P6_VIEW_MESSAGE, view, "p6-view/%d" % _p6_view_sequence)
	var put_error := _p6_view_socket.put_packet(Contracts.encode_message(message))
	if put_error != OK:
		return _failure("SM0_P6_VIEW_SEND_FAILED", {"error": put_error})
	var signature := "%s|%s|%d|%d" % [
		_p6_visual_role,
		String(_p6_visual_state.get("player_entity_id", "")),
		int(_directory.get("authority_epoch", 0)),
		int(_p6_visual_state.get("state_revision", 0)),
	]
	if force_event or signature != _p6_last_view_signature:
		_p6_last_view_signature = signature
		_event("SM0_P6_VIEW_PUBLISHED", {
			"view_sequence": _p6_view_sequence,
			"presentation_role": _p6_visual_role,
			"player_entity_id": String(_p6_visual_state.get("player_entity_id", "")),
			"owner_authority_id": String(_directory.get("owner_authority_id", "")),
			"authority_epoch": int(_directory.get("authority_epoch", 0)),
			"state_revision": int(_p6_visual_state.get("state_revision", 0)),
			"canonical_writer": _p6_visual_role == P6ViewContract.ROLE_CANONICAL,
			"read_only": _p6_visual_role != P6ViewContract.ROLE_CANONICAL,
			"command_channel": false,
		})
	return _success({"published": true, "view": view})


func p6_status_for_tests() -> Dictionary:
	return {
		"authority_id": _authority_id,
		"directory": _directory.duplicate(true),
		"presentation_role": _p6_visual_role,
		"stable_role": _p6_last_stable_role,
		"visual_state": _p6_visual_state.duplicate(true),
		"remote_projection": _p6_remote_projection.duplicate(true),
		"view_sequence": _p6_view_sequence,
		"pivot_count": _p6_pivot_count,
		"writer_count": _writer_count(),
		"command_channel": false,
	}


func _p6_normalize_canonical(player: Dictionary) -> Dictionary:
	return {
		"logical_player_id": String(player.get("logical_player_id", "")),
		"player_entity_id": String(player.get("player_entity_id", "")),
		"state_revision": int(player.get("state_revision", 0)),
		"last_input_sequence": int(player.get("last_input_sequence", 0)),
		"position": Dictionary(player.get("position", {})).duplicate(true),
		"velocity": Dictionary(player.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(player.get("orientation_yaw", 0.0)),
	}


func _p6_normalize_projection(projection: Dictionary) -> Dictionary:
	return {
		"logical_player_id": String(projection.get("logical_player_id", "")),
		"player_entity_id": String(projection.get("player_entity_id", "")),
		"state_revision": int(projection.get("state_revision", 0)),
		"last_input_sequence": int(projection.get("last_input_sequence", 0)),
		"position": Dictionary(projection.get("position", {})).duplicate(true),
		"velocity": Dictionary(projection.get("velocity", {})).duplicate(true),
		"orientation_yaw": float(projection.get("orientation_yaw", 0.0)),
	}


func _p6_state_signature(state: Dictionary) -> String:
	if state.is_empty():
		return ""
	return JSON.stringify(state, "", false, true).sha256_text()


func _shutdown(exit_code: int, reason: String) -> void:
	if _p6_view_socket != null:
		_p6_view_socket.close()
	super._shutdown(exit_code, reason)