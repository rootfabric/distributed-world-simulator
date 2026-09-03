extends RefCounted

## V0 P7.1 product authorization/composition gate for canonical Matter mutation.
##
## This object deliberately owns no canonical or durable world state. MW6 has
## already decoded and validated MatterMutationRequest before calling this
## interface. P7.1 only composes existing product predicates around that request:
## V0 player identity, SM1 one-writer authority, canonical P5 equipment, bounded
## reach, MW8 regional authority, and optional MW9 durable fencing.
##
## Successful authorization returns synchronously to the existing
## MatterAuthoritativeServer, which remains responsible for invoking MW4.

const TOOL_SLOT := "tool/main"
const MINING_TOOL_DEFINITION_ID := "item/tool/mining"
const PLAYER_ENTITY_PREFIX := "player/"
const OPERATION_EXCAVATE := "EXCAVATE"
const EPSILON := 0.000000001

var _configured: bool = false
var _gameplay_player_port = null
var _item_graph_port = null
var _sm1_authority_port = null
var _matter_region_gate = null
var _durable_authority_gate = null
var _durable_context_provider := Callable()
var _position_projector := Callable()
var _authority_id: String = ""
var _authority_epoch: int = 0
var _max_reach_m: float = 0.0


func configure(
	gameplay_player_port,
	item_graph_port,
	sm1_authority_port,
	matter_region_gate,
	authority_id: String,
	authority_epoch: int,
	max_reach_m: float,
	position_projector: Callable,
	durable_authority_gate = null,
	durable_context_provider: Callable = Callable()
) -> Dictionary:
	if _configured:
		return _failure("P7_MATTER_GATE_ALREADY_CONFIGURED")
	if gameplay_player_port == null or not gameplay_player_port.has_method("get_player"):
		return _failure("P7_MATTER_GAMEPLAY_PLAYER_PORT_REQUIRED")
	if item_graph_port == null or not item_graph_port.has_method("get_equipped_item"):
		return _failure("P7_MATTER_ITEM_GRAPH_PORT_REQUIRED")
	if sm1_authority_port == null or not sm1_authority_port.has_method("authorize_write"):
		return _failure("P7_MATTER_SM1_AUTHORITY_PORT_REQUIRED")
	if matter_region_gate == null or not matter_region_gate.has_method("authorize_mutation"):
		return _failure("P7_MATTER_REGIONAL_AUTHORITY_GATE_REQUIRED")
	var normalized_authority_id := authority_id.strip_edges().to_lower()
	if normalized_authority_id.is_empty() or authority_epoch < 1:
		return _failure("P7_MATTER_AUTHORITY_TUPLE_INVALID")
	if not _finite_positive(max_reach_m):
		return _failure("P7_MATTER_MAX_REACH_INVALID")
	if not position_projector.is_valid():
		return _failure("P7_MATTER_POSITION_PROJECTOR_REQUIRED")
	if durable_authority_gate != null:
		if not durable_authority_gate.has_method("authorize"):
			return _failure("P7_MATTER_DURABLE_AUTHORITY_GATE_INVALID")
		if not durable_context_provider.is_valid():
			return _failure("P7_MATTER_DURABLE_CONTEXT_PROVIDER_REQUIRED")
	elif durable_context_provider.is_valid():
		return _failure("P7_MATTER_DURABLE_CONTEXT_PROVIDER_WITHOUT_GATE")

	_gameplay_player_port = gameplay_player_port
	_item_graph_port = item_graph_port
	_sm1_authority_port = sm1_authority_port
	_matter_region_gate = matter_region_gate
	_durable_authority_gate = durable_authority_gate
	_durable_context_provider = durable_context_provider
	_position_projector = position_projector
	_authority_id = normalized_authority_id
	_authority_epoch = authority_epoch
	_max_reach_m = max_reach_m
	_configured = true
	return _success({
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"max_reach_m": _max_reach_m,
		"durable_fence_enabled": _durable_authority_gate != null,
		"canonical_state_owned": false,
		"durable_state_owned": false,
	})


