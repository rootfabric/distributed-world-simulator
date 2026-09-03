extends SceneTree

const GateScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd"
)

const PRODUCT_AUTHORITY := "authority/product/a"
const PRODUCT_EPOCH := 7
const MATTER_OWNER := "authority/matter/a"
const MATTER_EPOCH := 3
const REGION_ID := "region/matter/p7/a"
const TOOL_ID := "item/tool/p7/drill-1"

var _assertions := 0
var _failures := 0
var _projection_fail := false
var _durable_context_fail := false
var _durable_context_mismatch := false


class GameplayPort:
	extends RefCounted
	var player: Dictionary = {}

	func get_player(logical_player_id: String) -> Dictionary:
		if String(player.get("logical_player_id", "")) != logical_player_id:
			return {}
		return player.duplicate(true)


class ItemGraphPort:
	extends RefCounted
	var equipped: Dictionary = {}

	func get_equipped_item(logical_player_id: String, slot_id: String) -> Dictionary:
		if logical_player_id != "b" or slot_id != "tool/main":
			return {}
		return equipped.duplicate(true)


class SM1Port:
	extends RefCounted
	var result: Dictionary = {"success": true, "error_code": "", "details": {}}
	var calls := 0
	var last_authority_id := ""
	var last_authority_epoch := 0

	func authorize_write(authority_id: String, authority_epoch: int) -> Dictionary:
		calls += 1
		last_authority_id = authority_id
		last_authority_epoch = authority_epoch
		return result.duplicate(true)


class RegionalGate:
	extends RefCounted
	var result: Dictionary = {
		"success": true,
		"error_code": "",
		"details": {"region_id": REGION_ID},
	}
	var calls := 0

	func authorize_mutation(_request: Dictionary) -> Dictionary:
		calls += 1
		return result.duplicate(true)

	func owner_id() -> String:
		return MATTER_OWNER

	func authority_epoch() -> int:
		return MATTER_EPOCH


