extends "res://scripts/construction/distributed/construction_authority_server_endpoint.gd"

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ConstructionCommand = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")

# MVP6 composition adapter only. Canonical Construction, sessions, permissions,
# terminal command replay and durable state remain owned by the existing C17/M3
# gateway stack. This object owns only the authenticated session -> actor routing
# binding needed to preserve trusted_context across the C17 server boundary.
var _actors_by_session: Dictionary = {}
var _sessions_by_actor: Dictionary = {}


func bind_authenticated_player(logical_player_id: String, routing_session: Dictionary) -> Dictionary:
	var actor := logical_player_id.strip_edges().to_lower()
	var client_id := String(routing_session.get("client_id", "")).strip_edges()
	var session_id := String(routing_session.get("session_id", "")).strip_edges()
	var session_epoch := int(routing_session.get("session_epoch", 0))
	var ownership_epoch := int(routing_session.get("ownership_epoch", 0))
	if actor.is_empty() or client_id.is_empty() or session_id.is_empty() or session_epoch < 1 or ownership_epoch < 1:
		return ParametricUtils.failure("MVP6_CONSTRUCTION_ACTOR_BINDING_INVALID")
	var next := {
		"logical_player_id": actor,
		"client_id": client_id,
		"session_id": session_id,
		"session_epoch": session_epoch,
		"ownership_epoch": ownership_epoch,
	}
	if _actors_by_session.has(session_id) and Dictionary(_actors_by_session[session_id]) != next:
		return ParametricUtils.failure("MVP6_CONSTRUCTION_SESSION_BINDING_CONFLICT")
	if _sessions_by_actor.has(actor):
		var previous_session := String(_sessions_by_actor[actor])
		if previous_session != session_id:
			_actors_by_session.erase(previous_session)
	_actors_by_session[session_id] = next.duplicate(true)
	_sessions_by_actor[actor] = session_id
	return ParametricUtils.success({"binding": next.duplicate(true)})


func unbind_authenticated_player(logical_player_id: String) -> Dictionary:
	var actor := logical_player_id.strip_edges().to_lower()
	if actor.is_empty() or not _sessions_by_actor.has(actor):
		return ParametricUtils.failure("MVP6_CONSTRUCTION_ACTOR_BINDING_NOT_FOUND")
	var session_id := String(_sessions_by_actor[actor])
	_sessions_by_actor.erase(actor)
	_actors_by_session.erase(session_id)
	return ParametricUtils.success({"logical_player_id": actor, "session_id": session_id})


func submit(command: Dictionary) -> Dictionary:
	var checked: Dictionary = ConstructionCommand.validate(command)
	if not bool(checked.get("success", false)):
		return checked
	var session_id := String(command.get("session_id", ""))
	if not _actors_by_session.has(session_id):
		return ParametricUtils.failure("MVP6_CONSTRUCTION_ACTOR_ROUTE_NOT_BOUND")
	var binding: Dictionary = Dictionary(_actors_by_session[session_id])
	if (
		String(command.get("client_id", "")) != String(binding.get("client_id", ""))
		or int(command.get("session_epoch", 0)) != int(binding.get("session_epoch", 0))
	):
		return ParametricUtils.failure("MVP6_CONSTRUCTION_ACTOR_ROUTE_SESSION_MISMATCH")
	return _gateway.submit(command, "", {
		"logical_player_id": String(binding["logical_player_id"]),
		"ownership_epoch": int(binding["ownership_epoch"]),
	})


func get_authenticated_binding(logical_player_id: String) -> Dictionary:
	var actor := logical_player_id.strip_edges().to_lower()
	var session_id := String(_sessions_by_actor.get(actor, ""))
	return Dictionary(_actors_by_session.get(session_id, {})).duplicate(true)


func get_route_report() -> Dictionary:
	var actors := _sessions_by_actor.keys()
	actors.sort()
	return {
		"schema": "distributed_world_simulator.mvp6_authenticated_construction_authority_endpoint.v1",
		"bound_actor_ids": actors,
		"binding_count": _actors_by_session.size(),
		"canonical_construction_owned": false,
		"session_store_owned": false,
		"permission_store_owned": false,
		"terminal_replay_owned": false,
	}