func authorize_product_intent(request: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("P7_MATTER_GATE_NOT_CONFIGURED")
	if String(request.get("operation_type", "")) != OPERATION_EXCAVATE:
		return _failure("P7_MATTER_OPERATION_NOT_SUPPORTED", {
			"operation_type": String(request.get("operation_type", "")),
		})
	if typeof(request.get("shape")) != TYPE_DICTIONARY:
		return _failure("P7_MATTER_REQUEST_SHAPE_REQUIRED")

	var actor_id := String(request.get("actor_id", "")).strip_edges().to_lower()
	if not actor_id.begins_with(PLAYER_ENTITY_PREFIX) or actor_id.length() <= PLAYER_ENTITY_PREFIX.length():
		return _failure("P7_MATTER_ACTOR_ID_INVALID")
	var logical_player_id := actor_id.substr(PLAYER_ENTITY_PREFIX.length())
	if logical_player_id.is_empty():
		return _failure("P7_MATTER_ACTOR_ID_INVALID")

	var player_value = _gameplay_player_port.get_player(logical_player_id)
	if typeof(player_value) != TYPE_DICTIONARY:
		return _failure("P7_MATTER_PLAYER_PORT_INVALID_RESULT")
	var player: Dictionary = player_value
	if player.is_empty():
		return _failure("P7_MATTER_PLAYER_NOT_FOUND", {"logical_player_id": logical_player_id})
	if String(player.get("player_entity_id", "")).strip_edges().to_lower() != actor_id:
		return _failure("P7_MATTER_PLAYER_IDENTITY_MISMATCH", {
			"logical_player_id": logical_player_id,
			"actor_id": actor_id,
		})
	if not bool(player.get("connected", false)):
		return _failure("P7_MATTER_PLAYER_DISCONNECTED", {"logical_player_id": logical_player_id})

	var sm1_value = _sm1_authority_port.authorize_write(_authority_id, _authority_epoch)
	var sm1_check := _owner_result("SM1", sm1_value, "P7_SM1_WRITE_NOT_AUTHORIZED")
	if not bool(sm1_check.get("success", false)):
		return sm1_check

	var equipped_value = _item_graph_port.get_equipped_item(logical_player_id, TOOL_SLOT)
	if typeof(equipped_value) != TYPE_DICTIONARY:
		return _failure("P7_MATTER_ITEM_GRAPH_INVALID_RESULT")
	var equipped: Dictionary = equipped_value
	if equipped.is_empty() \
			or String(equipped.get("definition_id", "")) != MINING_TOOL_DEFINITION_ID \
			or int(equipped.get("quantity", 0)) != 1:
		return _failure("P7_MINING_TOOL_REQUIRED", {"logical_player_id": logical_player_id})
	var equipped_item_id := String(equipped.get("item_id", "")).strip_edges().to_lower()
	var request_tool_id := String(request.get("tool_id", "")).strip_edges().to_lower()
	if equipped_item_id.is_empty() or request_tool_id != equipped_item_id:
		return _failure("P7_MATTER_TOOL_ID_MISMATCH", {
			"equipped_item_id": equipped_item_id,
			"request_tool_id": request_tool_id,
		})

	var projection_value = _position_projector.call(player.duplicate(true), request.duplicate(true))
	if typeof(projection_value) != TYPE_DICTIONARY:
		return _failure("P7_MATTER_POSITION_PROJECTOR_INVALID_RESULT")
	var projection: Dictionary = projection_value
	if not bool(projection.get("success", false)):
		return _owner_result(
			"POSITION_PROJECTOR",
			projection,
			"P7_MATTER_POSITION_PROJECTION_FAILED"
		)
	var player_position_m = projection.get("position_m")
	if not _valid_vector3_array(player_position_m):
		return _failure("P7_MATTER_POSITION_INVALID")
	var reach_result := _validate_reach(Array(player_position_m), Dictionary(request.get("shape", {})))
	if not bool(reach_result.get("success", false)):
		return reach_result

	return _success({
		"result": "P7_MATTER_PRODUCT_INTENT_AUTHORIZED",
		"logical_player_id": logical_player_id,
		"player_entity_id": actor_id,
		"tool_item_id": equipped_item_id,
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"canonical_state_owned": false,
		"durable_state_owned": false,
	})


func authorize_mutation(request: Dictionary) -> Dictionary:
	var intent := authorize_product_intent(request)
	if not bool(intent.get("success", false)):
		return intent
	var identity: Dictionary = intent["details"]

	var regional_value = _matter_region_gate.authorize_mutation(request)
	var regional_check := _owner_result(
		"MW8",
		regional_value,
		"P7_MATTER_REGIONAL_AUTHORITY_NOT_AUTHORIZED"
	)
	if not bool(regional_check.get("success", false)):
		return regional_check
	var regional: Dictionary = regional_value
	var region_id := String(regional.get("details", {}).get("region_id", "")).strip_edges().to_lower()
	if region_id.is_empty():
		return _failure("P7_MATTER_REGION_ID_REQUIRED")

	var durable_fence_verified := false
	if _durable_authority_gate != null:
		var context_value = _durable_context_provider.call(region_id, request.duplicate(true))
		if typeof(context_value) != TYPE_DICTIONARY:
			return _failure("P7_DURABLE_CONTEXT_INVALID")
		var context: Dictionary = context_value
		if not bool(context.get("success", false)):
			return _owner_result("MW9_CONTEXT", context, "P7_DURABLE_CONTEXT_INVALID")
		var owner_id := String(context.get("owner_id", "")).strip_edges().to_lower()
		var durable_epoch := int(context.get("authority_epoch", 0))
		var fencing_token_value = context.get("fencing_token")
		var server_tick_value = context.get("server_tick")
		if owner_id.is_empty() or durable_epoch < 1 \
				or typeof(fencing_token_value) != TYPE_DICTIONARY \
				or typeof(server_tick_value) != TYPE_INT or int(server_tick_value) < 0:
			return _failure("P7_DURABLE_CONTEXT_INVALID")
		if _matter_region_gate.has_method("owner_id") \
				and String(_matter_region_gate.owner_id()).strip_edges().to_lower() != owner_id:
			return _failure("P7_DURABLE_CONTEXT_REGIONAL_MISMATCH")
		if _matter_region_gate.has_method("authority_epoch") \
				and int(_matter_region_gate.authority_epoch()) != durable_epoch:
			return _failure("P7_DURABLE_CONTEXT_REGIONAL_MISMATCH")
		var durable_value = _durable_authority_gate.authorize(
			region_id,
			owner_id,
			durable_epoch,
			Dictionary(fencing_token_value).duplicate(true),
			int(server_tick_value),
			request
		)
		var durable_check := _owner_result(
			"MW9",
			durable_value,
			"P7_MATTER_DURABLE_AUTHORITY_NOT_AUTHORIZED"
		)
		if not bool(durable_check.get("success", false)):
			return durable_check
		durable_fence_verified = true

	return _success({
		"result": "P7_MATTER_MUTATION_AUTHORIZED",
		"logical_player_id": String(identity["logical_player_id"]),
		"player_entity_id": String(identity["player_entity_id"]),
		"tool_item_id": String(identity["tool_item_id"]),
		"region_id": region_id,
		"authority_id": _authority_id,
		"authority_epoch": _authority_epoch,
		"durable_fence_verified": durable_fence_verified,
		"canonical_state_owned": false,
		"durable_state_owned": false,
	})


func contract_report() -> Dictionary:
	return {
		"configured": _configured,
		"interface": "authorize_mutation(request)",
		"product_intent_interface": "authorize_product_intent(request)",
		"canonical_state_owned": false,
		"durable_state_owned": false,
		"replay_ledger_owned": false,
		"matter_contract_owned": false,
		"item_graph_owned": false,
		"authority_owned": false,
		"position_projection_required": true,
		"durable_fence_enabled": _durable_authority_gate != null,
	}


func _validate_reach(player_position_m: Array, shape: Dictionary) -> Dictionary:
	var start_value = shape.get("start_position_m")
	var end_value = shape.get("end_position_m")
	if not _valid_vector3_array(start_value) or not _valid_vector3_array(end_value):
		return _failure("P7_MATTER_SHAPE_INVALID")
	var bound_result := _shape_bound_radius(shape)
	if not bool(bound_result.get("success", false)):
		return bound_result
	var bound_radius := float(bound_result.get("details", {}).get("bound_radius_m", 0.0))
	var start_distance := _distance(Array(player_position_m), Array(start_value))
	var end_distance := _distance(Array(player_position_m), Array(end_value))
	var required_reach := maxf(start_distance, end_distance) + bound_radius
	if required_reach > _max_reach_m + EPSILON:
		return _failure("P7_MATTER_OUT_OF_REACH", {
			"required_reach_m": required_reach,
			"max_reach_m": _max_reach_m,
		})
	return _success({
		"required_reach_m": required_reach,
		"max_reach_m": _max_reach_m,
	})


func _shape_bound_radius(shape: Dictionary) -> Dictionary:
	var kind := String(shape.get("kind", "")).strip_edges().to_upper()
	if kind in ["SPHERE", "CAPSULE"]:
		var radius_value = shape.get("radius_m")
		if not _finite_positive_variant(radius_value):
			return _failure("P7_MATTER_SHAPE_INVALID")
		return _success({"bound_radius_m": float(radius_value)})
	if kind == "BOX":
		var extents_value = shape.get("half_extents_m")
		if not _valid_vector3_array(extents_value):
			return _failure("P7_MATTER_SHAPE_INVALID")
		var extents: Array = extents_value
		for value in extents:
			if float(value) <= 0.0:
				return _failure("P7_MATTER_SHAPE_INVALID")
		return _success({
			"bound_radius_m": sqrt(
				float(extents[0]) * float(extents[0])
				+ float(extents[1]) * float(extents[1])
				+ float(extents[2]) * float(extents[2])
			),
		})
	return _failure("P7_MATTER_SHAPE_INVALID")


func _distance(a: Array, b: Array) -> float:
	var dx := float(a[0]) - float(b[0])
	var dy := float(a[1]) - float(b[1])
	var dz := float(a[2]) - float(b[2])
	return sqrt(dx * dx + dy * dy + dz * dz)


func _valid_vector3_array(value) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != 3:
		return false
	for component in Array(value):
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var number := float(component)
		if is_nan(number) or is_inf(number):
			return false
	return true


func _finite_positive(value: float) -> bool:
	return not is_nan(value) and not is_inf(value) and value > 0.0


func _finite_positive_variant(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return _finite_positive(float(value))


func _owner_result(owner: String, value, fallback_error: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(fallback_error, {"owner": owner, "invalid_result_type": typeof(value)})
	var result: Dictionary = value
	if bool(result.get("success", false)):
		return _success({"owner": owner})
	var error_code := String(result.get("error_code", "")).strip_edges()
	if error_code.is_empty():
		error_code = fallback_error
	return _failure(error_code, {
		"owner": owner,
		"owner_details": Dictionary(result.get("details", {})).duplicate(true) 			if typeof(result.get("details")) == TYPE_DICTIONARY else {},
	})


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