class DurableGate:
	extends RefCounted
	var result: Dictionary = {
		"success": true,
		"error_code": "",
		"details": {"durable_fence_verified": true},
	}
	var calls := 0
	var last_region_id := ""
	var last_owner_id := ""
	var last_epoch := 0
	var last_tick := -1

	func authorize(
		region_id: String,
		owner_id: String,
		authority_epoch: int,
		_fencing_token: Dictionary,
		server_tick: int,
		_request: Dictionary = {}
	) -> Dictionary:
		calls += 1
		last_region_id = region_id
		last_owner_id = owner_id
		last_epoch = authority_epoch
		last_tick = server_tick
		return result.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_configuration_is_fail_closed()
	_test_happy_path_and_zero_ownership()
	_test_identity_fences()
	_test_sm1_and_tool_fences()
	_test_spatial_fences()
	_test_regional_and_durable_fences()
	print("V0-P7.1 authority gate: PASS (%d assertions, %d failures)" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _test_configuration_is_fail_closed() -> void:
	var gate = GateScript.new()
	_assert_error(gate.authorize_mutation(_request()), "P7_MATTER_GATE_NOT_CONFIGURED", "unconfigured gate")

	var fx := _ports()
	var invalid_reach = GateScript.new()
	_assert_error(
		invalid_reach.configure(
			fx.gameplay, fx.graph, fx.sm1, fx.regional,
			PRODUCT_AUTHORITY, PRODUCT_EPOCH, 0.0,
			Callable(self, "_project_position")
		),
		"P7_MATTER_MAX_REACH_INVALID",
		"zero reach"
	)

	var provider_without_gate = GateScript.new()
	_assert_error(
		provider_without_gate.configure(
			fx.gameplay, fx.graph, fx.sm1, fx.regional,
			PRODUCT_AUTHORITY, PRODUCT_EPOCH, 4.0,
			Callable(self, "_project_position"),
			null,
			Callable(self, "_durable_context")
		),
		"P7_MATTER_DURABLE_CONTEXT_PROVIDER_WITHOUT_GATE",
		"durable provider without MW9 gate"
	)


func _test_happy_path_and_zero_ownership() -> void:
	var intent_fx := _fixture()
	var intent: Dictionary = intent_fx.gate.authorize_product_intent(_request())
	_assert_success(intent, "product intent happy path")
	_assert_true(String(intent.details.get("logical_player_id", "")) == "b", "product intent retains logical player")
	_assert_true(intent_fx.regional.calls == 0, "product intent does not claim MW8 regional authorization")
	_assert_true(intent_fx.durable.calls == 0, "product intent does not claim MW9 durable authorization")

	var fx := _fixture()
	var result: Dictionary = fx.gate.authorize_mutation(_request())
	_assert_success(result, "happy path")
	_assert_true(String(result.details.get("logical_player_id", "")) == "b", "logical identity is derived from player_entity_id")
	_assert_true(String(result.details.get("player_entity_id", "")) == "player/b", "Matter actor identity is retained")
	_assert_true(String(result.details.get("tool_item_id", "")) == TOOL_ID, "exact equipped item identity is retained")
	_assert_true(String(result.details.get("region_id", "")) == REGION_ID, "MW8 region result is retained")
	_assert_true(not bool(result.details.get("durable_fence_verified", true)), "MW9 flag is false when durable gate is absent")
	_assert_true(fx.sm1.calls == 1, "SM1 authorize_write called exactly once")
	_assert_true(fx.sm1.last_authority_id == PRODUCT_AUTHORITY and fx.sm1.last_authority_epoch == PRODUCT_EPOCH, "exact SM1 tuple is checked")
	_assert_true(fx.regional.calls == 1, "MW8 gate called exactly once")

	var report: Dictionary = fx.gate.contract_report()
	for field in [
		"canonical_state_owned",
		"durable_state_owned",
		"replay_ledger_owned",
		"matter_contract_owned",
		"item_graph_owned",
		"authority_owned",
	]:
		_assert_true(not bool(report.get(field, true)), "P7 gate owns no %s" % field)


func _test_identity_fences() -> void:
	var fx := _fixture()
	var malformed := _request()
	malformed.actor_id = "b"
	_assert_error(fx.gate.authorize_mutation(malformed), "P7_MATTER_ACTOR_ID_INVALID", "raw logical id is not a Matter actor id")

	var missing := _request()
	missing.actor_id = "player/c"
	_assert_error(fx.gate.authorize_mutation(missing), "P7_MATTER_PLAYER_NOT_FOUND", "unknown canonical actor")

	var mismatch_fx := _fixture()
	mismatch_fx.gameplay.player.player_entity_id = "player/c"
	_assert_error(
		mismatch_fx.gate.authorize_mutation(_request()),
		"P7_MATTER_PLAYER_IDENTITY_MISMATCH",
		"player_entity round trip mismatch"
	)

	var disconnected_fx := _fixture()
	disconnected_fx.gameplay.player.connected = false
	_assert_error(
		disconnected_fx.gate.authorize_mutation(_request()),
		"P7_MATTER_PLAYER_DISCONNECTED",
		"disconnected gameplay identity"
	)


func _test_sm1_and_tool_fences() -> void:
	var sm1_fx := _fixture()
	sm1_fx.sm1.result = {
		"success": false,
		"error_code": "SM1_AUTHORITY_TRANSFER_WRITE_FENCED",
		"details": {"state": "SOURCE_FROZEN"},
	}
	_assert_error(
		sm1_fx.gate.authorize_mutation(_request()),
		"SM1_AUTHORITY_TRANSFER_WRITE_FENCED",
		"SM1 transfer gap"
	)
	_assert_true(sm1_fx.regional.calls == 0, "MW8 is not consulted after SM1 rejection")

	var missing_tool := _fixture()
	missing_tool.graph.equipped = {}
	_assert_error(
		missing_tool.gate.authorize_mutation(_request()),
		"P7_MINING_TOOL_REQUIRED",
		"missing equipped mining tool"
	)

	var wrong_definition := _fixture()
	wrong_definition.graph.equipped.definition_id = "item/tool/repair"
	_assert_error(
		wrong_definition.gate.authorize_mutation(_request()),
		"P7_MINING_TOOL_REQUIRED",
		"wrong equipped tool definition"
	)

	var wrong_quantity := _fixture()
	wrong_quantity.graph.equipped.quantity = 2
	_assert_error(
		wrong_quantity.gate.authorize_mutation(_request()),
		"P7_MINING_TOOL_REQUIRED",
		"non-unit equipment relation"
	)

	var forged_tool := _fixture()
	var request := _request()
	request.tool_id = "item/tool/p7/forged"
	_assert_error(
		forged_tool.gate.authorize_mutation(request),
		"P7_MATTER_TOOL_ID_MISMATCH",
		"forged request tool identity"
	)

	var unsupported := _fixture()
	var deposit := _request()
	deposit.operation_type = "DEPOSIT"
	_assert_error(
		unsupported.gate.authorize_mutation(deposit),
		"P7_MATTER_OPERATION_NOT_SUPPORTED",
		"P7.1 mining tool cannot authorize deposit"
	)


func _test_spatial_fences() -> void:
	_projection_fail = true
	var projector_failure := _fixture()
	_assert_error(
		projector_failure.gate.authorize_mutation(_request()),
		"P7_TEST_POSITION_PROJECTION_BLOCKED",
		"position projector failure is propagated"
	)
	_projection_fail = false

	var far_fx := _fixture(4.0)
	var far := _request()
	far.shape.start_position_m = [10.0, 0.0, 0.0]
	far.shape.end_position_m = [11.0, 0.0, 0.0]
	_assert_error(
		far_fx.gate.authorize_mutation(far),
		"P7_MATTER_OUT_OF_REACH",
		"far swept shape"
	)

	var huge := _fixture(4.0)
	var huge_shape := _request()
	huge_shape.shape.kind = "SPHERE"
	huge_shape.shape.start_position_m = [0.0, 0.0, 0.0]
	huge_shape.shape.end_position_m = [0.0, 0.0, 0.0]
	huge_shape.shape.radius_m = 5.0
	_assert_error(
		huge.gate.authorize_mutation(huge_shape),
		"P7_MATTER_OUT_OF_REACH",
		"shape radius participates in reach bound"
	)

	var malformed := _fixture()
	var invalid_shape := _request()
	invalid_shape.shape.kind = "CYLINDER"
	_assert_error(
		malformed.gate.authorize_mutation(invalid_shape),
		"P7_MATTER_SHAPE_INVALID",
		"unknown Matter shape kind"
	)


func _test_regional_and_durable_fences() -> void:
	var regional_fx := _fixture()
	regional_fx.regional.result = {
		"success": false,
		"error_code": "MATTER_REGION_NOT_OWNED_BY_SERVER",
		"details": {},
	}
	_assert_error(
		regional_fx.gate.authorize_mutation(_request()),
		"MATTER_REGION_NOT_OWNED_BY_SERVER",
		"MW8 rejection is preserved"
	)

	var durable_fx := _fixture(4.0, true)
	var durable_result: Dictionary = durable_fx.gate.authorize_mutation(_request())
	_assert_success(durable_result, "MW9 durable happy path")
	_assert_true(bool(durable_result.details.get("durable_fence_verified", false)), "MW9 durable fence marked")
	_assert_true(durable_fx.durable.calls == 1, "MW9 gate called exactly once")
	_assert_true(durable_fx.durable.last_region_id == REGION_ID, "MW9 uses MW8 region")
	_assert_true(durable_fx.durable.last_owner_id == MATTER_OWNER and durable_fx.durable.last_epoch == MATTER_EPOCH, "MW9 context matches MW8 owner tuple")
	_assert_true(durable_fx.durable.last_tick == 42, "MW9 context uses server-side tick")

	_durable_context_mismatch = true
	var mismatch := _fixture(4.0, true)
	_assert_error(
		mismatch.gate.authorize_mutation(_request()),
		"P7_DURABLE_CONTEXT_REGIONAL_MISMATCH",
		"MW9 context cannot disagree with MW8"
	)
	_durable_context_mismatch = false

	_durable_context_fail = true
	var context_fail := _fixture(4.0, true)
	_assert_error(
		context_fail.gate.authorize_mutation(_request()),
		"P7_TEST_DURABLE_CONTEXT_BLOCKED",
		"durable context provider failure"
	)
	_durable_context_fail = false

	var durable_reject := _fixture(4.0, true)
	durable_reject.durable.result = {
		"success": false,
		"error_code": "MATTER_DURABLE_FENCING_TOKEN_STALE",
		"details": {},
	}
	_assert_error(
		durable_reject.gate.authorize_mutation(_request()),
		"MATTER_DURABLE_FENCING_TOKEN_STALE",
		"MW9 rejection is preserved"
	)


func _ports() -> Dictionary:
	var gameplay := GameplayPort.new()
	gameplay.player = {
		"logical_player_id": "b",
		"player_entity_id": "player/b",
		"connected": true,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
	}
	var graph := ItemGraphPort.new()
	graph.equipped = {
		"item_id": TOOL_ID,
		"definition_id": "item/tool/mining",
		"quantity": 1,
		"equipment": {"player_id": "b", "slot_id": "tool/main"},
	}
	return {
		"gameplay": gameplay,
		"graph": graph,
		"sm1": SM1Port.new(),
		"regional": RegionalGate.new(),
		"durable": DurableGate.new(),
	}


func _fixture(max_reach_m: float = 4.0, durable_enabled: bool = false) -> Dictionary:
	var fx := _ports()
	var gate = GateScript.new()
	var configured: Dictionary
	if durable_enabled:
		configured = gate.configure(
			fx.gameplay,
			fx.graph,
			fx.sm1,
			fx.regional,
			PRODUCT_AUTHORITY,
			PRODUCT_EPOCH,
			max_reach_m,
			Callable(self, "_project_position"),
			fx.durable,
			Callable(self, "_durable_context")
		)
	else:
		configured = gate.configure(
			fx.gameplay,
			fx.graph,
			fx.sm1,
			fx.regional,
			PRODUCT_AUTHORITY,
			PRODUCT_EPOCH,
			max_reach_m,
			Callable(self, "_project_position")
		)
	_assert_success(configured, "fixture configure")
	fx["gate"] = gate
	return fx


func _project_position(player: Dictionary, _request_value: Dictionary) -> Dictionary:
	if _projection_fail:
		return {
			"success": false,
			"error_code": "P7_TEST_POSITION_PROJECTION_BLOCKED",
			"details": {},
		}
	var position: Dictionary = player.get("position", {})
	return {
		"success": true,
		"error_code": "",
		"position_m": [
			float(position.get("x", 0.0)),
			float(position.get("y", 0.0)),
			float(position.get("z", 0.0)),
		],
	}


func _durable_context(_region_id: String, _request_value: Dictionary) -> Dictionary:
	if _durable_context_fail:
		return {
			"success": false,
			"error_code": "P7_TEST_DURABLE_CONTEXT_BLOCKED",
			"details": {},
		}
	return {
		"success": true,
		"error_code": "",
		"owner_id": "authority/matter/other" if _durable_context_mismatch else MATTER_OWNER,
		"authority_epoch": MATTER_EPOCH,
		"fencing_token": {"token_id": "fence/p7/test"},
		"server_tick": 42,
	}


func _request() -> Dictionary:
	return {
		"operation_type": "EXCAVATE",
		"actor_id": "player/b",
		"tool_id": TOOL_ID,
		"shape": {
			"kind": "CAPSULE",
			"start_position_m": [1.0, 0.0, 0.0],
			"end_position_m": [2.0, 0.0, 0.0],
			"radius_m": 0.5,
			"half_extents_m": [0.0, 0.0, 0.0],
		},
	}


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert_true(not bool(result.get("success", false)), "%s rejects" % message)
	_assert_true(
		String(result.get("error_code", "")) == error_code,
		"%s error expected=%s actual=%s" % [
			message,
			error_code,
			String(result.get("error_code", "")),
		]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P7.1] %s" % message)
